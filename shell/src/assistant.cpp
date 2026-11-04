#include "assistant.h"

#include <QClipboard>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QMimeData>
#include <QDir>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>

static const QString kService = QStringLiteral("org.aster.Assistant");
static const QString kPath = QStringLiteral("/org/aster/Assistant");
static const QString kIface = QStringLiteral("org.aster.Assistant");

// ——— Model wiadomości ———

QVariant AssistantMessages::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Message &m = m_items.at(index.row());
    switch (role) {
    case RoleRole: return m.role;
    case TextRole: return m.text;
    case BadgeRole: return m.badge;
    case ErrorRole: return m.error;
    case PendingRole: return m.pending;
    case CommandRole: return m.command;
    case StateRole: return m.state;
    case OutputRole: return m.output;
    }
    return {};
}

QHash<int, QByteArray> AssistantMessages::roleNames() const
{
    return {{RoleRole, "role"}, {TextRole, "text"}, {BadgeRole, "badge"}, {ErrorRole, "error"}, {PendingRole, "pending"},
            {CommandRole, "command"}, {StateRole, "phase"}, {OutputRole, "output"}};
}

void AssistantMessages::reset(const QList<Message> &items)
{
    beginResetModel();
    m_items = items;
    endResetModel();
}

void AssistantMessages::append(const Message &m)
{
    beginInsertRows({}, int(m_items.size()), int(m_items.size()));
    m_items.append(m);
    endInsertRows();
}

void AssistantMessages::lastChanged()
{
    if (m_items.isEmpty())
        return;
    const QModelIndex i = index(int(m_items.size()) - 1);
    Q_EMIT dataChanged(i, i);
}

void AssistantMessages::changedAt(int i)
{
    const QModelIndex x = index(i);
    Q_EMIT dataChanged(x, x);
}

void AssistantMessages::removeLast()
{
    if (m_items.isEmpty())
        return;
    beginRemoveRows({}, int(m_items.size()) - 1, int(m_items.size()) - 1);
    m_items.removeLast();
    endRemoveRows();
}

// ——— Skrót globalny (kglobalaccel przez D-Bus, bez biblioteki KF6GlobalAccel) ———

namespace {
// Sekwencja klawiszy na szynie: „(ai)”
struct KeySeq {
    QList<int> keys;
};
}
Q_DECLARE_METATYPE(KeySeq)
static QDBusArgument &operator<<(QDBusArgument &a, const KeySeq &s)
{
    a.beginStructure();
    a << s.keys;
    a.endStructure();
    return a;
}
static const QDBusArgument &operator>>(const QDBusArgument &a, KeySeq &s)
{
    a.beginStructure();
    a >> s.keys;
    a.endStructure();
    return a;
}

static const QString kAccel = QStringLiteral("org.kde.kglobalaccel");
static const QStringList kShortcutId{QStringLiteral("aster-shell"), QStringLiteral("assistant"), QStringLiteral("Powłoka Aster"),
                                     QStringLiteral("Aster Intelligence")};

void Assistant::registerShortcut()
{
    qDBusRegisterMetaType<KeySeq>();
    qDBusRegisterMetaType<QList<KeySeq>>();
    QDBusConnection bus = QDBusConnection::sessionBus();
    auto accel = [](const QString &method, const QVariantList &args) {
        QDBusMessage m = QDBusMessage::createMethodCall(kAccel, QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), method);
        m.setArguments(args);
        QDBusConnection::sessionBus().asyncCall(m);
    };
    const QList<KeySeq> keys{KeySeq{{QKeyCombination(Qt::META, Qt::Key_Space).toCombined()}}};
    accel(QStringLiteral("doRegister"), {kShortcutId});
    // SetPresent (2): skrót aktywny, a jeśli ktoś go zmienił w Ustawieniach — zostaje jego wybór; IsDefault (8): domyślny
    accel(QStringLiteral("setShortcutKeys"), {kShortcutId, QVariant::fromValue(keys), 2u});
    accel(QStringLiteral("setShortcutKeys"), {kShortcutId, QVariant::fromValue(keys), 2u | 8u});
    const bool ok = bus.connect(kAccel, QStringLiteral("/component/aster_shell"), QStringLiteral("org.kde.kglobalaccel.Component"),
                                QStringLiteral("globalShortcutPressed"), this, SLOT(onShortcut(QString, QString, qlonglong)));
    qInfo("asystent: skrót Meta+Space zarejestrowany, nasłuch %s", ok ? "działa" : "NIE działa");
}

void Assistant::onShortcut(const QString &component, const QString &action, qlonglong)
{
    if (component == kShortcutId.at(0) && action == kShortcutId.at(1))
        Q_EMIT toggleRequested();
}

// ——— Usługa ———

static QDBusMessage method(const QString &name, const QVariantList &args = {})
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kIface, name);
    m.setArguments(args);
    return m;
}

Assistant::Assistant(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kIface, QStringLiteral("Chunk"), this, SLOT(onChunk(QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("Finished"), this, SLOT(onFinished(QString, QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("Failed"), this, SLOT(onFailed(QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("StatusChanged"), this, SLOT(refreshStatus()));
    bus.connect(kService, kPath, kIface, QStringLiteral("ActionRequested"), this,
                SLOT(onActionRequested(QString, QString, QString, QString, bool)));
    bus.connect(kService, kPath, kIface, QStringLiteral("ShowConversation"), this, SLOT(onShowConversation(QString, QString)));
    if (!qEnvironmentVariableIsSet("ASTER_PREVIEW"))
        registerShortcut();
    QClipboard *cb = QGuiApplication::clipboard();
    connect(cb, &QClipboard::selectionChanged, this, &Assistant::refreshSelection);
    connect(cb, &QClipboard::dataChanged, this, &Assistant::refreshSelection);
}

// Zaznaczony tekst (podstawowe zaznaczenie Waylanda) albo — gdy nic nie zaznaczono — tekst ze schowka.
// Wayland podaje zaznaczenie tylko oknu z klawiaturą, więc wyspa czyta je po otwarciu pola pytania.
void Assistant::refreshSelection()
{
    QString text, source;
    if (const QString fake = qEnvironmentVariable("ASTER_SHOT_SELECTION"); !fake.isEmpty()) {
        text = fake;
        source = QStringLiteral("zaznaczenie");
    } else {
        QClipboard *cb = QGuiApplication::clipboard();
        // Hasła skopiowane z menedżera haseł (KeePassXC, Bitwarden…) nie trafiają do podpowiedzi
        auto secret = [](const QMimeData *d) {
            return d && d->data(QStringLiteral("x-kde-passwordManagerHint")) == "secret";
        };
        if (cb->supportsSelection() && !secret(cb->mimeData(QClipboard::Selection)))
            text = cb->text(QClipboard::Selection).trimmed();
        source = QStringLiteral("zaznaczenie");
        if (text.isEmpty() && !secret(cb->mimeData(QClipboard::Clipboard))) {
            text = cb->text(QClipboard::Clipboard).trimmed();
            source = QStringLiteral("schowek");
        }
    }
    // Pojedyncze słowo albo adres to nie tekst do przeredagowania
    if (text.size() < 12 || !text.contains(QLatin1Char(' ')))
        text.clear();
    if (text.isEmpty())
        source.clear();
    if (text == m_selection && source == m_selectionSource)
        return;
    m_selection = text;
    m_selectionSource = source;
    Q_EMIT selectionChanged();
}

QString Assistant::title() const
{
    for (const auto &m : m_messages.items())
        if (m.role == QLatin1String("user"))
            return m.text.simplified();
    return {};
}

int Assistant::exchanges() const
{
    int n = 0;
    for (const auto &m : m_messages.items())
        n += m.role == QLatin1String("user");
    return n;
}

QString Assistant::lastAnswer() const
{
    const auto &items = m_messages.items();
    return !items.isEmpty() && items.last().role == QLatin1String("assistant") ? items.last().text : QString();
}

QString Assistant::lastBadge() const
{
    const auto &items = m_messages.items();
    return !items.isEmpty() ? items.last().badge : QString();
}

bool Assistant::acting() const
{
    for (const auto &m : m_messages.items())
        if (m.role == QLatin1String("action"))
            return true;
    return false;
}

bool Assistant::lastError() const
{
    const auto &items = m_messages.items();
    return !items.isEmpty() && items.last().error;
}

void Assistant::refreshStatus()
{
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("Status")), 5000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w] {
        const QDBusMessage r = w->reply();
        w->deleteLater();
        m_available = r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty();
        if (m_available)
            m_status = qdbus_cast<QVariantMap>(r.arguments().first());
        Q_EMIT statusChanged();
    });
}

void Assistant::ask(const QString &text, const QString &source, const QString &context)
{
    const QString q = text.trimmed();
    if (q.isEmpty())
        return;
    // Znaczek z góry według bieżącego dostawcy — po odpowiedzi zastąpi go ten od usługi
    m_messages.append({QStringLiteral("user"), q, QString(), false, false});
    m_messages.append({QStringLiteral("assistant"), QString(), m_status.value(QStringLiteral("badge")).toString(), false, true});
    m_busy = true;
    Q_EMIT changed();
    auto *w = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("Ask"), {m_conversation, q, context, source}), 25000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w] {
        const QDBusMessage r = w->reply();
        w->deleteLater();
        if (r.type() != QDBusMessage::ReplyMessage) {
            onFailed(m_conversation, QStringLiteral("Usługa asystenta nie odpowiada (%1)").arg(r.errorMessage()));
            return;
        }
        m_conversation = r.arguments().value(0).toString();
        Q_EMIT changed();
    });
    if (m_status.isEmpty())
        refreshStatus();
}

void Assistant::cancel()
{
    if (!m_busy)
        return;
    QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("Cancel"), {m_conversation}));
    if (const int w = waitingAction(); w >= 0) {
        m_messages.at(w).state = QStringLiteral("odmowa");
        m_messages.changedAt(w);
    }
    if (!m_messages.isEmpty() && m_messages.last().pending) {
        m_messages.last().pending = false;
        if (m_messages.last().text.isEmpty())
            m_messages.last().text = QStringLiteral("(przerwano)");
        m_messages.lastChanged();
    }
    m_busy = false;
    Q_EMIT changed();
}

void Assistant::newConversation()
{
    cancel();
    m_conversation.clear();
    m_messages.reset({});
    Q_EMIT changed();
}

void Assistant::openConversation(const QString &id)
{
    cancel();
    const QDBusMessage r = QDBusConnection::sessionBus().call(method(QStringLiteral("Conversation"), {id}), QDBus::Block, 3000);
    if (r.type() != QDBusMessage::ReplyMessage)
        return;
    const QJsonObject o = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).object();
    QList<AssistantMessages::Message> items;
    for (const QJsonValue &v : o.value(QStringLiteral("messages")).toArray()) {
        const QJsonObject m = v.toObject();
        const QString role = m.value(QStringLiteral("role")).toString();
        if (role == QLatin1String("action")) {
            const int code = m.value(QStringLiteral("exit")).toInt();
            items.append({role, m.value(QStringLiteral("description")).toString(), QString(), false, false,
                          m.value(QStringLiteral("command")).toString(),
                          code == -2 ? QStringLiteral("odmowa") : code == 0 ? QStringLiteral("gotowe") : QStringLiteral("blad"),
                          m.value(QStringLiteral("text")).toString(), QString()});
            continue;
        }
        QString text = m.value(QStringLiteral("text")).toString();
        items.append({role, text, m.value(QStringLiteral("badge")).toString(), false, false});
    }
    m_conversation = id;
    m_messages.reset(items);
    Q_EMIT changed();
}

// Agent znalazł wcześniejszą rozmowę: panel przechodzi do niej (bieżąca zostaje w historii)
void Assistant::onShowConversation(const QString &conversation, const QString &target)
{
    if (conversation != m_conversation || target.isEmpty() || m_busy)
        return;
    openConversation(target);
    Q_EMIT conversationShown();
}

void Assistant::deleteConversation(const QString &id)
{
    QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("DeleteConversation"), {id}));
    if (id == m_conversation)
        newConversation();
}

QVariantList Assistant::history() const
{
    const QDBusMessage r = QDBusConnection::sessionBus().call(method(QStringLiteral("Conversations")), QDBus::Block, 3000);
    if (r.type() != QDBusMessage::ReplyMessage)
        return {};
    return QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array().toVariantList();
}

void Assistant::copy(const QString &text) const
{
    QGuiApplication::clipboard()->setText(text);
}

void Assistant::openSettings() const
{
    QProcess::startDetached(QStringLiteral("aster-settings"), {QStringLiteral("assistant")});
}

void Assistant::onChunk(const QString &conversation, const QString &text)
{
    if (conversation != m_conversation || m_messages.isEmpty() || !m_busy)
        return;
    if (!m_messages.last().pending)
        m_messages.append({QStringLiteral("assistant"), QString(), m_status.value(QStringLiteral("badge")).toString(), false, true});
    m_messages.last().text += text;
    m_messages.lastChanged();
    Q_EMIT changed();
}

void Assistant::onFinished(const QString &conversation, const QString &text, const QString &badge)
{
    if (conversation != m_conversation || m_messages.isEmpty() || !m_busy)
        return;
    if (!m_messages.last().pending)
        m_messages.append({QStringLiteral("assistant"), QString(), badge, false, true});
    auto &m = m_messages.last();
    m.text = text;
    m.badge = badge;
    m.pending = false;
    m_messages.lastChanged();
    m_busy = false;
    Q_EMIT changed();
    Q_EMIT answered();
}

void Assistant::onFailed(const QString &conversation, const QString &message)
{
    if (conversation != m_conversation || m_messages.isEmpty() || !m_busy)
        return;
    if (!m_messages.last().pending)
        m_messages.append({QStringLiteral("assistant"), QString(), QString(), false, true});
    auto &m = m_messages.last();
    m.text = message;
    m.error = true;
    m.pending = false;
    m.badge.clear();
    m_messages.lastChanged();
    m_busy = false;
    Q_EMIT changed();
    Q_EMIT answered();
}

// ——— Agent: polecenia ———

int Assistant::waitingAction() const
{
    const auto &items = m_messages.items();
    for (int i = int(items.size()) - 1; i >= 0; --i)
        if (items.at(i).role == QLatin1String("action") && items.at(i).state == QLatin1String("czeka"))
            return i;
    return -1;
}

void Assistant::onActionRequested(const QString &conversation, const QString &action, const QString &command,
                                  const QString &description, bool safe)
{
    if (conversation != m_conversation || m_messages.isEmpty())
        return;
    // Tekst odpowiedzi bez bloku z poleceniem i bez zdania-opisu (oba są na karcie działania)
    if (m_messages.last().pending) {
        QString t = m_messages.last().text;
        static const QRegularExpression block(QStringLiteral("```(?:bash|sh|shell|zsh|console)[ \\t]*\\n[\\s\\S]*?(```|$)"));
        t.remove(block);
        t = t.trimmed();
        // ostatni wiersz to zwykle zdanie-opis — jest już na karcie
        const int nl = t.lastIndexOf(QLatin1Char('\n'));
        const QString lastLine = t.mid(nl + 1).remove(QRegularExpression(QStringLiteral("[*_`#>]"))).trimmed();
        if (!description.isEmpty() && (lastLine == description || lastLine.startsWith(description.left(24))))
            t = nl < 0 ? QString() : t.left(nl).trimmed();
        if (t.endsWith(QLatin1Char(':')))
            t.chop(1);
        if (t.isEmpty()) {
            m_messages.removeLast();
        } else {
            m_messages.last().text = t;
            m_messages.last().badge.clear();     // znaczek dostaje dopiero końcowa odpowiedź
            m_messages.last().pending = false;
            m_messages.lastChanged();
        }
    }
    AssistantMessages::Message m{QStringLiteral("action"), description, QString(), false, false, command,
                                 safe ? QStringLiteral("dziala") : QStringLiteral("czeka"), QString(), action};
    m_messages.append(m);
    Q_EMIT changed();
    if (safe)
        runAction(int(m_messages.rowCount()) - 1);
}

void Assistant::approve(bool yes)
{
    const int i = waitingAction();
    if (i < 0)
        return;
    if (yes) {
        runAction(i);
    } else {
        m_messages.at(i).state = QStringLiteral("odmowa");
        m_messages.changedAt(i);
        sendResult(i, -2, QString());
    }
}

// Programy z oknem (aster-files, aster-settings…) startują osobno — agent dostaje tylko „uruchomiono”.
// sudo nie ma tu terminala na hasło: zamieniane na pkexec (okno hasła powłoki).
void Assistant::runAction(int index)
{
    auto &m = m_messages.at(index);
    m.state = QStringLiteral("dziala");
    m_messages.changedAt(index);
    Q_EMIT changed();
    QString cmd = m.command;
    cmd.replace(QRegularExpression(QStringLiteral("(^|[;&|]\\s*)sudo\\s+")), QStringLiteral("\\1pkexec "));
    const QString first = cmd.section(QLatin1Char(' '), 0, 0);
    static const QStringList cli{QStringLiteral("aster-assistant"), QStringLiteral("aster-firstboot")};
    if (first.startsWith(QLatin1String("aster-")) && !cli.contains(first) && !cmd.contains(QLatin1Char('|'))) {
        const bool ok = QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), cmd}, QDir::homePath());
        sendResult(index, ok ? 0 : 127, ok ? QStringLiteral("Program uruchomiony (okno otwiera się na ekranie).")
                                           : QStringLiteral("Nie udało się uruchomić programu."));
        return;
    }
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    p->setWorkingDirectory(QDir::homePath());
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C.UTF-8"));   // przewidywalne komunikaty dla modelu
    env.insert(QStringLiteral("PAGER"), QStringLiteral("cat"));
    env.insert(QStringLiteral("SYSTEMD_PAGER"), QString());
    env.insert(QStringLiteral("ASTER_AGENT"), QStringLiteral("1"));   // `aster --historia` wie, że czyta agent
    p->setProcessEnvironment(env);
    const QString id = m.actionId;
    auto *timeout = new QTimer(p);
    timeout->setSingleShot(true);
    connect(timeout, &QTimer::timeout, p, [p] { p->kill(); });
    // Instalacja programu może pobierać setki MB — dostaje pół godziny, reszta 3 minuty
    const bool long_ = cmd.contains(QLatin1String("flatpak install")) || cmd.contains(QLatin1String("aster --instaluj"))
                    || cmd.contains(QLatin1String("flatpak update")) || cmd.contains(QLatin1String("bootc upgrade"));
    connect(p, &QProcess::finished, this, [this, p, id](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        const auto &items = m_messages.items();
        for (int i = 0; i < items.size(); ++i)
            if (items.at(i).actionId == id) {
                QString out = QString::fromUtf8(p->readAll());
                if (st != QProcess::NormalExit)
                    out += QStringLiteral("\n(polecenie przerwane — trwało za długo)");
                sendResult(i, st == QProcess::NormalExit ? code : 124, out);
                return;
            }
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, id](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        p->deleteLater();
        const auto &items = m_messages.items();
        for (int i = 0; i < items.size(); ++i)
            if (items.at(i).actionId == id)
                sendResult(i, 127, QStringLiteral("Nie udało się uruchomić powłoki bash."));
    });
    p->start(QStringLiteral("bash"), {QStringLiteral("-lc"), cmd}, QIODevice::ReadOnly);
    p->closeWriteChannel();
    timeout->start(long_ ? 30 * 60 * 1000 : 180000);
}

void Assistant::sendResult(int index, int exitCode, const QString &output)
{
    auto &m = m_messages.at(index);
    if (exitCode != -2) {
        m.state = exitCode == 0 ? QStringLiteral("gotowe") : QStringLiteral("blad");
        m.output = output.trimmed();
    }
    m_messages.changedAt(index);
    QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("ActionResult"), {m_conversation, m.actionId, exitCode, output}));
    // Model myśli nad wynikiem — miejsce na jego następną odpowiedź
    m_messages.append({QStringLiteral("assistant"), QString(), m_status.value(QStringLiteral("badge")).toString(), false, true});
    Q_EMIT changed();
}

void Assistant::openInTerminal(const QString &command) const
{
    QProcess::startDetached(QStringLiteral("aster-terminal"), {QStringLiteral("--wpisz"), command});
}

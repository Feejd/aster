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
#include <QProcess>

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
    }
    return {};
}

QHash<int, QByteArray> AssistantMessages::roleNames() const
{
    return {{RoleRole, "role"}, {TextRole, "text"}, {BadgeRole, "badge"}, {ErrorRole, "error"}, {PendingRole, "pending"}};
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
                                     QStringLiteral("Asystent Aster")};

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
    if (!qEnvironmentVariableIsSet("ASTER_PREVIEW"))
        registerShortcut();
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

void Assistant::ask(const QString &text, const QString &source)
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
        QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("Ask"), {m_conversation, q, QString(), source}), 25000), this);
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
        items.append({m.value(QStringLiteral("role")).toString(), m.value(QStringLiteral("text")).toString(),
                      m.value(QStringLiteral("badge")).toString(), false, false});
    }
    m_conversation = id;
    m_messages.reset(items);
    Q_EMIT changed();
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
    if (conversation != m_conversation || m_messages.isEmpty() || !m_messages.last().pending)
        return;
    m_messages.last().text += text;
    m_messages.lastChanged();
    Q_EMIT changed();
}

void Assistant::onFinished(const QString &conversation, const QString &text, const QString &badge)
{
    if (conversation != m_conversation || m_messages.isEmpty() || !m_messages.last().pending)
        return;
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
    if (conversation != m_conversation || m_messages.isEmpty() || !m_messages.last().pending)
        return;
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

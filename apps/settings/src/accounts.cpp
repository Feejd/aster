#include "accounts.h"

#include "util.h"

#include <QDBusObjectPath>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QRandomGenerator>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QUrl>

#include <crypt.h>
#include <unistd.h>

static const QString acc = QStringLiteral("org.freedesktop.Accounts");
static const QString accPath = QStringLiteral("/org/freedesktop/Accounts");
static const QString userIface = QStringLiteral("org.freedesktop.Accounts.User");

Accounts::Accounts(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    m_hostName = QSysInfo::machineHostName();
    if (m_preview) {
        m_realName = QStringLiteral("Dominik Nowak");
        m_userName = QStringLiteral("dominik");
        m_admin = true;
        m_others = {QVariantMap{{QStringLiteral("uid"), 1001}, {QStringLiteral("userName"), QStringLiteral("ola")}, {QStringLiteral("realName"), QStringLiteral("Ola Nowak")},
                                {QStringLiteral("iconUrl"), QString()}, {QStringLiteral("admin"), false}}};
        m_hostName = QStringLiteral("laptop-dominika");
        return;
    }
    refresh();
}

void Accounts::refresh()
{
    if (m_preview)
        return;
    dbusCall(this, dbusMethod(acc, accPath, acc, QStringLiteral("FindUserById"), {qlonglong(getuid())}), true, false, [this](const QDBusMessage &r) {
        if (r.type() != QDBusMessage::ReplyMessage)
            return;
        m_path = qvariant_cast<QDBusObjectPath>(r.arguments().value(0)).path();
        readUser(m_path, true);
    });
    dbusCall(this, dbusMethod(acc, accPath, acc, QStringLiteral("ListCachedUsers")), true, false, [this](const QDBusMessage &r) {
        m_others.clear();
        Q_EMIT changed();
        if (r.type() != QDBusMessage::ReplyMessage)
            return;
        QList<QDBusObjectPath> paths;
        qvariant_cast<QDBusArgument>(r.arguments().value(0)) >> paths;
        for (const QDBusObjectPath &p : paths)
            readUser(p.path(), false);
    });
}

void Accounts::readUser(const QString &path, bool self)
{
    dbusGetAll(this, acc, path, userIface, true, [this, self](const QVariantMap &p) {
        if (p.isEmpty())
            return;
        const QString icon = p.value(QStringLiteral("IconFile")).toString();
        const QString iconUrl = QFileInfo(icon).isFile() && QFileInfo(icon).size() > 0 ? QUrl::fromLocalFile(icon).toString() : QString();
        const bool admin = p.value(QStringLiteral("AccountType")).toInt() == 1;
        const qlonglong uid = p.value(QStringLiteral("Uid")).toLongLong();
        if (self) {
            m_realName = p.value(QStringLiteral("RealName")).toString();
            m_userName = p.value(QStringLiteral("UserName")).toString();
            m_iconUrl = iconUrl;
            m_admin = admin;
        } else if (uid != qlonglong(getuid()) && !p.value(QStringLiteral("SystemAccount")).toBool()) {
            m_others << QVariantMap{{QStringLiteral("uid"), uid}, {QStringLiteral("userName"), p.value(QStringLiteral("UserName"))},
                                    {QStringLiteral("realName"), p.value(QStringLiteral("RealName"))}, {QStringLiteral("iconUrl"), iconUrl},
                                    {QStringLiteral("admin"), admin}};
        }
        Q_EMIT changed();
    });
}

void Accounts::callUser(const QString &path, const QString &method, const QVariantList &args, const QString &ok, const QString &fail)
{
    if (m_preview) {
        Q_EMIT message(QStringLiteral("W podglądzie nic się nie zmienia"));
        return;
    }
    m_busy = true;
    Q_EMIT changed();
    dbusCall(this, dbusMethod(acc, path, userIface, method, args), true, true, [this, ok, fail](const QDBusMessage &r) {
        m_busy = false;
        Q_EMIT message(r.type() == QDBusMessage::ReplyMessage ? ok : fail);
        refresh();
    });
}

void Accounts::setRealName(const QString &name)
{
    const QString n = name.simplified();
    if (n.isEmpty() || n == m_realName)
        return;
    m_realName = n;
    Q_EMIT changed();
    callUser(m_path, QStringLiteral("SetRealName"), {n}, QStringLiteral("Zmieniono imię"), QStringLiteral("Nie udało się zmienić imienia"));
}

void Accounts::setIcon(const QString &fileUrl)
{
    // Zdjęcie przycięte do kwadratu 256×256 — AccountsService i tak je kopiuje
    const QString file = QUrl(fileUrl).isLocalFile() ? QUrl(fileUrl).toLocalFile() : fileUrl;
    QImage img(file);
    if (img.isNull()) {
        Q_EMIT message(QStringLiteral("Tego pliku nie da się użyć jako zdjęcia"));
        return;
    }
    const int side = qMin(img.width(), img.height());
    img = img.copy((img.width() - side) / 2, (img.height() - side) / 2, side, side).scaled(256, 256, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    static QTemporaryDir dir;
    const QString out = dir.filePath(QStringLiteral("avatar.png"));
    img.save(out);
    m_iconUrl = QUrl::fromLocalFile(out).toString() + QStringLiteral("?") + QString::number(QRandomGenerator::global()->generate());
    Q_EMIT changed();
    callUser(m_path, QStringLiteral("SetIconFile"), {out}, QStringLiteral("Zmieniono zdjęcie"), QStringLiteral("Nie udało się zmienić zdjęcia"));
}

QString Accounts::hashPassword(const QString &password)
{
    // Domyślny algorytm systemu (w Fedorze yescrypt, „$y$”)
    char *salt = crypt_gensalt_ra(nullptr, 0, nullptr, 0);
    if (!salt)
        return QString();
    struct crypt_data data = {};
    const char *hash = crypt_r(password.toUtf8().constData(), salt, &data);
    free(salt);
    return hash && hash[0] != '*' ? QString::fromLatin1(hash) : QString();
}

void Accounts::setPassword(const QString &password)
{
    if (password.size() < 1)
        return;
    const QString hash = hashPassword(password);
    if (hash.isEmpty()) {
        Q_EMIT message(QStringLiteral("Nie udało się przygotować hasła"));
        return;
    }
    callUser(m_path, QStringLiteral("SetPassword"), {hash, QString()}, QStringLiteral("Zmieniono hasło"), QStringLiteral("Hasło nie zostało zmienione"));
}

QString Accounts::suggestUserName(const QString &realName) const
{
    // Pierwsze słowo, bez polskich znaków, małymi literami
    static const QHash<QChar, QChar> pl{{u'ą', u'a'}, {u'ć', u'c'}, {u'ę', u'e'}, {u'ł', u'l'}, {u'ń', u'n'}, {u'ó', u'o'}, {u'ś', u's'}, {u'ź', u'z'}, {u'ż', u'z'}};
    QString out;
    for (const QChar c : realName.trimmed().section(QLatin1Char(' '), 0, 0).toLower())
        if (c.isLetterOrNumber())
            out += pl.value(c, c.unicode() < 128 ? c : QChar());
    out.remove(QChar());
    return out.left(31);
}

void Accounts::createUser(const QString &userName, const QString &realName, bool admin, const QString &password)
{
    if (m_preview) {
        Q_EMIT message(QStringLiteral("W podglądzie nic się nie zmienia"));
        return;
    }
    m_busy = true;
    Q_EMIT changed();
    dbusCall(this, dbusMethod(acc, accPath, acc, QStringLiteral("CreateUser"), {userName, realName, admin ? 1 : 0}), true, true,
             [this, password, userName](const QDBusMessage &r) {
                 m_busy = false;
                 if (r.type() != QDBusMessage::ReplyMessage) {
                     Q_EMIT message(QStringLiteral("Nie udało się dodać konta „%1”").arg(userName));
                     Q_EMIT changed();
                     return;
                 }
                 const QString path = qvariant_cast<QDBusObjectPath>(r.arguments().value(0)).path();
                 callUser(path, QStringLiteral("SetPassword"), {hashPassword(password), QString()}, QStringLiteral("Dodano konto „%1”").arg(userName),
                          QStringLiteral("Konto dodane, ale hasło nie zostało ustawione"));
             });
}

void Accounts::deleteUser(qlonglong uid, bool removeFiles)
{
    if (m_preview) {
        Q_EMIT message(QStringLiteral("W podglądzie nic się nie zmienia"));
        return;
    }
    dbusCall(this, dbusMethod(acc, accPath, acc, QStringLiteral("DeleteUser"), {uid, removeFiles}), true, true, [this](const QDBusMessage &r) {
        Q_EMIT message(r.type() == QDBusMessage::ReplyMessage ? QStringLiteral("Usunięto konto") : QStringLiteral("Nie udało się usunąć konta"));
        refresh();
    });
}

void Accounts::setHostName(const QString &name)
{
    // „Laptop Dominika” → ładna nazwa jak wpisana, a nazwa sieciowa „laptop-dominika”
    const QString pretty = name.simplified();
    const QString host = pretty.toLower();
    static const QHash<QChar, QChar> pl{{u'ą', u'a'}, {u'ć', u'c'}, {u'ę', u'e'}, {u'ł', u'l'}, {u'ń', u'n'}, {u'ó', u'o'}, {u'ś', u's'}, {u'ź', u'z'}, {u'ż', u'z'}};
    QString net;
    for (const QChar c : host) {
        const QChar d = pl.value(c, c);
        if (d.isLetterOrNumber() && d.unicode() < 128)
            net += d;
        else if (!net.endsWith(QLatin1Char('-')))
            net += QLatin1Char('-');
    }
    while (net.endsWith(QLatin1Char('-')))
        net.chop(1);
    if (net.isEmpty())
        return;
    m_hostName = net;
    Q_EMIT changed();
    if (m_preview)
        return;
    const QString h = QStringLiteral("org.freedesktop.hostname1"), hp = QStringLiteral("/org/freedesktop/hostname1");
    dbusCall(this, dbusMethod(h, hp, h, QStringLiteral("SetPrettyHostname"), {pretty, true}), true, true);
    dbusCall(this, dbusMethod(h, hp, h, QStringLiteral("SetStaticHostname"), {net.left(63), true}), true, true, [this](const QDBusMessage &r) {
        Q_EMIT message(r.type() == QDBusMessage::ReplyMessage ? QStringLiteral("Zmieniono nazwę komputera") : QStringLiteral("Nie udało się zmienić nazwy komputera"));
    });
}

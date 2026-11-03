#include "secrets.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QEventLoop>
#include <QTimer>

// Secret Service API: https://specifications.freedesktop.org/secret-service-spec/latest/
// Sesja „plain” — klucz idzie szyną sesji użytkownika bez dodatkowego szyfrowania (szyna jest prywatna).
namespace {

const QString kService = QStringLiteral("org.freedesktop.secrets");
const QString kPath = QStringLiteral("/org/freedesktop/secrets");
const QString kIfService = QStringLiteral("org.freedesktop.Secret.Service");
const QString kIfCollection = QStringLiteral("org.freedesktop.Secret.Collection");
const QString kIfItem = QStringLiteral("org.freedesktop.Secret.Item");
const QString kIfPrompt = QStringLiteral("org.freedesktop.Secret.Prompt");

using StringMap = QMap<QString, QString>;

struct Secret {
    QDBusObjectPath session;
    QByteArray parameters;
    QByteArray value;
    QString contentType;
};

} // namespace

Q_DECLARE_METATYPE(Secret)

static QDBusArgument &operator<<(QDBusArgument &a, const Secret &s)
{
    a.beginStructure();
    a << s.session << s.parameters << s.value << s.contentType;
    a.endStructure();
    return a;
}
static const QDBusArgument &operator>>(const QDBusArgument &a, Secret &s)
{
    a.beginStructure();
    a >> s.session >> s.parameters >> s.value >> s.contentType;
    a.endStructure();
    return a;
}

namespace {

void registerTypes()
{
    static bool done = false;
    if (done)
        return;
    done = true;
    qDBusRegisterMetaType<Secret>();
    qDBusRegisterMetaType<StringMap>();
}

QDBusMessage call(const QString &path, const QString &iface, const QString &method, const QVariantList &args, QString *error)
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, path, iface, method);
    m.setArguments(args);
    QDBusMessage r = QDBusConnection::sessionBus().call(m, QDBus::Block, 15000);
    if (r.type() == QDBusMessage::ErrorMessage && error) {
        if (r.errorName() == QLatin1String("org.freedesktop.DBus.Error.ServiceUnknown"))
            *error = QStringLiteral("Brak portfela systemu (Secret Service / KWallet)");
        else
            *error = QStringLiteral("Portfel: %1").arg(r.errorMessage());
    }
    return r;
}

// Okienko portfela (odblokowanie, nowa kolekcja). Zwraca false, gdy użytkownik je zamknął.
class PromptWaiter : public QObject
{
    Q_OBJECT
public:
    QEventLoop loop;
    bool dismissed = true;
public Q_SLOTS:
    void completed(bool d, const QDBusVariant &)
    {
        dismissed = d;
        loop.quit();
    }
};

bool runPrompt(const QDBusObjectPath &prompt, QString *error)
{
    if (prompt.path().isEmpty() || prompt.path() == QLatin1String("/"))
        return true;
    PromptWaiter w;
    QDBusConnection::sessionBus().connect(kService, prompt.path(), kIfPrompt, QStringLiteral("Completed"), &w,
                                          SLOT(completed(bool, QDBusVariant)));
    call(prompt.path(), kIfPrompt, QStringLiteral("Prompt"), {QString()}, error);
    QTimer::singleShot(120000, &w.loop, &QEventLoop::quit);
    w.loop.exec();
    if (w.dismissed && error)
        *error = QStringLiteral("Portfel pozostał zamknięty");
    return !w.dismissed;
}

bool unlock(const QList<QDBusObjectPath> &objects, QString *error)
{
    if (objects.isEmpty())
        return true;
    const QDBusMessage r = call(kPath, kIfService, QStringLiteral("Unlock"), {QVariant::fromValue(objects)}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return false;
    return runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(1)), error);
}

QDBusObjectPath openSession(QString *error)
{
    const QDBusMessage r = call(kPath, kIfService, QStringLiteral("OpenSession"),
                                {QStringLiteral("plain"), QVariant::fromValue(QDBusVariant(QString()))}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return {};
    return qdbus_cast<QDBusObjectPath>(r.arguments().at(1));
}

StringMap attributes(const QString &provider)
{
    return {{QStringLiteral("application"), QStringLiteral("aster-assistant")}, {QStringLiteral("provider"), provider}};
}

// Wpisy dostawcy (najpierw odblokowuje zablokowane)
QList<QDBusObjectPath> findItems(const QString &provider, QString *error)
{
    const QDBusMessage r = call(kPath, kIfService, QStringLiteral("SearchItems"), {QVariant::fromValue(attributes(provider))}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return {};
    QList<QDBusObjectPath> items = qdbus_cast<QList<QDBusObjectPath>>(r.arguments().at(0));
    const QList<QDBusObjectPath> locked = qdbus_cast<QList<QDBusObjectPath>>(r.arguments().at(1));
    if (!locked.isEmpty() && unlock(locked, error))
        items += locked;
    return items;
}

QDBusObjectPath defaultCollection(QString *error)
{
    QDBusMessage r = call(kPath, kIfService, QStringLiteral("ReadAlias"), {QStringLiteral("default")}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return {};
    QDBusObjectPath c = qdbus_cast<QDBusObjectPath>(r.arguments().at(0));
    if (c.path() != QLatin1String("/"))
        return c;
    // Pierwszy klucz w systemie bez portfela: utwórz domyślny (portfel zapyta o hasło)
    QVariantMap props{{QStringLiteral("org.freedesktop.Secret.Collection.Label"), QStringLiteral("Domyślny")}};
    r = call(kPath, kIfService, QStringLiteral("CreateCollection"), {props, QStringLiteral("default")}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return {};
    c = qdbus_cast<QDBusObjectPath>(r.arguments().at(0));
    if (c.path() == QLatin1String("/")) {
        if (!runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(1)), error))
            return {};
        r = call(kPath, kIfService, QStringLiteral("ReadAlias"), {QStringLiteral("default")}, error);
        if (r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty())
            c = qdbus_cast<QDBusObjectPath>(r.arguments().at(0));
    }
    return c.path() == QLatin1String("/") ? QDBusObjectPath() : c;
}

} // namespace

QString Secrets::read(const QString &provider, QString *error)
{
    registerTypes();
    const QList<QDBusObjectPath> items = findItems(provider, error);
    if (items.isEmpty())
        return {};
    const QDBusObjectPath session = openSession(error);
    if (session.path().isEmpty())
        return {};
    const QDBusMessage r = call(items.first().path(), kIfItem, QStringLiteral("GetSecret"), {QVariant::fromValue(session)}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return {};
    const Secret s = qdbus_cast<Secret>(r.arguments().at(0));
    return QString::fromUtf8(s.value).trimmed();
}

bool Secrets::write(const QString &provider, const QString &label, const QString &key, QString *error)
{
    registerTypes();
    if (key.isEmpty()) {
        for (const QDBusObjectPath &item : findItems(provider, error)) {
            const QDBusMessage r = call(item.path(), kIfItem, QStringLiteral("Delete"), {}, error);
            if (r.type() != QDBusMessage::ReplyMessage)
                return false;
            if (!r.arguments().isEmpty() && !runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(0)), error))
                return false;
        }
        return true;
    }
    const QDBusObjectPath collection = defaultCollection(error);
    if (collection.path().isEmpty())
        return false;
    if (!unlock({collection}, error))
        return false;
    const QDBusObjectPath session = openSession(error);
    if (session.path().isEmpty())
        return false;
    QVariantMap props{{QStringLiteral("org.freedesktop.Secret.Item.Label"), QStringLiteral("Asystent Aster — klucz API %1").arg(label)},
                      {QStringLiteral("org.freedesktop.Secret.Item.Attributes"), QVariant::fromValue(attributes(provider))}};
    const Secret secret{session, {}, key.toUtf8(), QStringLiteral("text/plain")};
    const QDBusMessage r = call(collection.path(), kIfCollection, QStringLiteral("CreateItem"),
                                {props, QVariant::fromValue(secret), true}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return false;
    const QDBusObjectPath item = qdbus_cast<QDBusObjectPath>(r.arguments().at(0));
    if (item.path() == QLatin1String("/"))
        return runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(1)), error);
    return true;
}

#include "secrets.moc"

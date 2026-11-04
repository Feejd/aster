#include "secretstore.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QCoreApplication>
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

// Jeden wpis na projekt: wszystkie zmienne jako JSON { NAZWA: wartość }
StringMap attributes(const QString &root)
{
    return {{QStringLiteral("application"), QStringLiteral("aster-code")}, {QStringLiteral("project"), root}};
}

// Wpisy projektu (najpierw odblokowuje zablokowane)
QList<QDBusObjectPath> findItems(const QString &root, QString *error)
{
    const QDBusMessage r = call(kPath, kIfService, QStringLiteral("SearchItems"), {QVariant::fromValue(attributes(root))}, error);
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

// ——— Portfel: odczyt i zapis wpisu projektu ———

namespace {

QJsonObject readBlob(const QString &root, QString *error)
{
    registerTypes();
    const QList<QDBusObjectPath> items = findItems(root, error);
    if (items.isEmpty())
        return {};
    const QDBusObjectPath session = openSession(error);
    if (session.path().isEmpty())
        return {};
    const QDBusMessage r = call(items.first().path(), kIfItem, QStringLiteral("GetSecret"), {QVariant::fromValue(session)}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return {};
    return QJsonDocument::fromJson(qdbus_cast<Secret>(r.arguments().at(0)).value).object();
}

bool writeBlob(const QString &root, const QJsonObject &vars, QString *error)
{
    registerTypes();
    if (vars.isEmpty()) {
        for (const QDBusObjectPath &item : findItems(root, error)) {
            const QDBusMessage r = call(item.path(), kIfItem, QStringLiteral("Delete"), {}, error);
            if (r.type() != QDBusMessage::ReplyMessage)
                return false;
            if (!r.arguments().isEmpty() && !runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(0)), error))
                return false;
        }
        return true;
    }
    const QDBusObjectPath collection = defaultCollection(error);
    if (collection.path().isEmpty() || !unlock({collection}, error))
        return false;
    const QDBusObjectPath session = openSession(error);
    if (session.path().isEmpty())
        return false;
    QVariantMap props{{QStringLiteral("org.freedesktop.Secret.Item.Label"), QStringLiteral("Aster Code — sekrety projektu %1").arg(QFileInfo(root).fileName())},
                      {QStringLiteral("org.freedesktop.Secret.Item.Attributes"), QVariant::fromValue(attributes(root))}};
    const Secret secret{session, {}, QJsonDocument(vars).toJson(QJsonDocument::Compact), QStringLiteral("application/json")};
    // replace = true — ten sam wpis (te same atrybuty) jest nadpisywany
    const QDBusMessage r = call(collection.path(), kIfCollection, QStringLiteral("CreateItem"), {props, QVariant::fromValue(secret), true}, error);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().size() < 2)
        return false;
    const QDBusObjectPath item = qdbus_cast<QDBusObjectPath>(r.arguments().at(0));
    if (item.path() == QLatin1String("/"))
        return runPrompt(qdbus_cast<QDBusObjectPath>(r.arguments().at(1)), error);
    return true;
}

} // namespace

// ——— SecretStore ———

SecretStore *SecretStore::instance()
{
    static SecretStore *s = new SecretStore;
    return s;
}

SecretStore *SecretStore::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

SecretStore::SecretStore(QObject *parent)
    : QObject(parent)
{
}

void SecretStore::setRoot(const QString &r)
{
    if (r == m_root)
        return;
    m_root = r;
    m_vars.clear();
    m_loaded = false;
    m_error.clear();
    Q_EMIT changed();
}

void SecretStore::load() const
{
    if (m_loaded || m_root.isEmpty())
        return;
    m_loaded = true;
    QString err;
    const QJsonObject o = readBlob(m_root, &err);
    m_vars.clear();
    for (auto it = o.begin(); it != o.end(); ++it)
        m_vars.insert(it.key(), it.value().toString());
    m_error = err;
}

bool SecretStore::save()
{
    QJsonObject o;
    for (auto it = m_vars.cbegin(); it != m_vars.cend(); ++it)
        o.insert(it.key(), it.value());
    QString err;
    const bool ok = writeBlob(m_root, o, &err);
    m_error = ok ? QString() : (err.isEmpty() ? QStringLiteral("Nie udało się zapisać w portfelu") : err);
    Q_EMIT changed();
    return ok;
}

QStringList SecretStore::names() const
{
    load();
    QStringList n = m_vars.keys();
    std::sort(n.begin(), n.end());
    return n;
}

QString SecretStore::error() const
{
    load();
    return m_error;
}

bool SecretStore::set(const QString &name, const QString &value)
{
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z_][A-Za-z0-9_]*$"));
    if (!valid.match(name).hasMatch()) {
        m_error = QStringLiteral("Nazwa zmiennej: litery, cyfry i _, np. OPENAI_API_KEY");
        Q_EMIT changed();
        return false;
    }
    load();
    m_vars.insert(name, value);
    return save();
}

bool SecretStore::remove(const QString &name)
{
    load();
    m_vars.remove(name);
    return save();
}

QString SecretStore::reveal(const QString &name) const
{
    load();
    return m_vars.value(name);
}

QVariantMap SecretStore::env() const
{
    load();
    QVariantMap out;
    for (auto it = m_vars.cbegin(); it != m_vars.cend(); ++it)
        out.insert(it.key(), it.value());
    return out;
}

QString SecretStore::redact(const QString &text) const
{
    // Wartości sekretów (od 4 znaków) zamieniane na ••• — tekst idący do modelu nie zawiera ich nigdy
    load();
    QString t = text;
    for (const QString &v : std::as_const(m_vars))
        if (v.size() >= 4)
            t.replace(v, QStringLiteral("•••"));
    return t;
}

bool SecretStore::isSecretFile(const QString &path)
{
    const QString n = QFileInfo(path).fileName();
    return (n == QLatin1String(".env") || n.startsWith(QLatin1String(".env.")) || n.endsWith(QLatin1String(".pem"))
            || n.endsWith(QLatin1String(".key")) || n == QLatin1String("id_rsa") || n == QLatin1String("id_ed25519"))
        && !n.endsWith(QLatin1String(".example")) && !n.endsWith(QLatin1String(".sample")) && !n.endsWith(QLatin1String(".template"));
}

QVariantList SecretStore::envFiles() const
{
    QVariantList out;
    for (const QString &n : QDir(m_root).entryList({QStringLiteral(".env"), QStringLiteral(".env.*")}, QDir::Files | QDir::Hidden))
        if (isSecretFile(n))
            out << QVariantMap{{QStringLiteral("name"), n}, {QStringLiteral("path"), m_root + QLatin1Char('/') + n},
                               {QStringLiteral("count"), parseEnv(m_root + QLatin1Char('/') + n).size()}};
    return out;
}

QVariantMap SecretStore::parseEnv(const QString &path)
{
    QFile f(path);
    QVariantMap out;
    if (!f.open(QIODevice::ReadOnly))
        return out;
    static const QRegularExpression line(QStringLiteral("^\\s*(?:export\\s+)?([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.*?)\\s*$"));
    for (const QString &l : QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'))) {
        if (l.trimmed().startsWith(QLatin1Char('#')))
            continue;
        const auto m = line.match(l);
        if (!m.hasMatch())
            continue;
        QString v = m.captured(2);
        if (v.size() >= 2 && (v.startsWith(QLatin1Char('"')) && v.endsWith(QLatin1Char('"')) || v.startsWith(QLatin1Char('\'')) && v.endsWith(QLatin1Char('\''))))
            v = v.mid(1, v.size() - 2);
        else if (const int hash = int(v.indexOf(QLatin1String(" #"))); hash >= 0)
            v = v.left(hash).trimmed();
        out.insert(m.captured(1), v);
    }
    return out;
}

int SecretStore::importEnv(const QString &path, bool clearFile)
{
    // Zmienne z pliku .env do portfela; clearFile — w pliku zostają same nazwy (jak w .env.example)
    const QVariantMap vars = parseEnv(path);
    if (vars.isEmpty())
        return 0;
    load();
    for (auto it = vars.cbegin(); it != vars.cend(); ++it)
        m_vars.insert(it.key(), it.value().toString());
    if (!save())
        return -1;
    if (clearFile) {
        QFile f(path);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            QString t = QStringLiteral("# Wartości są w portfelu systemu (Aster Code → Sekrety projektu) i trafiają do programu przy uruchomieniu.\n");
            for (auto it = vars.cbegin(); it != vars.cend(); ++it)
                t += it.key() + QStringLiteral("=\n");
            f.write(t.toUtf8());
        }
    }
    return int(vars.size());
}

QString SecretStore::writeEnvFile() const
{
    // Plik dla powłoki w kontenerze / systemie: tylko dla właściciela, kasowany zaraz po wczytaniu
    load();
    if (m_vars.isEmpty())
        return {};
    QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (dir.isEmpty())
        return {};
    // We Flatpaku /run/user jest prywatne — wspólny z systemem (i kontenerem) jest tylko app/<id>
    if (const QString id = qEnvironmentVariable("FLATPAK_ID"); !id.isEmpty()) {
        dir += QStringLiteral("/app/") + id;
        QDir().mkpath(dir);
    }
    QString path;
    for (int i = 0; i < 100; ++i) {
        path = dir + QStringLiteral("/aster-code-env-%1-%2").arg(QCoreApplication::applicationPid()).arg(++m_fileSeq);
        if (!QFileInfo::exists(path))
            break;
    }
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::NewOnly))
        return {};
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QString t;
    for (auto it = m_vars.cbegin(); it != m_vars.cend(); ++it) {
        QString v = it.value();
        v.replace(QLatin1Char('\''), QLatin1String("'\\''"));
        t += QStringLiteral("export ") + it.key() + QStringLiteral("='") + v + QStringLiteral("'\n");
    }
    f.write(t.toUtf8());
    return path;
}

#include "secretstore.moc"

#include "workspace.h"
#include "secrets.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

namespace {

const QString kMeta = QStringLiteral("pulse.json");

bool readJson(const QString &path, QJsonObject *out, QString *error)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (error)
            *error = QStringLiteral("Nie można otworzyć %1").arg(path);
        return false;
    }
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &pe);
    if (!doc.isObject()) {
        if (error)
            *error = QStringLiteral("%1: błąd JSON (%2)").arg(QFileInfo(path).fileName(), pe.errorString());
        return false;
    }
    *out = doc.object();
    return true;
}

bool writeJson(const QString &path, const QJsonObject &obj, QString *error)
{
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        if (error)
            *error = QStringLiteral("Nie można zapisać %1").arg(path);
        return false;
    }
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return f.commit();
}

// Nazwa pliku z nazwy kolekcji: małe litery bez polskich znaków, myślniki
QString slug(const QString &name)
{
    static const QString from = QStringLiteral("ąćęłńóśźż");
    static const QString to = QStringLiteral("acelnoszz");
    QString s;
    for (QChar c : name.toLower()) {
        const int i = from.indexOf(c);
        if (i >= 0)
            c = to.at(i);
        if (c.isLetterOrNumber() && c.unicode() < 128)
            s += c;
        else if (!s.endsWith(QLatin1Char('-')))
            s += QLatin1Char('-');
    }
    while (s.startsWith(QLatin1Char('-')))
        s.remove(0, 1);
    while (s.endsWith(QLatin1Char('-')))
        s.chop(1);
    return s.isEmpty() ? QStringLiteral("kolekcja") : s;
}

QJsonObject kv(const QString &k, const QString &v, bool enabled = true)
{
    return {{QStringLiteral("key"), k}, {QStringLiteral("value"), v}, {QStringLiteral("enabled"), enabled}};
}

} // namespace

QJsonObject normalizedRequest(const QJsonObject &in)
{
    QJsonObject r = in;
    if (r.value(QLatin1String("id")).toString().isEmpty())
        r[QStringLiteral("id")] = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    if (r.value(QLatin1String("name")).toString().isEmpty())
        r[QStringLiteral("name")] = QStringLiteral("Nowe zapytanie");
    if (r.value(QLatin1String("method")).toString().isEmpty())
        r[QStringLiteral("method")] = QStringLiteral("GET");
    r[QStringLiteral("method")] = r.value(QLatin1String("method")).toString().toUpper();
    if (!r.contains(QLatin1String("url")))
        r[QStringLiteral("url")] = QString();
    for (const char *k : {"params", "headers"})
        if (!r.value(QLatin1String(k)).isArray())
            r[QLatin1String(k)] = QJsonArray();
    QJsonObject body = r.value(QLatin1String("body")).toObject();
    if (body.value(QLatin1String("mode")).toString().isEmpty())
        body[QStringLiteral("mode")] = QStringLiteral("none");
    if (!body.value(QLatin1String("form")).isArray())
        body[QStringLiteral("form")] = QJsonArray();
    r[QStringLiteral("body")] = body;
    QJsonObject auth = r.value(QLatin1String("auth")).toObject();
    if (auth.value(QLatin1String("type")).toString().isEmpty())
        auth[QStringLiteral("type")] = QStringLiteral("none");
    r[QStringLiteral("auth")] = auth;
    return r;
}

// ——— Obszar roboczy ———

QString Workspace::defaultDir()
{
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty())
        docs = QDir::homePath() + QStringLiteral("/Dokumenty");
    return docs + QStringLiteral("/Pulse");
}

QString Workspace::forFolder(const QString &folder)
{
    const QDir d(folder);
    if (QFileInfo::exists(d.filePath(kMeta)))
        return d.absolutePath();
    for (const char *sub : {"pulse", ".pulse"})
        if (QFileInfo::exists(d.filePath(QLatin1String(sub) + QLatin1Char('/') + kMeta)))
            return d.absoluteFilePath(QLatin1String(sub));
    // Folder z innymi plikami (projekt) → obszar w podfolderze pulse/; pusty folder — sam jest obszarem
    const bool empty = d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden).isEmpty();
    return empty ? d.absolutePath() : d.absoluteFilePath(QStringLiteral("pulse"));
}

QString Workspace::locate(const QString &explicitDir, const QString &startDir)
{
    if (!explicitDir.isEmpty())
        return forFolder(explicitDir);
    const QString env = qEnvironmentVariable("PULSE_DIR");
    if (!env.isEmpty())
        return forFolder(env);
    QDir d(startDir);
    for (int i = 0; i < 40; ++i) {
        for (const QString &cand : {QStringLiteral("pulse/") + kMeta, QStringLiteral(".pulse/") + kMeta, kMeta})
            if (QFileInfo::exists(d.filePath(cand)))
                return QFileInfo(d.filePath(cand)).absolutePath();
        if (!d.cdUp())
            break;
    }
    return defaultDir();
}

bool Workspace::create(const QString &dir, const QString &name, bool examples)
{
    QDir().mkpath(dir);
    if (QFileInfo::exists(QDir(dir).filePath(kMeta)))
        return true;
    const QJsonArray envs{
        QJsonObject{{QStringLiteral("name"), QStringLiteral("lokalne")},
                    {QStringLiteral("vars"), QJsonArray{QJsonObject{{QStringLiteral("key"), QStringLiteral("baseUrl")}, {QStringLiteral("value"), QStringLiteral("http://localhost:8000")}, {QStringLiteral("secret"), false}},
                                                        QJsonObject{{QStringLiteral("key"), QStringLiteral("token")}, {QStringLiteral("value"), QString()}, {QStringLiteral("secret"), true}}}}},
        QJsonObject{{QStringLiteral("name"), QStringLiteral("produkcyjne")},
                    {QStringLiteral("vars"), QJsonArray{QJsonObject{{QStringLiteral("key"), QStringLiteral("baseUrl")}, {QStringLiteral("value"), QStringLiteral("https://api.example.com")}, {QStringLiteral("secret"), false}},
                                                        QJsonObject{{QStringLiteral("key"), QStringLiteral("token")}, {QStringLiteral("value"), QString()}, {QStringLiteral("secret"), true}}}}}};
    const QJsonObject meta{{QStringLiteral("name"), name}, {QStringLiteral("environments"), envs}, {QStringLiteral("activeEnvironment"), QStringLiteral("lokalne")}};
    if (!writeJson(QDir(dir).filePath(kMeta), meta, nullptr))
        return false;
    if (examples) {
        QJsonObject get = normalizedRequest({{QStringLiteral("name"), QStringLiteral("Stan serwera")}, {QStringLiteral("url"), QStringLiteral("{{baseUrl}}/health")}});
        QJsonObject list = normalizedRequest({{QStringLiteral("name"), QStringLiteral("Lista użytkowników")}, {QStringLiteral("url"), QStringLiteral("{{baseUrl}}/users")},
                                              {QStringLiteral("params"), QJsonArray{kv(QStringLiteral("page"), QStringLiteral("1")), kv(QStringLiteral("limit"), QStringLiteral("20"), false)}}});
        QJsonObject post = normalizedRequest({{QStringLiteral("name"), QStringLiteral("Dodaj użytkownika")}, {QStringLiteral("method"), QStringLiteral("POST")},
                                              {QStringLiteral("url"), QStringLiteral("{{baseUrl}}/users")},
                                              {QStringLiteral("body"), QJsonObject{{QStringLiteral("mode"), QStringLiteral("json")}, {QStringLiteral("text"), QStringLiteral("{\n  \"name\": \"Ala\",\n  \"email\": \"ala@example.com\"\n}")}}},
                                              {QStringLiteral("auth"), QJsonObject{{QStringLiteral("type"), QStringLiteral("bearer")}, {QStringLiteral("token"), QStringLiteral("{{token}}")}}}});
        writeJson(QDir(dir).filePath(QStringLiteral("przyklady.json")),
                  {{QStringLiteral("name"), QStringLiteral("Przykłady")}, {QStringLiteral("requests"), QJsonArray{get, list, post}}}, nullptr);
    }
    return true;
}

bool Workspace::load(const QString &dir, QString *error)
{
    m_dir = QDir(dir).absolutePath();
    m_meta = {};
    m_collections.clear();
    const QString metaPath = QDir(m_dir).filePath(kMeta);
    if (!QFileInfo::exists(metaPath)) {
        if (error)
            *error = QStringLiteral("W %1 nie ma obszaru Pulse (pliku pulse.json)").arg(m_dir);
        return false;
    }
    if (!readJson(metaPath, &m_meta, error))
        return false;
    const QDir d(m_dir);
    const QStringList files = d.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    for (const QString &f : files) {
        if (f == kMeta)
            continue;
        QJsonObject c;
        if (!readJson(d.filePath(f), &c, nullptr) || !c.value(QLatin1String("requests")).isArray())
            continue;
        c[QStringLiteral("file")] = f;
        if (c.value(QLatin1String("name")).toString().isEmpty())
            c[QStringLiteral("name")] = QFileInfo(f).completeBaseName();
        QJsonArray reqs;
        for (const QJsonValue &r : c.value(QLatin1String("requests")).toArray())
            reqs.append(normalizedRequest(r.toObject()));
        c[QStringLiteral("requests")] = reqs;
        m_collections.append(c);
    }
    std::sort(m_collections.begin(), m_collections.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QLatin1String("name")).toString().localeAwareCompare(b.value(QLatin1String("name")).toString()) < 0;
    });
    return true;
}

QString Workspace::name() const
{
    const QString n = m_meta.value(QLatin1String("name")).toString();
    if (!n.isEmpty())
        return n;
    const QFileInfo fi(m_dir);
    // <projekt>/pulse → nazwa projektu
    return (fi.fileName() == QLatin1String("pulse") || fi.fileName() == QLatin1String(".pulse")) ? QFileInfo(fi.path()).fileName() : fi.fileName();
}

QJsonObject Workspace::environment(const QString &name) const
{
    for (const QJsonValue &e : environments())
        if (e.toObject().value(QLatin1String("name")).toString().compare(name, Qt::CaseInsensitive) == 0)
            return e.toObject();
    return {};
}

bool Workspace::writeMeta(QString *error)
{
    return writeJson(QDir(m_dir).filePath(kMeta), m_meta, error);
}

void Workspace::setActiveEnvironment(const QString &name)
{
    if (activeEnvironment() == name)
        return;
    m_meta[QStringLiteral("activeEnvironment")] = name;
    writeMeta(nullptr);
}

bool Workspace::saveEnvironments(const QJsonArray &envs, QString *error)
{
    QJsonArray clean;
    for (const QJsonValue &ev : envs) {
        QJsonObject e = ev.toObject();
        QJsonArray vars;
        for (const QJsonValue &vv : e.value(QLatin1String("vars")).toArray()) {
            QJsonObject v = vv.toObject();
            if (v.value(QLatin1String("key")).toString().trimmed().isEmpty())
                continue;
            v[QStringLiteral("key")] = v.value(QLatin1String("key")).toString().trimmed();
            const bool secret = v.value(QLatin1String("secret")).toBool();
            v[QStringLiteral("secret")] = secret;
            if (secret)
                v[QStringLiteral("value")] = QString();
            vars.append(v);
        }
        e[QStringLiteral("vars")] = vars;
        clean.append(e);
    }
    m_meta[QStringLiteral("environments")] = clean;
    return writeMeta(error);
}

bool Workspace::saveCollection(const QJsonObject &collection, QString *error)
{
    QJsonObject c = collection;
    const QString file = c.take(QLatin1String("file")).toString();
    if (file.isEmpty() || file.contains(QLatin1Char('/')) || file == kMeta) {
        if (error)
            *error = QStringLiteral("Zła nazwa pliku kolekcji");
        return false;
    }
    if (!writeJson(QDir(m_dir).filePath(file), c, error))
        return false;
    c[QStringLiteral("file")] = file;
    for (QJsonObject &o : m_collections)
        if (o.value(QLatin1String("file")).toString() == file) {
            o = c;
            return true;
        }
    m_collections.append(c);
    return true;
}

QString Workspace::createCollection(const QString &name, QString *error)
{
    QString base = slug(name);
    if (base == QLatin1String("pulse"))
        base = QStringLiteral("pulse-kolekcja");
    QString file = base + QStringLiteral(".json");
    for (int i = 2; QFileInfo::exists(QDir(m_dir).filePath(file)); ++i)
        file = base + QStringLiteral("-%1.json").arg(i);
    QString clean = name.trimmed();
    clean.replace(QLatin1Char('/'), QLatin1Char('-'));
    const QJsonObject c{{QStringLiteral("file"), file}, {QStringLiteral("name"), clean}, {QStringLiteral("requests"), QJsonArray()}};
    return saveCollection(c, error) ? file : QString();
}

bool Workspace::removeCollection(const QString &file)
{
    for (int i = 0; i < m_collections.size(); ++i)
        if (m_collections.at(i).value(QLatin1String("file")).toString() == file) {
            m_collections.removeAt(i);
            break;
        }
    return QFile::remove(QDir(m_dir).filePath(file));
}

QString Workspace::refFor(const QJsonObject &collection, const QJsonObject &request) const
{
    return collection.value(QLatin1String("name")).toString() + QLatin1Char('/') + request.value(QLatin1String("name")).toString();
}

QJsonObject Workspace::findRequest(const QString &ref, QString *error) const
{
    const int slash = ref.indexOf(QLatin1Char('/'));
    if (slash <= 0) {
        if (error)
            *error = QStringLiteral("Podaj zapytanie jako „kolekcja/zapytanie” (np. przyklady/Stan serwera)");
        return {};
    }
    const QString col = ref.left(slash).trimmed(), req = ref.mid(slash + 1).trimmed();
    for (const QJsonObject &c : m_collections) {
        const QString file = QFileInfo(c.value(QLatin1String("file")).toString()).completeBaseName();
        if (c.value(QLatin1String("name")).toString().compare(col, Qt::CaseInsensitive) != 0 && file.compare(col, Qt::CaseInsensitive) != 0
            && slug(c.value(QLatin1String("name")).toString()) != slug(col))
            continue;
        const QJsonArray reqs = c.value(QLatin1String("requests")).toArray();
        for (const QJsonValue &rv : reqs) {
            const QJsonObject r = rv.toObject();
            if (r.value(QLatin1String("name")).toString().compare(req, Qt::CaseInsensitive) == 0 || r.value(QLatin1String("id")).toString() == req)
                return r;
        }
        for (const QJsonValue &rv : reqs)   // „stan-serwera” zamiast „Stan serwera”
            if (slug(rv.toObject().value(QLatin1String("name")).toString()) == slug(req))
                return rv.toObject();
        if (error)
            *error = QStringLiteral("W kolekcji „%1” nie ma zapytania „%2”").arg(c.value(QLatin1String("name")).toString(), req);
        return {};
    }
    if (error)
        *error = QStringLiteral("Nie ma kolekcji „%1” w %2").arg(col, m_dir);
    return {};
}

QMap<QString, QString> Workspace::secretAttributes(const QString &dir, const QString &env, const QString &key)
{
    return {{QStringLiteral("application"), QStringLiteral("aster-pulse")},
            {QStringLiteral("workspace"), QDir(dir).absolutePath()},
            {QStringLiteral("environment"), env},
            {QStringLiteral("variable"), key}};
}

QHash<QString, QString> Workspace::variables(const QString &env, QStringList *missingSecrets, QString *error) const
{
    QHash<QString, QString> vars;
    const QJsonObject e = environment(env);
    for (const QJsonValue &vv : e.value(QLatin1String("vars")).toArray()) {
        const QJsonObject v = vv.toObject();
        const QString key = v.value(QLatin1String("key")).toString();
        if (key.isEmpty() || v.value(QLatin1String("enabled")).toBool(true) == false)
            continue;
        if (v.value(QLatin1String("secret")).toBool()) {
            const QString value = Secrets::read(secretAttributes(m_dir, e.value(QLatin1String("name")).toString(), key), error);
            if (value.isEmpty()) {
                if (missingSecrets)
                    missingSecrets->append(key);
                continue;
            }
            vars.insert(key, value);
        } else {
            vars.insert(key, v.value(QLatin1String("value")).toString());
        }
    }
    return vars;
}

QJsonObject Workspace::describe() const
{
    QJsonArray envs;
    for (const QJsonValue &ev : environments()) {
        const QJsonObject e = ev.toObject();
        QJsonArray vars;
        for (const QJsonValue &vv : e.value(QLatin1String("vars")).toArray()) {
            const QJsonObject v = vv.toObject();
            QJsonObject o{{QStringLiteral("key"), v.value(QLatin1String("key"))}, {QStringLiteral("secret"), v.value(QLatin1String("secret")).toBool()}};
            if (!v.value(QLatin1String("secret")).toBool())
                o[QStringLiteral("value")] = v.value(QLatin1String("value"));
            vars.append(o);
        }
        envs.append(QJsonObject{{QStringLiteral("name"), e.value(QLatin1String("name"))},
                                {QStringLiteral("active"), e.value(QLatin1String("name")).toString() == activeEnvironment()},
                                {QStringLiteral("variables"), vars}});
    }
    QJsonArray cols;
    for (const QJsonObject &c : m_collections) {
        QJsonArray reqs;
        for (const QJsonValue &rv : c.value(QLatin1String("requests")).toArray()) {
            const QJsonObject r = rv.toObject();
            reqs.append(QJsonObject{{QStringLiteral("ref"), refFor(c, r)},
                                    {QStringLiteral("name"), r.value(QLatin1String("name"))},
                                    {QStringLiteral("method"), r.value(QLatin1String("method"))},
                                    {QStringLiteral("url"), Vars::fullUrl(r)}});
        }
        cols.append(QJsonObject{{QStringLiteral("name"), c.value(QLatin1String("name"))}, {QStringLiteral("file"), c.value(QLatin1String("file"))}, {QStringLiteral("requests"), reqs}});
    }
    return {{QStringLiteral("workspace"), m_dir}, {QStringLiteral("name"), name()}, {QStringLiteral("activeEnvironment"), activeEnvironment()},
            {QStringLiteral("environments"), envs}, {QStringLiteral("collections"), cols}};
}

// ——— Zmienne ———

QString Vars::resolve(const QString &text, const QHash<QString, QString> &vars, QStringList *unresolved)
{
    if (!text.contains(QLatin1String("{{")))
        return text;
    static const QRegularExpression re(QStringLiteral("\\{\\{\\s*([^{}\\s]+)\\s*\\}\\}"));
    QString out;
    qsizetype last = 0;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        const auto m = it.next();
        out += text.mid(last, m.capturedStart() - last);
        last = m.capturedEnd();
        const QString name = m.captured(1);
        if (vars.contains(name)) {
            out += vars.value(name);
        } else if (name == QLatin1String("$timestamp")) {
            out += QString::number(QDateTime::currentSecsSinceEpoch());
        } else if (name == QLatin1String("$isoTimestamp")) {
            out += QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
        } else if (name == QLatin1String("$uuid") || name == QLatin1String("$guid")) {
            out += QUuid::createUuid().toString(QUuid::WithoutBraces);
        } else if (name == QLatin1String("$randomInt")) {
            out += QString::number(QRandomGenerator::global()->bounded(1000));
        } else {
            out += m.captured(0);
            if (unresolved && !unresolved->contains(name))
                unresolved->append(name);
        }
    }
    out += text.mid(last);
    return out;
}

QString Vars::fullUrl(const QJsonObject &req)
{
    QString url = req.value(QLatin1String("url")).toString().trimmed();
    QStringList parts;
    for (const QJsonValue &pv : req.value(QLatin1String("params")).toArray()) {
        const QJsonObject p = pv.toObject();
        if (!p.value(QLatin1String("enabled")).toBool(true) || p.value(QLatin1String("key")).toString().isEmpty())
            continue;
        // {{zmienne}} zostają bez kodowania — kodujemy po podstawieniu (w Runner)
        parts << p.value(QLatin1String("key")).toString() + QLatin1Char('=') + p.value(QLatin1String("value")).toString();
    }
    if (!parts.isEmpty())
        url += (url.contains(QLatin1Char('?')) ? QLatin1Char('&') : QLatin1Char('?')) + parts.join(QLatin1Char('&'));
    return url;
}

QJsonObject Vars::resolveRequest(const QJsonObject &req, const QHash<QString, QString> &vars, QStringList *unresolved)
{
    QJsonObject r = req;
    auto list = [&](const QJsonArray &a) {
        QJsonArray out;
        for (const QJsonValue &v : a) {
            QJsonObject o = v.toObject();
            o[QStringLiteral("key")] = resolve(o.value(QLatin1String("key")).toString(), vars, unresolved);
            o[QStringLiteral("value")] = resolve(o.value(QLatin1String("value")).toString(), vars, unresolved);
            out.append(o);
        }
        return out;
    };
    r[QStringLiteral("url")] = resolve(req.value(QLatin1String("url")).toString(), vars, unresolved);
    r[QStringLiteral("params")] = list(req.value(QLatin1String("params")).toArray());
    r[QStringLiteral("headers")] = list(req.value(QLatin1String("headers")).toArray());
    QJsonObject body = req.value(QLatin1String("body")).toObject();
    if (body.value(QLatin1String("mode")).toString() != QLatin1String("none")) {
        body[QStringLiteral("text")] = resolve(body.value(QLatin1String("text")).toString(), vars, unresolved);
        body[QStringLiteral("form")] = list(body.value(QLatin1String("form")).toArray());
        body[QStringLiteral("file")] = resolve(body.value(QLatin1String("file")).toString(), vars, unresolved);
    }
    r[QStringLiteral("body")] = body;
    QJsonObject auth = req.value(QLatin1String("auth")).toObject();
    for (const char *k : {"token", "user", "password"})
        if (auth.contains(QLatin1String(k)))
            auth[QLatin1String(k)] = resolve(auth.value(QLatin1String(k)).toString(), vars, unresolved);
    r[QStringLiteral("auth")] = auth;
    return r;
}

// ——— Historia ———

QString History::path()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster-pulse/history.json");
}

QJsonArray History::load()
{
    QFile f(path());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).array();
}

void History::append(const QJsonObject &request, const QJsonObject &result, const QString &env, const QString &source, const QString &workspace)
{
    QJsonArray all = load();
    QJsonObject req = request;
    req.remove(QStringLiteral("insecure"));
    const QJsonObject entry{{QStringLiteral("time"), QDateTime::currentDateTime().toString(Qt::ISODate)},
                            {QStringLiteral("request"), req},
                            {QStringLiteral("environment"), env},
                            {QStringLiteral("workspace"), workspace},
                            {QStringLiteral("source"), source},
                            {QStringLiteral("url"), result.value(QLatin1String("url"))},
                            {QStringLiteral("status"), result.value(QLatin1String("status"))},
                            {QStringLiteral("error"), result.value(QLatin1String("error"))},
                            {QStringLiteral("timeMs"), result.value(QLatin1String("timeMs"))},
                            {QStringLiteral("size"), result.value(QLatin1String("size"))}};
    all.prepend(entry);
    while (all.size() > 300)
        all.removeLast();
    QDir().mkpath(QFileInfo(path()).path());
    QSaveFile f(path());
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(all).toJson(QJsonDocument::Compact));
        f.commit();
    }
}

void History::clear()
{
    QFile::remove(path());
}

#include "engine.h"

#include <algorithm>
#include <memory>

#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDnsLookup>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHostAddress>
#include <QHostInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>

namespace {

Launch *s_instance = nullptr;

// Cytowanie dla powłoki — pokazywane polecenia mają dać się skopiować i wkleić do terminala
QString sq(const QString &s)
{
    static const QRegularExpression safe(QStringLiteral("^[A-Za-z0-9_./:=@%+,-]+$"));
    if (!s.isEmpty() && safe.match(s).hasMatch())
        return s;
    QString r = s;
    r.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + r + QLatin1Char('\'');
}

QString joinCmd(const QString &program, const QStringList &args)
{
    QStringList parts{sq(program)};
    for (const QString &a : args)
        parts << sq(a);
    return parts.join(QLatin1Char(' '));
}

QString slugOf(const QString &name)
{
    QString s = name.toLower();
    const QString from = QStringLiteral("ąćęłńóśźż"), to = QStringLiteral("acelnoszz");
    for (int i = 0; i < from.size(); ++i)
        s.replace(from[i], to[i]);
    s.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    s.remove(QRegularExpression(QStringLiteral("^-+|-+$")));
    return s.isEmpty() ? QStringLiteral("app") : s.left(40);
}

// Nazwa na serwerze (foldery, usługa, kontener) — ustalona przy dodaniu projektu, nie zmienia się ze zmianą nazwy
QString slugFor(const QJsonObject &p)
{
    const QString s = p.value(QStringLiteral("slug")).toString();
    return s.isEmpty() ? slugOf(p.value(QStringLiteral("name")).toString()) : s;
}

bool exists(const QString &dir, const QString &name) { return QFileInfo::exists(dir + QLatin1Char('/') + name); }

QString readFile(const QString &path, qint64 max = 512 * 1024)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.read(max));
}

QString now() { return QDateTime::currentDateTime().toString(Qt::ISODate); }

// Domeny, dla których Caddy sam wystawia certyfikat z własnego urzędu (bez Let's Encrypt)
bool localDomain(const QString &d)
{
    static const QStringList tl{QStringLiteral(".localhost"), QStringLiteral(".local"), QStringLiteral(".internal"),
                                QStringLiteral(".home.arpa"), QStringLiteral(".test"), QStringLiteral(".lan")};
    if (d == QLatin1String("localhost"))
        return true;
    for (const QString &t : tl)
        if (d.endsWith(t))
            return true;
    return !QHostAddress(d).isNull();
}

// Typowe błędy ssh/rsync po ludzku
QString explain(const QString &out)
{
    if (out.contains(QLatin1String("Permission denied (publickey")) || out.contains(QLatin1String("Permission denied, please try again")))
        return QStringLiteral("Serwer nie przyjął klucza SSH. Dodaj klucz publiczny na serwerze („Dodaj klucz na serwer” w ustawieniach celu).");
    if (out.contains(QLatin1String("Could not resolve hostname")))
        return QStringLiteral("Nie znaleziono serwera o tej nazwie — sprawdź adres.");
    if (out.contains(QLatin1String("Connection refused")))
        return QStringLiteral("Serwer odmówił połączenia — czy działa na nim SSH i czy port jest właściwy?");
    if (out.contains(QLatin1String("timed out")))
        return QStringLiteral("Serwer nie odpowiada — sprawdź adres i zaporę sieciową.");
    if (out.contains(QLatin1String("REMOTE HOST IDENTIFICATION HAS CHANGED")))
        return QStringLiteral("Klucz serwera się zmienił (nowy system albo ktoś się podszywa). Sprawdź to i usuń stary wpis: ssh-keygen -R ADRES.");
    if (out.contains(QLatin1String("sudo: a password is required")) || out.contains(QLatin1String("sudo: a terminal is required")))
        return QStringLiteral("Użytkownik na serwerze potrzebuje hasła do sudo. Użyj konta root albo zezwól na sudo bez hasła (NOPASSWD).");
    if (out.contains(QLatin1String("rsync: command not found")) || out.contains(QLatin1String("rsync: not found")))
        return QStringLiteral("Na serwerze brakuje programu rsync.");
    return {};
}

const char *kTypeNames[][2] = {
    {"static", "Statyczna strona"},
    {"node", "Node.js"},
    {"python", "Python"},
    {"docker", "Docker"},
    {"compose", "Docker Compose"},
};

} // namespace

// ——— LogModel ———

QVariant LogModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_lines.size())
        return {};
    const QString &l = m_lines.at(index.row());
    if (role == TextRole)
        return l;
    if (role == LevelRole) {
        if (l.startsWith(QLatin1String("▸ ")))
            return QStringLiteral("step");
        static const QRegularExpression err(QStringLiteral("\\b(error|err|fatal|failed|exception|traceback|błąd)\\b"), QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression warn(QStringLiteral("\\b(warn|warning|ostrzeżenie)\\b"), QRegularExpression::CaseInsensitiveOption);
        if (err.match(l).hasMatch())
            return QStringLiteral("error");
        if (warn.match(l).hasMatch())
            return QStringLiteral("warn");
        return QString();
    }
    return {};
}

void LogModel::append(const QString &line)
{
    constexpr int limit = 3000;
    if (m_lines.size() >= limit) {
        const int drop = 500;
        beginRemoveRows({}, 0, drop - 1);
        m_lines.erase(m_lines.begin(), m_lines.begin() + drop);
        endRemoveRows();
    }
    beginInsertRows({}, int(m_lines.size()), int(m_lines.size()));
    m_lines << line;
    endInsertRows();
    Q_EMIT countChanged();
    Q_EMIT appended(line);
}

void LogModel::clear()
{
    beginResetModel();
    m_lines.clear();
    endResetModel();
    Q_EMIT countChanged();
}

// ——— Launch ———

Launch::Launch(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
    load();
}

Launch::~Launch()
{
    if (m_liveProc)
        m_liveProc->kill();
    if (m_proc)
        m_proc->kill();
    if (s_instance == this)
        s_instance = nullptr;
}

Launch *Launch::instance()
{
    if (!s_instance)
        new Launch(QCoreApplication::instance());
    return s_instance;
}

Launch *Launch::create(QQmlEngine *, QJSEngine *)
{
    Launch *l = instance();
    QJSEngine::setObjectOwnership(l, QJSEngine::CppOwnership);
    return l;
}

bool Launch::flatpak() const { return QFileInfo::exists(QStringLiteral("/.flatpak-info")); }

QString Launch::dataDir() const
{
    const QString d = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Aster/aster-launch");
    QDir().mkpath(d);
    return d;
}

void Launch::load()
{
    const QJsonDocument doc = QJsonDocument::fromJson(readFile(dataDir() + QStringLiteral("/projekty.json"), 16 * 1024 * 1024).toUtf8());
    m_projects = doc.object().value(QStringLiteral("projects")).toArray();
}

void Launch::reload()
{
    if (m_running)
        return;
    load();
    Q_EMIT projectsChanged();
}

void Launch::save()
{
    QSaveFile f(dataDir() + QStringLiteral("/projekty.json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(QJsonObject{{QStringLiteral("projects"), m_projects}}).toJson(QJsonDocument::Indented));
        f.commit();
    }
    Q_EMIT projectsChanged();
}

QJsonObject *Launch::find(const QString &id)
{
    // QJsonArray nie daje referencji do elementów — trzymamy kopię roboczą i zapisujemy ją z powrotem w updateProject
    static QJsonObject tmp;
    for (const QJsonValue &v : std::as_const(m_projects))
        if (v.toObject().value(QStringLiteral("id")).toString() == id) {
            tmp = v.toObject();
            return &tmp;
        }
    return nullptr;
}

const QJsonObject *Launch::find(const QString &id) const { return const_cast<Launch *>(this)->find(id); }

QVariantList Launch::projects() const
{
    QVariantList out;
    for (const QJsonValue &v : m_projects) {
        QVariantMap m = v.toObject().toVariantMap();
        m[QStringLiteral("typeName")] = describeType(m.value(QStringLiteral("type")).toString());
        m[QStringLiteral("url")] = urlFor(m.value(QStringLiteral("id")).toString());
        out << m;
    }
    return out;
}

QVariantMap Launch::project(const QString &id) const
{
    for (const QVariant &v : projects())
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            return v.toMap();
    return {};
}

QString Launch::findProject(const QString &key) const
{
    const QString abs = QFileInfo(key).absoluteFilePath();
    for (const QJsonValue &v : m_projects) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("id")).toString() == key || o.value(QStringLiteral("name")).toString().compare(key, Qt::CaseInsensitive) == 0
            || slugFor(o) == key || o.value(QStringLiteral("path")).toString() == abs)
            return o.value(QStringLiteral("id")).toString();
    }
    return {};
}

QString Launch::describeType(const QString &type) const
{
    for (const auto &t : kTypeNames)
        if (type == QLatin1String(t[0]))
            return QString::fromUtf8(t[1]);
    return type;
}

// ——— Wykrywanie typu projektu ———

QVariantMap Launch::detect(const QString &path) const
{
    QVariantMap r;
    QStringList notes;
    const QString d = QDir(path).absolutePath();
    QString type, build, output, start;
    int port = 0;

    const QStringList composeFiles{QStringLiteral("compose.yaml"), QStringLiteral("compose.yml"), QStringLiteral("docker-compose.yml"), QStringLiteral("docker-compose.yaml")};
    QString composeFile;
    for (const QString &c : composeFiles)
        if (exists(d, c)) {
            composeFile = c;
            break;
        }
    const bool dockerfile = exists(d, QStringLiteral("Dockerfile")) || exists(d, QStringLiteral("Containerfile"));
    const bool pkg = exists(d, QStringLiteral("package.json"));
    const bool py = exists(d, QStringLiteral("requirements.txt")) || exists(d, QStringLiteral("pyproject.toml"))
        || exists(d, QStringLiteral("app.py")) || exists(d, QStringLiteral("main.py")) || exists(d, QStringLiteral("manage.py"));

    if (!composeFile.isEmpty()) {
        type = QStringLiteral("compose");
        static const QRegularExpression portRe(QStringLiteral("[\"']?(?:\\d+\\.\\d+\\.\\d+\\.\\d+:)?(\\d{2,5}):\\d{2,5}[\"']?"));
        const auto m = portRe.match(readFile(d + QLatin1Char('/') + composeFile));
        port = m.hasMatch() ? m.captured(1).toInt() : 8080;
        notes << QStringLiteral("Plik %1 — usługi uruchomi „compose up” na serwerze.").arg(composeFile);
    } else if (dockerfile) {
        type = QStringLiteral("docker");
        const QString df = readFile(d + (exists(d, QStringLiteral("Dockerfile")) ? QStringLiteral("/Dockerfile") : QStringLiteral("/Containerfile")));
        static const QRegularExpression expose(QStringLiteral("^\\s*EXPOSE\\s+(\\d+)"), QRegularExpression::MultilineOption | QRegularExpression::CaseInsensitiveOption);
        const auto m = expose.match(df);
        port = m.hasMatch() ? m.captured(1).toInt() : 8080;
        notes << QStringLiteral("Obraz zbuduje się na serwerze z Dockerfile.");
    } else if (pkg) {
        const QJsonObject pj = QJsonDocument::fromJson(readFile(d + QStringLiteral("/package.json")).toUtf8()).object();
        const QJsonObject scripts = pj.value(QStringLiteral("scripts")).toObject();
        QJsonObject deps = pj.value(QStringLiteral("dependencies")).toObject();
        const QJsonObject dev = pj.value(QStringLiteral("devDependencies")).toObject();
        for (auto it = dev.begin(); it != dev.end(); ++it)
            deps.insert(it.key(), it.value());
        const auto has = [&](const char *n) { return deps.contains(QLatin1String(n)); };
        const bool server = has("express") || has("fastify") || has("koa") || has("@nestjs/core") || has("next") || has("nuxt")
            || has("@sveltejs/adapter-node") || has("hono") || (scripts.contains(QStringLiteral("start")) && !scripts.contains(QStringLiteral("build")));
        if (!server && scripts.contains(QStringLiteral("build"))) {
            type = QStringLiteral("static");
            build = exists(d, QStringLiteral("pnpm-lock.yaml")) ? QStringLiteral("pnpm install && pnpm run build")
                : exists(d, QStringLiteral("yarn.lock"))        ? QStringLiteral("yarn install && yarn build")
                                                                 : QStringLiteral("npm install && npm run build");
            output = has("react-scripts") || has("@docusaurus/core") ? QStringLiteral("build")
                : has("@angular/core")                               ? QStringLiteral("dist")
                                                                      : QStringLiteral("dist");
            notes << QStringLiteral("Strona budowana na tym komputerze (%1), na serwer trafia tylko folder %2.").arg(build, output);
        } else {
            type = QStringLiteral("node");
            start = scripts.contains(QStringLiteral("start")) ? QStringLiteral("npm start")
                : exists(d, QStringLiteral("server.js"))      ? QStringLiteral("node server.js")
                                                               : QStringLiteral("node index.js");
            port = has("next") || has("nuxt") || has("express") ? 3000 : 3000;
            notes << QStringLiteral("Aplikacja Node.js — zależności zainstalują się na serwerze, program działa jako usługa systemd.");
            notes << QStringLiteral("Program powinien słuchać na porcie ze zmiennej PORT.");
        }
    } else if (py) {
        type = QStringLiteral("python");
        const QString mainFile = exists(d, QStringLiteral("app.py")) ? QStringLiteral("app.py")
            : exists(d, QStringLiteral("main.py"))                   ? QStringLiteral("main.py")
            : exists(d, QStringLiteral("server.py"))                 ? QStringLiteral("server.py")
                                                                      : QStringLiteral("app.py");
        const QString req = readFile(d + QStringLiteral("/requirements.txt")).toLower();
        if (exists(d, QStringLiteral("manage.py")))
            start = QStringLiteral(".venv/bin/python manage.py runserver 127.0.0.1:$PORT --noreload");
        else if (req.contains(QLatin1String("uvicorn")) && mainFile == QLatin1String("main.py"))
            start = QStringLiteral(".venv/bin/uvicorn main:app --host 127.0.0.1 --port $PORT");
        else if (req.contains(QLatin1String("gunicorn")))
            start = QStringLiteral(".venv/bin/gunicorn -b 127.0.0.1:$PORT %1:app").arg(QFileInfo(mainFile).baseName());
        else
            start = QStringLiteral(".venv/bin/python %1").arg(mainFile);
        port = 8000;
        notes << QStringLiteral("Aplikacja Python — środowisko .venv i zależności powstaną na serwerze, program działa jako usługa systemd.");
        notes << QStringLiteral("Program powinien słuchać na porcie ze zmiennej PORT.");
    } else {
        type = QStringLiteral("static");
        if (!exists(d, QStringLiteral("index.html")) && exists(d, QStringLiteral("public/index.html")))
            output = QStringLiteral("public");
        if (!exists(d, QStringLiteral("index.html")) && output.isEmpty())
            notes << QStringLiteral("Nie ma tu index.html — wybierz folder ze stroną albo zmień typ projektu.");
        else
            notes << QStringLiteral("Pliki strony trafią na serwer bez budowania, poda je Caddy.");
    }

    r[QStringLiteral("type")] = type;
    r[QStringLiteral("typeName")] = describeType(type);
    r[QStringLiteral("build")] = build;
    r[QStringLiteral("output")] = output;
    r[QStringLiteral("start")] = start;
    r[QStringLiteral("port")] = port;
    r[QStringLiteral("notes")] = notes;
    r[QStringLiteral("git")] = exists(d, QStringLiteral(".git"));
    return r;
}

QString Launch::addProject(const QString &rawPath)
{
    QString path = rawPath;
    if (path.startsWith(QLatin1String("file:")))
        path = QUrl(path).toLocalFile();
    path = QDir(path).absolutePath();
    if (!QFileInfo(path).isDir())
        return {};
    const QString existing = findProject(path);
    if (!existing.isEmpty())
        return existing;
    const QVariantMap d = detect(path);
    QString id = QString::number(QRandomGenerator::global()->generate(), 16);
    QJsonObject o{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), QFileInfo(path).fileName()},
        {QStringLiteral("slug"), slugOf(QFileInfo(path).fileName())},
        {QStringLiteral("path"), path},
        {QStringLiteral("type"), d.value(QStringLiteral("type")).toString()},
        {QStringLiteral("build"), d.value(QStringLiteral("build")).toString()},
        {QStringLiteral("output"), d.value(QStringLiteral("output")).toString()},
        {QStringLiteral("start"), d.value(QStringLiteral("start")).toString()},
        {QStringLiteral("port"), d.value(QStringLiteral("port")).toInt()},
        {QStringLiteral("target"), QStringLiteral("ssh")},
        {QStringLiteral("host"), QString()},
        {QStringLiteral("user"), QStringLiteral("root")},
        {QStringLiteral("sshPort"), 22},
        {QStringLiteral("key"), QString()},
        {QStringLiteral("domain"), QString()},
        {QStringLiteral("publicPort"), 8080},
        {QStringLiteral("site"), QString()},
        {QStringLiteral("keep"), 5},
        {QStringLiteral("current"), 0},
        {QStringLiteral("history"), QJsonArray()},
        {QStringLiteral("events"), QJsonArray()},
        {QStringLiteral("created"), now()},
    };
    m_projects.append(o);
    save();
    return id;
}

void Launch::updateProject(const QString &id, const QVariantMap &changes)
{
    for (int i = 0; i < m_projects.size(); ++i) {
        QJsonObject o = m_projects.at(i).toObject();
        if (o.value(QStringLiteral("id")).toString() != id)
            continue;
        for (auto it = changes.begin(); it != changes.end(); ++it) {
            if (it.key() == QLatin1String("id") || it.key() == QLatin1String("history") || it.key() == QLatin1String("slug"))
                continue;
            o.insert(it.key(), QJsonValue::fromVariant(it.value()));
        }
        // Zmiana serwera = stare informacje o nim nieaktualne
        if (changes.contains(QStringLiteral("host")) || changes.contains(QStringLiteral("user")) || changes.contains(QStringLiteral("sshPort")))
            o.remove(QStringLiteral("facts"));
        m_projects.replace(i, o);
        save();
        return;
    }
}

void Launch::removeProject(const QString &id)
{
    for (int i = 0; i < m_projects.size(); ++i)
        if (m_projects.at(i).toObject().value(QStringLiteral("id")).toString() == id) {
            m_projects.removeAt(i);
            save();
            return;
        }
}

QString Launch::urlFor(const QString &id) const
{
    const QJsonObject *p = find(id);
    if (!p)
        return {};
    const QString domain = p->value(QStringLiteral("domain")).toString().trimmed();
    if (!domain.isEmpty())
        return QStringLiteral("https://") + domain + QLatin1Char('/');
    const QString target = p->value(QStringLiteral("target")).toString();
    if (target != QLatin1String("ssh")) {
        const QJsonArray h = p->value(QStringLiteral("history")).toArray();
        const int cur = p->value(QStringLiteral("current")).toInt();
        for (const QJsonValue &v : h)
            if (v.toObject().value(QStringLiteral("v")).toInt() == cur)
                return v.toObject().value(QStringLiteral("url")).toString();
        return {};
    }
    const QString host = p->value(QStringLiteral("host")).toString();
    if (host.isEmpty())
        return {};
    const int port = p->value(QStringLiteral("publicPort")).toInt(80);
    return QStringLiteral("http://%1%2/").arg(host, port == 80 ? QString() : QStringLiteral(":%1").arg(port));
}

int Launch::previousVersion(const QString &id) const
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return 0;
    const int cur = pp->value(QStringLiteral("current")).toInt();
    const bool ssh = pp->value(QStringLiteral("target")).toString() == QLatin1String("ssh");
    int best = 0;
    for (const QJsonValue &h : pp->value(QStringLiteral("history")).toArray()) {
        const QJsonObject o = h.toObject();
        const int v = o.value(QStringLiteral("v")).toInt();
        if (v < cur && v > best && o.value(QStringLiteral("status")).toString() != QLatin1String("failed") && (!ssh || o.value(QStringLiteral("onServer")).toBool()))
            best = v;
    }
    return best;
}

// ——— Polecenia ———

void Launch::hostCommand(QString &program, QStringList &args) const
{
    if (!flatpak())
        return;
    args.prepend(program);
    args.prepend(QStringLiteral("--host"));
    program = QStringLiteral("flatpak-spawn");
}

QString Launch::which(const QString &program) const
{
    if (flatpak()) {
        QProcess p;
        p.start(QStringLiteral("flatpak-spawn"), {QStringLiteral("--host"), QStringLiteral("sh"), QStringLiteral("-lc"), QStringLiteral("command -v ") + sq(program)});
        p.waitForFinished(3000);
        return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    }
    const QString home = QDir::homePath();
    QString r = QStandardPaths::findExecutable(program);
    if (r.isEmpty())
        r = QStandardPaths::findExecutable(program, {home + QStringLiteral("/.local/bin"), home + QStringLiteral("/.npm-global/bin"), home + QStringLiteral("/bin")});
    return r;
}

QStringList Launch::sshOptions(const QJsonObject &p) const
{
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/aster-launch");
    QDir().mkpath(cache);
    QStringList o{QStringLiteral("-o"), QStringLiteral("BatchMode=yes"),
                  QStringLiteral("-o"), QStringLiteral("StrictHostKeyChecking=accept-new"),
                  QStringLiteral("-o"), QStringLiteral("ConnectTimeout=10"),
                  QStringLiteral("-o"), QStringLiteral("ServerAliveInterval=15"),
                  QStringLiteral("-o"), QStringLiteral("ControlMaster=auto"),
                  QStringLiteral("-o"), QStringLiteral("ControlPath=") + cache + QStringLiteral("/cm-%C"),
                  QStringLiteral("-o"), QStringLiteral("ControlPersist=60")};
    const int port = p.value(QStringLiteral("sshPort")).toInt(22);
    if (port != 22)
        o << QStringLiteral("-p") << QString::number(port);
    const QString key = p.value(QStringLiteral("key")).toString();
    if (!key.isEmpty()) {
        o << QStringLiteral("-i") << key << QStringLiteral("-o") << QStringLiteral("IdentitiesOnly=yes");
    } else {
        // „Domyślny”: zwykłe klucze z ~/.ssh wprost (ssh bierze katalog domowy z /etc/passwd, nie z $HOME)
        for (const char *n : {"id_ed25519", "id_ecdsa", "id_rsa"}) {
            const QString k = QDir::homePath() + QStringLiteral("/.ssh/") + QLatin1String(n);
            if (QFileInfo::exists(k))
                o << QStringLiteral("-i") << k;
        }
    }
    return o;
}

QString Launch::sshDest(const QJsonObject &p) const
{
    const QString user = p.value(QStringLiteral("user")).toString();
    const QString host = p.value(QStringLiteral("host")).toString();
    return user.isEmpty() ? host : user + QLatin1Char('@') + host;
}

static bool needsSudo(const QJsonObject &p) { return p.value(QStringLiteral("user")).toString() != QLatin1String("root") && !p.value(QStringLiteral("user")).toString().isEmpty(); }

Step Launch::remoteStep(const QJsonObject &p, const QString &id, const QString &title, const QString &detail, const QString &script, bool change) const
{
    Step s;
    s.id = id;
    s.title = title;
    s.detail = detail;
    s.where = QStringLiteral("Na serwerze %1").arg(sshDest(p));
    s.program = QStringLiteral("ssh");
    s.args = sshOptions(p);
    s.args << sshDest(p) << (needsSudo(p) ? QStringLiteral("sudo -n sh -s") : QStringLiteral("sh -s"));
    s.input = (QStringLiteral("set -e\n") + script + QLatin1Char('\n')).toUtf8();
    s.shown = script;
    s.change = change;
    return s;
}

void Launch::runRemote(const QJsonObject &p, const QString &script, std::function<void(int, QString)> done)
{
    QString program = QStringLiteral("ssh");
    QStringList args = sshOptions(p);
    args << sshDest(p) << (needsSudo(p) ? QStringLiteral("sudo -n sh -s") : QStringLiteral("sh -s"));
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::finished, this, [proc, done](int code, QProcess::ExitStatus st) {
        done(st == QProcess::NormalExit ? code : -1, QString::fromUtf8(proc->readAll()));
        proc->deleteLater();
    });
    connect(proc, &QProcess::errorOccurred, this, [proc, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            done(-2, QStringLiteral("Nie udało się uruchomić ssh (czy jest zainstalowany?)."));
            proc->deleteLater();
        }
    });
    proc->start(program, args);
    proc->write(script.toUtf8());
    proc->closeWriteChannel();
}

// ——— Sprawdzenie serwera (tylko odczyt) ———

void Launch::probe(const QString &id)
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    const QJsonObject p = *pp;
    if (p.value(QStringLiteral("host")).toString().isEmpty()) {
        Q_EMIT probed(id, false, QStringLiteral("Podaj adres serwera."));
        return;
    }
    const QString script = QStringLiteral(
        "echo user=$(id -un)\n"
        "echo os=$(. /etc/os-release 2>/dev/null; echo \"$PRETTY_NAME\")\n"
        "echo arch=$(uname -m)\n"
        "for c in systemctl podman docker caddy rsync node npm python3 curl dnf apt-get; do printf '%s=%s\\n' \"$c\" \"$(command -v $c 2>/dev/null)\"; done\n"
        "[ -d /run/systemd/system ] && echo systemd=yes || echo systemd=no\n"
        "if [ \"$(id -u)\" = 0 ]; then echo sudo=root; elif sudo -n true 2>/dev/null; then echo sudo=yes; else echo sudo=no; fi\n"
        "systemctl is-active caddy 2>/dev/null | sed 's/^/caddyActive=/' || true\n"
        "echo apps=$(ls /srv/aster-launch 2>/dev/null | tr '\\n' ' ')\n");
    QString program = QStringLiteral("ssh");
    QStringList args = sshOptions(p);
    args << sshDest(p) << QStringLiteral("sh -s");
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::finished, this, [this, proc, id](int code, QProcess::ExitStatus) {
        const QString out = QString::fromUtf8(proc->readAll());
        proc->deleteLater();
        if (code != 0) {
            const QString why = explain(out);
            Q_EMIT probed(id, false, why.isEmpty() ? out.trimmed().split(QLatin1Char('\n')).last() : why);
            return;
        }
        QJsonObject facts;
        for (const QString &line : out.split(QLatin1Char('\n'))) {
            const int eq = line.indexOf(QLatin1Char('='));
            if (eq > 0)
                facts.insert(line.left(eq), line.mid(eq + 1).trimmed());
        }
        facts.insert(QStringLiteral("time"), now());
        for (int i = 0; i < m_projects.size(); ++i) {
            QJsonObject o = m_projects.at(i).toObject();
            if (o.value(QStringLiteral("id")).toString() == id) {
                o.insert(QStringLiteral("facts"), facts);
                m_projects.replace(i, o);
            }
        }
        save();
        QStringList have;
        if (facts.value(QStringLiteral("systemd")).toString() == QLatin1String("yes"))
            have << QStringLiteral("systemd");
        for (const char *c : {"podman", "docker", "caddy", "rsync", "node", "python3"})
            if (!facts.value(QLatin1String(c)).toString().isEmpty())
                have << QLatin1String(c);
        QString msg = QStringLiteral("Połączono: %1 (%2). Jest: %3.").arg(facts.value(QStringLiteral("os")).toString(), facts.value(QStringLiteral("arch")).toString(), have.join(QStringLiteral(", ")));
        if (facts.value(QStringLiteral("sudo")).toString() == QLatin1String("no"))
            msg += QStringLiteral(" Uwaga: brak sudo bez hasła — wdrożenie wymaga konta root albo NOPASSWD.");
        Q_EMIT probed(id, true, msg);
    });
    proc->start(program, args);
    proc->write(script.toUtf8());
    proc->closeWriteChannel();
}

QString Launch::serverIp(const QJsonObject &p) const
{
    const QString host = p.value(QStringLiteral("host")).toString();
    if (!QHostAddress(host).isNull())
        return host;
    const QHostInfo info = QHostInfo::fromName(host);
    for (const QHostAddress &a : info.addresses())
        if (a.protocol() == QAbstractSocket::IPv4Protocol)
            return a.toString();
    return info.addresses().isEmpty() ? QString() : info.addresses().first().toString();
}

void Launch::checkDns(const QString &id)
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    const QJsonObject p = *pp;
    const QString domain = p.value(QStringLiteral("domain")).toString().trimmed();
    if (domain.isEmpty()) {
        Q_EMIT dnsChecked(id, {{QStringLiteral("ok"), true}, {QStringLiteral("message"), QStringLiteral("Bez domeny — strona będzie pod adresem serwera.")}});
        return;
    }
    const QString ip = p.value(QStringLiteral("target")).toString() == QLatin1String("ssh") ? serverIp(p) : QString();
    auto *lookup = new QDnsLookup(QDnsLookup::A, domain, this);
    connect(lookup, &QDnsLookup::finished, this, [this, lookup, id, domain, ip] {
        QStringList records;
        for (const QDnsHostAddressRecord &r : lookup->hostAddressRecords())
            records << r.value().toString();
        lookup->deleteLater();
        QVariantMap res{{QStringLiteral("domain"), domain}, {QStringLiteral("records"), records}, {QStringLiteral("server"), ip}};
        bool ok = false;
        QString msg;
        if (records.isEmpty()) {
            msg = localDomain(domain)
                ? QStringLiteral("„%1” to domena lokalna — w internecie jej nie ma. Caddy wystawi certyfikat z własnego urzędu (przeglądarki go nie znają).").arg(domain)
                : QStringLiteral("Domena „%1” nie ma jeszcze rekordu A. U rejestratora domeny dodaj rekord A: %1 → %2. Zmiana DNS może potrwać do kilku godzin.").arg(domain, ip.isEmpty() ? QStringLiteral("adres serwera") : ip);
        } else if (ip.isEmpty() || records.contains(ip)) {
            ok = true;
            msg = ip.isEmpty() ? QStringLiteral("Domena wskazuje na %1.").arg(records.join(QStringLiteral(", ")))
                               : QStringLiteral("Domena wskazuje na ten serwer (%1) — Caddy sam pobierze certyfikat HTTPS z Let's Encrypt.").arg(ip);
        } else {
            msg = QStringLiteral("Domena wskazuje na %1, a serwer ma adres %2. Zmień rekord A u rejestratora domeny na %2.").arg(records.join(QStringLiteral(", ")), ip);
        }
        res[QStringLiteral("ok")] = ok;
        res[QStringLiteral("message")] = msg;
        Q_EMIT dnsChecked(id, res);
    });
    lookup->lookup();
}

// ——— Sprawdzenie strony ———

QStringList Launch::healthCurl(const QJsonObject &p, bool insecure) const
{
    const QString id = p.value(QStringLiteral("id")).toString();
    const QString url = urlFor(id);
    QStringList a{QStringLiteral("-sS"), QStringLiteral("-o"), QStringLiteral("/dev/null"), QStringLiteral("-w"), QStringLiteral("%{http_code} %{time_total}"),
                  QStringLiteral("--max-time"), QStringLiteral("10"), QStringLiteral("-L"), QStringLiteral("--max-redirs"), QStringLiteral("3")};
    const QString domain = p.value(QStringLiteral("domain")).toString().trimmed();
    if (!domain.isEmpty() && p.value(QStringLiteral("target")).toString() == QLatin1String("ssh")) {
        // Domena może jeszcze nie wskazywać serwera (DNS) — pytamy wprost serwer, z właściwą nazwą (SNI)
        const QHostInfo info = QHostInfo::fromName(domain);
        const QString ip = serverIp(p);
        bool points = false;
        for (const QHostAddress &h : info.addresses())
            points |= h.toString() == ip;
        if (!points && !ip.isEmpty())
            a << QStringLiteral("--resolve") << QStringLiteral("%1:443:%2").arg(domain, ip) << QStringLiteral("--resolve") << QStringLiteral("%1:80:%2").arg(domain, ip);
    }
    if (insecure)
        a << QStringLiteral("-k");
    a << url;
    return a;
}

void Launch::checkHealth(const QString &id)
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    const QJsonObject p = *pp;
    const QString url = urlFor(id);
    if (url.isEmpty()) {
        Q_EMIT healthChecked(id, {{QStringLiteral("ok"), false}, {QStringLiteral("message"), QStringLiteral("Brak adresu strony.")}});
        return;
    }
    auto attempt = std::make_shared<std::function<void(bool)>>();
    *attempt = [this, id, p, url, attempt](bool insecure) {
        QString program = QStringLiteral("curl");
        QStringList args = healthCurl(p, insecure);
        hostCommand(program, args);
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this, [this, proc, id, url, insecure, attempt](int code, QProcess::ExitStatus) {
            const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
            const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            proc->deleteLater();
            // 60 = nieznany urząd certyfikacji — spróbuj jeszcze raz bez sprawdzania, żeby powiedzieć, czy strona w ogóle działa
            if ((code == 60 || code == 35) && !insecure) {
                (*attempt)(true);
                return;
            }
            const int http = out.section(QLatin1Char(' '), 0, 0).toInt();
            const double secs = out.section(QLatin1Char(' '), 1, 1).toDouble();
            const bool ok = code == 0 && http >= 200 && http < 400;
            QString msg;
            if (ok)
                msg = QStringLiteral("Strona odpowiada (HTTP %1, %2 ms)").arg(http).arg(qRound(secs * 1000));
            else if (code == 0)
                msg = QStringLiteral("Strona odpowiada błędem HTTP %1").arg(http);
            else
                msg = QStringLiteral("Strona nie odpowiada: %1").arg(err.isEmpty() ? QStringLiteral("kod curl %1").arg(code) : err);
            if (ok && insecure)
                msg += QStringLiteral(" — certyfikat niezaufany (domena lokalna albo jeszcze bez Let's Encrypt)");
            QVariantMap res{{QStringLiteral("ok"), ok}, {QStringLiteral("code"), http}, {QStringLiteral("ms"), qRound(secs * 1000)},
                            {QStringLiteral("url"), url}, {QStringLiteral("insecure"), insecure}, {QStringLiteral("message"), msg}, {QStringLiteral("time"), now()}};
            for (int i = 0; i < m_projects.size(); ++i) {
                QJsonObject o = m_projects.at(i).toObject();
                if (o.value(QStringLiteral("id")).toString() == id) {
                    o.insert(QStringLiteral("lastCheck"), QJsonObject::fromVariantMap(res));
                    m_projects.replace(i, o);
                }
            }
            save();
            Q_EMIT healthChecked(id, res);
        });
        proc->start(program, args);
    };
    (*attempt)(false);
}

// ——— Klucze SSH ———

QVariantList Launch::sshKeys() const
{
    QVariantList out;
    const QDir d(QDir::homePath() + QStringLiteral("/.ssh"));
    for (const QFileInfo &fi : d.entryInfoList({QStringLiteral("*.pub")}, QDir::Files, QDir::Name)) {
        const QString priv = fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName();
        if (!QFileInfo::exists(priv))
            continue;
        const QString pub = readFile(fi.absoluteFilePath()).trimmed();
        out << QVariantMap{{QStringLiteral("name"), fi.completeBaseName()}, {QStringLiteral("path"), priv},
                           {QStringLiteral("kind"), pub.section(QLatin1Char(' '), 0, 0).remove(QStringLiteral("ssh-"))},
                           {QStringLiteral("comment"), pub.section(QLatin1Char(' '), 2)}};
    }
    return out;
}

QString Launch::publicKey(const QString &privatePath) const
{
    const QString path = privatePath.isEmpty() ? QString() : privatePath + QStringLiteral(".pub");
    if (!path.isEmpty())
        return readFile(path).trimmed();
    for (const QString &n : {QStringLiteral("id_ed25519"), QStringLiteral("id_ecdsa"), QStringLiteral("id_rsa")}) {
        const QString t = readFile(QDir::homePath() + QStringLiteral("/.ssh/") + n + QStringLiteral(".pub")).trimmed();
        if (!t.isEmpty())
            return t;
    }
    return {};
}

QVariantMap Launch::createKey(const QString &rawName)
{
    QString name = slugOf(rawName.isEmpty() ? QStringLiteral("aster-launch") : rawName).replace(QLatin1Char('-'), QLatin1Char('_'));
    const QString dir = QDir::homePath() + QStringLiteral("/.ssh");
    QDir().mkpath(dir);
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QString path = dir + QLatin1Char('/') + name + QStringLiteral("_ed25519");
    for (int i = 2; QFileInfo::exists(path); ++i)
        path = dir + QLatin1Char('/') + name + QStringLiteral("_ed25519_") + QString::number(i);
    QString program = QStringLiteral("ssh-keygen");
    QStringList args{QStringLiteral("-q"), QStringLiteral("-t"), QStringLiteral("ed25519"), QStringLiteral("-N"), QString(), QStringLiteral("-f"), path,
                     QStringLiteral("-C"), QStringLiteral("aster-launch@") + QSysInfo::machineHostName()};
    hostCommand(program, args);
    QProcess p;
    p.start(program, args);
    p.waitForFinished(20000);
    if (p.exitCode() != 0 || !QFileInfo::exists(path))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("message"), QString::fromUtf8(p.readAllStandardError()).trimmed()}};
    return {{QStringLiteral("ok"), true}, {QStringLiteral("path"), path}, {QStringLiteral("public"), publicKey(path)}};
}

void Launch::copyKeyInTerminal(const QString &id)
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    QStringList args{QStringLiteral("-e"), QStringLiteral("ssh-copy-id")};
    const QString key = pp->value(QStringLiteral("key")).toString();
    if (!key.isEmpty())
        args << QStringLiteral("-i") << key + QStringLiteral(".pub");
    const int port = pp->value(QStringLiteral("sshPort")).toInt(22);
    if (port != 22)
        args << QStringLiteral("-p") << QString::number(port);
    args << sshDest(*pp);
    QString program = QStringLiteral("aster-terminal");
    hostCommand(program, args);
    QProcess::startDetached(program, args);
}

void Launch::copyText(const QString &text)
{
    if (auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
        app->clipboard()->setText(text);
}

void Launch::openFolder(const QString &path) { QDesktopServices::openUrl(QUrl::fromLocalFile(path)); }
void Launch::openUrl(const QString &url) { QDesktopServices::openUrl(QUrl(url)); }

// ——— Hostingi ———

QVariantMap Launch::hostingInfo(const QString &kind) const
{
    QString name, cli, pkg, site;
    if (kind == QLatin1String("netlify")) {
        name = QStringLiteral("Netlify");
        cli = QStringLiteral("netlify");
        pkg = QStringLiteral("netlify-cli");
        site = QStringLiteral("Nazwa albo ID strony z app.netlify.com (nową utworzysz poleceniem: netlify sites:create)");
    } else if (kind == QLatin1String("vercel")) {
        name = QStringLiteral("Vercel");
        cli = QStringLiteral("vercel");
        pkg = QStringLiteral("vercel");
        site = QStringLiteral("Projekt Vercel powstanie sam przy pierwszym wdrożeniu");
    } else if (kind == QLatin1String("cloudflare")) {
        name = QStringLiteral("Cloudflare Pages");
        cli = QStringLiteral("wrangler");
        pkg = QStringLiteral("wrangler");
        site = QStringLiteral("Nazwa projektu Pages (powstanie przy pierwszym wdrożeniu)");
    } else {
        return {};
    }
    const QString path = which(cli);
    return {{QStringLiteral("kind"), kind}, {QStringLiteral("name"), name}, {QStringLiteral("cli"), cli}, {QStringLiteral("installed"), !path.isEmpty()},
            {QStringLiteral("path"), path}, {QStringLiteral("package"), pkg}, {QStringLiteral("siteHint"), site},
            {QStringLiteral("install"), QStringLiteral("npm install -g --prefix ~/.local ") + pkg},
            {QStringLiteral("npm"), !which(QStringLiteral("npm")).isEmpty()},
            {QStringLiteral("login"), cli + QStringLiteral(" login")}};
}

void Launch::checkHostingLogin(const QString &kind)
{
    const QVariantMap info = hostingInfo(kind);
    if (!info.value(QStringLiteral("installed")).toBool()) {
        Q_EMIT hostingChecked(kind, false, QString());
        return;
    }
    QString program = info.value(QStringLiteral("path")).toString();
    QStringList args = kind == QLatin1String("netlify") ? QStringList{QStringLiteral("status")} : QStringList{QStringLiteral("whoami")};
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::finished, this, [this, proc, kind](int code, QProcess::ExitStatus) {
        const QString out = QString::fromUtf8(proc->readAll());
        proc->deleteLater();
        static const QRegularExpression email(QStringLiteral("[\\w.+-]+@[\\w-]+\\.[\\w.]+"));
        const auto m = email.match(out);
        const bool notLogged = out.contains(QLatin1String("Not logged in"), Qt::CaseInsensitive) || out.contains(QLatin1String("not authenticated"), Qt::CaseInsensitive);
        QString who = m.hasMatch() ? m.captured(0) : out.trimmed().split(QLatin1Char('\n')).last().trimmed();
        Q_EMIT hostingChecked(kind, code == 0 && !notLogged, who.left(80));
    });
    proc->start(program, args);
}

void Launch::hostingLogin(const QString &kind)
{
    const QVariantMap info = hostingInfo(kind);
    if (!info.value(QStringLiteral("installed")).toBool())
        return;
    QString program = info.value(QStringLiteral("path")).toString();
    QStringList args{QStringLiteral("login")};
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::readyRead, this, [this, proc, kind] {
        const QString chunk = QString::fromUtf8(proc->readAll()).trimmed();
        if (!chunk.isEmpty())
            Q_EMIT hostingMessage(kind, chunk.split(QLatin1Char('\n')).last());
    });
    connect(proc, &QProcess::finished, this, [this, proc, kind](int, QProcess::ExitStatus) {
        proc->deleteLater();
        checkHostingLogin(kind);
    });
    Q_EMIT hostingMessage(kind, QStringLiteral("Otwieram stronę logowania w przeglądarce…"));
    proc->start(program, args);
}

void Launch::installHostingCli(const QString &kind)
{
    const QVariantMap info = hostingInfo(kind);
    QString program = QStringLiteral("npm");
    QStringList args{QStringLiteral("install"), QStringLiteral("-g"), QStringLiteral("--prefix"), QDir::homePath() + QStringLiteral("/.local"), info.value(QStringLiteral("package")).toString()};
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::finished, this, [this, proc, kind](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        Q_EMIT hostingMessage(kind, code == 0 ? QStringLiteral("Zainstalowano.") : QStringLiteral("Instalacja nie udała się (kod %1).").arg(code));
        checkHostingLogin(kind);
    });
    Q_EMIT hostingMessage(kind, QStringLiteral("Instaluję %1…").arg(info.value(QStringLiteral("package")).toString()));
    proc->start(program, args);
}

// ——— Plan wdrożenia ———

QString Launch::startCommand(const QJsonObject &p) const
{
    QString s = p.value(QStringLiteral("start")).toString().trimmed();
    if (s.isEmpty())
        s = p.value(QStringLiteral("type")).toString() == QLatin1String("python") ? QStringLiteral(".venv/bin/python app.py") : QStringLiteral("npm start");
    return s;
}

QString Launch::unitFile(const QJsonObject &p) const
{
    const QString slug = slugFor(p);
    const QString base = QStringLiteral("/srv/aster-launch/") + slug;
    const int port = p.value(QStringLiteral("port")).toInt(3000);
    QString start = startCommand(p);
    const bool node = p.value(QStringLiteral("type")).toString() == QLatin1String("node");
    // systemd szuka programu w PATH dopiero od wersji 239 i bez powłoki — przez /bin/sh działają też „npm start” i $PORT
    return QStringLiteral(
               "[Unit]\n"
               "Description=%1 (Aster Launch)\n"
               "After=network-online.target\n"
               "Wants=network-online.target\n\n"
               "[Service]\n"
               "WorkingDirectory=%2/current\n"
               "Environment=PORT=%3\n"
               "Environment=HOST=127.0.0.1\n"
               "%4"
               "Environment=HOME=/var/lib/aster-%5\n"
               "ExecStart=/bin/sh -c %6\n"
               "Restart=always\n"
               "RestartSec=2\n"
               "DynamicUser=yes\n"
               "StateDirectory=aster-%5\n"
               "ProtectSystem=strict\n"
               "ProtectHome=yes\n"
               "PrivateTmp=yes\n"
               "NoNewPrivileges=yes\n\n"
               "[Install]\n"
               "WantedBy=multi-user.target\n")
        .arg(p.value(QStringLiteral("name")).toString(), base, QString::number(port),
             node ? QStringLiteral("Environment=NODE_ENV=production\n") : QString(), slug, sq(QStringLiteral("exec ") + start));
}

QString Launch::caddySite(const QJsonObject &p) const
{
    const QString slug = slugFor(p);
    const QString domain = p.value(QStringLiteral("domain")).toString().trimmed();
    const QString address = domain.isEmpty() ? QStringLiteral(":%1").arg(p.value(QStringLiteral("publicPort")).toInt(8080)) : domain;
    QString body;
    if (p.value(QStringLiteral("type")).toString() == QLatin1String("static"))
        body = QStringLiteral("\troot * /srv/aster-launch/%1/current\n"
                              "\tencode zstd gzip\n"
                              "\ttry_files {path} {path}/ {path}.html /index.html\n"
                              "\tfile_server\n")
                   .arg(slug);
    else
        body = QStringLiteral("\tencode zstd gzip\n\treverse_proxy 127.0.0.1:%1\n").arg(p.value(QStringLiteral("port")).toInt(3000));
    return QStringLiteral("# Aster Launch: %1 — plik zarządzany przez program, zmiany zostaną nadpisane\n%2 {\n%3}\n")
        .arg(p.value(QStringLiteral("name")).toString(), address, body);
}

static QString heredoc(const QString &path, const QString &content)
{
    return QStringLiteral("cat > %1 <<'ASTER_EOF'\n%2ASTER_EOF\n").arg(sq(path), content.endsWith(QLatin1Char('\n')) ? content : content + QLatin1Char('\n'));
}

QList<Step> Launch::deploySteps(const QJsonObject &p, int v, QString &error) const
{
    QList<Step> steps;
    const QString type = p.value(QStringLiteral("type")).toString();
    const QString target = p.value(QStringLiteral("target")).toString();
    const QString path = p.value(QStringLiteral("path")).toString();
    const QString build = p.value(QStringLiteral("build")).toString().trimmed();
    const QString output = p.value(QStringLiteral("output")).toString().trimmed();
    const QString slug = slugFor(p);

    if (!QFileInfo(path).isDir()) {
        error = QStringLiteral("Nie ma folderu projektu: %1").arg(path);
        return {};
    }

    if (!build.isEmpty()) {
        Step s;
        s.id = QStringLiteral("build");
        s.title = QStringLiteral("Budowanie");
        s.detail = QStringLiteral("Polecenie budowania projektu");
        s.where = QStringLiteral("Na tym komputerze");
        s.program = QStringLiteral("sh");
        s.args = {QStringLiteral("-c"), build};
        s.workDir = path;
        s.shown = QStringLiteral("cd %1\n%2").arg(sq(path), build);
        s.change = false;
        steps << s;
    }
    const QString src = output.isEmpty() ? path : path + QLatin1Char('/') + output;

    // ——— Hostingi ———
    if (target != QLatin1String("ssh")) {
        const QVariantMap info = hostingInfo(target);
        if (info.isEmpty()) {
            error = QStringLiteral("Nieznany cel wdrożenia.");
            return {};
        }
        if (!info.value(QStringLiteral("installed")).toBool()) {
            error = QStringLiteral("Brakuje programu %1 (%2). Zainstaluj go w ustawieniach celu.").arg(info.value(QStringLiteral("cli")).toString(), info.value(QStringLiteral("name")).toString());
            return {};
        }
        const QString site = p.value(QStringLiteral("site")).toString().trimmed();
        if (site.isEmpty() && target != QLatin1String("vercel")) {
            error = QStringLiteral("Podaj nazwę strony w %1 (ustawienia celu).").arg(info.value(QStringLiteral("name")).toString());
            return {};
        }
        const bool whole = type != QLatin1String("static"); // Vercel buduje aplikacje Node sam — wysyłamy cały folder
        if (whole && target != QLatin1String("vercel")) {
            error = QStringLiteral("%1 przyjmuje tu tylko strony statyczne. Aplikację %2 wdrożysz na własny serwer albo do Vercel.")
                        .arg(info.value(QStringLiteral("name")).toString(), describeType(type));
            return {};
        }
        // Kopia wdrożonych plików na tym komputerze — z niej przywracamy poprzednią wersję
        const QString snap = dataDir() + QStringLiteral("/kopie/") + slug + QStringLiteral("/v") + QString::number(v);
        QString deployDir = src;
        if (!whole) {
            Step c;
            c.id = QStringLiteral("snapshot");
            c.title = QStringLiteral("Kopia wersji v%1").arg(v);
            c.detail = QStringLiteral("Do przywrócenia tej wersji jednym kliknięciem");
            c.where = QStringLiteral("Na tym komputerze");
            c.program = QStringLiteral("sh");
            c.args = {QStringLiteral("-c"), QStringLiteral("mkdir -p %1 && cp -a %2/. %1/").arg(sq(snap), sq(src))};
            c.shown = c.args.last();
            c.change = false;
            steps << c;
            deployDir = snap;
        }
        Step d;
        d.id = QStringLiteral("hosting");
        d.title = QStringLiteral("Wdrożenie do %1").arg(info.value(QStringLiteral("name")).toString());
        d.detail = QStringLiteral("Wersja produkcyjna — zastąpi obecną stronę");
        d.where = info.value(QStringLiteral("name")).toString();
        d.program = info.value(QStringLiteral("path")).toString();
        if (target == QLatin1String("netlify"))
            d.args = {QStringLiteral("deploy"), QStringLiteral("--prod"), QStringLiteral("--dir"), deployDir, QStringLiteral("--site"), site,
                      QStringLiteral("--message"), QStringLiteral("Aster Launch v%1").arg(v)};
        else if (target == QLatin1String("vercel"))
            d.args = whole ? QStringList{QStringLiteral("deploy"), QStringLiteral("--prod"), QStringLiteral("--yes")}
                           : QStringList{QStringLiteral("deploy"), deployDir, QStringLiteral("--prod"), QStringLiteral("--yes")};
        else
            d.args = {QStringLiteral("pages"), QStringLiteral("deploy"), deployDir, QStringLiteral("--project-name"), site, QStringLiteral("--branch"), QStringLiteral("main"),
                      QStringLiteral("--commit-dirty=true")};
        d.workDir = path;
        d.shown = joinCmd(info.value(QStringLiteral("cli")).toString(), d.args);
        steps << d;
    } else {
        // ——— Własny serwer przez SSH ———
        const QJsonObject f = p.value(QStringLiteral("facts")).toObject();
        if (p.value(QStringLiteral("host")).toString().isEmpty()) {
            error = QStringLiteral("Podaj adres serwera w ustawieniach celu.");
            return {};
        }
        if (f.isEmpty()) {
            error = QStringLiteral("Nie udało się sprawdzić serwera.");
            return {};
        }
        if (f.value(QStringLiteral("sudo")).toString() == QLatin1String("no")) {
            error = QStringLiteral("Użytkownik %1 nie ma na serwerze sudo bez hasła. Użyj konta root albo dodaj regułę NOPASSWD.").arg(p.value(QStringLiteral("user")).toString());
            return {};
        }
        const bool systemd = f.value(QStringLiteral("systemd")).toString() == QLatin1String("yes");
        const bool container = type == QLatin1String("docker") || type == QLatin1String("compose");
        QString engine = f.value(QStringLiteral("podman")).toString().isEmpty() ? (f.value(QStringLiteral("docker")).toString().isEmpty() ? QString() : QStringLiteral("docker")) : QStringLiteral("podman");
        const QString base = QStringLiteral("/srv/aster-launch/") + slug;
        const QString rel = base + QStringLiteral("/releases/v") + QString::number(v);
        const int port = p.value(QStringLiteral("port")).toInt(3000);
        const int cur = p.value(QStringLiteral("current")).toInt();

        if ((type == QLatin1String("node") || type == QLatin1String("python")) && !systemd) {
            error = QStringLiteral("Na serwerze nie działa systemd, a aplikacja %1 ma chodzić jako usługa. Użyj serwera z systemd albo dodaj Dockerfile.").arg(describeType(type));
            return {};
        }

        // Brakujące programy na serwerze
        QStringList pkgs;
        if (f.value(QStringLiteral("caddy")).toString().isEmpty())
            pkgs << QStringLiteral("caddy");
        if (f.value(QStringLiteral("rsync")).toString().isEmpty())
            pkgs << QStringLiteral("rsync");
        if (type == QLatin1String("node") && f.value(QStringLiteral("npm")).toString().isEmpty())
            pkgs << QStringLiteral("nodejs") << QStringLiteral("npm");
        if (type == QLatin1String("python") && f.value(QStringLiteral("python3")).toString().isEmpty())
            pkgs << QStringLiteral("python3");
        if (container && engine.isEmpty()) {
            pkgs << QStringLiteral("podman");
            if (type == QLatin1String("compose"))
                pkgs << QStringLiteral("podman-compose");
            engine = QStringLiteral("podman");
        }
        if (!pkgs.isEmpty()) {
            QString cmd;
            if (!f.value(QStringLiteral("dnf")).toString().isEmpty())
                cmd = QStringLiteral("dnf install -y ") + pkgs.join(QLatin1Char(' '));
            else if (!f.value(QStringLiteral("apt-get")).toString().isEmpty()) {
                if (type == QLatin1String("python"))
                    pkgs << QStringLiteral("python3-venv");
                cmd = QStringLiteral("export DEBIAN_FRONTEND=noninteractive\napt-get update -q\napt-get install -y ") + pkgs.join(QLatin1Char(' '));
            } else {
                error = QStringLiteral("Na serwerze brakuje: %1, a nie umiem ich zainstalować w tym systemie (%2). Zainstaluj je ręcznie.")
                            .arg(pkgs.join(QStringLiteral(", ")), f.value(QStringLiteral("os")).toString());
                return {};
            }
            if (pkgs.contains(QStringLiteral("caddy")) && systemd)
                cmd += QStringLiteral("\nsystemctl enable --now caddy");
            steps << remoteStep(p, QStringLiteral("packages"), QStringLiteral("Instalacja programów na serwerze"),
                                QStringLiteral("Brakuje: %1").arg(pkgs.join(QStringLiteral(", "))), cmd);
        }

        steps << remoteStep(p, QStringLiteral("prepare"), QStringLiteral("Folder nowej wersji"),
                            QStringLiteral("Nowa wersja obok poprzednich — obecna działa dalej"), QStringLiteral("mkdir -p %1").arg(rel));

        // Wysyłka plików: rsync (tylko zmienione pliki; niezmienione jako twarde dowiązania do poprzedniej wersji)
        {
            Step s;
            s.id = QStringLiteral("upload");
            s.title = QStringLiteral("Wysłanie plików");
            s.detail = output.isEmpty() ? QStringLiteral("Folder projektu bez .git, node_modules i .venv") : QStringLiteral("Zbudowana strona z folderu %1").arg(output);
            s.where = QStringLiteral("Z tego komputera na %1").arg(sshDest(p));
            s.program = QStringLiteral("rsync");
            QStringList ssh{QStringLiteral("ssh")};
            for (const QString &o : sshOptions(p))
                ssh << sq(o);
            s.args = {QStringLiteral("-az"), QStringLiteral("--delete"), QStringLiteral("--human-readable"), QStringLiteral("--stats"),
                      QStringLiteral("--exclude=.git"), QStringLiteral("--exclude=node_modules"), QStringLiteral("--exclude=.venv"),
                      QStringLiteral("--exclude=__pycache__"), QStringLiteral("--exclude=.DS_Store")};
            if (cur > 0)
                s.args << QStringLiteral("--link-dest=%1/releases/v%2/").arg(base).arg(cur);
            if (needsSudo(p))
                s.args << QStringLiteral("--rsync-path=sudo -n rsync");
            s.args << QStringLiteral("-e") << ssh.join(QLatin1Char(' ')) << src + QLatin1Char('/') << sshDest(p) + QLatin1Char(':') + rel + QLatin1Char('/');
            s.shown = joinCmd(QStringLiteral("rsync"), s.args);
            steps << s;
        }

        // Przygotowanie wersji: zależności albo obraz
        if (type == QLatin1String("node")) {
            QString script = QStringLiteral("cd %1\nif [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi\n").arg(rel);
            const QJsonObject scripts = QJsonDocument::fromJson(readFile(path + QStringLiteral("/package.json")).toUtf8()).object().value(QStringLiteral("scripts")).toObject();
            if (scripts.contains(QStringLiteral("build")))
                script += QStringLiteral("npm run build\n");
            steps << remoteStep(p, QStringLiteral("install"), QStringLiteral("Zależności Node.js"), QStringLiteral("npm w folderze nowej wersji"), script);
        } else if (type == QLatin1String("python")) {
            QString script = QStringLiteral("cd %1\npython3 -m venv .venv\n").arg(rel);
            if (exists(path, QStringLiteral("requirements.txt")))
                script += QStringLiteral(".venv/bin/pip install -q --disable-pip-version-check -r requirements.txt\n");
            else if (exists(path, QStringLiteral("pyproject.toml")))
                script += QStringLiteral(".venv/bin/pip install -q --disable-pip-version-check .\n");
            steps << remoteStep(p, QStringLiteral("install"), QStringLiteral("Środowisko Python"), QStringLiteral("venv i zależności w folderze nowej wersji"), script);
        } else if (type == QLatin1String("docker")) {
            steps << remoteStep(p, QStringLiteral("install"), QStringLiteral("Budowa obrazu"), QStringLiteral("Obraz kontenera z Dockerfile"),
                                QStringLiteral("%1 build -t localhost/aster-%2:v%3 %4").arg(engine, slug).arg(v).arg(rel));
        }

        // Przełączenie na nową wersję
        QString sw;
        if (type == QLatin1String("node") || type == QLatin1String("python")) {
            sw = heredoc(QStringLiteral("/etc/systemd/system/aster-%1.service").arg(slug), unitFile(p));
            sw += QStringLiteral("ln -sfn releases/v%1 %2/current\n"
                                 "systemctl daemon-reload\n"
                                 "systemctl enable aster-%3.service\n"
                                 "systemctl restart aster-%3.service\n"
                                 "sleep 2\n"
                                 "systemctl is-active aster-%3.service")
                      .arg(v)
                      .arg(base, slug);
        } else if (type == QLatin1String("docker")) {
            sw = QStringLiteral("%1 rm -f aster-%2 >/dev/null 2>&1 || true\n"
                                "%1 run -d --name aster-%2 --restart=always -e PORT=%3 -p 127.0.0.1:%3:%3 localhost/aster-%2:v%4\n"
                                "ln -sfn releases/v%4 %5/current")
                     .arg(engine, slug)
                     .arg(port)
                     .arg(v)
                     .arg(base);
            if (engine == QLatin1String("podman") && systemd)
                sw += QStringLiteral("\nsystemctl enable podman-restart.service >/dev/null 2>&1 || true");
        } else if (type == QLatin1String("compose")) {
            sw = QStringLiteral("cd %1\n%2 compose -p aster-%3 up -d --build --remove-orphans\nln -sfn releases/v%4 %5/current")
                     .arg(rel, engine, slug)
                     .arg(v)
                     .arg(base);
        } else {
            sw = QStringLiteral("ln -sfn releases/v%1 %2/current").arg(v).arg(base);
        }
        steps << remoteStep(p, QStringLiteral("switch"), QStringLiteral("Przełączenie na v%1").arg(v),
                            type == QLatin1String("static") ? QStringLiteral("Strona od razu pokazuje nową wersję")
                                                            : container ? QStringLiteral("Nowy kontener zastępuje poprzedni")
                                                                        : QStringLiteral("Usługa systemd aster-%1 uruchamia nową wersję").arg(slug),
                            sw);

        // Caddy: reverse proxy i HTTPS
        {
            const QString file = QStringLiteral("/etc/caddy/Caddyfile.d/aster-%1.caddyfile").arg(slug);
            QString script = QStringLiteral("mkdir -p /etc/caddy/Caddyfile.d\n") + heredoc(file, caddySite(p));
            script += QStringLiteral("grep -qs 'Caddyfile.d/\\*' /etc/caddy/Caddyfile || printf '\\nimport Caddyfile.d/*.caddyfile\\n' >> /etc/caddy/Caddyfile\n"
                                     "caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 | tail -n 1\n");
            script += systemd ? QStringLiteral("systemctl enable caddy >/dev/null 2>&1 || true\nsystemctl reload-or-restart caddy")
                              : QStringLiteral("caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null || caddy start --config /etc/caddy/Caddyfile --adapter caddyfile");
            const QString domain = p.value(QStringLiteral("domain")).toString().trimmed();
            steps << remoteStep(p, QStringLiteral("proxy"), QStringLiteral("Caddy"),
                                domain.isEmpty() ? QStringLiteral("Strona pod portem %1 serwera").arg(p.value(QStringLiteral("publicPort")).toInt(8080))
                                : localDomain(domain) ? QStringLiteral("%1 z certyfikatem HTTPS z urzędu Caddy (domena lokalna)").arg(domain)
                                                      : QStringLiteral("%1 z automatycznym certyfikatem HTTPS (Let's Encrypt)").arg(domain),
                                script);
        }

        // Sprzątanie: zostaje `keep` ostatnich wersji
        {
            const int keep = qMax(2, p.value(QStringLiteral("keep")).toInt(5));
            QList<int> versions;
            for (const QJsonValue &h : p.value(QStringLiteral("history")).toArray()) {
                const QJsonObject o = h.toObject();
                if (o.value(QStringLiteral("onServer")).toBool())
                    versions << o.value(QStringLiteral("v")).toInt();
            }
            versions << v;
            std::sort(versions.begin(), versions.end(), std::greater<int>());
            QStringList kept;
            for (int i = 0; i < versions.size() && kept.size() < keep; ++i)
                kept << QStringLiteral("v%1").arg(versions[i]);
            if (cur > 0 && !kept.contains(QStringLiteral("v%1").arg(cur)))
                kept << QStringLiteral("v%1").arg(cur);
            if (versions.size() > keep) {
                QString script = QStringLiteral("cd %1/releases\nfor d in v*; do case \" %2 \" in *\" $d \"*) ;; *) echo \"usuwam $d\"; rm -rf \"$d\";; esac; done")
                                     .arg(base, kept.join(QLatin1Char(' ')));
                if (type == QLatin1String("docker"))
                    script += QStringLiteral("\nfor i in $(%1 images --format '{{.Tag}}' localhost/aster-%2); do case \" %3 \" in *\" $i \"*) ;; *) %1 rmi localhost/aster-%2:$i >/dev/null 2>&1 || true;; esac; done")
                                  .arg(engine, slug, kept.join(QLatin1Char(' ')));
                steps << remoteStep(p, QStringLiteral("cleanup"), QStringLiteral("Sprzątanie starych wersji"),
                                    QStringLiteral("Zostają: %1").arg(kept.join(QStringLiteral(", "))), script);
            }
        }
    }

    Step h;
    h.id = QStringLiteral("health");
    h.title = QStringLiteral("Sprawdzenie strony");
    h.detail = QStringLiteral("Czy strona odpowiada po wdrożeniu");
    h.where = QStringLiteral("Na tym komputerze");
    h.program = QStringLiteral("curl");
    h.shown = target == QLatin1String("ssh") ? joinCmd(QStringLiteral("curl"), healthCurl(p, false)) : QStringLiteral("curl <adres z wdrożenia>");
    h.change = false;
    steps << h;
    return steps;
}

QList<Step> Launch::rollbackSteps(const QJsonObject &p, int v, QString &error) const
{
    QList<Step> steps;
    const QString type = p.value(QStringLiteral("type")).toString();
    const QString target = p.value(QStringLiteral("target")).toString();
    const QString slug = slugFor(p);
    QJsonObject entry;
    for (const QJsonValue &h : p.value(QStringLiteral("history")).toArray())
        if (h.toObject().value(QStringLiteral("v")).toInt() == v)
            entry = h.toObject();
    if (entry.isEmpty()) {
        error = QStringLiteral("Nie ma wersji v%1.").arg(v);
        return {};
    }
    if (v == p.value(QStringLiteral("current")).toInt()) {
        error = QStringLiteral("Wersja v%1 już działa.").arg(v);
        return {};
    }

    if (target != QLatin1String("ssh")) {
        const QVariantMap info = hostingInfo(target);
        if (!info.value(QStringLiteral("installed")).toBool()) {
            error = QStringLiteral("Brakuje programu %1.").arg(info.value(QStringLiteral("cli")).toString());
            return {};
        }
        Step d;
        d.id = QStringLiteral("hosting");
        d.where = info.value(QStringLiteral("name")).toString();
        d.program = info.value(QStringLiteral("path")).toString();
        d.workDir = p.value(QStringLiteral("path")).toString();
        const QString snap = dataDir() + QStringLiteral("/kopie/") + slug + QStringLiteral("/v") + QString::number(v);
        if (target == QLatin1String("vercel") && !entry.value(QStringLiteral("url")).toString().isEmpty()) {
            d.title = QStringLiteral("Przywrócenie v%1 w Vercel").arg(v);
            d.detail = QStringLiteral("Vercel wskazuje domenę produkcyjną na wcześniejsze wdrożenie");
            d.args = {QStringLiteral("rollback"), entry.value(QStringLiteral("url")).toString(), QStringLiteral("--yes")};
        } else {
            if (!QFileInfo(snap).isDir()) {
                error = QStringLiteral("Nie ma już kopii wersji v%1 na tym komputerze.").arg(v);
                return {};
            }
            const QString site = p.value(QStringLiteral("site")).toString();
            d.title = QStringLiteral("Ponowne wdrożenie v%1 do %2").arg(v).arg(info.value(QStringLiteral("name")).toString());
            d.detail = QStringLiteral("Z kopii zapisanej przy wdrożeniu v%1").arg(v);
            if (target == QLatin1String("netlify"))
                d.args = {QStringLiteral("deploy"), QStringLiteral("--prod"), QStringLiteral("--dir"), snap, QStringLiteral("--site"), site,
                          QStringLiteral("--message"), QStringLiteral("Aster Launch: przywrócenie v%1").arg(v)};
            else if (target == QLatin1String("vercel"))
                d.args = {QStringLiteral("deploy"), snap, QStringLiteral("--prod"), QStringLiteral("--yes")};
            else
                d.args = {QStringLiteral("pages"), QStringLiteral("deploy"), snap, QStringLiteral("--project-name"), site, QStringLiteral("--branch"), QStringLiteral("main"),
                          QStringLiteral("--commit-dirty=true")};
        }
        d.shown = joinCmd(info.value(QStringLiteral("cli")).toString(), d.args);
        steps << d;
    } else {
        if (!entry.value(QStringLiteral("onServer")).toBool()) {
            error = QStringLiteral("Wersji v%1 nie ma już na serwerze (usunięta przy sprzątaniu albo nieudana).").arg(v);
            return {};
        }
        const QJsonObject f = p.value(QStringLiteral("facts")).toObject();
        const QString engine = f.value(QStringLiteral("podman")).toString().isEmpty() ? QStringLiteral("docker") : QStringLiteral("podman");
        const QString base = QStringLiteral("/srv/aster-launch/") + slug;
        const int port = p.value(QStringLiteral("port")).toInt(3000);
        QString sw;
        if (type == QLatin1String("node") || type == QLatin1String("python"))
            sw = QStringLiteral("test -d %1/releases/v%2\nln -sfn releases/v%2 %1/current\nsystemctl restart aster-%3.service\nsleep 2\nsystemctl is-active aster-%3.service")
                     .arg(base)
                     .arg(v)
                     .arg(slug);
        else if (type == QLatin1String("docker"))
            sw = QStringLiteral("%1 image exists localhost/aster-%2:v%3 2>/dev/null || %1 image inspect localhost/aster-%2:v%3 >/dev/null\n"
                                "%1 rm -f aster-%2 >/dev/null 2>&1 || true\n"
                                "%1 run -d --name aster-%2 --restart=always -e PORT=%4 -p 127.0.0.1:%4:%4 localhost/aster-%2:v%3\n"
                                "ln -sfn releases/v%3 %5/current")
                     .arg(engine, slug)
                     .arg(v)
                     .arg(port)
                     .arg(base);
        else if (type == QLatin1String("compose"))
            sw = QStringLiteral("cd %1/releases/v%2\n%3 compose -p aster-%4 up -d --build --remove-orphans\nln -sfn releases/v%2 %1/current")
                     .arg(base)
                     .arg(v)
                     .arg(engine, slug);
        else
            sw = QStringLiteral("test -d %1/releases/v%2\nln -sfn releases/v%2 %1/current").arg(base).arg(v);
        steps << remoteStep(p, QStringLiteral("switch"), QStringLiteral("Powrót do v%1").arg(v),
                            QStringLiteral("Wersja v%1 jest jeszcze na serwerze — wystarczy na nią przełączyć").arg(v), sw);
    }
    Step h;
    h.id = QStringLiteral("health");
    h.title = QStringLiteral("Sprawdzenie strony");
    h.detail = QStringLiteral("Czy strona odpowiada po przywróceniu");
    h.where = QStringLiteral("Na tym komputerze");
    h.program = QStringLiteral("curl");
    h.shown = target == QLatin1String("ssh") ? joinCmd(QStringLiteral("curl"), healthCurl(p, false)) : QStringLiteral("curl <adres strony>");
    h.change = false;
    steps << h;
    return steps;
}

void Launch::setPreparing(bool p)
{
    if (m_preparing == p)
        return;
    m_preparing = p;
    Q_EMIT preparingChanged();
}

void Launch::setPlan(const QString &id, const QString &title, const QList<Step> &steps, const QString &kind, int version)
{
    m_plan = steps;
    m_planProject = id;
    m_planTitle = title;
    m_planKind = kind;
    m_planVersion = version;
    m_runResult.clear();
    Q_EMIT planChanged();
}

void Launch::prepareDeploy(const QString &id, const QString &origin)
{
    if (m_running || m_preparing)
        return;
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    m_planOrigin = origin;
    setPreparing(true);
    const auto build = [this, id] {
        setPreparing(false);
        const QJsonObject p = *find(id);
        int v = 0;
        for (const QJsonValue &h : p.value(QStringLiteral("history")).toArray())
            v = qMax(v, h.toObject().value(QStringLiteral("v")).toInt());
        ++v;
        QString error;
        const QList<Step> steps = deploySteps(p, v, error);
        if (!error.isEmpty()) {
            Q_EMIT planFailed(id, error);
            return;
        }
        setPlan(id, QStringLiteral("Wdrożenie %1 — wersja v%2").arg(p.value(QStringLiteral("name")).toString()).arg(v), steps, QStringLiteral("deploy"), v);
        Q_EMIT planReady(id);
    };
    if (pp->value(QStringLiteral("target")).toString() == QLatin1String("ssh")) {
        // Najpierw świeży odczyt stanu serwera (bez zmian), żeby plan był dokładny
        auto conn = std::make_shared<QMetaObject::Connection>();
        *conn = connect(this, &Launch::probed, this, [this, id, build, conn](const QString &pid, bool ok, const QString &msg) {
            if (pid != id)
                return;
            disconnect(*conn);
            if (!ok) {
                setPreparing(false);
                Q_EMIT planFailed(id, msg);
                return;
            }
            build();
        });
        probe(id);
    } else {
        QTimer::singleShot(0, this, build);
    }
}

void Launch::prepareRollback(const QString &id, int version, const QString &origin)
{
    if (m_running || m_preparing)
        return;
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    m_planOrigin = origin;
    QString error;
    const QJsonObject p = *pp;
    const QList<Step> steps = rollbackSteps(p, version, error);
    if (!error.isEmpty()) {
        Q_EMIT planFailed(id, error);
        return;
    }
    setPlan(id, QStringLiteral("Przywrócenie %1 do wersji v%2").arg(p.value(QStringLiteral("name")).toString()).arg(version), steps, QStringLiteral("rollback"), version);
    Q_EMIT planReady(id);
}

QVariantList Launch::plan() const
{
    QVariantList out;
    for (const Step &s : m_plan)
        out << QVariantMap{{QStringLiteral("id"), s.id}, {QStringLiteral("title"), s.title}, {QStringLiteral("detail"), s.detail},
                           {QStringLiteral("where"), s.where}, {QStringLiteral("shown"), s.shown}, {QStringLiteral("change"), s.change},
                           {QStringLiteral("state"), s.state}};
    return out;
}

QString Launch::planText() const
{
    QString t = m_planTitle + QLatin1Char('\n');
    int n = 1;
    for (const Step &s : m_plan) {
        t += QStringLiteral("\n%1. %2 — %3\n   %4%5\n").arg(n++).arg(s.title, s.detail, s.where, s.change ? QStringLiteral(" (zmiana)") : QString());
        for (const QString &line : s.shown.split(QLatin1Char('\n')))
            t += QStringLiteral("     │ ") + line + QLatin1Char('\n');
    }
    return t;
}

void Launch::cancelPlan()
{
    if (m_running)
        return;
    const QString id = m_planProject;
    m_plan.clear();
    m_planProject.clear();
    m_planTitle.clear();
    Q_EMIT planChanged();
    Q_EMIT runFinished(id, false, QStringLiteral("Anulowano — na serwerze nic się nie zmieniło."));
}

void Launch::confirmPlan()
{
    if (m_running || m_plan.isEmpty())
        return;
    m_running = true;
    m_runResult.clear();
    m_output.clear();
    Q_EMIT runningChanged();
    m_output.append(QStringLiteral("▸ ") + m_planTitle + QStringLiteral(" · ") + QDateTime::currentDateTime().toString(QStringLiteral("dd.MM.yyyy HH:mm:ss")));
    runStep(0);
}

void Launch::runStep(int i)
{
    m_step = i;
    if (i >= m_plan.size()) {
        finishRun(true, m_planKind == QLatin1String("rollback") ? QStringLiteral("Przywrócono wersję v%1.").arg(m_planVersion)
                                                                 : QStringLiteral("Wdrożono wersję v%1.").arg(m_planVersion));
        return;
    }
    Step &s = m_plan[i];
    s.state = QStringLiteral("running");
    Q_EMIT planChanged();
    Q_EMIT stepChanged(i, s.title, s.state);
    m_output.append(QStringLiteral("▸ %1. %2").arg(i + 1).arg(s.title));
    if (s.id == QLatin1String("health")) {
        runHealthStep(i, 0);
        return;
    }
    QString program = s.program;
    QStringList args = s.args;
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    m_proc = proc;
    m_stepOutput.clear();
    proc->setProcessChannelMode(QProcess::MergedChannels);
    if (!s.workDir.isEmpty())
        proc->setWorkingDirectory(s.workDir);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("PATH"), env.value(QStringLiteral("PATH")) + QStringLiteral(":") + QDir::homePath() + QStringLiteral("/.local/bin"));
    env.insert(QStringLiteral("CI"), QStringLiteral("1"));          // CLI hostingów bez pytań i animacji
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    proc->setProcessEnvironment(env);
    connect(proc, &QProcess::readyRead, this, [this, proc] {
        const QString chunk = QString::fromUtf8(proc->readAll());
        m_stepOutput += chunk;
        static const QRegularExpression ansi(QStringLiteral("\x1b\\[[0-9;?]*[A-Za-z]"));
        for (QString line : chunk.split(QLatin1Char('\n'))) {
            line.remove(ansi);
            line.remove(QLatin1Char('\r'));
            if (!line.trimmed().isEmpty())
                m_output.append(line);
        }
    });
    connect(proc, &QProcess::finished, this, [this, proc, i](int code, QProcess::ExitStatus st) {
        proc->deleteLater();
        if (!m_running || m_step != i)
            return;
        Step &s = m_plan[i];
        if (st != QProcess::NormalExit || code != 0) {
            s.state = QStringLiteral("failed");
            Q_EMIT planChanged();
            Q_EMIT stepChanged(i, s.title, s.state);
            const QString why = explain(m_stepOutput);
            finishRun(false, QStringLiteral("Krok „%1” nie udał się%2.%3").arg(s.title, st == QProcess::NormalExit ? QStringLiteral(" (kod %1)").arg(code) : QString(),
                                                                              why.isEmpty() ? QString() : QLatin1Char(' ') + why));
            return;
        }
        if (s.id == QLatin1String("hosting")) {
            // Adres wdrożenia z wyjścia CLI (ostatni adres w domenie hostingu)
            static const QRegularExpression url(QStringLiteral("https://[A-Za-z0-9.-]+\\.(netlify\\.app|vercel\\.app|pages\\.dev)[^\\s\"']*"));
            auto it = url.globalMatch(m_stepOutput);
            QString found;
            while (it.hasNext())
                found = it.next().captured(0);
            if (!found.isEmpty())
                m_plan[i].detail = found;
        }
        s.state = QStringLiteral("done");
        Q_EMIT planChanged();
        Q_EMIT stepChanged(i, s.title, s.state);
        runStep(i + 1);
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc, i](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart || !m_running || m_step != i)
            return;
        proc->deleteLater();
        m_plan[i].state = QStringLiteral("failed");
        Q_EMIT planChanged();
        finishRun(false, QStringLiteral("Nie udało się uruchomić programu %1.").arg(m_plan[i].program));
    });
    proc->start(program, args);
    if (!s.input.isEmpty())
        proc->write(s.input);
    proc->closeWriteChannel();
}

void Launch::runHealthStep(int i, int attempt)
{
    const QJsonObject *pp = find(m_planProject);
    if (!pp) {
        finishRun(false, QStringLiteral("Projekt zniknął."));
        return;
    }
    QJsonObject p = *pp;
    // Hostingi: adres z wyjścia CLI (bieżące wdrożenie), gdy nie ma własnej domeny
    QString hostingUrl;
    for (const Step &s : std::as_const(m_plan))
        if (s.id == QLatin1String("hosting") && s.detail.startsWith(QLatin1String("https://")))
            hostingUrl = s.detail;
    const auto onResult = [this, i, attempt](const QString &pid, const QVariantMap &res) {
        Q_UNUSED(pid)
        if (!m_running || m_step != i)
            return;
        const bool ok = res.value(QStringLiteral("ok")).toBool();
        m_output.append(res.value(QStringLiteral("message")).toString() + QStringLiteral(" — ") + res.value(QStringLiteral("url")).toString());
        if (!ok && attempt < 7) {
            QTimer::singleShot(1500, this, [this, i, attempt] { if (m_running && m_step == i) runHealthStep(i, attempt + 1); });
            return;
        }
        m_plan[i].state = ok ? QStringLiteral("done") : QStringLiteral("failed");
        m_plan[i].detail = res.value(QStringLiteral("message")).toString();
        Q_EMIT planChanged();
        Q_EMIT stepChanged(i, m_plan[i].title, m_plan[i].state);
        if (ok)
            runStep(i + 1);
        else
            finishRun(false, QStringLiteral("Nowa wersja działa, ale strona nie odpowiada poprawnie: %1").arg(res.value(QStringLiteral("message")).toString()));
    };
    if (!hostingUrl.isEmpty() && p.value(QStringLiteral("domain")).toString().trimmed().isEmpty()) {
        QString program = QStringLiteral("curl");
        QStringList args{QStringLiteral("-sS"), QStringLiteral("-o"), QStringLiteral("/dev/null"), QStringLiteral("-w"), QStringLiteral("%{http_code} %{time_total}"),
                         QStringLiteral("--max-time"), QStringLiteral("10"), QStringLiteral("-L"), hostingUrl};
        hostCommand(program, args);
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this, [proc, onResult, hostingUrl, this](int code, QProcess::ExitStatus) {
            const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
            proc->deleteLater();
            const int http = out.section(QLatin1Char(' '), 0, 0).toInt();
            const bool ok = code == 0 && http >= 200 && http < 400;
            onResult(m_planProject, {{QStringLiteral("ok"), ok}, {QStringLiteral("url"), hostingUrl},
                                     {QStringLiteral("message"), ok ? QStringLiteral("Strona odpowiada (HTTP %1)").arg(http) : QStringLiteral("Strona nie odpowiada (HTTP %1, curl %2)").arg(http).arg(code)}});
        });
        proc->start(program, args);
        return;
    }
    auto conn = std::make_shared<QMetaObject::Connection>();
    const QString id = m_planProject;
    *conn = connect(this, &Launch::healthChecked, this, [conn, id, onResult](const QString &pid, const QVariantMap &res) {
        if (pid != id)
            return;
        QObject::disconnect(*conn);
        onResult(pid, res);
    });
    checkHealth(id);
}

void Launch::finishRun(bool ok, const QString &message)
{
    const QString id = m_planProject;
    // Historia: która wersja działa, co jest na serwerze
    bool switched = false;
    QString url;
    for (const Step &s : std::as_const(m_plan)) {
        if ((s.id == QLatin1String("switch") || s.id == QLatin1String("hosting")) && s.state == QLatin1String("done"))
            switched = true;
        if (s.id == QLatin1String("hosting") && s.detail.startsWith(QLatin1String("https://")))
            url = s.detail;
    }
    bool healthy = true;
    for (const Step &s : std::as_const(m_plan))
        if (s.id == QLatin1String("health") && s.state != QLatin1String("done"))
            healthy = false;
    QStringList removed;
    for (const Step &s : std::as_const(m_plan))
        if (s.id == QLatin1String("cleanup") && s.state == QLatin1String("done")) {
            static const QRegularExpression kept(QStringLiteral("Zostają: (.*)"));
            removed = kept.match(s.detail).captured(1).split(QStringLiteral(", "));
        }
    for (int i = 0; i < m_projects.size(); ++i) {
        QJsonObject o = m_projects.at(i).toObject();
        if (o.value(QStringLiteral("id")).toString() != id)
            continue;
        QJsonArray history = o.value(QStringLiteral("history")).toArray();
        QJsonArray events = o.value(QStringLiteral("events")).toArray();
        const int prev = o.value(QStringLiteral("current")).toInt();
        if (m_planKind == QLatin1String("deploy")) {
            QJsonObject e{{QStringLiteral("v"), m_planVersion}, {QStringLiteral("time"), now()},
                          {QStringLiteral("status"), !switched ? QStringLiteral("failed") : healthy ? QStringLiteral("ok") : QStringLiteral("unhealthy")},
                          {QStringLiteral("onServer"), switched && o.value(QStringLiteral("target")).toString() == QLatin1String("ssh")},
                          {QStringLiteral("message"), message}};
            if (!url.isEmpty())
                e.insert(QStringLiteral("url"), url);
            // Wersja z gita (jeśli projekt jest repozytorium)
            QProcess git;
            git.setWorkingDirectory(o.value(QStringLiteral("path")).toString());
            git.start(QStringLiteral("git"), {QStringLiteral("log"), QStringLiteral("-1"), QStringLiteral("--format=%h%x09%s")});
            if (git.waitForFinished(3000) && git.exitCode() == 0) {
                const QString line = QString::fromUtf8(git.readAllStandardOutput()).trimmed();
                e.insert(QStringLiteral("commit"), line.section(QLatin1Char('\t'), 0, 0));
                e.insert(QStringLiteral("subject"), line.section(QLatin1Char('\t'), 1));
                QProcess dirty;
                dirty.setWorkingDirectory(o.value(QStringLiteral("path")).toString());
                dirty.start(QStringLiteral("git"), {QStringLiteral("status"), QStringLiteral("--porcelain")});
                if (dirty.waitForFinished(3000) && !dirty.readAllStandardOutput().trimmed().isEmpty())
                    e.insert(QStringLiteral("dirty"), true);
            }
            history.append(e);
            if (switched)
                o.insert(QStringLiteral("current"), m_planVersion);
            events.append(QJsonObject{{QStringLiteral("kind"), QStringLiteral("deploy")}, {QStringLiteral("v"), m_planVersion}, {QStringLiteral("from"), prev},
                                      {QStringLiteral("ok"), ok}, {QStringLiteral("time"), now()}, {QStringLiteral("origin"), m_planOrigin}});
        } else {
            if (switched)
                o.insert(QStringLiteral("current"), m_planVersion);
            events.append(QJsonObject{{QStringLiteral("kind"), QStringLiteral("rollback")}, {QStringLiteral("v"), m_planVersion}, {QStringLiteral("from"), prev},
                                      {QStringLiteral("ok"), ok}, {QStringLiteral("time"), now()}, {QStringLiteral("origin"), m_planOrigin}});
        }
        if (!removed.isEmpty())
            for (int k = 0; k < history.size(); ++k) {
                QJsonObject h = history.at(k).toObject();
                if (h.value(QStringLiteral("onServer")).toBool() && !removed.contains(QStringLiteral("v%1").arg(h.value(QStringLiteral("v")).toInt()))) {
                    h.insert(QStringLiteral("onServer"), false);
                    history.replace(k, h);
                }
            }
        while (events.size() > 200)
            events.removeFirst();
        o.insert(QStringLiteral("history"), history);
        o.insert(QStringLiteral("events"), events);
        m_projects.replace(i, o);
    }
    // Stare kopie wersji (hostingi) — tyle, ile wersji trzymamy
    if (const QJsonObject *pp = find(id); pp && pp->value(QStringLiteral("target")).toString() != QLatin1String("ssh")) {
        const int keep = qMax(2, pp->value(QStringLiteral("keep")).toInt(5));
        QDir snaps(dataDir() + QStringLiteral("/kopie/") + slugFor(*pp));
        QStringList dirs = snaps.entryList({QStringLiteral("v*")}, QDir::Dirs | QDir::NoDotAndDotDot);
        std::sort(dirs.begin(), dirs.end(), [](const QString &a, const QString &b) { return a.mid(1).toInt() > b.mid(1).toInt(); });
        const QString cur = QStringLiteral("v%1").arg(pp->value(QStringLiteral("current")).toInt());
        for (int k = keep; k < dirs.size(); ++k)
            if (dirs[k] != cur)
                QDir(snaps.filePath(dirs[k])).removeRecursively();
    }
    save();
    m_running = false;
    m_runResult = ok ? QStringLiteral("ok") : QStringLiteral("failed");
    m_output.append((ok ? QStringLiteral("▸ Gotowe: ") : QStringLiteral("▸ Błąd: ")) + message);
    Q_EMIT runningChanged();
    Q_EMIT planChanged();
    Q_EMIT runFinished(id, ok, message);
}

void Launch::stopRun()
{
    if (!m_running)
        return;
    if (m_proc)
        m_proc->kill();
    if (m_step >= 0 && m_step < m_plan.size()) {
        m_plan[m_step].state = QStringLiteral("failed");
        m_plan[m_step].detail = QStringLiteral("Przerwano");
    }
    finishRun(false, QStringLiteral("Przerwano."));
}

void Launch::closeRun()
{
    if (m_running)
        return;
    m_plan.clear();
    m_planTitle.clear();
    m_planProject.clear();
    m_runResult.clear();
    Q_EMIT planChanged();
    Q_EMIT runningChanged();
}

// ——— Logi produkcji ———

static QString logCommand(const QJsonObject &p, int lines, bool follow)
{
    const QString type = p.value(QStringLiteral("type")).toString();
    const QString slug = slugFor(p);
    const QJsonObject f = p.value(QStringLiteral("facts")).toObject();
    const QString engine = f.value(QStringLiteral("podman")).toString().isEmpty() ? QStringLiteral("docker") : QStringLiteral("podman");
    const QString fl = follow ? QStringLiteral(" -f") : QString();
    if (type == QLatin1String("node") || type == QLatin1String("python"))
        return QStringLiteral("journalctl -u aster-%1.service -n %2 --no-pager -o short-iso%3").arg(slug).arg(lines).arg(fl);
    if (type == QLatin1String("docker"))
        return QStringLiteral("%1 logs --tail %2%3 aster-%4 2>&1").arg(engine).arg(lines).arg(fl, slug);
    if (type == QLatin1String("compose"))
        return QStringLiteral("cd /srv/aster-launch/%1/current && %2 compose -p aster-%1 logs --tail %3%4 2>&1").arg(slug, engine).arg(lines).arg(fl);
    // Strona statyczna: dziennik Caddy
    if (f.value(QStringLiteral("systemd")).toString() == QLatin1String("yes"))
        return QStringLiteral("journalctl -u caddy.service -n %1 --no-pager -o short-iso%2").arg(lines).arg(fl);
    return QStringLiteral("echo 'Brak dziennika: serwer bez systemd'");
}

void Launch::startLiveLog(const QString &id, int lines)
{
    stopLiveLog();
    const QJsonObject *pp = find(id);
    if (!pp)
        return;
    const QJsonObject p = *pp;
    m_live.clear();
    m_liveProject = id;
    if (p.value(QStringLiteral("target")).toString() != QLatin1String("ssh")) {
        m_live.append(QStringLiteral("Logi tej strony są w panelu %1.").arg(hostingInfo(p.value(QStringLiteral("target")).toString()).value(QStringLiteral("name")).toString()));
        Q_EMIT liveLogChanged();
        return;
    }
    QString program = QStringLiteral("ssh");
    QStringList args = sshOptions(p);
    args << sshDest(p) << (needsSudo(p) ? QStringLiteral("sudo -n sh -c ") + sq(logCommand(p, qBound(1, lines, 5000), true)) : logCommand(p, qBound(1, lines, 5000), true));
    hostCommand(program, args);
    auto *proc = new QProcess(this);
    m_liveProc = proc;
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::readyRead, this, [this, proc] {
        if (m_liveProc != proc)
            return;
        for (QString line : QString::fromUtf8(proc->readAll()).split(QLatin1Char('\n'))) {
            line.remove(QLatin1Char('\r'));
            if (!line.isEmpty())
                m_live.append(line);
        }
    });
    connect(proc, &QProcess::finished, this, [this, proc](int code, QProcess::ExitStatus st) {
        if (m_liveProc == proc && st == QProcess::NormalExit && code != 0)
            m_live.append(QStringLiteral("▸ Połączenie z logami zakończone (kod %1)").arg(code));
        proc->deleteLater();
        Q_EMIT liveLogChanged();
    });
    proc->start(program, args);
    Q_EMIT liveLogChanged();
}

void Launch::stopLiveLog()
{
    if (m_liveProc) {
        QProcess *p = m_liveProc;
        m_liveProc = nullptr;
        p->kill();
    }
    Q_EMIT liveLogChanged();
}

void Launch::fetchLogs(const QString &id, int lines)
{
    const QJsonObject *pp = find(id);
    if (!pp) {
        Q_EMIT logsFetched(id, false, QStringLiteral("Nie ma takiego projektu."));
        return;
    }
    const QJsonObject p = *pp;
    if (p.value(QStringLiteral("target")).toString() != QLatin1String("ssh")) {
        Q_EMIT logsFetched(id, false, QStringLiteral("Logi tej strony są w panelu hostingu."));
        return;
    }
    runRemote(p, logCommand(p, qBound(1, lines, 5000), false), [this, id](int code, const QString &out) {
        const QString why = code != 0 ? explain(out) : QString();
        Q_EMIT logsFetched(id, code == 0, why.isEmpty() ? out : why);
    });
}

// ——— Stan i pytania ———

QJsonObject Launch::statusJson(const QString &id) const
{
    const QJsonObject *pp = find(id);
    if (!pp)
        return {};
    const QJsonObject p = *pp;
    QJsonObject s{{QStringLiteral("id"), id}, {QStringLiteral("name"), p.value(QStringLiteral("name"))}, {QStringLiteral("path"), p.value(QStringLiteral("path"))},
                  {QStringLiteral("type"), p.value(QStringLiteral("type"))}, {QStringLiteral("target"), p.value(QStringLiteral("target"))},
                  {QStringLiteral("host"), p.value(QStringLiteral("host"))}, {QStringLiteral("domain"), p.value(QStringLiteral("domain"))},
                  {QStringLiteral("url"), urlFor(id)}, {QStringLiteral("current"), p.value(QStringLiteral("current"))},
                  {QStringLiteral("lastCheck"), p.value(QStringLiteral("lastCheck"))}};
    QJsonArray versions;
    for (const QJsonValue &h : p.value(QStringLiteral("history")).toArray()) {
        const QJsonObject o = h.toObject();
        versions.append(QJsonObject{{QStringLiteral("v"), o.value(QStringLiteral("v"))}, {QStringLiteral("time"), o.value(QStringLiteral("time"))},
                                    {QStringLiteral("status"), o.value(QStringLiteral("status"))}, {QStringLiteral("commit"), o.value(QStringLiteral("commit"))},
                                    {QStringLiteral("restorable"), o.value(QStringLiteral("onServer")).toBool() || p.value(QStringLiteral("target")).toString() != QLatin1String("ssh")}});
    }
    s.insert(QStringLiteral("versions"), versions);
    return s;
}

int Launch::requestPermission(const QString &title, const QString &text, const QString &button)
{
    const int token = ++m_askToken;
    m_ask = {{QStringLiteral("token"), token}, {QStringLiteral("title"), title}, {QStringLiteral("text"), text}, {QStringLiteral("button"), button}};
    Q_EMIT askChanged();
    Q_EMIT wantsAttention();
    return token;
}

void Launch::answer(int token, bool ok)
{
    if (m_ask.value(QStringLiteral("token")).toInt() != token)
        return;
    m_ask.clear();
    Q_EMIT askChanged();
    Q_EMIT answered(token, ok);
}

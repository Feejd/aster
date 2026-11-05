#include "pulse.h"
#include "agent.h"
#include "curl.h"
#include "runner.h"
#include "secrets.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QSettings>
#include <QStringDecoder>
#include <QUrl>

QString PulseApp::s_initialFolder;
QNetworkAccessManager *PulseApp::s_nam = nullptr;

namespace {
QJsonObject toObject(const QVariantMap &m) { return QJsonObject::fromVariantMap(m); }

QString shellQuote(const QString &s)
{
    QString q = s;
    q.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + q + QLatin1Char('\'');
}
}

PulseApp *PulseApp::create(QQmlEngine *, QJSEngine *)
{
    return new PulseApp;
}

PulseApp::PulseApp(QObject *parent)
    : QObject(parent)
    , m_nam(s_nam ? s_nam : new QNetworkAccessManager(this))
{
    m_wallet = Secrets::available();
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(250);
    connect(&m_reloadTimer, &QTimer::timeout, this, &PulseApp::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadTimer, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadTimer, qOverload<>(&QTimer::start));

    QString dir;
    if (!s_initialFolder.isEmpty()) {
        dir = Workspace::forFolder(s_initialFolder);
    } else {
        const QString last = QSettings().value(QStringLiteral("workspace")).toString();
        dir = !last.isEmpty() && QFileInfo::exists(QDir(last).filePath(QStringLiteral("pulse.json"))) ? last : Workspace::defaultDir();
    }
    // Pierwsze uruchomienie: ~/Dokumenty/Pulse z przykładami
    if (!QFileInfo::exists(QDir(dir).filePath(QStringLiteral("pulse.json"))))
        Workspace::create(dir, QString(), dir == Workspace::defaultDir() || !s_initialFolder.isEmpty());
    setWorkspace(dir);
    loadHistory();
}

void PulseApp::setWorkspace(const QString &dir)
{
    QString error;
    if (!m_ws.load(dir, &error))
        setError(error);
    m_secretCache.clear();
    QSettings s;
    s.setValue(QStringLiteral("workspace"), m_ws.dir());
    QStringList recent = s.value(QStringLiteral("recent")).toStringList();
    recent.removeAll(m_ws.dir());
    recent.prepend(m_ws.dir());
    while (recent.size() > 8)
        recent.removeLast();
    s.setValue(QStringLiteral("recent"), recent);
    watch();
    Q_EMIT workspaceChanged();
    Q_EMIT collectionsChanged();
    Q_EMIT environmentsChanged();
}

void PulseApp::watch()
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    if (!m_watcher.files().isEmpty())
        m_watcher.removePaths(m_watcher.files());
    m_watcher.addPath(m_ws.dir());
    QDir().mkpath(QFileInfo(History::path()).path());
    m_watcher.addPath(QFileInfo(History::path()).path());
}

void PulseApp::reload()
{
    QString error;
    m_ws.load(m_ws.dir(), &error);
    Q_EMIT collectionsChanged();
    Q_EMIT environmentsChanged();
    loadHistory();
}

QStringList PulseApp::recentWorkspaces() const
{
    QStringList out;
    for (const QString &d : QSettings().value(QStringLiteral("recent")).toStringList())
        if (d != m_ws.dir() && QFileInfo::exists(QDir(d).filePath(QStringLiteral("pulse.json"))))
            out << d;
    return out;
}

bool PulseApp::openFolder(const QVariant &folder)
{
    const QString path = localPath(folder);
    if (path.isEmpty())
        return false;
    const QString dir = Workspace::forFolder(path);
    if (!QFileInfo::exists(QDir(dir).filePath(QStringLiteral("pulse.json"))) && !Workspace::create(dir, QString(), false)) {
        setError(QStringLiteral("Nie można utworzyć obszaru w %1").arg(dir));
        return false;
    }
    setWorkspace(dir);
    Q_EMIT message(QStringLiteral("Otwarto: %1").arg(m_ws.name()));
    return true;
}

QVariantList PulseApp::collections() const
{
    QVariantList out;
    for (const QJsonObject &c : m_ws.collections())
        out << c.toVariantMap();
    return out;
}

QJsonObject PulseApp::collectionByFile(const QString &file) const
{
    for (const QJsonObject &c : m_ws.collections())
        if (c.value(QLatin1String("file")).toString() == file)
            return c;
    return {};
}

void PulseApp::setActiveEnv(const QString &env)
{
    if (env == m_ws.activeEnvironment())
        return;
    m_ws.setActiveEnvironment(env);
    Q_EMIT environmentsChanged();
}

QStringList PulseApp::variableNames() const
{
    QStringList names;
    for (const QJsonValue &v : m_ws.environment(m_ws.activeEnvironment()).value(QLatin1String("vars")).toArray())
        names << v.toObject().value(QLatin1String("key")).toString();
    return names;
}

QString PulseApp::variableValue(const QString &name) const
{
    for (const QJsonValue &vv : m_ws.environment(m_ws.activeEnvironment()).value(QLatin1String("vars")).toArray()) {
        const QJsonObject v = vv.toObject();
        if (v.value(QLatin1String("key")).toString() == name)
            return v.value(QLatin1String("secret")).toBool() ? QStringLiteral("•••••• (w portfelu)") : v.value(QLatin1String("value")).toString();
    }
    return {};
}

QString PulseApp::preview(const QString &text) const
{
    QHash<QString, QString> vars;
    for (const QJsonValue &vv : m_ws.environment(m_ws.activeEnvironment()).value(QLatin1String("vars")).toArray()) {
        const QJsonObject v = vv.toObject();
        vars.insert(v.value(QLatin1String("key")).toString(), v.value(QLatin1String("secret")).toBool() ? QStringLiteral("•••") : v.value(QLatin1String("value")).toString());
    }
    return Vars::resolve(text, vars);
}

QHash<QString, QString> PulseApp::sendVariables(QStringList *missing)
{
    const QString env = m_ws.activeEnvironment();
    QHash<QString, QString> vars;
    bool needSecrets = false;
    for (const QJsonValue &vv : m_ws.environment(env).value(QLatin1String("vars")).toArray()) {
        const QJsonObject v = vv.toObject();
        if (v.value(QLatin1String("secret")).toBool())
            needSecrets = true;
        else
            vars.insert(v.value(QLatin1String("key")).toString(), v.value(QLatin1String("value")).toString());
    }
    if (needSecrets) {
        if (!m_secretCache.contains(env)) {
            // Odczyt z portfela raz na środowisko (przy zamkniętym portfelu system zapyta o hasło)
            QHash<QString, QString> secrets;
            QStringList miss;
            const QHash<QString, QString> all = m_ws.variables(env, &miss);
            for (const QJsonValue &vv : m_ws.environment(env).value(QLatin1String("vars")).toArray()) {
                const QJsonObject v = vv.toObject();
                const QString key = v.value(QLatin1String("key")).toString();
                if (v.value(QLatin1String("secret")).toBool() && all.contains(key))
                    secrets.insert(key, all.value(key));
            }
            m_secretCache.insert(env, secrets);
        }
        const QHash<QString, QString> secrets = m_secretCache.value(env);
        for (auto it = secrets.begin(); it != secrets.end(); ++it)
            vars.insert(it.key(), it.value());
        for (const QJsonValue &vv : m_ws.environment(env).value(QLatin1String("vars")).toArray()) {
            const QJsonObject v = vv.toObject();
            if (v.value(QLatin1String("secret")).toBool() && !secrets.contains(v.value(QLatin1String("key")).toString()) && missing)
                missing->append(v.value(QLatin1String("key")).toString());
        }
    }
    return vars;
}

bool PulseApp::busy() const
{
    return m_runner && m_runner->running();
}

void PulseApp::send(const QVariantMap &request)
{
    cancel();
    const QJsonObject req = normalizedRequest(toObject(request));
    QStringList missing, unresolved;
    const QHash<QString, QString> vars = sendVariables(&missing);
    const QJsonObject resolved = Vars::resolveRequest(req, vars, &unresolved);
    const QString env = m_ws.activeEnvironment();
    if (!m_runner)
        m_runner = new Runner(m_nam, this);
    m_runner->disconnect(this);
    connect(m_runner, &Runner::finished, this, [this, req, env, unresolved, missing](const QJsonObject &result, const QByteArray &body) {
        History::append(req, result, env, QStringLiteral("app"), m_ws.dir());
        m_body = body;
        QVariantMap r = result.toVariantMap();
        r[QStringLiteral("has")] = true;
        QStringList unr = unresolved;
        r[QStringLiteral("unresolved")] = unr;
        QStringList missingUsed;
        for (const QString &u : unresolved)
            if (missing.contains(u))
                missingUsed << u;
        r[QStringLiteral("missingSecrets")] = missingUsed;
        const QString ct = result.value(QLatin1String("contentType")).toString().toLower();
        QJsonValue json;
        m_tree.clear();
        m_responseText.clear();
        QString kind = QStringLiteral("empty");
        if (body.isEmpty()) {
            kind = QStringLiteral("empty");
        } else if (body.size() < 30 * 1024 * 1024 && AgentRun::parseJsonBody(body, ct, &json)) {
            kind = QStringLiteral("json");
            m_tree.setJson(json);
            const QByteArray pretty = json.isArray() ? QJsonDocument(json.toArray()).toJson(QJsonDocument::Indented)
                                                     : QJsonDocument(json.toObject()).toJson(QJsonDocument::Indented);
            m_responseText = QString::fromUtf8(pretty.left(2 * 1024 * 1024));
            r[QStringLiteral("viewTruncated")] = pretty.size() > 2 * 1024 * 1024;
        } else {
            QStringDecoder dec(QStringDecoder::Utf8);
            const QByteArray part = body.left(1024 * 1024);
            const QString text = dec.decode(part);
            if ((!dec.hasError() || body.size() > part.size()) && !text.contains(QChar(0)) && !ct.startsWith(QLatin1String("image/"))) {
                kind = ct.contains(QLatin1String("html")) ? QStringLiteral("html") : ct.contains(QLatin1String("xml")) ? QStringLiteral("xml") : QStringLiteral("text");
                m_responseText = text;
                r[QStringLiteral("viewTruncated")] = body.size() > part.size();
            } else {
                kind = ct.startsWith(QLatin1String("image/")) ? QStringLiteral("image") : QStringLiteral("binary");
                if (kind == QLatin1String("image") && body.size() < 8 * 1024 * 1024)
                    r[QStringLiteral("dataUrl")] = QStringLiteral("data:%1;base64,%2").arg(ct.section(QLatin1Char(';'), 0, 0), QString::fromLatin1(body.toBase64()));
            }
        }
        r[QStringLiteral("kind")] = kind;
        m_response = r;
        Q_EMIT responseChanged();
        Q_EMIT busyChanged();
        loadHistory();
    });
    m_response = {{QStringLiteral("has"), false}};
    Q_EMIT responseChanged();
    m_runner->start(resolved);
    Q_EMIT busyChanged();
}

void PulseApp::cancel()
{
    if (m_runner && m_runner->running())
        m_runner->abort();
}

void PulseApp::clearResponse()
{
    cancel();
    m_response.clear();
    m_responseText.clear();
    m_body.clear();
    m_tree.clear();
    Q_EMIT responseChanged();
}

QString PulseApp::createCollection(const QString &name)
{
    QString error;
    const QString file = m_ws.createCollection(name.trimmed().isEmpty() ? QStringLiteral("Nowa kolekcja") : name.trimmed(), &error);
    if (file.isEmpty())
        setError(error);
    Q_EMIT collectionsChanged();
    return file;
}

bool PulseApp::renameCollection(const QString &file, const QString &name)
{
    QJsonObject c = collectionByFile(file);
    if (c.isEmpty() || name.trimmed().isEmpty())
        return false;
    QString clean = name.trimmed();
    clean.replace(QLatin1Char('/'), QLatin1Char('-'));
    c[QStringLiteral("name")] = clean;
    QString error;
    const bool ok = m_ws.saveCollection(c, &error);
    if (!ok)
        setError(error);
    m_ws.load(m_ws.dir());
    Q_EMIT collectionsChanged();
    return ok;
}

bool PulseApp::deleteCollection(const QString &file)
{
    const bool ok = m_ws.removeCollection(file);
    Q_EMIT collectionsChanged();
    return ok;
}

QVariantMap PulseApp::saveRequest(const QString &file, const QVariantMap &request)
{
    QJsonObject c = collectionByFile(file);
    if (c.isEmpty()) {
        setError(QStringLiteral("Nie ma tej kolekcji"));
        return {};
    }
    QJsonObject req = normalizedRequest(toObject(request));
    req.remove(QStringLiteral("file"));
    req[QStringLiteral("name")] = req.value(QLatin1String("name")).toString().trimmed();
    QJsonArray reqs = c.value(QLatin1String("requests")).toArray();
    bool replaced = false;
    for (int i = 0; i < reqs.size(); ++i)
        if (reqs.at(i).toObject().value(QLatin1String("id")).toString() == req.value(QLatin1String("id")).toString()) {
            reqs[i] = req;
            replaced = true;
        }
    if (!replaced)
        reqs.append(req);
    c[QStringLiteral("requests")] = reqs;
    QString error;
    if (!m_ws.saveCollection(c, &error)) {
        setError(error);
        return {};
    }
    Q_EMIT collectionsChanged();
    return req.toVariantMap();
}

bool PulseApp::deleteRequest(const QString &file, const QString &id)
{
    QJsonObject c = collectionByFile(file);
    QJsonArray reqs = c.value(QLatin1String("requests")).toArray();
    for (int i = 0; i < reqs.size(); ++i)
        if (reqs.at(i).toObject().value(QLatin1String("id")).toString() == id) {
            reqs.removeAt(i);
            c[QStringLiteral("requests")] = reqs;
            const bool ok = m_ws.saveCollection(c);
            Q_EMIT collectionsChanged();
            return ok;
        }
    return false;
}

QVariantMap PulseApp::duplicateRequest(const QString &file, const QString &id)
{
    for (const QJsonValue &rv : collectionByFile(file).value(QLatin1String("requests")).toArray()) {
        QJsonObject r = rv.toObject();
        if (r.value(QLatin1String("id")).toString() != id)
            continue;
        r.remove(QStringLiteral("id"));
        r[QStringLiteral("name")] = r.value(QLatin1String("name")).toString() + QStringLiteral(" (kopia)");
        return saveRequest(file, r.toVariantMap());
    }
    return {};
}

bool PulseApp::moveRequest(const QString &fromFile, const QString &id, const QString &toFile)
{
    if (fromFile == toFile)
        return true;
    for (const QJsonValue &rv : collectionByFile(fromFile).value(QLatin1String("requests")).toArray()) {
        const QJsonObject r = rv.toObject();
        if (r.value(QLatin1String("id")).toString() != id)
            continue;
        if (saveRequest(toFile, r.toVariantMap()).isEmpty())
            return false;
        return deleteRequest(fromFile, id);
    }
    return false;
}

QVariantMap PulseApp::newRequest() const
{
    return normalizedRequest({{QStringLiteral("url"), variableNames().contains(QStringLiteral("baseUrl")) ? QStringLiteral("{{baseUrl}}/") : QString()}}).toVariantMap();
}

QVariantList PulseApp::environmentsWithSecrets()
{
    QJsonArray envs = m_ws.environments();
    QString error;
    for (int i = 0; i < envs.size(); ++i) {
        QJsonObject e = envs.at(i).toObject();
        const QString name = e.value(QLatin1String("name")).toString();
        QJsonArray vars = e.value(QLatin1String("vars")).toArray();
        for (int j = 0; j < vars.size(); ++j) {
            QJsonObject v = vars.at(j).toObject();
            if (!v.value(QLatin1String("secret")).toBool())
                continue;
            if (m_wallet)
                v[QStringLiteral("value")] = Secrets::read(Workspace::secretAttributes(m_ws.dir(), name, v.value(QLatin1String("key")).toString()), &error);
            vars[j] = v;
        }
        e[QStringLiteral("vars")] = vars;
        envs[i] = e;
    }
    if (!error.isEmpty())
        setError(error);
    return envs.toVariantList();
}

bool PulseApp::saveEnvironments(const QVariantList &list)
{
    const QJsonArray envs = QJsonArray::fromVariantList(list);
    QString error;
    bool walletOk = true;
    // Stare tajne wpisy, których już nie ma (zmieniona nazwa, usunięta zmienna) — usuń z portfela
    QSet<QString> keep;
    for (const QJsonValue &ev : envs)
        for (const QJsonValue &vv : ev.toObject().value(QLatin1String("vars")).toArray())
            if (vv.toObject().value(QLatin1String("secret")).toBool())
                keep.insert(ev.toObject().value(QLatin1String("name")).toString() + QLatin1Char('\n') + vv.toObject().value(QLatin1String("key")).toString());
    if (m_wallet) {
        for (const QJsonValue &ev : m_ws.environments())
            for (const QJsonValue &vv : ev.toObject().value(QLatin1String("vars")).toArray()) {
                const QString env = ev.toObject().value(QLatin1String("name")).toString(), key = vv.toObject().value(QLatin1String("key")).toString();
                if (vv.toObject().value(QLatin1String("secret")).toBool() && !keep.contains(env + QLatin1Char('\n') + key))
                    Secrets::write(Workspace::secretAttributes(m_ws.dir(), env, key), QString(), QString(), &error);
            }
        for (const QJsonValue &ev : envs) {
            const QString env = ev.toObject().value(QLatin1String("name")).toString();
            for (const QJsonValue &vv : ev.toObject().value(QLatin1String("vars")).toArray()) {
                const QJsonObject v = vv.toObject();
                const QString key = v.value(QLatin1String("key")).toString().trimmed();
                if (!v.value(QLatin1String("secret")).toBool() || key.isEmpty())
                    continue;
                const QString label = QStringLiteral("Aster Pulse — %1 (%2, %3)").arg(key, env, m_ws.name());
                walletOk &= Secrets::write(Workspace::secretAttributes(m_ws.dir(), env, key), label, v.value(QLatin1String("value")).toString(), &error);
            }
        }
    } else {
        // Bez portfela tajne wartości żyją tylko do zamknięcia programu
        for (const QJsonValue &ev : envs) {
            const QString env = ev.toObject().value(QLatin1String("name")).toString();
            QHash<QString, QString> secrets;
            for (const QJsonValue &vv : ev.toObject().value(QLatin1String("vars")).toArray())
                if (vv.toObject().value(QLatin1String("secret")).toBool())
                    secrets.insert(vv.toObject().value(QLatin1String("key")).toString(), vv.toObject().value(QLatin1String("value")).toString());
            m_secretCache.insert(env, secrets);
        }
    }
    if (m_wallet)
        m_secretCache.clear();
    const bool ok = m_ws.saveEnvironments(envs, &error);
    if (!m_ws.environments().isEmpty() && m_ws.environment(m_ws.activeEnvironment()).isEmpty())
        m_ws.setActiveEnvironment(m_ws.environments().first().toObject().value(QLatin1String("name")).toString());
    if (!ok || !walletOk)
        setError(error.isEmpty() ? QStringLiteral("Nie udało się zapisać środowisk") : error);
    else
        Q_EMIT message(m_wallet ? QStringLiteral("Zapisano środowiska — tajne wartości są w portfelu") : QStringLiteral("Zapisano środowiska (bez portfela tajne wartości znikną po zamknięciu)"));
    Q_EMIT environmentsChanged();
    return ok && walletOk;
}

QVariantMap PulseApp::importCurl(const QString &command) const
{
    QString error;
    const QJsonObject req = Curl::parse(command, &error);
    if (req.isEmpty())
        return {{QStringLiteral("error"), error}};
    return {{QStringLiteral("request"), req.toVariantMap()}};
}

QString PulseApp::exportCurl(const QVariantMap &request, bool resolve)
{
    QJsonObject req = normalizedRequest(toObject(request));
    if (resolve) {
        // Tajne zostają jako {{nazwa}} — polecenie można bezpiecznie wkleić do zgłoszenia czy czatu
        QHash<QString, QString> vars;
        for (const QJsonValue &vv : m_ws.environment(m_ws.activeEnvironment()).value(QLatin1String("vars")).toArray()) {
            const QJsonObject v = vv.toObject();
            if (!v.value(QLatin1String("secret")).toBool())
                vars.insert(v.value(QLatin1String("key")).toString(), v.value(QLatin1String("value")).toString());
        }
        req = Vars::resolveRequest(req, vars);
    }
    return Curl::build(req);
}

void PulseApp::copy(const QString &text) const
{
    QGuiApplication::clipboard()->setText(text);
}

QString PulseApp::clipboardText() const
{
    return QGuiApplication::clipboard()->text();
}

bool PulseApp::saveResponse(const QVariant &file)
{
    QFile f(localPath(file));
    if (!f.open(QIODevice::WriteOnly)) {
        setError(QStringLiteral("Nie można zapisać %1").arg(f.fileName()));
        return false;
    }
    f.write(m_body);
    Q_EMIT message(QStringLiteral("Zapisano odpowiedź: %1").arg(QFileInfo(f).fileName()));
    return true;
}

void PulseApp::loadHistory()
{
    m_history = History::load().toVariantList();
    Q_EMIT historyChanged();
}

void PulseApp::clearHistory()
{
    History::clear();
    loadHistory();
}

void PulseApp::externalRequestFinished()
{
    loadHistory();
}

QString PulseApp::formatJson(const QString &text) const
{
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8(), &pe);
    if (pe.error != QJsonParseError::NoError)
        return {};
    return QString::fromUtf8(doc.toJson(QJsonDocument::Indented)).trimmed();
}

QString PulseApp::jsonError(const QString &text) const
{
    if (text.trimmed().isEmpty() || text.contains(QLatin1String("{{")))
        return {};   // ze zmiennymi sprawdzamy dopiero po podstawieniu
    QJsonParseError pe;
    QJsonDocument::fromJson(text.toUtf8(), &pe);
    if (pe.error == QJsonParseError::NoError)
        return {};
    const QByteArray b = text.toUtf8().left(pe.offset);
    const int line = int(b.count('\n')) + 1;
    return QStringLiteral("Błąd JSON w wierszu %1: %2").arg(line).arg(pe.errorString());
}

QString PulseApp::localPath(const QVariant &url) const
{
    const QString s = url.toString();
    if (s.startsWith(QLatin1String("file:")))
        return QUrl(s).toLocalFile();
    return s;
}

QString PulseApp::fileName(const QString &path) const
{
    return QFileInfo(path).fileName();
}

QString PulseApp::prettyPath(const QString &path) const
{
    const QString home = QDir::homePath();
    if (path == home)
        return QStringLiteral("~");
    if (path.startsWith(home + QLatin1Char('/')))
        return QLatin1Char('~') + path.mid(home.size());
    return path;
}

QString PulseApp::cliCommand(const QString &file, const QString &requestName) const
{
    const QJsonObject c = collectionByFile(file);
    QString cmd = QStringLiteral("aster-pulse run ") + shellQuote(c.value(QLatin1String("name")).toString() + QLatin1Char('/') + requestName);
    if (!m_ws.activeEnvironment().isEmpty())
        cmd += QStringLiteral(" --env ") + shellQuote(m_ws.activeEnvironment());
    if (m_ws.dir() != Workspace::defaultDir())
        cmd += QStringLiteral(" --dir ") + shellQuote(m_ws.dir());
    return cmd;
}

void PulseApp::setError(const QString &e)
{
    m_lastError = e;
    Q_EMIT lastErrorChanged();
    if (!e.isEmpty())
        Q_EMIT message(e);
}

#include "tasks.h"
#include "projectenv.h"
#include "secretstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QHostAddress>
#include <QTcpSocket>

namespace {

constexpr int MaxLines = 20000;

QString readText(const QString &path, qint64 limit = 512 * 1024)
{
    QFile f(path);
    if (f.size() > limit || !f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll());
}

QString groupFor(const QString &name)
{
    const QString n = name.toLower();
    if (n.contains(QLatin1String("test")) || n == QLatin1String("check"))
        return QStringLiteral("test");
    if (n.contains(QLatin1String("build")) || n == QLatin1String("all") || n == QLatin1String("compile"))
        return QStringLiteral("build");
    if (n == QLatin1String("start") || n == QLatin1String("dev") || n == QLatin1String("serve") || n == QLatin1String("run")
        || n == QLatin1String("preview") || n == QLatin1String("watch"))
        return QStringLiteral("run");
    return QStringLiteral("other");
}

QVariantMap task(const QString &label, const QString &command, const QString &cwd, const QString &group, const QString &source)
{
    return {{QStringLiteral("label"), label}, {QStringLiteral("command"), command}, {QStringLiteral("cwd"), cwd},
            {QStringLiteral("group"), group}, {QStringLiteral("source"), source}};
}

const QRegularExpression &ansi()
{
    static const QRegularExpression re(QStringLiteral("\\x1B(?:\\[[0-9;?]*[ -/]*[@-~]|\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)|[()][0-9A-Za-z]|[=>78])"));
    return re;
}

} // namespace

Tasks::Tasks(QObject *parent)
    : QObject(parent)
{
    m_notify.setSingleShot(true);
    m_notify.setInterval(80);
    connect(&m_notify, &QTimer::timeout, this, [this] { Q_EMIT outputChanged(); Q_EMIT problemsChanged(); Q_EMIT processesChanged(); });
}

Tasks::~Tasks()
{
    for (Proc *p : std::as_const(m_procs)) {
        kill(p);
        delete p;
    }
}

Tasks::Proc *Tasks::find(int id) const
{
    for (Proc *p : m_procs)
        if (p->id == id)
            return p;
    return nullptr;
}

QStringList Tasks::lines() const { const Proc *p = current(); return p ? p->lines : QStringList(); }
bool Tasks::running() const { const Proc *p = current(); return p && p->proc && p->proc->state() != QProcess::NotRunning; }
QString Tasks::title() const { const Proc *p = current(); return p ? p->title : QString(); }
int Tasks::exitCode() const { const Proc *p = current(); return p ? p->exitCode : -1; }
qint64 Tasks::elapsed() const { const Proc *p = current(); return p ? p->elapsed : 0; }
int Tasks::errorCount() const { int n = 0; for (const Proc *p : m_procs) n += p->errors; return n; }
int Tasks::warningCount() const { int n = 0; for (const Proc *p : m_procs) n += p->warnings; return n; }
int Tasks::runningCount() const
{
    int n = 0;
    for (const Proc *p : m_procs)
        if (p->proc && p->proc->state() != QProcess::NotRunning)
            ++n;
    return n;
}

QVariantList Tasks::processes() const
{
    QVariantList out;
    for (const Proc *p : m_procs)
        out << QVariantMap{{QStringLiteral("id"), p->id}, {QStringLiteral("label"), p->title}, {QStringLiteral("command"), p->command},
                           {QStringLiteral("running"), p->proc && p->proc->state() != QProcess::NotRunning},
                           {QStringLiteral("exitCode"), p->exitCode}, {QStringLiteral("url"), p->url},
                           {QStringLiteral("errors"), p->errors}, {QStringLiteral("cwd"), p->cwd}};
    return out;
}

QVariantList Tasks::diagnostics(const QString &path) const
{
    QVariantList out;
    for (const Proc *p : m_procs)
        out += p->problems.value(path);
    return out;
}

QVariantList Tasks::detectOne(const QString &root) const
{
    QVariantList out;
    if (root.isEmpty())
        return out;
    const QDir dir(root);

    // Własne zadania projektu: .aster/zadania.json — [{ label, command, group, cwd }] (cwd względem folderu)
    for (const QJsonValue &v : QJsonDocument::fromJson(readText(dir.filePath(QStringLiteral(".aster/zadania.json"))).toUtf8()).array()) {
        const QJsonObject o = v.toObject();
        const QString cmd = o.value(QStringLiteral("command")).toString();
        if (cmd.isEmpty())
            continue;
        out << task(o.value(QStringLiteral("label")).toString(cmd), cmd, QDir::cleanPath(dir.filePath(o.value(QStringLiteral("cwd")).toString(QStringLiteral(".")))),
                    o.value(QStringLiteral("group")).toString(QStringLiteral("other")), QStringLiteral(".aster/zadania.json"));
    }

    // package.json — skrypty przez npm, pnpm albo yarn (wg pliku blokady)
    if (dir.exists(QStringLiteral("package.json"))) {
        const QJsonObject pkg = QJsonDocument::fromJson(readText(dir.filePath(QStringLiteral("package.json"))).toUtf8()).object();
        const QString runner = dir.exists(QStringLiteral("pnpm-lock.yaml")) ? QStringLiteral("pnpm run")
                             : dir.exists(QStringLiteral("yarn.lock")) ? QStringLiteral("yarn")
                             : dir.exists(QStringLiteral("bun.lockb")) ? QStringLiteral("bun run") : QStringLiteral("npm run");
        const QJsonObject scripts = pkg.value(QStringLiteral("scripts")).toObject();
        for (auto it = scripts.begin(); it != scripts.end(); ++it)
            out << task(it.key(), runner + QLatin1Char(' ') + it.key(), root, groupFor(it.key()), QStringLiteral("package.json"));
        if (!dir.exists(QStringLiteral("node_modules")))
            out << task(QStringLiteral("zainstaluj zależności"), runner.section(QLatin1Char(' '), 0, 0) + QStringLiteral(" install"), root,
                        QStringLiteral("other"), QStringLiteral("package.json"));
    }
    // Makefile — cele z definicji (bez zmiennych i celów specjalnych z kropką)
    for (const QString &mk : {QStringLiteral("GNUmakefile"), QStringLiteral("makefile"), QStringLiteral("Makefile")}) {
        if (!dir.exists(mk))
            continue;
        out << task(QStringLiteral("make"), QStringLiteral("make -j$(nproc)"), root, QStringLiteral("build"), mk);
        static const QRegularExpression target(QStringLiteral("^([A-Za-z0-9][A-Za-z0-9_.-]*)\\s*:(?![=:])"), QRegularExpression::MultilineOption);
        QStringList seen;
        auto it = target.globalMatch(readText(dir.filePath(mk)));
        while (it.hasNext() && seen.size() < 40) {
            const QString t = it.next().captured(1);
            if (seen.contains(t) || t.contains(QLatin1Char('.')) || t == QLatin1String("all"))
                continue;
            seen << t;
            out << task(QStringLiteral("make ") + t, QStringLiteral("make ") + t, root, groupFor(t), mk);
        }
        break;
    }
    // CMake — folder build obok źródeł
    if (dir.exists(QStringLiteral("CMakeLists.txt"))) {
        out << task(QStringLiteral("cmake: zbuduj"), QStringLiteral("cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build -j$(nproc)"),
                    root, QStringLiteral("build"), QStringLiteral("CMakeLists.txt"));
        out << task(QStringLiteral("cmake: testy"), QStringLiteral("ctest --test-dir build --output-on-failure"), root, QStringLiteral("test"),
                    QStringLiteral("CMakeLists.txt"));
        out << task(QStringLiteral("cmake: wyczyść"), QStringLiteral("cmake --build build --target clean"), root, QStringLiteral("other"),
                    QStringLiteral("CMakeLists.txt"));
    }
    if (dir.exists(QStringLiteral("meson.build"))) {
        out << task(QStringLiteral("meson: zbuduj"), QStringLiteral("[ -d build ] || meson setup build; meson compile -C build"), root,
                    QStringLiteral("build"), QStringLiteral("meson.build"));
        out << task(QStringLiteral("meson: testy"), QStringLiteral("meson test -C build"), root, QStringLiteral("test"), QStringLiteral("meson.build"));
    }
    if (dir.exists(QStringLiteral("Cargo.toml"))) {
        out << task(QStringLiteral("cargo build"), QStringLiteral("cargo build"), root, QStringLiteral("build"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo run"), QStringLiteral("cargo run"), root, QStringLiteral("run"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo test"), QStringLiteral("cargo test"), root, QStringLiteral("test"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo clippy"), QStringLiteral("cargo clippy"), root, QStringLiteral("other"), QStringLiteral("Cargo.toml"));
    }
    if (dir.exists(QStringLiteral("go.mod"))) {
        out << task(QStringLiteral("go build"), QStringLiteral("go build ./..."), root, QStringLiteral("build"), QStringLiteral("go.mod"));
        out << task(QStringLiteral("go run"), QStringLiteral("go run ."), root, QStringLiteral("run"), QStringLiteral("go.mod"));
        out << task(QStringLiteral("go test"), QStringLiteral("go test ./..."), root, QStringLiteral("test"), QStringLiteral("go.mod"));
    }
    for (const QString &jf : {QStringLiteral("justfile"), QStringLiteral("Justfile")}) {
        if (!dir.exists(jf))
            continue;
        static const QRegularExpression recipe(QStringLiteral("^@?([A-Za-z0-9_-]+)[^:=\\n]*:(?!=)"), QRegularExpression::MultilineOption);
        auto it = recipe.globalMatch(readText(dir.filePath(jf)));
        int n = 0;
        while (it.hasNext() && n++ < 40) {
            const QString r = it.next().captured(1);
            out << task(QStringLiteral("just ") + r, QStringLiteral("just ") + r, root, groupFor(r), jf);
        }
        break;
    }
    // Python: serwer WWW (FastAPI, Flask, Django), skrypty z pyproject, testy (pytest) i główny plik
    const bool py = dir.exists(QStringLiteral("pyproject.toml")) || dir.exists(QStringLiteral("setup.py")) || dir.exists(QStringLiteral("requirements.txt"))
                    || dir.exists(QStringLiteral("main.py")) || dir.exists(QStringLiteral("app.py"));
    if (py) {
        const QString deps = (readText(dir.filePath(QStringLiteral("pyproject.toml"))) + readText(dir.filePath(QStringLiteral("requirements.txt")))).toLower();
        const QString venvPy = dir.exists(QStringLiteral(".venv/bin/python")) ? QStringLiteral(".venv/bin/python") : QStringLiteral("python3");
        // Moduł z aplikacją: pierwszy plik, który tworzy FastAPI() / Flask(...)
        const auto findApp = [&](const QString &marker) -> QString {
            for (const QString &f : {QStringLiteral("main.py"), QStringLiteral("app.py"), QStringLiteral("server.py"), QStringLiteral("api.py"),
                                     QStringLiteral("app/main.py"), QStringLiteral("src/main.py"), QStringLiteral("src/app.py")}) {
                const QString t = readText(dir.filePath(f));
                static const QRegularExpression var(QStringLiteral("^(\\w+)\\s*=\\s*"), QRegularExpression::MultilineOption);
                const int at = int(t.indexOf(marker));
                if (at < 0)
                    continue;
                const int ls = int(t.lastIndexOf(QLatin1Char('\n'), at)) + 1;
                const auto m = var.match(t.mid(ls, at - ls + 1));
                QString mod = f;
                mod.chop(3);
                return mod.replace(QLatin1Char('/'), QLatin1Char('.')) + QLatin1Char(':') + (m.hasMatch() ? m.captured(1) : QStringLiteral("app"));
            }
            return {};
        };
        if (deps.contains(QLatin1String("fastapi")) || deps.contains(QLatin1String("uvicorn"))) {
            const QString app = findApp(QStringLiteral("FastAPI("));
            if (!app.isEmpty())
                out << task(QStringLiteral("uvicorn (serwer)"), venvPy + QStringLiteral(" -m uvicorn ") + app + QStringLiteral(" --reload"), root,
                            QStringLiteral("run"), QStringLiteral("FastAPI"));
        }
        if (deps.contains(QLatin1String("flask"))) {
            const QString app = findApp(QStringLiteral("Flask("));
            if (!app.isEmpty())
                out << task(QStringLiteral("flask (serwer)"), venvPy + QStringLiteral(" -m flask --app ") + app.section(QLatin1Char(':'), 0, 0)
                                                                + QStringLiteral(" run --debug"), root, QStringLiteral("run"), QStringLiteral("Flask"));
        }
        if (dir.exists(QStringLiteral("manage.py")))
            out << task(QStringLiteral("django (serwer)"), venvPy + QStringLiteral(" manage.py runserver"), root, QStringLiteral("run"), QStringLiteral("Django"));
        // [project.scripts] nazwa = "moduł:funkcja"
        const QString pp = readText(dir.filePath(QStringLiteral("pyproject.toml")));
        if (const int s = int(pp.indexOf(QLatin1String("[project.scripts]"))); s >= 0) {
            static const QRegularExpression entry(QStringLiteral("^\\s*([A-Za-z0-9_.-]+)\\s*="), QRegularExpression::MultilineOption);
            const QString sect = pp.mid(s + 17).section(QLatin1String("\n["), 0, 0);
            auto it = entry.globalMatch(sect);
            while (it.hasNext()) {
                const QString n = it.next().captured(1);
                out << task(n, n, root, groupFor(n), QStringLiteral("pyproject.toml"));
            }
        }
        if (!dir.exists(QStringLiteral(".venv")) && (dir.exists(QStringLiteral("requirements.txt")) || dir.exists(QStringLiteral("pyproject.toml"))))
            out << task(QStringLiteral("zainstaluj zależności (.venv)"),
                        dir.exists(QStringLiteral("requirements.txt"))
                            ? QStringLiteral("python3 -m venv .venv && .venv/bin/pip install -r requirements.txt")
                            : QStringLiteral("python3 -m venv .venv && .venv/bin/pip install -e ."),
                        root, QStringLiteral("other"), QStringLiteral("Python"));
        for (const QString &m : {QStringLiteral("main.py"), QStringLiteral("app.py"), QStringLiteral("manage.py")})
            if (dir.exists(m)) {
                out << task(QStringLiteral("python ") + m, QStringLiteral("python3 ") + m, root, QStringLiteral("run"), m);
                break;
            }
        if (dir.exists(QStringLiteral("tests")) || dir.exists(QStringLiteral("test")))
            out << task(QStringLiteral("pytest"), QStringLiteral("python3 -m pytest"), root, QStringLiteral("test"), QStringLiteral("Python"));
    }
    // Kolejność: budowanie, uruchamianie, testy, reszta (w grupie — kolejność z pliku)
    const QStringList order{QStringLiteral("build"), QStringLiteral("run"), QStringLiteral("test"), QStringLiteral("other")};
    std::stable_sort(out.begin(), out.end(), [&](const QVariant &a, const QVariant &b) {
        return order.indexOf(a.toMap().value(QStringLiteral("group")).toString()) < order.indexOf(b.toMap().value(QStringLiteral("group")).toString());
    });
    return out;
}

QVariantList Tasks::detect(const QString &root) const
{
    // Folder projektu i jego podfoldery z własnym projektem (frontend/, backend/, web/, api/…) — z przedrostkiem
    QVariantList out = detectOne(root);
    const QStringList skip{QStringLiteral("node_modules"), QStringLiteral("build"), QStringLiteral("dist"), QStringLiteral("target"),
                           QStringLiteral("venv"), QStringLiteral(".venv"), QStringLiteral("vendor"), QStringLiteral("third_party")};
    for (const QFileInfo &d : QDir(root).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (skip.contains(d.fileName()) || d.fileName().startsWith(QLatin1Char('.')))
            continue;
        for (QVariant v : detectOne(d.absoluteFilePath())) {
            QVariantMap m = v.toMap();
            m.insert(QStringLiteral("label"), d.fileName() + QStringLiteral(": ") + m.value(QStringLiteral("label")).toString());
            m.insert(QStringLiteral("folder"), d.fileName());
            out << m;
        }
    }
    const QStringList order{QStringLiteral("build"), QStringLiteral("run"), QStringLiteral("test"), QStringLiteral("other")};
    std::stable_sort(out.begin(), out.end(), [&](const QVariant &a, const QVariant &b) {
        return order.indexOf(a.toMap().value(QStringLiteral("group")).toString()) < order.indexOf(b.toMap().value(QStringLiteral("group")).toString());
    });
    return out;
}

// „Uruchom”: serwer deweloperski z każdego projektu (dev, start, serve, uvicorn…) — po jednym na folder
QVariantList Tasks::runTargets(const QString &root) const
{
    QVariantList out;
    QHash<QString, QVariantMap> best;
    const QStringList prefer{QStringLiteral("dev"), QStringLiteral("start"), QStringLiteral("serve"), QStringLiteral("uvicorn (serwer)"),
                             QStringLiteral("flask (serwer)"), QStringLiteral("django (serwer)"), QStringLiteral("cargo run"), QStringLiteral("go run"),
                             QStringLiteral("make run")};
    const auto rank = [&](const QVariantMap &m) {
        const QString l = m.value(QStringLiteral("label")).toString().section(QStringLiteral(": "), -1);
        const int i = int(prefer.indexOf(l));
        return i < 0 ? 100 : i;
    };
    for (const QVariant &v : detect(root)) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("group")).toString() != QLatin1String("run"))
            continue;
        const QString key = m.value(QStringLiteral("cwd")).toString();
        if (!best.contains(key) || rank(m) < rank(best.value(key)))
            best.insert(key, m);
    }
    for (const QVariantMap &m : std::as_const(best))
        out << m;
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("label")).toString() < b.toMap().value(QStringLiteral("label")).toString();
    });
    return out;
}

int Tasks::run(const QString &label, const QString &command, const QString &cwd, const QVariantMap &env)
{
    m_root = cwd;
    // To samo polecenie w tym samym folderze — nowy start w miejscu starego
    Proc *p = nullptr;
    for (Proc *q : std::as_const(m_procs))
        if (q->command == command && q->cwd == cwd)
            p = q;
    if (!p) {
        p = new Proc;
        p->id = m_nextId++;
        m_procs << p;
    }
    p->title = label;
    p->command = command;
    p->cwd = cwd;
    p->env = env;
    m_selected = p->id;
    start(p);
    return p->id;
}

void Tasks::kill(Proc *p)
{
    if (!p->proc)
        return;
    p->proc->disconnect(this);
    if (p->proc->state() != QProcess::NotRunning) {
        p->proc->terminate();
        if (!p->proc->waitForFinished(800)) {
            p->proc->kill();
            p->proc->waitForFinished(500);
        }
    }
    p->proc->deleteLater();
    p->proc = nullptr;
}

void Tasks::start(Proc *p)
{
    kill(p);
    p->lines.clear();
    p->partial.clear();
    p->problems.clear();
    p->errors = p->warnings = 0;
    p->pyLine = -1;
    p->rustSev = 0;
    p->exitCode = -1;
    p->elapsed = 0;
    p->url.clear();
    p->lines << QStringLiteral("> ") + p->command;
    auto *proc = new QProcess(this);
    p->proc = proc;
    proc->setWorkingDirectory(p->cwd);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // Bez kolorów i pytań — wyjście czyta człowiek w prostym widoku
    env.insert(QStringLiteral("TERM"), QStringLiteral("dumb"));
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    env.insert(QStringLiteral("FORCE_COLOR"), QStringLiteral("0"));
    env.insert(QStringLiteral("CLICOLOR"), QStringLiteral("0"));
    env.insert(QStringLiteral("CARGO_TERM_COLOR"), QStringLiteral("never"));
    env.insert(QStringLiteral("PYTHONUNBUFFERED"), QStringLiteral("1"));
    env.insert(QStringLiteral("GIT_TERMINAL_PROMPT"), QStringLiteral("0"));
    env.insert(QStringLiteral("BROWSER"), QStringLiteral("none"));          // serwery deweloperskie nie otwierają przeglądarki
    for (auto it = p->env.cbegin(); it != p->env.cend(); ++it)
        if (!it.key().startsWith(QLatin1String("__")))
            env.insert(it.key(), it.value().toString());
    proc->setProcessEnvironment(env);
    const int id = p->id;
    connect(proc, &QProcess::readyRead, this, [this, id, proc] { if (Proc *q = find(id)) append(q, proc->readAll()); });
    connect(proc, &QProcess::finished, this, [this, id, proc](int code, QProcess::ExitStatus st) {
        if (Proc *q = find(id)) {
            append(q, proc->readAll());
            finish(q, st == QProcess::NormalExit ? code : -2);
        }
    });
    connect(proc, &QProcess::errorOccurred, this, [this, id](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        if (Proc *q = find(id)) {
            q->lines << QStringLiteral("Nie można uruchomić powłoki");
            finish(q, 127);
        }
    });
    p->clock.start();
    // Kontener projektu albo system (z Flatpaka); „__host” w env — zawsze w systemie (zakładanie kontenera)
    const bool onHost = p->env.value(QStringLiteral("__host")).toBool();
    // Sekrety projektu z portfela: plik „export …” w /run/user, wczytany i skasowany przez powłokę przed poleceniem
    QString command = p->command;
    if (p->env.value(QStringLiteral("__secrets")).toBool())
        if (const QString f = SecretStore::instance()->writeEnvFile(); !f.isEmpty())
            command = QStringLiteral(". '%1'; rm -f '%1'; %2").arg(f, command);
    QStringList argv = onHost ? ProjectEnv::instance()->hostShell(command, p->cwd) : ProjectEnv::instance()->shell(command, p->cwd);
    if (argv.isEmpty())
        argv = {QStringLiteral("/bin/sh"), QStringLiteral("-c"), command};
    proc->start(argv.first(), argv.mid(1));
    proc->closeWriteChannel();
    Q_EMIT stateChanged();
    Q_EMIT outputChanged();
    Q_EMIT problemsChanged();
    Q_EMIT processesChanged();
}

void Tasks::stop(int id)
{
    Proc *p = id < 0 ? current() : find(id);
    if (!p || !p->proc || p->proc->state() == QProcess::NotRunning)
        return;
    p->proc->terminate();
    QTimer::singleShot(1500, p->proc, [q = p->proc] { if (q && q->state() != QProcess::NotRunning) q->kill(); });
}

void Tasks::stopAll()
{
    for (Proc *p : std::as_const(m_procs))
        stop(p->id);
}

void Tasks::rerun(int id)
{
    Proc *p = id < 0 ? current() : find(id);
    if (!p)
        return;
    m_selected = p->id;
    start(p);
}

void Tasks::clear()
{
    Proc *p = current();
    if (!p || running())
        return;
    p->lines.clear();
    Q_EMIT outputChanged();
}

void Tasks::select(int id)
{
    if (!find(id) || id == m_selected)
        return;
    m_selected = id;
    Q_EMIT stateChanged();
    Q_EMIT outputChanged();
}

void Tasks::remove(int id)
{
    Proc *p = find(id);
    if (!p)
        return;
    kill(p);
    m_procs.removeOne(p);
    delete p;
    if (m_selected == id)
        m_selected = m_procs.isEmpty() ? 0 : m_procs.last()->id;
    Q_EMIT stateChanged();
    Q_EMIT outputChanged();
    Q_EMIT problemsChanged();
    Q_EMIT processesChanged();
}

void Tasks::append(Proc *p, const QByteArray &data)
{
    if (data.isEmpty())
        return;
    QString text = p->partial + QString::fromUtf8(data);
    text.remove(ansi());
    text.remove(QLatin1Char('\r'));
    const int nl = int(text.lastIndexOf(QLatin1Char('\n')));
    p->partial = nl < 0 ? text : text.mid(nl + 1);
    if (nl >= 0) {
        const QStringList parts = text.left(nl).split(QLatin1Char('\n'));
        for (const QString &l : parts) {
            parseLine(p, l);
            checkUrl(p, l);
            p->lines << l;
        }
        if (p->lines.size() > MaxLines)
            p->lines.remove(1, p->lines.size() - MaxLines);
    }
    if (!m_notify.isActive())
        m_notify.start();
}

void Tasks::checkUrl(Proc *p, const QString &line)
{
    if (!p->url.isEmpty() || p->urlPending)
        return;
    // Vite, Next, webpack, uvicorn, Flask, Django, Rails, PHP, http.server…
    static const QRegularExpression url(QStringLiteral("(https?)://(localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1?\\]|\\[::\\]):(\\d{2,5})(/[^\\s'\"()\\[\\]<>]*)?"));
    static const QRegularExpression portOnly(QStringLiteral("(?:listening|running|started|serving|available)\\b[^\\n]*?(?:port\\s*|:)(\\d{4,5})\\b"),
                                             QRegularExpression::CaseInsensitiveOption);
    QString scheme = QStringLiteral("http"), path;
    int port = 0;
    if (const auto m = url.match(line); m.hasMatch()) {
        scheme = m.captured(1);
        port = m.captured(3).toInt();
        path = m.captured(4);
        while (path.endsWith(QLatin1Char('.')) || path.endsWith(QLatin1Char(',')))
            path.chop(1);
    } else if (const auto m2 = portOnly.match(line); m2.hasMatch() && !line.contains(QLatin1String("IPv"))
               && !line.contains(QLatin1String("database"), Qt::CaseInsensitive) && !line.contains(QLatin1String("postgres"), Qt::CaseInsensitive)) {
        port = m2.captured(1).toInt();
    }
    if (port <= 0 || port > 65535)
        return;
    // Serwer zgłasza adres zanim zacznie przyjmować połączenia — sprawdzamy, czy port odpowiada (do 15 s)
    p->urlPending = true;
    const QString u = scheme + QStringLiteral("://localhost:") + QString::number(port) + (path.isEmpty() ? QStringLiteral("/") : path);
    const int id = p->id;
    auto *tries = new int(0);
    auto *timer = new QTimer(this);
    timer->setInterval(300);
    connect(timer, &QTimer::timeout, this, [this, id, port, u, timer, tries] {
        Proc *q = find(id);
        if (!q || !q->proc || !q->url.isEmpty() || ++*tries > 50) {
            if (q)
                q->urlPending = false;
            timer->deleteLater();
            delete tries;
            return;
        }
        // IPv4 i IPv6 osobno — Node i Vite słuchają często tylko na ::1, a „localhost” nie zawsze go obejmuje
        for (const QHostAddress &addr : {QHostAddress(QHostAddress::LocalHost), QHostAddress(QHostAddress::LocalHostIPv6)}) {
            auto *s = new QTcpSocket(this);
            connect(s, &QTcpSocket::connected, this, [this, id, u, s] {
                s->deleteLater();
                if (Proc *q = find(id); q && q->url.isEmpty()) {
                    q->url = u;
                    q->urlPending = false;              // licznik prób sprząta się w następnym takcie
                    Q_EMIT processesChanged();
                    Q_EMIT urlDetected(id, q->title, u);
                }
            });
            connect(s, &QTcpSocket::errorOccurred, s, &QObject::deleteLater);
            s->connectToHost(addr, quint16(port));
        }
    });
    timer->start();
}

void Tasks::finish(Proc *p, int code)
{
    if (!p->partial.isEmpty()) {
        parseLine(p, p->partial);
        p->lines << p->partial;
        p->partial.clear();
    }
    p->exitCode = code;
    p->elapsed = p->clock.elapsed();
    p->url.clear();
    const QString secs = QString::number(p->elapsed / 1000.0, 'f', 1).replace(QLatin1Char('.'), QLatin1Char(','));
    p->lines << QString();
    p->lines << (code == 0 ? QStringLiteral("✓ Gotowe w %1 s").arg(secs)
                           : code == -2 || code == 143 ? QStringLiteral("■ Zatrzymano po %1 s").arg(secs)
                                                       : QStringLiteral("✗ Zakończone z kodem %1 po %2 s").arg(code).arg(secs));
    m_notify.stop();
    Q_EMIT outputChanged();
    Q_EMIT problemsChanged();
    Q_EMIT stateChanged();
    Q_EMIT processesChanged();
    Q_EMIT finished(p->title, code);
}

QVariantMap Tasks::locate(const QString &line) const
{
    const Proc *p = current();
    return locateIn(line, p ? p->cwd : m_root);
}

QVariantMap Tasks::locateIn(const QString &line, const QString &cwd)
{
    // gcc/clang/go/rustc/eslint: ścieżka:wiersz:kolumna; tsc: ścieżka(wiersz,kolumna); rustc: --> ścieżka:w:k; Python: File "x", line N
    static const QRegularExpression colon(QStringLiteral("^\\s*(?:-->\\s*)?((?:[A-Za-z]:)?[^\\s:()\"'][^:()\"']*?\\.[A-Za-z0-9+]+):(\\d+)(?::(\\d+))?"));
    static const QRegularExpression paren(QStringLiteral("^\\s*([^\\s(]+\\.[A-Za-z0-9]+)\\((\\d+),(\\d+)\\)"));
    static const QRegularExpression python(QStringLiteral("^\\s*File \"([^\"]+)\", line (\\d+)"));
    QRegularExpressionMatch m = colon.match(line);
    if (!m.hasMatch())
        m = paren.match(line);
    if (!m.hasMatch())
        m = python.match(line);
    if (!m.hasMatch())
        return {};
    QString path = m.captured(1);
    if (QFileInfo(path).isRelative())
        path = QDir(cwd).absoluteFilePath(path);
    path = QDir::cleanPath(path);
    if (!QFileInfo(path).isFile())
        return {};
    return {{QStringLiteral("path"), path}, {QStringLiteral("line"), std::max(0, m.captured(2).toInt() - 1)},
            {QStringLiteral("col"), std::max(0, m.captured(3).toInt() - 1)}};
}

void Tasks::parseLine(Proc *proc, const QString &line)
{
    static const QRegularExpression sev(QStringLiteral("\\b(fatal error|error|warning)(?:\\[[A-Z0-9]+\\])?\\s*(?:TS\\d+\\s*)?:\\s*(.*)$"),
                                        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression rustHead(QStringLiteral("^(error|warning)(?:\\[[A-Z0-9]+\\])?: (.*)$"));
    static const QRegularExpression pyErr(QStringLiteral("^([A-Za-z_]+(?:Error|Exception|Warning)): ?(.*)$"));
    QString &rustMsg = proc->rustMsg;
    int &rustSev = proc->rustSev;

    const auto add = [proc](const QVariantMap &loc, int severity, const QString &message, const QString &source) {
        const QString path = loc.value(QStringLiteral("path")).toString();
        QVariantList &list = proc->problems[path];
        if (list.size() > 500)
            return;
        list << QVariantMap{{QStringLiteral("line"), loc.value(QStringLiteral("line"))}, {QStringLiteral("col"), loc.value(QStringLiteral("col"))},
                            {QStringLiteral("endLine"), loc.value(QStringLiteral("line"))}, {QStringLiteral("endCol"), loc.value(QStringLiteral("col"))},
                            {QStringLiteral("severity"), severity}, {QStringLiteral("message"), message.trimmed()}, {QStringLiteral("source"), source}};
        if (severity == 1)
            ++proc->errors;
        else
            ++proc->warnings;
    };

    // Rust: komunikat w wierszu „error: …”, miejsce w następnym „--> plik:w:k”
    if (const auto r = rustHead.match(line); r.hasMatch()) {
        rustMsg = r.captured(2);
        rustSev = r.captured(1) == QLatin1String("error") ? 1 : 2;
        return;
    }
    if (line.trimmed().startsWith(QLatin1String("-->")) && rustSev) {
        const QVariantMap loc = locateIn(line, proc->cwd);
        if (!loc.isEmpty())
            add(loc, rustSev, rustMsg, QStringLiteral("rustc"));
        rustSev = 0;
        return;
    }
    // Python: ostatnie „File …, line N” przed wierszem z wyjątkiem
    if (line.trimmed().startsWith(QLatin1String("File \""))) {
        const QVariantMap loc = locateIn(line, proc->cwd);
        if (!loc.isEmpty()) {
            proc->pyFile = loc.value(QStringLiteral("path")).toString();
            proc->pyLine = loc.value(QStringLiteral("line")).toInt();
        }
        return;
    }
    if (proc->pyLine >= 0) {
        if (const auto p = pyErr.match(line); p.hasMatch()) {
            add({{QStringLiteral("path"), proc->pyFile}, {QStringLiteral("line"), proc->pyLine}, {QStringLiteral("col"), 0}}, 1,
                p.captured(1) + QStringLiteral(": ") + p.captured(2), QStringLiteral("python"));
            proc->pyLine = -1;
        }
        return;
    }
    // gcc/clang/tsc/go: miejsce i „error: …” w jednym wierszu
    const auto s = sev.match(line);
    if (!s.hasMatch())
        return;
    const QVariantMap loc = locateIn(line, proc->cwd);
    if (loc.isEmpty())
        return;
    const bool err = s.captured(1).toLower() != QLatin1String("warning");
    add(loc, err ? 1 : 2, s.captured(2), QStringLiteral("kompilator"));
}

QVariantList Tasks::problems() const
{
    QHash<QString, QVariantList> all;
    for (const Proc *p : m_procs)
        for (auto it = p->problems.cbegin(); it != p->problems.cend(); ++it)
            all[it.key()] += it.value();
    QStringList paths = all.keys();
    std::sort(paths.begin(), paths.end());
    QVariantList out;
    for (const QString &p : std::as_const(paths)) {
        const QString rel = m_root.isEmpty() || !p.startsWith(m_root + QLatin1Char('/')) ? p : p.mid(m_root.size() + 1);
        const int slash = int(rel.lastIndexOf(QLatin1Char('/')));
        out << QVariantMap{{QStringLiteral("path"), p}, {QStringLiteral("name"), rel.mid(slash + 1)},
                           {QStringLiteral("dir"), slash > 0 ? rel.left(slash) : QString()}, {QStringLiteral("items"), all.value(p)},
                           {QStringLiteral("fromTask"), true}};
    }
    return out;
}

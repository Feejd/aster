#include "harbor.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <cstdio>

Harbor *Harbor::instance = nullptr;

// Rodzaje środowisk z kreatora: toolbox z Fedorą i gotowymi narzędziami
struct Kind { const char *id, *name, *desc, *icon, *c1, *c2, *packages; };
static const Kind kKinds[] = {
    { "node", "Node.js", "node, npm, TypeScript", "braces", "#7EE8A8", "#16A34A", "nodejs npm" },
    { "python", "Python", "python3, pip i venv", "code", "#7FB2FF", "#2F5BD3", "python3 python3-pip python3-devel gcc" },
    { "go", "Go", "go i gopls", "bolt", "#7DE3F0", "#0891B2", "golang gopls" },
    { "rust", "Rust", "cargo, clippy, analyzer", "tool", "#FDBA74", "#C2410C", "rust cargo rustfmt clippy rust-analyzer gcc" },
    { "cpp", "C i C++", "gcc, CMake, gdb, clangd", "cpu", "#A5B4FC", "#4F46E5", "gcc gcc-c++ make cmake ninja-build gdb clang-tools-extra" },
    { "php", "PHP", "php i composer", "globe", "#C4B5FD", "#7C3AED", "php-cli php-mbstring php-xml php-pdo php-intl composer" },
    { "java", "Java", "OpenJDK i Maven", "disc", "#FCA5A5", "#DC2626", "java-latest-openjdk-devel maven" },
    { "ruby", "Ruby", "ruby i bundler", "star", "#F9A8D4", "#BE185D", "ruby ruby-devel rubygem-bundler gcc make" },
    { "fedora", "Pusta Fedora", "sam dnf, resztę dobierzesz", "terminal", "#CBD5E1", "#475569", "" },
};

QStringList Harbor::packagesFor(const QString &kind)
{
    for (const Kind &k : kKinds)
        if (kind == QLatin1String(k.id)) return QString::fromLatin1(k.packages).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    return {};
}

QVariantList Harbor::kinds() const
{
    QVariantList out;
    for (const Kind &k : kKinds)
        out.append(QVariantMap{
            { QStringLiteral("id"), QString::fromLatin1(k.id) },
            { QStringLiteral("name"), QString::fromUtf8(k.name) },
            { QStringLiteral("desc"), QString::fromUtf8(k.desc) },
            { QStringLiteral("icon"), QString::fromLatin1(k.icon) },
            { QStringLiteral("colors"), QStringList{ QString::fromLatin1(k.c1), QString::fromLatin1(k.c2) } },
            { QStringLiteral("packages"), QString::fromLatin1(k.packages) },
        });
    return out;
}

Harbor::Harbor(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("Aster"), QStringLiteral("aster-harbor"))
    , m_logLines(new LineModel(3000, this))
    , m_taskLines(new LineModel(600, this))
{
    instance = this;
    m_timer.setInterval(3000);
    connect(&m_timer, &QTimer::timeout, this, &Harbor::refresh);
    m_timer.start();
    QTimer::singleShot(0, this, &Harbor::refresh);
    QTimer::singleShot(0, this, &Harbor::refreshImages);
}

void Harbor::setActive(bool a)
{
    if (a == m_active) return;
    m_active = a;
    if (a) { m_timer.start(); refresh(); }
    else m_timer.stop();
    Q_EMIT activeChanged();
}

void Harbor::runAsync(const Pod::Cmd &cmd, std::function<void(int, const QByteArray &, const QString &)> done)
{
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [p, done](int code, QProcess::ExitStatus st) {
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed().section(QLatin1Char('\n'), -2);
        done(st == QProcess::NormalExit ? code : 1, p->readAllStandardOutput(), err);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [p, done, cmd](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        done(-1, {}, QStringLiteral("Nie znaleziono programu „%1”.").arg(cmd.program));
        p->deleteLater();
    });
    p->start(cmd.program, cmd.args);
}

// ——— Odświeżanie ———

void Harbor::refresh()
{
    if (m_psRunning) return;
    m_psRunning = true;
    runAsync(Pod::podman({ QStringLiteral("ps"), QStringLiteral("-a"), QStringLiteral("--format"), QStringLiteral("json") }),
             [this](int code, const QByteArray &out, const QString &err) {
        m_psRunning = false;
        m_ready = true;
        if (code == -1) {
            m_available = false;
            m_error = QStringLiteral("Podman nie jest zainstalowany.");
            m_raw.clear();
        } else if (code != 0) {
            m_available = true;
            m_error = err.isEmpty() ? QStringLiteral("Podman nie odpowiada.") : err;
        } else {
            m_available = true;
            m_error.clear();
            m_raw = Pod::parseContainers(out);
        }
        rebuild();
        const bool anyRunning = std::any_of(m_raw.cbegin(), m_raw.cend(), [](const QVariant &v) { return v.toMap().value(QStringLiteral("running")).toBool(); });
        if (anyRunning && m_active) readStats();
        else if (!anyRunning && !m_stats.isEmpty()) { m_stats.clear(); rebuild(); }
    });
}

void Harbor::readStats()
{
    if (m_statsRunning) return;
    m_statsRunning = true;
    runAsync(Pod::podman({ QStringLiteral("stats"), QStringLiteral("--no-stream"), QStringLiteral("--format"), QStringLiteral("json") }),
             [this](int code, const QByteArray &out, const QString &) {
        m_statsRunning = false;
        if (code != 0) return;
        m_stats = Pod::parseStats(out);
        rebuild();
    });
}

void Harbor::rebuild()
{
    QVariantList list;
    QMap<QString, QVariantMap> projects;
    int running = 0, toolboxes = 0;
    double cpu = 0;
    qint64 mem = 0;
    const QString home = QDir::homePath();

    for (const QVariant &v : std::as_const(m_raw)) {
        QVariantMap c = v.toMap();
        const QString name = c.value(QStringLiteral("name")).toString();
        const QVariantMap st = m_stats.value(name);
        const bool on = c.value(QStringLiteral("running")).toBool();
        if (on) ++running;
        if (c.value(QStringLiteral("toolbox")).toBool()) ++toolboxes;
        if (on && !st.isEmpty()) {
            c.insert(QStringLiteral("cpu"), st.value(QStringLiteral("cpu")));
            c.insert(QStringLiteral("mem"), st.value(QStringLiteral("mem")));
            c.insert(QStringLiteral("memText"), st.value(QStringLiteral("memText")));
            cpu += st.value(QStringLiteral("cpu")).toDouble();
            mem += st.value(QStringLiteral("mem")).toLongLong();
        }
        m_settings.beginGroup(QStringLiteral("envs/") + name);
        QString kind = m_settings.value(QStringLiteral("kind")).toString();
        const QString folder = m_settings.value(QStringLiteral("folder")).toString();
        m_settings.endGroup();
        c.insert(QStringLiteral("kind"), kind);
        c.insert(QStringLiteral("folder"), folder);
        c.insert(QStringLiteral("busy"), m_busy.contains(name));
        list.append(c);

        // Projekt compose po etykietach kontenerów
        const QString wd = c.value(QStringLiteral("workdir")).toString();
        const QString project = c.value(QStringLiteral("project")).toString();
        if (!project.isEmpty() && !wd.isEmpty()) {
            QVariantMap &p = projects[wd];
            p.insert(QStringLiteral("name"), project);
            if (!c.value(QStringLiteral("configFile")).toString().isEmpty())
                p.insert(QStringLiteral("file"), c.value(QStringLiteral("configFile")));
            QVariantList ct = p.value(QStringLiteral("containers")).toList();
            ct.append(c);
            p.insert(QStringLiteral("containers"), ct);
        }
    }
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        const bool rx = x.value(QStringLiteral("running")).toBool(), ry = y.value(QStringLiteral("running")).toBool();
        if (rx != ry) return rx;
        return x.value(QStringLiteral("name")).toString().localeAwareCompare(y.value(QStringLiteral("name")).toString()) < 0;
    });
    m_containers = list;

    // Projekty: z kontenerów + foldery dodane ręcznie
    for (const QString &f : m_settings.value(QStringLiteral("projects")).toStringList())
        if (!projects.contains(f)) projects.insert(f, QVariantMap{ { QStringLiteral("name"), QFileInfo(f).fileName() } });
    QVariantList plist;
    const QStringList saved = m_settings.value(QStringLiteral("projects")).toStringList();
    for (auto it = projects.begin(); it != projects.end(); ++it) {
        QVariantMap p = it.value();
        const QString folder = it.key();
        QString file = p.value(QStringLiteral("file")).toString();
        if (file.isEmpty() || !QFileInfo::exists(file)) file = Pod::findComposeFile(folder);
        const QVariantList cts = p.value(QStringLiteral("containers")).toList();
        QStringList names = Pod::composeServices(file);
        for (const QVariant &cv : cts) {
            const QString s = cv.toMap().value(QStringLiteral("service")).toString();
            if (!s.isEmpty() && !names.contains(s)) names << s;
        }
        QVariantList services;
        int up = 0;
        for (const QString &s : std::as_const(names)) {
            QVariantMap svc{ { QStringLiteral("name"), s }, { QStringLiteral("state"), QStringLiteral("none") }, { QStringLiteral("running"), false } };
            for (const QVariant &cv : cts) {
                const QVariantMap c = cv.toMap();
                if (c.value(QStringLiteral("service")).toString() != s) continue;
                svc.insert(QStringLiteral("container"), c.value(QStringLiteral("name")));
                svc.insert(QStringLiteral("state"), c.value(QStringLiteral("state")));
                svc.insert(QStringLiteral("running"), c.value(QStringLiteral("running")));
                svc.insert(QStringLiteral("status"), c.value(QStringLiteral("status")));
                svc.insert(QStringLiteral("ports"), c.value(QStringLiteral("ports")));
                svc.insert(QStringLiteral("image"), c.value(QStringLiteral("image")));
                svc.insert(QStringLiteral("cpu"), c.value(QStringLiteral("cpu")));
                svc.insert(QStringLiteral("memText"), c.value(QStringLiteral("memText")));
                if (c.value(QStringLiteral("running")).toBool()) ++up;
                break;
            }
            services.append(svc);
        }
        p.remove(QStringLiteral("containers"));
        p.insert(QStringLiteral("folder"), folder);
        p.insert(QStringLiteral("folderText"), homePath(folder));
        p.insert(QStringLiteral("file"), file);
        p.insert(QStringLiteral("fileName"), QFileInfo(file).fileName());
        p.insert(QStringLiteral("missing"), file.isEmpty());
        p.insert(QStringLiteral("services"), services);
        p.insert(QStringLiteral("up"), up);
        p.insert(QStringLiteral("saved"), saved.contains(folder));
        p.insert(QStringLiteral("busy"), m_busy.contains(QStringLiteral("compose:") + folder));
        plist.append(p);
    }
    m_projects = plist;

    m_summary = {
        { QStringLiteral("running"), running },
        { QStringLiteral("total"), int(m_raw.size()) },
        { QStringLiteral("toolboxes"), toolboxes },
        { QStringLiteral("cpu"), cpu },
        { QStringLiteral("mem"), mem },
        { QStringLiteral("memText"), Pod::formatBytes(mem) },
        { QStringLiteral("projects"), int(plist.size()) },
    };
    Q_UNUSED(home);
    Q_EMIT changed();
}

QVariantMap Harbor::info(const QString &name) const
{
    for (const QVariant &v : m_containers)
        if (v.toMap().value(QStringLiteral("name")).toString() == name) return v.toMap();
    return {};
}

bool Harbor::nameTaken(const QString &name) const
{
    for (const QVariant &v : m_raw)
        if (v.toMap().value(QStringLiteral("name")).toString() == name) return true;
    return false;
}

// ——— Akcje na kontenerach ———

void Harbor::containerAction(const QString &name, const QString &verb, const QString &okText)
{
    if (m_busy.contains(name)) return;
    m_busy.insert(name);
    Q_EMIT busyChanged();
    rebuild();
    QStringList args{ verb };
    if (verb == QLatin1String("rm")) args << QStringLiteral("-f");
    if (verb == QLatin1String("stop") || verb == QLatin1String("restart")) args << QStringLiteral("-t") << QStringLiteral("5");
    args << name;
    runAsync(Pod::podman(args), [this, name, verb, okText](int code, const QByteArray &, const QString &err) {
        m_busy.remove(name);
        Q_EMIT busyChanged();
        if (code == 0) {
            if (verb == QLatin1String("rm")) m_settings.remove(QStringLiteral("envs/") + name);
            Q_EMIT message(okText.arg(name));
        } else {
            Q_EMIT message(QStringLiteral("Nie udało się: ") + (err.isEmpty() ? name : err));
        }
        refresh();
        if (verb == QLatin1String("rm")) refreshImages();
        if (m_logName == name && verb != QLatin1String("stop") && verb != QLatin1String("rm"))
            QTimer::singleShot(400, this, &Harbor::followLogs);
    });
}

void Harbor::start(const QString &name) { containerAction(name, QStringLiteral("start"), QStringLiteral("Uruchomiono „%1”")); }
void Harbor::stop(const QString &name) { containerAction(name, QStringLiteral("stop"), QStringLiteral("Zatrzymano „%1”")); }
void Harbor::restart(const QString &name) { containerAction(name, QStringLiteral("restart"), QStringLiteral("Uruchomiono ponownie „%1”")); }
void Harbor::remove(const QString &name)
{
    if (m_logName == name) closeLogs();
    containerAction(name, QStringLiteral("rm"), QStringLiteral("Usunięto „%1”"));
}

static void launchOnHost(const QString &program, const QStringList &args, const QString &dir = {})
{
    // Bez --watch-bus: program ma żyć dalej po zamknięciu Harbora
    if (Pod::inFlatpak()) {
        QStringList a{ QStringLiteral("--host") };
        if (!dir.isEmpty()) a << QStringLiteral("--directory=") + dir;
        QProcess::startDetached(QStringLiteral("flatpak-spawn"), a << program << args);
    } else {
        QProcess::startDetached(program, args, dir);
    }
}

void Harbor::openTerminal(const QString &name)
{
    const QVariantMap c = info(name);
    if (c.isEmpty()) return;
    QString term = qEnvironmentVariable("ASTER_HARBOR_TERMINAL");
    if (term.isEmpty()) term = QStringLiteral("aster-terminal");
    QString folder = c.value(QStringLiteral("folder")).toString();
    if (folder.isEmpty() || !QFileInfo::exists(folder)) folder = QDir::homePath();
    QStringList args{ QStringLiteral("--workdir"), folder, QStringLiteral("-e") };
    const QString podman = qEnvironmentVariable("ASTER_HARBOR_PODMAN").isEmpty() ? QStringLiteral("podman") : qEnvironmentVariable("ASTER_HARBOR_PODMAN");
    if (c.value(QStringLiteral("toolbox")).toBool()) {
        // toolbox enter sam uruchamia zatrzymany kontener
        args << (qEnvironmentVariable("ASTER_HARBOR_TOOLBOX").isEmpty() ? QStringLiteral("toolbox") : qEnvironmentVariable("ASTER_HARBOR_TOOLBOX"))
             << QStringLiteral("enter") << name;
        launchOnHost(term, args, folder);
        Q_EMIT message(QStringLiteral("Otwieram terminal w „%1”").arg(name));
        return;
    }
    args << podman << QStringLiteral("exec") << QStringLiteral("-it") << name << QStringLiteral("sh") << QStringLiteral("-c")
         << QStringLiteral("command -v bash >/dev/null && exec bash || exec sh");
    if (c.value(QStringLiteral("running")).toBool()) {
        launchOnHost(term, args, folder);
        Q_EMIT message(QStringLiteral("Otwieram terminal w „%1”").arg(name));
        return;
    }
    Q_EMIT message(QStringLiteral("Uruchamiam „%1”…").arg(name));
    runAsync(Pod::podman({ QStringLiteral("start"), name }), [this, term, args, folder, name](int code, const QByteArray &, const QString &err) {
        if (code == 0) launchOnHost(term, args, folder);
        else Q_EMIT message(QStringLiteral("Nie udało się uruchomić „%1”: %2").arg(name, err));
        refresh();
    });
}

// ——— Logi na żywo ———

void Harbor::openLogs(const QString &name)
{
    closeLogs();
    m_logName = name;
    m_logLines->clear();
    followLogs();
}

void Harbor::followLogs()
{
    if (m_logName.isEmpty()) return;
    if (m_logProc) { m_logProc->disconnect(this); m_logProc->kill(); m_logProc->deleteLater(); m_logProc = nullptr; }
    const bool resume = m_logLines->all().size() > 0;
    m_logRest.clear();
    m_logProc = new QProcess(this);
    m_logProc->setProcessChannelMode(QProcess::MergedChannels);
    QStringList args{ QStringLiteral("logs"), QStringLiteral("-f") };
    // Po wznowieniu tylko nowe linie (od teraz), za pierwszym razem ostatnie 400
    if (resume) args << QStringLiteral("--since") << QStringLiteral("1s");
    else args << QStringLiteral("--tail") << QStringLiteral("400");
    args << m_logName;
    const Pod::Cmd cmd = Pod::podman(args);
    QProcess *p = m_logProc;
    connect(p, &QProcess::readyRead, this, [this, p] { appendLog(p->readAll()); });
    connect(p, &QProcess::finished, this, [this, p] {
        if (p != m_logProc) return;
        appendLog(p->readAll());
        if (!m_logRest.isEmpty()) appendLog("\n");
        m_logProc = nullptr;
        p->deleteLater();
        Q_EMIT logChanged();
    });
    p->start(cmd.program, cmd.args);
    Q_EMIT logChanged();
}

void Harbor::appendLog(const QByteArray &data)
{
    if (data.isEmpty()) return;
    m_logRest += data;
    const int last = m_logRest.lastIndexOf('\n');
    if (last < 0) return;
    const QList<QByteArray> lines = m_logRest.left(last).split('\n');
    m_logRest = m_logRest.mid(last + 1);
    QStringList add;
    for (const QByteArray &l : lines) add << Pod::stripAnsi(QString::fromUtf8(l));
    m_logLines->append(add);
}

void Harbor::closeLogs()
{
    if (m_logProc) { m_logProc->disconnect(this); m_logProc->kill(); m_logProc->deleteLater(); m_logProc = nullptr; }
    m_logName.clear();
    m_logLines->clear();
    m_logLines->setFilter({});
    Q_EMIT logChanged();
}

void Harbor::copyLogs()
{
    QGuiApplication::clipboard()->setText(m_logLines->all().join(QLatin1Char('\n')));
    Q_EMIT message(QStringLiteral("Logi skopiowane"));
}

// ——— Compose ———

void Harbor::composeUp(const QString &folder)
{
    QString file = Pod::findComposeFile(folder);
    for (const QVariant &v : std::as_const(m_projects))
        if (v.toMap().value(QStringLiteral("folder")).toString() == folder && !v.toMap().value(QStringLiteral("file")).toString().isEmpty())
            file = v.toMap().value(QStringLiteral("file")).toString();
    if (file.isEmpty()) { Q_EMIT message(QStringLiteral("W tym folderze nie ma pliku compose")); return; }
    const QString name = QFileInfo(folder).fileName();
    startTask(QStringLiteral("Uruchamianie „%1”").arg(name),
              { { QStringLiteral("Pobieranie obrazów i uruchamianie usług"), Pod::compose(file, { QStringLiteral("up"), QStringLiteral("-d") }), {} } },
              { { QStringLiteral("kind"), QStringLiteral("compose") }, { QStringLiteral("folder"), folder } });
}

void Harbor::composeDown(const QString &folder)
{
    QString file;
    for (const QVariant &v : std::as_const(m_projects))
        if (v.toMap().value(QStringLiteral("folder")).toString() == folder) file = v.toMap().value(QStringLiteral("file")).toString();
    if (file.isEmpty()) file = Pod::findComposeFile(folder);
    if (file.isEmpty()) { Q_EMIT message(QStringLiteral("W tym folderze nie ma pliku compose")); return; }
    const QString key = QStringLiteral("compose:") + folder;
    m_busy.insert(key);
    Q_EMIT busyChanged();
    rebuild();
    auto *p = new QProcess(this);
    p->setWorkingDirectory(folder);
    const Pod::Cmd cmd = Pod::compose(file, { QStringLiteral("down") });
    connect(p, &QProcess::finished, this, [this, p, key, folder](int code) {
        m_busy.remove(key);
        Q_EMIT busyChanged();
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed().section(QLatin1Char('\n'), -1);
        Q_EMIT message(code == 0 ? QStringLiteral("Zatrzymano „%1”").arg(QFileInfo(folder).fileName())
                                 : QStringLiteral("Nie udało się zatrzymać: ") + err);
        p->deleteLater();
        refresh();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, key](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_busy.remove(key);
        Q_EMIT busyChanged();
        Q_EMIT message(QStringLiteral("Brakuje podmana"));
        p->deleteLater();
    });
    p->start(cmd.program, cmd.args);
}

void Harbor::addProject(const QUrl &url)
{
    QString folder = url.isLocalFile() ? url.toLocalFile() : url.toString();
    if (QFileInfo(folder).isFile()) folder = QFileInfo(folder).absolutePath();
    folder = QDir::cleanPath(folder);
    if (Pod::findComposeFile(folder).isEmpty()) {
        Q_EMIT message(QStringLiteral("W folderze „%1” nie ma compose.yaml ani docker-compose.yml").arg(QFileInfo(folder).fileName()));
        return;
    }
    QStringList list = m_settings.value(QStringLiteral("projects")).toStringList();
    if (!list.contains(folder)) list << folder;
    m_settings.setValue(QStringLiteral("projects"), list);
    rebuild();
    Q_EMIT message(QStringLiteral("Dodano projekt „%1”").arg(QFileInfo(folder).fileName()));
}

void Harbor::forgetProject(const QString &folder)
{
    QStringList list = m_settings.value(QStringLiteral("projects")).toStringList();
    list.removeAll(folder);
    m_settings.setValue(QStringLiteral("projects"), list);
    rebuild();
}

// ——— Obrazy ———

void Harbor::refreshImages()
{
    runAsync(Pod::podman({ QStringLiteral("images"), QStringLiteral("--format"), QStringLiteral("json") }),
             [this](int code, const QByteArray &out, const QString &) {
        if (code != 0) return;
        QVariantList list = Pod::parseImages(out);
        std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("size")).toLongLong() > b.toMap().value(QStringLiteral("size")).toLongLong();
        });
        qint64 total = 0, unused = 0;
        int unusedCount = 0;
        for (const QVariant &v : std::as_const(list)) {
            const QVariantMap m = v.toMap();
            total += m.value(QStringLiteral("size")).toLongLong();
            if (m.value(QStringLiteral("unused")).toBool()) { unused += m.value(QStringLiteral("size")).toLongLong(); ++unusedCount; }
        }
        m_images = list;
        m_imageSummary = {
            { QStringLiteral("count"), int(list.size()) },
            { QStringLiteral("size"), total },
            { QStringLiteral("sizeText"), Pod::formatBytes(total) },
            { QStringLiteral("unusedCount"), unusedCount },
            { QStringLiteral("unused"), unused },
            { QStringLiteral("unusedText"), Pod::formatBytes(unused) },
            { QStringLiteral("busy"), m_busy.contains(QStringLiteral("images")) },
        };
        Q_EMIT imagesChanged();
    });
}

void Harbor::removeImage(const QString &id)
{
    if (m_busy.contains(id)) return;
    m_busy.insert(id);
    Q_EMIT busyChanged();
    runAsync(Pod::podman({ QStringLiteral("rmi"), id }), [this, id](int code, const QByteArray &, const QString &err) {
        m_busy.remove(id);
        Q_EMIT busyChanged();
        Q_EMIT message(code == 0 ? QStringLiteral("Usunięto obraz") : QStringLiteral("Nie udało się usunąć obrazu: ") + err);
        refreshImages();
    });
}

void Harbor::pruneImages()
{
    if (m_busy.contains(QStringLiteral("images"))) return;
    const int count = m_imageSummary.value(QStringLiteral("unusedCount")).toInt();
    const QString freed = m_imageSummary.value(QStringLiteral("unusedText")).toString();
    m_busy.insert(QStringLiteral("images"));
    m_imageSummary.insert(QStringLiteral("busy"), true);
    Q_EMIT busyChanged();
    Q_EMIT imagesChanged();
    runAsync(Pod::podman({ QStringLiteral("image"), QStringLiteral("prune"), QStringLiteral("-a"), QStringLiteral("-f") }),
             [this, count, freed](int code, const QByteArray &out, const QString &err) {
        m_busy.remove(QStringLiteral("images"));
        Q_EMIT busyChanged();
        const int removed = int(out.trimmed().isEmpty() ? 0 : out.trimmed().split('\n').size());
        if (code != 0) Q_EMIT message(QStringLiteral("Nie udało się posprzątać: ") + err);
        else if (removed == 0 && count == 0) Q_EMIT message(QStringLiteral("Nie ma nieużywanych obrazów"));
        else Q_EMIT message(QStringLiteral("Usunięto nieużywane obrazy (%1) · zwolniono ok. %2").arg(qMax(removed, count)).arg(freed));
        refreshImages();
    });
}

// ——— Nowe środowisko ———

QString Harbor::defaultFolder(const QString &name) const
{
    return QDir::home().filePath(QStringLiteral("Projekty/") + (name.isEmpty() ? QStringLiteral("projekt") : name));
}

QString Harbor::homePath(const QString &path) const
{
    const QString home = QDir::homePath();
    if (path == home) return QStringLiteral("~");
    if (path.startsWith(home + QLatin1Char('/'))) return QStringLiteral("~") + path.mid(home.size());
    return path;
}

void Harbor::createEnvironment(const QString &kind, const QString &name, const QString &folderIn)
{
    if (m_taskState == QLatin1String("running")) return;
    QString folder = folderIn.trimmed();
    if (folder.startsWith(QLatin1Char('~'))) folder = QDir::homePath() + folder.mid(1);
    const QStringList pkgs = packagesFor(kind);
    QString kindName;
    for (const Kind &k : kKinds) if (kind == QLatin1String(k.id)) kindName = QString::fromUtf8(k.name);

    QList<Step> steps;
    steps.append({ QStringLiteral("Tworzenie toolboxa (za pierwszym razem pobiera Fedorę, ok. 300 MB)"),
                   Pod::toolbox({ QStringLiteral("-y"), QStringLiteral("create"), name }),
                   [folder] { if (!folder.isEmpty()) QDir().mkpath(folder); } });
    if (!pkgs.isEmpty())
        steps.append({ QStringLiteral("Instalowanie narzędzi: ") + pkgs.join(QStringLiteral(", ")),
                       Pod::toolbox(QStringList{ QStringLiteral("run"), QStringLiteral("-c"), name, QStringLiteral("sudo"), QStringLiteral("dnf"),
                                                 QStringLiteral("install"), QStringLiteral("-y"), QStringLiteral("--setopt=install_weak_deps=False") } + pkgs),
                       {} });
    steps.append({ QStringLiteral("Sprawdzanie środowiska"),
                   Pod::toolbox({ QStringLiteral("run"), QStringLiteral("-c"), name, QStringLiteral("sh"), QStringLiteral("-c"),
                                  QStringLiteral("cat /etc/fedora-release; for t in node npm python3 pip3 go cargo rustc gcc g++ cmake php composer java mvn ruby bundle; do command -v $t >/dev/null && echo \"$t: $($t --version 2>&1 | head -n1)\"; done; true") }),
                   {} });

    startTask(QStringLiteral("Nowe środowisko: ") + kindName,
              steps,
              { { QStringLiteral("kind"), QStringLiteral("env") }, { QStringLiteral("name"), name }, { QStringLiteral("folder"), folder } },
              [this, name, kind, folder](bool ok) {
        if (!ok) return;
        m_settings.beginGroup(QStringLiteral("envs/") + name);
        m_settings.setValue(QStringLiteral("kind"), kind);
        m_settings.setValue(QStringLiteral("folder"), folder);
        m_settings.endGroup();
        refreshImages();
    });
}

void Harbor::startTask(const QString &title, const QList<Step> &steps, const QVariantMap &result, std::function<void(bool)> finished)
{
    m_taskTitle = title;
    m_steps = steps;
    m_taskSteps.clear();
    for (const Step &s : steps) m_taskSteps << s.title;
    m_taskLines->clear();
    m_taskStep = -1;
    m_taskState = QStringLiteral("running");
    m_taskResult = result;
    m_taskFinished = std::move(finished);
    runStep();
}

void Harbor::runStep()
{
    ++m_taskStep;
    if (qEnvironmentVariableIsSet("ASTER_HARBOR_DEBUG"))
        fprintf(stderr, "[zadanie] krok %d/%d\n", m_taskStep + 1, int(m_steps.size()));
    if (m_taskStep >= m_steps.size()) {
        m_taskState = QStringLiteral("done");
        if (m_taskFinished) m_taskFinished(true);
        Q_EMIT taskChanged();
        refresh();
        return;
    }
    const Step &s = m_steps.at(m_taskStep);
    if (s.before) s.before();
    m_taskRest.clear();
    m_taskProc = new QProcess(this);
    m_taskProc->setProcessChannelMode(QProcess::MergedChannels);
    const QString folder = m_taskResult.value(QStringLiteral("folder")).toString();
    if (!folder.isEmpty() && QFileInfo(folder).isDir()) m_taskProc->setWorkingDirectory(folder);
    QProcess *p = m_taskProc;
    connect(p, &QProcess::readyRead, this, [this, p] { taskOutput(p->readAll()); });
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus st) {
        taskOutput(p->readAll());
        if (!m_taskRest.isEmpty()) taskOutput("\n");
        p->deleteLater();
        m_taskProc = nullptr;
        if (st != QProcess::NormalExit || code != 0) {
            if (qEnvironmentVariableIsSet("ASTER_HARBOR_DEBUG")) fprintf(stderr, "[zadanie] błąd, kod %d\n", code);
            m_taskState = QStringLiteral("failed");
            if (m_taskFinished) m_taskFinished(false);
            Q_EMIT taskChanged();
            refresh();
            return;
        }
        runStep();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_taskLines->append({ QStringLiteral("Nie znaleziono programu „%1”.").arg(p->program()) });
        m_taskState = QStringLiteral("failed");
        p->deleteLater();
        m_taskProc = nullptr;
        if (m_taskFinished) m_taskFinished(false);
        Q_EMIT taskChanged();
    });
    p->start(s.cmd.program, s.cmd.args);
    Q_EMIT taskChanged();
}

void Harbor::taskOutput(const QByteArray &data)
{
    if (data.isEmpty()) return;
    m_taskRest += data;
    const int last = qMax(m_taskRest.lastIndexOf('\n'), m_taskRest.lastIndexOf('\r'));
    if (last < 0) return;
    QStringList add;
    for (const QByteArray &l : m_taskRest.left(last).split('\n')) {
        const QString line = Pod::stripAnsi(QString::fromUtf8(l)).trimmed();
        if (!line.isEmpty()) add << line;
    }
    m_taskRest = m_taskRest.mid(last + 1);
    if (qEnvironmentVariableIsSet("ASTER_HARBOR_DEBUG"))   // diagnostyka: wyjście zadań na stderr
        for (const QString &l : std::as_const(add)) fprintf(stderr, "[zadanie] %s\n", qPrintable(l));
    m_taskLines->append(add);
}

void Harbor::closeTask()
{
    if (m_taskProc) { m_taskProc->disconnect(this); m_taskProc->kill(); m_taskProc->deleteLater(); m_taskProc = nullptr; }
    m_taskState.clear();
    m_taskTitle.clear();
    m_taskSteps.clear();
    m_taskLines->clear();
    m_taskStep = -1;
    m_taskResult.clear();
    Q_EMIT taskChanged();
    refresh();
}

void Harbor::openFolder(const QString &path)
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void Harbor::openInCode(const QString &path)
{
    launchOnHost(QStringLiteral("aster-code"), { path }, path);
    Q_EMIT message(QStringLiteral("Otwieram w Aster Code…"));
}

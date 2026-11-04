#include "flatpak.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPointer>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QThreadPool>

static const QString remoteUrl = QStringLiteral("https://dl.flathub.org/repo/flathub.flatpakrepo");
static const QString bundleBase = QStringLiteral("https://github.com/Feejd/aster/releases/download/aplikacje/");

// flatpak podaje rozmiary po ludzku („268,5 MB”), a sklep sam je sumuje
static double parseSize(QString text)
{
    text = text.trimmed().replace(QLatin1Char(','), QLatin1Char('.')).replace(QChar(0xA0), QLatin1Char(' '));
    static const QRegularExpression re(QStringLiteral("^([0-9.]+)\\s*([kKMGT]?)i?B?"));
    const auto m = re.match(text);
    if (!m.hasMatch())
        return 0;
    const QString unit = m.captured(2).toUpper();
    const double scale = unit == QLatin1String("K") ? 1e3 : unit == QLatin1String("M") ? 1e6 : unit == QLatin1String("G") ? 1e9 : unit == QLatin1String("T") ? 1e12 : 1;
    return m.captured(1).toDouble() * scale;
}

// Komunikaty flatpaka po ludzku: to, co da się z nimi zrobić, a nie stos wywołań
static QString humanError(const QString &raw)
{
    const QString low = raw.toLower();
    if (low.contains(QLatin1String("no space")) || low.contains(QLatin1String("not enough")))
        return QStringLiteral("Brakuje miejsca na dysku. Zwolnij trochę w zakładce Twój komputer → Porządki.");
    if (low.contains(QLatin1String("resolve")) || low.contains(QLatin1String("could not connect")) || low.contains(QLatin1String("network"))
        || low.contains(QLatin1String("timeout")) || low.contains(QLatin1String("timed out")))
        return QStringLiteral("Nie ma połączenia z internetem. Spróbuj, gdy wróci.");
    if (low.contains(QLatin1String("nothing matches")) || low.contains(QLatin1String("no remote refs")))
        return QStringLiteral("Tego programu nie ma w wersji na ten komputer.");
    if (low.contains(QLatin1String("authorization")) || low.contains(QLatin1String("not allowed")))
        return QStringLiteral("Ten program jest zainstalowany dla całego systemu i wymaga hasła administratora.");
    return raw.isEmpty() ? QStringLiteral("Nie udało się.") : raw;
}

static QProcessEnvironment cEnv()
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    return env;
}

Flatpak::Flatpak(QObject *parent)
    : QObject(parent)
{
    m_net.setTransferTimeout(60000);
    readWebApps();
    refresh();
}

bool Flatpak::available() const { return !QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty(); }
bool Flatpak::webAppsAvailable() const { return !QStandardPaths::findExecutable(QStringLiteral("aster-webapps")).isEmpty(); }
bool Flatpak::hasExecutable(const QString &exec) const { return !QStandardPaths::findExecutable(exec).isEmpty(); }

QString Flatpak::arch() const
{
    const QString cpu = QSysInfo::currentCpuArchitecture();
    return cpu == QLatin1String("arm64") ? QStringLiteral("aarch64") : cpu;
}

double Flatpak::memoryGb() const
{
    QFile f(QStringLiteral("/proc/meminfo"));
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    static const QRegularExpression re(QStringLiteral("MemTotal:\\s+(\\d+)"));
    const auto m = re.match(QString::fromLatin1(f.readAll()));
    return m.hasMatch() ? m.captured(1).toDouble() / 1048576.0 : 0;
}

double Flatpak::diskFree() const { return double(QStorageInfo(QDir::homePath()).bytesAvailable()); }

void Flatpak::capture(const QStringList &args, std::function<void(const QString &)> done)
{
    auto *p = new QProcess(this);
    p->setProcessEnvironment(cEnv());
    connect(p, &QProcess::finished, this, [p, done] {
        done(QString::fromUtf8(p->readAllStandardOutput()));
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            done(QString());
            p->deleteLater();
        }
    });
    p->start(QStringLiteral("flatpak"), args);
}

void Flatpak::refresh()
{
    readWebApps();
    if (!available())
        return;
    // Zainstalowane programy (z obu miejsc: użytkownika i systemu)
    capture({QStringLiteral("list"), QStringLiteral("--app"), QStringLiteral("--columns=application,name,version,size,origin,installation,runtime")},
            [this](const QString &out) {
        QStringList ids;
        QVariantList apps;
        for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList c = line.split(QLatin1Char('\t'));
            if (c.size() < 6 || ids.contains(c.at(0)))
                continue;
            ids << c.at(0);
            apps.append(QVariantMap{{QStringLiteral("id"), c.at(0)}, {QStringLiteral("name"), c.at(1)}, {QStringLiteral("version"), c.at(2)},
                                    {QStringLiteral("size"), parseSize(c.at(3))}, {QStringLiteral("origin"), c.at(4)},
                                    {QStringLiteral("installation"), c.at(5)}, {QStringLiteral("runtime"), c.value(6)}});
        }
        m_installed = ids;
        m_apps = apps;
        Q_EMIT installedChanged();
    });

    // Biblioteki wspólne (żeby uczciwie policzyć, ile naprawdę pobierze się przy instalacji)
    capture({QStringLiteral("list"), QStringLiteral("--runtime"), QStringLiteral("--columns=ref,size")}, [this](const QString &out) {
        QVariantMap map;
        for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList c = line.split(QLatin1Char('\t'));
            if (c.size() < 2)
                continue;
            map.insert(c.at(0), parseSize(c.at(1)));   // np. org.gnome.Platform/x86_64/51
        }
        m_runtimes = map;
        Q_EMIT runtimesChanged();
    });

    // Dostępne aktualizacje
    capture({QStringLiteral("remote-ls"), QStringLiteral("--updates"), QStringLiteral("--app"),
             QStringLiteral("--columns=application,version,download-size")}, [this](const QString &out) {
        QStringList ids;
        QVariantList info;
        for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList c = line.split(QLatin1Char('\t'));
            if (c.isEmpty() || c.at(0).trimmed().isEmpty() || ids.contains(c.at(0)))
                continue;
            ids << c.at(0).trimmed();
            info.append(QVariantMap{{QStringLiteral("id"), ids.last()}, {QStringLiteral("version"), c.value(1)},
                                    {QStringLiteral("size"), parseSize(c.value(2))}});
        }
        m_updates = ids;
        m_updateInfo = info;
        Q_EMIT updatesChanged();
    });
}

// Ile danych zostawia program w ~/.var/app i kiedy ostatnio coś tam zapisał (w osobnym wątku: dysk bywa wolny)
void Flatpak::refreshUsage()
{
    const QStringList ids = m_installed;
    QPointer<Flatpak> self(this);
    QThreadPool::globalInstance()->start([ids, self] {
        QVariantMap usage;
        const QString root = QDir::homePath() + QStringLiteral("/.var/app/");
        for (const QString &id : ids) {
            qint64 total = 0;
            QDateTime newest;
            QDirIterator it(root + id, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                it.next();
                const QFileInfo info = it.fileInfo();
                total += info.size();
                if (!newest.isValid() || info.lastModified() > newest)
                    newest = info.lastModified();
            }
            usage.insert(id, QVariantMap{{QStringLiteral("data"), double(total)},
                                         {QStringLiteral("lastUsed"), newest.isValid() ? double(newest.toMSecsSinceEpoch()) : 0.0}});
        }
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, usage] {
            if (!self)
                return;
            self->m_usage = usage;
            Q_EMIT self->usageChanged();
        }, Qt::QueuedConnection);
    });
}

void Flatpak::readWebApps()
{
    QVariantMap map;
    const QString root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/webapps");
    for (const QString &id : QDir(root).entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        QFile f(root + QLatin1Char('/') + id + QStringLiteral("/app.json"));
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QString url = QJsonDocument::fromJson(f.readAll()).object().value(QStringLiteral("url")).toString();
        if (!url.isEmpty())
            map.insert(url, id);
    }
    if (map != m_webApps) {
        m_webApps = map;
        Q_EMIT webAppsChanged();
    }
}

void Flatpak::install(const QString &appId) { enqueue({QStringLiteral("install"), appId, {}}); }
void Flatpak::installBundle(const QString &appId, const QString &key) { enqueue({QStringLiteral("bundle"), appId, {key}}); }
void Flatpak::uninstall(const QString &appId, bool deleteData)
{
    enqueue({QStringLiteral("uninstall"), appId, deleteData ? QStringList{QStringLiteral("--delete-data")} : QStringList{}});
}
void Flatpak::update(const QString &appId) { enqueue({QStringLiteral("update"), appId, {}}); }
void Flatpak::updateAll() { enqueue({QStringLiteral("update"), QStringLiteral("*"), {}}); }
void Flatpak::rollback(const QString &appId) { enqueue({QStringLiteral("rollback"), appId, {}}); }
void Flatpak::pruneRuntimes() { enqueue({QStringLiteral("prune"), QStringLiteral("porzadki"), {}}); }
void Flatpak::addWebApp(const QString &key, const QString &url, const QString &name, const QString &category, const QString &color)
{
    QStringList args = {QStringLiteral("--add"), url, QStringLiteral("--name"), name, QStringLiteral("--category"), category};
    if (!color.isEmpty())
        args << QStringLiteral("--color") << color;
    enqueue({QStringLiteral("webadd"), key, args});
}
void Flatpak::removeWebApp(const QString &key, const QString &id) { enqueue({QStringLiteral("webremove"), key, {id}}); }

void Flatpak::launch(const QString &appId) { QProcess::startDetached(QStringLiteral("flatpak"), {QStringLiteral("run"), appId}); }
void Flatpak::launchWebApp(const QString &id) { QProcess::startDetached(QStringLiteral("aster-webapps"), {QStringLiteral("--run"), id}); }
void Flatpak::launchExecutable(const QString &exec) { QProcess::startDetached(exec, {}); }

QVariantList Flatpak::activity() const
{
    QVariantList out;
    const auto add = [this, &out](const Job &j, double value) {
        out.append(QVariantMap{{QStringLiteral("appId"), j.appId}, {QStringLiteral("action"), j.action}, {QStringLiteral("value"), value}});
    };
    if (m_running)
        add(m_current, m_progress.value(m_current.appId, 0.0).toDouble());
    for (const Job &j : m_queue)
        add(j, -1);
    return out;
}

void Flatpak::setProgress(const QString &appId, double value)
{
    if (appId.isEmpty())
        return;
    if (value < -1.5)
        m_progress.remove(appId);
    else
        m_progress.insert(appId, value);
    Q_EMIT progressChanged();
}

void Flatpak::enqueue(const Job &job)
{
    for (const Job &j : std::as_const(m_queue))
        if (j.action == job.action && j.appId == job.appId)
            return;
    if (m_running && m_current.action == job.action && m_current.appId == job.appId)
        return;
    m_queue.append(job);
    setProgress(job.appId, -1);
    if (!m_running)
        startNext();
}

void Flatpak::runProcess(const QString &program, const QStringList &args)
{
    m_proc = new QProcess(this);
    m_proc->setProcessEnvironment(cEnv());
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_proc, &QProcess::readyRead, this, [this] { parseOutput(m_proc->readAll()); });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        m_proc->deleteLater();
        finishJob(ok, ok ? QString() : humanError(m_lastError));
    });
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_proc->deleteLater();
            finishJob(false, QStringLiteral("Brakuje składnika systemu potrzebnego do tej operacji."));
        }
    });
    m_proc->start(program, args);
}

void Flatpak::finishJob(bool ok, const QString &message)
{
    const Job job = m_current;
    m_running = false;
    setProgress(job.appId, -2);
    Q_EMIT finished(job.appId, job.action, ok, message);
    // Nowe programy od razu w Starcie
    if (ok)
        QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
    refresh();
    startNext();
}

void Flatpak::startNext()
{
    if (m_queue.isEmpty())
        return;
    m_current = m_queue.takeFirst();
    m_running = true;
    m_lastError.clear();
    setProgress(m_current.appId, 0);

    const QString &action = m_current.action;
    const QString yes = QStringLiteral("-y"), non = QStringLiteral("--noninteractive"), user = QStringLiteral("--user");

    // Flathub dodajemy do konta użytkownika przy pierwszej instalacji (nic się nie dzieje, gdy już jest)
    if (action == QLatin1String("install") || action == QLatin1String("bundle"))
        QProcess::execute(QStringLiteral("flatpak"), {QStringLiteral("remote-add"), user, QStringLiteral("--if-not-exists"), QStringLiteral("flathub"), remoteUrl});

    if (action == QLatin1String("install")) {
        runProcess(QStringLiteral("flatpak"), {QStringLiteral("install"), user, yes, non, QStringLiteral("flathub"), m_current.appId});
    } else if (action == QLatin1String("bundle")) {
        downloadBundle();
    } else if (action == QLatin1String("uninstall")) {
        // Bez --user: program mógł przyjść z systemu; polkit zapyta tylko wtedy
        QStringList args = {QStringLiteral("uninstall"), yes, non};
        args << m_current.args << m_current.appId;
        runProcess(QStringLiteral("flatpak"), args);
    } else if (action == QLatin1String("update")) {
        QStringList args = {QStringLiteral("update"), user, yes, non};
        if (m_current.appId != QLatin1String("*"))
            args << m_current.appId;
        runProcess(QStringLiteral("flatpak"), args);
    } else if (action == QLatin1String("prune")) {
        runProcess(QStringLiteral("flatpak"), {QStringLiteral("uninstall"), user, yes, non, QStringLiteral("--unused")});
    } else if (action == QLatin1String("webadd") || action == QLatin1String("webremove")) {
        runProcess(QStringLiteral("aster-webapps"), action == QLatin1String("webadd") ? m_current.args
                                                                                     : QStringList{QStringLiteral("--remove"), m_current.args.value(0)});
    } else if (action == QLatin1String("rollback")) {
        // Historia programu z repozytorium: wracamy do pierwszego wydania innego niż zainstalowane
        const QString id = m_current.appId;
        capture({QStringLiteral("info"), user, QStringLiteral("--show-commit"), id}, [this, id](const QString &current) {
            capture({QStringLiteral("remote-info"), QStringLiteral("--user"), QStringLiteral("--log"), QStringLiteral("flathub"), id}, [this, id, current](const QString &log) {
                static const QRegularExpression re(QStringLiteral("Commit:\\s*([0-9a-f]{64})"));
                QString target;
                auto it = re.globalMatch(log);
                while (it.hasNext()) {
                    const QString commit = it.next().captured(1);
                    if (commit != current.trimmed()) {
                        target = commit;
                        break;
                    }
                }
                if (target.isEmpty()) {
                    finishJob(false, QStringLiteral("Nie ma wcześniejszej wersji, do której można wrócić."));
                    return;
                }
                runProcess(QStringLiteral("flatpak"), {QStringLiteral("update"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive"),
                                                       QStringLiteral("--commit=") + target, id});
            });
        });
    } else {
        finishJob(false);
    }
}

// Paczka Aster: pobieramy plik .flatpak z wydania (pierwsze 40% paska), potem instalacja jak w tools/install-apps.sh
void Flatpak::downloadBundle()
{
    const QString key = m_current.args.value(0);
    QNetworkRequest req{QUrl(bundleBase + key + QLatin1Char('-') + arch() + QStringLiteral(".flatpak"))};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    auto *dir = new QTemporaryDir;
    const QString path = dir->filePath(key + QStringLiteral(".flatpak"));
    auto *file = new QFile(path, this);
    if (!dir->isValid() || !file->open(QIODevice::WriteOnly)) {
        delete dir;
        file->deleteLater();
        finishJob(false, QStringLiteral("Brakuje miejsca na dysku."));
        return;
    }
    QNetworkReply *reply = m_net.get(req);
    connect(reply, &QNetworkReply::readyRead, this, [reply, file] { file->write(reply->readAll()); });
    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        if (total > 0)
            setProgress(m_current.appId, 0.4 * double(got) / double(total));
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, file, dir, path] {
        reply->deleteLater();
        file->close();
        file->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            delete dir;
            finishJob(false, reply->error() == QNetworkReply::ContentNotFoundError ? QStringLiteral("Tej aplikacji nie ma jeszcze w wersji na ten komputer.")
                                                                                   : humanError(QStringLiteral("network")));
            return;
        }
        runProcess(QStringLiteral("flatpak"), {QStringLiteral("install"), QStringLiteral("--user"), QStringLiteral("--reinstall"), QStringLiteral("-y"),
                                               QStringLiteral("--noninteractive"), path});
        connect(m_proc, &QProcess::finished, this, [dir] { delete dir; });
    });
}

void Flatpak::parseOutput(const QByteArray &chunk)
{
    // Linie typu „Installing 2/3… ███▌ 45%  3,1 MB/s” (odświeżane przez \r)
    const QString text = QString::fromUtf8(chunk);
    static const QRegularExpression lineRe(QStringLiteral("[\\r\\n]"));
    static const QRegularExpression stepRe(QStringLiteral("(\\d+)/(\\d+)"));
    static const QRegularExpression pctRe(QStringLiteral("(\\d{1,3})%"));
    static const QRegularExpression errRe(QStringLiteral("(?:error|Error|błąd|Błąd):\\s*(.+)"));
    const bool bundle = m_current.action == QLatin1String("bundle");
    for (const QString &line : text.split(lineRe, Qt::SkipEmptyParts)) {
        const auto e = errRe.match(line);
        if (e.hasMatch())
            m_lastError = e.captured(1).trimmed();
        auto pm = pctRe.globalMatch(line);
        int pct = -1;
        while (pm.hasNext())
            pct = pm.next().captured(1).toInt();
        if (pct < 0)
            continue;
        double value = pct / 100.0;
        const auto s = stepRe.match(line);
        if (s.hasMatch() && s.captured(2).toInt() > 0) {
            const int step = s.captured(1).toInt(), steps = s.captured(2).toInt();
            value = (step - 1 + value) / steps;
        }
        if (bundle)
            value = 0.4 + 0.6 * value;
        setProgress(m_current.appId, qBound(0.0, value, 1.0));
    }
}

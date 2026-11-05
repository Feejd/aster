#include "agent.h"
#include "podman.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSettings>
#include <cstdio>

Agent::Agent(QObject *parent)
    : QObject(parent)
{
    m_idle.setSingleShot(true);
    connect(&m_idle, &QTimer::timeout, qApp, &QCoreApplication::quit);
}

void Agent::setIdleQuit(int ms)
{
    m_idle.setInterval(ms);
    m_idle.start();
}

static QString toJson(const QJsonArray &a, bool pretty = false)
{
    return QString::fromUtf8(QJsonDocument(a).toJson(pretty ? QJsonDocument::Indented : QJsonDocument::Compact));
}

static QJsonArray listArray(QString *err)
{
    QByteArray out;
    if (Pod::run(Pod::podman({ QStringLiteral("ps"), QStringLiteral("-a"), QStringLiteral("--format"), QStringLiteral("json") }), &out, err) != 0)
        return {};
    const QVariantList cts = Pod::parseContainers(out);
    QHash<QString, QVariantMap> stats;
    bool anyRunning = false;
    for (const QVariant &v : cts) anyRunning |= v.toMap().value(QStringLiteral("running")).toBool();
    if (anyRunning) {
        QByteArray s;
        if (Pod::run(Pod::podman({ QStringLiteral("stats"), QStringLiteral("--no-stream"), QStringLiteral("--format"), QStringLiteral("json") }), &s, nullptr, 15000) == 0)
            stats = Pod::parseStats(s);
    }
    QSettings settings(QStringLiteral("Aster"), QStringLiteral("aster-harbor"));
    QJsonArray a;
    for (const QVariant &v : cts) {
        const QVariantMap c = v.toMap();
        const QString name = c.value(QStringLiteral("name")).toString();
        QJsonObject o{
            { QStringLiteral("name"), name },
            { QStringLiteral("id"), c.value(QStringLiteral("id")).toString() },
            { QStringLiteral("kind"), c.value(QStringLiteral("toolbox")).toBool() ? QStringLiteral("toolbox")
                                     : !c.value(QStringLiteral("project")).toString().isEmpty() ? QStringLiteral("compose") : QStringLiteral("container") },
            { QStringLiteral("state"), c.value(QStringLiteral("state")).toString() },
            { QStringLiteral("running"), c.value(QStringLiteral("running")).toBool() },
            { QStringLiteral("status"), c.value(QStringLiteral("status")).toString() },
            { QStringLiteral("image"), c.value(QStringLiteral("image")).toString() },
            { QStringLiteral("ports"), c.value(QStringLiteral("ports")).toString() },
        };
        if (!c.value(QStringLiteral("project")).toString().isEmpty()) {
            o.insert(QStringLiteral("project"), c.value(QStringLiteral("project")).toString());
            o.insert(QStringLiteral("service"), c.value(QStringLiteral("service")).toString());
            o.insert(QStringLiteral("projectFolder"), c.value(QStringLiteral("workdir")).toString());
        }
        const QString env = settings.value(QStringLiteral("envs/") + name + QStringLiteral("/kind")).toString();
        if (!env.isEmpty()) o.insert(QStringLiteral("environment"), env);
        const QString folder = settings.value(QStringLiteral("envs/") + name + QStringLiteral("/folder")).toString();
        if (!folder.isEmpty()) o.insert(QStringLiteral("folder"), folder);
        if (stats.contains(name)) {
            o.insert(QStringLiteral("cpu"), stats[name].value(QStringLiteral("cpu")).toDouble());
            o.insert(QStringLiteral("memory"), stats[name].value(QStringLiteral("memText")).toString());
        }
        a.append(o);
    }
    return a;
}

QString Agent::list(QString *err)
{
    err->clear();
    const QJsonArray a = listArray(err);
    return err->isEmpty() ? toJson(a) : QString();
}

QString Agent::images(QString *err)
{
    QByteArray out;
    if (Pod::run(Pod::podman({ QStringLiteral("images"), QStringLiteral("--format"), QStringLiteral("json") }), &out, err) != 0)
        return {};
    QJsonArray a;
    for (const QVariant &v : Pod::parseImages(out)) {
        const QVariantMap m = v.toMap();
        a.append(QJsonObject{
            { QStringLiteral("id"), m.value(QStringLiteral("id")).toString() },
            { QStringLiteral("name"), m.value(QStringLiteral("fullName")).toString() },
            { QStringLiteral("size"), m.value(QStringLiteral("sizeText")).toString() },
            { QStringLiteral("containers"), m.value(QStringLiteral("containers")).toInt() },
            { QStringLiteral("unused"), m.value(QStringLiteral("unused")).toBool() },
        });
    }
    return toJson(a);
}

QString Agent::logs(const QString &name, int lines, QString *err)
{
    QByteArray out;
    Pod::Cmd cmd = Pod::podman({ QStringLiteral("logs"), QStringLiteral("--tail"), QString::number(lines > 0 ? qMin(lines, 5000) : 100), name });
    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(cmd.program, cmd.args);
    if (!p.waitForStarted(5000)) { *err = QStringLiteral("Podman nie jest zainstalowany."); return {}; }
    p.waitForFinished(20000);
    out = p.readAll();
    if (p.exitCode() != 0) { *err = QString::fromUtf8(out).trimmed().section(QLatin1Char('\n'), -1); return {}; }
    QStringList res;
    for (const QByteArray &l : out.split('\n')) res << Pod::stripAnsi(QString::fromUtf8(l));
    while (!res.isEmpty() && res.last().isEmpty()) res.removeLast();
    return res.join(QLatin1Char('\n'));
}

QString Agent::action(const QString &verb, const QString &name, QString *err)
{
    QStringList args{ verb };
    if (verb != QLatin1String("start")) args << QStringLiteral("-t") << QStringLiteral("5");
    args << name;
    if (Pod::run(Pod::podman(args), nullptr, err, 60000) != 0) return {};
    err->clear();
    return QStringLiteral("ok");
}

QString Agent::reply(const QString &result, const QString &err)
{
    if (m_idle.interval() > 0) m_idle.start();
    if (!err.isEmpty() && calledFromDBus()) sendErrorReply(QDBusError::Failed, err);
    return result;
}

QString Agent::List() { QString e; const QString r = list(&e); return reply(r, e); }
QString Agent::Images() { QString e; const QString r = images(&e); return reply(r, e); }
QString Agent::Logs(const QString &name, int lines) { QString e; const QString r = logs(name, lines, &e); return reply(r, e); }
QString Agent::Start(const QString &name) { QString e; const QString r = action(QStringLiteral("start"), name, &e); return reply(r, e); }
QString Agent::Stop(const QString &name) { QString e; const QString r = action(QStringLiteral("stop"), name, &e); return reply(r, e); }
QString Agent::Restart(const QString &name) { QString e; const QString r = action(QStringLiteral("restart"), name, &e); return reply(r, e); }

// ——— Wiersz poleceń ———

static void print(const QString &s, FILE *f = stdout)
{
    const QByteArray b = s.toUtf8();
    fwrite(b.constData(), 1, size_t(b.size()), f);
    if (!b.endsWith('\n')) fputc('\n', f);
}

int runCli(const QStringList &args)
{
    const QString cmd = args.value(0);
    const bool json = args.contains(QStringLiteral("--json"));
    QString err;
    if (cmd == QLatin1String("list") || cmd == QLatin1String("ls")) {
        const QJsonArray a = listArray(&err);
        if (!err.isEmpty()) { print(err, stderr); return 1; }
        if (json) { print(toJson(a, true)); return 0; }
        if (a.isEmpty()) { print(QStringLiteral("Brak kontenerów i środowisk.")); return 0; }
        for (const QJsonValue &v : a) {
            const QJsonObject o = v.toObject();
            QString line = QStringLiteral("%1  %2  %3  %4").arg(o.value(QStringLiteral("running")).toBool() ? QStringLiteral("●") : QStringLiteral("○"),
                                                               o.value(QStringLiteral("name")).toString().leftJustified(24),
                                                               o.value(QStringLiteral("kind")).toString().leftJustified(9),
                                                               o.value(QStringLiteral("status")).toString());
            if (!o.value(QStringLiteral("ports")).toString().isEmpty()) line += QStringLiteral("  porty ") + o.value(QStringLiteral("ports")).toString();
            if (o.contains(QStringLiteral("cpu")))
                line += QStringLiteral("  CPU %1%  RAM %2").arg(o.value(QStringLiteral("cpu")).toDouble(), 0, 'f', 1).arg(o.value(QStringLiteral("memory")).toString());
            print(line);
        }
        return 0;
    }
    if (cmd == QLatin1String("images")) {
        const QString r = Agent::images(&err);
        if (!err.isEmpty()) { print(err, stderr); return 1; }
        if (json) { print(QString::fromUtf8(QJsonDocument::fromJson(r.toUtf8()).toJson())); return 0; }
        for (const QJsonValue &v : QJsonDocument::fromJson(r.toUtf8()).array()) {
            const QJsonObject o = v.toObject();
            print(QStringLiteral("%1  %2  %3%4").arg(o.value(QStringLiteral("id")).toString(), o.value(QStringLiteral("size")).toString().rightJustified(9),
                                                    o.value(QStringLiteral("name")).toString(), o.value(QStringLiteral("unused")).toBool() ? QStringLiteral("  (nieużywany)") : QString()));
        }
        return 0;
    }
    if (cmd == QLatin1String("logs")) {
        const QString name = args.value(1);
        if (name.isEmpty()) { print(QStringLiteral("Użycie: aster-harbor logs NAZWA [-n LINIE]"), stderr); return 2; }
        int lines = 100;
        const int n = args.indexOf(QStringLiteral("-n"));
        if (n > 0) lines = args.value(n + 1).toInt();
        const QString r = Agent::logs(name, lines, &err);
        if (!err.isEmpty()) { print(err, stderr); return 1; }
        if (!r.isEmpty()) print(r);
        return 0;
    }
    if (cmd == QLatin1String("start") || cmd == QLatin1String("stop") || cmd == QLatin1String("restart")) {
        const QString name = args.value(1);
        if (name.isEmpty()) { print(QStringLiteral("Użycie: aster-harbor %1 NAZWA").arg(cmd), stderr); return 2; }
        Agent::action(cmd, name, &err);
        if (!err.isEmpty()) { print(err, stderr); return 1; }
        print(cmd == QLatin1String("stop") ? QStringLiteral("Zatrzymano %1").arg(name) : QStringLiteral("Uruchomiono %1").arg(name));
        return 0;
    }
    print(QStringLiteral(
        "Aster Harbor — kontenery i środowiska programisty\n\n"
        "  aster-harbor                     okno programu\n"
        "  aster-harbor list [--json]       kontenery i toolboxy (stan, porty, CPU, RAM)\n"
        "  aster-harbor images [--json]     obrazy (rozmiar, czy używane)\n"
        "  aster-harbor logs NAZWA [-n N]   ostatnie linie logów\n"
        "  aster-harbor start|stop|restart NAZWA\n"
        "  aster-harbor --dbus              usługa D-Bus org.aster.Harbor (uruchamiana sama na żądanie)\n"),
        cmd == QLatin1String("help") || cmd == QLatin1String("--help") || cmd == QLatin1String("-h") ? stdout : stderr);
    return cmd == QLatin1String("help") || cmd == QLatin1String("--help") || cmd == QLatin1String("-h") ? 0 : 2;
}

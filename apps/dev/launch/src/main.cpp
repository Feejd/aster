// aster-launch — Aster Launch: wdrażanie aplikacji na własny serwer (SSH) albo do hostingów (Netlify, Vercel, Cloudflare Pages).
//   aster-launch                      okno programu
//   aster-launch FOLDER               okno z dodanym projektem
//   aster-launch lista                projekty
//   aster-launch status [PROJEKT]     wersja na produkcji, historia, czy strona odpowiada
//   aster-launch wdroz PROJEKT        plan zmian → potwierdzenie [t/N] → wdrożenie
//   aster-launch przywroc PROJEKT [WERSJA]
//   aster-launch logi PROJEKT [-n 200] [-f]
//   aster-launch dodaj FOLDER
// Bez terminala do potwierdzenia (np. wywołanie przez asystenta) wdrożenie i przywrócenie idą przez D-Bus
// do okna Aster Launch, gdzie użytkownik widzi plan i decyduje.

#include "bus.h"
#include "engine.h"

#include <KWindowSystem>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include <cstdio>
#include <unistd.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

namespace {

const QString kService = QStringLiteral("org.aster.Launch");
const QString kPath = QStringLiteral("/org/aster/Launch");

void out(const QString &s) { std::fputs((s + QLatin1Char('\n')).toUtf8().constData(), stdout); std::fflush(stdout); }
void err(const QString &s) { std::fputs((s + QLatin1Char('\n')).toUtf8().constData(), stderr); }

bool color() { return isatty(1); }
QString bold(const QString &s) { return color() ? QStringLiteral("\033[1m") + s + QStringLiteral("\033[0m") : s; }
QString dim(const QString &s) { return color() ? QStringLiteral("\033[2m") + s + QStringLiteral("\033[0m") : s; }
QString green(const QString &s) { return color() ? QStringLiteral("\033[32m") + s + QStringLiteral("\033[0m") : s; }
QString red(const QString &s) { return color() ? QStringLiteral("\033[31m") + s + QStringLiteral("\033[0m") : s; }

void usage()
{
    out(QStringLiteral("Aster Launch — wdrażanie aplikacji\n\n"
                       "  aster-launch                       okno programu\n"
                       "  aster-launch lista                 projekty\n"
                       "  aster-launch status [PROJEKT]      stan na produkcji (--json)\n"
                       "  aster-launch wdroz PROJEKT         wdrożenie (najpierw plan i potwierdzenie)\n"
                       "  aster-launch przywroc PROJEKT [N]  powrót do wersji N (domyślnie poprzedniej)\n"
                       "  aster-launch logi PROJEKT [-n 200] [-f]\n"
                       "  aster-launch dodaj FOLDER          nowy projekt (cel ustawisz w oknie)\n\n"
                       "Każda zmiana na serwerze jest najpierw pokazana i czeka na potwierdzenie."));
}

// Odpowiedź tak/nie z terminala (nie ze stdin — potok nie może potwierdzić za użytkownika)
int askTty(const QString &question)
{
    FILE *tty = std::fopen("/dev/tty", "r+");
    if (!tty)
        return -1;
    std::fputs((question + QStringLiteral(" [t/N] ")).toUtf8().constData(), tty);
    std::fflush(tty);
    char buf[64] = {};
    const bool got = std::fgets(buf, sizeof buf, tty) != nullptr;
    std::fclose(tty);
    const QString a = QString::fromUtf8(buf).trimmed().toLower();
    return got && (a == QLatin1String("t") || a == QLatin1String("tak") || a == QLatin1String("y") || a == QLatin1String("yes")) ? 1 : 0;
}

QString versionLine(const QJsonObject &v, int current)
{
    const QString st = v.value(QStringLiteral("status")).toString();
    const QString mark = v.value(QStringLiteral("v")).toInt() == current ? green(QStringLiteral("● na produkcji")) : QString();
    QString t = QStringLiteral("  v%1  %2  %3").arg(v.value(QStringLiteral("v")).toInt()).arg(v.value(QStringLiteral("time")).toString().replace(QLatin1Char('T'), QLatin1Char(' ')).left(16),
                                                   st == QLatin1String("ok") ? QStringLiteral("ok") : st == QLatin1String("unhealthy") ? QStringLiteral("nie odpowiadała") : QStringLiteral("nieudana"));
    if (!v.value(QStringLiteral("commit")).toString().isEmpty())
        t += QStringLiteral("  ") + dim(v.value(QStringLiteral("commit")).toString());
    if (!v.value(QStringLiteral("restorable")).toBool() && v.value(QStringLiteral("v")).toInt() != current && st != QLatin1String("failed"))
        t += dim(QStringLiteral("  (usunięta z serwera)"));
    if (!mark.isEmpty())
        t += QStringLiteral("  ") + mark;
    return t;
}

// Wdrożenie / przywrócenie z terminala
int runPlanCli(QCoreApplication &app, Launch *l, const QString &id, int rollbackTo)
{
    int result = 1;
    QObject::connect(l, &Launch::planFailed, &app, [&](const QString &, const QString &e) {
        err(red(QStringLiteral("Nie da się przygotować planu: ")) + e);
        result = 2;
        app.quit();
    });
    QObject::connect(l, &Launch::planReady, &app, [&](const QString &) {
        out(QString());
        for (const QString &line : l->planText().split(QLatin1Char('\n')))
            out(line.startsWith(QLatin1String("     │")) ? dim(line) : line);
        const int a = askTty(bold(rollbackTo ? QStringLiteral("Przywrócić tę wersję na serwerze?") : QStringLiteral("Wykonać te zmiany?")));
        if (a != 1) {
            l->cancelPlan();
            out(QStringLiteral("Anulowano — nic nie zostało zmienione."));
            result = 3;
            app.quit();
            return;
        }
        l->confirmPlan();
    });
    QObject::connect(l->output(), &LogModel::appended, &app, [](const QString &line) {
        out(line.startsWith(QLatin1String("▸ ")) ? bold(line) : QStringLiteral("  ") + line);
    });
    QObject::connect(l, &Launch::runFinished, &app, [&](const QString &, bool ok, const QString &) {
        if (!l->running() && l->runResult().isEmpty())
            return; // anulowanie — obsłużone wyżej
        result = ok ? 0 : 1;
        if (ok && !l->urlFor(id).isEmpty())
            out(green(QStringLiteral("Strona: ")) + l->urlFor(id));
        app.quit();
    });
    // Dopiero w pętli zdarzeń — plan przywrócenia powstaje od razu, a quit() przed exec() nic by nie dał
    QTimer::singleShot(0, &app, [&] {
        if (rollbackTo)
            l->prepareRollback(id, rollbackTo, QStringLiteral("Terminal"));
        else {
            out(dim(QStringLiteral("Sprawdzam serwer…")));
            l->prepareDeploy(id, QStringLiteral("Terminal"));
        }
    });
    app.exec();
    return result;
}

// Bez terminala: decyzja w oknie programu (przez D-Bus, okno uruchomi się samo)
int viaBus(const QString &method, const QVariantList &args)
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kService, method);
    m.setArguments(args);
    const QDBusMessage r = QDBusConnection::sessionBus().call(m, QDBus::Block, 60 * 60 * 1000);
    if (r.type() == QDBusMessage::ErrorMessage) {
        err(r.errorMessage());
        return r.errorName().endsWith(QLatin1String("Denied")) ? 3 : 1;
    }
    out(r.arguments().value(0).toString());
    return 0;
}

int cli(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aster-launch"));
    app.setOrganizationName(QStringLiteral("Aster"));
    QStringList args = app.arguments().mid(1);
    const QString cmd = args.takeFirst();
    const bool json = args.removeAll(QStringLiteral("--json")) > 0;
    Launch *l = Launch::instance();

    if (cmd == QLatin1String("pomoc") || cmd == QLatin1String("help") || cmd == QLatin1String("--help") || cmd == QLatin1String("-h")) {
        usage();
        return 0;
    }
    if (cmd == QLatin1String("lista") || cmd == QLatin1String("list")) {
        const QVariantList ps = l->projects();
        if (json) {
            QJsonArray a;
            for (const QVariant &p : ps)
                a.append(l->statusJson(p.toMap().value(QStringLiteral("id")).toString()));
            out(QString::fromUtf8(QJsonDocument(a).toJson()));
            return 0;
        }
        if (ps.isEmpty())
            out(QStringLiteral("Brak projektów. Dodaj: aster-launch dodaj FOLDER"));
        for (const QVariant &v : ps) {
            const QVariantMap p = v.toMap();
            const int cur = p.value(QStringLiteral("current")).toInt();
            out(QStringLiteral("%1  %2  %3  %4").arg(bold(p.value(QStringLiteral("name")).toString()), p.value(QStringLiteral("typeName")).toString(),
                                                     cur ? QStringLiteral("v%1").arg(cur) : QStringLiteral("niewdrożony"), p.value(QStringLiteral("url")).toString()));
        }
        return 0;
    }
    if (cmd == QLatin1String("dodaj") || cmd == QLatin1String("add")) {
        if (args.isEmpty()) {
            usage();
            return 2;
        }
        const QString id = l->addProject(args.first());
        if (id.isEmpty()) {
            err(QStringLiteral("To nie jest folder: ") + args.first());
            return 2;
        }
        const QVariantMap p = l->project(id);
        out(QStringLiteral("Dodano „%1” (%2). Cel wdrożenia ustawisz w oknie Aster Launch.").arg(p.value(QStringLiteral("name")).toString(), p.value(QStringLiteral("typeName")).toString()));
        return 0;
    }

    if (args.isEmpty() && cmd != QLatin1String("status")) {
        usage();
        return 2;
    }
    const QString name = args.value(0);
    if (cmd == QLatin1String("status") && name.isEmpty()) {
        const QVariantList ps = l->projects();
        for (const QVariant &v : ps) {
            const QVariantMap p = v.toMap();
            const int cur = p.value(QStringLiteral("current")).toInt();
            const QVariantMap check = p.value(QStringLiteral("lastCheck")).toMap();
            out(QStringLiteral("%1  %2  %3").arg(bold(p.value(QStringLiteral("name")).toString()), cur ? QStringLiteral("v%1").arg(cur) : QStringLiteral("niewdrożony"),
                                                 check.value(QStringLiteral("message")).toString()));
        }
        return 0;
    }
    const QString id = l->findProject(name);
    if (id.isEmpty()) {
        err(QStringLiteral("Nie ma projektu „%1”. Lista: aster-launch lista").arg(name));
        return 2;
    }

    if (cmd == QLatin1String("status")) {
        int code = 0;
        QObject::connect(l, &Launch::healthChecked, &app, [&](const QString &, const QVariantMap &res) {
            const QJsonObject s = l->statusJson(id);
            if (json) {
                out(QString::fromUtf8(QJsonDocument(s).toJson()));
            } else {
                const int cur = s.value(QStringLiteral("current")).toInt();
                out(bold(s.value(QStringLiteral("name")).toString()) + QStringLiteral("  ") + l->describeType(s.value(QStringLiteral("type")).toString()));
                out(QStringLiteral("  Adres: ") + s.value(QStringLiteral("url")).toString());
                out(QStringLiteral("  Na produkcji: ") + (cur ? QStringLiteral("v%1").arg(cur) : QStringLiteral("nic")));
                out(QStringLiteral("  ") + (res.value(QStringLiteral("ok")).toBool() ? green(res.value(QStringLiteral("message")).toString()) : red(res.value(QStringLiteral("message")).toString())));
                const QJsonArray vs = s.value(QStringLiteral("versions")).toArray();
                if (!vs.isEmpty())
                    out(QStringLiteral("\nWersje:"));
                for (int i = vs.size() - 1; i >= 0 && i >= vs.size() - 10; --i)
                    out(versionLine(vs.at(i).toObject(), cur));
            }
            code = res.value(QStringLiteral("ok")).toBool() ? 0 : 1;
            app.quit();
        });
        if (l->project(id).value(QStringLiteral("current")).toInt() == 0) {
            out(QStringLiteral("„%1” nie był jeszcze wdrażany.").arg(name));
            return 0;
        }
        l->checkHealth(id);
        app.exec();
        return code;
    }

    if (cmd == QLatin1String("logi") || cmd == QLatin1String("logs")) {
        const bool follow = args.contains(QStringLiteral("-f"));
        const int ni = args.indexOf(QStringLiteral("-n"));
        const int n = ni >= 0 ? args.value(ni + 1).toInt() : 200;
        if (follow) {
            QObject::connect(l->liveLog(), &LogModel::appended, &app, [](const QString &line) { out(line); });
            l->startLiveLog(id, n > 0 ? n : 200);
            QObject::connect(l, &Launch::liveLogChanged, &app, [&] {
                QTimer::singleShot(200, &app, [&] { if (!l->liveLogRunning()) app.quit(); });
            });
            return app.exec();
        }
        int code = 0;
        QObject::connect(l, &Launch::logsFetched, &app, [&](const QString &, bool ok, const QString &text) {
            (ok ? out : err)(text.trimmed());
            code = ok ? 0 : 1;
            app.quit();
        });
        l->fetchLogs(id, n > 0 ? n : 200);
        app.exec();
        return code;
    }

    const bool deploy = cmd == QLatin1String("wdroz") || cmd == QLatin1String("wdróż") || cmd == QLatin1String("deploy");
    const bool rollback = cmd == QLatin1String("przywroc") || cmd == QLatin1String("przywróć") || cmd == QLatin1String("rollback");
    if (deploy || rollback) {
        int version = 0;
        if (rollback) {
            QString vs = args.value(1);
            if (vs.startsWith(QLatin1Char('v')))
                vs.remove(0, 1);
            version = vs.isEmpty() ? l->previousVersion(id) : vs.toInt();
            if (version <= 0) {
                err(QStringLiteral("Nie ma wcześniejszej wersji do przywrócenia."));
                return 2;
            }
        }
        FILE *tty = std::fopen("/dev/tty", "r");
        if (!tty) {
            // Wywołanie bez terminala (np. przez asystenta): potwierdzenie w oknie Aster Launch
            err(QStringLiteral("Brak terminala — plan zmian pojawi się w oknie Aster Launch do potwierdzenia."));
            return deploy ? viaBus(QStringLiteral("Deploy"), {name}) : viaBus(QStringLiteral("Rollback"), {name, version});
        }
        std::fclose(tty);
        return runPlanCli(app, l, id, version);
    }

    usage();
    return 2;
}

} // namespace

int main(int argc, char *argv[])
{
    static const QStringList commands{QStringLiteral("lista"), QStringLiteral("list"), QStringLiteral("status"), QStringLiteral("wdroz"), QStringLiteral("wdróż"),
                                      QStringLiteral("deploy"), QStringLiteral("przywroc"), QStringLiteral("przywróć"), QStringLiteral("rollback"),
                                      QStringLiteral("logi"), QStringLiteral("logs"), QStringLiteral("dodaj"), QStringLiteral("add"), QStringLiteral("pomoc"),
                                      QStringLiteral("help"), QStringLiteral("--help"), QStringLiteral("-h")};
    if (argc > 1 && commands.contains(QString::fromLocal8Bit(argv[1])))
        return cli(argc, argv);

    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-launch"));
    app.setApplicationDisplayName(QStringLiteral("Aster Launch"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.launch"));

    const QStringList args = app.arguments();
    const QString folder = args.size() > 1 && QFileInfo(args.at(1)).isDir() ? QFileInfo(args.at(1)).absoluteFilePath() : QString();

    Launch *launch = Launch::instance();
    LaunchBus bus(launch);
    QDBusConnection session = QDBusConnection::sessionBus();
    if (session.isConnected()) {
        if (!session.registerService(kService)) {
            // Okno już jest — przekaż folder (jako nowy projekt) i przywołaj je
            if (!folder.isEmpty())
                launch->addProject(folder);
            QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kService, QStringLiteral("Activate"));
            m << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
            session.call(m, QDBus::Block, 2000);
            return 0;
        }
        session.registerObject(kPath, &bus, QDBusConnection::ExportAllSlots);
    }

    QString selected;
    if (!folder.isEmpty())
        selected = launch->addProject(folder);

    // Zmiany z polecenia w terminalu (inny proces) — odśwież listę
    QFileSystemWatcher watcher;
    const QString file = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Aster/aster-launch/projekty.json");
    const auto watch = [&watcher, file] {
        if (QFileInfo::exists(file) && !watcher.files().contains(file))
            watcher.addPath(file);
        const QString dir = QFileInfo(file).absolutePath();
        if (!watcher.directories().contains(dir))
            watcher.addPath(dir);
    };
    watch();
    QTimer reloadTimer;
    reloadTimer.setSingleShot(true);
    reloadTimer.setInterval(300);
    QObject::connect(&reloadTimer, &QTimer::timeout, launch, [launch, &watch] {
        launch->reload();
        watch();
    });
    QObject::connect(&watcher, &QFileSystemWatcher::fileChanged, &reloadTimer, qOverload<>(&QTimer::start));
    QObject::connect(&watcher, &QFileSystemWatcher::directoryChanged, &reloadTimer, qOverload<>(&QTimer::start));
    // Własne zapisy też wywołają odświeżenie — reload() wczytuje ten sam stan, więc nic się nie zmienia

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("selected"), selected}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Launch", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    const auto raise = [window](const QString &token) {
        if (window->visibility() == QWindow::Minimized)
            window->showNormal();
        if (!token.isEmpty())
            KWindowSystem::setCurrentXdgActivationToken(token);
        KWindowSystem::activateWindow(window);
    };
    QObject::connect(&bus, &LaunchBus::activated, window, raise);
    QObject::connect(launch, &Launch::wantsAttention, window, [raise] { raise(QString()); });

    // Do testów: ASTER_OPEN=… (testOpen w Main.qml), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) — zrzut okna i koniec
    // ASTER_OPEN działa tylko razem z ASTER_SHOT (program kończy się po zrzucie) — haki testowe, w tym
    // automatyczne potwierdzenie planu, nie mogą posłużyć do obejścia zgody użytkownika w zwykłej pracy
    const QString open = qEnvironmentVariableIsEmpty("ASTER_SHOT") ? QString() : qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(900, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 3500, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

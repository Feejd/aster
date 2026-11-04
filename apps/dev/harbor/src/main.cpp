// aster-harbor — Aster Harbor: kontenery i środowiska programisty.
//   aster-harbor                        okno (druga kopia przywołuje otwarte okno, D-Bus: org.aster.harbor)
//   aster-harbor new                    okno z kreatorem „Nowe środowisko”
//   aster-harbor list|images|logs|start|stop|restart …   bez okna, dla skryptów i agenta asystenta
//   aster-harbor --dbus                 usługa org.aster.Harbor (D-Bus, start na żądanie, kończy się po bezczynności)

#include "agent.h"
#include "harbor.h"
#include "instance.h"

#include <KWindowSystem>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

static const QStringList kCliCommands{ QStringLiteral("list"), QStringLiteral("ls"), QStringLiteral("images"), QStringLiteral("logs"),
                                       QStringLiteral("start"), QStringLiteral("stop"), QStringLiteral("restart"),
                                       QStringLiteral("help"), QStringLiteral("--help"), QStringLiteral("-h") };

static void exportAgent(QDBusConnection &bus, Agent *agent)
{
    // Agent asystenta Aster: org.aster.Harbor /org/aster/Harbor
    bus.registerObject(QStringLiteral("/org/aster/Harbor"), agent, QDBusConnection::ExportAllSlots);
    bus.registerService(QStringLiteral("org.aster.Harbor"));
}

int main(int argc, char *argv[])
{
    const QString first = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QString();

    // ——— Bez okna: CLI i usługa D-Bus ———
    if (kCliCommands.contains(first) || first == QLatin1String("--dbus")) {
        QCoreApplication app(argc, argv);
        app.setApplicationName(QStringLiteral("aster-harbor"));
        app.setOrganizationName(QStringLiteral("Aster"));
        if (first != QLatin1String("--dbus"))
            return runCli(app.arguments().mid(1));
        QDBusConnection bus = QDBusConnection::sessionBus();
        Agent agent;
        bus.registerObject(QStringLiteral("/org/aster/Harbor"), &agent, QDBusConnection::ExportAllSlots);
        if (!bus.registerService(QStringLiteral("org.aster.Harbor")))
            return 0;   // już działa (okno albo inna usługa)
        agent.setIdleQuit(5 * 60 * 1000);
        return app.exec();
    }

    // ——— Okno ———
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-harbor"));
    app.setApplicationDisplayName(QStringLiteral("Aster Harbor"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.harbor"));

    QString page = first == QLatin1String("new") ? QStringLiteral("new") : QString();
    if (page.isEmpty()) page = qEnvironmentVariable("ASTER_PAGE");

    const QString service = QStringLiteral("org.aster.harbor");
    QDBusConnection bus = QDBusConnection::sessionBus();
    Instance instance;
    Agent agent;
    if (bus.isConnected() && qEnvironmentVariable("ASTER_SHOT").isEmpty()) {
        if (!bus.registerService(service)) {
            QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/"), service, QStringLiteral("Activate"));
            m << page << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
            bus.call(m, QDBus::Block, 2000);
            return 0;
        }
        bus.registerObject(QStringLiteral("/"), &instance, QDBusConnection::ExportAllSlots);
        exportAgent(bus, &agent);   // gdy usługa D-Bus już działa, zostaje przy niej — to bez znaczenia
    }

    Harbor harbor;
    QQmlApplicationEngine engine;
    engine.setInitialProperties({ { QStringLiteral("startPage"), page } });
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Harbor", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    QObject::connect(&instance, &Instance::activated, window, [window](const QString &page, const QString &token) {
        if (!page.isEmpty())
            QMetaObject::invokeMethod(window, "openPage", Q_ARG(QVariant, page));
        if (window->visibility() == QWindow::Minimized)
            window->showNormal();
        if (!token.isEmpty())
            KWindowSystem::setCurrentXdgActivationToken(token);
        KWindowSystem::activateWindow(window);
    });

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) zapisuje zrzut okna i kończy program;
    // ASTER_OPEN=… otwiera wybrany widok (patrz testOpen w Main.qml)
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(1800, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
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

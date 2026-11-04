// aster-pulse — Aster Pulse, testowanie API.
//   aster-pulse [FOLDER]                       okno (FOLDER — projekt z pulse/ albo obszar Pulse)
//   aster-pulse run|send|list|curl|import …    polecenia dla terminala i agenta (wynik JSON), patrz --help
//   aster-pulse --dbus                         usługa D-Bus bez okna (start na żądanie)
// Okno wystawia org.aster.pulse (/org/aster/Pulse, interfejs org.aster.Pulse); drugie uruchomienie przywołuje je.

#include "agent.h"
#include "pulse.h"

#include <KWindowSystem>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    // Polecenia w terminalu — bez okna i bez grafiki
    const int code = runCommandLine(argc, argv);
    if (code >= 0)
        return code;

    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-pulse"));
    app.setApplicationDisplayName(QStringLiteral("Aster Pulse"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.pulse"));

    QString folder;
    for (const QString &a : app.arguments().mid(1))
        if (!a.startsWith(QLatin1Char('-')) && QFileInfo(a).isDir())
            folder = QFileInfo(a).absoluteFilePath();

    QNetworkAccessManager nam;
    PulseService service(&nam, true);
    QDBusConnection bus = QDBusConnection::sessionBus();
    const bool test = !qEnvironmentVariable("ASTER_SHOT").isEmpty();
    if (bus.isConnected() && !test) {
        if (!bus.registerService(PulseService::busName)) {
            // Działa już okno (przywołaj je) albo sama usługa dla agenta (wtedy otwieramy okno bez nazwy na szynie)
            QDBusMessage m = QDBusMessage::createMethodCall(PulseService::busName, PulseService::objectPath, QStringLiteral("org.aster.Pulse"), QStringLiteral("Activate"));
            m << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
            const QDBusReply<bool> r = bus.call(m, QDBus::Block, 2000);
            if (r.isValid() && r.value() && folder.isEmpty())
                return 0;
        } else {
            bus.registerObject(PulseService::objectPath, &service, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
        }
    }

    PulseApp::setInitialFolder(folder);
    PulseApp::setNetwork(&nam);
    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Pulse", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    auto *pulse = engine.singletonInstance<PulseApp *>("Aster.Pulse", "Pulse");

    QObject::connect(&service, &PulseService::activated, window, [window](const QString &token) {
        if (window->visibility() == QWindow::Minimized)
            window->showNormal();
        if (!token.isEmpty())
            KWindowSystem::setCurrentXdgActivationToken(token);
        KWindowSystem::activateWindow(window);
    });
    if (pulse)
        QObject::connect(&service, &PulseService::requestFinished, pulse, &PulseApp::externalRequestFinished);

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) — zrzut okna i koniec; ASTER_OPEN=… — patrz testOpen w Main.qml
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(900, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 3000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

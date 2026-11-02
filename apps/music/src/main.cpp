// aster-music — Muzyka Aster.
//   aster-music                  biblioteka; kolejka i utwór z poprzedniego razu czekają w pasku na dole
//   aster-music PLIK…            gra od razu; gdy Muzyka już działa — w jej oknie (D-Bus: org.aster.music)

#include "library.h"

#include <KWindowSystem>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-music"));
    app.setApplicationDisplayName(QStringLiteral("Muzyka"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.music"));

    QStringList files;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        files << QFileInfo(url.isLocalFile() ? url.toLocalFile() : args.at(i)).absoluteFilePath();
    }

    const bool testing = !qEnvironmentVariable("ASTER_SHOT").isEmpty();
    const QString service = QStringLiteral("org.aster.music");
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && !testing && !bus.registerService(service)) {
        // Już działa — pliki do jego kolejki (bez plików: tylko przywołanie okna)
        QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/"), service, QStringLiteral("openFiles"));
        m << files;
        bus.call(m, QDBus::Block, 2000);
        return 0;
    }
    Library::s_pending = files;

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Music", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    auto *library = engine.singletonInstance<Library *>("Aster.Music", "Library");
    if (bus.isConnected() && !testing)
        bus.registerObject(QStringLiteral("/"), library, QDBusConnection::ExportAllSlots);
    QObject::connect(library, &Library::openRequested, window, [window] { KWindowSystem::activateWindow(window); });

    // Do testów: ASTER_OPEN=kroki po „;” (testOpen w Main.qml, co 1,2 s), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step)); });
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

// aster-shell — powłoka systemu Aster.
// Działa w sesji KWin (Wayland) zamiast plasmashell: tapeta, dok i górna wyspa
// to osobne okna warstwy (wlr-layer-shell), ustawiane w QML przez Platform.makeLayer().

#include "platform.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aster-shell"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setDesktopFileName(QStringLiteral("org.aster.shell"));
    app.setQuitOnLastWindowClosed(false);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Shell", "Shell");

    // Do testów: ASTER_SHOT_START=plik.png otwiera Start, zapisuje jego zrzut i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT_START");
    if (!shot.isEmpty()) {
        QTimer::singleShot(1000, &app, [&engine] {
            if (auto *platform = engine.singletonInstance<Platform *>("Aster.Shell", "Platform"))
                platform->activateLauncherMenu();
        });
        QTimer::singleShot(2200, &app, [shot] {
            for (QWindow *w : QGuiApplication::topLevelWindows())
                if (w->title() == QLatin1String("Start"))
                    if (auto *qw = qobject_cast<QQuickWindow *>(w))
                        qw->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

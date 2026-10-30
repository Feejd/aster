// aster-shell — powłoka systemu Aster.
// Działa w sesji KWin (Wayland) zamiast plasmashell: tapeta, dok i górna wyspa
// to osobne okna warstwy (wlr-layer-shell), ustawiane w QML przez Platform.makeLayer().

#include <QGuiApplication>
#include <QQmlApplicationEngine>

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

    return app.exec();
}

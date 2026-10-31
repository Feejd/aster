// aster-store — Sklep: programy z Flathub (Flatpak), w wyglądzie Aster.
// Uruchomienie z identyfikatorem aplikacji (aster-store org.gimp.GIMP) otwiera jej stronę.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-store"));
    app.setApplicationDisplayName(QStringLiteral("Sklep"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.store"));

    QString openApp;
    const QStringList args = app.arguments();
    if (args.size() > 1 && !args.at(1).startsWith(QLatin1Char('-')))
        openApp = args.at(1).section(QLatin1Char('/'), -1).remove(QStringLiteral("appstream://"));

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("openApp"), openApp}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Store", "Main");

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) zapisuje zrzut okna i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") : 6000;
        QTimer::singleShot(delay, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

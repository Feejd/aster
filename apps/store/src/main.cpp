// aster-store — Sklep Aster: własny katalog programów (Flatpak, aplikacje Aster, aplikacje webowe).
// Uruchomienie z identyfikatorem aplikacji (aster-store org.gimp.GIMP) otwiera jej stronę.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include "net.h"
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
    ImageCacheFactory imageCache;
    engine.setNetworkAccessManagerFactory(&imageCache);
    // ASTER_OPEN: strona na start, do zrzutów i testów (np. task:film, windows, mine, compare:a,b, search:tekst)
    engine.setInitialProperties({{QStringLiteral("openApp"), openApp}, {QStringLiteral("openRoute"), qEnvironmentVariable("ASTER_OPEN")},
                                 {QStringLiteral("openScroll"), qEnvironmentVariableIntValue("ASTER_SCROLL")}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Store", "Main");

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) zapisuje zrzut okna i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        if (qEnvironmentVariableIntValue("ASTER_SHOT_WIDTH") > 0)
            window->resize(qEnvironmentVariableIntValue("ASTER_SHOT_WIDTH"), qMax(window->minimumHeight(), 650));
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") : 6000;
        QTimer::singleShot(delay, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

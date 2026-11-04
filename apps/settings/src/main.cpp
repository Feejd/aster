// aster-settings — Ustawienia systemu Aster.
// Argument wybiera dział, np. „aster-settings wifi” (Wi‑Fi i sieć), „bluetooth”, „sound”, „wallpaper”.

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
    app.setApplicationName(QStringLiteral("aster-settings"));
    app.setApplicationDisplayName(QStringLiteral("Ustawienia"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.settings"));

    static const QStringList pages{QStringLiteral("wifi"), QStringLiteral("bluetooth"), QStringLiteral("notifications"), QStringLiteral("sound"),
                                   QStringLiteral("general"), QStringLiteral("appearance"), QStringLiteral("wallpaper"), QStringLiteral("desktop"),
                                   QStringLiteral("display"), QStringLiteral("account"), QStringLiteral("power"), QStringLiteral("mouse"),
                                   QStringLiteral("keyboard"), QStringLiteral("shortcuts"), QStringLiteral("printers"), QStringLiteral("datetime"),
                                   QStringLiteral("language"), QStringLiteral("apps"), QStringLiteral("accessibility"), QStringLiteral("assistant"), QStringLiteral("privacy"),
                                   QStringLiteral("storage")};
    QString page = qEnvironmentVariable("ASTER_PAGE");
    const QStringList args = app.arguments();
    if (args.size() > 1)
        page = args.at(1).section(QLatin1Char(':'), -1).remove(QLatin1Char('/'));
    if (!pages.contains(page))
        page = QStringLiteral("general");

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("startPage"), page}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Settings", "Main");

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) zapisuje zrzut okna i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") : 2500;
        QTimer::singleShot(delay, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

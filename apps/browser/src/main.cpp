// aster-browser — Przeglądarka systemu Aster. Silnik: Qt WebEngine (Chromium).
// Uruchomienie z adresem (aster-browser https://…) otwiera go w pierwszej karcie.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);

    asterTypography();
    app.setApplicationName(QStringLiteral("aster-browser"));
    app.setApplicationDisplayName(QStringLiteral("Przeglądarka"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.browser"));

    QString start;
    const QStringList args = app.arguments();
    if (args.size() > 1)
        start = QUrl::fromUserInput(args.at(1)).toString();

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("startUrl"), start}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Browser", "Main");

    // Do testów: ASTER_SHOT=plik.png zapisuje zrzut okna po 3 s i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QTimer::singleShot(3000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

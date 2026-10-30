// aster-files — Pliki: menedżer plików systemu Aster.
// Uruchomienie z adresem folderu (aster-files ~/Dokumenty) otwiera go od razu.

#include <QApplication>
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    // QApplication (nie QGuiApplication): KIO pokazuje czasem okna dialogowe z widżetów
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aster-files"));
    app.setApplicationDisplayName(QStringLiteral("Pliki"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setDesktopFileName(QStringLiteral("org.aster.files"));

    QUrl start = QUrl::fromLocalFile(QDir::homePath());
    const QStringList args = app.arguments();
    if (args.size() > 1)
        start = QUrl::fromUserInput(args.at(1), QDir::currentPath(), QUrl::AssumeLocalFile);

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("startUrl"), start.toString()}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Files", "Main");

    // Do testów: ASTER_SHOT=plik.png zapisuje zrzut okna po 2 s i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QTimer::singleShot(2000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

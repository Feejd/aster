// aster-files — Pliki: menedżer plików systemu Aster.
// Uruchomienie z adresem folderu (aster-files ~/Dokumenty) otwiera go od razu.

#include <QApplication>
#include "archiver.h"

#include <QDir>
#include <QFileInfo>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    // QApplication (nie QGuiApplication): KIO pokazuje czasem okna dialogowe z widżetów
    QApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-files"));
    app.setApplicationDisplayName(QStringLiteral("Pliki"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setDesktopFileName(QStringLiteral("org.aster.files"));

    QUrl start = QUrl::fromLocalFile(QDir::homePath());
    const QStringList args = app.arguments();
    if (args.size() > 1)
        start = QUrl::fromUserInput(args.at(1), QDir::currentPath(), QUrl::AssumeLocalFile);

    // Archiwum jako argument (dwuklik w innym programie): ZIP/TAR — otwarte jak folder,
    // inne (7z, RAR…) — folder z archiwum i od razu wypakowanie obok
    QString extract;
    if (start.isLocalFile() && QFileInfo(start.toLocalFile()).isFile()) {
        Archiver probe;
        const QString browse = probe.browseUrl(start.toString());
        if (!browse.isEmpty()) {
            start = QUrl(browse);
        } else {
            if (probe.isArchive(start.toString()))
                extract = start.toString();
            start = QUrl::fromLocalFile(QFileInfo(start.toLocalFile()).absolutePath());
        }
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("startUrl"), start.toString()}, {QStringLiteral("extractOnStart"), extract}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Files", "Main");

    // Do testów: ASTER_OPEN=kroki po „;” (testOpen w Main.qml, co 1,2 s),
    // ASTER_SHOT=plik.png zapisuje zrzut okna (po ASTER_SHOT_DELAY ms, domyślnie 2 s) i kończy program
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step)); });
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 2000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

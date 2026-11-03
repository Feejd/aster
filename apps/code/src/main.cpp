// aster-code — Aster Code, edytor kodu.
//   aster-code                 okno startowe (ostatnie foldery) albo ostatni projekt
//   aster-code FOLDER          folder jako projekt
//   aster-code PLIK…           pliki w kartach, projekt — ich folder (albo repozytorium gita nad nim)

#include "project.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QProcess>
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
    app.setApplicationName(QStringLiteral("aster-code"));
    app.setApplicationDisplayName(QStringLiteral("Aster Code"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.code"));

    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        const QFileInfo fi(url.isLocalFile() ? url.toLocalFile() : args.at(i));
        if (fi.isDir()) {
            Project::s_pendingFolder = fi.absoluteFilePath();
        } else {
            Project::s_pendingFiles << fi.absoluteFilePath();
            if (Project::s_pendingFolder.isEmpty()) {
                // Projekt dla pliku: repozytorium gita, w którym leży, albo jego folder
                QProcess p;
                p.start(QStringLiteral("git"), {QStringLiteral("-C"), fi.absolutePath(), QStringLiteral("rev-parse"), QStringLiteral("--show-toplevel")});
                const bool git = p.waitForFinished(2000) && p.exitCode() == 0;
                Project::s_pendingFolder = git ? QString::fromUtf8(p.readAllStandardOutput()).trimmed() : fi.absolutePath();
            }
        }
    }

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Code", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    // Do testów: ASTER_OPEN=kroki po „;” (testOpen w Main.qml, co 1,2 s),
    // ASTER_SHOT=plik.png zapisuje zrzut okna (po ASTER_SHOT_DELAY ms, domyślnie 3 s) i kończy program
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step)); });
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

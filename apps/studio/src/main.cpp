// aster-studio — Studio Aster: proste studio nagrań (ścieżki, nagrywanie, pętle, mikser, eksport).
//   aster-studio                 ekran startowy z ostatnimi projektami
//   aster-studio FOLDER|projekt.json   otwiera projekt

#include "studio.h"

#include <QFileInfo>
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
    app.setApplicationName(QStringLiteral("aster-studio"));
    app.setApplicationDisplayName(QStringLiteral("Studio"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.studio"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Studio", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    auto *studio = engine.singletonInstance<Studio *>("Aster.Studio", "Studio");

    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i)
        if (!args.at(i).startsWith(QLatin1Char('-')) && studio) {
            studio->openProject(QFileInfo(args.at(i)).absoluteFilePath());
            break;
        }

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

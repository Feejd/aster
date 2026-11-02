// aster-photos — Zdjęcia Aster.
//   aster-photos                 biblioteka (Obrazy, Pobrane, Pulpit i dodane foldery)
//   aster-photos PLIK            zdjęcie, a strzałkami — reszta zdjęć z jego folderu
//   aster-photos FOLDER          zdjęcia z folderu

#include "photos.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
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
    app.setApplicationName(QStringLiteral("aster-photos"));
    app.setApplicationDisplayName(QStringLiteral("Zdjęcia"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.photos"));

    QString file, folder;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a.startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(a);
        const QString path = QFileInfo(url.isLocalFile() ? url.toLocalFile() : a).absoluteFilePath();
        if (QFileInfo(path).isDir())
            folder = QDir::cleanPath(path);
        else if (QFileInfo::exists(path))
            file = path;
        break;
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("thumb"), new ThumbProvider);
    engine.setInitialProperties({{QStringLiteral("startFile"), file}, {QStringLiteral("startFolder"), folder}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Photos", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    // Do testów: ASTER_OPEN=info|menu|zoom|grid… (testOpen w Main.qml), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(1500, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
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

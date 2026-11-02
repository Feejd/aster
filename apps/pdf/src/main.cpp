// aster-pdf — Podgląd PDF Aster.
//   aster-pdf                ekran startowy z ostatnimi dokumentami
//   aster-pdf PLIK.pdf       dokument (od strony, na której skończono czytać)

#include <QApplication>
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
    // QApplication (nie QGuiApplication) — okno drukowania jest z Qt Widgets
    QApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-pdf"));
    app.setApplicationDisplayName(QStringLiteral("Podgląd PDF"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.pdf"));

    QString file;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        file = QFileInfo(url.isLocalFile() ? url.toLocalFile() : args.at(i)).absoluteFilePath();
        break;
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("startFile"), file}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Pdf", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    // Do testów: ASTER_OPEN=find:tekst|outline|thumbs|menu|zoom|props, ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(1800, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
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

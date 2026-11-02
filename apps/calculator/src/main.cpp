// aster-calculator — Kalkulator Aster.

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
    app.setApplicationName(QStringLiteral("aster-calculator"));
    app.setApplicationDisplayName(QStringLiteral("Kalkulator"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.calculator"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Calculator", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    // Do testów: ASTER_TYPE=„12+3×4=” wpisuje klawisze, ASTER_OPEN=science|history, ASTER_SHOT=plik.png;
    // ASTER_TEST=1 — sprawdzenie obliczeń (wynik na wyjściu) i koniec
    if (qEnvironmentVariableIntValue("ASTER_TEST")) {
        QMetaObject::invokeMethod(window, "selfTest");
        return 0;
    }
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    const QString type = qEnvironmentVariable("ASTER_TYPE");
    QTimer::singleShot(800, window, [window, open, type] {
        if (!open.isEmpty())
            QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open));
        if (!type.isEmpty())
            QMetaObject::invokeMethod(window, "typeKeys", Q_ARG(QVariant, type));
    });
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty())
        QTimer::singleShot(2500, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    return app.exec();
}

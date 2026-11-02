// aster-emoji — panel emoji i znaków (Win+.).
// Pierwsze Win+. uruchamia program; kolejne (gdy działa) tylko pokazują/chowają panel (D-Bus: org.aster.emoji).

#include "emoji.h"

#include <LayerShellQt/Window>
#include <QDBusConnection>
#include <QDBusMessage>
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
    app.setApplicationName(QStringLiteral("aster-emoji"));
    app.setApplicationDisplayName(QStringLiteral("Emoji"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.emoji"));
    app.setQuitOnLastWindowClosed(false);             // schowany panel czeka na następne Win+.

    const bool testing = !qEnvironmentVariable("ASTER_SHOT").isEmpty();
    const QString service = QStringLiteral("org.aster.emoji");
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && !testing && !bus.registerService(service)) {
        bus.call(QDBusMessage::createMethodCall(service, QStringLiteral("/"), service, QStringLiteral("Toggle")), QDBus::Block, 2000);
        return 0;
    }

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Emoji", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    auto *emoji = engine.singletonInstance<Emoji *>("Aster.Emoji", "Emoji");
    if (bus.isConnected() && !testing)
        bus.registerObject(QStringLiteral("/"), emoji, QDBusConnection::ExportAllSlots);

    // Warstwa nad oknami, na dole ekranu nad dokiem, z klawiaturą (pole szukania); po schowaniu
    // aktywny wraca program, do którego wstawiamy emoji
    if (auto *lw = LayerShellQt::Window::get(window)) {
        lw->setLayer(LayerShellQt::Window::LayerOverlay);
        lw->setAnchors(LayerShellQt::Window::AnchorBottom);
        lw->setMargins({0, 0, 0, 72});
        lw->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        lw->setScope(QStringLiteral("aster-emoji"));
    }
    QMetaObject::invokeMethod(window, "showPanel");

    // Do testów: ASTER_OPEN=kroki po „;” (testOpen w Main.qml, co 0,8 s), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(800 * (i + 1), window, [window, step = steps.at(i)] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step)); });
    if (testing) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 2500, &app, [window] {
            window->grabWindow().save(qEnvironmentVariable("ASTER_SHOT"));
            QCoreApplication::quit();
        });
    }
    return app.exec();
}

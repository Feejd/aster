// aster-tasks — Menedżer zadań Aster (Ctrl+Shift+Esc).
//   aster-tasks                 okno z procesami
//   aster-tasks performance     od razu Wydajność
// Druga kopia przywołuje już otwarte okno (D-Bus: org.aster.tasks).

#include "instance.h"

#include <KWindowSystem>
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
    app.setApplicationName(QStringLiteral("aster-tasks"));
    app.setApplicationDisplayName(QStringLiteral("Menedżer zadań"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.tasks"));

    const QStringList args = app.arguments();
    const QString page = args.contains(QLatin1String("performance")) || qEnvironmentVariable("ASTER_PAGE") == QLatin1String("performance")
        ? QStringLiteral("performance")
        : QStringLiteral("processes");

    const QString service = QStringLiteral("org.aster.tasks");
    QDBusConnection bus = QDBusConnection::sessionBus();
    Instance instance;
    if (bus.isConnected() && qEnvironmentVariable("ASTER_SHOT").isEmpty()) {
        if (!bus.registerService(service)) {
            QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/"), service, QStringLiteral("Activate"));
            m << page << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
            bus.call(m, QDBus::Block, 2000);
            return 0;
        }
        bus.registerObject(QStringLiteral("/"), &instance, QDBusConnection::ExportAllSlots);
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("page"), page}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Tasks", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    QObject::connect(&instance, &Instance::activated, window, [window](const QString &page, const QString &token) {
        if (page == QLatin1String("performance"))
            window->setProperty("page", page);
        if (window->visibility() == QWindow::Minimized)
            window->showNormal();
        if (!token.isEmpty())
            KWindowSystem::setCurrentXdgActivationToken(token);
        KWindowSystem::activateWindow(window);
    });

    // Do testów: ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms) zapisuje zrzut okna i kończy program;
    // ASTER_OPEN=details|menu|confirm otwiera okno szczegółów, menu albo pytanie o zakończenie
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

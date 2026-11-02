// aster-portal — okna systemowe Aster dla xdg-desktop-portal (na razie „Otwórz / Zapisz”).
// Uruchamia go D-Bus na żądanie portalu; po kwadransie bez próśb kończy działanie.
//   ASTER_PORTAL_DEMO=open|save|folder   samo okno bez D-Bus (podgląd wyglądu)

#include "filechooser.h"

#include <QDBusConnection>
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
    app.setApplicationName(QStringLiteral("aster-portal"));
    app.setApplicationDisplayName(QStringLiteral("Aster"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setDesktopFileName(QStringLiteral("org.aster.portal"));
    app.setQuitOnLastWindowClosed(false);

    QQmlApplicationEngine engine;
    FileChooser chooser(&engine);

    const QString demo = qEnvironmentVariable("ASTER_PORTAL_DEMO");
    if (!demo.isEmpty()) {
        QQuickWindow *w = chooser.showDemo(demo);
        if (!w)
            return 1;
        const QString shot = qEnvironmentVariable("ASTER_SHOT");
        if (!shot.isEmpty())
            QTimer::singleShot(2500, &app, [w, shot] {
                w->grabWindow().save(shot);
                QCoreApplication::quit();
            });
        return app.exec();
    }

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/org/freedesktop/portal/desktop"), &chooser, QDBusConnection::ExportAllSlots)
        || !bus.registerService(QStringLiteral("org.freedesktop.impl.portal.desktop.aster"))) {
        qWarning("Nie udało się zarejestrować usługi portalu Aster (działa już inna kopia?)");
        return 1;
    }

    // Bezczynność: koniec po 15 minutach bez otwartych okien (D-Bus uruchomi nas znowu)
    QTimer idle;
    idle.setSingleShot(true);
    idle.setInterval(15 * 60 * 1000);
    QObject::connect(&idle, &QTimer::timeout, &app, &QCoreApplication::quit);
    QObject::connect(&chooser, &FileChooser::busyChanged, &idle, [&idle](bool busy) {
        if (busy)
            idle.stop();
        else
            idle.start();
    });
    idle.start();

    return app.exec();
}

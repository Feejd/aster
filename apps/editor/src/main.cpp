// aster-editor — Edytor tekstu Aster.
//   aster-editor                 ostatnie karty (także niezapisane) albo nowa, pusta
//   aster-editor PLIK…           pliki w kartach; gdy edytor już działa — karty w jego oknie (D-Bus: org.aster.editor)

#include "editor.h"

#include <KWindowSystem>
#include <QDBusConnection>
#include <QDBusMessage>
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
    app.setApplicationName(QStringLiteral("aster-editor"));
    app.setApplicationDisplayName(QStringLiteral("Edytor tekstu"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.editor"));

    QStringList files;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        files << QFileInfo(url.isLocalFile() ? url.toLocalFile() : args.at(i)).absoluteFilePath();
    }

    const QString service = QStringLiteral("org.aster.editor");
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && qEnvironmentVariable("ASTER_SHOT").isEmpty()) {
        if (!bus.registerService(service)) {
            // Już działa — pliki do jego okna (bez plików: tylko przywołanie)
            QDBusMessage m = QDBusMessage::createMethodCall(service, QStringLiteral("/"), service, QStringLiteral("openFiles"));
            m << files;
            bus.call(m, QDBus::Block, 2000);
            return 0;
        }
    }
    Editor::s_pending = files;

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Editor", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    // Ten sam obiekt co „Editor” w QML — przez niego drugie uruchomienie dokłada karty
    auto *editor = engine.singletonInstance<Editor *>("Aster.Editor", "Editor");
    if (bus.isConnected() && qEnvironmentVariable("ASTER_SHOT").isEmpty())
        bus.registerObject(QStringLiteral("/"), editor, QDBusConnection::ExportAllSlots);
    QObject::connect(editor, &Editor::openRequested, window, [window] {
        if (window->visibility() == QWindow::Minimized)
            window->showNormal();
        KWindowSystem::activateWindow(window);
    });

    // Do testów: ASTER_OPEN=find:tekst|replace|menu|goto|close, ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(1500, window, [window, open] { QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, open)); });
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

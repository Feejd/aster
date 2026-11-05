// aster-vault — Aster Vault, program do baz danych (SQLite, PostgreSQL, MySQL/MariaDB).
//   aster-vault                    okno: zapisane połączenia
//   aster-vault PLIK.db            okno z otwartym plikiem SQLite
//   aster-vault --list | --schema | --query …   odczyt z terminala (dla asystenta: --json)
//   aster-vault --service          usługa D-Bus org.aster.Vault (tylko odczyt)

#include "agent.h"
#include "vault.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include <cstdio>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

static void names(QCoreApplication &app)
{
    app.setApplicationName(QStringLiteral("aster-vault"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
}

int main(int argc, char *argv[])
{
    QStringList cli;
    for (int i = 1; i < argc; ++i)
        cli << QString::fromLocal8Bit(argv[i]);
    static const QStringList cliModes{QStringLiteral("--list"), QStringLiteral("--schema"), QStringLiteral("--query"), QStringLiteral("--help"), QStringLiteral("-h")};
    for (const QString &a : std::as_const(cli)) {
        if (cliModes.contains(a)) {
            QCoreApplication app(argc, argv);
            names(app);
            return Agent::runCli(app.arguments());
        }
    }
    if (cli.contains(QStringLiteral("--service"))) {
        QCoreApplication app(argc, argv);
        names(app);
        VaultService service;
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.registerObject(QStringLiteral("/org/aster/Vault"), &service, QDBusConnection::ExportAllSlots)
            || !bus.registerService(QStringLiteral("org.aster.Vault"))) {
            std::fprintf(stderr, "aster-vault: nie można zarejestrować org.aster.Vault na szynie sesji\n");
            return 1;
        }
        return app.exec();
    }

    QGuiApplication app(argc, argv);
    asterTypography();
    names(app);
    app.setApplicationDisplayName(QStringLiteral("Aster Vault"));
    app.setDesktopFileName(QStringLiteral("org.aster.vault"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Vault", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    for (const QString &a : std::as_const(cli)) {
        if (a.startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(a);
        const QFileInfo fi(url.isLocalFile() ? url.toLocalFile() : a);
        if (auto *vault = engine.singletonInstance<Vault *>("Aster.Vault", "Vault"))
            vault->openFile(fi.absoluteFilePath());
        break;
    }

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

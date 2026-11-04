// aster-webapps — Aplikacje webowe: zamienia strony w programy, które wyglądają i działają jak natywne.
//   aster-webapps                      menedżer (polecane aplikacje, dodawanie własnych)
//   aster-webapps --run <id>           okno zainstalowanej aplikacji
//   aster-webapps --install <adres>    menedżer z gotowym podglądem strony
//   aster-webapps aster-webapp:install?url=…   to samo z przeglądarki (własny schemat adresów)
//   aster-webapps --add <adres> [--name N] [--category K] [--color #RRGGBB]
//                                      instalacja bez okna (skrypty, obraz systemu)
//   aster-webapps --remove <id>        usunięcie bez okna (Sklep)

#include "runtime.h"
#include "webapps.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QtQml/qqmlextensionplugin.h>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);

    asterTypography();
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));

    const QStringList args = app.arguments();
    const int run = args.indexOf(QStringLiteral("--run"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);

    // ——— Instalacja bez okna ———
    const int add = args.indexOf(QStringLiteral("--add"));
    if (add > 0 && add + 1 < args.size()) {
        const auto opt = [&args](const QString &name) {
            const int i = args.indexOf(name);
            return i > 0 && i + 1 < args.size() ? args.at(i + 1) : QString();
        };
        auto *apps = new WebApps(&app);
        QObject::connect(apps, &WebApps::inspected, apps, [apps, opt](QVariantMap info) {
            if (!opt(QStringLiteral("--name")).isEmpty())
                info[QStringLiteral("name")] = opt(QStringLiteral("--name"));
            if (!opt(QStringLiteral("--category")).isEmpty())
                info[QStringLiteral("category")] = opt(QStringLiteral("--category"));
            if (!opt(QStringLiteral("--color")).isEmpty())
                info[QStringLiteral("themeColor")] = opt(QStringLiteral("--color"));
            apps->install(info);
        });
        QObject::connect(apps, &WebApps::installedApp, &app, [](const QString &id) {
            qInfo("Zainstalowano: %s", qPrintable(id));
            QCoreApplication::exit(0);
        });
        QObject::connect(apps, &WebApps::failed, &app, [](const QString &message) {
            qWarning("%s", qPrintable(message));
            QCoreApplication::exit(1);
        });
        apps->inspect(args.at(add + 1));
        return app.exec();
    }

    // ——— Usunięcie bez okna ———
    const int remove = args.indexOf(QStringLiteral("--remove"));
    if (remove > 0 && remove + 1 < args.size()) {
        WebApps apps;
        apps.uninstall(args.at(remove + 1));
        return 0;
    }

    std::unique_ptr<Runtime> runtime;
    if (run > 0 && run + 1 < args.size()) {
        // ——— Okno aplikacji ———
        const QString id = args.at(run + 1);
        const QVariantMap data = WebApps::load(id);
        if (data.isEmpty()) {
            qWarning("Nie ma aplikacji webowej „%s”", qPrintable(id));
            return 1;
        }
        // Ten sam identyfikator co plik .desktop → dok pokazuje właściwą ikonę i grupuje okna
        app.setApplicationName(QStringLiteral("aster-webapp-") + id);
        app.setDesktopFileName(QStringLiteral("aster-webapp-") + id);
        app.setApplicationDisplayName(data.value(QStringLiteral("name")).toString());
        runtime = std::make_unique<Runtime>(id);
        if (runtime->forwardToRunning())
            return 0;
        engine.setInitialProperties({{QStringLiteral("app"), data}, {QStringLiteral("runtime"), QVariant::fromValue(runtime.get())}});
        engine.loadFromModule("Aster.WebApps", "WebAppWindow");
    } else {
        // ——— Menedżer ———
        app.setApplicationName(QStringLiteral("aster-webapps"));
        app.setApplicationDisplayName(QStringLiteral("Aplikacje webowe"));
        app.setDesktopFileName(QStringLiteral("org.aster.webapps"));
        QString installUrl;
        const int inst = args.indexOf(QStringLiteral("--install"));
        if (inst > 0 && inst + 1 < args.size())
            installUrl = args.at(inst + 1);
        for (const QString &a : args)
            if (a.startsWith(QLatin1String("aster-webapp:")))
                installUrl = QUrlQuery(QUrl(a).query()).queryItemValue(QStringLiteral("url"), QUrl::FullyDecoded);
        engine.setInitialProperties({{QStringLiteral("installUrl"), installUrl}});
        engine.loadFromModule("Aster.WebApps", "Manager");
    }

    // Do testów: ASTER_SHOT=plik.png zapisuje zrzut okna i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty() && !engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QTimer::singleShot(qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") : 3000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

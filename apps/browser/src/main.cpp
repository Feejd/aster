// aster-browser — Przeglądarka systemu Aster. Silnik: Qt WebEngine (Chromium).
//   aster-browser [adres…]          nowe karty w działającej przeglądarce (albo pierwsze okno)
//   aster-browser --private [adres] nowe okno prywatne
// Działa zawsze jedna kopia programu: kolejne uruchomienia tylko przekazują jej adresy,
// bo dwa procesy na jednym profilu silnika psułyby sobie nawzajem dane.

#include "browser.h"

#include <QDir>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
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
    app.setApplicationName(QStringLiteral("aster-browser"));
    app.setApplicationDisplayName(QStringLiteral("Przeglądarka"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.browser"));
    app.setQuitOnLastWindowClosed(false);       // o końcu decyduje Browser (zapisuje sesję)

    bool privateMode = false;
    QStringList urls;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a == QLatin1String("--private") || a == QLatin1String("--incognito"))
            privateMode = true;
        else if (a.startsWith(QLatin1String("--")))
            continue;
        else if (a.startsWith(QLatin1String("aster:")))
            urls << a;
        else
            urls << QUrl::fromUserInput(a, QDir::currentPath(), QUrl::AssumeLocalFile).toString();
    }

    if (Browser::forwardToRunning(urls, privateMode))
        return 0;

    QQmlApplicationEngine engine;
    Browser browser(&engine);
    browser.listen();
    browser.start(urls, privateMode);

    // Do testów: ASTER_SHOT=plik.png zapisuje zrzut pierwszego okna i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 3000, &app, [shot] {
            for (QWindow *w : QGuiApplication::topLevelWindows())
                if (auto *qw = qobject_cast<QQuickWindow *>(w); qw && qw->isVisible()) {
                    qw->grabWindow().save(shot);
                    break;
                }
            QCoreApplication::quit();
        });
    }

    return app.exec();
}

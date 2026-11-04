// aster-terminal — Terminal systemu Aster.
//   aster-terminal                          nowe okno w folderze domowym
//   aster-terminal --workdir KATALOG        nowe okno w podanym folderze (też -w, --working-directory)
//   aster-terminal -e POLECENIE [ARG…]      uruchamia polecenie zamiast powłoki (programy z Terminal=true)
//   aster-terminal --wpisz POLECENIE        wpisuje polecenie w powłokę, bez Entera (Aster Intelligence)

#include "terminal.h"
#include "terminalview.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>
#include <functional>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    asterTypography();
    app.setApplicationName(QStringLiteral("aster-terminal"));
    app.setApplicationDisplayName(QStringLiteral("Terminal"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.terminal"));

    QString dir;
    QStringList command;
    QString typeOnly;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a == QLatin1String("-e") || a == QLatin1String("-x") || a == QLatin1String("--")) {
            command = args.mid(i + 1);
            // „-e 'htop -d 5'” jako jeden argument — dzielone jak w powłoce
            if (command.size() == 1 && command.first().contains(QLatin1Char(' ')))
                command = QProcess::splitCommand(command.first());
            break;
        }
        if (a == QLatin1String("--wpisz") && i + 1 < args.size()) {
            typeOnly = args.at(++i);
            continue;
        }
        if ((a == QLatin1String("--workdir") || a == QLatin1String("-w") || a == QLatin1String("--working-directory")) && i + 1 < args.size())
            dir = args.at(++i);
        else if (a.startsWith(QLatin1String("--working-directory=")) || a.startsWith(QLatin1String("--workdir=")))
            dir = a.section(QLatin1Char('='), 1);
        else if (!a.startsWith(QLatin1Char('-')) && QFileInfo(a).isDir())
            dir = a;
    }
    if (!dir.isEmpty())
        dir = QDir(dir).absolutePath();

    QQmlApplicationEngine engine;
    Terminal terminal(&engine);
    QQuickWindow *window = terminal.openWindow(dir, command);
    if (!window)
        return 1;

    // ASTER_TYPE (testy) wpisuje i zatwierdza; --wpisz tylko wpisuje — Enter naciska użytkownik
    const QString typed = !typeOnly.isEmpty() ? typeOnly : qEnvironmentVariable("ASTER_TYPE");
    const bool enter = typeOnly.isEmpty();
    if (!typed.isEmpty())
        QTimer::singleShot(900, window, [window, typed, enter] {
            // Widok jest w delegacie Repeatera — szukamy po drzewie elementów, nie obiektów
            std::function<TerminalView *(QQuickItem *)> find = [&find](QQuickItem *item) -> TerminalView * {
                if (auto *v = qobject_cast<TerminalView *>(item))
                    return v;
                for (QQuickItem *child : item->childItems())
                    if (TerminalView *v = find(child))
                        return v;
                return nullptr;
            };
            if (TerminalView *view = find(window->contentItem()))
                view->sendText(enter ? typed + QLatin1Char('\r') : typed);
        });

    // Do testów: ASTER_OPEN=settings|find|tabs otwiera ustawienia, wyszukiwanie albo drugą kartę
    const QString open = qEnvironmentVariable("ASTER_OPEN");
    if (!open.isEmpty())
        QTimer::singleShot(1600, window, [window, open] {
            if (open == QLatin1String("settings"))
                window->setProperty("settingsOpen", true);
            else if (open == QLatin1String("tabs"))
                QMetaObject::invokeMethod(window, "newTab", Q_ARG(QVariant, QVariant()), Q_ARG(QVariant, QVariant()));
            else if (open.startsWith(QLatin1String("find:")))
                QMetaObject::invokeMethod(window, "testFind", Q_ARG(QVariant, open.mid(5)));
        });

    // Do testów: ASTER_SHOT=plik.png zapisuje zrzut okna i kończy program;
    // ASTER_TYPE=tekst wpisuje polecenie w terminal po starcie
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 2500, &app, [shot] {
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

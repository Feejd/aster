// aster-code — Aster Code, edytor kodu.
//   aster-code                 okno startowe (ostatnie foldery) albo ostatni projekt
//   aster-code FOLDER          folder jako projekt
//   aster-code PLIK…           pliki w kartach, projekt — ich folder (albo repozytorium gita nad nim)

#include "project.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    // Podgląd strony (QtWebEngine) — przed utworzeniem aplikacji
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-code"));
    app.setApplicationDisplayName(QStringLiteral("Aster Code"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.code"));

    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        const QFileInfo fi(url.isLocalFile() ? url.toLocalFile() : args.at(i));
        if (fi.isDir()) {
            Project::s_pendingFolder = fi.absoluteFilePath();
        } else {
            Project::s_pendingFiles << fi.absoluteFilePath();
            if (Project::s_pendingFolder.isEmpty()) {
                // Projekt dla pliku: repozytorium gita, w którym leży, albo jego folder
                QProcess p;
                p.start(QStringLiteral("git"), {QStringLiteral("-C"), fi.absolutePath(), QStringLiteral("rev-parse"), QStringLiteral("--show-toplevel")});
                const bool git = p.waitForFinished(2000) && p.exitCode() == 0;
                Project::s_pendingFolder = git ? QString::fromUtf8(p.readAllStandardOutput()).trimmed() : fi.absolutePath();
            }
        }
    }

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Code", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

#ifdef ASTER_CODE_TEST_HOOKS
    // Do testów (tylko build z -DASTER_CODE_TEST_HOOKS=ON): ASTER_OPEN=kroki po „;” (testOpen w Main.qml, co 1,2 s),
    // ASTER_SHOT=plik.png zapisuje zrzut okna (po ASTER_SHOT_DELAY ms, domyślnie 3 s) i kończy program
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] {
            // wheel:X,Y,DY[,shift] — prawdziwe zdarzenie kółka w oknie (DY w jednostkach kąta, 120 = jeden ząbek)
            if (step.startsWith(QLatin1String("wheel:"))) {
                const QStringList a = step.mid(6).split(QLatin1Char(','));
                const QPointF pos(a.value(0).toDouble(), a.value(1).toDouble());
                const bool shift = a.value(3) == QLatin1String("shift");
                QWheelEvent ev(pos, window->mapToGlobal(pos), QPoint(), QPoint(0, a.value(2).toInt()), Qt::NoButton,
                               shift ? Qt::ShiftModifier : Qt::NoModifier, Qt::NoScrollPhase, false);
                QCoreApplication::sendEvent(window, &ev);
                return;
            }
            // wheelpx:X,Y,DY — jak touchpad (delta w pikselach); key:NAZWA — klawisz (PageDown…); drag:X1,Y1,X2,Y2 — przeciągnięcie
            if (step.startsWith(QLatin1String("wheelpx:"))) {
                const QStringList a = step.mid(8).split(QLatin1Char(','));
                const QPointF pos(a.value(0).toDouble(), a.value(1).toDouble());
                const int dy = a.value(2).toInt();
                QWheelEvent ev(pos, window->mapToGlobal(pos), QPoint(0, dy), QPoint(0, dy * 2), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
                QCoreApplication::sendEvent(window, &ev);
                return;
            }
            // hover:X,Y — ruch myszy bez przycisku (podpisy przycisków)
            if (step.startsWith(QLatin1String("hover:"))) {
                const QStringList a = step.mid(6).split(QLatin1Char(','));
                const QPointF p(a.value(0).toDouble(), a.value(1).toDouble());
                QMouseEvent ev(QEvent::MouseMove, p, window->mapToGlobal(p), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::sendEvent(window, &ev);
                return;
            }
            if (step.startsWith(QLatin1String("key:"))) {
                const QKeySequence seq(step.mid(4));
                const int k = seq.isEmpty() ? 0 : seq[0].key();
                QKeyEvent press(QEvent::KeyPress, k, Qt::NoModifier), release(QEvent::KeyRelease, k, Qt::NoModifier);
                QCoreApplication::sendEvent(window, &press);
                QCoreApplication::sendEvent(window, &release);
                return;
            }
            if (step.startsWith(QLatin1String("drag:"))) {
                const QStringList a = step.mid(5).split(QLatin1Char(','));
                const QPointF p1(a.value(0).toDouble(), a.value(1).toDouble()), p2(a.value(2).toDouble(), a.value(3).toDouble());
                const auto send = [window](QEvent::Type t, QPointF p, Qt::MouseButton b, Qt::MouseButtons bs) {
                    QMouseEvent ev(t, p, window->mapToGlobal(p), b, bs, Qt::NoModifier);
                    QCoreApplication::sendEvent(window, &ev);
                };
                send(QEvent::MouseButtonPress, p1, Qt::LeftButton, Qt::LeftButton);
                for (int i = 1; i <= 8; ++i)
                    send(QEvent::MouseMove, p1 + (p2 - p1) * (i / 8.0), Qt::NoButton, Qt::LeftButton);
                send(QEvent::MouseButtonRelease, p2, Qt::LeftButton, Qt::NoButton);
                return;
            }
            QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step));
        });
    const QString shot = qEnvironmentVariable("ASTER_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("ASTER_SHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 3000, &app, [window, shot] {
            window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }
#else
    Q_UNUSED(window)
#endif
    return app.exec();
}

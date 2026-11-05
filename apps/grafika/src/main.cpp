// aster-grafika — Aster Pixel: posty, plakaty, zaproszenia, CV i miniaturki bez internetu, z gotowych szablonów.

#include "library.h"
#include "online.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QMouseEvent>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-grafika"));
    app.setApplicationDisplayName(QStringLiteral("Aster Pixel"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.grafika"));

    Online::loadDownloadedFonts();

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("thumb"), new ThumbProvider);
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Grafika", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    // Projekt podany w wierszu poleceń (dwuklik na pliku .grafika w Plikach)
    const QStringList args = app.arguments();
    if (args.size() > 1) {
        const QString file = args.at(1).startsWith(QLatin1String("file:")) ? QUrl(args.at(1)).toLocalFile() : args.at(1);
        QMetaObject::invokeMethod(window, "openProject", Q_ARG(QVariant, file));
    }

    // Do testów: ASTER_OPEN=kroki rozdzielone „;” (testOpen w Main.qml, co 1,2 s), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms)
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] {
            // drag:x0,y0,x1,y1[,alt|shift] — prawdziwe zdarzenia myszy w oknie (punkty okna), jak ruch człowieka
            // path:x,y,x,y,… — to samo po kilku punktach (lasso)
            if (step.startsWith(QLatin1String("path:"))) {
                const QStringList a = step.mid(5).split(QLatin1Char(','));
                auto at = [&a](int i) { return QPointF(a.value(2 * i).toDouble(), a.value(2 * i + 1).toDouble()); };
                auto send = [window](QEvent::Type type, const QPointF &p, Qt::MouseButton button, Qt::MouseButtons held) {
                    QMouseEvent e(type, p, p, window->mapToGlobal(p), button, held, Qt::NoModifier);
                    QCoreApplication::sendEvent(window, &e);
                };
                send(QEvent::MouseMove, at(0), Qt::NoButton, Qt::NoButton);
                send(QEvent::MouseButtonPress, at(0), Qt::LeftButton, Qt::LeftButton);
                const int n = int(a.size() / 2);
                for (int i = 1; i < n; ++i)
                    for (int k = 1; k <= 8; ++k)
                        send(QEvent::MouseMove, at(i - 1) + (at(i) - at(i - 1)) * (k / 8.0), Qt::NoButton, Qt::LeftButton);
                send(QEvent::MouseButtonRelease, at(n - 1), Qt::LeftButton, Qt::NoButton);
                return;
            }
            if (step.startsWith(QLatin1String("drag:"))) {
                const QStringList a = step.mid(5).split(QLatin1Char(','));
                const QPointF from(a.value(0).toDouble(), a.value(1).toDouble()), to(a.value(2).toDouble(), a.value(3).toDouble());
                const Qt::KeyboardModifiers mods = a.value(4) == QLatin1String("shift") ? Qt::ShiftModifier : a.size() > 4 ? Qt::AltModifier : Qt::NoModifier;
                auto send = [window, mods](QEvent::Type type, const QPointF &p, Qt::MouseButton button, Qt::MouseButtons held) {
                    QMouseEvent e(type, p, p, window->mapToGlobal(p), button, held, mods);
                    QCoreApplication::sendEvent(window, &e);
                };
                send(QEvent::MouseMove, from, Qt::NoButton, Qt::NoButton);
                send(QEvent::MouseButtonPress, from, Qt::LeftButton, Qt::LeftButton);
                for (int k = 1; k <= 24; ++k)
                    send(QEvent::MouseMove, from + (to - from) * (k / 24.0), Qt::NoButton, Qt::LeftButton);
                send(QEvent::MouseButtonRelease, to, Qt::LeftButton, Qt::NoButton);
                return;
            }
            QMetaObject::invokeMethod(window, "testOpen", Q_ARG(QVariant, step));
        });
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

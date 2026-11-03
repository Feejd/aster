// aster-montaz — Montaż Aster: prosty edytor filmów (TikTok, Reels, YouTube, wakacje).
//   aster-montaz                 projekty i nowy projekt
//   aster-montaz PLIK…           nowy projekt z tymi filmami, zdjęciami i muzyką

#include "engine.h"
#include "project.h"

#include <QFileInfo>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

#include <mlt++/Mlt.h>

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-montaz"));
    app.setApplicationDisplayName(QStringLiteral("Montaż"));
    app.setApplicationVersion(QStringLiteral("1.0"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setOrganizationDomain(QStringLiteral("aster.local"));
    app.setDesktopFileName(QStringLiteral("org.aster.montaz"));

    // MLT: wtyczki z systemu; aplikacja Qt już istnieje, więc moduł qt (napisy) z niej korzysta
    Mlt::Factory::init();

    QStringList files;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args.at(i).startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(args.at(i));
        files << (url.isLocalFile() ? url.toLocalFile() : QFileInfo(args.at(i)).absoluteFilePath());
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("mthumb"), new ThumbProvider);
    engine.addImageProvider(QStringLiteral("mwave"), new WaveProvider);
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Montaz", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!files.isEmpty())
        QMetaObject::invokeMethod(window, "startWith", Q_ARG(QVariant, files));

    // Do testów: ASTER_OPEN=kroki rozdzielone „;” (testOpen w Main.qml, co 1,2 s), ASTER_SHOT=plik.png (ASTER_SHOT_DELAY ms).
    // Krok drag:x1,y1,x2,y2 przeciąga myszą w oknie (współrzędne okna) — sprawdza przycinanie i przesuwanie.
    const QStringList steps = qEnvironmentVariable("ASTER_OPEN").split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (int i = 0; i < steps.size(); ++i)
        QTimer::singleShot(1200 * (i + 1), window, [window, step = steps.at(i)] {
            if (step.startsWith(QLatin1String("drag:"))) {
                const QStringList v = step.mid(5).split(QLatin1Char(','));
                if (v.size() != 4)
                    return;
                const QPointF a(v[0].toDouble(), v[1].toDouble()), b(v[2].toDouble(), v[3].toDouble());
                auto send = [window](QEvent::Type type, QPointF p, Qt::MouseButtons buttons) {
                    QMouseEvent e(type, p, window->mapToGlobal(p), type == QEvent::MouseMove ? Qt::NoButton : Qt::LeftButton, buttons, Qt::NoModifier);
                    QCoreApplication::sendEvent(window, &e);
                };
                send(QEvent::MouseButtonPress, a, Qt::LeftButton);
                for (int k = 1; k <= 10; ++k)
                    send(QEvent::MouseMove, a + (b - a) * k / 10.0, Qt::LeftButton);
                send(QEvent::MouseButtonRelease, b, Qt::NoButton);
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

// aster-shell — powłoka systemu Aster.
// Działa w sesji KWin (Wayland) zamiast plasmashell: tapeta, dok i górna wyspa
// to osobne okna warstwy (wlr-layer-shell), ustawiane w QML przez Platform.makeLayer().

#include "platform.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <algorithm>
#include <QPainter>
#include <QPainterPath>
#include <QtQml/qqmlextensionplugin.h>
#include "typography.h"

Q_IMPORT_QML_PLUGIN(Aster_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    asterTypography();
    app.setApplicationName(QStringLiteral("aster-shell"));
    app.setOrganizationName(QStringLiteral("Aster"));
    app.setDesktopFileName(QStringLiteral("org.aster.shell"));
    app.setQuitOnLastWindowClosed(false);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Aster.Shell", "Shell");

    // Do testów: ASTER_SHOT_DESKTOP=plik.png składa podgląd całego pulpitu z okien powłoki
    // (tapeta, dok, wyspa, zegar) i udaje rozmycie KWin pod szklanymi obszarami
    const QString desktopShot = qEnvironmentVariable("ASTER_SHOT_DESKTOP");
    if (!desktopShot.isEmpty()) {
        QTimer::singleShot(qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SHOT_DELAY") : 3000, &app, [&engine, desktopShot] {
            auto *platform = engine.singletonInstance<Platform *>("Aster.Shell", "Platform");
            QList<QQuickWindow *> windows;
            QQuickWindow *wallpaper = nullptr;
            for (QWindow *w : QGuiApplication::topLevelWindows())
                if (auto *qw = qobject_cast<QQuickWindow *>(w); qw && qw->isVisible()) {
                    if (qw->title() == QLatin1String("Tapeta")) wallpaper = qw;
                    else windows << qw;
                }
            if (!wallpaper)
                return QCoreApplication::quit();
            const QImage base = wallpaper->grabWindow().convertToFormat(QImage::Format_ARGB32_Premultiplied);
            const QSize S = base.size();
            // „Rozmycie”: zmniejszenie i powiększenie z wygładzaniem, trzy razy
            QImage blurred = base;
            for (int i = 0; i < 3; ++i)
                blurred = blurred.scaled(S / 12, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).scaled(S, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            QImage out = base;
            QPainter p(&out);
            p.setRenderHint(QPainter::Antialiasing);
            // kolejność: pulpit (zegar) → wyspa → dok → Start
            std::sort(windows.begin(), windows.end(), [](QQuickWindow *a, QQuickWindow *b) {
                static const QStringList order{QStringLiteral("Zegar"), QStringLiteral("Horyzont"), QStringLiteral("Dok"), QStringLiteral("Start"),
                                                QStringLiteral("Centrum sterowania"), QStringLiteral("Asystent")};
                return order.indexOf(a->title()) < order.indexOf(b->title());
            });
            for (QQuickWindow *w : windows) {
                const QImage img = w->grabWindow();
                // okna przyklejone do krawędzi podają swoje miejsce na ekranie (shotX/shotY)
                const QPoint pos(w->property("shotX").toInt(), w->property("shotY").toInt());
                for (const QVariant &v : platform->blurRegions.value(w)) {
                    const QVariantMap r = v.toMap();
                    QPainterPath path;
                    path.addRoundedRect(QRectF(pos.x() + r.value(QStringLiteral("x")).toReal(), pos.y() + r.value(QStringLiteral("y")).toReal(),
                                               r.value(QStringLiteral("w")).toReal(), r.value(QStringLiteral("h")).toReal()),
                                        r.value(QStringLiteral("r")).toReal(), r.value(QStringLiteral("r")).toReal());
                    p.save();
                    p.setClipPath(path);
                    p.drawImage(0, 0, blurred);
                    p.restore();
                }
                p.drawImage(pos, img);
            }
            p.end();
            out.save(desktopShot);
            QCoreApplication::quit();
        });
    }

    // Do testów: ASTER_SHOT_START=plik.png otwiera Start, zapisuje jego zrzut i kończy program
    const QString shot = qEnvironmentVariable("ASTER_SHOT_START");
    if (!shot.isEmpty()) {
        QTimer::singleShot(1000, &app, [&engine] {
            if (auto *platform = engine.singletonInstance<Platform *>("Aster.Shell", "Platform"))
                platform->activateLauncherMenu();
        });
        // razem z ASTER_SHOT_DESKTOP: tylko otwórz Start, zrzut zrobi podgląd pulpitu
        if (desktopShot.isEmpty())
            QTimer::singleShot(2200, &app, [shot] {
                for (QWindow *w : QGuiApplication::topLevelWindows())
                    if (w->title() == QLatin1String("Start"))
                        if (auto *qw = qobject_cast<QQuickWindow *>(w))
                            qw->grabWindow().save(shot);
                QCoreApplication::quit();
            });
    }

    // Do testów: ASTER_OPEN_CONTROL=1 otwiera centrum sterowania (np. razem z ASTER_SHOT_DESKTOP)
    if (!qEnvironmentVariableIsEmpty("ASTER_OPEN_CONTROL"))
        QTimer::singleShot(1000, &app, [] {
            for (QWindow *w : QGuiApplication::topLevelWindows())
                if (w->title() == QLatin1String("Centrum sterowania"))
                    QMetaObject::invokeMethod(w, "toggle");
        });

    // Do testów: ASTER_OPEN_ASSISTANT=1 otwiera panel asystenta (pusty albo z ASTER_SHOT_ASK)
    if (!qEnvironmentVariableIsEmpty("ASTER_OPEN_ASSISTANT"))
        QTimer::singleShot(1000, &app, [] {
            for (QWindow *w : QGuiApplication::topLevelWindows())
                if (w->title() == QLatin1String("Asystent"))
                    QMetaObject::invokeMethod(w, "show");
        });

    // Do testów: ASTER_SHOT_NOTIFY=1 pokazuje przykładowe powiadomienie (dynamiczna wyspa jako karta)
    if (!qEnvironmentVariableIsEmpty("ASTER_SHOT_NOTIFY"))
        QTimer::singleShot(1200, &app, [&engine] {
            if (auto *platform = engine.singletonInstance<Platform *>("Aster.Shell", "Platform"))
                Q_EMIT platform->notificationPosted({{QStringLiteral("id"), 1u},
                                                     {QStringLiteral("appName"), QStringLiteral("Wiadomości")},
                                                     {QStringLiteral("icon"), QStringLiteral("mail-message")},
                                                     {QStringLiteral("summary"), QStringLiteral("Ola")},
                                                     {QStringLiteral("body"), QStringLiteral("Wpadniesz dziś na kawę? Mam nowe zdjęcia z gór ☕")},
                                                     {QStringLiteral("image"), QString()}});
        });

    return app.exec();
}

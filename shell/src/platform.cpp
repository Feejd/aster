#include "platform.h"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QHash>
#include <QPainterPath>
#include <QProcess>
#include <QQuickWindow>
#include <QRegion>
#include <QStandardPaths>

using LayerWindow = LayerShellQt::Window;

Platform::Platform(QObject *parent)
    : QObject(parent)
{
}

QString Platform::dataDir() const
{
    const QByteArray env = qgetenv("ASTER_DATA_DIR");
    if (!env.isEmpty())
        return QString::fromLocal8Bit(env);
    const QString found = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("aster"),
                                                 QStandardPaths::LocateDirectory);
    return found.isEmpty() ? QStringLiteral(ASTER_INSTALL_DATADIR) : found;
}

void Platform::makeLayer(QQuickWindow *window, const QString &layer, int anchors, int exclusiveZone,
                         const QString &keyboard, const QString &scope)
{
    if (!window)
        return;
    LayerWindow *lw = LayerWindow::get(window);
    if (!lw)
        return;

    static const QHash<QString, LayerWindow::Layer> layers{
        {QStringLiteral("background"), LayerWindow::LayerBackground},
        {QStringLiteral("bottom"), LayerWindow::LayerBottom},
        {QStringLiteral("top"), LayerWindow::LayerTop},
        {QStringLiteral("overlay"), LayerWindow::LayerOverlay},
    };
    static const QHash<QString, LayerWindow::KeyboardInteractivity> keyboards{
        {QStringLiteral("none"), LayerWindow::KeyboardInteractivityNone},
        {QStringLiteral("exclusive"), LayerWindow::KeyboardInteractivityExclusive},
        {QStringLiteral("ondemand"), LayerWindow::KeyboardInteractivityOnDemand},
    };

    lw->setLayer(layers.value(layer, LayerWindow::LayerTop));
    lw->setAnchors(LayerWindow::Anchors::fromInt(anchors));
    lw->setExclusiveZone(exclusiveZone);
    lw->setKeyboardInteractivity(keyboards.value(keyboard, LayerWindow::KeyboardInteractivityNone));
    lw->setScope(scope);
}

void Platform::setBlur(QQuickWindow *window, const QVariantList &rects)
{
    if (!window)
        return;
    QRegion region;
    for (const QVariant &v : rects) {
        const QVariantMap m = v.toMap();
        const QRectF r(m.value(QStringLiteral("x")).toReal(), m.value(QStringLiteral("y")).toReal(),
                       m.value(QStringLiteral("w")).toReal(), m.value(QStringLiteral("h")).toReal());
        const qreal radius = m.value(QStringLiteral("r")).toReal();
        QPainterPath path;
        path.addRoundedRect(r, radius, radius);
        region += QRegion(path.toFillPolygon().toPolygon());
    }
    KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
}

void Platform::run(const QString &program, const QStringList &args)
{
    QProcess::startDetached(program, args);
}

#include "windoweffects.h"

#include <KWindowEffects>

#include <QPainterPath>
#include <QRegion>

WindowEffects::WindowEffects(QObject *parent)
    : QObject(parent)
{
}

void WindowEffects::setBlur(QQuickWindow *window, const QRectF &rect, qreal radius)
{
    if (!window)
        return;
    QPainterPath path;
    path.addRoundedRect(rect, radius, radius);
    KWindowEffects::enableBlurBehind(window, true, QRegion(path.toFillPolygon().toPolygon()));
}

void WindowEffects::setInputRegion(QQuickWindow *window, const QRectF &rect)
{
    if (window)
        window->setMask(QRegion(rect.toAlignedRect()));
}

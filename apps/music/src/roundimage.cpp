#include "roundimage.h"

#include <QCache>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QQuickWindow>

RoundImage::RoundImage(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void RoundImage::setSource(const QString &s)
{
    if (s == m_source)
        return;
    m_source = s;
    reload();
    Q_EMIT sourceChanged();
}

void RoundImage::setRadius(qreal r)
{
    if (qFuzzyCompare(r, m_radius))
        return;
    m_radius = r;
    update();
    Q_EMIT radiusChanged();
}

void RoundImage::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    // Wczytaj ponownie tylko przy wyraźnie większym rozmiarze (przy mniejszym wystarczy skalowanie)
    if (!m_image.isNull() && newGeometry.width() * 1.3 < m_image.width() / qMax(1.0, window() ? window()->devicePixelRatio() : 1.0) + 1)
        return;
    if (newGeometry.size() != oldGeometry.size())
        reload();
}

void RoundImage::reload()
{
    const bool was = !m_image.isNull();
    m_image = {};
    const qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
    const int side = qBound(16, int(qMax(width(), height()) * dpr), 1200);
    if (!m_source.isEmpty() && width() > 0) {
        // Rozmiar zaokrąglony w górę do 64 px — kafelki o podobnej wielkości dzielą wpis w pamięci
        const int bucket = (side + 63) / 64 * 64;
        static QCache<QString, QImage> cache(60 * 1024 * 1024);
        const QString key = m_source + QLatin1Char('@') + QString::number(bucket);
        if (QImage *hit = cache.object(key)) {
            m_image = *hit;
        } else {
            QImageReader r(m_source);
            r.setAutoTransform(true);
            const QSize s = r.size();
            if (s.isValid() && qMin(s.width(), s.height()) > bucket)
                r.setScaledSize(s.scaled(bucket, bucket, Qt::KeepAspectRatioByExpanding));
            QImage img = r.read();
            if (!img.isNull()) {
                m_image = img;
                cache.insert(key, new QImage(img), int(img.sizeInBytes()));
            }
        }
    }
    if (was != !m_image.isNull())
        Q_EMIT readyChanged();
    update();
}

void RoundImage::paint(QPainter *p)
{
    if (m_image.isNull())
        return;
    p->setRenderHint(QPainter::Antialiasing);
    p->setRenderHint(QPainter::SmoothPixmapTransform);
    QPainterPath path;
    path.addRoundedRect(QRectF(0, 0, width(), height()), m_radius, m_radius);
    p->setClipPath(path);
    // Wypełnij, przycinając nadmiar (jak PreserveAspectCrop)
    const QSizeF target = QSizeF(m_image.size()).scaled(QSizeF(width(), height()), Qt::KeepAspectRatioByExpanding);
    const QRectF r((width() - target.width()) / 2, (height() - target.height()) / 2, target.width(), target.height());
    p->drawImage(r, m_image);
}

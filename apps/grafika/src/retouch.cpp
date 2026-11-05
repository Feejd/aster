#include "retouch.h"
#include "art.h"
#include "project.h"
#include "selection.h"

#include <QBuffer>
#include <QPainter>
#include <QThreadPool>
#include <QtMath>
#include <algorithm>
#include <cmath>

Retouch::Retouch(QObject *parent)
    : QObject(parent)
    , m_pool(new QThreadPool(this))
{
    m_pool->setMaxThreadCount(1);           // kreski zapisują się po kolei
    m_live.setInterval(33);
    connect(&m_live, &QTimer::timeout, this, &Retouch::flush);
}

Retouch::~Retouch()
{
    m_pool->waitForDone();
}

void Retouch::setTool(const QString &tool)
{
    if (m_tool != tool) {
        m_tool = tool;
        Q_EMIT settingsChanged();
    }
}

void Retouch::setColor(const QString &color)
{
    if (m_color != color) {
        m_color = color;
        Q_EMIT settingsChanged();
    }
}

void Retouch::setSize(qreal size)
{
    if (!qFuzzyCompare(m_size, size)) {
        m_size = qMax(1.0, size);
        Q_EMIT settingsChanged();
    }
}

void Retouch::setHardness(qreal hardness)
{
    if (!qFuzzyCompare(m_hardness, hardness)) {
        m_hardness = qBound(0.0, hardness, 1.0);
        Q_EMIT settingsChanged();
    }
}

void Retouch::setStrength(qreal strength)
{
    if (!qFuzzyCompare(m_strength, strength)) {
        m_strength = qBound(0.0, strength, 1.0);
        Q_EMIT settingsChanged();
    }
}

// Zdjęcie warstwy i przeliczanie strona → piksele zdjęcia. Po cofnięciu `src` jest inny — wtedy wczytuje od nowa.
bool Retouch::load(Project *project, const QString &id)
{
    if (!project)
        return false;
    const QVariantMap el = project->get(id);
    const QString key = el.value(QStringLiteral("src")).toString();
    if (key.isEmpty())
        return false;
    if (m_project != project || m_id != id || m_key != key || m_img.isNull()) {
        if (m_saving > 0 && m_project == project && m_id == id)
            return false;                   // poprzednia kreska jeszcze się zapisuje
        const QImage full = project->fullImage(key);
        if (full.isNull())
            return false;
        m_img = full.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        m_key = key;
    }
    m_project = project;
    m_id = id;
    m_el = el;
    const QTransform frame = Art::frameTransform(el, m_img.size());
    m_toImage = Art::pageToFrame(el) * frame.inverted();
    m_scale = qSqrt(qAbs(m_toImage.determinant()));
    Selection *sel = Selection::instance();
    m_clip = sel && sel->active() ? sel->mapped(m_toImage, m_img.size()) : QImage();
    return true;
}

void Retouch::setSource(Project *project, const QString &id, qreal x, qreal y)
{
    if (!load(project, id))
        return;
    m_sourceImage = m_toImage.map(QPointF(x, y));
    m_sourcePage = m_sourcePageStart = QPointF(x, y);
    m_hasSource = true;
    m_aligned = false;
    Q_EMIT sourceChanged();
}

bool Retouch::press(Project *project, const QString &id, qreal x, qreal y)
{
    if (m_tool == QLatin1String("clone") && !m_hasSource) {
        Q_EMIT failed(QStringLiteral("Najpierw Alt+klik w miejsce, z którego stempel ma kopiować."));
        return false;
    }
    if (!load(project, id)) {
        Q_EMIT failed(QStringLiteral("Tej warstwy nie da się teraz malować — spróbuj za chwilę."));
        return false;
    }
    const QPointF at = m_toImage.map(QPointF(x, y));
    m_base = m_img;
    m_mask = QImage(m_img.size(), QImage::Format_Alpha8);
    m_mask.fill(0);
    m_radius = qMax(0.5, m_size * m_scale / 2);
    QColor ink = QColor::fromString(m_color);
    m_ink = ink.isValid() ? qPremultiply(ink.rgba()) : qRgba(0, 0, 0, 255);
    if (m_tool == QLatin1String("clone")) {
        if (!m_aligned) {
            m_offset = m_sourceImage - at;
            m_pressPage = QPointF(x, y);
            m_aligned = true;
        }
    } else if (m_tool == QLatin1String("blur")) {
        m_blurred = m_img;
        Art::blur(m_blurred, qMax(1, qRound(m_radius * 0.35)));
    } else if (m_tool == QLatin1String("smudge")) {
        const int side = qCeil(m_radius * 2) + 1;
        m_carry = m_img.copy(qRound(at.x() - side / 2.0), qRound(at.y() - side / 2.0), side, side);
    }
    m_active = true;
    m_last = at;
    m_left = 0;
    dab(at);
    m_dirty = true;
    m_live.start();
    flush();
    return true;
}

void Retouch::move(qreal x, qreal y)
{
    if (!m_active)
        return;
    dabsTo(m_toImage.map(QPointF(x, y)));
    if (m_tool == QLatin1String("clone")) {
        m_sourcePage = m_sourcePageStart + (QPointF(x, y) - m_pressPage);
        Q_EMIT sourceChanged();
    }
}

void Retouch::dabsTo(const QPointF &to)
{
    const QPointF d = to - m_last;
    const qreal dist = std::hypot(d.x(), d.y());
    const qreal gap = qMax(1.0, m_radius * (m_tool == QLatin1String("smudge") ? 0.2 : 0.25));
    qreal pos = gap - m_left;
    while (pos <= dist) {
        dab(m_last + d * (pos / dist));
        pos += gap;
    }
    m_left = dist - (pos - gap);
    m_last = to;
    m_dirty = true;
}

static inline int mix(int a, int b, int t)
{
    return (a * (255 - t) + b * t + 127) / 255;
}

static inline QRgb lerp(QRgb a, QRgb b, int t)
{
    return qRgba(mix(qRed(a), qRed(b), t), mix(qGreen(a), qGreen(b), t), mix(qBlue(a), qBlue(b), t), mix(qAlpha(a), qAlpha(b), t));
}

void Retouch::dab(const QPointF &c)
{
    if (m_tool == QLatin1String("smudge")) {
        smudge(c);
        return;
    }
    const qreal r = m_radius;
    const QRect box = QRect(qFloor(c.x() - r) - 1, qFloor(c.y() - r) - 1, qCeil(2 * r) + 3, qCeil(2 * r) + 3) & m_img.rect();
    const qreal hard = qMin(0.98, m_hardness);
    const int power = qRound(m_strength * 255);
    enum { Paint, Erase, Clone, Dodge, Burn, Soft } kind = m_tool == QLatin1String("eraser") ? Erase : m_tool == QLatin1String("clone") ? Clone
        : m_tool == QLatin1String("dodge") ? Dodge : m_tool == QLatin1String("burn") ? Burn : m_tool == QLatin1String("blur") ? Soft : Paint;
    const int dx = qRound(m_offset.x()), dy = qRound(m_offset.y());
    const int W = m_img.width(), H = m_img.height();
    for (int y = box.top(); y <= box.bottom(); ++y) {
        uchar *mask = m_mask.scanLine(y);
        QRgb *out = reinterpret_cast<QRgb *>(m_img.scanLine(y));
        const QRgb *base = reinterpret_cast<const QRgb *>(m_base.constScanLine(y));
        const uchar *clip = m_clip.isNull() ? nullptr : m_clip.constScanLine(y);
        for (int x = box.left(); x <= box.right(); ++x) {
            if (clip && clip[x] == 0)
                continue;
            const qreal d = std::hypot(x + 0.5 - c.x(), y + 0.5 - c.y()) / r;
            if (d >= 1)
                continue;
            qreal a = 1;
            if (d > hard) {
                const qreal t = (1 - d) / (1 - hard);
                a = t * t * (3 - 2 * t);
            }
            const int v = int(a * 255);
            if (v <= mask[x])
                continue;
            mask[x] = uchar(v);
            const int t = clip ? v * power / 255 * clip[x] / 255 : v * power / 255;
            const QRgb px = base[x];
            switch (kind) {
            case Paint:
                out[x] = lerp(px, m_ink, t);
                break;
            case Erase:
                out[x] = lerp(px, 0, t);
                break;
            case Clone: {
                const int sx = x + dx, sy = y + dy;
                if (sx >= 0 && sy >= 0 && sx < W && sy < H)
                    out[x] = lerp(px, reinterpret_cast<const QRgb *>(m_base.constScanLine(sy))[sx], t);
                break;
            }
            case Soft:
                out[x] = lerp(px, reinterpret_cast<const QRgb *>(m_blurred.constScanLine(y))[x], t);
                break;
            case Dodge: {
                const int al = qAlpha(px), k = t / 2;
                out[x] = qRgba(mix(qRed(px), al, k), mix(qGreen(px), al, k), mix(qBlue(px), al, k), al);
                break;
            }
            case Burn: {
                const int k = t / 2;
                out[x] = qRgba(mix(qRed(px), 0, k), mix(qGreen(px), 0, k), mix(qBlue(px), 0, k), qAlpha(px));
                break;
            }
            }
        }
    }
}

// Rozmazywanie: niesiona łata miesza się z tym, co pod pędzlem, i przesuwa dalej
void Retouch::smudge(const QPointF &c)
{
    const int side = m_carry.width();
    const int x0 = qRound(c.x() - side / 2.0), y0 = qRound(c.y() - side / 2.0);
    const qreal r = side / 2.0, hard = qMin(0.9, m_hardness);
    const int power = qRound(m_strength * 235);
    for (int j = 0; j < side; ++j) {
        const int y = y0 + j;
        if (y < 0 || y >= m_img.height())
            continue;
        QRgb *out = reinterpret_cast<QRgb *>(m_img.scanLine(y));
        QRgb *patch = reinterpret_cast<QRgb *>(m_carry.scanLine(j));
        const uchar *clip = m_clip.isNull() ? nullptr : m_clip.constScanLine(y);
        for (int i = 0; i < side; ++i) {
            const int x = x0 + i;
            if (x < 0 || x >= m_img.width())
                continue;
            const qreal d = std::hypot(i + 0.5 - r, j + 0.5 - r) / r;
            if (d >= 1)
                continue;
            qreal a = 1;
            if (d > hard) {
                const qreal t = (1 - d) / (1 - hard);
                a = t * t * (3 - 2 * t);
            }
            const int t = clip ? int(a * power) * clip[x] / 255 : int(a * power);
            const QRgb mixed = lerp(out[x], patch[i], t);
            out[x] = mixed;
            patch[i] = mixed;
        }
    }
}

void Retouch::flush()
{
    if (!m_dirty || !m_project)
        return;
    m_dirty = false;
    m_project->setLive(m_key, m_img);
}

void Retouch::release()
{
    if (!m_active)
        return;
    m_active = false;
    m_live.stop();
    m_dirty = true;
    flush();
    if (m_tool == QLatin1String("clone")) {
        m_sourcePage = m_sourcePageStart;
        Q_EMIT sourceChanged();
    }
    m_base = QImage();
    m_mask = QImage();
    m_blurred = QImage();
    m_carry = QImage();
    store(m_img);
}

// PNG w tle (duże zdjęcie to pół sekundy), potem nowy plik w projekcie i krok cofania
void Retouch::store(const QImage &image)
{
    QPointer<Project> pr(m_project);
    const QString id = m_id, old = m_key;
    ++m_saving;
    m_pool->start([this, pr, id, old, image] {
        const QImage straight = image.convertToFormat(QImage::Format_ARGB32);
        QByteArray data;
        QBuffer buf(&data);
        buf.open(QIODevice::WriteOnly);
        straight.save(&buf, "PNG", 70);
        QMetaObject::invokeMethod(this, [this, pr, id, old, data = std::move(data), straight] {
            --m_saving;
            if (!pr)
                return;
            const QString key = pr->addDecoded(data, straight);
            if (m_id == id)
                m_key = key;
            if (pr->indexOf(id) >= 0)
                pr->change(id, {{QStringLiteral("src"), key}});
            if (m_active && m_id == id)
                pr->setLive(m_key, m_img);
            pr->clearLive(old);
        }, Qt::QueuedConnection);
    });
}

void Retouch::fill(Project *project, const QString &id, qreal x, qreal y, qreal tolerance)
{
    if (!load(project, id) || m_saving > 0)
        return;
    const QPoint seed = m_toImage.map(QPointF(x, y)).toPoint();
    if (!m_img.rect().contains(seed))
        return;
    const int W = m_img.width(), H = m_img.height();
    const QRgb from = m_img.pixel(seed);
    const int limit = qRound(qBound(0.0, tolerance, 1.0) * 255 * 2);
    auto similar = [&](QRgb c) {
        return std::abs(qRed(c) - qRed(from)) + std::abs(qGreen(c) - qGreen(from)) + std::abs(qBlue(c) - qBlue(from)) + std::abs(qAlpha(c) - qAlpha(from)) <= limit;
    };
    QImage mark(m_img.size(), QImage::Format_Alpha8);
    mark.fill(0);
    QList<QPoint> stack{seed};
    while (!stack.isEmpty()) {
        const QPoint p = stack.takeLast();
        const QRgb *row = reinterpret_cast<const QRgb *>(m_img.constScanLine(p.y()));
        uchar *mk = mark.scanLine(p.y());
        if (mk[p.x()])
            continue;
        int a = p.x(), b = p.x();
        while (a > 0 && !mk[a - 1] && similar(row[a - 1]))
            --a;
        while (b < W - 1 && !mk[b + 1] && similar(row[b + 1]))
            ++b;
        for (int i = a; i <= b; ++i)
            mk[i] = 255;
        for (const int ny : {p.y() - 1, p.y() + 1}) {
            if (ny < 0 || ny >= H)
                continue;
            const QRgb *nrow = reinterpret_cast<const QRgb *>(m_img.constScanLine(ny));
            const uchar *nmk = mark.constScanLine(ny);
            bool open = false;
            for (int i = a; i <= b; ++i) {
                const bool ok = !nmk[i] && similar(nrow[i]);
                if (ok && !open)
                    stack.append(QPoint(i, ny));
                open = ok;
            }
        }
    }
    // Wygładzone brzegi kresek są pośrednim kolorem i nie łapią się w tolerancję: obszar rośnie o piksel, bez obwódki
    {
        const QImage grown = mark.copy();
        for (int y2 = 0; y2 < H; ++y2) {
            const uchar *up = grown.constScanLine(qMax(0, y2 - 1)), *mid = grown.constScanLine(y2), *down = grown.constScanLine(qMin(H - 1, y2 + 1));
            uchar *mk = mark.scanLine(y2);
            for (int x2 = 0; x2 < W; ++x2)
                if (up[x2] || down[x2] || mid[qMax(0, x2 - 1)] || mid[qMin(W - 1, x2 + 1)])
                    mk[x2] = 255;
        }
    }
    const QColor ink = QColor::fromString(m_color);
    const QRgb color = ink.isValid() ? qPremultiply(ink.rgba()) : qRgba(0, 0, 0, 255);
    const int t = qRound(m_strength * 255);
    for (int y2 = 0; y2 < H; ++y2) {
        const uchar *mk = mark.constScanLine(y2);
        QRgb *o = reinterpret_cast<QRgb *>(m_img.scanLine(y2));
        for (int x2 = 0; x2 < W; ++x2)
            if (mk[x2] && (m_clip.isNull() || m_clip.constScanLine(y2)[x2]))
                o[x2] = lerp(o[x2], color, m_clip.isNull() ? t : t * m_clip.constScanLine(y2)[x2] / 255);
    }
    m_project->setLive(m_key, m_img);
    store(m_img);
}

void Retouch::clearSelected(Project *project, const QString &id)
{
    if (!load(project, id) || m_clip.isNull())
        return;
    for (int y = 0; y < m_img.height(); ++y) {
        QRgb *o = reinterpret_cast<QRgb *>(m_img.scanLine(y));
        const uchar *clip = m_clip.constScanLine(y);
        for (int x = 0; x < m_img.width(); ++x)
            if (clip[x])
                o[x] = lerp(o[x], 0, clip[x]);
    }
    m_project->setLive(m_key, m_img);
    store(m_img);
}

void Retouch::fillSelected(Project *project, const QString &id)
{
    if (!load(project, id) || m_clip.isNull())
        return;
    const QColor ink = QColor::fromString(m_color);
    const QRgb color = ink.isValid() ? qPremultiply(ink.rgba()) : qRgba(0, 0, 0, 255);
    for (int y = 0; y < m_img.height(); ++y) {
        QRgb *o = reinterpret_cast<QRgb *>(m_img.scanLine(y));
        const uchar *clip = m_clip.constScanLine(y);
        for (int x = 0; x < m_img.width(); ++x)
            if (clip[x])
                o[x] = lerp(o[x], color, clip[x]);
    }
    m_project->setLive(m_key, m_img);
    store(m_img);
}

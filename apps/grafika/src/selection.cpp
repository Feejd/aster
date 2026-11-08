#include "selection.h"
#include "art.h"
#include "project.h"
#include "retouch.h"

#include <QPainter>
#include <QPainterPath>
#include <QtMath>
#include <algorithm>
#include <cmath>

Selection *Selection::s_instance = nullptr;

Selection::Selection(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
}

Selection *Selection::instance()
{
    return s_instance;
}

static QImage toAlpha(const QImage &premultiplied)
{
    return premultiplied.convertToFormat(QImage::Format_Alpha8);
}

static QImage toPremultiplied(const QImage &alpha)
{
    return alpha.convertToFormat(QImage::Format_ARGB32_Premultiplied);
}

// Rozmiar maski wynika ze strony; nowa strona albo inny projekt zaczyna od zera
bool Selection::prepare(Project *project)
{
    if (!project)
        return false;
    const QSizeF page(project->pageWidth(), project->pageHeight());
    if (page != m_page) {
        const qreal side = qMax(page.width(), page.height());
        m_k = qBound(2048.0, side, 4096.0) / side;
        m_page = page;
        m_size = QSize(qMax(1, qRound(page.width() * m_k)), qMax(1, qRound(page.height() * m_k)));
        m_mask = QImage();
        m_history.clear();
    }
    return true;
}

QImage Selection::blank(bool premultiplied) const
{
    QImage img(m_size, premultiplied ? QImage::Format_ARGB32_Premultiplied : QImage::Format_Alpha8);
    img.fill(Qt::transparent);
    return img;
}

void Selection::remember()
{
    m_history.append(m_mask);
    if (m_history.size() > 30)
        m_history.removeFirst();
}

void Selection::set(const QImage &mask)
{
    // Pusta maska to brak zaznaczenia
    bool any = false;
    if (!mask.isNull())
        for (int y = 0; y < mask.height() && !any; ++y) {
            const uchar *row = mask.constScanLine(y);
            any = std::any_of(row, row + mask.width(), [](uchar v) { return v > 0; });
        }
    m_mask = any ? mask : QImage();
    Q_EMIT changed();
}

void Selection::combine(const QImage &shapeImage, const QString &mode, qreal feather)
{
    QImage shape = shapeImage;
    if (feather > 0)
        Art::blur(shape, qRound(feather * m_k));
    remember();
    const QImage in = toAlpha(shape);
    if (mode == QLatin1String("new") || m_mask.isNull()) {
        if (mode == QLatin1String("subtract") || mode == QLatin1String("intersect"))
            set({});
        else
            set(in);
        return;
    }
    QImage out = m_mask.copy();
    const bool add = mode == QLatin1String("add"), sub = mode == QLatin1String("subtract");
    for (int y = 0; y < out.height(); ++y) {
        uchar *o = out.scanLine(y);
        const uchar *s = in.constScanLine(y);
        for (int x = 0; x < out.width(); ++x)
            o[x] = uchar(add ? qMax(o[x], s[x]) : sub ? o[x] * (255 - s[x]) / 255 : o[x] * s[x] / 255);
    }
    set(out);
}

void Selection::shape(Project *project, qreal x, qreal y, qreal w, qreal h, bool ellipse, const QString &mode, qreal featherPx)
{
    if (!prepare(project))
        return;
    QImage s = blank();
    QPainter p(&s);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    p.setBrush(Qt::white);
    p.scale(m_k, m_k);
    if (ellipse)
        p.drawEllipse(QRectF(x, y, w, h));
    else
        p.drawRect(QRectF(x, y, w, h));
    p.end();
    combine(s, mode, featherPx);
}

void Selection::lasso(Project *project, const QVariantList &points, const QString &mode, qreal featherPx)
{
    if (!prepare(project) || points.size() < 3)
        return;
    QPainterPath path;
    for (int i = 0; i < points.size(); ++i) {
        const QVariantList q = points.at(i).toList();
        const QPointF pt(q.value(0).toDouble(), q.value(1).toDouble());
        if (i == 0)
            path.moveTo(pt);
        else
            path.lineTo(pt);
    }
    path.closeSubpath();
    QImage s = blank();
    QPainter p(&s);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    p.setBrush(Qt::white);
    p.scale(m_k, m_k);
    p.drawPath(path);
    p.end();
    combine(s, mode, featherPx);
}

void Selection::wand(Project *project, qreal x, qreal y, qreal tolerance, bool contiguous, const QString &onlyId, const QString &mode, qreal featherPx)
{
    if (!prepare(project))
        return;
    QVariantMap doc = project->pageDocument(project->currentPage());
    if (!onlyId.isEmpty()) {
        doc[QStringLiteral("elements")] = QVariantList{project->get(onlyId)};
        doc.remove(QStringLiteral("background"));
    }
    const QImage page = Art::renderPage(doc, m_size, project, Qt::transparent);
    const QPoint seed(qRound(x * m_k), qRound(y * m_k));
    if (!page.rect().contains(seed))
        return;
    const QRgb from = page.pixel(seed);
    const int limit = qRound(qBound(0.0, tolerance, 1.0) * 255 * 3);
    auto similar = [&](QRgb c) {
        return std::abs(qRed(c) - qRed(from)) + std::abs(qGreen(c) - qGreen(from)) + std::abs(qBlue(c) - qBlue(from)) + std::abs(qAlpha(c) - qAlpha(from)) <= limit;
    };
    const int W = page.width(), H = page.height();
    QImage mark(page.size(), QImage::Format_Alpha8);
    mark.fill(0);
    if (contiguous) {
        QList<QPoint> stack{seed};
        while (!stack.isEmpty()) {
            const QPoint p = stack.takeLast();
            const QRgb *row = reinterpret_cast<const QRgb *>(page.constScanLine(p.y()));
            uchar *mk = mark.scanLine(p.y());
            if (mk[p.x()])
                continue;
            int a = p.x(), b = p.x();
            while (a > 0 && !mk[a - 1] && similar(row[a - 1]))
                --a;
            while (b < W - 1 && !mk[b + 1] && similar(row[b + 1]))
                ++b;
            std::fill(mk + a, mk + b + 1, uchar(255));
            for (const int ny : {p.y() - 1, p.y() + 1}) {
                if (ny < 0 || ny >= H)
                    continue;
                const QRgb *nrow = reinterpret_cast<const QRgb *>(page.constScanLine(ny));
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
    } else {
        for (int j = 0; j < H; ++j) {
            const QRgb *row = reinterpret_cast<const QRgb *>(page.constScanLine(j));
            uchar *mk = mark.scanLine(j);
            for (int i = 0; i < W; ++i)
                if (similar(row[i]))
                    mk[i] = 255;
        }
    }
    // Lekko zmiękczony brzeg zamiast schodków
    QImage soft = toPremultiplied(mark);
    Art::blur(soft, 1);
    combine(soft, mode, featherPx);
}

void Selection::all(Project *project)
{
    if (!prepare(project))
        return;
    remember();
    QImage m = blank(false);
    m.fill(255);
    set(m);
}

void Selection::clear()
{
    if (m_mask.isNull())
        return;
    remember();
    set({});
}

void Selection::invert(Project *project)
{
    if (!prepare(project))
        return;
    remember();
    QImage m = m_mask.isNull() ? blank(false) : m_mask.copy();
    for (int y = 0; y < m.height(); ++y) {
        uchar *row = m.scanLine(y);
        for (int x = 0; x < m.width(); ++x)
            row[x] = uchar(255 - row[x]);
    }
    set(m);
}

void Selection::feather(qreal radius)
{
    if (m_mask.isNull() || radius <= 0)
        return;
    remember();
    QImage s = toPremultiplied(m_mask);
    Art::blur(s, qRound(radius * m_k));
    set(toAlpha(s));
}

void Selection::grow(qreal radius)
{
    if (m_mask.isNull() || radius == 0)
        return;
    remember();
    // Rozmyta maska progowana nisko powiększa, wysoko zmniejsza; próg z rampą daje gładki brzeg
    QImage s = toPremultiplied(m_mask);
    Art::blur(s, qMax(1, qRound(qAbs(radius) * m_k * 0.75)));
    QImage m = toAlpha(s);
    const int low = radius > 0 ? 4 : 215, high = radius > 0 ? 40 : 251;
    for (int y = 0; y < m.height(); ++y) {
        uchar *row = m.scanLine(y);
        for (int x = 0; x < m.width(); ++x)
            row[x] = uchar(qBound(0, (row[x] - low) * 255 / (high - low), 255));
    }
    set(m);
}

void Selection::translate(qreal dx, qreal dy)
{
    if (m_mask.isNull())
        return;
    remember();
    QImage s = blank();
    QPainter p(&s);
    p.drawImage(QPointF(dx * m_k, dy * m_k), toPremultiplied(m_mask));
    p.end();
    set(toAlpha(s));
}

bool Selection::contains(qreal x, qreal y) const
{
    const QPoint p(qRound(x * m_k), qRound(y * m_k));
    return !m_mask.isNull() && m_mask.rect().contains(p) && m_mask.constScanLine(p.y())[p.x()] > 127;
}

void Selection::undo()
{
    if (m_history.isEmpty())
        return;
    m_mask = m_history.takeLast();
    Q_EMIT changed();
}

QImage Selection::mapped(const QTransform &pageToTarget, const QSize &size) const
{
    QImage out(size, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    if (m_mask.isNull())
        return toAlpha(out);
    QPainter p(&out);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    p.setTransform(QTransform::fromScale(1 / m_k, 1 / m_k) * pageToTarget);
    p.drawImage(0, 0, toPremultiplied(m_mask));
    p.end();
    return toAlpha(out);
}

void Selection::fromLayer(Project *project, const QVariantMap &el, const QImage &mask, const QString &mode)
{
    if (!prepare(project))
        return;
    // Piksele zdjęcia → ramka → strona → maska zaznaczenia
    const QTransform t = Art::frameTransform(el, mask.size()) * Art::pageToFrame(el).inverted() * QTransform::fromScale(m_k, m_k);
    QImage s = blank();
    QPainter p(&s);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    p.setTransform(t);
    p.drawImage(0, 0, toPremultiplied(mask));
    p.end();
    combine(s, mode, 0);
}

static QRect solidBounds(const QImage &alpha)
{
    int x0 = alpha.width(), y0 = alpha.height(), x1 = -1, y1 = -1;
    for (int y = 0; y < alpha.height(); ++y) {
        const uchar *row = alpha.constScanLine(y);
        for (int x = 0; x < alpha.width(); ++x)
            if (row[x] > 0) {
                x0 = qMin(x0, x);
                x1 = qMax(x1, x);
                y0 = qMin(y0, y);
                y1 = qMax(y1, y);
            }
    }
    return x1 < 0 ? QRect() : QRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

QVariantMap Selection::bounds() const
{
    const QRect b = m_mask.isNull() ? QRect() : solidBounds(m_mask);
    return {{QStringLiteral("x"), b.x() / m_k}, {QStringLiteral("y"), b.y() / m_k}, {QStringLiteral("w"), b.width() / m_k}, {QStringLiteral("h"), b.height() / m_k}};
}

// Kopia zaznaczonego fragmentu jako nowa warstwa pikselowa, tuż nad warstwą źródłową
QString Selection::toLayer(Project *project, const QString &id, bool cut)
{
    if (m_mask.isNull() || !prepare(project))
        return {};
    const QRect box = solidBounds(m_mask);
    if (box.isEmpty())
        return {};
    QImage layer(m_size, QImage::Format_ARGB32_Premultiplied);
    layer.fill(Qt::transparent);
    {
        QPainter p(&layer);
        p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
        p.scale(m_k, m_k);
        if (id.isEmpty()) {
            Art::paintPage(&p, project->pageDocument(project->currentPage()), project);
        } else {
            const QVariantMap el = project->get(id);
            p.setTransform(Art::pageToFrame(el).inverted(), true);
            Art::paintElement(&p, el, project);
        }
        p.resetTransform();
        p.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        p.drawImage(0, 0, toPremultiplied(m_mask));
    }
    const QString key = project->addImage(layer.copy(box).convertToFormat(QImage::Format_ARGB32));
    const QVariantMap source = id.isEmpty() ? QVariantMap() : project->get(id);
    QVariantMap n{{QStringLiteral("type"), QStringLiteral("image")}, {QStringLiteral("src"), key}, {QStringLiteral("pixel"), true},
                  {QStringLiteral("x"), std::round(box.x() / m_k * 10) / 10}, {QStringLiteral("y"), std::round(box.y() / m_k * 10) / 10},
                  {QStringLiteral("w"), std::round(box.width() / m_k * 10) / 10}, {QStringLiteral("h"), std::round(box.height() / m_k * 10) / 10}};
    if (cut && !id.isEmpty())
        maskLayer(project, id, true);       // wycięte miejsce chowa maska: warstwa zostaje do odzyskania
    const QString made = project->add(n);
    if (!id.isEmpty())
        project->moveTo(made, project->indexOf(id) + 1);
    clear();
    return made;
}

// Zaznaczenie jako maska warstwy; hide — odwrotnie: zaznaczone znika. Łączy się z maską, która już jest.
void Selection::maskLayer(Project *project, const QString &id, bool hide)
{
    if (m_mask.isNull() || !prepare(project))
        return;
    const QVariantMap el = project->get(id);
    const QSize size = project->maskSizeFor(el);
    const bool whole = el.value(QStringLiteral("type")).toString() == QLatin1String("adjust");
    const QTransform toFrame = whole ? QTransform() : Art::pageToFrame(el);
    const qreal w = whole ? m_page.width() : el.value(QStringLiteral("w")).toDouble(), h = whole ? m_page.height() : el.value(QStringLiteral("h")).toDouble();
    QImage in = mapped(toFrame * QTransform::fromScale(size.width() / w, size.height() / h), size);
    const QImage old = Art::maskSource(el.value(QStringLiteral("layerMask")).toString(), project);
    const QImage oldGray = old.isNull() ? QImage() : old.convertToFormat(QImage::Format_Grayscale8).scaled(size);
    QImage gray(size, QImage::Format_Grayscale8);
    for (int y = 0; y < size.height(); ++y) {
        const uchar *s = in.constScanLine(y);
        const uchar *o = oldGray.isNull() ? nullptr : oldGray.constScanLine(y);
        uchar *d = gray.scanLine(y);
        for (int x = 0; x < size.width(); ++x) {
            const int v = hide ? 255 - s[x] : s[x];
            d[x] = uchar(o ? v * o[x] / 255 : v);
        }
    }
    project->setMaskImage(id, gray);
}

// ——— Mrówki ———

SelectionView::SelectionView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    m_tick.setInterval(140);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        m_step = (m_step + 1) % 8;
        update();
    });
}

void SelectionView::geometryChange(const QRectF &now, const QRectF &old)
{
    QQuickPaintedItem::geometryChange(now, old);
    if (now.size() != old.size())
        rebuild();
}

void SelectionView::rebuild()
{
    m_edges.clear();
    m_phase.clear();
    Selection *s = Selection::instance();
    const int W = qRound(width()), H = qRound(height());
    if (!s || !s->active() || W < 2 || H < 2) {
        m_tick.stop();
        update();
        return;
    }
    const QImage small = s->mask().scaled(W, H, Qt::IgnoreAspectRatio, Qt::FastTransformation);
    auto on = [&](int x, int y) { return x >= 0 && y >= 0 && x < W && y < H && small.constScanLine(y)[x] > 127; };
    for (int y = 0; y <= H; ++y)
        for (int x = 0; x <= W; ++x) {
            const bool here = on(x, y);
            if (here != on(x, y - 1) && x < W) {
                m_edges.append(QLineF(x, y, x + 1, y));
                m_phase.append(x + y);
            }
            if (here != on(x - 1, y) && y < H) {
                m_edges.append(QLineF(x, y, x, y + 1));
                m_phase.append(x + y);
            }
        }
    if (!m_tick.isActive())
        m_tick.start();
    update();
}

void SelectionView::paint(QPainter *p)
{
    QList<QLineF> dark, light;
    for (int i = 0; i < m_edges.size(); ++i)
        ((m_phase.at(i) + m_step) / 4 % 2 ? dark : light).append(m_edges.at(i));
    p->setPen(QPen(Qt::black, 1));
    p->drawLines(dark);
    p->setPen(QPen(Qt::white, 1));
    p->drawLines(light);
}

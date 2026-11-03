#include "art.h"

#include <QCache>
#include <QGlyphRun>
#include <QJsonDocument>
#include <QLinearGradient>
#include <QMutex>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QSvgRenderer>
#include <QRawFont>
#include <QTextLayout>
#include <QtMath>

namespace {

qreal num(const QVariantMap &m, const char *key, qreal fallback)
{
    const QVariant v = m.value(QLatin1String(key));
    return v.isValid() && !v.isNull() ? v.toDouble() : fallback;
}

QColor color(const QVariantMap &m, const char *key, const QColor &fallback = Qt::transparent)
{
    const QString s = m.value(QLatin1String(key)).toString();
    if (s.isEmpty())
        return fallback;
    const QColor c = QColor::fromString(s);
    return c.isValid() ? c : fallback;
}

// ——— Tekst ———

QFont textFont(const QVariantMap &el)
{
    QFont f(el.value(QStringLiteral("font"), QStringLiteral("Geist")).toString());
    const qreal size = qMax(1.0, num(el, "size", 48));
    f.setPixelSize(qMax(1, qRound(size)));
    f.setWeight(QFont::Weight(qBound(100, int(num(el, "weight", 400)), 900)));
    f.setItalic(el.value(QStringLiteral("italic")).toBool());
    f.setUnderline(el.value(QStringLiteral("underline")).toBool());
    // Odstęp liter w częściach wielkości czcionki — przy skalowaniu tekstu rośnie razem z nim
    f.setLetterSpacing(QFont::AbsoluteSpacing, num(el, "spacing", 0) * size);
    if (el.value(QStringLiteral("caps")).toBool())
        f.setCapitalization(QFont::AllUppercase);
    f.setHintingPreference(QFont::PreferNoHinting);
    f.setStyleStrategy(QFont::PreferAntialias);
    f.setKerning(true);
    return f;
}

Qt::Alignment textAlign(const QVariantMap &el)
{
    const QString a = el.value(QStringLiteral("align")).toString();
    if (a == QLatin1String("center"))
        return Qt::AlignHCenter;
    if (a == QLatin1String("right"))
        return Qt::AlignRight;
    return Qt::AlignLeft;
}

// Tekst po łuku ma jeden wiersz
QString curvedText(const QVariantMap &el)
{
    return el.value(QStringLiteral("text")).toString().simplified();
}

QString layoutText(const QVariantMap &el)
{
    QString t = el.value(QStringLiteral("text")).toString();
    t.replace(QLatin1Char('\n'), QChar::LineSeparator);
    return t;
}

// Układa tekst w wiersze o wysokości size × lineHeight; zwraca wysokość bloku
qreal layout(QTextLayout &tl, const QVariantMap &el, qreal width)
{
    QTextOption opt(textAlign(el));
    opt.setWrapMode(width > 0 ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::NoWrap);
    opt.setUseDesignMetrics(true);
    tl.setTextOption(opt);
    tl.setCacheEnabled(true);
    const qreal lineH = qMax(1.0, num(el, "size", 48)) * num(el, "lineHeight", 1.2);
    qreal y = 0;
    tl.beginLayout();
    for (;;) {
        QTextLine line = tl.createLine();
        if (!line.isValid())
            break;
        if (width > 0)
            line.setLineWidth(width);
        line.setPosition(QPointF(0, y + (lineH - line.height()) / 2));
        y += lineH;
    }
    tl.endLayout();
    return qMax(y, lineH);
}

QPainterPath glyphPath(const QTextLayout &tl)
{
    QPainterPath path;
    for (const QGlyphRun &run : tl.glyphRuns()) {
        const QRawFont font = run.rawFont();
        const QList<quint32> glyphs = run.glyphIndexes();
        const QList<QPointF> pos = run.positions();
        for (int i = 0; i < glyphs.size(); ++i)
            path.addPath(font.pathForGlyph(glyphs.at(i)).translated(pos.at(i)));
    }
    return path;
}

// Tekst po łuku: każda litera obrócona wzdłuż okręgu. curve > 0 — łuk w górę, < 0 — w dół (−1..1 = do pół okręgu)
void paintCurvedText(QPainter *p, const QVariantMap &el)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const qreal curve = qBound(-1.0, num(el, "curve", 0), 1.0);
    const qreal size = qMax(1.0, num(el, "size", 48));
    QTextLayout tl(curvedText(el), textFont(el));
    const qreal lineH = layout(tl, el, 0);
    if (tl.lineCount() == 0)
        return;
    const QTextLine line = tl.lineAt(0);
    const qreal len = line.naturalTextWidth();
    const qreal angle = qAbs(curve) * M_PI;
    const qreal r = len / angle;
    const qreal ascent = line.ascent() + (lineH - line.height()) / 2;
    const bool up = curve > 0;
    // Środek okręgu: pod tekstem (łuk w górę) albo nad nim (w dół); środkowa litera na osi elementu
    const qreal baseMid = up ? ascent : h - (lineH - ascent);
    const QPointF c(w / 2, up ? baseMid + r : baseMid - r);
    QPainterPath out;
    for (const QGlyphRun &run : tl.glyphRuns()) {
        const QRawFont font = run.rawFont();
        const QList<quint32> glyphs = run.glyphIndexes();
        const QList<QPointF> pos = run.positions();
        const QList<QPointF> adv = font.advancesForGlyphIndexes(glyphs);
        for (int i = 0; i < glyphs.size(); ++i) {
            const qreal gw = adv.at(i).x();
            const qreal s = pos.at(i).x() + gw / 2 - len / 2;          // odległość środka litery od środka napisu
            const qreal t = s / r;
            QTransform tr;
            if (up) {
                tr.translate(c.x() + r * qSin(t), c.y() - r * qCos(t));
                tr.rotateRadians(t);
            } else {
                tr.translate(c.x() + r * qSin(t), c.y() + r * qCos(t));
                tr.rotateRadians(-t);
            }
            out.addPath(tr.map(font.pathForGlyph(glyphs.at(i)).translated(-gw / 2, 0)));
        }
    }
    p->setRenderHint(QPainter::Antialiasing);
    const qreal outline = num(el, "outline", 0) * size;
    if (outline > 0) {
        QPen pen(color(el, "outlineColor", Qt::black), outline * 2);
        pen.setJoinStyle(Qt::RoundJoin);
        p->strokePath(out, pen);
    }
    p->fillPath(out, color(el, "color", Qt::black));
}

void paintText(QPainter *p, const QVariantMap &el)
{
    if (num(el, "curve", 0) != 0) {
        paintCurvedText(p, el);
        return;
    }
    const qreal w = num(el, "w", 100);
    QTextLayout tl(layoutText(el), textFont(el));
    layout(tl, el, w);
    const qreal size = qMax(1.0, num(el, "size", 48));

    // Tło pod każdym wierszem (jak zakreślenie w postach) — `bgPadding` i `bgRadius` w wielkościach czcionki
    const QColor bg = color(el, "bg");
    if (bg.alpha() > 0) {
        const qreal pad = num(el, "bgPadding", 0.25) * size, radius = num(el, "bgRadius", 0.2) * size;
        QPainterPath boxes;
        boxes.setFillRule(Qt::WindingFill);
        for (int i = 0; i < tl.lineCount(); ++i) {
            const QTextLine line = tl.lineAt(i);
            if (line.naturalTextWidth() <= 0)
                continue;
            const QRectF r = line.naturalTextRect().adjusted(-pad, -pad * 0.5, pad, pad * 0.5);
            boxes.addRoundedRect(r, radius, radius);
        }
        p->setPen(Qt::NoPen);
        p->setBrush(bg);
        p->drawPath(boxes.simplified());
    }

    // Stary twardy cień tekstu (bez rozmycia); miękki cień rysuje paintElement
    if (el.value(QStringLiteral("shadow")).toBool() && !el.contains(QStringLiteral("shadowBlur"))) {
        p->setPen(color(el, "shadowColor", QColor(0, 0, 0, 90)));
        tl.draw(p, QPointF(size * 0.04, size * 0.06));
    }
    const qreal outline = num(el, "outline", 0) * size;
    if (outline > 0) {
        // Obrys z kształtów liter, pod wypełnieniem — gruby obrys nie zjada liter od środka
        const QPainterPath path = glyphPath(tl);
        QPen pen(color(el, "outlineColor", Qt::black), outline * 2);
        pen.setJoinStyle(Qt::RoundJoin);
        pen.setCapStyle(Qt::RoundCap);
        p->strokePath(path, pen);
    }
    p->setPen(color(el, "color", Qt::black));
    tl.draw(p, QPointF(0, 0));
}

// ——— Wypełnienia ———

// Gradient liniowy jak w CSS: kąt 0° — ku górze, 90° — w prawo, 180° — w dół
QBrush gradientBrush(const QColor &a, const QColor &b, qreal angle, const QRectF &r, bool radial)
{
    if (radial) {
        QRadialGradient g(r.center(), qMax(r.width(), r.height()) * 0.72);
        g.setColorAt(0, a);
        g.setColorAt(1, b);
        return QBrush(g);
    }
    const qreal rad = qDegreesToRadians(angle);
    const QPointF d(qSin(rad), -qCos(rad));
    const qreal len = qAbs(r.width() * d.x()) + qAbs(r.height() * d.y());
    QLinearGradient g(r.center() - d * len / 2, r.center() + d * len / 2);
    g.setColorAt(0, a);
    g.setColorAt(1, b);
    return QBrush(g);
}

QBrush fillBrush(const QVariantMap &el, const QRectF &r)
{
    const QColor a = color(el, "fill");
    const QColor b = color(el, "fill2");
    if (a.alpha() > 0 && b.isValid() && b.alpha() > 0)
        return gradientBrush(a, b, num(el, "gradientAngle", 180), r, el.value(QStringLiteral("gradient")).toString() == QLatin1String("radial"));
    return a.alpha() > 0 ? QBrush(a) : QBrush(Qt::NoBrush);
}

// Skala rysowania (ile pikseli wyjścia na piksel projektu)
qreal deviceScale(const QPainter *p)
{
    const QTransform t = p->deviceTransform();
    return qMax(0.01, qSqrt(qAbs(t.determinant())));
}

// Zdjęcie przycięte tak, żeby wypełniło prostokąt („cover”), w kształcie `clip` (zaokrąglenie, koło)
void paintCover(QPainter *p, const QImage &img, const QRectF &r, const QPainterPath &clip, qreal fx = 0.5, qreal fy = 0.5, qreal zoom = 1)
{
    if (img.isNull() || r.isEmpty())
        return;
    const qreal s = qMax(r.width() / img.width(), r.height() / img.height()) * qMax(1.0, zoom);
    const QSizeF sz(img.width() * s, img.height() * s);
    const QPointF origin(r.x() - (sz.width() - r.width()) * fx, r.y() - (sz.height() - r.height()) * fy);
    p->setRenderHint(QPainter::SmoothPixmapTransform);
    if (clip.isEmpty()) {
        const QRectF src((r.x() - origin.x()) / s, (r.y() - origin.y()) / s, r.width() / s, r.height() / s);
        p->drawImage(r, img, src);
        return;
    }
    QBrush brush(img);
    QTransform t;
    t.translate(origin.x(), origin.y());
    t.scale(s, s);
    brush.setTransform(t);
    p->setPen(Qt::NoPen);
    p->setBrush(brush);
    p->drawPath(clip);
}

QPainterPath starPath(const QRectF &r, int points, qreal inner)
{
    QPainterPath path;
    const QPointF c = r.center();
    for (int i = 0; i < points * 2; ++i) {
        const qreal a = -M_PI / 2 + i * M_PI / points;
        const qreal k = i % 2 ? inner : 1.0;
        const QPointF pt(c.x() + qCos(a) * r.width() / 2 * k, c.y() + qSin(a) * r.height() / 2 * k);
        if (i == 0)
            path.moveTo(pt);
        else
            path.lineTo(pt);
    }
    path.closeSubpath();
    return path;
}

QPainterPath heartPath(const QRectF &r)
{
    const qreal x = r.x(), y = r.y(), w = r.width(), h = r.height();
    QPainterPath path;
    path.moveTo(x + w / 2, y + h * 0.28);
    path.cubicTo(x + w * 0.5, y + h * 0.05, x + w * 0.08, y - h * 0.02, x + w * 0.02, y + h * 0.3);
    path.cubicTo(x - w * 0.04, y + h * 0.6, x + w * 0.35, y + h * 0.78, x + w / 2, y + h);
    path.cubicTo(x + w * 0.65, y + h * 0.78, x + w * 1.04, y + h * 0.6, x + w * 0.98, y + h * 0.3);
    path.cubicTo(x + w * 0.92, y - h * 0.02, x + w * 0.5, y + h * 0.05, x + w / 2, y + h * 0.28);
    path.closeSubpath();
    return path;
}

// Kształty zdjęć (i kształtów): sześciokąt, łuk (okno), kropla, liść, „plama”
QPainterPath maskPath(const QString &mask, const QRectF &r)
{
    QPainterPath path;
    const qreal x = r.x(), y = r.y(), w = r.width(), h = r.height();
    if (mask == QLatin1String("star")) {
        path = starPath(r, 5, 0.45);
    } else if (mask == QLatin1String("heart")) {
        path = heartPath(r);
    } else if (mask == QLatin1String("triangle")) {
        path.moveTo(x + w / 2, y);
        path.lineTo(x + w, y + h);
        path.lineTo(x, y + h);
        path.closeSubpath();
    } else if (mask == QLatin1String("hexagon")) {
        for (int i = 0; i < 6; ++i) {
            const qreal a = M_PI / 6 + i * M_PI / 3;
            const QPointF pt(x + w / 2 + qCos(a) * w / 2, y + h / 2 + qSin(a) * h / 2);
            if (i == 0)
                path.moveTo(pt);
            else
                path.lineTo(pt);
        }
        path.closeSubpath();
    } else if (mask == QLatin1String("arch")) {
        const qreal k = qMin(w / 2, h);
        path.moveTo(x, y + h);
        path.lineTo(x, y + k);
        path.arcTo(QRectF(x, y, w, 2 * k), 180, -180);
        path.lineTo(x + w, y + h);
        path.closeSubpath();
    } else if (mask == QLatin1String("leaf")) {
        const qreal k = qMin(w, h) * 0.5;
        path.moveTo(x + k, y);
        path.lineTo(x + w, y);
        path.lineTo(x + w, y + h - k);
        path.quadTo(x + w, y + h, x + w - k, y + h);
        path.lineTo(x, y + h);
        path.lineTo(x, y + k);
        path.quadTo(x, y, x + k, y);
        path.closeSubpath();
    } else if (mask == QLatin1String("blob")) {
        // Miękka, nieregularna plama — stałe punkty, żeby kształt był zawsze ten sam
        const qreal pts[][2] = {{0.50, 0.02}, {0.86, 0.12}, {0.98, 0.50}, {0.84, 0.88}, {0.46, 0.98}, {0.10, 0.82}, {0.03, 0.40}, {0.20, 0.10}};
        const int n = 8;
        auto at = [&](int i) { return QPointF(x + pts[(i + n) % n][0] * w, y + pts[(i + n) % n][1] * h); };
        path.moveTo((at(0) + at(1)) / 2);
        for (int i = 1; i <= n; ++i)
            path.quadTo(at(i), (at(i) + at(i + 1)) / 2);
        path.closeSubpath();
    } else {
        path.addRect(r);
    }
    return path;
}

void paintShape(QPainter *p, const QVariantMap &el)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const QString shape = el.value(QStringLiteral("shape"), QStringLiteral("rect")).toString();
    const qreal sw = num(el, "strokeWidth", 0);
    const QColor stroke = color(el, "stroke");

    if (shape == QLatin1String("line") || shape == QLatin1String("arrow")) {
        const qreal t = qMax(1.0, sw > 0 ? sw : 6);
        QPen pen(stroke.alpha() > 0 ? stroke : color(el, "fill", Qt::black), t);
        pen.setCapStyle(Qt::RoundCap);
        if (el.value(QStringLiteral("dash")).toBool())
            pen.setDashPattern({2, 2.2});
        const qreal cy = h / 2;
        qreal end = w - t / 2;
        if (shape == QLatin1String("arrow")) {
            const qreal head = qMin(w * 0.45, t * 3.2 + 10);
            end = w - head * 0.7;
            QPainterPath tip;
            tip.moveTo(w, cy);
            tip.lineTo(w - head, cy - head * 0.62);
            tip.lineTo(w - head, cy + head * 0.62);
            tip.closeSubpath();
            p->setPen(Qt::NoPen);
            p->setBrush(pen.color());
            p->drawPath(tip);
        }
        p->setPen(pen);
        p->drawLine(QPointF(t / 2, cy), QPointF(end, cy));
        return;
    }

    // Obrys wewnątrz pola elementu
    const QRectF r = QRectF(0, 0, w, h).adjusted(sw / 2, sw / 2, -sw / 2, -sw / 2);
    QPainterPath path;
    if (shape == QLatin1String("ellipse")) {
        path.addEllipse(r);
    } else if (shape == QLatin1String("triangle")) {
        path.moveTo(r.center().x(), r.top());
        path.lineTo(r.bottomRight());
        path.lineTo(r.bottomLeft());
        path.closeSubpath();
    } else if (shape == QLatin1String("star")) {
        path = starPath(r, 5, 0.45);
    } else if (shape == QLatin1String("heart")) {
        path = heartPath(r);
    } else {
        const qreal radius = qMin(num(el, "radius", 0), qMin(r.width(), r.height()) / 2);
        path.addRoundedRect(r, radius, radius);
    }
    QPen pen(Qt::NoPen);
    if (sw > 0 && stroke.alpha() > 0) {
        pen = QPen(stroke, sw);
        pen.setJoinStyle(Qt::RoundJoin);
        if (el.value(QStringLiteral("dash")).toBool())
            pen.setDashPattern({3, 2});
    }
    p->setPen(pen);
    p->setBrush(fillBrush(el, r));
    p->drawPath(path);
}

// ——— Poprawki zdjęć ———

// Jasność, kontrast, nasycenie (−1..1) i gotowe filtry; wynik w pamięci podręcznej, bo płótno rysuje się często.
// `pixels` — potrzebny dłuższy bok: większe zdjęcie najpierw się zmniejsza (miniatury filtrów, suwaki bez zacinania).
QImage adjusted(const QImage &src, const QVariantMap &el, qreal pixels)
{
    const qreal br = qBound(-1.0, num(el, "brightness", 0), 1.0);
    const qreal ct = qBound(-1.0, num(el, "contrast", 0), 1.0);
    const qreal sat = qBound(-1.0, num(el, "saturation", 0), 1.0);
    const QString filter = el.value(QStringLiteral("filter")).toString();
    if (br == 0 && ct == 0 && sat == 0 && filter.isEmpty())
        return src;

    static QMutex lock;
    static QCache<QString, QImage> cache(160);       // koszt w MB
    const int side = qMax(src.width(), src.height());
    const int target = pixels * 1.25 < side ? qMax(16, qRound(pixels * 1.25)) : side;
    const QString key = QStringLiteral("%1|%2|%3|%4|%5|%6").arg(src.cacheKey()).arg(target).arg(br).arg(ct).arg(sat).arg(filter);
    {
        QMutexLocker l(&lock);
        if (const QImage *hit = cache.object(key))
            return *hit;
    }

    QImage img = (target < side ? src.scaled(src.width() * target / side, src.height() * target / side, Qt::KeepAspectRatio, Qt::SmoothTransformation) : src)
                     .convertToFormat(QImage::Format_ARGB32);
    int lut[256];
    for (int i = 0; i < 256; ++i)
        lut[i] = qBound(0, qRound((i - 128) * (1 + ct) + 128 + br * 110), 255);
    const qreal satK = filter == QLatin1String("gray") ? 0 : 1 + sat;
    for (int y = 0; y < img.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb c = line[x];
            qreal r = lut[qRed(c)], g = lut[qGreen(c)], b = lut[qBlue(c)];
            const qreal gray = 0.299 * r + 0.587 * g + 0.114 * b;
            r = gray + (r - gray) * satK;
            g = gray + (g - gray) * satK;
            b = gray + (b - gray) * satK;
            if (filter == QLatin1String("sepia")) {
                const qreal tr = 0.393 * r + 0.769 * g + 0.189 * b, tg = 0.349 * r + 0.686 * g + 0.168 * b, tb = 0.272 * r + 0.534 * g + 0.131 * b;
                r = tr; g = tg; b = tb;
            } else if (filter == QLatin1String("warm")) {
                r *= 1.08; g *= 1.02; b *= 0.88;
            } else if (filter == QLatin1String("cool")) {
                r *= 0.9; g *= 1.0; b *= 1.1;
            } else if (filter == QLatin1String("fade")) {
                r = r * 0.82 + 34; g = g * 0.82 + 30; b = b * 0.82 + 38;
            } else if (filter == QLatin1String("vivid")) {
                const qreal k = 1.35;
                r = gray + (r - gray) * k; g = gray + (g - gray) * k; b = gray + (b - gray) * k;
            }
            line[x] = qRgba(qBound(0, qRound(r), 255), qBound(0, qRound(g), 255), qBound(0, qRound(b), 255), qAlpha(c));
        }
    }
    QMutexLocker l(&lock);
    cache.insert(key, new QImage(img), int(img.sizeInBytes() / (1024 * 1024)) + 1);
    return img;
}

// Ikona albo naklejka (SVG). `color` zastępuje currentColor — jednokolorowe ikony da się przefarbować
void paintVector(QPainter *p, const QVariantMap &el, const ImageSource *images)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    QByteArray data = images ? images->vector(el.value(QStringLiteral("src")).toString()) : QByteArray();
    if (data.isEmpty())
        return;
    const QString c = el.value(QStringLiteral("color")).toString();
    if (!c.isEmpty())
        data.replace("currentColor", c.toLatin1());
    QSvgRenderer svg(data);
    if (!svg.isValid())
        return;
    svg.setAspectRatioMode(Qt::KeepAspectRatio);
    if (el.value(QStringLiteral("flipX")).toBool()) {
        p->translate(w, 0);
        p->scale(-1, 1);
    }
    svg.render(p, QRectF(0, 0, w, h));
}

void paintPicture(QPainter *p, const QVariantMap &el, const ImageSource *images)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const QRectF r(0, 0, w, h);
    QPainterPath clip;
    const QString mask = el.value(QStringLiteral("mask")).toString();
    if (mask == QLatin1String("ellipse")) {
        clip.addEllipse(r);
    } else if (!mask.isEmpty()) {
        clip = maskPath(mask, r);
    } else {
        const qreal radius = qMin(num(el, "radius", 0), qMin(w, h) / 2);
        if (radius > 0)
            clip.addRoundedRect(r, radius, radius);
    }
    const qreal pixels = qMax(w, h) * deviceScale(p) * qMax(1.0, num(el, "zoom", 1));
    QImage img = images ? images->image(el.value(QStringLiteral("src")).toString(), pixels) : QImage();
    if (img.isNull()) {
        // Miejsce na zdjęcie (np. w szablonie) — przyciemnione pole z rysunkiem zdjęcia na środku
        p->setPen(Qt::NoPen);
        p->setBrush(QColor(0, 0, 0, 30));
        if (clip.isEmpty())
            p->drawRect(r);
        else
            p->drawPath(clip);
        const qreal k = qMin(w, h) * 0.22;
        const QRectF ic(r.center().x() - k / 2, r.center().y() - k * 0.4, k, k * 0.8);
        QPen pen(QColor(255, 255, 255, 170), qMax(1.0, k * 0.07));
        pen.setJoinStyle(Qt::RoundJoin);
        p->setPen(pen);
        p->setBrush(Qt::NoBrush);
        p->drawRoundedRect(ic, k * 0.1, k * 0.1);
        QPainterPath m;
        m.moveTo(ic.left(), ic.bottom() - ic.height() * 0.15);
        m.lineTo(ic.left() + ic.width() * 0.4, ic.top() + ic.height() * 0.45);
        m.lineTo(ic.left() + ic.width() * 0.62, ic.top() + ic.height() * 0.7);
        m.lineTo(ic.left() + ic.width() * 0.78, ic.top() + ic.height() * 0.55);
        m.lineTo(ic.right(), ic.top() + ic.height() * 0.75);
        p->drawPath(m);
        return;
    }
    // Przy „cover” dłuższy bok zdjęcia wystaje poza ramkę — tyle pikseli naprawdę trafi na wyjście
    const qreal cover = qMax(w / img.width(), h / img.height());
    img = adjusted(img, el, qMax(img.width(), img.height()) * cover * pixels / qMax(w, h));
    if (el.value(QStringLiteral("flipX")).toBool()) {
        p->translate(w, 0);
        p->scale(-1, 1);
    }
    paintCover(p, img, r, clip, num(el, "focusX", 0.5), num(el, "focusY", 0.5), num(el, "zoom", 1));
}

}

namespace Art {

qreal textHeight(const QVariantMap &el)
{
    const qreal curve = qBound(-1.0, num(el, "curve", 0), 1.0);
    if (curve != 0) {
        // Tekst po łuku: jeden wiersz, wysokość rośnie o strzałkę łuku
        QTextLayout tl(curvedText(el), textFont(el));
        const qreal lineH = layout(tl, el, 0);
        const qreal len = tl.lineCount() ? tl.lineAt(0).naturalTextWidth() : 0;
        const qreal angle = qAbs(curve) * M_PI;
        const qreal r = len / angle;
        return lineH + r * (1 - qCos(angle / 2)) + lineH * 0.2 * qAbs(curve);
    }
    QTextLayout tl(layoutText(el), textFont(el));
    return layout(tl, el, num(el, "w", 100));
}

qreal textNaturalWidth(const QVariantMap &el)
{
    const qreal curve = qBound(-1.0, num(el, "curve", 0), 1.0);
    if (curve != 0) {
        // Cięciwa łuku i zapas na wysokość liter po bokach
        QTextLayout tl(curvedText(el), textFont(el));
        const qreal lineH = layout(tl, el, 0);
        const qreal len = tl.lineCount() ? tl.lineAt(0).naturalTextWidth() : 0;
        const qreal angle = qAbs(curve) * M_PI;
        const qreal r = len / angle;
        return std::ceil(2 * r * qSin(qMin(angle / 2, M_PI / 2)) + lineH * qSin(angle / 2)) + 4;
    }
    QTextLayout tl(layoutText(el), textFont(el));
    layout(tl, el, 0);
    qreal w = 0;
    for (int i = 0; i < tl.lineCount(); ++i)
        w = qMax(w, tl.lineAt(i).naturalTextWidth());
    return std::ceil(w) + 2;
}

// ——— Miękki cień ———

// Rozmycie kanału alfa: trzy przejścia rozmycia pudełkowego ≈ rozmycie Gaussa
static void blurAlpha(QImage &img, int radius)
{
    if (radius < 1)
        return;
    const int w = img.width(), h = img.height();
    QList<int> line(qMax(w, h));
    for (int pass = 0; pass < 3; ++pass) {
        for (int dir = 0; dir < 2; ++dir) {
            const int len = dir == 0 ? w : h, count = dir == 0 ? h : w;
            for (int j = 0; j < count; ++j) {
                auto px = [&](int i) -> QRgb & {
                    return dir == 0 ? reinterpret_cast<QRgb *>(img.scanLine(j))[i] : reinterpret_cast<QRgb *>(img.scanLine(i))[j];
                };
                for (int i = 0; i < len; ++i)
                    line[i] = qAlpha(px(i));
                int sum = 0;
                const int win = radius * 2 + 1;
                for (int i = -radius; i <= radius; ++i)
                    sum += line[qBound(0, i, len - 1)];
                for (int i = 0; i < len; ++i) {
                    px(i) = qRgba(0, 0, 0, sum / win);
                    sum += line[qMin(len - 1, i + radius + 1)] - line[qMax(0, i - radius)];
                }
            }
        }
    }
}

void paintElement(QPainter *p, const QVariantMap &el, const ImageSource *images);

// Cień elementu: element narysowany na boku, rozmyty i przesunięty. Wynik w pamięci podręcznej (płótno rysuje często)
static void paintSoftShadow(QPainter *p, const QVariantMap &el, const ImageSource *images)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const qreal blur = qMax(0.0, num(el, "shadowBlur", 20));
    const qreal dist = num(el, "shadowDist", 12), angle = qDegreesToRadians(num(el, "shadowAngle", 135));
    QColor c = color(el, "shadowColor", Qt::black);
    c.setAlphaF(c.alphaF() * qBound(0.0, num(el, "shadowOpacity", 0.35), 1.0));
    const qreal scale = qBound(0.05, deviceScale(p), 8.0);
    const qreal m = blur * 1.5 + 2;
    const QSize size(qCeil((w + 2 * m) * scale), qCeil((h + 2 * m) * scale));
    if (size.width() * size.height() > 40'000'000 || size.isEmpty())
        return;

    QVariantMap plain = el;
    for (const char *k : {"shadow", "x", "y", "rotation", "opacity"})
        plain.remove(QLatin1String(k));
    static QMutex lock;
    static QCache<QString, QImage> cache(120);
    const QString key = QString::fromUtf8(QJsonDocument::fromVariant(plain).toJson(QJsonDocument::Compact))
                        + QStringLiteral("|%1|%2x%3").arg(c.name(QColor::HexArgb)).arg(size.width()).arg(size.height());
    QImage img;
    {
        QMutexLocker l(&lock);
        if (const QImage *hit = cache.object(key))
            img = *hit;
    }
    if (img.isNull()) {
        img = QImage(size, QImage::Format_ARGB32);
        img.fill(Qt::transparent);
        {
            QPainter q(&img);
            q.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
            q.scale(scale, scale);
            q.translate(m, m);
            plain.remove(QStringLiteral("shadowBlur"));
            paintElement(&q, plain, images);
        }
        blurAlpha(img, qRound(blur * scale / 2));
        // Kolor cienia z zachowaniem rozmytej alfy
        for (int y = 0; y < img.height(); ++y) {
            QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x)
                line[x] = qRgba(c.red(), c.green(), c.blue(), qAlpha(line[x]) * c.alpha() / 255);
        }
        QMutexLocker l(&lock);
        cache.insert(key, new QImage(img), int(img.sizeInBytes() / (1024 * 1024)) + 1);
    }
    p->save();
    p->setRenderHint(QPainter::SmoothPixmapTransform);
    p->drawImage(QRectF(-m + qSin(angle) * dist, -m - qCos(angle) * dist, w + 2 * m, h + 2 * m), img);
    p->restore();
}

void paintElement(QPainter *p, const QVariantMap &el, const ImageSource *images)
{
    const QString kind = el.value(QStringLiteral("type")).toString();
    if (el.value(QStringLiteral("shadow")).toBool() && (kind != QLatin1String("text") || el.contains(QStringLiteral("shadowBlur"))))
        paintSoftShadow(p, el, images);
    p->save();
    p->setRenderHint(QPainter::Antialiasing);
    p->setRenderHint(QPainter::TextAntialiasing);
    const QString type = el.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("text"))
        paintText(p, el);
    else if (type == QLatin1String("shape"))
        paintShape(p, el);
    else if (type == QLatin1String("image"))
        paintPicture(p, el, images);
    else if (type == QLatin1String("vector"))
        paintVector(p, el, images);
    p->restore();
}

void paintBackground(QPainter *p, const QVariantMap &bg, const QSizeF &page, const ImageSource *images)
{
    const QRectF r(QPointF(0, 0), page);
    const QString type = bg.value(QStringLiteral("type"), QStringLiteral("color")).toString();
    const QColor c = color(bg, "color", Qt::white);
    if (type == QLatin1String("gradient") || type == QLatin1String("radial")) {
        p->fillRect(r, gradientBrush(c, color(bg, "color2", Qt::black), num(bg, "angle", 180), r, type == QLatin1String("radial")));
    } else {
        p->fillRect(r, c);
        if (type == QLatin1String("image") && images) {
            const QImage img = images->image(bg.value(QStringLiteral("src")).toString(), qMax(page.width(), page.height()) * deviceScale(p));
            p->save();
            p->setOpacity(num(bg, "imageOpacity", 1));
            paintCover(p, img, r, {});
            p->restore();
        }
    }
}

void paintPage(QPainter *p, const QVariantMap &doc, const ImageSource *images)
{
    const QSizeF page(num(doc, "width", 1080), num(doc, "height", 1080));
    p->save();
    p->setClipRect(QRectF(QPointF(0, 0), page));
    paintBackground(p, doc.value(QStringLiteral("background")).toMap(), page, images);
    const QVariantList elements = doc.value(QStringLiteral("elements")).toList();
    for (const QVariant &v : elements) {
        const QVariantMap el = v.toMap();
        if (el.value(QStringLiteral("hidden")).toBool())
            continue;
        const qreal w = num(el, "w", 100), h = num(el, "h", 100);
        p->save();
        p->translate(num(el, "x", 0) + w / 2, num(el, "y", 0) + h / 2);
        p->rotate(num(el, "rotation", 0));
        p->translate(-w / 2, -h / 2);
        p->setOpacity(qBound(0.0, num(el, "opacity", 1), 1.0));
        paintElement(p, el, images);
        p->restore();
    }
    p->restore();
}

qreal bleed(const QVariantMap &el)
{
    if (!el.value(QStringLiteral("shadow")).toBool() || (el.value(QStringLiteral("type")).toString() == QLatin1String("text") && !el.contains(QStringLiteral("shadowBlur"))))
        return 0;
    return num(el, "shadowBlur", 20) * 1.5 + qAbs(num(el, "shadowDist", 12)) + 2;
}

QImage renderPage(const QVariantMap &doc, const QSize &size, const ImageSource *images, const QColor &under)
{
    QImage img(size, QImage::Format_ARGB32_Premultiplied);
    img.fill(under);
    QPainter p(&img);
    p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    p.scale(size.width() / num(doc, "width", 1080), size.height() / num(doc, "height", 1080));
    paintPage(&p, doc, images);
    p.end();
    return img;
}

}

#include "art.h"

#include <QCache>
#include <QFontMetricsF>
#include <QGlyphRun>
#include <Prison/Barcode>
#include <QJsonDocument>
#include <QLocale>
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
    const int weight = qBound(100, int(num(el, "weight", 400)), 900);
    f.setWeight(QFont::Weight(weight));
    // Czcionki zmienne (np. pobrane z repozytorium Google Fonts) — grubość z osi „wght”, inaczej byłaby najcieńsza
    f.setVariableAxis(QFont::Tag("wght"), weight);
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

// Lista: `list` = "bullet" (•) albo "number" (1. 2. …) — znak przed każdym akapitem, puste wiersze bez znaku
QString listPrefix(const QVariantMap &el, int n)
{
    const QString list = el.value(QStringLiteral("list")).toString();
    if (list == QLatin1String("bullet"))
        return QStringLiteral("•\u2002");
    if (list == QLatin1String("number"))
        return QString::number(n) + QStringLiteral(".\u2002");
    return {};
}

QString layoutText(const QVariantMap &el)
{
    QString t = el.value(QStringLiteral("text")).toString();
    if (el.value(QStringLiteral("list")).toString().isEmpty()) {
        t.replace(QLatin1Char('\n'), QChar::LineSeparator);
        return t;
    }
    QStringList lines = t.split(QLatin1Char('\n'));
    int n = 0;
    for (QString &line : lines)
        if (!line.trimmed().isEmpty())
            line.prepend(listPrefix(el, ++n));
    return lines.join(QChar::LineSeparator);
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
    // Lista wyrównana do lewej: zawinięte wiersze zaczynają się pod tekstem, nie pod znakiem
    const bool hanging = !el.value(QStringLiteral("list")).toString().isEmpty() && textAlign(el) == Qt::AlignLeft && width > 0;
    const QFontMetricsF fm(tl.font());
    qreal indent = 0;                           // szerokość znaku bieżącego akapitu („•”, „12.”)
    const QString text = tl.text();
    qreal y = 0;
    tl.beginLayout();
    for (;;) {
        QTextLine line = tl.createLine();
        if (!line.isValid())
            break;
        const int start = line.textStart();
        const bool first = start == 0 || text.at(start - 1) == QChar::LineSeparator;
        if (hanging && first) {
            const int end = text.indexOf(QChar(0x2002), start);
            indent = end >= 0 && end - start < 6 ? fm.horizontalAdvance(text.mid(start, end - start + 1)) : 0;
        }
        const bool cont = hanging && !first && indent > 0;
        if (width > 0)
            line.setLineWidth(cont ? width - indent : width);
        line.setPosition(QPointF(cont ? indent : 0, y + (lineH - line.height()) / 2));
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

QBrush gradientBrush(const QColor &a, const QColor &b, qreal angle, const QRectF &r, bool radial);

// Kolor tekstu albo przejście kolorów (`color2`, `gradientAngle`) przez cały blok tekstu
QBrush textBrush(const QVariantMap &el, const QRectF &r)
{
    const QColor a = color(el, "color", Qt::black), b = color(el, "color2");
    if (b.isValid() && b.alpha() > 0)
        return gradientBrush(a, b, num(el, "gradientAngle", 90), r, false);
    return QBrush(a);
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
    p->fillPath(out, textBrush(el, out.boundingRect()));
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
    p->setPen(QPen(textBrush(el, QRectF(0, 0, w, num(el, "h", 100))), 0));
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
    } else if (mask == QLatin1String("pentagon") || mask == QLatin1String("octagon")) {
        const int n = mask == QLatin1String("pentagon") ? 5 : 8;
        const qreal start = n == 5 ? -M_PI / 2 : -M_PI / 2 + M_PI / 8;
        for (int i = 0; i < n; ++i) {
            const qreal a = start + i * 2 * M_PI / n;
            const QPointF pt(x + w / 2 + qCos(a) * w / 2, y + h / 2 + qSin(a) * h / 2);
            if (i == 0)
                path.moveTo(pt);
            else
                path.lineTo(pt);
        }
        path.closeSubpath();
    } else if (mask == QLatin1String("burst")) {
        // Plakietka promocyjna — gwiazda z wieloma krótkimi ramionami
        path = starPath(r, 16, 0.84);
    } else if (mask == QLatin1String("bubble")) {
        // Dymek: zaokrąglony prostokąt i ogonek w lewym dolnym rogu
        const qreal tail = h * 0.2, k = qMin(w, h - tail) * 0.22;
        QPainterPath box;
        box.addRoundedRect(QRectF(x, y, w, h - tail), k, k);
        QPainterPath t;
        t.moveTo(x + w * 0.18, y + h - tail - 1);
        t.lineTo(x + w * 0.12, y + h);
        t.lineTo(x + w * 0.38, y + h - tail - 1);
        t.closeSubpath();
        path = box.united(t);
    } else if (mask == QLatin1String("arrowBlock")) {
        const qreal head = qMin(w * 0.45, h);
        path.moveTo(x, y + h * 0.3);
        path.lineTo(x + w - head, y + h * 0.3);
        path.lineTo(x + w - head, y);
        path.lineTo(x + w, y + h / 2);
        path.lineTo(x + w - head, y + h);
        path.lineTo(x + w - head, y + h * 0.7);
        path.lineTo(x, y + h * 0.7);
        path.closeSubpath();
    } else if (mask == QLatin1String("ribbon")) {
        // Wstążka na napis — wcięte końce
        const qreal n = qMin(w * 0.12, h * 0.5);
        path.moveTo(x, y);
        path.lineTo(x + w, y);
        path.lineTo(x + w - n, y + h / 2);
        path.lineTo(x + w, y + h);
        path.lineTo(x, y + h);
        path.lineTo(x + n, y + h / 2);
        path.closeSubpath();
    } else if (mask == QLatin1String("cross")) {
        const qreal t = qMin(w, h) / 3;
        path.addRect(QRectF(x + (w - t) / 2, y, t, h));
        path.addRect(QRectF(x, y + (h - t) / 2, w, t));
        path = path.simplified();
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

    if (shape == QLatin1String("line") || shape == QLatin1String("arrow") || shape == QLatin1String("doubleArrow")) {
        const qreal t = qMax(1.0, sw > 0 ? sw : 6);
        QPen pen(stroke.alpha() > 0 ? stroke : color(el, "fill", Qt::black), t);
        pen.setCapStyle(Qt::RoundCap);
        if (el.value(QStringLiteral("dash")).toBool())
            pen.setDashPattern({2, 2.2});
        const qreal cy = h / 2;
        qreal end = w - t / 2, begin = t / 2;
        if (shape != QLatin1String("line")) {
            const bool both = shape == QLatin1String("doubleArrow");
            const qreal head = qMin(w * (both ? 0.3 : 0.45), t * 3.2 + 10);
            end = w - head * 0.7;
            if (both)
                begin = head * 0.7;
            QPainterPath tip;
            tip.moveTo(w, cy);
            tip.lineTo(w - head, cy - head * 0.62);
            tip.lineTo(w - head, cy + head * 0.62);
            tip.closeSubpath();
            if (both) {
                tip.moveTo(0, cy);
                tip.lineTo(head, cy - head * 0.62);
                tip.lineTo(head, cy + head * 0.62);
                tip.closeSubpath();
            }
            p->setPen(Qt::NoPen);
            p->setBrush(pen.color());
            p->drawPath(tip);
        }
        p->setPen(pen);
        p->drawLine(QPointF(begin, cy), QPointF(end, cy));
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
    } else if (shape != QLatin1String("rect")) {
        path = maskPath(shape, r);
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

// Rysunek odręczny: punkty (x, y) w częściach pola elementu, gładka linia przez środki odcinków.
// pen: pen (pisak), marker, highlighter (zakreślacz — półprzezroczysty, płaskie końce), neon (świecąca poświata)
QPainterPath drawPath(const QVariantMap &el)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const QVariantList pts = el.value(QStringLiteral("points")).toList();
    QPainterPath path;
    const int n = int(pts.size() / 2);
    if (n == 0)
        return path;
    auto at = [&](int i) { return QPointF(pts[2 * i].toDouble() * w, pts[2 * i + 1].toDouble() * h); };
    path.moveTo(at(0));
    if (n == 1) {
        path.lineTo(at(0) + QPointF(0.01, 0));
        return path;
    }
    for (int i = 1; i < n - 1; ++i) {
        const QPointF a = at(i), b = at(i + 1);
        path.quadTo(a, (a + b) / 2);
    }
    path.lineTo(at(n - 1));
    return path;
}

void paintDraw(QPainter *p, const QVariantMap &el)
{
    const QPainterPath path = drawPath(el);
    if (path.isEmpty())
        return;
    const QString kind = el.value(QStringLiteral("pen"), QStringLiteral("pen")).toString();
    const qreal sw = qMax(0.5, num(el, "strokeWidth", 8));
    QColor c = color(el, "stroke", Qt::black);
    p->setBrush(Qt::NoBrush);
    if (kind == QLatin1String("neon")) {
        // Poświata: kilka coraz węższych warstw, na środku jasny rdzeń
        for (const auto &[k, a] : {std::pair{4.2, 0.07}, {3.0, 0.1}, {2.0, 0.16}, {1.4, 0.3}}) {
            QColor g = c;
            g.setAlphaF(c.alphaF() * a);
            QPen pen(g, sw * k, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            p->setPen(pen);
            p->drawPath(path);
        }
        p->setPen(QPen(c, sw, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(path);
        p->setPen(QPen(QColor(255, 255, 255, 220), sw * 0.4, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(path);
        return;
    }
    const bool hi = kind == QLatin1String("highlighter");
    if (hi)
        c.setAlphaF(c.alphaF() * 0.42);
    QPen pen(c, sw, Qt::SolidLine, hi ? Qt::FlatCap : Qt::RoundCap, hi ? Qt::BevelJoin : Qt::RoundJoin);
    p->setPen(pen);
    p->drawPath(path);
}

// ——— Poprawki zdjęć ———

// Jasność, kontrast, nasycenie (−1..1) i gotowe filtry; wynik w pamięci podręcznej, bo płótno rysuje się często.
// `pixels` — potrzebny dłuższy bok: większe zdjęcie najpierw się zmniejsza (miniatury filtrów, suwaki bez zacinania).
// Rozmycie pudełkowe trzy razy (≈ Gauss) na wszystkich kanałach obrazu z premultiplikowaną alfą
void boxBlur(QImage &img, int r)
{
    if (r < 1)
        return;
    const int w = img.width(), h = img.height();
    QList<QRgb> buf(qMax(w, h));
    for (int pass = 0; pass < 3; ++pass) {
        for (int dir = 0; dir < 2; ++dir) {
            const int len = dir == 0 ? w : h, count = dir == 0 ? h : w;
            for (int j = 0; j < count; ++j) {
                auto px = [&](int i) -> QRgb & {
                    return dir == 0 ? reinterpret_cast<QRgb *>(img.scanLine(j))[i] : reinterpret_cast<QRgb *>(img.scanLine(i))[j];
                };
                for (int i = 0; i < len; ++i)
                    buf[i] = px(i);
                int sa = 0, sr = 0, sg = 0, sb = 0;
                const int win = r * 2 + 1;
                for (int i = -r; i <= r; ++i) {
                    const QRgb c = buf[qBound(0, i, len - 1)];
                    sa += qAlpha(c); sr += qRed(c); sg += qGreen(c); sb += qBlue(c);
                }
                for (int i = 0; i < len; ++i) {
                    px(i) = qRgba(sr / win, sg / win, sb / win, sa / win);
                    const QRgb in = buf[qMin(len - 1, i + r + 1)], out = buf[qMax(0, i - r)];
                    sa += qAlpha(in) - qAlpha(out); sr += qRed(in) - qRed(out);
                    sg += qGreen(in) - qGreen(out); sb += qBlue(in) - qBlue(out);
                }
            }
        }
    }
}

// Usunięcie jednolitego tła (np. produkt na białym): zalewanie od brzegów pikselami podobnymi do koloru rogów,
// potem lekko rozmyta maska, żeby krawędź nie była poszarpana. tolerance 0..1
void removeBackground(QImage &img, qreal tolerance)
{
    const int w = img.width(), h = img.height();
    if (w < 3 || h < 3)
        return;
    int r = 0, g = 0, b = 0;
    const QPoint corners[] = {{0, 0}, {w - 1, 0}, {0, h - 1}, {w - 1, h - 1}};
    for (const QPoint &c : corners) {
        const QRgb px = img.pixel(c);
        r += qRed(px); g += qGreen(px); b += qBlue(px);
    }
    r /= 4; g /= 4; b /= 4;
    const int thr = qRound(qBound(0.02, tolerance, 1.0) * 160);
    const int thr2 = thr * thr;
    auto near = [&](QRgb c) {
        const int dr = qRed(c) - r, dg = qGreen(c) - g, db = qBlue(c) - b;
        return qAlpha(c) < 16 || dr * dr + dg * dg + db * db <= thr2;
    };
    QImage mask(w, h, QImage::Format_ARGB32_Premultiplied);
    mask.fill(qRgba(255, 255, 255, 255));
    QList<int> stack;
    QList<bool> seen(w * h, false);
    auto push = [&](int x, int y) {
        const int i = y * w + x;
        if (seen[i])
            return;
        seen[i] = true;
        if (near(reinterpret_cast<const QRgb *>(img.constScanLine(y))[x]))
            stack.append(i);
    };
    for (int x = 0; x < w; ++x) { push(x, 0); push(x, h - 1); }
    for (int y = 0; y < h; ++y) { push(0, y); push(w - 1, y); }
    while (!stack.isEmpty()) {
        const int i = stack.takeLast();
        const int x = i % w, y = i / w;
        reinterpret_cast<QRgb *>(mask.scanLine(y))[x] = 0;
        if (x > 0) push(x - 1, y);
        if (x < w - 1) push(x + 1, y);
        if (y > 0) push(x, y - 1);
        if (y < h - 1) push(x, y + 1);
    }
    boxBlur(mask, qMax(1, qMax(w, h) / 600));
    for (int y = 0; y < h; ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
        const QRgb *m = reinterpret_cast<const QRgb *>(mask.constScanLine(y));
        for (int x = 0; x < w; ++x)
            line[x] = qRgba(qRed(line[x]), qGreen(line[x]), qBlue(line[x]), qAlpha(line[x]) * qAlpha(m[x]) / 255);
    }
}

QImage adjusted(const QImage &src, const QVariantMap &el, qreal pixels)
{
    const qreal br = qBound(-1.0, num(el, "brightness", 0), 1.0);
    const qreal ct = qBound(-1.0, num(el, "contrast", 0), 1.0);
    const qreal sat = qBound(-1.0, num(el, "saturation", 0), 1.0);
    const qreal blur = qBound(0.0, num(el, "blur", 0), 1.0);
    const qreal vignette = qBound(0.0, num(el, "vignette", 0), 1.0);
    const qreal removeBg = el.value(QStringLiteral("removeBg")).toBool() ? num(el, "bgTolerance", 0.25) : -1;
    const QString filter = el.value(QStringLiteral("filter")).toString();
    const QColor duo1 = color(el, "duo1", QColor(0x1E, 0x2A, 0x78)), duo2 = color(el, "duo2", QColor(0xFF, 0xB3, 0xC7));
    if (br == 0 && ct == 0 && sat == 0 && filter.isEmpty() && blur == 0 && vignette == 0 && removeBg < 0)
        return src;

    static QMutex lock;
    static QCache<QString, QImage> cache(160);       // koszt w MB
    const int side = qMax(src.width(), src.height());
    const int target = pixels * 1.25 < side ? qMax(16, qRound(pixels * 1.25)) : side;
    const QString key = QStringLiteral("%1|%2|%3|%4|%5|%6|%7|%8|%9").arg(src.cacheKey()).arg(target).arg(br).arg(ct).arg(sat).arg(filter)
                            .arg(blur).arg(vignette).arg(removeBg) + duo1.name() + duo2.name();
    {
        QMutexLocker l(&lock);
        if (const QImage *hit = cache.object(key))
            return *hit;
    }

    QImage img = (target < side ? src.scaled(src.width() * target / side, src.height() * target / side, Qt::KeepAspectRatio, Qt::SmoothTransformation) : src)
                     .convertToFormat(QImage::Format_ARGB32);
    if (removeBg >= 0)
        removeBackground(img, removeBg);
    int lut[256];
    for (int i = 0; i < 256; ++i)
        lut[i] = qBound(0, qRound((i - 128) * (1 + ct) + 128 + br * 110), 255);
    const qreal satK = filter == QLatin1String("gray") || filter == QLatin1String("duotone") ? 0 : 1 + sat;
    const qreal cx = img.width() / 2.0, cy = img.height() / 2.0, diag = std::hypot(cx, cy);
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
            } else if (filter == QLatin1String("duotone")) {
                // Cienie w pierwszym kolorze, światła w drugim
                const qreal t = qBound(0.0, r / 255, 1.0);
                r = duo1.red() + (duo2.red() - duo1.red()) * t;
                g = duo1.green() + (duo2.green() - duo1.green()) * t;
                b = duo1.blue() + (duo2.blue() - duo1.blue()) * t;
            }
            if (vignette > 0) {
                // Przyciemnienie brzegów: od 45% odległości od środka do rogów
                const qreal d = std::hypot(x - cx, y - cy) / diag;
                const qreal k = 1 - vignette * 0.85 * qBound(0.0, (d - 0.45) / 0.55, 1.0);
                r *= k; g *= k; b *= k;
            }
            line[x] = qRgba(qBound(0, qRound(r), 255), qBound(0, qRound(g), 255), qBound(0, qRound(b), 255), qAlpha(c));
        }
    }
    if (blur > 0) {
        // Promień w częściach zdjęcia — ten sam wygląd na ekranie i w eksporcie w pełnej rozdzielczości
        img = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        boxBlur(img, qRound(blur * 0.03 * qMax(img.width(), img.height())));
    }
    QMutexLocker l(&lock);
    cache.insert(key, new QImage(img), int(img.sizeInBytes() / (1024 * 1024)) + 1);
    return img;
}

// ——— Kody QR i kreskowe ———

// Treść kodu: zwykły tekst/adres albo Wi-Fi (sieć i hasło w formacie, który rozumieją aparaty telefonów)
QString codeData(const QVariantMap &el)
{
    if (el.value(QStringLiteral("qrType")).toString() == QLatin1String("wifi")) {
        auto esc = [](QString s) {
            for (const char *c : {"\\", ";", ",", ":", "\""})
                s.replace(QLatin1String(c), QLatin1String("\\") + QLatin1String(c));
            return s;
        };
        const QString pass = el.value(QStringLiteral("pass")).toString();
        return QStringLiteral("WIFI:T:%1;S:%2;P:%3;;").arg(pass.isEmpty() ? QStringLiteral("nopass") : QStringLiteral("WPA"),
                                                           esc(el.value(QStringLiteral("ssid")).toString()), esc(pass));
    }
    return el.value(QStringLiteral("data")).toString();
}

// Moduły kodu jako kształt (ostry w PDF); wynik w pamięci podręcznej. size — liczba modułów
QPainterPath codePath(const QString &kind, const QString &data, QSizeF *size)
{
    static QMutex lock;
    static QHash<QString, QPair<QPainterPath, QSizeF>> cache;
    const QString key = kind + QLatin1Char('|') + data;
    QMutexLocker l(&lock);
    if (cache.contains(key)) {
        *size = cache.value(key).second;
        return cache.value(key).first;
    }
    const Prison::BarcodeType type = kind == QLatin1String("ean13") ? Prison::EAN13 : kind == QLatin1String("code128") ? Prison::Code128 : Prison::QRCode;
    QPainterPath path;
    QSizeF s;
    if (auto code = Prison::Barcode::create(type)) {
        code->setData(data);
        const QImage img = code->toImage(code->minimumSize());
        s = img.size();
        // Ciemne piksele najmniejszego obrazu kodu = moduły; poziome odcinki łączone w prostokąty
        for (int y = 0; y < img.height(); ++y) {
            int run = -1;
            for (int x = 0; x <= img.width(); ++x) {
                const bool dark = x < img.width() && qGray(img.pixel(x, y)) < 128 && qAlpha(img.pixel(x, y)) > 128;
                if (dark && run < 0)
                    run = x;
                if (!dark && run >= 0) {
                    path.addRect(QRectF(run, y, x - run, 1));
                    run = -1;
                }
            }
        }
        path = path.simplified();
    }
    if (cache.size() > 200)
        cache.clear();
    cache.insert(key, {path, s});
    *size = s;
    return path;
}

void paintCode(QPainter *p, const QVariantMap &el)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const QString kind = el.value(QStringLiteral("kind"), QStringLiteral("qr")).toString();
    const QColor bg = color(el, "bg", Qt::white);
    const qreal radius = num(el, "radius", 0);
    p->setPen(Qt::NoPen);
    if (bg.alpha() > 0) {
        p->setBrush(bg);
        p->drawRoundedRect(QRectF(0, 0, w, h), radius, radius);
    }
    QSizeF modules;
    const QPainterPath path = codePath(kind, codeData(el), &modules);
    if (path.isEmpty() || modules.isEmpty()) {
        // Złe dane (np. EAN-13 bez 12–13 cyfr) — przekreślone pole zamiast kodu
        QPen pen(QColor(229, 57, 53), qMax(1.0, qMin(w, h) * 0.02));
        p->setPen(pen);
        p->drawLine(QPointF(w * 0.2, h * 0.2), QPointF(w * 0.8, h * 0.8));
        p->drawLine(QPointF(w * 0.8, h * 0.2), QPointF(w * 0.2, h * 0.8));
        return;
    }
    // Margines (strefa ciszy) i skala: kwadratowe moduły QR, kod kreskowy rozciągnięty na całe pole
    const qreal m = qMin(w, h) * 0.06;
    const QRectF area(m, m, w - 2 * m, h - 2 * m);
    qreal sx = area.width() / modules.width(), sy = area.height() / modules.height();
    if (kind == QLatin1String("qr"))
        sx = sy = qMin(sx, sy);
    QTransform t;
    t.translate(area.center().x() - modules.width() * sx / 2, area.center().y() - modules.height() * sy / 2);
    t.scale(sx, sy);
    p->setBrush(color(el, "color", Qt::black));
    p->drawPath(t.map(path));
}

// ——— Wykresy ———

// data: [{ label, value, color }]; chart = column | bar | pie | donut | line
void paintChart(QPainter *p, const QVariantMap &el)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const QVariantList data = el.value(QStringLiteral("data")).toList();
    const QString chart = el.value(QStringLiteral("chart"), QStringLiteral("column")).toString();
    static const char *palette[] = {"#5B7CFA", "#FF7A59", "#22B07D", "#FFB300", "#E53961", "#7E57C2", "#00ACC1", "#8D6E63"};
    auto colorAt = [&](int i) {
        const QColor c = color(data.at(i).toMap(), "color");
        return c.isValid() && c.alpha() > 0 ? c : QColor::fromString(QLatin1String(palette[i % 8]));
    };
    const QColor ink = color(el, "color", QColor(0x3D, 0x40, 0x48));
    const qreal fs = qMax(6.0, num(el, "size", qMin(w, h) * 0.06));
    QFont font(el.value(QStringLiteral("font"), QStringLiteral("Geist")).toString());
    font.setPixelSize(qMax(1, qRound(fs)));
    font.setHintingPreference(QFont::PreferNoHinting);
    p->setFont(font);
    const QFontMetricsF fm(font);
    const bool values = el.value(QStringLiteral("values"), true).toBool();
    if (data.isEmpty())
        return;
    qreal max = 0, sum = 0;
    for (const QVariant &v : data) {
        max = qMax(max, v.toMap().value(QStringLiteral("value")).toDouble());
        sum += qMax(0.0, v.toMap().value(QStringLiteral("value")).toDouble());
    }
    auto fmt = [](qreal v) { return QLocale(QLocale::Polish).toString(v, 'g', 6); };
    const int n = data.size();

    if (chart == QLatin1String("pie") || chart == QLatin1String("donut")) {
        // Koło po lewej, legenda po prawej (albo pod spodem w wąskim polu)
        const bool side = w >= h * 1.2;
        const qreal d = side ? qMin(h, w * 0.55) : qMin(w, h - (fm.height() * 1.4) * n);
        const QRectF circle(side ? 0 : (w - d) / 2, side ? (h - d) / 2 : 0, d, d);
        qreal start = 90 * 16;
        for (int i = 0; i < n; ++i) {
            const qreal v = qMax(0.0, data.at(i).toMap().value(QStringLiteral("value")).toDouble());
            const qreal span = sum > 0 ? -v / sum * 360 * 16 : 0;
            p->setPen(QPen(color(el, "bg", Qt::white), qMax(1.0, d * 0.008)));
            p->setBrush(colorAt(i));
            p->drawPie(circle, int(start), int(span));
            start += span;
        }
        if (chart == QLatin1String("donut")) {
            p->setPen(Qt::NoPen);
            const QColor hole = color(el, "bg", Qt::white);
            p->setBrush(hole.alpha() > 0 ? hole : QColor(Qt::white));
            const qreal k = d * 0.28;
            p->drawEllipse(circle.adjusted(k, k, -k, -k));
        }
        qreal ly = side ? (h - fm.height() * 1.5 * n) / 2 : d + fm.height() * 0.6;
        const qreal lx = side ? d + fs * 1.4 : fs;
        for (int i = 0; i < n; ++i) {
            const QVariantMap it = data.at(i).toMap();
            p->setPen(Qt::NoPen);
            p->setBrush(colorAt(i));
            p->drawRoundedRect(QRectF(lx, ly + fm.height() * 0.2, fm.height() * 0.6, fm.height() * 0.6), fs * 0.12, fs * 0.12);
            p->setPen(ink);
            const qreal v = it.value(QStringLiteral("value")).toDouble();
            const QString text = it.value(QStringLiteral("label")).toString() + (values && sum > 0 ? QStringLiteral(" · %1%").arg(qRound(v / sum * 100)) : QString());
            p->drawText(QRectF(lx + fm.height(), ly, w - lx - fm.height(), fm.height()), Qt::AlignLeft | Qt::AlignVCenter, text);
            ly += fm.height() * 1.5;
        }
        return;
    }

    const bool bars = chart == QLatin1String("bar");
    const qreal labelSpace = bars ? 0 : fm.height() * 1.4;
    const qreal valueSpace = values ? fm.height() * 1.3 : 0;
    if (bars) {
        // Poziome słupki: podpisy po lewej, wartości za słupkiem
        qreal lw = 0;
        for (const QVariant &v : data)
            lw = qMax(lw, fm.horizontalAdvance(v.toMap().value(QStringLiteral("label")).toString()));
        lw = qMin(lw + fs * 0.6, w * 0.4);
        const qreal vw = values ? fm.horizontalAdvance(fmt(max)) + fs * 0.6 : 0;
        const qreal row = h / n, bh = row * 0.62;
        for (int i = 0; i < n; ++i) {
            const QVariantMap it = data.at(i).toMap();
            const qreal v = qMax(0.0, it.value(QStringLiteral("value")).toDouble());
            const qreal y = i * row + (row - bh) / 2;
            const qreal len = max > 0 ? (w - lw - vw) * v / max : 0;
            p->setPen(ink);
            p->drawText(QRectF(0, i * row, lw - fs * 0.6, row), Qt::AlignRight | Qt::AlignVCenter, it.value(QStringLiteral("label")).toString());
            p->setPen(Qt::NoPen);
            p->setBrush(colorAt(i));
            p->drawRoundedRect(QRectF(lw, y, qMax(len, 1.0), bh), qMin(bh, len) * 0.18, qMin(bh, len) * 0.18);
            if (values) {
                p->setPen(ink);
                p->drawText(QRectF(lw + len + fs * 0.4, i * row, vw, row), Qt::AlignLeft | Qt::AlignVCenter, fmt(v));
            }
        }
        return;
    }
    const qreal plotH = h - labelSpace - valueSpace;
    const qreal colW = w / n;
    if (chart == QLatin1String("line")) {
        QPainterPath line;
        QList<QPointF> pts;
        for (int i = 0; i < n; ++i) {
            const qreal v = data.at(i).toMap().value(QStringLiteral("value")).toDouble();
            pts.append(QPointF(colW * (i + 0.5), valueSpace + plotH - (max > 0 ? plotH * v / max : 0)));
        }
        line.moveTo(pts.first());
        for (int i = 1; i < pts.size(); ++i)
            line.lineTo(pts.at(i));
        QPen pen(colorAt(0), qMax(2.0, fs * 0.22));
        pen.setJoinStyle(Qt::RoundJoin);
        pen.setCapStyle(Qt::RoundCap);
        p->setPen(pen);
        p->setBrush(Qt::NoBrush);
        p->drawPath(line);
        for (int i = 0; i < n; ++i) {
            p->setPen(Qt::NoPen);
            p->setBrush(colorAt(0));
            p->drawEllipse(pts.at(i), fs * 0.32, fs * 0.32);
            const QVariantMap it = data.at(i).toMap();
            p->setPen(ink);
            if (values)
                p->drawText(QRectF(colW * i, pts.at(i).y() - fm.height() * 1.3, colW, fm.height()), Qt::AlignCenter, fmt(it.value(QStringLiteral("value")).toDouble()));
            p->drawText(QRectF(colW * i, h - labelSpace, colW, labelSpace), Qt::AlignCenter, it.value(QStringLiteral("label")).toString());
        }
        return;
    }
    // Słupki pionowe
    const qreal bw = colW * 0.62;
    for (int i = 0; i < n; ++i) {
        const QVariantMap it = data.at(i).toMap();
        const qreal v = qMax(0.0, it.value(QStringLiteral("value")).toDouble());
        const qreal bh = max > 0 ? plotH * v / max : 0;
        const QRectF bar(colW * i + (colW - bw) / 2, valueSpace + plotH - bh, bw, qMax(bh, 1.0));
        p->setPen(Qt::NoPen);
        p->setBrush(colorAt(i));
        const qreal r = qMin(bw, bh) * 0.12;
        p->drawRoundedRect(bar, r, r);
        p->setPen(ink);
        if (values)
            p->drawText(QRectF(colW * i, bar.top() - fm.height() * 1.25, colW, fm.height()), Qt::AlignCenter, fmt(v));
        p->drawText(QRectF(colW * i, h - labelSpace, colW, labelSpace), Qt::AlignCenter, it.value(QStringLiteral("label")).toString());
    }
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

// Obramowanie zdjęcia: wzdłuż kształtu, w całości wewnątrz ramki
void paintFrameBorder(QPainter *p, const QVariantMap &el, const QPainterPath &clip, const QRectF &r)
{
    const qreal sw = num(el, "strokeWidth", 0);
    const QColor c = color(el, "stroke");
    if (sw <= 0 || c.alpha() == 0)
        return;
    QPainterPath shape = clip;
    if (shape.isEmpty())
        shape.addRect(r);
    p->save();
    p->setClipPath(shape, Qt::IntersectClip);
    p->setPen(QPen(c, sw * 2, Qt::SolidLine, Qt::FlatCap, Qt::MiterJoin));
    p->setBrush(Qt::NoBrush);
    p->drawPath(shape);
    p->restore();
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
    paintFrameBorder(p, el, clip, r);
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
    else if (type == QLatin1String("code"))
        paintCode(p, el);
    else if (type == QLatin1String("chart"))
        paintChart(p, el);
    else if (type == QLatin1String("draw"))
        paintDraw(p, el);
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

void paintPage(QPainter *p, const QVariantMap &doc, const ImageSource *images, qreal bleed)
{
    const QSizeF page(num(doc, "width", 1080), num(doc, "height", 1080));
    p->save();
    // Spad (druk): tło i elementy wychodzą o `bleed` poza stronę, żeby po przycięciu nie było białych brzegów
    p->setClipRect(QRectF(QPointF(0, 0), page).adjusted(-bleed, -bleed, bleed, bleed));
    p->save();
    p->translate(-bleed, -bleed);
    paintBackground(p, doc.value(QStringLiteral("background")).toMap(), page + QSizeF(2 * bleed, 2 * bleed), images);
    p->restore();
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

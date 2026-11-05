#include "stickers.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontMetricsF>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QtMath>

namespace {

// Małe litery bez polskich znaków — „zolw” znajdzie „żółw”
QString fold(const QString &s)
{
    QString out = s.toLower().normalized(QString::NormalizationForm_D);
    out.remove(QRegularExpression(QStringLiteral("\\p{Mn}")));
    out.replace(QChar(0x0142), QLatin1Char('l'));
    return out;
}

struct Builtin { const char *id, *name; };
const Builtin builtinTable[] = {
    {"subskrybuj", "Subskrybuj"}, {"obserwuj", "Obserwuj"}, {"polub", "Polub"}, {"link", "Link w opisie"},
    {"nowosc", "Nowość"}, {"czesc", "Część 1"}, {"strzalka", "Strzałka"}, {"kolko", "Kółko"},
    {"dymek", "Dymek"}, {"wow", "Wow"}, {"serce", "Serce"}, {"iskry", "Iskry"},
};

QFont heavy(int px)
{
    QFont f(QStringLiteral("Geist"));
    f.setPixelSize(px);
    f.setWeight(QFont::Black);
    return f;
}

// Obraz przycięty do tego, co narysowano (plus margines)
QImage trimmed(const QImage &img, int margin = 6)
{
    int x0 = img.width(), y0 = img.height(), x1 = -1, y1 = -1;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x)
            if (qAlpha(line[x]) > 8) {
                x0 = qMin(x0, x); x1 = qMax(x1, x);
                y0 = qMin(y0, y); y1 = qMax(y1, y);
            }
    }
    if (x1 < 0)
        return img;
    return img.copy(QRect(QPoint(x0, y0), QPoint(x1, y1)).adjusted(-margin, -margin, margin, margin).intersected(img.rect()));
}

// Napis jako kształt (do obrysu)
QPainterPath textPath(const QString &text, const QFont &font, QPointF center)
{
    QPainterPath p;
    const QFontMetricsF fm(font);
    p.addText(center.x() - fm.horizontalAdvance(text) / 2, center.y() + (fm.ascent() - fm.descent()) / 2, font, text);
    return p;
}

// Pigułka z napisem: tło (gradient), opcjonalny znaczek z lewej
void pill(QPainter &p, const QString &text, const QColor &a, const QColor &b, const QColor &fg, int icon)
{
    const QFont f = heavy(70);
    const QFontMetricsF fm(f);
    const qreal h = 130, iconW = icon ? 110 : 0;
    const qreal w = fm.horizontalAdvance(text) + 110 + iconW;
    const QRectF r((1000 - w) / 2, (400 - h) / 2, w, h);
    QLinearGradient g(r.topLeft(), r.bottomRight());
    g.setColorAt(0, a);
    g.setColorAt(1, b);
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0, 0, 0, 60));
    p.drawRoundedRect(r.translated(0, 8), h / 2, h / 2);       // cień
    p.setBrush(g);
    p.drawRoundedRect(r, h / 2, h / 2);
    const QPointF ic(r.left() + 55 + iconW / 2 - 10, r.center().y());
    if (icon == 1) {          // przycisk odtwarzania
        p.setBrush(Qt::white);
        p.drawRoundedRect(QRectF(ic.x() - 42, ic.y() - 30, 84, 60), 16, 16);
        QPainterPath tri;
        tri.moveTo(ic.x() - 12, ic.y() - 16);
        tri.lineTo(ic.x() + 18, ic.y());
        tri.lineTo(ic.x() - 12, ic.y() + 16);
        tri.closeSubpath();
        p.setBrush(a);
        p.drawPath(tri);
    } else if (icon == 2) {   // serce
        QPainterPath h2;
        h2.moveTo(ic.x(), ic.y() + 30);
        h2.cubicTo(ic.x() - 60, ic.y() - 10, ic.x() - 25, ic.y() - 55, ic.x(), ic.y() - 22);
        h2.cubicTo(ic.x() + 25, ic.y() - 55, ic.x() + 60, ic.y() - 10, ic.x(), ic.y() + 30);
        p.setBrush(QColor(0xFF, 0x2D, 0x55));
        p.drawPath(h2);
    }
    p.setBrush(fg);
    p.drawPath(textPath(text, f, QPointF(r.center().x() + iconW / 2, r.center().y())));
}

QPainterPath heartPath(QPointF c, qreal s)
{
    QPainterPath h;
    h.moveTo(c.x(), c.y() + s * 0.9);
    h.cubicTo(c.x() - s * 1.9, c.y() - s * 0.2, c.x() - s * 0.8, c.y() - s * 1.7, c.x(), c.y() - s * 0.6);
    h.cubicTo(c.x() + s * 0.8, c.y() - s * 1.7, c.x() + s * 1.9, c.y() - s * 0.2, c.x(), c.y() + s * 0.9);
    return h;
}

QPainterPath sparkle(QPointF c, qreal r)
{
    QPainterPath s;
    s.moveTo(c.x(), c.y() - r);
    s.quadTo(c.x(), c.y(), c.x() + r, c.y());
    s.quadTo(c.x(), c.y(), c.x(), c.y() + r);
    s.quadTo(c.x(), c.y(), c.x() - r, c.y());
    s.quadTo(c.x(), c.y(), c.x(), c.y() - r);
    return s;
}

QImage drawBuiltin(const QString &id)
{
    QImage img(1000, 400, QImage::Format_ARGB32_Premultiplied);
    if (id == QLatin1String("kolko") || id == QLatin1String("wow") || id == QLatin1String("serce") || id == QLatin1String("iskry")
        || id == QLatin1String("dymek") || id == QLatin1String("strzalka"))
        img = QImage(800, 800, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::TextAntialiasing);
    const QPointF c(img.width() / 2.0, img.height() / 2.0);
    if (id == QLatin1String("subskrybuj")) {
        pill(p, QStringLiteral("SUBSKRYBUJ"), QColor(0xFF, 0x3B, 0x5C), QColor(0xD9, 0x10, 0x3A), Qt::white, 1);
    } else if (id == QLatin1String("obserwuj")) {
        pill(p, QStringLiteral("OBSERWUJ +"), QColor(0x8B, 0x5C, 0xF6), QColor(0xEC, 0x48, 0x99), Qt::white, 0);
    } else if (id == QLatin1String("polub")) {
        pill(p, QStringLiteral("POLUB"), Qt::white, QColor(0xEE, 0xF0, 0xF5), QColor(0x16, 0x18, 0x1D), 2);
    } else if (id == QLatin1String("link")) {
        pill(p, QStringLiteral("LINK W OPISIE ↓"), QColor(0x23, 0x26, 0x2F), QColor(0x10, 0x12, 0x18), Qt::white, 0);
    } else if (id == QLatin1String("nowosc")) {
        p.translate(c);
        p.rotate(-6);
        p.translate(-c);
        pill(p, QStringLiteral("NOWOŚĆ!"), QColor(0xFF, 0xE0, 0x66), QColor(0xFF, 0xC4, 0x2E), QColor(0x16, 0x18, 0x1D), 0);
    } else if (id == QLatin1String("czesc")) {
        const QPainterPath t = textPath(QStringLiteral("CZĘŚĆ 1"), heavy(150), c);
        p.setPen(QPen(QColor(0x16, 0x18, 0x1D), 22, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(Qt::NoBrush);
        p.drawPath(t);
        p.setPen(Qt::NoPen);
        QLinearGradient g(0, c.y() - 70, 0, c.y() + 70);
        g.setColorAt(0, QColor(0xFF, 0xF3, 0xA0));
        g.setColorAt(1, QColor(0xFF, 0xC4, 0x2E));
        p.setBrush(g);
        p.drawPath(t);
    } else if (id == QLatin1String("strzalka")) {
        // Wygięta strzałka wskazująca w prawo w dół
        QPainterPath a;
        a.moveTo(150, 250);
        a.cubicTo(380, 120, 600, 260, 560, 520);
        QPainterPathStroker st;
        st.setWidth(56);
        st.setCapStyle(Qt::RoundCap);
        QPainterPath body = st.createStroke(a);
        QPainterPath head;
        head.moveTo(430, 470);
        head.lineTo(560, 660);
        head.lineTo(680, 450);
        head.closeSubpath();
        body = body.united(head);
        p.setPen(QPen(QColor(0x16, 0x18, 0x1D), 18, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(Qt::white);
        p.drawPath(body);
    } else if (id == QLatin1String("kolko")) {
        // Odręczne kółko do zaznaczania (koniec zachodzi na początek)
        QPainterPath ring;
        for (int i = 0; i <= 380; i += 4) {
            const qreal t = qDegreesToRadians(qreal(i) - 100);
            const qreal rr = 1 + 0.04 * qSin(t * 3);
            const QPointF pt(c.x() + 300 * rr * qCos(t), c.y() + 230 * rr * qSin(t) - (i > 360 ? 18 : 0));
            if (i == 0)
                ring.moveTo(pt);
            else
                ring.lineTo(pt);
        }
        p.setPen(QPen(QColor(0xFF, 0x3B, 0x30), 30, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(Qt::NoBrush);
        p.drawPath(ring);
    } else if (id == QLatin1String("dymek")) {
        QPainterPath b;
        b.addRoundedRect(QRectF(110, 170, 580, 330), 150, 150);
        QPainterPath tail;
        tail.moveTo(250, 470);
        tail.lineTo(190, 640);
        tail.lineTo(380, 490);
        tail.closeSubpath();
        b = b.united(tail);
        p.setPen(QPen(QColor(0x16, 0x18, 0x1D), 16, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(Qt::white);
        p.drawPath(b);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0x16, 0x18, 0x1D));
        p.drawPath(textPath(QStringLiteral("Hej!"), heavy(140), QPointF(400, 335)));
    } else if (id == QLatin1String("wow")) {
        QPainterPath star;
        const int n = 14;
        for (int i = 0; i <= 2 * n; ++i) {
            const qreal t = M_PI * i / n - M_PI / 2;
            const qreal r = i % 2 ? 250 : 360;
            const QPointF pt(c.x() + r * qCos(t), c.y() + r * 0.8 * qSin(t));
            if (i == 0)
                star.moveTo(pt);
            else
                star.lineTo(pt);
        }
        p.setPen(QPen(QColor(0x16, 0x18, 0x1D), 16, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(QColor(0xFF, 0xD8, 0x4D));
        p.drawPath(star);
        const QPainterPath t = textPath(QStringLiteral("WOW!"), heavy(170), c);
        p.setPen(QPen(Qt::white, 14, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(QColor(0xFF, 0x2D, 0x55));
        p.drawPath(t);
    } else if (id == QLatin1String("serce")) {
        const QPainterPath h = heartPath(QPointF(c.x(), c.y() + 40), 210);
        QLinearGradient g(0, 150, 0, 650);
        g.setColorAt(0, QColor(0xFF, 0x6B, 0x8A));
        g.setColorAt(1, QColor(0xE0, 0x10, 0x3A));
        p.setPen(Qt::NoPen);
        p.setBrush(g);
        p.drawPath(h);
        p.setBrush(QColor(255, 255, 255, 120));
        p.drawEllipse(QPointF(c.x() - 150, c.y() - 90), 45, 28);
    } else if (id == QLatin1String("iskry")) {
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0xFF, 0xD8, 0x4D));
        p.drawPath(sparkle(QPointF(380, 420), 230));
        p.setBrush(Qt::white);
        p.drawPath(sparkle(QPointF(610, 210), 120));
        p.setBrush(QColor(0xFF, 0xE9, 0x9A));
        p.drawPath(sparkle(QPointF(620, 600), 80));
    }
    p.end();
    return trimmed(img);
}

} // namespace

Stickers::Stickers(QObject *parent)
    : QObject(parent)
{
}

QString Stickers::dir() const
{
    const QString d = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/stickers");
    QDir().mkpath(d);
    return d;
}

void Stickers::load()
{
    if (!m_groups.isEmpty())
        return;
    // Te same dane co panel emoji Aster (apps/emoji/data/emoji.json — z Unicode i polskiego CLDR)
    QFile f(QStringLiteral(":/emoji/emoji.json"));
    if (!f.open(QIODevice::ReadOnly))
        return;
    for (const QJsonValue &g : QJsonDocument::fromJson(f.readAll()).array()) {
        const QJsonObject o = g.toObject();
        Group group{o.value(QLatin1String("id")).toString(), o.value(QLatin1String("name")).toString(), {}};
        for (const QJsonValue &v : o.value(QLatin1String("emoji")).toArray()) {
            const QJsonArray e = v.toArray();
            group.items << Item{e.at(0).toString(), e.at(1).toString(), fold(e.at(1).toString() + QLatin1Char(' ') + e.at(2).toString())};
        }
        m_groups << group;
    }
}

QVariantList Stickers::groups()
{
    load();
    QVariantList l;
    for (const Group &g : std::as_const(m_groups))
        l << QVariantMap{{QStringLiteral("id"), g.id}, {QStringLiteral("name"), g.name},
                         {QStringLiteral("icon"), g.items.isEmpty() ? QString() : g.items.first().c}};
    return l;
}

QVariantList Stickers::emoji(const QString &group) const
{
    QVariantList l;
    for (const Group &g : m_groups)
        if (g.id == group)
            for (const Item &i : g.items)
                l << QVariantMap{{QStringLiteral("c"), i.c}, {QStringLiteral("n"), i.n}};
    return l;
}

QVariantList Stickers::search(const QString &text) const
{
    QVariantList l;
    const QStringList words = fold(text).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (words.isEmpty())
        return l;
    for (const Group &g : m_groups)
        for (const Item &i : g.items) {
            bool all = true;
            for (const QString &w : words)
                all &= i.s.contains(w);
            if (all)
                l << QVariantMap{{QStringLiteral("c"), i.c}, {QStringLiteral("n"), i.n}};
            if (l.size() >= 120)
                return l;
        }
    return l;
}

QString Stickers::emojiName(const QString &emoji) const
{
    for (const Group &g : m_groups)
        for (const Item &i : g.items)
            if (i.c == emoji)
                return i.n;
    return QStringLiteral("Emoji");
}

QString Stickers::emojiFile(const QString &emoji)
{
    QString code;
    for (const uint u : emoji.toUcs4())
        code += (code.isEmpty() ? QString() : QStringLiteral("-")) + QString::number(u, 16);
    const QString path = dir() + QStringLiteral("/emoji-%1.png").arg(code);
    if (QFileInfo::exists(path))
        return path;
    // Kolorowe emoji (Noto Color Emoji) w dużym rozmiarze — ostre także na pełnym kadrze 1080p.
    // Gdyby się nie narysowało (zależy od wersji Qt i czcionki), próbujemy mniejszych i powiększamy wynik.
    QImage result;
    for (const int px : {440, 320, 220}) {
        // Duże płótno i rysowanie od linii bazowej (wyśrodkowanie bywa mylone przez wymiary kolorowych glifów)
        QImage img(px * 3, px * 3, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        QFont f(QStringLiteral("Noto Color Emoji"));
        f.setPixelSize(px);
        p.setFont(f);
        p.drawText(QPointF(px * 0.75, px * 1.9), emoji);
        p.end();
        const QImage t = trimmed(img, 2);
        if (t.size() != img.size()) {      // coś narysowano
            result = px < 400 ? t.scaled(t.size() * (440.0 / px), Qt::KeepAspectRatio, Qt::SmoothTransformation) : t;
            break;
        }
    }
    if (result.isNull())
        return QString();
    result.save(path);
    return path;
}

QString Stickers::builtinFile(const QString &id)
{
    const QString path = dir() + QStringLiteral("/aster-%1-v1.png").arg(id);
    if (!QFileInfo::exists(path))
        drawBuiltin(id).save(path);
    return path;
}

QString Stickers::builtinName(const QString &id) const
{
    for (const Builtin &b : builtinTable)
        if (id == QLatin1String(b.id))
            return QString::fromUtf8(b.name);
    return QString();
}

QVariantList Stickers::builtins()
{
    if (m_builtins.isEmpty())
        for (const Builtin &b : builtinTable)
            m_builtins << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(b.id)}, {QStringLiteral("name"), QString::fromUtf8(b.name)},
                                      {QStringLiteral("url"), QUrl::fromLocalFile(builtinFile(QString::fromLatin1(b.id))).toString()}};
    return m_builtins;
}

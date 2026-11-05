#include "decoration.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KPluginFactory>
#include <QHash>
#include <QPainter>
#include <QPainterPath>

using namespace KDecoration3;

namespace Aster {

namespace {
// Pasek jest niższy niż w programach Aster (44 px), bo tam mieści się w nim też ich pasek narzędzi
constexpr qreal TitleHeight = 40;
constexpr qreal CornerRadius = 18;
constexpr qreal ButtonSize = 28;
constexpr qreal ButtonSpacing = 4;
constexpr qreal DotSize = 16;
constexpr qreal SideMargin = 8;
constexpr qreal ResizeMargin = 6;

struct DotColors {
    QColor top, bottom;
};

DotColors dotColors(DecorationButtonType type)
{
    switch (type) {
    case DecorationButtonType::Minimize:
        return {QColor(0xFF, 0xD1, 0x5C), QColor(0xF5, 0xA6, 0x23)};
    case DecorationButtonType::Maximize:
        return {QColor(0x5E, 0xDB, 0x8A), QColor(0x21, 0xB3, 0x5A)};
    default:
        return {QColor(0xFF, 0x7A, 0x72), QColor(0xEE, 0x3B, 0x32)};
    }
}

// Cień: 9‑segmentowy obraz, wspólny dla okien o tym samym stanie (kilka warstw jak w WindowShadow.qml)
std::shared_ptr<DecorationShadow> makeShadow(bool active, bool dark)
{
    // Słabe wskaźniki: cień znika razem z ostatnim oknem, które go używa
    static QHash<int, std::weak_ptr<DecorationShadow>> cache;
    const int key = (active ? 1 : 0) | (dark ? 2 : 0);
    if (auto cached = cache.value(key).lock())
        return cached;

    const int blur = active ? 44 : 26;
    const int offsetY = active ? 16 : 8;
    const qreal strength = (dark ? 0.62 : 0.30) * (active ? 1.0 : 0.65);
    const int inner = 2 * int(CornerRadius) + 2;
    const int side = blur + inner + blur;
    const QSize size(side, side + offsetY);

    QImage img(size, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);

    // Rozmycie Gaussa przybliżone nakładaniem coraz mniejszych, bardzo słabych prostokątów
    const QRectF base(blur, blur + offsetY, inner, inner);
    const int steps = blur;
    for (int i = 0; i < steps; ++i) {
        const qreal t = qreal(i) / steps;
        const qreal grow = blur * (1 - t) * 0.9;
        const qreal weight = t * t * (3 - 2 * t);
        p.setBrush(QColor(0, 0, 0, qBound(1, qRound(255 * strength * (0.02 + weight * 0.05)), 255)));
        p.drawRoundedRect(base.adjusted(-grow, -grow, grow, grow), CornerRadius + grow, CornerRadius + grow);
    }
    // Pod oknem nic nie widać, więc wycinamy środek — program z przezroczystością nie ściemni się od cienia
    p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
    p.setBrush(Qt::black);
    p.drawRoundedRect(QRectF(blur, blur, inner, inner), CornerRadius, CornerRadius);
    p.end();

    auto shadow = std::make_shared<DecorationShadow>();
    shadow->setShadow(img);
    shadow->setPadding(QMarginsF(blur, blur, blur, blur + offsetY));
    shadow->setInnerShadowRect(QRectF(blur + CornerRadius, blur + CornerRadius, 2, 2));
    cache.insert(key, shadow);
    return shadow;
}
} // namespace

Button::Button(DecorationButtonType type, Decoration *decoration)
    : DecorationButton(type, decoration, decoration)
{
    m_hoverAnim.setDuration(140);
    m_hoverAnim.setEasingCurve(QEasingCurve::OutCubic);
    connect(&m_hoverAnim, &QVariantAnimation::valueChanged, this, [this](const QVariant &v) {
        m_hover = v.toReal();
        update();
    });
    connect(this, &DecorationButton::hoveredChanged, this, [this](bool hovered) {
        m_hoverAnim.stop();
        m_hoverAnim.setStartValue(m_hover);
        m_hoverAnim.setEndValue(hovered ? 1.0 : 0.0);
        m_hoverAnim.start();
    });
    connect(this, &DecorationButton::pressedChanged, this, [this] { update(); });
}

void Button::setGroupHovered(qreal progress)
{
    m_group = progress;
    update();
}

void Button::paint(QPainter *painter, const QRectF &)
{
    if (!isVisible())
        return;
    const auto *win = decoration()->window();
    const bool dark = win->palette().window().color().lightnessF() < 0.5;
    const bool lit = win->isActive() || m_group > 0;
    const DotColors c = dotColors(type());
    const QPointF center = geometry().center();

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);

    // Poświata w kolorze przycisku
    if (m_hover > 0) {
        QColor glow = c.bottom;
        glow.setAlphaF(0.28 * m_hover);
        painter->setBrush(glow);
        const qreal r = 13 * (0.6 + 0.4 * m_hover);
        painter->drawEllipse(center, r, r);
    }

    const qreal r = DotSize / 2 * (isPressed() ? 0.85 : 1 + 0.18 * m_hover);
    const QRectF dot(center.x() - r, center.y() - r, 2 * r, 2 * r);
    if (lit) {
        QLinearGradient g(dot.topLeft(), dot.bottomLeft());
        g.setColorAt(0, c.top);
        g.setColorAt(1, c.bottom);
        painter->setBrush(g);
        painter->setPen(QPen(c.bottom.darker(125), 1));
    } else {
        painter->setBrush(dark ? QColor(255, 255, 255, 20) : QColor(16, 24, 40, 15));
        painter->setPen(QPen(dark ? QColor(0, 0, 0, 51) : QColor(0, 0, 0, 20), 1));
    }
    painter->drawEllipse(dot.adjusted(0.5, 0.5, -0.5, -0.5));

    // Połysk
    if (lit) {
        painter->setPen(Qt::NoPen);
        painter->setBrush(QColor(255, 255, 255, 89));
        painter->drawRoundedRect(QRectF(dot.x() + 3, dot.y() + 1.5, dot.width() - 6, dot.height() * 0.45), r * 0.45, r * 0.45);
    }

    // Znak na kropce
    if (m_group > 0) {
        QColor ink = lit ? QColor(0, 0, 0, 140) : win->palette().windowText().color();
        ink.setAlphaF(ink.alphaF() * m_group);
        QPen pen(ink, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        const qreal s = 3.2;
        switch (type()) {
        case DecorationButtonType::Minimize:
            painter->drawLine(center + QPointF(-s, 0), center + QPointF(s, 0));
            break;
        case DecorationButtonType::Maximize:
            if (win->isMaximized()) {
                const qreal m = s * 0.6;
                painter->drawRoundedRect(QRectF(center.x() - m, center.y() - m, 2 * m, 2 * m), 1, 1);
            } else {
                painter->drawRoundedRect(QRectF(center.x() - s, center.y() - s, 2 * s, 2 * s), 1, 1);
            }
            break;
        default:
            painter->drawLine(center + QPointF(-s, -s), center + QPointF(s, s));
            painter->drawLine(center + QPointF(-s, s), center + QPointF(s, -s));
            break;
        }
    }
    painter->restore();
}

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

bool Decoration::isDark() const
{
    return window()->palette().window().color().lightnessF() < 0.5;
}

bool Decoration::init()
{
    auto *win = window();

    m_groupAnim.setDuration(120);
    connect(&m_groupAnim, &QVariantAnimation::valueChanged, this, [this](const QVariant &v) {
        m_group = v.toReal();
        for (Button *b : std::as_const(m_buttons))
            b->setGroupHovered(m_group);
    });

    for (auto type : {DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close}) {
        auto *b = new Button(type, this);
        m_buttons.append(b);
        connect(b, &DecorationButton::hoveredChanged, this, &Decoration::updateGroupHover);
        connect(b, &DecorationButton::clicked, this, [this, type](Qt::MouseButton button) {
            if (type == DecorationButtonType::Minimize)
                requestMinimize();
            else if (type == DecorationButtonType::Close)
                requestClose();
            else
                requestToggleMaximization(button);
        });
    }

    const auto relayout = [this] { updateLayout(); update(); };
    connect(win, &DecoratedWindow::sizeChanged, this, relayout);
    connect(win, &DecoratedWindow::maximizedChanged, this, relayout);
    connect(win, &DecoratedWindow::minimizeableChanged, this, relayout);
    connect(win, &DecoratedWindow::maximizeableChanged, this, relayout);
    connect(win, &DecoratedWindow::closeableChanged, this, relayout);
    connect(win, &DecoratedWindow::captionChanged, this, [this] { update(); });
    connect(win, &DecoratedWindow::activeChanged, this, [this, relayout] { updateShadow(); relayout(); });
    connect(win, &DecoratedWindow::paletteChanged, this, [this, relayout] { updateShadow(); relayout(); });

    updateLayout();
    updateShadow();
    return true;
}

void Decoration::updateGroupHover()
{
    bool any = false;
    for (const Button *b : std::as_const(m_buttons))
        any = any || b->isHovered();
    m_groupAnim.stop();
    m_groupAnim.setStartValue(m_group);
    m_groupAnim.setEndValue(any ? 1.0 : 0.0);
    m_groupAnim.start();
}

void Decoration::updateShadow()
{
    setShadow(makeShadow(window()->isActive(), isDark()));
}

void Decoration::updateLayout()
{
    const auto *win = window();
    const qreal width = win->width();

    setBorders(QMarginsF(0, TitleHeight, 0, 0));
    setResizeOnlyBorders(win->isMaximized() ? QMarginsF() : QMarginsF(ResizeMargin, 0, ResizeMargin, ResizeMargin));
    setTitleBar(QRectF(0, 0, width, TitleHeight));

    // Rogi zostają także po powiększeniu okna; na pełnym ekranie KWin w ogóle nie rysuje ramki
    setBorderRadius(BorderRadius(CornerRadius));
    // Delikatny rant jak w programach Aster: oddziela okno od tła tego samego koloru
    setBorderOutline(BorderOutline(1, isDark() ? QColor(255, 255, 255, 22) : QColor(16, 24, 40, 28), BorderRadius(CornerRadius)));
    setOpaque(false);

    qreal x = width - SideMargin;
    for (auto it = m_buttons.rbegin(); it != m_buttons.rend(); ++it) {
        Button *b = *it;
        const bool show = (b->type() == DecorationButtonType::Close && win->isCloseable())
            || (b->type() == DecorationButtonType::Maximize && win->isMaximizeable())
            || (b->type() == DecorationButtonType::Minimize && win->isMinimizeable());
        b->setVisible(show);
        if (!show)
            continue;
        x -= ButtonSize;
        b->setGeometry(QRectF(x, (TitleHeight - ButtonSize) / 2, ButtonSize, ButtonSize));
        x -= ButtonSpacing;
    }
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    const auto *win = window();
    const qreal width = win->width();
    const QRectF bar(0, 0, width, TitleHeight);
    const QPalette pal = win->palette();

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);

    // Kolor paska = kolor okna programu, dzięki czemu pasek i treść tworzą jedną całość
    QColor background = pal.window().color();
    if (!win->isActive())
        background = isDark() ? background.lighter(108) : background.darker(102);
    painter->setBrush(background);
    QPainterPath path;
    path.moveTo(0, TitleHeight);
    path.lineTo(0, CornerRadius);
    path.arcTo(QRectF(0, 0, 2 * CornerRadius, 2 * CornerRadius), 180, -90);
    path.lineTo(width - CornerRadius, 0);
    path.arcTo(QRectF(width - 2 * CornerRadius, 0, 2 * CornerRadius, 2 * CornerRadius), 90, -90);
    path.lineTo(width, TitleHeight);
    path.closeSubpath();
    painter->drawPath(path);

    // Tytuł na środku; nie wchodzi na przyciski
    const qreal reserved = 3 * (ButtonSize + ButtonSpacing) + SideMargin + 12;
    if (width > 2 * reserved) {
        QFont font(QStringLiteral("Geist"));
        font.setPixelSize(13);
        font.setWeight(QFont::Medium);
        painter->setFont(font);
        QColor ink = pal.windowText().color();
        ink.setAlphaF(win->isActive() ? 0.92 : 0.5);
        painter->setPen(ink);
        const QRectF titleRect = bar.adjusted(reserved, 0, -reserved, 0);
        painter->drawText(titleRect, Qt::AlignCenter, painter->fontMetrics().elidedText(win->caption(), Qt::ElideRight, int(titleRect.width())));
    }
    painter->restore();

    for (Button *b : std::as_const(m_buttons))
        b->paint(painter, repaintArea);
}

} // namespace Aster

K_PLUGIN_FACTORY_WITH_JSON(AsterDecorationFactory, "aster.json", registerPlugin<Aster::Decoration>();)

#include "decoration.moc"

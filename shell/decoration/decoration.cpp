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
constexpr qreal CornerRadius = 22;
constexpr qreal ButtonSize = 30;
constexpr qreal ButtonSpacing = 2;
constexpr qreal SideMargin = 8;
constexpr qreal ResizeMargin = 6;

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

void Button::paint(QPainter *painter, const QRectF &)
{
    if (!isVisible())
        return;
    const auto *win = decoration()->window();
    const bool closing = type() == DecorationButtonType::Close;
    const QRectF box = geometry().adjusted(1, 1, -1, -1);
    const QPointF center = box.center();

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);

    // Płytka widoczna w aktywnym oknie; po najechaniu ciemnieje, a zamknięcie czerwienieje
    QColor back = win->palette().windowText().color();
    back.setAlphaF(win->isActive() ? 0.07 + 0.07 * m_hover : 0.1 * m_hover);
    if (closing && m_hover > 0) {
        back = QColor(0xD9, 0x3B, 0x40);
        back.setAlphaF(m_hover);
    }
    painter->setBrush(back);
    painter->drawEllipse(box);

    QColor ink = closing && m_hover > 0.5 ? QColor(Qt::white) : win->palette().windowText().color();
    if (!win->isActive() && m_hover == 0)
        ink.setAlphaF(0.5);
    painter->setPen(QPen(ink, 1.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter->setBrush(Qt::NoBrush);
    // Te same znaki co w programach Aster (common/Icons.js), w siatce 24 × 24
    const qreal k = 15.0 / 24.0;
    const auto at = [&](qreal x, qreal y) { return center + QPointF((x - 12) * k, (y - 12) * k); };
    const auto line = [&](std::initializer_list<QPointF> points) {
        QPainterPath path;
        bool first = true;
        for (const QPointF &p : points) {
            if (first)
                path.moveTo(at(p.x(), p.y()));
            else
                path.lineTo(at(p.x(), p.y()));
            first = false;
        }
        painter->drawPath(path);
    };
    if (type() == DecorationButtonType::Minimize) {
        line({{12, 4}, {12, 15}});
        line({{7.5, 10.5}, {12, 15}, {16.5, 10.5}});
        line({{6, 20}, {18, 20}});
    } else if (type() == DecorationButtonType::Maximize && win->isMaximized()) {
        line({{9, 4}, {9, 9}, {4, 9}});
        line({{20, 9}, {15, 9}, {15, 4}});
        line({{15, 20}, {15, 15}, {20, 15}});
        line({{4, 15}, {9, 15}, {9, 20}});
    } else if (type() == DecorationButtonType::Maximize) {
        line({{4, 9}, {4, 4}, {9, 4}});
        line({{15, 4}, {20, 4}, {20, 9}});
        line({{20, 15}, {20, 20}, {15, 20}});
        line({{9, 20}, {4, 20}, {4, 15}});
    } else {
        line({{6, 6}, {18, 18}});
        line({{18, 6}, {6, 18}});
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

    for (auto type : {DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close}) {
        auto *b = new Button(type, this);
        m_buttons.append(b);
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
        QFont font(QStringLiteral("Outfit"));
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

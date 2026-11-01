#include "terminalview.h"

#include <QClipboard>
#include <QCursor>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QMimeData>
#include <QPainter>
#include <QPainterPath>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QStyleHints>
#include <QUrl>
#include <QtMath>

#include <climits>

using namespace Term;

namespace {

// Domyślna paleta (Aster, ciemny) — QML i tak ustawia swoją
const QVector<QRgb> defaultPalette = {
    0xFF1C1E26, 0xFFFF6B7A, 0xFF7EE0A0, 0xFFF5D07A, 0xFF6EA8FF, 0xFFC79BFF, 0xFF67E1E6, 0xFFC9CED8,
    0xFF5C6370, 0xFFFF8B96, 0xFF9BF0B8, 0xFFFFE09A, 0xFF8DBBFF, 0xFFD8B4FF, 0xFF8EEBEE, 0xFFF4F6FA};

const QRegularExpression &linkPattern()
{
    static const QRegularExpression re(QStringLiteral("(?:(?:https?|ftp|file)://|www\\.)[^\\s<>\"'`]+"));
    return re;
}

// Linie ramek: grubość ramion góra/prawo/dół/lewo (1 cienka, 2 gruba, 3 podwójna)
constexpr quint8 arms(int up, int right, int down, int left)
{
    return quint8(up | (right << 2) | (down << 4) | (left << 6));
}

const QHash<char32_t, quint8> &boxTable()
{
    static const QHash<char32_t, quint8> t = {
        {0x2500, arms(0, 1, 0, 1)}, {0x2502, arms(1, 0, 1, 0)}, {0x250C, arms(0, 1, 1, 0)}, {0x2510, arms(0, 0, 1, 1)},
        {0x2514, arms(1, 1, 0, 0)}, {0x2518, arms(1, 0, 0, 1)}, {0x251C, arms(1, 1, 1, 0)}, {0x2524, arms(1, 0, 1, 1)},
        {0x252C, arms(0, 1, 1, 1)}, {0x2534, arms(1, 1, 0, 1)}, {0x253C, arms(1, 1, 1, 1)},
        {0x2501, arms(0, 2, 0, 2)}, {0x2503, arms(2, 0, 2, 0)}, {0x250F, arms(0, 2, 2, 0)}, {0x2513, arms(0, 0, 2, 2)},
        {0x2517, arms(2, 2, 0, 0)}, {0x251B, arms(2, 0, 0, 2)}, {0x2523, arms(2, 2, 2, 0)}, {0x252B, arms(2, 0, 2, 2)},
        {0x2533, arms(0, 2, 2, 2)}, {0x253B, arms(2, 2, 0, 2)}, {0x254B, arms(2, 2, 2, 2)},
        {0x2550, arms(0, 3, 0, 3)}, {0x2551, arms(3, 0, 3, 0)}, {0x2554, arms(0, 3, 3, 0)}, {0x2557, arms(0, 0, 3, 3)},
        {0x255A, arms(3, 3, 0, 0)}, {0x255D, arms(3, 0, 0, 3)}, {0x2560, arms(3, 3, 3, 0)}, {0x2563, arms(3, 0, 3, 3)},
        {0x2566, arms(0, 3, 3, 3)}, {0x2569, arms(3, 3, 0, 3)}, {0x256C, arms(3, 3, 3, 3)},
        {0x2574, arms(0, 0, 0, 1)}, {0x2575, arms(1, 0, 0, 0)}, {0x2576, arms(0, 1, 0, 0)}, {0x2577, arms(0, 0, 1, 0)},
        {0x2578, arms(0, 0, 0, 2)}, {0x2579, arms(2, 0, 0, 0)}, {0x257A, arms(0, 2, 0, 0)}, {0x257B, arms(0, 0, 2, 0)},
    };
    return t;
}

QString shellQuote(const QString &s)
{
    static const QRegularExpression safe(QStringLiteral("^[A-Za-z0-9_@%+=:,./-]+$"));
    if (safe.match(s).hasMatch())
        return s;
    QString q = s;
    q.replace(QLatin1Char('\''), QLatin1String("'\\''"));
    return QLatin1Char('\'') + q + QLatin1Char('\'');
}

bool isWordChar(char32_t c)
{
    if (c == 0 || c == ' ')
        return false;
    if (QChar::isLetterOrNumber(c))
        return true;
    return QStringView(u"-_./~+@%:=?&#").contains(QChar(c));
}

} // namespace

TerminalView::TerminalView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_palette16(defaultPalette)
{
    setFlag(ItemAcceptsInputMethod);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    setFillColor(Qt::transparent);
    setOpaquePainting(false);
    setAntialiasing(true);
    setCursor(Qt::IBeamCursor);

    m_blink.setInterval(560);
    connect(&m_blink, &QTimer::timeout, this, [this] {
        m_blinkOn = !m_blinkOn;
        update();
    });
    m_autoScroll.setInterval(40);
    connect(&m_autoScroll, &QTimer::timeout, this, [this] {
        scrollBy(m_autoScrollDir < 0 ? 1 : -1);
        extendSelection(posAt(m_lastMouse, m_selMode == 1));
    });
    m_searchTimer.setSingleShot(true);
    m_searchTimer.setInterval(150);
    connect(&m_searchTimer, &QTimer::timeout, this, [this] { runSearch(true); });

    m_session = new TerminalSession(this);
    attachSession();
    updateMetrics();
}

TerminalView::~TerminalView() = default;

void TerminalView::attachSession()
{
    TerminalSession *s = m_session;
    connect(s, &TerminalSession::contentChanged, this, &TerminalView::onContent);
    connect(s, &TerminalSession::historyPushed, this, [this](int n) {
        if (m_scroll > 0)
            m_scroll = qMin(m_scroll + n, m_session->historyCount());
        emit scrollChanged();
    });
    connect(s, &TerminalSession::historyCleared, this, [this] {
        m_scroll = 0;
        m_selActive = false;
        m_matches.clear();
        m_matchIndex = -1;
        emit scrollChanged();
        emit selectionChanged();
        emit searchChanged();
    });
    connect(s, &TerminalSession::cursorChanged, this, [this] { update(); });
    connect(s, &TerminalSession::modesChanged, this, [this] {
        setCursor(m_session->mouseMode() ? Qt::ArrowCursor : Qt::IBeamCursor);
        emit modesChanged();
    });
    connect(s, &TerminalSession::titleChanged, this, &TerminalView::appTitleChanged);
    connect(s, &TerminalSession::bell, this, &TerminalView::bell);
    connect(s, &TerminalSession::directoryChanged, this, &TerminalView::currentDirectoryChanged);
    connect(s, &TerminalSession::programChanged, this, &TerminalView::programChanged);
    connect(s, &TerminalSession::clipboardRequested, this, [](const QString &text) {
        QGuiApplication::clipboard()->setText(text);
    });
    connect(s, &TerminalSession::finished, this, [this](int code) {
        m_blink.stop();
        update();
        emit runningChanged();
        emit finished(code);
    });
}

// ——— Uruchomienie i rozmiar ———

void TerminalView::componentComplete()
{
    QQuickPaintedItem::componentComplete();
    m_complete = true;
    updateSize();
}

void TerminalView::start()
{
    if (m_started || width() < 1 || height() < 1)
        return;
    m_started = true;
    m_session->setHistoryLimit(m_historyLimit);
    applyPalette();
    const int cols = qMax(2, int(width() / m_cw));
    const int rows = qMax(2, int(height() / m_ch));
    m_session->start(rows, cols, m_startDir, m_command);
    emit sizeChanged();
    emit runningChanged();
    emit currentDirectoryChanged();
    if (!m_session->running())
        emit finished(127);
    resetBlink();
}

// Nowa sesja w tym samym miejscu (po zakończeniu programu)
void TerminalView::restart()
{
    const QString dir = m_session->currentDirectory();
    m_session->disconnect(this);
    m_session->deleteLater();
    m_session = new TerminalSession(this);
    attachSession();
    if (!dir.isEmpty())
        m_startDir = dir;
    m_started = false;
    m_scroll = 0;
    m_selActive = false;
    endSearch();
    emit scrollChanged();
    emit selectionChanged();
    emit modesChanged();
    start();
    update();
}

void TerminalView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        updateSize();
}

void TerminalView::updateSize()
{
    if (!m_complete || width() < 1 || height() < 1)
        return;
    if (!m_started) {
        start();
        return;
    }
    const int cols = qMax(2, int(width() / m_cw));
    const int rows = qMax(2, int(height() / m_ch));
    if (cols == m_session->cols() && rows == m_session->rows())
        return;
    m_session->resize(rows, cols);
    m_scroll = qMin(m_scroll, m_session->historyCount());
    emit sizeChanged();
    emit scrollChanged();
    update();
}

void TerminalView::updateMetrics()
{
    m_font = QFont(m_family.isEmpty() ? QStringLiteral("monospace") : m_family);
    m_font.setStyleHint(QFont::Monospace, QFont::PreferDefault);
    m_font.setFixedPitch(true);
    m_font.setKerning(false);
    m_font.setPixelSize(qMax(6, qRound(m_size)));
    // Bez ligatur: w terminalu „!=” ma zostać dwoma znakami
    m_font.setFeature(QFont::Tag("calt"), 0);
    m_font.setFeature(QFont::Tag("liga"), 0);
    m_bold = m_font;
    m_bold.setWeight(QFont::Bold);
    m_italic = m_font;
    m_italic.setItalic(true);
    m_boldItalic = m_bold;
    m_boldItalic.setItalic(true);

    const QFontMetricsF fm(m_font);
    m_cw = fm.horizontalAdvance(QLatin1Char('M'));
    const qreal natural = fm.ascent() + fm.descent();
    m_ch = qCeil(natural * m_lineHeight);
    m_textTop = qFloor((m_ch - natural) / 2);
    m_ascent = fm.ascent();
    m_underlinePos = qMax(1.0, fm.underlinePos());
    m_strikePos = fm.strikeOutPos();
    m_lineWidth = qMax(1.0, qRound(fm.lineWidth() * 1.0) * 1.0);
    m_inFont.clear();
    m_inBold.clear();
    emit fontChanged();
    updateSize();
    update();
}

void TerminalView::setFontFamily(const QString &f)
{
    if (f == m_family)
        return;
    m_family = f;
    updateMetrics();
}

void TerminalView::setFontSize(qreal s)
{
    if (qFuzzyCompare(s, m_size))
        return;
    m_size = s;
    updateMetrics();
}

void TerminalView::setLineHeight(qreal h)
{
    if (qFuzzyCompare(h, m_lineHeight))
        return;
    m_lineHeight = qBound(0.9, h, 2.0);
    updateMetrics();
}

// ——— Kolory ———

void TerminalView::setForeground(const QColor &c)
{
    if (c == m_fg)
        return;
    m_fg = c;
    applyPalette();
    emit colorsChanged();
}

void TerminalView::setBackground(const QColor &c)
{
    if (c == m_bg)
        return;
    m_bg = c;
    applyPalette();
    emit colorsChanged();
}

QVariantList TerminalView::colorPalette() const
{
    QVariantList l;
    for (QRgb c : m_palette16)
        l << QColor::fromRgb(c);
    return l;
}

void TerminalView::setColorPalette(const QVariantList &list)
{
    QVector<QRgb> p = defaultPalette;
    for (int i = 0; i < 16 && i < list.size(); ++i)
        p[i] = list[i].value<QColor>().rgb();
    if (p == m_palette16)
        return;
    m_palette16 = p;
    applyPalette();
    emit colorsChanged();
}

void TerminalView::applyPalette()
{
    QColor bg = m_bg;
    bg.setAlpha(255);
    m_session->setPalette(m_palette16, m_fg.rgb(), bg.rgb());
    update();
}

QRgb TerminalView::resolve(quint32 color, bool fg) const
{
    switch (color & ColorTypeMask) {
    case ColorIndexed:
        return m_session->paletteColor(int(color & 0xFF)) | 0xFF000000;
    case ColorRgb:
        return 0xFF000000 | (color & 0xFFFFFF);
    default:
        return fg ? m_fg.rgba() : 0;      // przezroczyste tło: widać panel okna
    }
}

void TerminalView::setCursorBlinking(bool on)
{
    if (on == m_blinking)
        return;
    m_blinking = on;
    resetBlink();
    emit cursorStyleChanged();
}

void TerminalView::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickPaintedItem::itemChange(change, value);
    // Kursor w oknie w tle jest pustym obrysem i nie miga
    if (change == ItemSceneChange && value.window)
        connect(value.window, &QWindow::activeChanged, this, &TerminalView::resetBlink, Qt::UniqueConnection);
}

void TerminalView::resetBlink()
{
    m_blinkOn = true;
    if (m_blinking && hasActiveFocus() && window() && window()->isActive() && m_session->running())
        m_blink.start();
    else
        m_blink.stop();
    update();
}

void TerminalView::setHistoryLimit(int lines)
{
    if (lines == m_historyLimit)
        return;
    m_historyLimit = lines;
    m_session->setHistoryLimit(lines);
    m_scroll = qMin(m_scroll, m_session->historyCount());
    emit historyLimitChanged();
    emit scrollChanged();
}

// ——— Rysowanie ———

qint64 TerminalView::topLine() const
{
    return m_session->endAbsolute() - m_session->rows() - m_scroll;
}

bool TerminalView::inFont(char32_t ch, bool bold)
{
    QHash<char32_t, bool> &cache = bold ? m_inBold : m_inFont;
    auto it = cache.constFind(ch);
    if (it != cache.cend())
        return *it;
    const bool in = QFontMetricsF(bold ? m_bold : m_font).inFontUcs4(ch);
    cache.insert(ch, in);
    return in;
}

// Ramki i bloki rysowane geometrycznie — łączą się idealnie między komórkami przy każdej wysokości linii
bool TerminalView::drawBox(QPainter *p, char32_t ch, const QRect &r, const QColor &color) const
{
    const int x = r.x(), y = r.y(), w = r.width(), h = r.height();

    // Bloki ▀▄█▌▐ i ćwiartki
    if (ch >= 0x2580 && ch <= 0x259F) {
        auto fill = [&](qreal x0, qreal y0, qreal x1, qreal y1) {
            p->fillRect(QRect(x + qRound(w * x0), y + qRound(h * y0), qRound(w * x1) - qRound(w * x0), qRound(h * y1) - qRound(h * y0)), color);
        };
        if (ch == 0x2580) fill(0, 0, 1, 0.5);
        else if (ch >= 0x2581 && ch <= 0x2588) fill(0, 1 - (ch - 0x2580) / 8.0, 1, 1);
        else if (ch >= 0x2589 && ch <= 0x258F) fill(0, 0, (0x2590 - ch) / 8.0, 1);
        else if (ch == 0x2590) fill(0.5, 0, 1, 1);
        else if (ch >= 0x2591 && ch <= 0x2593) {
            QColor c = color;
            c.setAlphaF(color.alphaF() * (ch - 0x2590) / 4.0);
            p->fillRect(r, c);
        } else if (ch == 0x2594) fill(0, 0, 1, 1 / 8.0);
        else if (ch == 0x2595) fill(7 / 8.0, 0, 1, 1);
        else {
            static const quint8 quads[] = {4, 8, 1, 1 | 4 | 8, 1 | 8, 1 | 2 | 4, 1 | 2 | 8, 2, 2 | 4, 2 | 4 | 8};
            const quint8 q = quads[ch - 0x2596];
            if (q & 1) fill(0, 0, 0.5, 0.5);
            if (q & 2) fill(0.5, 0, 1, 0.5);
            if (q & 4) fill(0, 0.5, 0.5, 1);
            if (q & 8) fill(0.5, 0.5, 1, 1);
        }
        return true;
    }

    const int light = qMax(1, qRound(m_ch / 18.0));
    const int heavy = qMax(light + 1, light * 2);

    // Zaokrąglone narożniki ╭╮╯╰
    if (ch >= 0x256D && ch <= 0x2570) {
        const qreal cx = x + (w - light) / 2 + light / 2.0, cy = y + (h - light) / 2 + light / 2.0;
        const qreal rad = qMin(w, h) / 2.0;
        QPainterPath path;
        const bool up = ch == 0x256F || ch == 0x2570, right = ch == 0x256D || ch == 0x2570;
        const qreal ex = right ? x + w : x, ey = up ? y : y + h;
        path.moveTo(ex, cy);
        path.lineTo(right ? cx + rad : cx - rad, cy);
        path.quadTo(cx, cy, cx, up ? cy - rad : cy + rad);
        path.lineTo(cx, ey);
        p->save();
        p->setRenderHint(QPainter::Antialiasing);
        p->setPen(QPen(color, light, Qt::SolidLine, Qt::FlatCap));
        p->setBrush(Qt::NoBrush);
        p->drawPath(path);
        p->restore();
        return true;
    }

    const auto it = boxTable().constFind(ch);
    if (it == boxTable().cend())
        return false;
    const int a[4] = {*it & 3, (*it >> 2) & 3, (*it >> 4) & 3, (*it >> 6) & 3};   // góra, prawo, dół, lewo
    const auto thick = [&](int weight) { return weight == 2 ? heavy : light; };

    if (a[0] == 3 || a[1] == 3 || a[2] == 3 || a[3] == 3) {
        // Podwójne linie: dwie równoległe kreski; w narożnikach i skrzyżowaniach rozchodzą się jak w piśmie
        const int g = qMax(light + 1, qRound(w / 5.0));
        const int cx = x + w / 2, cy = y + h / 2;
        const bool up = a[0], right = a[1], down = a[2], left = a[3];
        auto hline = [&](int x0, int x1, int yy) { p->fillRect(QRect(qMin(x0, x1), yy - light / 2, qAbs(x1 - x0) + light, light), color); };
        auto vline = [&](int y0, int y1, int xx) { p->fillRect(QRect(xx - light / 2, qMin(y0, y1), light, qAbs(y1 - y0) + light), color); };
        if (right) {
            hline(up ? cx + g : cx - g, x + w, cy - g);
            hline(down ? cx + g : cx - g, x + w, cy + g);
        }
        if (left) {
            hline(x, up ? cx - g : cx + g, cy - g);
            hline(x, down ? cx - g : cx + g, cy + g);
        }
        if (down) {
            vline(left ? cy + g : cy - g, y + h, cx - g);
            vline(right ? cy + g : cy - g, y + h, cx + g);
        }
        if (up) {
            vline(y, left ? cy - g : cy + g, cx - g);
            vline(y, right ? cy - g : cy + g, cx + g);
        }
        if (!left && !right) {
            if (up && !down) { vline(y, cy, cx - g); vline(y, cy, cx + g); }
            if (down && !up) { vline(cy, y + h, cx - g); vline(cy, y + h, cx + g); }
        }
        return true;
    }

    const int tv = qMax(thick(a[0]) * (a[0] > 0), thick(a[2]) * (a[2] > 0));    // grubość pionu
    const int th = qMax(thick(a[1]) * (a[1] > 0), thick(a[3]) * (a[3] > 0));    // grubość poziomu
    const auto vx = [&](int t) { return x + (w - t) / 2; };
    const auto hy = [&](int t) { return y + (h - t) / 2; };
    const int cyEnd = th ? hy(th) + th : y + h / 2;
    const int cxEnd = tv ? vx(tv) + tv : x + w / 2;
    if (a[0]) p->fillRect(QRect(vx(thick(a[0])), y, thick(a[0]), cyEnd - y), color);
    if (a[2]) p->fillRect(QRect(vx(thick(a[2])), th ? hy(th) : y + h / 2, thick(a[2]), y + h - (th ? hy(th) : y + h / 2)), color);
    if (a[3]) p->fillRect(QRect(x, hy(thick(a[3])), cxEnd - x, thick(a[3])), color);
    if (a[1]) p->fillRect(QRect(tv ? vx(tv) : x + w / 2, hy(thick(a[1])), x + w - (tv ? vx(tv) : x + w / 2), thick(a[1])), color);
    return true;
}

void TerminalView::paint(QPainter *p)
{
    p->setRenderHint(QPainter::TextAntialiasing);
    const int rows = m_session->rows(), cols = m_session->cols();
    const qint64 top = topLine();
    const bool globalReverse = m_session->reverseVideo();
    const QRgb bgSolid = (m_bg.rgb() | 0xFF000000);
    const QRgb currentMatchText = qGray(m_matchColor.rgb()) > 140 ? 0xFF16181D : 0xFFFFFFFF;

    // Kursor
    const qint64 cursorLine = m_session->endAbsolute() - rows + m_session->cursorRow();
    const int cursorCol = qMin(m_session->cursorCol(), cols - 1);
    const int shape = m_session->cursorShape() ? m_session->cursorShape() : m_cursorStyle;
    const bool focused = hasActiveFocus() && window() && window()->isActive();
    const bool cursorShown = m_session->running() && m_session->cursorVisible() && (!focused || !m_blinking || m_blinkOn);
    const QRgb cursorRgb = m_cursorColor.rgba();
    const QRgb cursorText = qGray(m_cursorColor.rgb()) > 140 ? 0xFF101114 : 0xFFFFFFFF;

    QVarLengthArray<QRgb, 512> fgs(cols), bgs(cols);
    QVarLengthArray<quint8, 512> marks(cols);       // 1 — zaznaczenie, 2 — wynik wyszukiwania, 3 — bieżący wynik

    for (int y = 0; y < rows; ++y) {
        const qint64 ln = top + y;
        const Line line = m_session->line(ln);
        const int yPx = qRound(y * m_ch);
        const int hPx = qRound((y + 1) * m_ch) - yPx;
        const auto colX = [&](int c) { return qRound(c * m_cw); };

        // Kolory komórek
        for (int x = 0; x < cols; ++x) {
            const Cell c = x < line.cells.size() ? line.cells[x] : Cell{};
            QRgb fg = resolve(c.fg, true), bg = resolve(c.bg, false);
            if (((c.flags & Reverse) != 0) != globalReverse) {
                const QRgb f = qAlpha(bg) ? bg : bgSolid;
                bg = fg;
                fg = f;
            }
            if (c.flags & Conceal)
                fg = qAlpha(bg) ? bg : bgSolid;
            fgs[x] = fg;
            bgs[x] = bg;
            marks[x] = selected(ln, x) ? 1 : 0;
        }
        for (int i = 0; i < int(m_matches.size()); ++i) {
            const Match &m = m_matches[size_t(i)];
            if (m.line != ln)
                continue;
            for (int x = qMax(0, m.start); x < qMin(cols, m.end); ++x)
                if (!marks[x] || i == m_matchIndex)
                    marks[x] = i == m_matchIndex ? 3 : 2;
        }

        // Tła — łączone w odcinki
        for (int x = 0; x < cols;) {
            const QRgb bg = bgs[x];
            int e = x + 1;
            while (e < cols && bgs[e] == bg)
                ++e;
            if (qAlpha(bg))
                p->fillRect(QRect(colX(x), yPx, colX(e) - colX(x), hPx), QColor::fromRgba(bg));
            x = e;
        }
        for (int x = 0; x < cols;) {
            const quint8 m = marks[x];
            int e = x + 1;
            while (e < cols && marks[e] == m)
                ++e;
            if (m) {
                QColor c = m == 1 ? m_selectionColor : m_matchColor;
                if (m == 2)
                    c.setAlphaF(0.38);
                p->fillRect(QRect(colX(x), yPx, colX(e) - colX(x), hPx), c);
            }
            x = e;
        }
        const bool cursorHere = cursorShown && ln == cursorLine;
        const bool cursorBlock = cursorHere && focused && shape <= 1;
        if (cursorBlock) {
            const int cw = cursorCol + 1 < line.cells.size() && line.cells[cursorCol].width == 2 ? 2 : 1;
            p->fillRect(QRect(colX(cursorCol), yPx, colX(cursorCol + cw) - colX(cursorCol), hPx), QColor::fromRgba(cursorRgb));
        }

        // Tekst — odcinki w jednym kolorze i kroju; znaki spoza czcionki i szerokie osobno
        const qreal baseline = yPx + m_textTop + m_ascent;
        QString run;
        int runStart = -1;
        QRgb runColor = 0;
        int runStyle = 0;
        const auto flush = [&] {
            if (run.isEmpty())
                return;
            p->setFont(runStyle == 3 ? m_boldItalic : runStyle == 2 ? m_italic : runStyle == 1 ? m_bold : m_font);
            p->setPen(QColor::fromRgba(runColor));
            p->drawText(QPointF(runStart * m_cw, baseline), run);
            run.clear();
            runStart = -1;
        };
        for (int x = 0; x < cols && x < line.cells.size(); ++x) {
            const Cell &c = line.cells[x];
            if (c.width == 0)
                continue;
            QRgb fg = fgs[x];
            if (marks[x] == 3)
                fg = currentMatchText;
            if (cursorBlock && x == cursorCol)
                fg = cursorText;
            const char32_t ch = c.ch;
            if (ch == 0 || ch == ' ') {
                flush();
                continue;
            }
            const QRect cell(colX(x), yPx, colX(x + qMax(1, int(c.width))) - colX(x), hPx);
            if (ch >= 0x2500 && ch <= 0x259F && drawBox(p, ch, cell, QColor::fromRgba(fg))) {
                flush();
                continue;
            }
            const int style = ((c.flags & Bold) ? 1 : 0) | ((c.flags & Italic) ? 2 : 0);
            if (c.width > 1 || !inFont(ch, style & 1)) {
                flush();
                p->setFont(style == 3 ? m_boldItalic : style == 2 ? m_italic : style == 1 ? m_bold : m_font);
                p->setPen(QColor::fromRgba(fg));
                p->drawText(QRectF(x * m_cw, yPx, m_cw * qMax(1, int(c.width)), hPx), Qt::AlignCenter | Qt::TextDontClip,
                            QString::fromUcs4(&ch, 1));
                continue;
            }
            if (runStart >= 0 && (fg != runColor || style != runStyle || runStart + run.size() != x))
                flush();
            if (runStart < 0) {
                runStart = x;
                runColor = fg;
                runStyle = style;
            }
            // Znak spoza BMP (para zastępcza) zajmuje dwa miejsca w QString — przerywa odcinek
            if (ch > 0xFFFF) {
                flush();
                p->setFont(style == 1 ? m_bold : m_font);
                p->setPen(QColor::fromRgba(fg));
                p->drawText(QPointF(x * m_cw, baseline), QString::fromUcs4(&ch, 1));
                continue;
            }
            run += QChar(ch);
        }
        flush();

        // Podkreślenia, przekreślenia, link pod kursorem myszy
        for (int x = 0; x < cols && x < line.cells.size(); ++x) {
            const Cell &c = line.cells[x];
            const bool link = ln == m_linkLine && x >= m_linkStart && x < m_linkEnd;
            if (!(c.flags & (Underline | DoubleUnderline | CurlyUnderline | Strike)) && !link)
                continue;
            const QColor col = QColor::fromRgba(cursorBlock && x == cursorCol ? cursorText : fgs[x]);
            const int x0 = colX(x), x1 = colX(x + 1);
            const int uy = qMin(yPx + hPx - int(m_lineWidth), qRound(baseline + m_underlinePos));
            if ((c.flags & Underline) || link)
                p->fillRect(QRect(x0, uy, x1 - x0, int(m_lineWidth)), col);
            if (c.flags & DoubleUnderline) {
                p->fillRect(QRect(x0, uy - 1, x1 - x0, int(m_lineWidth)), col);
                p->fillRect(QRect(x0, qMin(yPx + hPx - 1, uy + 2), x1 - x0, int(m_lineWidth)), col);
            }
            if (c.flags & CurlyUnderline) {
                QPainterPath wave;
                wave.moveTo(x0, uy);
                wave.cubicTo(x0 + (x1 - x0) * 0.25, uy - 2, x0 + (x1 - x0) * 0.25, uy - 2, x0 + (x1 - x0) * 0.5, uy);
                wave.cubicTo(x0 + (x1 - x0) * 0.75, uy + 2, x0 + (x1 - x0) * 0.75, uy + 2, x1, uy);
                p->save();
                p->setRenderHint(QPainter::Antialiasing);
                p->setPen(QPen(col, m_lineWidth));
                p->drawPath(wave);
                p->restore();
            }
            if (c.flags & Strike)
                p->fillRect(QRect(x0, qRound(baseline - m_strikePos), x1 - x0, int(m_lineWidth)), col);
        }

        // Kursor: kreska, podkreślenie albo obrys (okno bez fokusu)
        if (cursorHere && !cursorBlock) {
            const int x0 = colX(cursorCol), x1 = colX(cursorCol + 1);
            const QColor cc = QColor::fromRgba(cursorRgb);
            const int t = qMax(2, qRound(m_ch / 9.0));
            if (!focused) {
                p->save();
                p->setPen(QPen(cc, 1));
                p->setBrush(Qt::NoBrush);
                p->drawRect(QRectF(x0 + 0.5, yPx + 0.5, x1 - x0 - 1, hPx - 1));
                p->restore();
            } else if (shape == 2) {
                p->fillRect(QRect(x0, yPx + hPx - t, x1 - x0, t), cc);
            } else {
                p->fillRect(QRect(x0, yPx, t, hPx), cc);
            }
        }
    }
}

// ——— Pozycje i tekst ———

TerminalView::Pos TerminalView::posAt(QPointF p, bool boundary) const
{
    const int rows = m_session->rows(), cols = m_session->cols();
    const int row = qBound(0, int(qFloor(p.y() / m_ch)), rows - 1);
    int col = boundary ? qRound(p.x() / m_cw) : int(qFloor(p.x() / m_cw));
    col = qBound(0, col, boundary ? cols : cols - 1);
    if (p.y() < 0 && boundary)
        col = 0;
    else if (p.y() >= height() && boundary)
        col = cols;
    return {topLine() + row, col};
}

QString TerminalView::rowText(qint64 ln, QVector<int> *cols) const
{
    const Line l = m_session->line(ln);
    QString s;
    s.reserve(l.cells.size());
    if (cols) {
        cols->clear();
        cols->reserve(l.cells.size());
    }
    for (int x = 0; x < l.cells.size(); ++x) {
        const Cell &c = l.cells[x];
        if (c.width == 0)
            continue;
        const QString piece = c.ch ? QString::fromUcs4(&c.ch, 1) : QStringLiteral(" ");
        s += piece;
        if (cols)
            for (int k = 0; k < piece.size(); ++k)
                cols->append(x);
    }
    return s;
}

bool TerminalView::selected(qint64 line, int col) const
{
    if (!m_selActive)
        return false;
    const Pos p{line, col};
    return !(p < m_selStart) && p < m_selEnd;
}

void TerminalView::setSelection(Pos a, Pos b)
{
    if (b < a)
        std::swap(a, b);
    const bool was = hasSelection();
    m_selStart = a;
    m_selEnd = b;
    m_selActive = a != b;
    if (was != hasSelection())
        emit selectionChanged();
    update();
}

TerminalView::Pos TerminalView::wordStart(Pos p) const
{
    const Line l = m_session->line(p.line);
    if (p.col >= l.cells.size() || !isWordChar(l.cells[p.col].ch))
        return p;
    int c = p.col;
    while (c > 0 && (l.cells[c - 1].width == 0 || isWordChar(l.cells[c - 1].ch)))
        --c;
    return {p.line, c};
}

TerminalView::Pos TerminalView::wordEnd(Pos p) const
{
    const Line l = m_session->line(p.line);
    if (p.col >= l.cells.size() || !isWordChar(l.cells[p.col].ch))
        return {p.line, p.col + 1};
    int c = p.col;
    while (c + 1 < l.cells.size() && (l.cells[c + 1].width == 0 || isWordChar(l.cells[c + 1].ch)))
        ++c;
    // Kropka, dwukropek i znak zapytania na końcu zdania nie należą do słowa
    while (c > p.col && QStringView(u".:?,").contains(QChar(l.cells[c].ch)))
        --c;
    return {p.line, c + 1};
}

void TerminalView::extendSelection(Pos p)
{
    if (m_selMode == 1) {
        setSelection(m_anchor, p);
    } else if (m_selMode == 2) {
        const Pos s = wordStart(p), e = wordEnd(p);
        if (p < m_anchor)
            setSelection(s, m_anchorEnd);
        else
            setSelection(m_anchor, std::max(e, m_anchorEnd));
    } else {
        qint64 a = qMin(m_anchor.line, p.line), b = qMax(m_anchorEnd.line - 1, p.line);
        while (a > m_session->firstAbsolute() && m_session->line(a - 1).wrapped)
            --a;
        while (b + 1 < m_session->endAbsolute() && m_session->line(b).wrapped)
            ++b;
        setSelection({a, 0}, {b + 1, 0});
    }
}

QString TerminalView::selectedText() const
{
    if (!hasSelection())
        return {};
    QString out;
    const qint64 last = qMin(m_selEnd.col == 0 ? m_selEnd.line - 1 : m_selEnd.line, m_session->endAbsolute() - 1);
    for (qint64 ln = m_selStart.line; ln <= last; ++ln) {
        const Line l = m_session->line(ln);
        const int from = ln == m_selStart.line ? m_selStart.col : 0;
        const int to = ln == m_selEnd.line ? m_selEnd.col : INT_MAX;
        QString s;
        for (int x = from; x < l.cells.size() && x < to; ++x) {
            const Cell &c = l.cells[x];
            if (c.width == 0)
                continue;
            s += c.ch ? QString::fromUcs4(&c.ch, 1) : QStringLiteral(" ");
        }
        // Linia zawinięta przez terminal łączy się z następną bez znaku nowej linii
        const bool continues = l.wrapped && to >= l.cells.size();
        if (!continues)
            while (s.endsWith(QLatin1Char(' ')))
                s.chop(1);
        out += s;
        if (ln < last && !continues)
            out += QLatin1Char('\n');
    }
    return out;
}

void TerminalView::finishSelection()
{
    if (!hasSelection())
        return;
    QClipboard *cb = QGuiApplication::clipboard();
    const QString text = selectedText();
    if (cb->supportsSelection())
        cb->setText(text, QClipboard::Selection);
    if (m_copyOnSelect) {
        cb->setText(text);
        emit copied();
    }
}

void TerminalView::clearSelection()
{
    if (!m_selActive)
        return;
    m_selActive = false;
    emit selectionChanged();
    update();
}

void TerminalView::selectAll()
{
    m_selMode = 1;
    setSelection({m_session->firstAbsolute(), 0}, {m_session->endAbsolute() - 1, m_session->cols()});
    finishSelection();
}

// ——— Schowek ———

void TerminalView::copy()
{
    if (!hasSelection())
        return;
    QGuiApplication::clipboard()->setText(selectedText());
    emit copied();
}

void TerminalView::paste()
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime)
        return;
    QString text;
    // Pliki skopiowane w Plikach wklejają się jako ścieżki (w cudzysłowach, gdy trzeba)
    if (mime->hasUrls() && !mime->urls().isEmpty() && mime->urls().first().isLocalFile()) {
        QStringList paths;
        for (const QUrl &u : mime->urls())
            if (u.isLocalFile())
                paths << shellQuote(u.toLocalFile());
        text = paths.join(QLatin1Char(' '));
    } else {
        text = mime->text();
    }
    if (text.isEmpty())
        return;
    scrollToBottom();
    clearSelection();
    m_session->paste(text);
}

void TerminalView::pasteSelection()
{
    const QString text = QGuiApplication::clipboard()->text(QClipboard::Selection);
    if (text.isEmpty())
        return;
    scrollToBottom();
    m_session->paste(text);
}

void TerminalView::sendText(const QString &text)
{
    scrollToBottom();
    m_session->sendText(text);
}

void TerminalView::clear()
{
    m_session->clearHistory();
    if (m_session->foregroundProgram().isEmpty() && !m_session->altScreen())
        m_session->write("\x0c");       // Ctrl+L: powłoka czyści ekran i rysuje znak zachęty na górze
    else
        vterm_input_write(m_session->vt(), "\x1b[H\x1b[2J", 7);
    update();
}

QString TerminalView::historyText() const
{
    QString out;
    for (qint64 ln = m_session->firstAbsolute(); ln < m_session->endAbsolute(); ++ln) {
        QString t = rowText(ln);
        while (t.endsWith(QLatin1Char(' ')))
            t.chop(1);
        out += t;
        if (!m_session->line(ln).wrapped)
            out += QLatin1Char('\n');
    }
    return out.trimmed() + QLatin1Char('\n');
}

// ——— Przewijanie ———

void TerminalView::scrollTo(int linesFromBottom)
{
    const int v = qBound(0, linesFromBottom, m_session->historyCount());
    if (v == m_scroll)
        return;
    m_scroll = v;
    emit scrollChanged();
    update();
}

void TerminalView::scrollBy(int lines)
{
    scrollTo(m_scroll + lines);
}

void TerminalView::onContent()
{
    update();
    emit activity();
    if (!m_query.isEmpty())
        m_searchTimer.start();
}

// ——— Linki ———

QString TerminalView::linkAtPos(Pos c, int *start, int *end) const
{
    QVector<int> cols;
    const QString text = rowText(c.line, &cols);
    auto it = linkPattern().globalMatch(text);
    while (it.hasNext()) {
        const auto m = it.next();
        QString url = m.captured();
        // Interpunkcja na końcu zdania nie jest częścią adresu
        while (!url.isEmpty() && QStringView(u".,;:!?'\")]}>").contains(url.back())) {
            if (url.back() == QLatin1Char(')') && url.count(QLatin1Char('(')) >= url.count(QLatin1Char(')')))
                break;
            url.chop(1);
        }
        if (url.isEmpty())
            continue;
        const int s = cols.value(int(m.capturedStart())), e = cols.value(int(m.capturedStart() + url.size() - 1)) + 1;
        if (c.col >= s && c.col < e) {
            if (start)
                *start = s;
            if (end)
                *end = e;
            return url.startsWith(QLatin1String("www.")) ? QStringLiteral("https://") + url : url;
        }
    }
    return {};
}

QString TerminalView::linkAt(qreal x, qreal y) const
{
    return linkAtPos(posAt(QPointF(x, y)));
}

void TerminalView::updateHoveredLink(QPointF p, Qt::KeyboardModifiers mods)
{
    QString link;
    qint64 line = -1;
    int s = 0, e = 0;
    if (p.x() >= 0 && p.y() >= 0 && p.x() < width() && p.y() < height()) {
        const Pos c = posAt(p);
        link = linkAtPos(c, &s, &e);
        if (!link.isEmpty())
            line = c.line;
    }
    if (line != m_linkLine || s != m_linkStart || e != m_linkEnd) {
        m_linkLine = line;
        m_linkStart = s;
        m_linkEnd = e;
        update();
    }
    if (link != m_hoveredLink) {
        m_hoveredLink = link;
        emit hoveredLinkChanged();
    }
    setCursor(!link.isEmpty() && (mods & Qt::ControlModifier) ? Qt::PointingHandCursor
              : m_session->mouseMode() ? Qt::ArrowCursor : Qt::IBeamCursor);
}

// ——— Wyszukiwanie ———

void TerminalView::search(const QString &text)
{
    m_query = text;
    m_matchIndex = -1;
    runSearch(false);
    revealMatch();
}

void TerminalView::runSearch(bool keepIndex)
{
    Match previous{-1, 0, 0};
    if (keepIndex && m_matchIndex >= 0 && m_matchIndex < int(m_matches.size()))
        previous = m_matches[size_t(m_matchIndex)];
    m_matches.clear();
    m_matchIndex = -1;
    if (!m_query.isEmpty()) {
        QVector<int> cols;
        for (qint64 ln = m_session->firstAbsolute(); ln < m_session->endAbsolute() && m_matches.size() < 5000; ++ln) {
            const QString text = rowText(ln, &cols);
            for (qsizetype i = text.indexOf(m_query, 0, Qt::CaseInsensitive); i >= 0; i = text.indexOf(m_query, i + 1, Qt::CaseInsensitive))
                m_matches.push_back({ln, cols.value(int(i)), cols.value(int(i + m_query.size() - 1)) + 1});
        }
        if (!m_matches.empty()) {
            if (previous.line >= 0) {
                for (int i = 0; i < int(m_matches.size()); ++i)
                    if (m_matches[size_t(i)].line == previous.line && m_matches[size_t(i)].start == previous.start)
                        m_matchIndex = i;
            }
            if (m_matchIndex < 0) {
                // Najbliższy wynik nad dolną krawędzią widoku (najnowszy widoczny)
                const qint64 bottom = topLine() + m_session->rows();
                m_matchIndex = int(m_matches.size()) - 1;
                while (m_matchIndex > 0 && m_matches[size_t(m_matchIndex)].line >= bottom)
                    --m_matchIndex;
            }
        }
    }
    emit searchChanged();
    update();
}

void TerminalView::searchNext(bool backwards)
{
    if (m_matches.empty())
        return;
    const int n = int(m_matches.size());
    m_matchIndex = ((m_matchIndex + (backwards ? -1 : 1)) % n + n) % n;
    revealMatch();
    emit searchChanged();
    update();
}

void TerminalView::revealMatch()
{
    if (m_matchIndex < 0 || m_matchIndex >= int(m_matches.size()))
        return;
    const qint64 ln = m_matches[size_t(m_matchIndex)].line;
    const qint64 top = topLine();
    const int rows = m_session->rows();
    if (ln >= top && ln < top + rows)
        return;
    const qint64 newTop = ln - rows / 3;
    scrollTo(int(m_session->endAbsolute() - rows - newTop));
}

void TerminalView::endSearch()
{
    m_query.clear();
    m_matches.clear();
    m_matchIndex = -1;
    m_searchTimer.stop();
    emit searchChanged();
    update();
}

// ——— Klawiatura ———

static VTermModifier vtermMods(Qt::KeyboardModifiers m)
{
    int mod = VTERM_MOD_NONE;
    if (m & Qt::ShiftModifier) mod |= VTERM_MOD_SHIFT;
    if (m & Qt::AltModifier) mod |= VTERM_MOD_ALT;
    if (m & Qt::ControlModifier) mod |= VTERM_MOD_CTRL;
    return VTermModifier(mod);
}

bool TerminalView::event(QEvent *e)
{
    // Skróty okna (karty, powiększenie) zostają oknu; resztę klawiszy dostaje program w terminalu
    if (e->type() == QEvent::ShortcutOverride) {
        auto *k = static_cast<QKeyEvent *>(e);
        const Qt::KeyboardModifiers m = k->modifiers() & ~Qt::KeypadModifier;
        const int key = k->key();
        const bool ctrl = m & Qt::ControlModifier, shift = m & Qt::ShiftModifier;
        bool windowShortcut = (ctrl && shift && key != Qt::Key_C && key != Qt::Key_V)
            || (ctrl && (key == Qt::Key_Tab || key == Qt::Key_Backtab || key == Qt::Key_PageUp || key == Qt::Key_PageDown
                         || key == Qt::Key_Equal || key == Qt::Key_Plus || key == Qt::Key_Minus || key == Qt::Key_0))
            || key == Qt::Key_F11
            || (m == Qt::AltModifier && key >= Qt::Key_1 && key <= Qt::Key_9);
        if (!windowShortcut) {
            e->accept();
            return true;
        }
    }
    return QQuickPaintedItem::event(e);
}

void TerminalView::keyPressEvent(QKeyEvent *e)
{
    const Qt::KeyboardModifiers m = e->modifiers() & ~Qt::KeypadModifier;
    const int key = e->key();
    const bool ctrl = m & Qt::ControlModifier, shift = m & Qt::ShiftModifier;
    e->accept();

    // Schowek: Ctrl+Shift+C/V zawsze; Ctrl+C kopiuje, gdy coś jest zaznaczone (inaczej przerywa program);
    // Ctrl+V wkleja poza programami pełnoekranowymi (w Vimie to zaznaczanie blokiem)
    if (ctrl && shift && key == Qt::Key_C) { copy(); return; }
    if (ctrl && shift && key == Qt::Key_V) { paste(); return; }
    if (ctrl && !shift && key == Qt::Key_C && hasSelection()) { copy(); clearSelection(); return; }
    if (ctrl && !shift && key == Qt::Key_V && !m_session->altScreen()) { paste(); return; }
    if (shift && !ctrl && key == Qt::Key_Insert) { paste(); return; }

    // Historia: Shift+PgUp/PgDn, Shift+Home/End
    if (shift && !ctrl && !m_session->altScreen()) {
        const int page = qMax(1, m_session->rows() - 1);
        if (key == Qt::Key_PageUp) { scrollBy(page); return; }
        if (key == Qt::Key_PageDown) { scrollBy(-page); return; }
        if (key == Qt::Key_Home) { scrollTo(m_session->historyCount()); return; }
        if (key == Qt::Key_End) { scrollToBottom(); return; }
    }

    if (key == Qt::Key_Shift || key == Qt::Key_Control || key == Qt::Key_Alt || key == Qt::Key_Meta
        || key == Qt::Key_AltGr || key == Qt::Key_CapsLock || key == Qt::Key_NumLock || key == Qt::Key_Super_L || key == Qt::Key_Super_R) {
        if (key == Qt::Key_Control && !m_hoveredLink.isEmpty())
            setCursor(Qt::PointingHandCursor);
        return;
    }

    forwardKey(e);
    scrollToBottom();
    if (!e->text().isEmpty())
        clearSelection();
    resetBlink();
    if (key == Qt::Key_Return || key == Qt::Key_Enter)
        QTimer::singleShot(250, m_session, &TerminalSession::pollProcess);
}

void TerminalView::forwardKey(QKeyEvent *e)
{
    const Qt::KeyboardModifiers m = e->modifiers();
    VTermModifier mod = vtermMods(m);
    VTerm *vt = m_session->vt();
    VTermKey k = VTERM_KEY_NONE;
    switch (e->key()) {
    case Qt::Key_Return: k = VTERM_KEY_ENTER; break;
    case Qt::Key_Enter: k = (m & Qt::KeypadModifier) ? VTERM_KEY_KP_ENTER : VTERM_KEY_ENTER; break;
    case Qt::Key_Tab: k = VTERM_KEY_TAB; break;
    case Qt::Key_Backtab: k = VTERM_KEY_TAB; mod = VTermModifier(mod | VTERM_MOD_SHIFT); break;
    case Qt::Key_Backspace: k = VTERM_KEY_BACKSPACE; break;
    case Qt::Key_Escape: k = VTERM_KEY_ESCAPE; break;
    case Qt::Key_Up: k = VTERM_KEY_UP; break;
    case Qt::Key_Down: k = VTERM_KEY_DOWN; break;
    case Qt::Key_Left: k = VTERM_KEY_LEFT; break;
    case Qt::Key_Right: k = VTERM_KEY_RIGHT; break;
    case Qt::Key_Insert: k = VTERM_KEY_INS; break;
    case Qt::Key_Delete: k = VTERM_KEY_DEL; break;
    case Qt::Key_Home: k = VTERM_KEY_HOME; break;
    case Qt::Key_End: k = VTERM_KEY_END; break;
    case Qt::Key_PageUp: k = VTERM_KEY_PAGEUP; break;
    case Qt::Key_PageDown: k = VTERM_KEY_PAGEDOWN; break;
    default:
        if (e->key() >= Qt::Key_F1 && e->key() <= Qt::Key_F35)
            k = VTermKey(VTERM_KEY_FUNCTION(e->key() - Qt::Key_F1 + 1));
        break;
    }
    if (k != VTERM_KEY_NONE) {
        // Backspace z Ctrl usuwa słowo (jak w edytorach)
        if (k == VTERM_KEY_BACKSPACE && (m & Qt::ControlModifier)) {
            m_session->write((m & Qt::AltModifier) ? "\x1b\x08" : "\x17");
            return;
        }
        vterm_keyboard_key(vt, k, mod);
        return;
    }

    // Ctrl + litera i znaki sterujące
    if (m & Qt::ControlModifier) {
        const int key = e->key();
        int code = -1;
        if (key >= Qt::Key_A && key <= Qt::Key_Z) code = key - Qt::Key_A + 1;
        else if (key == Qt::Key_Space || key == Qt::Key_2 || key == Qt::Key_At) code = 0;
        else if (key == Qt::Key_BracketLeft || key == Qt::Key_3) code = 27;
        else if (key == Qt::Key_Backslash || key == Qt::Key_4) code = 28;
        else if (key == Qt::Key_BracketRight || key == Qt::Key_5) code = 29;
        else if (key == Qt::Key_AsciiCircum || key == Qt::Key_6) code = 30;
        else if (key == Qt::Key_Underscore || key == Qt::Key_Minus || key == Qt::Key_7 || key == Qt::Key_Slash) code = 31;
        else if (key == Qt::Key_8 || key == Qt::Key_Question) code = 127;
        if (code >= 0) {
            QByteArray b;
            if (m & Qt::AltModifier)
                b += '\x1b';
            b += char(code);
            m_session->write(b);
            return;
        }
    }

    const QString text = e->text();
    if (text.isEmpty())
        return;
    if ((m & Qt::AltModifier) && !(m & Qt::ControlModifier)) {
        const auto ucs = text.toUcs4();
        for (char32_t c : ucs)
            vterm_keyboard_unichar(vt, c, VTERM_MOD_ALT);
        return;
    }
    m_session->sendText(text);
}

void TerminalView::inputMethodEvent(QInputMethodEvent *e)
{
    if (!e->commitString().isEmpty()) {
        scrollToBottom();
        clearSelection();
        m_session->sendText(e->commitString());
        resetBlink();
    }
    e->accept();
}

QVariant TerminalView::inputMethodQuery(Qt::InputMethodQuery query) const
{
    switch (query) {
    case Qt::ImEnabled:
        return true;
    case Qt::ImHints:
        return int(Qt::ImhNoPredictiveText | Qt::ImhNoAutoUppercase | Qt::ImhPreferLatin);
    case Qt::ImCursorRectangle: {
        const int row = m_session->cursorRow() + m_scroll;
        return QRectF(m_session->cursorCol() * m_cw, row * m_ch, m_cw, m_ch);
    }
    case Qt::ImFont:
        return m_font;
    default:
        return QQuickPaintedItem::inputMethodQuery(query);
    }
}

void TerminalView::focusInEvent(QFocusEvent *e)
{
    QQuickPaintedItem::focusInEvent(e);
    m_session->focusChanged(true);
    resetBlink();
}

void TerminalView::focusOutEvent(QFocusEvent *e)
{
    QQuickPaintedItem::focusOutEvent(e);
    m_session->focusChanged(false);
    resetBlink();
}

// ——— Mysz ———

bool TerminalView::sendMouse(QMouseEvent *e, bool pressed, bool release)
{
    if (!m_session->mouseMode() || (e->modifiers() & Qt::ShiftModifier) || m_scroll > 0 || !m_session->running())
        return false;
    const int row = qBound(0, int(e->position().y() / m_ch), m_session->rows() - 1);
    const int col = qBound(0, int(e->position().x() / m_cw), m_session->cols() - 1);
    const VTermModifier mod = vtermMods(e->modifiers());
    vterm_mouse_move(m_session->vt(), row, col, mod);
    if (pressed || release) {
        const int b = e->button() == Qt::LeftButton ? 1 : e->button() == Qt::MiddleButton ? 2 : e->button() == Qt::RightButton ? 3 : 0;
        if (b)
            vterm_mouse_button(m_session->vt(), b, pressed, mod);
    }
    return true;
}

void TerminalView::mousePressEvent(QMouseEvent *e)
{
    forceActiveFocus(Qt::MouseFocusReason);
    // Drugi raz to samo kliknięcie (Qt Quick dostarcza je też jako podwójne)
    if (e->timestamp() == m_lastClickTime && m_clicks > 0)
        return;
    const QPointF pt = e->position();
    if (e->button() == Qt::LeftButton && (e->modifiers() & Qt::ControlModifier)) {
        const QString link = linkAt(pt.x(), pt.y());
        if (!link.isEmpty()) {
            emit linkActivated(link);
            return;
        }
    }
    if (sendMouse(e, true, false)) {
        m_mouseButtons |= e->button();
        return;
    }
    if (e->button() == Qt::RightButton) {
        emit contextMenuRequested(pt.x(), pt.y(), linkAt(pt.x(), pt.y()));
        return;
    }
    if (e->button() == Qt::MiddleButton) {
        pasteSelection();
        return;
    }
    if (e->button() != Qt::LeftButton)
        return;

    const quint64 now = e->timestamp();
    if (now - m_lastClickTime < quint64(QGuiApplication::styleHints()->mouseDoubleClickInterval())
        && (pt - m_pressPos).manhattanLength() < 6)
        m_clicks = m_clicks % 3 + 1;
    else
        m_clicks = 1;
    m_lastClickTime = now;
    m_pressPos = pt;
    m_lastMouse = pt;

    if ((e->modifiers() & Qt::ShiftModifier) && m_selActive && m_clicks == 1) {
        m_selMode = 1;
        m_anchor = posAt(pt, true) < m_selStart ? m_selEnd : m_selStart;
        extendSelection(posAt(pt, true));
        m_selecting = true;
        return;
    }

    m_selMode = m_clicks;
    const Pos cell = posAt(pt);
    if (m_selMode == 1) {
        m_anchor = posAt(pt, true);
        clearSelection();
    } else if (m_selMode == 2) {
        m_anchor = wordStart(cell);
        m_anchorEnd = wordEnd(cell);
        setSelection(m_anchor, m_anchorEnd);
    } else {
        m_anchor = {cell.line, 0};
        m_anchorEnd = {cell.line + 1, 0};
        extendSelection(cell);
        m_anchor = m_selStart;
        m_anchorEnd = m_selEnd;
    }
    m_selecting = true;
}

void TerminalView::mouseDoubleClickEvent(QMouseEvent *e)
{
    mousePressEvent(e);
}

void TerminalView::mouseMoveEvent(QMouseEvent *e)
{
    if (m_mouseButtons) {
        if (m_session->mouseMode() >= VTERM_PROP_MOUSE_DRAG)
            sendMouse(e, false, false);
        return;
    }
    if (!m_selecting)
        return;
    const QPointF pt = e->position();
    m_lastMouse = pt;
    if (m_selMode == 1 && !m_selActive && (pt - m_pressPos).manhattanLength() < 3)
        return;
    extendSelection(posAt(pt, m_selMode == 1));
    // Przeciąganie za krawędź przewija historię
    m_autoScrollDir = pt.y() < 0 ? -1 : pt.y() > height() ? 1 : 0;
    if (m_autoScrollDir && !m_autoScroll.isActive())
        m_autoScroll.start();
    else if (!m_autoScrollDir)
        m_autoScroll.stop();
}

void TerminalView::mouseReleaseEvent(QMouseEvent *e)
{
    if (m_mouseButtons & e->button()) {
        m_mouseButtons &= ~e->button();
        sendMouse(e, false, true);
        return;
    }
    m_autoScroll.stop();
    if (m_selecting) {
        m_selecting = false;
        finishSelection();
    }
}

void TerminalView::hoverMoveEvent(QHoverEvent *e)
{
    m_lastMouse = e->position();
    if (m_session->mouseMode() == VTERM_PROP_MOUSE_MOVE && !(e->modifiers() & Qt::ShiftModifier) && m_scroll == 0) {
        const int row = qBound(0, int(e->position().y() / m_ch), m_session->rows() - 1);
        const int col = qBound(0, int(e->position().x() / m_cw), m_session->cols() - 1);
        vterm_mouse_move(m_session->vt(), row, col, vtermMods(e->modifiers()));
    }
    updateHoveredLink(e->position(), e->modifiers());
}

void TerminalView::hoverLeaveEvent(QHoverEvent *)
{
    updateHoveredLink(QPointF(-1, -1), {});
}

void TerminalView::wheelEvent(QWheelEvent *e)
{
    if (e->modifiers() & Qt::ControlModifier) {
        if (e->angleDelta().y())
            emit zoomRequested(e->angleDelta().y() > 0 ? 1 : -1);
        return;
    }
    qreal lines = 0;
    if (!e->pixelDelta().isNull())
        lines = e->pixelDelta().y() / m_ch;
    else
        lines = e->angleDelta().y() / 120.0 * 3;
    m_wheelRest += lines;
    const int n = int(m_wheelRest);
    if (!n)
        return;
    m_wheelRest -= n;

    const bool shift = e->modifiers() & Qt::ShiftModifier;
    if (m_scroll == 0 && m_session->running() && !shift) {
        // Program obsługuje mysz sam — kółko jako przyciski 4/5
        if (m_session->mouseMode()) {
            const int row = qBound(0, int(e->position().y() / m_ch), m_session->rows() - 1);
            const int col = qBound(0, int(e->position().x() / m_cw), m_session->cols() - 1);
            vterm_mouse_move(m_session->vt(), row, col, VTERM_MOD_NONE);
            for (int i = 0; i < qAbs(n); ++i)
                vterm_mouse_button(m_session->vt(), n > 0 ? 4 : 5, true, VTERM_MOD_NONE);
            return;
        }
        // Program pełnoekranowy bez myszy (less, man): kółko jako strzałki
        if (m_session->altScreen()) {
            for (int i = 0; i < qAbs(n); ++i)
                vterm_keyboard_key(m_session->vt(), n > 0 ? VTERM_KEY_UP : VTERM_KEY_DOWN, VTERM_MOD_NONE);
            return;
        }
    }
    scrollBy(n);
}

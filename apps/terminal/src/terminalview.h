#pragma once

// Widok terminala: rysuje komórki sesji (własne rysowanie ramek i bloków, więc tabelki
// w htop czy mc łączą się bez szczelin), obsługuje klawiaturę, mysz, zaznaczanie,
// linki, przewijanie historii i wyszukiwanie.

#include "session.h"

#include <QColor>
#include <QFont>
#include <QHash>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class TerminalView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    // Wygląd
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontChanged)
    Q_PROPERTY(qreal fontSize READ fontSize WRITE setFontSize NOTIFY fontChanged)
    Q_PROPERTY(qreal lineHeight READ lineHeight WRITE setLineHeight NOTIFY fontChanged)
    Q_PROPERTY(QColor foreground MEMBER m_fg WRITE setForeground NOTIFY colorsChanged)
    Q_PROPERTY(QColor background MEMBER m_bg WRITE setBackground NOTIFY colorsChanged)
    Q_PROPERTY(QColor cursorColor MEMBER m_cursorColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor selectionColor MEMBER m_selectionColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor matchColor MEMBER m_matchColor NOTIFY colorsChanged)
    Q_PROPERTY(QVariantList colorPalette READ colorPalette WRITE setColorPalette NOTIFY colorsChanged)
    Q_PROPERTY(int cursorStyle MEMBER m_cursorStyle NOTIFY cursorStyleChanged)       // 1 blok, 2 podkreślenie, 3 kreska
    Q_PROPERTY(bool cursorBlinking READ cursorBlinking WRITE setCursorBlinking NOTIFY cursorStyleChanged)
    Q_PROPERTY(int historyLimit READ historyLimit WRITE setHistoryLimit NOTIFY historyLimitChanged)
    Q_PROPERTY(bool copyOnSelect MEMBER m_copyOnSelect NOTIFY copyOnSelectChanged)

    // Uruchomienie
    Q_PROPERTY(QString workingDirectory MEMBER m_startDir NOTIFY startChanged)
    Q_PROPERTY(QStringList command MEMBER m_command NOTIFY startChanged)

    // Stan
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int exitCode READ exitCode NOTIFY runningChanged)
    Q_PROPERTY(QString currentDirectory READ currentDirectory NOTIFY currentDirectoryChanged)
    Q_PROPERTY(QString program READ program NOTIFY programChanged)
    Q_PROPERTY(QString appTitle READ appTitle NOTIFY appTitleChanged)
    Q_PROPERTY(bool altScreen READ altScreen NOTIFY modesChanged)
    Q_PROPERTY(int columns READ columns NOTIFY sizeChanged)
    Q_PROPERTY(int rows READ rows NOTIFY sizeChanged)
    Q_PROPERTY(qreal cellWidth READ cellWidth NOTIFY fontChanged)
    Q_PROPERTY(qreal cellHeight READ cellHeight NOTIFY fontChanged)
    Q_PROPERTY(int scrollValue READ scrollValue NOTIFY scrollChanged)      // ile linii nad dołem
    Q_PROPERTY(int scrollMax READ scrollMax NOTIFY scrollChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(QString hoveredLink READ hoveredLink NOTIFY hoveredLinkChanged)
    Q_PROPERTY(int matchCount READ matchCount NOTIFY searchChanged)
    Q_PROPERTY(int matchIndex READ matchIndex NOTIFY searchChanged)

public:
    explicit TerminalView(QQuickItem *parent = nullptr);
    ~TerminalView() override;

    void paint(QPainter *p) override;

    QString fontFamily() const { return m_family; }
    void setFontFamily(const QString &f);
    qreal fontSize() const { return m_size; }
    void setFontSize(qreal s);
    qreal lineHeight() const { return m_lineHeight; }
    void setLineHeight(qreal h);
    void setForeground(const QColor &c);
    void setBackground(const QColor &c);
    QVariantList colorPalette() const;
    void setColorPalette(const QVariantList &list);
    bool cursorBlinking() const { return m_blinking; }
    void setCursorBlinking(bool on);
    int historyLimit() const { return m_historyLimit; }
    void setHistoryLimit(int lines);

    bool running() const { return m_session->running(); }
    int exitCode() const { return m_session->exitCode(); }
    QString currentDirectory() const { return m_session->currentDirectory(); }
    QString program() const { return m_session->foregroundProgram(); }
    QString appTitle() const { return m_session->title(); }
    bool altScreen() const { return m_session->altScreen(); }
    int columns() const { return m_session->cols(); }
    int rows() const { return m_session->rows(); }
    qreal cellWidth() const { return m_cw; }
    qreal cellHeight() const { return m_ch; }
    int scrollValue() const { return m_scroll; }
    int scrollMax() const { return m_session->historyCount(); }
    bool hasSelection() const { return m_selActive && m_selStart != m_selEnd; }
    QString hoveredLink() const { return m_hoveredLink; }
    int matchCount() const { return int(m_matches.size()); }
    int matchIndex() const { return m_matchIndex; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void copy();
    Q_INVOKABLE void paste();
    Q_INVOKABLE void pasteSelection();
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QString selectedText() const;
    Q_INVOKABLE void sendText(const QString &text);
    Q_INVOKABLE void clear();                              // czyści historię i ekran (jak „clear”)
    Q_INVOKABLE void scrollTo(int linesFromBottom);
    Q_INVOKABLE void scrollBy(int lines);
    Q_INVOKABLE void scrollToBottom() { scrollTo(0); }
    Q_INVOKABLE QString linkAt(qreal x, qreal y) const;
    Q_INVOKABLE void search(const QString &text);
    Q_INVOKABLE void searchNext(bool backwards);
    Q_INVOKABLE void endSearch();
    Q_INVOKABLE QString historyText() const;              // cała zawartość (zapis do pliku)

signals:
    void fontChanged();
    void colorsChanged();
    void cursorStyleChanged();
    void historyLimitChanged();
    void copyOnSelectChanged();
    void startChanged();
    void runningChanged();
    void currentDirectoryChanged();
    void programChanged();
    void appTitleChanged();
    void modesChanged();
    void sizeChanged();
    void scrollChanged();
    void selectionChanged();
    void hoveredLinkChanged();
    void searchChanged();
    void bell();
    void activity();
    void finished(int exitCode);
    void copied();
    void contextMenuRequested(qreal x, qreal y, const QString &link);
    void linkActivated(const QString &url);
    void zoomRequested(int direction);

protected:
    void componentComplete() override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    bool event(QEvent *e) override;
    void keyPressEvent(QKeyEvent *e) override;
    void inputMethodEvent(QInputMethodEvent *e) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    void focusInEvent(QFocusEvent *e) override;
    void focusOutEvent(QFocusEvent *e) override;
    void mousePressEvent(QMouseEvent *e) override;
    void mouseMoveEvent(QMouseEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;
    void mouseDoubleClickEvent(QMouseEvent *e) override;
    void hoverMoveEvent(QHoverEvent *e) override;
    void hoverLeaveEvent(QHoverEvent *e) override;
    void wheelEvent(QWheelEvent *e) override;

private:
    struct Pos {
        qint64 line = 0;
        int col = 0;
        bool operator==(const Pos &o) const { return line == o.line && col == o.col; }
        bool operator!=(const Pos &o) const { return !(*this == o); }
        bool operator<(const Pos &o) const { return line < o.line || (line == o.line && col < o.col); }
    };
    struct Match {
        qint64 line;
        int start, end;
    };

    void updateMetrics();
    void updateSize();
    void applyPalette();
    qint64 topLine() const;
    Pos posAt(QPointF p, bool boundary = false) const;    // komórka pod punktem albo najbliższa granica między komórkami
    QString rowText(qint64 line, QVector<int> *cols = nullptr) const;
    QString linkAtPos(Pos c, int *start = nullptr, int *end = nullptr) const;
    QRgb resolve(quint32 color, bool fg) const;
    bool drawBox(QPainter *p, char32_t ch, const QRect &r, const QColor &color) const;
    bool inFont(char32_t ch, bool bold);
    void setSelection(Pos a, Pos b);
    void extendSelection(Pos p);
    Pos wordStart(Pos p) const;
    Pos wordEnd(Pos p) const;
    void finishSelection();
    bool selected(qint64 line, int col) const;
    bool sendMouse(QMouseEvent *e, bool pressed, bool release);
    void forwardKey(QKeyEvent *e);
    void resetBlink();
    void updateHoveredLink(QPointF p, Qt::KeyboardModifiers mods);
    void runSearch(bool keepIndex);
    void revealMatch();
    void onContent();
    void attachSession();

    TerminalSession *m_session = nullptr;
    bool m_complete = false;
    bool m_started = false;
    QString m_startDir;
    QStringList m_command;

    QString m_family;
    qreal m_size = 14;
    qreal m_lineHeight = 1.2;
    QFont m_font, m_bold, m_italic, m_boldItalic;
    qreal m_cw = 8, m_ch = 16, m_ascent = 12, m_textTop = 0;
    qreal m_underlinePos = 2, m_strikePos = 4, m_lineWidth = 1;
    QHash<char32_t, bool> m_inFont, m_inBold;

    QColor m_fg = QColor(0xE6, 0xE8, 0xEE), m_bg = QColor(9, 10, 13);
    QColor m_cursorColor = QColor(0x7C, 0x8C, 0xFF), m_selectionColor = QColor(0x7C, 0x8C, 0xFF, 90);
    QColor m_matchColor = QColor(0xF5, 0xC5, 0x42);
    QVector<QRgb> m_palette16;
    int m_cursorStyle = 1;
    bool m_blinking = true;
    bool m_blinkOn = true;
    QTimer m_blink;
    int m_historyLimit = 10000;
    bool m_copyOnSelect = false;

    int m_scroll = 0;
    qreal m_wheelRest = 0;

    // Zaznaczenie: punkty w liniach bezwzględnych; tryb 1 — znaki, 2 — słowa, 3 — linie
    bool m_selActive = false;
    bool m_selecting = false;
    int m_selMode = 1;
    Pos m_anchor, m_anchorEnd, m_selStart, m_selEnd;
    QPointF m_pressPos;
    QTimer m_autoScroll;
    int m_autoScrollDir = 0;
    QPointF m_lastMouse;
    quint64 m_lastClickTime = 0;
    int m_clicks = 0;
    int m_mouseButtons = 0;

    QString m_hoveredLink;
    qint64 m_linkLine = -1;
    int m_linkStart = 0, m_linkEnd = 0;

    QString m_query;
    std::vector<Match> m_matches;
    int m_matchIndex = -1;
    QTimer m_searchTimer;
};

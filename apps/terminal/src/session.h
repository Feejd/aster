#pragma once

// Sesja terminala: powłoka na pseudoterminalu (forkpty) i stan ekranu z libvterm
// (ten sam silnik emulacji co w Neovimie) plus własna historia przewijania.
// Komórki ekranu i historii czyta TerminalView — oba źródła mają jeden kształt (Line).

#include <QByteArray>
#include <QColor>
#include <QObject>
#include <QSocketNotifier>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVector>
#include <deque>

extern "C" {
#include <vterm.h>
}

namespace Term {

// Kolor komórki: domyślny, z palety (indeks) albo RGB — rozwiązywany przy rysowaniu,
// więc zmiana schematu kolorów przemalowuje też historię.
enum : quint32 { ColorDefault = 0, ColorIndexed = 0x1000000, ColorRgb = 0x2000000, ColorTypeMask = 0xFF000000 };

enum CellFlag : quint16 {
    Bold = 1, Italic = 2, Underline = 4, DoubleUnderline = 8, CurlyUnderline = 16,
    Strike = 32, Reverse = 64, Conceal = 128, Blink = 256
};

struct Cell {
    char32_t ch = 0;          // 0 — pusta komórka; dalsza część szerokiego znaku ma width 0
    quint8 width = 1;
    quint16 flags = 0;
    quint32 fg = ColorDefault;
    quint32 bg = ColorDefault;
};

struct Line {
    QVector<Cell> cells;
    bool wrapped = false;     // ciąg dalszy następnej linii (zawinięta, a nie zakończona Enterem)
};

} // namespace Term

class TerminalSession : public QObject
{
    Q_OBJECT
public:
    explicit TerminalSession(QObject *parent = nullptr);
    ~TerminalSession() override;

    // Uruchamia powłokę użytkownika (albo command) w katalogu dir
    bool start(int rows, int cols, const QString &dir, const QStringList &command);
    bool running() const { return m_pid > 0 && m_fd >= 0; }

    void resize(int rows, int cols);
    int rows() const { return m_rows; }
    int cols() const { return m_cols; }

    // Wiersze: najpierw historia (0 … historyCount−1), potem ekran.
    // Numeracja „bezwzględna” (absolute) nie zmienia się, gdy najstarsze linie wypadają z historii.
    int historyCount() const { return int(m_history.size()); }
    qint64 dropped() const { return m_dropped; }
    qint64 firstAbsolute() const { return m_dropped; }
    qint64 endAbsolute() const { return m_dropped + historyCount() + m_rows; }
    Term::Line line(qint64 absolute) const;
    QString lineText(qint64 absolute) const;
    void setHistoryLimit(int lines);
    void clearHistory();

    // Pisanie do programu
    void write(const QByteArray &bytes);
    void sendText(const QString &text);
    void paste(const QString &text);
    VTerm *vt() const { return m_vt; }
    void focusChanged(bool in);

    // Kolory: 16 kolorów palety, tekst i tło (domyślne)
    void setPalette(const QVector<QRgb> &sixteen, QRgb fg, QRgb bg);
    QRgb paletteColor(int index) const;

    // Stan ekranu
    int cursorRow() const { return m_cursorRow; }
    int cursorCol() const { return m_cursorCol; }
    bool cursorVisible() const { return m_cursorVisible; }
    int cursorShape() const { return m_cursorShape; }        // 0 — według ustawień, 1 blok, 2 podkreślenie, 3 kreska
    bool cursorBlink() const { return m_cursorBlink; }
    bool altScreen() const { return m_altScreen; }
    int mouseMode() const { return m_mouseMode; }
    bool reverseVideo() const { return m_reverse; }
    QString title() const { return m_title; }

    // Proces
    int pid() const { return m_pid; }
    QString currentDirectory() const { return m_cwd; }
    QString foregroundProgram() const { return m_program; }   // pusty, gdy powłoka czeka na polecenie
    int exitCode() const { return m_exitCode; }
    void pollProcess();                                       // od razu sprawdza katalog i program

signals:
    void contentChanged();
    void historyPushed(int lines);
    void historyCleared();
    void cursorChanged();
    void modesChanged();
    void titleChanged();
    void bell();
    void directoryChanged();
    void programChanged();
    void clipboardRequested(const QString &text);    // OSC 52 (np. kopiowanie z Vima przez SSH)
    void finished(int exitCode);

private:
    static int cbDamage(VTermRect rect, void *user);
    static int cbMoveCursor(VTermPos pos, VTermPos oldpos, int visible, void *user);
    static int cbSetTermProp(VTermProp prop, VTermValue *val, void *user);
    static int cbBell(void *user);
    static int cbPushLine(int cols, const VTermScreenCell *cells, void *user);
    static int cbPopLine(int cols, VTermScreenCell *cells, void *user);
    static int cbClearHistory(void *user);
    static int cbOsc(int command, VTermStringFragment frag, void *user);
    static int cbSelectionSet(VTermSelectionMask mask, VTermStringFragment frag, void *user);
    static int cbSelectionQuery(VTermSelectionMask mask, void *user);
    static void cbOutput(const char *s, size_t len, void *user);

    Term::Cell convert(const VTermScreenCell &c) const;
    void readOutput();
    void flushWrites();
    void childGone();

    VTerm *m_vt = nullptr;
    VTermScreen *m_screen = nullptr;
    VTermState *m_state = nullptr;
    int m_rows = 24, m_cols = 80;
    int m_fd = -1;
    int m_pid = -1;
    int m_exitCode = 0;
    QSocketNotifier *m_readNotifier = nullptr;
    QSocketNotifier *m_writeNotifier = nullptr;
    QByteArray m_pending;
    QTimer m_poll;

    std::deque<Term::Line> m_history;
    qint64 m_dropped = 0;
    int m_historyLimit = 10000;
    int m_pushedInBatch = 0;
    bool m_dirty = false;

    QVector<QRgb> m_palette;
    int m_cursorRow = 0, m_cursorCol = 0;
    bool m_cursorVisible = true;
    int m_cursorShape = 0;
    bool m_cursorBlink = false;
    bool m_altScreen = false;
    int m_mouseMode = 0;
    bool m_reverse = false;
    QByteArray m_titleBuf, m_oscBuf, m_clipBuf;
    char m_selectionBuf[4096];
    QString m_title;
    QString m_cwd;
    QString m_program;
};

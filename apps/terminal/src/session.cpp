#include "session.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <pty.h>
#include <pwd.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <thread>
#include <unistd.h>

using namespace Term;

namespace {

// Paleta 256 kolorów xterm: 16 z motywu, sześcian 6×6×6 i 24 odcienie szarości
QVector<QRgb> xtermPalette()
{
    QVector<QRgb> p(256, 0);
    static const int steps[6] = {0, 95, 135, 175, 215, 255};
    for (int i = 0; i < 216; ++i)
        p[16 + i] = qRgb(steps[(i / 36) % 6], steps[(i / 6) % 6], steps[i % 6]);
    for (int i = 0; i < 24; ++i) {
        const int v = 8 + i * 10;
        p[232 + i] = qRgb(v, v, v);
    }
    return p;
}

VTermColor rgbColor(QRgb c)
{
    VTermColor v;
    vterm_color_rgb(&v, quint8(qRed(c)), quint8(qGreen(c)), quint8(qBlue(c)));
    return v;
}

} // namespace

TerminalSession::TerminalSession(QObject *parent)
    : QObject(parent)
    , m_palette(xtermPalette())
{
    m_vt = vterm_new(m_rows, m_cols);
    vterm_set_utf8(m_vt, 1);
    m_state = vterm_obtain_state(m_vt);
    m_screen = vterm_obtain_screen(m_vt);

    static VTermScreenCallbacks callbacks = [] {
        VTermScreenCallbacks c{};
        c.damage = cbDamage;
        c.movecursor = cbMoveCursor;
        c.settermprop = cbSetTermProp;
        c.bell = cbBell;
        c.sb_pushline = cbPushLine;
        c.sb_popline = cbPopLine;
        c.sb_clear = cbClearHistory;
        return c;
    }();
    static VTermStateFallbacks fallbacks = [] {
        VTermStateFallbacks f{};
        f.osc = cbOsc;
        return f;
    }();
    static VTermSelectionCallbacks selection = [] {
        VTermSelectionCallbacks s{};
        s.set = cbSelectionSet;
        s.query = cbSelectionQuery;
        return s;
    }();

    vterm_screen_set_callbacks(m_screen, &callbacks, this);
    vterm_screen_set_unrecognised_fallbacks(m_screen, &fallbacks, this);
    vterm_state_set_selection_callbacks(m_state, &selection, this, m_selectionBuf, sizeof m_selectionBuf);
    vterm_output_set_callback(m_vt, cbOutput, this);
    vterm_screen_enable_altscreen(m_screen, 1);
    vterm_screen_enable_reflow(m_screen, true);
    vterm_screen_set_damage_merge(m_screen, VTERM_DAMAGE_SCROLL);
    vterm_state_set_bold_highbright(m_state, 0);
    vterm_screen_reset(m_screen, 1);
    m_cursorShape = 0;              // kształt z ustawień, dopóki program nie poprosi o inny
    m_cursorBlink = false;

    m_poll.setInterval(700);
    connect(&m_poll, &QTimer::timeout, this, &TerminalSession::pollProcess);
}

TerminalSession::~TerminalSession()
{
    if (m_fd >= 0) {
        ::close(m_fd);                      // zamknięcie terminala wysyła SIGHUP programom na pierwszym planie
        m_fd = -1;
    }
    if (m_pid > 0) {
        const pid_t pid = m_pid;
        ::kill(pid, SIGHUP);
        // Sprzątanie procesu w tle: po 3 s bez reakcji — SIGKILL
        std::thread([pid] {
            for (int i = 0; i < 30; ++i) {
                if (::waitpid(pid, nullptr, WNOHANG) != 0)
                    return;
                ::usleep(100000);
            }
            ::kill(pid, SIGKILL);
            ::waitpid(pid, nullptr, 0);
        }).detach();
    }
    vterm_free(m_vt);
}

bool TerminalSession::start(int rows, int cols, const QString &dir, const QStringList &command)
{
    if (m_pid > 0)
        return true;
    m_rows = qMax(2, rows);
    m_cols = qMax(2, cols);
    vterm_set_size(m_vt, m_rows, m_cols);

    // Wszystko, czego potrzebuje proces potomny, przygotowane przed fork()
    QByteArray shell = qgetenv("SHELL");
    if (shell.isEmpty())
        if (const passwd *pw = ::getpwuid(::getuid()); pw && pw->pw_shell && *pw->pw_shell)
            shell = pw->pw_shell;
    if (shell.isEmpty())
        shell = "/bin/bash";
    QList<QByteArray> args;
    if (command.isEmpty())
        args << shell;
    else
        for (const QString &a : command)
            args << a.toLocal8Bit();
    QByteArray argv0 = args.first();
    if (command.isEmpty())
        argv0 = QFileInfo(QString::fromLocal8Bit(shell)).fileName().toLocal8Bit();
    QVector<char *> argv;
    argv << argv0.data();
    for (int i = 1; i < args.size(); ++i)
        argv << args[i].data();
    argv << nullptr;

    QString workDir = dir;
    if (workDir.isEmpty() || !QFileInfo(workDir).isDir())
        workDir = QDir::homePath();
    const QByteArray cwd = QFile::encodeName(workDir);

    winsize ws{};
    ws.ws_row = ushort(m_rows);
    ws.ws_col = ushort(m_cols);
    int fd = -1;
    const pid_t pid = ::forkpty(&fd, nullptr, nullptr, &ws);
    if (pid < 0)
        return false;
    if (pid == 0) {
        // Proces potomny: czyste sygnały, zmienne terminala, katalog — i powłoka
        sigset_t all;
        sigemptyset(&all);
        sigprocmask(SIG_SETMASK, &all, nullptr);
        for (int s = 1; s < NSIG; ++s)
            ::signal(s, SIG_DFL);
        ::setenv("TERM", "xterm-256color", 1);
        ::setenv("COLORTERM", "truecolor", 1);
        ::setenv("TERM_PROGRAM", "aster-terminal", 1);
        ::unsetenv("COLUMNS");
        ::unsetenv("LINES");
        if (::chdir(cwd.constData()) != 0)
            (void)::chdir("/");
        ::setenv("PWD", cwd.constData(), 1);
        ::execvp(args.first().constData(), argv.data());
        ::_exit(127);
    }

    m_pid = pid;
    m_fd = fd;
    ::fcntl(m_fd, F_SETFL, ::fcntl(m_fd, F_GETFL) | O_NONBLOCK);
    ::fcntl(m_fd, F_SETFD, FD_CLOEXEC);
    m_readNotifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_readNotifier, &QSocketNotifier::activated, this, &TerminalSession::readOutput);
    m_writeNotifier = new QSocketNotifier(m_fd, QSocketNotifier::Write, this);
    m_writeNotifier->setEnabled(false);
    connect(m_writeNotifier, &QSocketNotifier::activated, this, &TerminalSession::flushWrites);
    m_cwd = workDir;
    m_poll.start();
    return true;
}

void TerminalSession::resize(int rows, int cols)
{
    rows = qMax(2, rows);
    cols = qMax(2, cols);
    if (rows == m_rows && cols == m_cols)
        return;
    m_rows = rows;
    m_cols = cols;
    vterm_set_size(m_vt, rows, cols);
    vterm_screen_flush_damage(m_screen);
    if (m_fd >= 0) {
        winsize ws{};
        ws.ws_row = ushort(rows);
        ws.ws_col = ushort(cols);
        ::ioctl(m_fd, TIOCSWINSZ, &ws);
    }
    if (m_pushedInBatch) {
        emit historyPushed(m_pushedInBatch);
        m_pushedInBatch = 0;
    }
    m_dirty = false;
    emit contentChanged();
}

// ——— Wiersze ———

Cell TerminalSession::convert(const VTermScreenCell &v) const
{
    Cell c;
    c.ch = v.chars[0] == uint32_t(-1) ? 0 : v.chars[0];
    c.width = quint8(qMax(0, int(v.width)));
    quint16 f = 0;
    if (v.attrs.bold) f |= Bold;
    if (v.attrs.italic) f |= Italic;
    if (v.attrs.underline == VTERM_UNDERLINE_SINGLE) f |= Underline;
    else if (v.attrs.underline == VTERM_UNDERLINE_DOUBLE) f |= DoubleUnderline;
    else if (v.attrs.underline == VTERM_UNDERLINE_CURLY) f |= CurlyUnderline;
    if (v.attrs.strike) f |= Strike;
    if (v.attrs.reverse) f |= Reverse;
    if (v.attrs.conceal) f |= Conceal;
    if (v.attrs.blink) f |= Blink;
    c.flags = f;
    const auto color = [](const VTermColor &k, bool isDefault) -> quint32 {
        if (isDefault)
            return ColorDefault;
        if (VTERM_COLOR_IS_INDEXED(&k))
            return ColorIndexed | k.indexed.idx;
        return ColorRgb | (quint32(k.rgb.red) << 16) | (quint32(k.rgb.green) << 8) | k.rgb.blue;
    };
    c.fg = color(v.fg, VTERM_COLOR_IS_DEFAULT_FG(&v.fg));
    c.bg = color(v.bg, VTERM_COLOR_IS_DEFAULT_BG(&v.bg));
    return c;
}

Line TerminalSession::line(qint64 absolute) const
{
    const qint64 i = absolute - m_dropped;
    if (i < 0)
        return {};
    if (i < qint64(m_history.size()))
        return m_history[size_t(i)];
    const int row = int(i - qint64(m_history.size()));
    if (row >= m_rows)
        return {};
    Line l;
    l.cells.resize(m_cols);
    VTermScreenCell vc;
    for (int col = 0; col < m_cols; ++col) {
        VTermPos pos{row, col};
        if (!vterm_screen_get_cell(m_screen, pos, &vc))
            continue;
        l.cells[col] = convert(vc);
        if (col > 0 && l.cells[col - 1].width == 2)
            l.cells[col].width = 0;
    }
    if (row + 1 < m_rows)
        if (const VTermLineInfo *info = vterm_state_get_lineinfo(m_state, row + 1))
            l.wrapped = info->continuation;
    return l;
}

QString TerminalSession::lineText(qint64 absolute) const
{
    const Line l = line(absolute);
    QString s;
    s.reserve(l.cells.size());
    for (const Cell &c : l.cells) {
        if (c.width == 0)
            continue;
        if (c.ch == 0)
            s += QLatin1Char(' ');
        else
            s += QString::fromUcs4(&c.ch, 1);
    }
    while (s.endsWith(QLatin1Char(' ')))
        s.chop(1);
    return s;
}

void TerminalSession::setHistoryLimit(int lines)
{
    m_historyLimit = lines <= 0 ? 1000000 : lines;
    while (int(m_history.size()) > m_historyLimit) {
        m_history.pop_front();
        ++m_dropped;
    }
}

void TerminalSession::clearHistory()
{
    m_dropped += qint64(m_history.size());
    m_history.clear();
    emit historyCleared();
    emit contentChanged();
}

// ——— Pisanie ———

void TerminalSession::write(const QByteArray &bytes)
{
    if (m_fd < 0 || bytes.isEmpty())
        return;
    m_pending += bytes;
    flushWrites();
}

void TerminalSession::flushWrites()
{
    while (!m_pending.isEmpty() && m_fd >= 0) {
        const ssize_t n = ::write(m_fd, m_pending.constData(), size_t(m_pending.size()));
        if (n > 0) {
            m_pending.remove(0, int(n));
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        break;
    }
    if (m_writeNotifier)
        m_writeNotifier->setEnabled(!m_pending.isEmpty() && m_fd >= 0);
}

void TerminalSession::sendText(const QString &text)
{
    write(text.toUtf8());
}

void TerminalSession::paste(const QString &text)
{
    QString t = text;
    t.replace(QLatin1String("\r\n"), QLatin1String("\r"));
    t.replace(QLatin1Char('\n'), QLatin1Char('\r'));
    // Wklejanie w nawiasach (bracketed paste): powłoka nie wykona wklejonych poleceń od razu
    vterm_keyboard_start_paste(m_vt);
    write(t.toUtf8());
    vterm_keyboard_end_paste(m_vt);
}

void TerminalSession::focusChanged(bool in)
{
    if (in)
        vterm_state_focus_in(m_state);
    else
        vterm_state_focus_out(m_state);
}

void TerminalSession::setPalette(const QVector<QRgb> &sixteen, QRgb fg, QRgb bg)
{
    for (int i = 0; i < 16 && i < sixteen.size(); ++i) {
        m_palette[i] = sixteen[i];
        const VTermColor c = rgbColor(sixteen[i]);
        vterm_state_set_palette_color(m_state, i, &c);
    }
    const VTermColor f = rgbColor(fg), b = rgbColor(bg);
    vterm_screen_set_default_colors(m_screen, &f, &b);
    emit contentChanged();
}

QRgb TerminalSession::paletteColor(int index) const
{
    return m_palette.value(index & 0xFF);
}

// ——— Czytanie ———

void TerminalSession::readOutput()
{
    char buf[65536];
    qint64 total = 0;
    // Porcjami: przy zalewie danych (cat dużego pliku) okno nadal się odświeża i reaguje
    while (total < 1024 * 1024) {
        const ssize_t n = ::read(m_fd, buf, sizeof buf);
        if (n > 0) {
            vterm_input_write(m_vt, buf, size_t(n));
            total += n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && errno == EAGAIN)
            break;
        // 0 albo EIO: program zamknął terminal
        vterm_screen_flush_damage(m_screen);
        emit contentChanged();
        childGone();
        return;
    }
    vterm_screen_flush_damage(m_screen);
    if (m_pushedInBatch) {
        emit historyPushed(m_pushedInBatch);
        m_pushedInBatch = 0;
    }
    if (m_dirty) {
        m_dirty = false;
        emit contentChanged();
    }
}

void TerminalSession::childGone()
{
    if (m_readNotifier)
        m_readNotifier->setEnabled(false);
    if (m_writeNotifier)
        m_writeNotifier->setEnabled(false);
    m_poll.stop();
    if (m_fd >= 0) {
        ::close(m_fd);
        m_fd = -1;
    }
    // Proces mógł zamknąć terminal chwilę przed zakończeniem — czekamy na niego krótko
    int status = 0;
    pid_t r = 0;
    for (int i = 0; i < 50 && (r = ::waitpid(m_pid, &status, WNOHANG)) == 0; ++i)
        ::usleep(10000);
    if (r == 0) {
        ::kill(m_pid, SIGHUP);
        r = ::waitpid(m_pid, &status, 0);
    }
    if (r == m_pid)
        m_exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
    m_pid = -1;
    if (!m_program.isEmpty()) {
        m_program.clear();
        emit programChanged();
    }
    emit finished(m_exitCode);
}

// Katalog powłoki i program na pierwszym planie — z /proc
void TerminalSession::pollProcess()
{
    if (m_pid <= 0 || m_fd < 0)
        return;
    const QString cwd = QFileInfo(QStringLiteral("/proc/%1/cwd").arg(m_pid)).symLinkTarget();
    if (!cwd.isEmpty() && cwd != m_cwd) {
        m_cwd = cwd;
        emit directoryChanged();
    }
    QString program;
    const pid_t pg = ::tcgetpgrp(m_fd);
    if (pg > 0 && pg != m_pid) {
        QFile comm(QStringLiteral("/proc/%1/comm").arg(pg));
        if (comm.open(QIODevice::ReadOnly))
            program = QString::fromUtf8(comm.readAll()).trimmed();
    }
    if (program != m_program) {
        m_program = program;
        emit programChanged();
    }
}

// ——— Wywołania z libvterm ———

int TerminalSession::cbDamage(VTermRect, void *user)
{
    static_cast<TerminalSession *>(user)->m_dirty = true;
    return 1;
}

int TerminalSession::cbMoveCursor(VTermPos pos, VTermPos, int visible, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    s->m_cursorRow = pos.row;
    s->m_cursorCol = pos.col;
    s->m_cursorVisible = visible;
    s->m_dirty = true;
    emit s->cursorChanged();
    return 1;
}

int TerminalSession::cbSetTermProp(VTermProp prop, VTermValue *val, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    switch (prop) {
    case VTERM_PROP_CURSORVISIBLE:
        s->m_cursorVisible = val->boolean;
        emit s->cursorChanged();
        break;
    case VTERM_PROP_CURSORBLINK:
        s->m_cursorBlink = val->boolean;
        emit s->cursorChanged();
        break;
    case VTERM_PROP_CURSORSHAPE:
        s->m_cursorShape = val->number;
        emit s->cursorChanged();
        break;
    case VTERM_PROP_ALTSCREEN:
        s->m_altScreen = val->boolean;
        emit s->modesChanged();
        break;
    case VTERM_PROP_MOUSE:
        s->m_mouseMode = val->number;
        emit s->modesChanged();
        break;
    case VTERM_PROP_REVERSE:
        s->m_reverse = val->boolean;
        s->m_dirty = true;
        break;
    case VTERM_PROP_TITLE:
        if (val->string.initial)
            s->m_titleBuf.clear();
        s->m_titleBuf.append(val->string.str, int(val->string.len));
        if (val->string.final) {
            s->m_title = QString::fromUtf8(s->m_titleBuf);
            emit s->titleChanged();
        }
        break;
    default:
        break;
    }
    return 1;
}

int TerminalSession::cbBell(void *user)
{
    emit static_cast<TerminalSession *>(user)->bell();
    return 1;
}

int TerminalSession::cbPushLine(int cols, const VTermScreenCell *cells, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    Line l;
    // Bez pustego ogona — historia zajmuje mniej pamięci
    int used = cols;
    while (used > 0 && cells[used - 1].chars[0] == 0 && VTERM_COLOR_IS_DEFAULT_BG(&cells[used - 1].bg)
           && !cells[used - 1].attrs.reverse)
        --used;
    l.cells.resize(used);
    for (int i = 0; i < used; ++i) {
        l.cells[i] = s->convert(cells[i]);
        if (i > 0 && l.cells[i - 1].width == 2)
            l.cells[i].width = 0;
    }
    l.wrapped = used == cols && cells[cols - 1].chars[0] != 0;
    s->m_history.push_back(std::move(l));
    if (int(s->m_history.size()) > s->m_historyLimit) {
        s->m_history.pop_front();
        ++s->m_dropped;
    }
    ++s->m_pushedInBatch;
    s->m_dirty = true;
    return 1;
}

int TerminalSession::cbPopLine(int cols, VTermScreenCell *cells, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    if (s->m_history.empty())
        return 0;
    const Line l = std::move(s->m_history.back());
    s->m_history.pop_back();
    VTermColor dfg, dbg;
    vterm_state_get_default_colors(s->m_state, &dfg, &dbg);
    const auto color = [](quint32 c, const VTermColor &def) {
        VTermColor v = def;
        if ((c & ColorTypeMask) == ColorIndexed)
            vterm_color_indexed(&v, quint8(c & 0xFF));
        else if ((c & ColorTypeMask) == ColorRgb)
            vterm_color_rgb(&v, quint8((c >> 16) & 0xFF), quint8((c >> 8) & 0xFF), quint8(c & 0xFF));
        return v;
    };
    for (int i = 0; i < cols; ++i) {
        VTermScreenCell &v = cells[i];
        v = VTermScreenCell{};
        if (i < l.cells.size()) {
            const Cell &c = l.cells[i];
            v.chars[0] = c.width == 0 ? uint32_t(-1) : c.ch;
            v.width = char(qMax(1, int(c.width)));
            v.attrs.bold = (c.flags & Bold) != 0;
            v.attrs.italic = (c.flags & Italic) != 0;
            v.attrs.underline = (c.flags & Underline) ? VTERM_UNDERLINE_SINGLE : (c.flags & DoubleUnderline) ? VTERM_UNDERLINE_DOUBLE
                              : (c.flags & CurlyUnderline) ? VTERM_UNDERLINE_CURLY : VTERM_UNDERLINE_OFF;
            v.attrs.strike = (c.flags & Strike) != 0;
            v.attrs.reverse = (c.flags & Reverse) != 0;
            v.attrs.conceal = (c.flags & Conceal) != 0;
            v.attrs.blink = (c.flags & Blink) != 0;
            v.fg = color(c.fg, dfg);
            v.bg = color(c.bg, dbg);
        } else {
            v.width = 1;
            v.fg = dfg;
            v.bg = dbg;
        }
    }
    s->m_dirty = true;
    return 1;
}

int TerminalSession::cbClearHistory(void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    s->m_dropped += qint64(s->m_history.size());
    s->m_history.clear();
    emit s->historyCleared();
    s->m_dirty = true;
    return 1;
}

// OSC 7: powłoka podaje katalog jako file://host/ścieżka
int TerminalSession::cbOsc(int command, VTermStringFragment frag, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    if (command != 7)
        return 0;
    if (frag.initial)
        s->m_oscBuf.clear();
    s->m_oscBuf.append(frag.str, int(frag.len));
    if (frag.final) {
        const QUrl url(QString::fromUtf8(s->m_oscBuf));
        if (url.isLocalFile() && url.toLocalFile() != s->m_cwd) {
            s->m_cwd = url.toLocalFile();
            emit s->directoryChanged();
        }
    }
    return 1;
}

int TerminalSession::cbSelectionSet(VTermSelectionMask mask, VTermStringFragment frag, void *user)
{
    auto *s = static_cast<TerminalSession *>(user);
    if (frag.initial)
        s->m_clipBuf.clear();
    s->m_clipBuf.append(frag.str, int(frag.len));
    if (frag.final && (mask & (VTERM_SELECTION_CLIPBOARD | VTERM_SELECTION_PRIMARY | VTERM_SELECTION_SELECT)))
        emit s->clipboardRequested(QString::fromUtf8(s->m_clipBuf));
    return 1;
}

// Programy nie czytają schowka (ochrona przed wykradaniem danych)
int TerminalSession::cbSelectionQuery(VTermSelectionMask, void *)
{
    return 1;
}

void TerminalSession::cbOutput(const char *s, size_t len, void *user)
{
    static_cast<TerminalSession *>(user)->write(QByteArray(s, qsizetype(len)));
}

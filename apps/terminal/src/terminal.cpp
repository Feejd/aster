#include "terminal.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QUrl>

#include <pwd.h>
#include <unistd.h>

Terminal *Terminal::s_instance = nullptr;

namespace {

struct Scheme {
    const char *id;
    const char *name;
    const char *hint;
    const char *fg, *bg, *cursor;
    const char *palette[16];
};

// Schematy kolorów. „Aster” ma dwie odmiany i idzie za jasnym/ciemnym motywem systemu;
// tło ciemnej to ta sama głęboka czerń, co panele w innych oknach Aster.
const Scheme schemeList[] = {
    {"aster-dark", "Aster", "", "#E6E8EE", "#090A0D", "",
     {"#1C1E26", "#FF6B7A", "#7EE0A0", "#F5D07A", "#6EA8FF", "#C79BFF", "#67E1E6", "#C9CED8",
      "#5C6370", "#FF8B96", "#9BF0B8", "#FFE09A", "#8DBBFF", "#D8B4FF", "#8EEBEE", "#F4F6FA"}},
    {"aster-light", "Aster", "", "#1E2128", "#FFFFFF", "",
     {"#1E2128", "#D7263D", "#1A8F4C", "#A86A00", "#2459D6", "#8E3FD1", "#0B8796", "#8A909C",
      "#5C6370", "#E5484D", "#22A35A", "#C27C00", "#3B6EF0", "#A855F7", "#0E9FB0", "#B5BAC4"}},
    {"midnight", "Północ", "granat", "#D8DEE9", "#0E1524", "#82AAFF",
     {"#1B2333", "#F07178", "#A3D9A5", "#EBCB8B", "#82AAFF", "#C792EA", "#89DDFF", "#D8DEE9",
      "#4C5A75", "#FF8F96", "#BFE8C0", "#F5DCA6", "#A5C2FF", "#DDB4F5", "#AEE8FF", "#F2F5FA"}},
    {"graphite", "Grafit", "szarość", "#E3E3E6", "#1D1E22", "#E3E3E6",
     {"#2A2B30", "#F2777A", "#99CC99", "#FFCC66", "#6699CC", "#CC99CC", "#66CCCC", "#D3D3D7",
      "#6B6D75", "#F99A9C", "#B5DDB5", "#FFDA8A", "#8FB6DE", "#DDB6DD", "#8ADBDB", "#F5F5F7"}},
    {"paper", "Papier", "ciepły jasny", "#3B3833", "#FBF7EF", "#C2410C",
     {"#3B3833", "#B8312F", "#4E7D2D", "#9A6B00", "#2F5D9E", "#8A3D8F", "#2A7F80", "#A39E93",
      "#6E6A61", "#D2443F", "#5E9636", "#B98200", "#3D73BF", "#A44FA9", "#349A9B", "#C9C3B6"}},
    {"classic", "Klasyczny", "jak w Windows", "#CCCCCC", "#0C0C0C", "#FFFFFF",
     {"#0C0C0C", "#C50F1F", "#13A10E", "#C19C00", "#0037DA", "#881798", "#3A96DD", "#CCCCCC",
      "#767676", "#E74856", "#16C60C", "#F9F1A5", "#3B78FF", "#B4009E", "#61D6D6", "#F2F2F2"}},
};

const Scheme *findScheme(const QString &id)
{
    for (const Scheme &s : schemeList)
        if (id == QLatin1String(s.id))
            return &s;
    return nullptr;
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

} // namespace

Terminal::Terminal(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    s_instance = this;
    // Czcionka: pierwsza zainstalowana z listy (JetBrains Mono jest w obrazie Aster)
    const QStringList families = QFontDatabase::families();
    for (const char *f : {"JetBrains Mono", "Geist Mono", "Adwaita Mono", "Noto Sans Mono", "Hack", "DejaVu Sans Mono", "Liberation Mono"})
        if (families.contains(QLatin1String(f))) {
            m_defaultFont = QLatin1String(f);
            break;
        }
    if (m_defaultFont.isEmpty())
        m_defaultFont = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
}

Terminal *Terminal::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

QVariant Terminal::value(const char *key, const QVariant &def) const
{
    return m_settings.value(QLatin1String(key), def);
}

void Terminal::set(const char *key, const QVariant &v)
{
    if (m_settings.value(QLatin1String(key)) == v)
        return;
    m_settings.setValue(QLatin1String(key), v);
    emit settingsChanged();
}

QString Terminal::fontFamily() const
{
    const QString f = value("font", QString()).toString();
    return f.isEmpty() ? m_defaultFont : f;
}
void Terminal::setFontFamily(const QString &f) { set("font", f == m_defaultFont ? QString() : f); }
qreal Terminal::fontSize() const { return value("fontSize", 14).toReal(); }
void Terminal::setFontSize(qreal s) { set("fontSize", qBound(8.0, s, 40.0)); }
qreal Terminal::lineHeight() const { return value("lineHeight", 1.2).toReal(); }
void Terminal::setLineHeight(qreal h) { set("lineHeight", qBound(1.0, h, 1.6)); }
QString Terminal::scheme() const { return value("scheme", QStringLiteral("aster")).toString(); }
void Terminal::setScheme(const QString &s) { set("scheme", s); }
int Terminal::cursorStyle() const { return value("cursor", 3).toInt(); }
void Terminal::setCursorStyle(int s) { set("cursor", qBound(1, s, 3)); }
bool Terminal::cursorBlink() const { return value("cursorBlink", true).toBool(); }
void Terminal::setCursorBlink(bool on) { set("cursorBlink", on); }
int Terminal::historyLines() const { return value("history", 10000).toInt(); }
void Terminal::setHistoryLines(int n) { set("history", n); }
bool Terminal::newTabHere() const { return value("newTabHere", true).toBool(); }
void Terminal::setNewTabHere(bool on) { set("newTabHere", on); }
bool Terminal::visualBell() const { return value("visualBell", true).toBool(); }
void Terminal::setVisualBell(bool on) { set("visualBell", on); }
bool Terminal::confirmClose() const { return value("confirmClose", true).toBool(); }
void Terminal::setConfirmClose(bool on) { set("confirmClose", on); }
bool Terminal::copyOnSelect() const { return value("copyOnSelect", false).toBool(); }
void Terminal::setCopyOnSelect(bool on) { set("copyOnSelect", on); }
bool Terminal::notifyDone() const { return value("notifyDone", true).toBool(); }
void Terminal::setNotifyDone(bool on) { set("notifyDone", on); }

void Terminal::resetSettings()
{
    m_settings.clear();
    emit settingsChanged();
}

QVariantList Terminal::schemes() const
{
    QVariantList l;
    for (const Scheme &s : schemeList) {
        if (QLatin1String(s.id) == QLatin1String("aster-light"))
            continue;
        const QString id = QLatin1String(s.id) == QLatin1String("aster-dark") ? QStringLiteral("aster") : QLatin1String(s.id);
        l << QVariantMap{{QStringLiteral("id"), id},
                         {QStringLiteral("name"), QString::fromUtf8(s.name)},
                         {QStringLiteral("hint"), id == QLatin1String("aster") ? QStringLiteral("jak system") : QString::fromUtf8(s.hint)}};
    }
    return l;
}

QVariantMap Terminal::colors(const QString &id, bool dark) const
{
    const Scheme *s = findScheme(id == QLatin1String("aster") ? (dark ? QStringLiteral("aster-dark") : QStringLiteral("aster-light")) : id);
    if (!s)
        s = findScheme(dark ? QStringLiteral("aster-dark") : QStringLiteral("aster-light"));
    QVariantList palette;
    for (const char *c : s->palette)
        palette << QColor(QLatin1String(c));
    const QColor bg(QLatin1String(s->bg));
    return {{QStringLiteral("foreground"), QColor(QLatin1String(s->fg))},
            {QStringLiteral("background"), bg},
            {QStringLiteral("cursor"), QString::fromLatin1(s->cursor)},
            {QStringLiteral("dark"), bg.lightnessF() < 0.5},
            {QStringLiteral("palette"), palette}};
}

QStringList Terminal::fonts() const
{
    // Czcionki o stałej szerokości znaków (bez wariantów symboli i ozdobnych)
    QStringList out;
    for (const QString &f : QFontDatabase::families()) {
        if (!QFontDatabase::isFixedPitch(f) || QFontDatabase::isPrivateFamily(f))
            continue;
        if (f.contains(QLatin1String("Symbol"), Qt::CaseInsensitive) || f.contains(QLatin1String("Emoji"), Qt::CaseInsensitive)
            || f.contains(QLatin1String("Math"), Qt::CaseInsensitive) || f.contains(QLatin1String("NL ")))
            continue;
        out << f;
    }
    if (!out.contains(m_defaultFont))
        out.prepend(m_defaultFont);
    return out;
}

QString Terminal::defaultFont() const { return m_defaultFont; }

QString Terminal::shellName() const
{
    QString shell = qEnvironmentVariable("SHELL");
    if (shell.isEmpty())
        if (const passwd *pw = ::getpwuid(::getuid()); pw && pw->pw_shell)
            shell = QString::fromLocal8Bit(pw->pw_shell);
    return QFileInfo(shell.isEmpty() ? QStringLiteral("bash") : shell).fileName();
}

QString Terminal::version() const { return QCoreApplication::applicationVersion(); }

QQuickWindow *Terminal::openWindow(const QString &dir, const QStringList &command)
{
    QQmlComponent component(m_engine, QStringLiteral("Aster.Terminal"), QStringLiteral("Main"));
    QObject *obj = component.createWithInitialProperties({{QStringLiteral("startDir"), dir},
                                                          {QStringLiteral("startCommand"), command}});
    auto *window = qobject_cast<QQuickWindow *>(obj);
    if (!window) {
        qWarning("%s", qPrintable(component.errorString()));
        delete obj;
        return nullptr;
    }
    // Okno zwalnia się samo po zamknięciu
    connect(window, &QWindow::visibleChanged, window, [window] {
        if (!window->isVisible())
            window->deleteLater();
    });
    return window;
}

QString Terminal::prettyPath(const QString &path) const
{
    const QString home = QDir::homePath();
    if (path == home)
        return QStringLiteral("~");
    if (path.startsWith(home + QLatin1Char('/')))
        return QStringLiteral("~") + path.mid(home.size());
    return path;
}

QString Terminal::folderName(const QString &path) const
{
    if (path.isEmpty() || path == QDir::homePath())
        return QStringLiteral("~");
    if (path == QLatin1String("/"))
        return path;
    return QFileInfo(path).fileName();
}

QString Terminal::quotePaths(const QVariantList &urls) const
{
    QStringList out;
    for (const QVariant &v : urls) {
        const QUrl u = v.toUrl();
        out << shellQuote(u.isLocalFile() ? u.toLocalFile() : u.toString());
    }
    return out.join(QLatin1Char(' '));
}

void Terminal::notify(const QString &title, const QString &body)
{
    static const QString service = QStringLiteral("org.freedesktop.Notifications");
    static const QString path = QStringLiteral("/org/freedesktop/Notifications");
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("Notify"));
    msg << QStringLiteral("Terminal") << uint(0) << QStringLiteral("utilities-terminal") << title << body << QStringList()
        << QVariantMap{{QStringLiteral("desktop-entry"), QStringLiteral("org.aster.terminal")}} << int(-1);
    QDBusConnection::sessionBus().asyncCall(msg);
}

#include "processmodel.h"

#include <KService>
#include <KShell>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <algorithm>
#include <pwd.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

QByteArray readAll(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

qint64 nowMs()
{
    static QElapsedTimer t;
    if (!t.isValid())
        t.start();
    return t.elapsed();
}

// Znane procesy w tle i systemu — po ludzku (klucz: nazwa pliku programu)
const QHash<QString, QString> &friendlyNames()
{
    static const QHash<QString, QString> names{
        {QStringLiteral("aster-shell"), QStringLiteral("Powłoka Aster")},
        {QStringLiteral("aster-portal"), QStringLiteral("Okna „Otwórz / Zapisz” Aster")},
        {QStringLiteral("kwin_wayland"), QStringLiteral("Menedżer okien (KWin)")},
        {QStringLiteral("kwin_wayland_wrapper"), QStringLiteral("Uruchamianie menedżera okien")},
        {QStringLiteral("Xwayland"), QStringLiteral("Zgodność ze starszymi programami (Xwayland)")},
        {QStringLiteral("pipewire"), QStringLiteral("Dźwięk i obraz (PipeWire)")},
        {QStringLiteral("pipewire-pulse"), QStringLiteral("Dźwięk dla starszych programów (PulseAudio)")},
        {QStringLiteral("wireplumber"), QStringLiteral("Sterowanie dźwiękiem (WirePlumber)")},
        {QStringLiteral("systemd"), QStringLiteral("Menedżer usług (systemd)")},
        {QStringLiteral("dbus-broker"), QStringLiteral("Komunikacja między programami (D-Bus)")},
        {QStringLiteral("dbus-broker-launch"), QStringLiteral("Komunikacja między programami (D-Bus)")},
        {QStringLiteral("dbus-daemon"), QStringLiteral("Komunikacja między programami (D-Bus)")},
        {QStringLiteral("NetworkManager"), QStringLiteral("Sieć (NetworkManager)")},
        {QStringLiteral("wpa_supplicant"), QStringLiteral("Łączenie z Wi‑Fi")},
        {QStringLiteral("bluetoothd"), QStringLiteral("Bluetooth")},
        {QStringLiteral("sddm"), QStringLiteral("Ekran logowania")},
        {QStringLiteral("sddm-helper"), QStringLiteral("Ekran logowania — sesja")},
        {QStringLiteral("polkitd"), QStringLiteral("Uprawnienia administratora (polkit)")},
        {QStringLiteral("kded6"), QStringLiteral("Usługi KDE w tle")},
        {QStringLiteral("ksmserver"), QStringLiteral("Menedżer sesji")},
        {QStringLiteral("kscreenlocker_greet"), QStringLiteral("Ekran blokady")},
        {QStringLiteral("startplasma-wayland"), QStringLiteral("Uruchamianie sesji")},
        {QStringLiteral("plasma_session"), QStringLiteral("Sesja użytkownika")},
        {QStringLiteral("xdg-desktop-portal"), QStringLiteral("Portal systemowy")},
        {QStringLiteral("xdg-desktop-portal-kde"), QStringLiteral("Portal systemowy KDE")},
        {QStringLiteral("xdg-desktop-portal-gtk"), QStringLiteral("Portal systemowy GTK")},
        {QStringLiteral("xdg-document-portal"), QStringLiteral("Udostępnianie plików programom")},
        {QStringLiteral("xdg-permission-store"), QStringLiteral("Uprawnienia programów")},
        {QStringLiteral("org_kde_powerdevil"), QStringLiteral("Zarządzanie energią")},
        {QStringLiteral("upowerd"), QStringLiteral("Bateria i zasilanie (UPower)")},
        {QStringLiteral("udisksd"), QStringLiteral("Dyski i pendrive’y (UDisks)")},
        {QStringLiteral("systemd-journald"), QStringLiteral("Dziennik systemu")},
        {QStringLiteral("systemd-logind"), QStringLiteral("Logowanie i sesje")},
        {QStringLiteral("systemd-udevd"), QStringLiteral("Wykrywanie urządzeń (udev)")},
        {QStringLiteral("systemd-resolved"), QStringLiteral("Nazwy stron (DNS)")},
        {QStringLiteral("systemd-oomd"), QStringLiteral("Ochrona przed brakiem pamięci")},
        {QStringLiteral("systemd-userdbd"), QStringLiteral("Baza użytkowników")},
        {QStringLiteral("firewalld"), QStringLiteral("Zapora sieciowa")},
        {QStringLiteral("chronyd"), QStringLiteral("Synchronizacja zegara")},
        {QStringLiteral("cupsd"), QStringLiteral("Drukowanie (CUPS)")},
        {QStringLiteral("accounts-daemon"), QStringLiteral("Konta użytkowników")},
        {QStringLiteral("baloo_file"), QStringLiteral("Indeksowanie plików do wyszukiwania")},
        {QStringLiteral("kwalletd6"), QStringLiteral("Portfel haseł")},
        {QStringLiteral("kdeconnectd"), QStringLiteral("Połączenie z telefonem (KDE Connect)")},
        {QStringLiteral("gvfsd"), QStringLiteral("Dostęp do dysków sieciowych")},
        {QStringLiteral("rtkit-daemon"), QStringLiteral("Priorytety dźwięku")},
        {QStringLiteral("packagekitd"), QStringLiteral("Aktualizacje i instalacja programów")},
        {QStringLiteral("flatpak-session-helper"), QStringLiteral("Programy z Flathuba — pomocnik")},
        {QStringLiteral("flatpak-portal"), QStringLiteral("Programy z Flathuba — portal")},
        {QStringLiteral("gnome-keyring-daemon"), QStringLiteral("Pęk kluczy")},
        {QStringLiteral("agetty"), QStringLiteral("Konsola tekstowa")},
        {QStringLiteral("sshd"), QStringLiteral("Zdalne logowanie (SSH)")},
        {QStringLiteral("crond"), QStringLiteral("Zadania zaplanowane")},
        {QStringLiteral("auditd"), QStringLiteral("Dziennik bezpieczeństwa")},
        {QStringLiteral("abrtd"), QStringLiteral("Zgłaszanie awarii")},
        {QStringLiteral("smartd"), QStringLiteral("Stan dysków (SMART)")},
        {QStringLiteral("thermald"), QStringLiteral("Temperatura procesora")},
        {QStringLiteral("power-profiles-daemon"), QStringLiteral("Tryby zasilania")},
        {QStringLiteral("tuned"), QStringLiteral("Tryby zasilania")},
        {QStringLiteral("tuned-ppd"), QStringLiteral("Tryby zasilania")},
        {QStringLiteral("geoclue"), QStringLiteral("Lokalizacja")},
        {QStringLiteral("avahi-daemon"), QStringLiteral("Wykrywanie urządzeń w sieci")},
        {QStringLiteral("ModemManager"), QStringLiteral("Modemy i sieć komórkowa")},
        {QStringLiteral("fwupd"), QStringLiteral("Aktualizacje oprogramowania sprzętu")},
    };
    return names;
}

// Bez nich sesja się sypie — przed zakończeniem ostrzegamy
const QSet<QString> &criticalNames()
{
    static const QSet<QString> names{
        QStringLiteral("systemd"), QStringLiteral("kwin_wayland"), QStringLiteral("kwin_wayland_wrapper"), QStringLiteral("Xwayland"),
        QStringLiteral("startplasma-wayland"), QStringLiteral("plasma_session"), QStringLiteral("ksmserver"), QStringLiteral("sddm"),
        QStringLiteral("sddm-helper"), QStringLiteral("dbus-broker"), QStringLiteral("dbus-broker-launch"), QStringLiteral("dbus-daemon"),
        QStringLiteral("systemd-logind"), QStringLiteral("systemd-journald"), QStringLiteral("kscreenlocker_greet"), QStringLiteral("aster-shell"),
    };
    return names;
}

// Te programy z menu Start uruchamiają inne — po ich pliku nie zgadujemy, czyj to proces
const QSet<QString> &launcherNames()
{
    static const QSet<QString> names{
        QStringLiteral("sh"), QStringLiteral("bash"), QStringLiteral("env"), QStringLiteral("flatpak"), QStringLiteral("python3"),
        QStringLiteral("python"), QStringLiteral("perl"), QStringLiteral("java"), QStringLiteral("gjs"), QStringLiteral("kioclient"),
        QStringLiteral("kioclient5"), QStringLiteral("kde-open"), QStringLiteral("xdg-open"), QStringLiteral("systemctl"), QStringLiteral("sudo"),
        QStringLiteral("pkexec"), QStringLiteral("kstart"), QStringLiteral("plasmawindowed"), QStringLiteral("qdbus"), QStringLiteral("dbus-send"),
        QStringLiteral("gio"), QStringLiteral("mono"), QStringLiteral("wine"), QStringLiteral("steam-runtime"),
    };
    return names;
}

QString unescapeUnit(QString s)
{
    // systemd zapisuje znaki spoza nazwy jako \xNN (np. myślnik w identyfikatorze programu)
    int i;
    while ((i = s.indexOf(QLatin1String("\\x"))) >= 0 && i + 4 <= s.size()) {
        bool ok = false;
        const int code = s.mid(i + 2, 2).toInt(&ok, 16);
        if (!ok)
            break;
        s.replace(i, 4, QChar(code));
    }
    return s;
}

QString stateText(char s)
{
    switch (s) {
    case 'R': return QStringLiteral("Działa");
    case 'D': return QStringLiteral("Czeka na dysk");
    case 'T': case 't': return QStringLiteral("Wstrzymany");
    case 'Z': return QStringLiteral("Zakończony (czeka na rodzica)");
    case 'I': return QStringLiteral("Bezczynny");
    default: return QStringLiteral("Czeka");
    }
}

} // namespace

ProcessModel::ProcessModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_uid(getuid())
    , m_self(getpid())
    , m_hz(sysconf(_SC_CLK_TCK))
    , m_cpus(std::max(1L, sysconf(_SC_NPROCESSORS_ONLN)))
{
    // Programy z menu Start: nazwa pliku z Exec= → id programu
    const KService::List all = KService::allServices();
    for (const KService::Ptr &s : all) {
        if (!s->isApplication() || s->noDisplay())
            continue;
        QStringList args = KShell::splitArgs(s->exec());
        while (!args.isEmpty() && (args.first() == QLatin1String("env") || args.first().contains(QLatin1Char('='))))
            args.removeFirst();
        if (args.isEmpty())
            continue;
        const QString base = QFileInfo(args.first()).fileName();
        if (base.isEmpty() || launcherNames().contains(base))
            continue;
        QString id = s->storageId();
        if (id.endsWith(QLatin1String(".desktop")))
            id.chop(8);
        if (!m_exeMap.contains(base))
            m_exeMap.insert(base, id);
        m_apps.insert(id, App{id, s->name(), s->icon()});
    }
    m_collapsed.insert(QStringLiteral("system"));
}

int ProcessModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant ProcessModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Row &r = m_rows.at(index.row());
    switch (role) {
    case KindRole: return r.kind;
    case KeyRole: return r.key;
    case SectionRole: return r.section;
    case DepthRole: return r.depth;
    case PidRole: return r.pid;
    case Qt::DisplayRole:
    case NameRole: return r.name;
    case IconRole: return r.icon;
    case DesktopIdRole: return r.desktopId;
    case CpuRole: return r.cpu;
    case MemRole: return double(r.mem);
    case DiskRole: return r.disk;
    case CountRole: return r.count;
    case ExpandedRole: return r.expanded;
    case CriticalRole: return r.critical;
    case SystemRole: return r.system;
    case UserRole: return r.user;
    }
    return {};
}

QHash<int, QByteArray> ProcessModel::roleNames() const
{
    return {{KindRole, "kind"}, {KeyRole, "key"}, {SectionRole, "section"}, {DepthRole, "depth"}, {PidRole, "pid"},
            {NameRole, "name"}, {IconRole, "iconName"}, {DesktopIdRole, "desktopId"}, {CpuRole, "cpu"}, {MemRole, "mem"},
            {DiskRole, "disk"}, {CountRole, "count"}, {ExpandedRole, "expanded"}, {CriticalRole, "critical"},
            {SystemRole, "system"}, {UserRole, "user"}};
}

void ProcessModel::setSortKey(const QString &key)
{
    if (key == m_sortKey)
        return;
    m_sortKey = key;
    m_desc = key != QLatin1String("name");      // liczby — od największych, nazwy — alfabetycznie
    Q_EMIT sortChanged();
    rebuild();
}

void ProcessModel::setSortDescending(bool d)
{
    if (d == m_desc)
        return;
    m_desc = d;
    Q_EMIT sortChanged();
    rebuild();
}

void ProcessModel::setFilter(const QString &f)
{
    if (f == m_filter)
        return;
    m_filter = f;
    Q_EMIT filterChanged();
    rebuild();
}

const ProcessModel::App *ProcessModel::app(const QString &id) const
{
    if (id.isEmpty())
        return nullptr;
    auto it = m_apps.constFind(id);
    if (it != m_apps.constEnd())
        return it->id.isEmpty() ? nullptr : &*it;
    KService::Ptr s = KService::serviceByStorageId(id + QLatin1String(".desktop"));
    if (!s)
        s = KService::serviceByDesktopName(id);
    App a;
    if (s && s->isApplication() && !s->noDisplay()) {
        a.id = s->storageId();
        if (a.id.endsWith(QLatin1String(".desktop")))
            a.id.chop(8);
        a.name = s->name();
        a.icon = s->icon();
    }
    return &*m_apps.insert(id, a);
}

QString ProcessModel::appForScope(const QString &cgroupLine) const
{
    // „0::/user.slice/…/app.slice/app-org.kde.kate-1234.scope” albo „…/app-firefox@ab12.service”
    QString unit = cgroupLine.section(QLatin1Char('/'), -1).trimmed();
    if (!unit.startsWith(QLatin1String("app-")))
        return {};
    unit = unit.mid(4);
    if (unit.endsWith(QLatin1String(".scope")))
        unit.chop(6);
    else if (unit.endsWith(QLatin1String(".service")))
        unit.chop(8);
    else
        return {};
    if (const int at = unit.indexOf(QLatin1Char('@')); at >= 0)
        unit.truncate(at);
    if (unit.startsWith(QLatin1String("flatpak-")))
        unit = unit.mid(8);
    if (unit.startsWith(QLatin1String("dbus")))
        return {};
    // Na końcu bywa losowy dopisek („-1234”, „-a8b9…”) — odcinamy, aż trafimy na program
    QString candidate = unit;
    for (int guard = 0; guard < 6 && !candidate.isEmpty(); ++guard) {
        if (const App *a = app(unescapeUnit(candidate)))
            return a->id;
        const int dash = candidate.lastIndexOf(QLatin1Char('-'));
        if (dash <= 0)
            break;
        candidate.truncate(dash);
    }
    return {};
}

bool ProcessModel::readProc(int pid, Proc &p, bool first)
{
    const QString dir = QStringLiteral("/proc/%1/").arg(pid);
    const QByteArray stat = readAll(dir + QLatin1String("stat"));
    const int open = stat.indexOf('('), close = stat.lastIndexOf(')');
    if (open < 0 || close < open)
        return false;
    const QList<QByteArray> f = stat.mid(close + 2).split(' ');
    if (f.size() < 22)
        return false;
    const qulonglong start = f.at(19).toULongLong();
    if (!first && start != p.start)
        return false;                       // ten PID to już inny proces
    p.pid = pid;
    p.state = f.at(0).isEmpty() ? 'S' : f.at(0).at(0);
    p.ppid = f.at(1).toInt();
    p.ticks = f.at(11).toULongLong() + f.at(12).toULongLong();
    p.threads = f.at(17).toInt();
    p.start = start;

    const QList<QByteArray> statm = readAll(dir + QLatin1String("statm")).split(' ');
    if (statm.size() > 2)
        p.mem = (statm.at(1).toLongLong() - statm.at(2).toLongLong()) * sysconf(_SC_PAGESIZE);   // pamięć anonimowa (prywatna)

    if (first) {
        p.comm = QString::fromUtf8(stat.mid(open + 1, close - open - 1));
        struct stat st;
        if (::stat(QFile::encodeName(dir).constData(), &st) == 0)
            p.uid = st.st_uid;
        QByteArray cmd = readAll(dir + QLatin1String("cmdline"));
        while (cmd.endsWith('\0'))
            cmd.chop(1);
        const QByteArray arg0 = cmd.left(cmd.indexOf('\0') < 0 ? cmd.size() : cmd.indexOf('\0'));
        cmd.replace('\0', ' ');
        p.cmdline = QString::fromUtf8(cmd);
        p.exe = QFileInfo(dir + QLatin1String("exe")).symLinkTarget();
        if (p.exe.endsWith(QLatin1String(" (deleted)")))
            p.exe.chop(10);
        // Nazwa: plik programu (comm bywa ucięta do 15 znaków), dla Chromium/Electron — comm („chrome”, „Isolated Web Co”)
        const QString base0 = QFileInfo(QString::fromUtf8(arg0).section(QLatin1Char(' '), 0, 0)).fileName();
        p.name = base0.startsWith(p.comm) ? base0 : p.comm;
        if (p.uid == m_uid) {
            for (const QString &b : {QFileInfo(p.exe).fileName(), base0}) {
                if (const QString id = m_exeMap.value(b); !id.isEmpty()) {
                    p.exeApp = id;
                    break;
                }
            }
            const QByteArray cg = readAll(dir + QLatin1String("cgroup"));
            for (const QByteArray &line : cg.split('\n'))
                if (line.startsWith("0::")) {
                    p.scopeApp = appForScope(QString::fromUtf8(line));
                    break;
                }
        }
    }

    const QByteArray io = readAll(dir + QLatin1String("io"));
    p.rd = p.wr = 0;
    for (const QByteArray &line : io.split('\n')) {
        if (line.startsWith("read_bytes:"))
            p.rd = line.mid(11).trimmed().toULongLong();
        else if (line.startsWith("write_bytes:"))
            p.wr = line.mid(12).trimmed().toULongLong();
    }
    return true;
}

void ProcessModel::refresh()
{
    const qint64 now = nowMs();
    const double secs = m_lastMs ? std::max(0.05, (now - m_lastMs) / 1000.0) : 0;
    m_lastMs = now;

    QSet<int> alive;
    m_threads = 0;
    m_diskTotal = 0;
    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &e : entries) {
        bool ok = false;
        const int pid = e.toInt(&ok);
        if (!ok)
            continue;
        auto it = m_procs.find(pid);
        bool isNew = it == m_procs.end();
        Proc p = isNew ? Proc{} : *it;
        const qulonglong oldTicks = p.ticks, oldRd = p.rd, oldWr = p.wr;
        if (!readProc(pid, p, isNew)) {
            if (isNew)
                continue;
            p = Proc{};                         // PID przejęty przez nowy proces — wczytaj od nowa
            isNew = true;
            if (!readProc(pid, p, true))
                continue;
        }
        // Wątki jądra (rodzic: kthreadd) i zakończone procesy czekające na rodzica pomijamy — jak Windows
        if (pid == 2 || p.ppid == 2 || p.state == 'Z')
            continue;
        // Nowy proces: pierwszy odczyt bez poprzedniego — procesor i dysk policzymy przy następnym
        if (!isNew && secs > 0) {
            p.cpu = std::min(100.0, (p.ticks - std::min(p.ticks, oldTicks)) * 100.0 / (secs * m_hz * m_cpus));
            p.disk = ((p.rd - std::min(p.rd, oldRd)) + (p.wr - std::min(p.wr, oldWr))) / secs;
        }
        m_threads += p.threads;
        m_diskTotal += p.disk;
        alive.insert(pid);
        m_procs.insert(pid, p);
    }
    for (auto it = m_procs.begin(); it != m_procs.end();)
        it = alive.contains(it.key()) ? std::next(it) : m_procs.erase(it);

    QHash<int, QString> memo;
    m_group.clear();
    for (auto it = m_procs.cbegin(); it != m_procs.cend(); ++it)
        if (it->uid == m_uid)
            if (const QString g = groupOf(it.key(), memo); !g.isEmpty())
                m_group.insert(it.key(), g);

    rebuild();
    Q_EMIT updated();
}

QString ProcessModel::groupOf(int pid, QHash<int, QString> &memo, int depth) const
{
    if (auto it = memo.constFind(pid); it != memo.constEnd())
        return *it;
    auto it = m_procs.constFind(pid);
    if (it == m_procs.constEnd())
        return {};
    QString g = !it->exeApp.isEmpty() ? it->exeApp : it->scopeApp;
    if (g.isEmpty() && depth < 64 && it->ppid > 1) {
        auto parent = m_procs.constFind(it->ppid);
        if (parent != m_procs.constEnd() && parent->uid == it->uid)
            g = groupOf(it->ppid, memo, depth + 1);
    }
    memo.insert(pid, g);
    return g;
}

QString ProcessModel::displayName(const Proc &p) const
{
    if (const QString f = friendlyNames().value(p.name); !f.isEmpty())
        return f;
    if (const QString f = friendlyNames().value(p.comm); !f.isEmpty())
        return f;
    return p.name;
}

QString ProcessModel::userName(uint uid) const
{
    auto it = m_users.constFind(uid);
    if (it != m_users.constEnd())
        return *it;
    const struct passwd *pw = getpwuid(uid);
    const QString name = pw ? QString::fromLocal8Bit(pw->pw_name) : QString::number(uid);
    m_users.insert(uid, name);
    return name;
}

bool ProcessModel::isCritical(const Proc &p) const
{
    return p.pid == 1 || criticalNames().contains(p.name) || criticalNames().contains(p.comm);
}

void ProcessModel::rebuild()
{
    const QString q = m_filter.trimmed();
    auto matches = [&q](const QString &name, int pid) {
        return q.isEmpty() || name.contains(q, Qt::CaseInsensitive) || QString::number(pid) == q;
    };
    auto less = [this](const Row &a, const Row &b) {
        int c = 0;
        if (m_sortKey == QLatin1String("cpu"))
            c = a.cpu < b.cpu ? -1 : a.cpu > b.cpu ? 1 : 0;
        else if (m_sortKey == QLatin1String("mem"))
            c = a.mem < b.mem ? -1 : a.mem > b.mem ? 1 : 0;
        else if (m_sortKey == QLatin1String("disk"))
            c = a.disk < b.disk ? -1 : a.disk > b.disk ? 1 : 0;
        if (c == 0)
            c = QString::localeAwareCompare(a.name, b.name);
        if (c == 0)
            c = a.pid < b.pid ? -1 : a.pid > b.pid ? 1 : 0;
        return m_desc ? c > 0 : c < 0;
    };
    auto procRow = [this](const Proc &p, const QString &section, int depth) {
        Row r;
        r.kind = Process;
        r.key = QStringLiteral("p:%1").arg(p.pid);
        r.section = section;
        r.depth = depth;
        r.pid = p.pid;
        r.name = displayName(p);
        r.cpu = p.cpu;
        r.mem = p.mem;
        r.disk = p.disk;
        r.critical = isCritical(p);
        r.system = p.uid != m_uid;
        r.user = userName(p.uid);
        return r;
    };

    // Programy
    QHash<QString, QVector<Row>> children;
    for (auto it = m_group.cbegin(); it != m_group.cend(); ++it)
        children[it.value()].append(procRow(m_procs.value(it.key()), QStringLiteral("apps"), 1));
    QVector<QPair<Row, QVector<Row>>> groups;
    for (auto it = children.begin(); it != children.end(); ++it) {
        const App *a = app(it.key());
        Row g;
        g.kind = Group;
        g.key = QLatin1String("g:") + it.key();
        g.section = QStringLiteral("apps");
        g.name = a ? a->name : it.key();
        g.icon = a ? a->icon : QString();
        g.desktopId = it.key();
        g.count = it->size();
        g.pid = it->first().pid;
        for (const Row &c : *it) {
            g.cpu += c.cpu;
            g.mem += c.mem;
            g.disk += c.disk;
            g.pid = std::min(g.pid, c.pid);
        }
        g.user = userName(m_uid);
        QVector<Row> kids;
        const bool groupMatch = matches(g.name, -1);
        for (const Row &c : *it)
            if (groupMatch || matches(c.name, c.pid))
                kids.append(c);
        if (kids.isEmpty())
            continue;
        std::sort(kids.begin(), kids.end(), less);
        g.expanded = m_expanded.contains(g.key) || (!q.isEmpty() && !groupMatch);
        groups.append({g, kids});
    }
    std::sort(groups.begin(), groups.end(), [&less](const auto &a, const auto &b) { return less(a.first, b.first); });

    QVector<Row> background, system;
    for (auto it = m_procs.cbegin(); it != m_procs.cend(); ++it) {
        if (m_group.contains(it.key()))
            continue;
        const bool own = it->uid == m_uid;
        Row r = procRow(*it, own ? QStringLiteral("background") : QStringLiteral("system"), 0);
        if (!matches(r.name, r.pid) && !matches(it->comm, it->pid))
            continue;
        (own ? background : system).append(r);
    }
    std::sort(background.begin(), background.end(), less);
    std::sort(system.begin(), system.end(), less);

    QVector<Row> rows;
    auto header = [&](const QString &id, const QString &title, int count) {
        Row h;
        h.kind = Header;
        h.key = QLatin1String("h:") + id;
        h.section = id;
        h.name = title;
        h.count = count;
        h.expanded = !m_collapsed.contains(id) || !q.isEmpty();
        rows.append(h);
        return h.expanded;
    };
    if (!groups.isEmpty() && header(QStringLiteral("apps"), QStringLiteral("Aplikacje"), groups.size())) {
        for (const auto &[g, kids] : std::as_const(groups)) {
            rows.append(g);
            if (g.expanded)
                rows.append(kids);
        }
    }
    if (!background.isEmpty() && header(QStringLiteral("background"), QStringLiteral("Procesy w tle"), background.size()))
        rows.append(background);
    if (!system.isEmpty() && header(QStringLiteral("system"), QStringLiteral("Procesy systemu"), system.size()))
        rows.append(system);
    apply(rows);
}

void ProcessModel::apply(const QVector<Row> &rows)
{
    // Najmniejsze zmiany zamiast przeładowania — zaznaczenie i przewinięcie listy zostają na miejscu
    int i = 0;
    while (i < rows.size()) {
        if (i < m_rows.size() && m_rows.at(i).key == rows.at(i).key) {
            m_rows[i] = rows.at(i);
            ++i;
            continue;
        }
        int found = -1;
        for (int j = i + 1; j < m_rows.size(); ++j)
            if (m_rows.at(j).key == rows.at(i).key) {
                found = j;
                break;
            }
        if (found >= 0) {
            beginRemoveRows({}, i, found - 1);
            m_rows.remove(i, found - i);
            endRemoveRows();
            m_rows[i] = rows.at(i);
        } else {
            beginInsertRows({}, i, i);
            m_rows.insert(i, rows.at(i));
            endInsertRows();
        }
        ++i;
    }
    if (m_rows.size() > rows.size()) {
        beginRemoveRows({}, rows.size(), m_rows.size() - 1);
        m_rows.resize(rows.size());
        endRemoveRows();
    }
    if (!m_rows.isEmpty())
        Q_EMIT dataChanged(index(0), index(m_rows.size() - 1));
}

void ProcessModel::toggle(const QString &key)
{
    if (key.startsWith(QLatin1String("h:"))) {
        const QString id = key.mid(2);
        if (!m_collapsed.remove(id))
            m_collapsed.insert(id);
    } else if (!m_expanded.remove(key)) {
        m_expanded.insert(key);
    }
    rebuild();
}

int ProcessModel::indexOf(const QString &key) const
{
    for (int i = 0; i < m_rows.size(); ++i)
        if (m_rows.at(i).key == key)
            return i;
    return -1;
}

QList<int> ProcessModel::pidsFor(const QString &key) const
{
    QList<int> pids;
    if (key.startsWith(QLatin1String("g:"))) {
        const QString id = key.mid(2);
        for (auto it = m_group.cbegin(); it != m_group.cend(); ++it)
            if (it.value() == id)
                pids.append(it.key());
    } else if (key.startsWith(QLatin1String("p:"))) {
        const int pid = key.mid(2).toInt();
        if (m_procs.contains(pid))
            pids.append(pid);
    }
    return pids;
}

QVariantMap ProcessModel::info(const QString &key) const
{
    const QList<int> pids = pidsFor(key);
    if (pids.isEmpty())
        return {};
    const int i = indexOf(key);
    bool critical = false, foreign = false;
    for (int pid : pids) {
        const Proc &p = m_procs[pid];
        critical = critical || isCritical(p);
        foreign = foreign || p.uid != m_uid;
    }
    return {{QStringLiteral("key"), key},
            {QStringLiteral("name"), i >= 0 ? m_rows.at(i).name : displayName(m_procs.value(pids.first()))},
            {QStringLiteral("count"), pids.size()},
            {QStringLiteral("critical"), critical},
            {QStringLiteral("foreign"), foreign},
            {QStringLiteral("expanded"), m_expanded.contains(key)},
            {QStringLiteral("group"), key.startsWith(QLatin1String("g:"))}};
}

QVariantMap ProcessModel::details(const QString &key) const
{
    const QList<int> pids = pidsFor(key);
    if (pids.isEmpty())
        return {};
    // Program — szczegóły jego głównego (najstarszego) procesu
    int main = pids.first();
    for (int pid : pids)
        if (m_procs[pid].start < m_procs[main].start)
            main = pid;
    const Proc &p = m_procs[main];
    double cpu = 0, disk = 0;
    qint64 mem = 0;
    int threads = 0;
    for (int pid : pids) {
        const Proc &c = m_procs[pid];
        cpu += c.cpu;
        disk += c.disk;
        mem += c.mem;
        threads += c.threads;
    }
    qulonglong boot = 0;
    for (const QByteArray &line : readAll(QStringLiteral("/proc/stat")).split('\n'))
        if (line.startsWith("btime "))
            boot = line.mid(6).trimmed().toULongLong();
    const QDateTime started = QDateTime::fromSecsSinceEpoch(qint64(boot + p.start / qulonglong(std::max(1L, m_hz))));
    const QLocale pl(QLocale::Polish);
    const QString when = started.date() == QDate::currentDate()
        ? QStringLiteral("dziś, ") + pl.toString(started.time(), QStringLiteral("HH:mm"))
        : pl.toString(started, QStringLiteral("d MMMM, HH:mm"));
    const int i = indexOf(key);
    const App *a = key.startsWith(QLatin1String("g:")) ? app(key.mid(2)) : nullptr;
    return {{QStringLiteral("key"), key},
            {QStringLiteral("name"), i >= 0 ? m_rows.at(i).name : displayName(p)},
            {QStringLiteral("desktopId"), a ? a->id : QString()},
            {QStringLiteral("iconName"), a ? a->icon : QString()},
            {QStringLiteral("process"), p.name},
            {QStringLiteral("pid"), p.pid},
            {QStringLiteral("processes"), pids.size()},
            {QStringLiteral("threads"), threads},
            {QStringLiteral("user"), userName(p.uid)},
            {QStringLiteral("state"), stateText(p.state)},
            {QStringLiteral("started"), when},
            {QStringLiteral("command"), p.cmdline.isEmpty() ? p.comm : p.cmdline},
            {QStringLiteral("exe"), p.exe},
            {QStringLiteral("cpu"), cpu},
            {QStringLiteral("mem"), double(mem)},
            {QStringLiteral("disk"), disk},
            {QStringLiteral("critical"), isCritical(p)}};
}

void ProcessModel::end(const QString &key, bool force)
{
    const QList<int> pids = pidsFor(key);
    if (pids.isEmpty())
        return;
    const QVariantMap i = info(key);
    const QString name = i.value(QStringLiteral("name")).toString();
    QList<int> own, foreign;
    QList<QPair<int, qulonglong>> watch;
    for (int pid : pids) {
        (m_procs[pid].uid == m_uid ? own : foreign).append(pid);
        watch.append({pid, m_procs[pid].start});
    }
    for (int pid : std::as_const(own))
        ::kill(pid, force ? SIGKILL : SIGTERM);
    if (!foreign.isEmpty()) {
        // Cudze procesy — przez polkit (okno z hasłem administratora)
        QStringList args{QStringLiteral("/usr/bin/kill"), QStringLiteral("-s"), force ? QStringLiteral("KILL") : QStringLiteral("TERM")};
        for (int pid : std::as_const(foreign))
            args << QString::number(pid);
        QProcess::startDetached(QStringLiteral("pkexec"), args);
    }
    Q_EMIT message(QStringLiteral("Kończę „%1”").arg(name));

    // Program, który nie zamknął się sam w 4 sekundy, kończymy natychmiast (jak „Zakończ zadanie” w Windows)
    if (!force && !own.isEmpty())
        QTimer::singleShot(4000, this, [this, watch, name] {
            bool killed = false;
            for (const auto &[pid, start] : watch) {
                auto it = m_procs.constFind(pid);
                if (it == m_procs.constEnd() || it->start != start || it->uid != m_uid)
                    continue;
                const QByteArray stat = readAll(QStringLiteral("/proc/%1/stat").arg(pid));
                if (stat.isEmpty())
                    continue;
                ::kill(pid, SIGKILL);
                killed = true;
            }
            if (killed)
                Q_EMIT message(QStringLiteral("„%1” nie odpowiadał — zakończony natychmiast").arg(name));
        });
    QTimer::singleShot(600, this, &ProcessModel::refresh);
}

void ProcessModel::openLocation(const QString &key) const
{
    const QList<int> pids = pidsFor(key);
    if (pids.isEmpty())
        return;
    const Proc &p = m_procs[pids.first()];
    QString file = p.exe;
    if (file.isEmpty()) {
        const QString arg0 = p.cmdline.section(QLatin1Char(' '), 0, 0);
        file = arg0.startsWith(QLatin1Char('/')) ? arg0 : QStandardPaths::findExecutable(arg0.isEmpty() ? p.comm : arg0);
    }
    if (file.isEmpty())
        return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(file).absolutePath()));
}

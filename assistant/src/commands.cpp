#include "commands.h"

#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>

// Tylko odczyt: znane polecenia, które niczego nie zmieniają, bez przekierowań do plików, podstawień
// i łańcuchów (dozwolony potok między bezpiecznymi). Wszystko inne — po zgodzie użytkownika.
bool Commands::readOnly(const QString &command)
{
    const QString c = command.trimmed();
    if (c.isEmpty() || c.contains(QLatin1Char('\n')) || c.contains(QLatin1Char('>')) || c.contains(QLatin1Char('`'))
        || c.contains(QLatin1String("$(")) || c.contains(QLatin1Char(';')) || c.contains(QLatin1String("&&"))
        || c.contains(QLatin1String("||")) || c.contains(QLatin1Char('&')))
        return false;
    static const QStringList plain{
        QStringLiteral("ls"), QStringLiteral("cat"), QStringLiteral("head"), QStringLiteral("tail"), QStringLiteral("wc"),
        QStringLiteral("grep"), QStringLiteral("sort"), QStringLiteral("cut"), QStringLiteral("tr"),
        QStringLiteral("df"), QStringLiteral("du"), QStringLiteral("free"), QStringLiteral("uptime"), QStringLiteral("uname"),
        QStringLiteral("whoami"), QStringLiteral("id"), QStringLiteral("hostname"), QStringLiteral("date"), QStringLiteral("pwd"),
        QStringLiteral("lsblk"), QStringLiteral("lscpu"), QStringLiteral("lsusb"), QStringLiteral("lspci"), QStringLiteral("ps"),
        QStringLiteral("pgrep"), QStringLiteral("stat"), QStringLiteral("file"), QStringLiteral("which"), QStringLiteral("whereis"),
        QStringLiteral("type"), QStringLiteral("command"), QStringLiteral("journalctl"), QStringLiteral("dmesg"),
        QStringLiteral("findmnt"), QStringLiteral("ping"), QStringLiteral("getent"), QStringLiteral("printenv"),
        QStringLiteral("echo"), QStringLiteral("realpath"), QStringLiteral("basename"), QStringLiteral("dirname"),
        QStringLiteral("sensors"), QStringLiteral("fc-list"), QStringLiteral("locale"), QStringLiteral("timedatectl"),
        QStringLiteral("hostnamectl"), QStringLiteral("loginctl"), QStringLiteral("wpctl"), QStringLiteral("pactl"),
        QStringLiteral("top"), QStringLiteral("find"), QStringLiteral("tree"), QStringLiteral("md5sum"), QStringLiteral("sha256sum"),
        QStringLiteral("resolvectl"), QStringLiteral("upower"), QStringLiteral("inxi"), QStringLiteral("glxinfo"),
        QStringLiteral("rpm-ostree"), QStringLiteral("bootc"), QStringLiteral("rpm"),
    };
    // Polecenia z podpoleceniami: dozwolone tylko te do odczytu
    static const QHash<QString, QStringList> sub{
        {QStringLiteral("systemctl"), {QStringLiteral("status"), QStringLiteral("is-active"), QStringLiteral("is-enabled"), QStringLiteral("is-failed"),
                                       QStringLiteral("list-units"), QStringLiteral("list-unit-files"), QStringLiteral("list-timers"), QStringLiteral("show"),
                                       QStringLiteral("cat"), QStringLiteral("--failed")}},
        {QStringLiteral("flatpak"), {QStringLiteral("list"), QStringLiteral("info"), QStringLiteral("search"), QStringLiteral("remote-ls"),
                                     QStringLiteral("remotes"), QStringLiteral("history"), QStringLiteral("ps")}},
        {QStringLiteral("nmcli"), {QStringLiteral("general"), QStringLiteral("g")}},
        {QStringLiteral("ip"), {QStringLiteral("a"), QStringLiteral("addr"), QStringLiteral("address"), QStringLiteral("link"), QStringLiteral("r"),
                                QStringLiteral("route"), QStringLiteral("-br"), QStringLiteral("-4"), QStringLiteral("-6")}},
        {QStringLiteral("git"), {QStringLiteral("status"), QStringLiteral("log"), QStringLiteral("diff"), QStringLiteral("show")}},
        {QStringLiteral("toolbox"), {QStringLiteral("list")}},
        {QStringLiteral("bluetoothctl"), {QStringLiteral("show"), QStringLiteral("devices"), QStringLiteral("info"), QStringLiteral("list")}},
        {QStringLiteral("powerprofilesctl"), {QStringLiteral("get"), QStringLiteral("list")}},
    };
    // Słowa, które w odczytujących poleceniach jednak coś zmieniają
    static const QRegularExpression risky(QStringLiteral(
        "(^|\\s)(-delete|-exec|-execdir|-ok|--vacuum[-a-z]*|--rotate|--flush|-f\\b.*journalctl|upgrade|rollback|switch|install|"
        "uninstall|update|remove|reset|enter|create|rm|-e|-i|--erase|--import|kargs|override|rebase|cleanup|apply-live|usroverlay|"
        "initramfs|deploy|set-[a-z-]+|load-module|unload-module|terminate|kill|lock|poweroff|reboot|suspend|add|-fprint|-fprintf|-fls|"
        "-C|--clear)(\\s|=|$)"));
    // Te tylko czytają, a ich opcje (-e, -o…) przypadkiem pasują do słów wyżej
    static const QStringList readers{QStringLiteral("grep"), QStringLiteral("echo"), QStringLiteral("ps"), QStringLiteral("lsblk"),
                                     QStringLiteral("findmnt"), QStringLiteral("lscpu")};
    for (const QString &segment : c.split(QLatin1Char('|'))) {
        const QStringList w = QProcess::splitCommand(segment.trimmed());
        if (w.isEmpty())
            return false;
        const QString prog = w.first();
        if (risky.match(segment).hasMatch() && !readers.contains(prog))
            return false;
        if (prog == QLatin1String("sort") && (w.contains(QLatin1String("-o")) || segment.contains(QLatin1String("--output"))))
            return false;    // zapisuje do pliku
        if (prog == QLatin1String("top") && !w.contains(QLatin1String("-b")))
            return false;    // bez -b czeka na klawisze
        if (prog == QLatin1String("journalctl") && (w.contains(QLatin1String("-f")) || w.contains(QLatin1String("--follow"))))
            return false;
        if (prog == QLatin1String("ping") && !w.contains(QLatin1String("-c")))
            return false;    // bez -c nie kończy się sam
        if (prog == QLatin1String("dmesg") && w.contains(QLatin1String("-c")))
            return false;    // czyści bufor jądra
        if (plain.contains(prog))
            continue;
        auto it = sub.constFind(prog);
        if (it == sub.constEnd())
            return false;
        // pierwsze słowo niebędące opcją (albo opcja z listy) musi być podpoleceniem do odczytu
        bool ok = false;
        for (int i = 1; i < w.size(); ++i) {
            if (it.value().contains(w.at(i))) { ok = true; break; }
            if (!w.at(i).startsWith(QLatin1Char('-')))
                break;
        }
        if (prog == QLatin1String("nmcli"))
            ok = ok || (w.size() >= 3 && (w.at(2) == QLatin1String("show") || w.at(2) == QLatin1String("status") || w.at(2) == QLatin1String("list")))
                 || (w.size() == 2 && (w.at(1) == QLatin1String("device") || w.at(1) == QLatin1String("connection") || w.at(1) == QLatin1String("radio")));
        if (prog == QLatin1String("systemctl") && w.size() == 2 && w.at(1) == QLatin1String("--user"))
            ok = true;
        if (prog == QLatin1String("systemctl") && w.contains(QLatin1String("--user")))
            for (const QString &x : w)
                ok = ok || it.value().contains(x);
        if (!ok)
            return false;
    }
    return true;
}

// ——— Ważne polecenia: o nie agent pyta, resztę robi sam ———

namespace {

struct Split {
    QStringList commands;     // proste polecenia (bez potoków, łańcuchów i nawiasów)
    QStringList overwrites;   // cele przekierowań „>” (nadpisanie pliku)
    QStringList inner;        // treść $(…) i `…` — sprawdzana osobno
};

// Na tyle, na ile trzeba: cudzysłowy, potoki, ; && || &, nawiasy, $(…), `…`, przekierowania
Split split(const QString &s)
{
    Split out;
    QString cur;
    QChar quote;
    auto flush = [&] {
        if (!cur.trimmed().isEmpty())
            out.commands << cur.trimmed();
        cur.clear();
    };
    for (int i = 0; i < s.size(); ++i) {
        const QChar ch = s.at(i);
        if (!quote.isNull()) {
            if (ch == quote)
                quote = QChar();
            else if (quote == QLatin1Char('"') && ch == QLatin1Char('\\') && i + 1 < s.size()) {
                cur += ch;
                cur += s.at(++i);
                continue;
            }
            // podstawienie działa też w „…”
            if (quote == QLatin1Char('"') && ch == QLatin1Char('$') && s.mid(i, 2) == QLatin1String("$(")) {
                int depth = 0, j = i + 1;
                for (; j < s.size(); ++j) {
                    if (s.at(j) == QLatin1Char('(')) ++depth;
                    else if (s.at(j) == QLatin1Char(')') && --depth == 0) break;
                }
                out.inner << s.mid(i + 2, j - i - 2);
            } else if (quote == QLatin1Char('"') && ch == QLatin1Char('`')) {
                const int j = s.indexOf(QLatin1Char('`'), i + 1);
                out.inner << s.mid(i + 1, j < 0 ? -1 : j - i - 1);
            }
            cur += ch;
            continue;
        }
        if (ch == QLatin1Char('\'') || ch == QLatin1Char('"')) {
            quote = ch;
            cur += ch;
        } else if (ch == QLatin1Char('\\') && i + 1 < s.size()) {
            cur += ch;
            cur += s.at(++i);
        } else if (ch == QLatin1Char('#') && (cur.isEmpty() || cur.endsWith(QLatin1Char(' ')))) {
            while (i < s.size() && s.at(i) != QLatin1Char('\n'))
                ++i;
            flush();
        } else if (QStringLiteral("|;&\n(){}`").contains(ch)) {
            flush();
        } else if (ch == QLatin1Char('>')) {
            // >> dopisuje, >&2 / 2>&1 tylko przekierowuje strumień
            if (i + 1 < s.size() && (s.at(i + 1) == QLatin1Char('>') || s.at(i + 1) == QLatin1Char('&'))) {
                ++i;
                if (s.at(i) == QLatin1Char('&'))
                    while (i + 1 < s.size() && s.at(i + 1).isDigit())
                        ++i;
                else
                    while (i + 1 < s.size() && s.at(i + 1) == QLatin1Char(' '))
                        ++i, cur += QLatin1Char(' ');
                // cel >> zostaje w poleceniu jako zwykłe słowo — nieszkodliwe
                continue;
            }
            if (i + 1 < s.size() && s.at(i + 1) == QLatin1Char('|'))
                ++i;
            int j = i + 1;
            while (j < s.size() && s.at(j) == QLatin1Char(' '))
                ++j;
            int k = j;
            QChar q;
            while (k < s.size() && (!q.isNull() || !QStringLiteral(" |;&\n()<>").contains(s.at(k)))) {
                if (q.isNull() && (s.at(k) == QLatin1Char('"') || s.at(k) == QLatin1Char('\'')))
                    q = s.at(k);
                else if (s.at(k) == q)
                    q = QChar();
                ++k;
            }
            QString target = s.mid(j, k - j);
            target.remove(QLatin1Char('"')).remove(QLatin1Char('\''));
            out.overwrites << target;
            // cyfra przed > (2>plik) to numer strumienia — nie część polecenia
            while (!cur.isEmpty() && cur.back().isDigit())
                cur.chop(1);
            i = k - 1;
        } else {
            cur += ch;
        }
    }
    flush();
    return out;
}

QString expandHome(QString p)
{
    if (p == QLatin1String("~") || p.startsWith(QLatin1String("~/")))
        p.replace(0, 1, QDir::homePath());
    p.replace(QLatin1String("$HOME"), QDir::homePath());
    p.replace(QLatin1String("${HOME}"), QDir::homePath());
    return p;
}

// Nadpisanie pliku: bez pytania tylko do /dev/null i do nowego pliku pod znaną (bezwzględną) ścieżką
bool overwriteIsHarmless(const QString &raw)
{
    const QString t = expandHome(raw);
    if (t.startsWith(QLatin1String("/dev/")))
        return t == QLatin1String("/dev/null") || t == QLatin1String("/dev/stdout") || t == QLatin1String("/dev/stderr");
    if (t.isEmpty() || !t.startsWith(QLatin1Char('/')) || t.contains(QLatin1Char('$')) || t.contains(QLatin1Char('*')))
        return false;
    return !QFileInfo::exists(t) && t.startsWith(QDir::homePath() + QLatin1Char('/'));
}

bool has(const QStringList &w, std::initializer_list<const char *> any)
{
    for (const char *a : any)
        if (w.contains(QLatin1String(a)))
            return true;
    return false;
}

// Pierwsze słowo po programie, które nie jest opcją
QString subcommand(const QStringList &w, int from = 1)
{
    for (int i = from; i < w.size(); ++i)
        if (!w.at(i).startsWith(QLatin1Char('-')))
            return w.at(i);
    return {};
}

bool check(const QString &command, QString *why, int depth);

// Słowa jak w powłoce: '…' i "…" (QProcess::splitCommand nie zna apostrofów), \ przed znakiem
QStringList words(const QString &s)
{
    QStringList out;
    QString cur;
    bool any = false;
    QChar quote;
    for (int i = 0; i < s.size(); ++i) {
        const QChar ch = s.at(i);
        if (!quote.isNull()) {
            if (ch == quote)
                quote = QChar();
            else if (quote == QLatin1Char('"') && ch == QLatin1Char('\\') && i + 1 < s.size())
                cur += s.at(++i);
            else
                cur += ch;
        } else if (ch == QLatin1Char('\'') || ch == QLatin1Char('"')) {
            quote = ch;
            any = true;
        } else if (ch == QLatin1Char('\\') && i + 1 < s.size()) {
            cur += s.at(++i);
        } else if (ch.isSpace()) {
            if (any || !cur.isEmpty())
                out << cur;
            cur.clear();
            any = false;
        } else {
            cur += ch;
        }
    }
    if (any || !cur.isEmpty())
        out << cur;
    return out;
}

bool simple(QStringList w, QString *why, int depth)
{
    auto no = [why](const QString &r) {
        if (why)
            *why = r;
        return true;
    };
    // Zmienne środowiska i nakładki przed właściwym programem
    static const QRegularExpression assign(QStringLiteral("^[A-Za-z_][A-Za-z0-9_]*="));
    while (!w.isEmpty()) {
        const QString p = w.first();
        if (assign.match(p).hasMatch() || p == QLatin1String("nohup") || p == QLatin1String("time") || p == QLatin1String("command")
            || p == QLatin1String("builtin") || p == QLatin1String("exec") || p == QLatin1String("stdbuf") || p == QLatin1String("!")) {
            w.removeFirst();
            while (!w.isEmpty() && p == QLatin1String("stdbuf") && w.first().startsWith(QLatin1Char('-')))
                w.removeFirst();
        } else if (p == QLatin1String("env") || p == QLatin1String("nice") || p == QLatin1String("ionice")) {
            w.removeFirst();
            while (!w.isEmpty() && (w.first().startsWith(QLatin1Char('-')) || assign.match(w.first()).hasMatch()
                                    || (p != QLatin1String("env") && w.first().toInt() != 0)))
                w.removeFirst();
        } else if (p == QLatin1String("timeout")) {
            w.removeFirst();
            while (!w.isEmpty() && w.first().startsWith(QLatin1Char('-')))
                w.removeFirst();
            if (!w.isEmpty())
                w.removeFirst();     // czas
        } else if (p == QLatin1String("flatpak-spawn")) {
            w.removeFirst();
            while (!w.isEmpty() && w.first().startsWith(QLatin1Char('-')))
                w.removeFirst();
        } else if (p == QLatin1String("toolbox") && w.value(1) == QLatin1String("run")) {
            w = w.mid(2);
            while (!w.isEmpty() && w.first().startsWith(QLatin1Char('-'))) {
                if (w.first() == QLatin1String("-c") || w.first() == QLatin1String("--container"))
                    w.removeFirst();
                w.removeFirst();
            }
        } else if (p == QLatin1String("xargs")) {
            w.removeFirst();
            while (!w.isEmpty() && w.first().startsWith(QLatin1Char('-'))) {
                if (QStringList{QStringLiteral("-I"), QStringLiteral("-n"), QStringLiteral("-P"), QStringLiteral("-d"), QStringLiteral("-L")}.contains(w.first()))
                    w.removeFirst();
                w.removeFirst();
            }
        } else {
            break;
        }
    }
    if (w.isEmpty())
        return false;
    QString prog = w.first();
    if (prog.contains(QLatin1Char('/')) && !prog.startsWith(QLatin1String("/usr/bin/")) && !prog.startsWith(QLatin1String("/bin/")))
        return no(QStringLiteral("uruchamia skrypt albo program z pliku"));
    prog = prog.section(QLatin1Char('/'), -1);

    static const QSet<QString> always{
        // uprawnienia administratora
        QStringLiteral("pkexec"), QStringLiteral("sudo"), QStringLiteral("su"), QStringLiteral("doas"), QStringLiteral("run0"),
        // usuwanie
        QStringLiteral("rm"), QStringLiteral("rmdir"), QStringLiteral("shred"), QStringLiteral("unlink"), QStringLiteral("truncate"),
        QStringLiteral("trash-put"), QStringLiteral("trash-rm"), QStringLiteral("trash-empty"), QStringLiteral("trash"),
        // dyski
        QStringLiteral("dd"), QStringLiteral("wipefs"), QStringLiteral("fdisk"), QStringLiteral("sfdisk"), QStringLiteral("gdisk"),
        QStringLiteral("parted"), QStringLiteral("mount"), QStringLiteral("umount"), QStringLiteral("cryptsetup"), QStringLiteral("swapon"),
        QStringLiteral("swapoff"), QStringLiteral("losetup"), QStringLiteral("udisksctl"), QStringLiteral("blkdiscard"),
        // zasilanie i programy
        QStringLiteral("reboot"), QStringLiteral("poweroff"), QStringLiteral("shutdown"), QStringLiteral("halt"),
        QStringLiteral("kill"), QStringLiteral("pkill"), QStringLiteral("killall"), QStringLiteral("xkill"),
        // konta i uprawnienia plików
        QStringLiteral("passwd"), QStringLiteral("chpasswd"), QStringLiteral("useradd"), QStringLiteral("userdel"), QStringLiteral("usermod"),
        QStringLiteral("groupadd"), QStringLiteral("groupdel"), QStringLiteral("gpasswd"), QStringLiteral("chsh"), QStringLiteral("chown"),
        QStringLiteral("chgrp"), QStringLiteral("chattr"), QStringLiteral("setfacl"),
        // pakiety spoza Flatpaka, zmiany w plikach, cudzy kod
        QStringLiteral("dnf"), QStringLiteral("yum"), QStringLiteral("dnf5"), QStringLiteral("pip"), QStringLiteral("pip3"),
        QStringLiteral("npm"), QStringLiteral("tee"), QStringLiteral("eval"), QStringLiteral("source"), QStringLiteral("."),
        QStringLiteral("ssh"), QStringLiteral("at"), QStringLiteral("busctl"), QStringLiteral("dbus-send"), QStringLiteral("gdbus"),
        QStringLiteral("qdbus"), QStringLiteral("qdbus6"), QStringLiteral("efibootmgr"), QStringLiteral("grub2-install"),
        QStringLiteral("dracut"), QStringLiteral("modprobe"), QStringLiteral("rmmod"), QStringLiteral("insmod"), QStringLiteral("sysctl"),
        QStringLiteral("chroot"), QStringLiteral("nsenter"), QStringLiteral("setenforce"), QStringLiteral("restorecon"),
        QStringLiteral("authselect"), QStringLiteral("update-alternatives"), QStringLiteral("fwupdmgr"),
    };
    if (always.contains(prog) || prog.startsWith(QLatin1String("mkfs")))
        return no(QStringLiteral("ważna zmiana: %1").arg(prog));

    // Programy, które czekają na klawisze albo nie kończą się same
    static const QSet<QString> interactive{QStringLiteral("nano"), QStringLiteral("vi"), QStringLiteral("vim"), QStringLiteral("nvim"),
                                           QStringLiteral("emacs"), QStringLiteral("less"), QStringLiteral("more"), QStringLiteral("man"),
                                           QStringLiteral("htop"), QStringLiteral("btop"), QStringLiteral("watch"), QStringLiteral("mc")};
    if (interactive.contains(prog) || (prog == QLatin1String("top") && !w.contains(QLatin1String("-b")))
        || ((prog == QLatin1String("tail") || prog == QLatin1String("journalctl")) && has(w, {"-f", "-F", "--follow"}))
        || (prog == QLatin1String("ping") && !w.contains(QLatin1String("-c"))))
        return no(QStringLiteral("czeka na klawisze albo się nie kończy"));

    // Powłoki i języki: kod w -c / -e sprawdzamy, skryptów z plików — nie da się, więc pytamy
    static const QSet<QString> shells{QStringLiteral("bash"), QStringLiteral("sh"), QStringLiteral("zsh"), QStringLiteral("fish"), QStringLiteral("dash")};
    if (shells.contains(prog)) {
        const int c = int(w.indexOf(QLatin1String("-c")) >= 0 ? w.indexOf(QLatin1String("-c")) : w.indexOf(QLatin1String("-lc")));
        if (c >= 0 && c + 1 < w.size())
            return depth < 4 ? check(w.at(c + 1), why, depth + 1) : no(QStringLiteral("zbyt zagnieżdżone"));
        return no(QStringLiteral("uruchamia skrypt"));
    }
    static const QSet<QString> langs{QStringLiteral("python"), QStringLiteral("python3"), QStringLiteral("perl"), QStringLiteral("node"),
                                     QStringLiteral("ruby"), QStringLiteral("php"), QStringLiteral("lua")};
    if (langs.contains(prog)) {
        const int c = int(std::max(w.indexOf(QLatin1String("-c")), w.indexOf(QLatin1String("-e"))));
        if (c < 0 || c + 1 >= w.size())
            return no(QStringLiteral("uruchamia skrypt"));
        static const QRegularExpression risky(QStringLiteral(
            "remove|unlink|rmtree|rmdir|truncate|system|subprocess|popen|exec|spawn|kill|chmod|chown|rename|replace|"
            "open\\([^)]*['\"][wax+]|write|shutil|requests\\.(post|put|delete)|urlopen|socket|eval"));
        if (risky.match(w.at(c + 1)).hasMatch())
            return no(QStringLiteral("skrypt może zmieniać pliki"));
        return false;
    }

    // Zmiany w plikach na miejscu
    if ((prog == QLatin1String("sed") || prog == QLatin1String("perl"))
        && std::any_of(w.begin() + 1, w.end(), [](const QString &a) { return a.startsWith(QLatin1String("-i")) || a == QLatin1String("--in-place"); }))
        return no(QStringLiteral("zmienia plik"));
    if (prog == QLatin1String("chmod") && (has(w, {"-R", "--recursive"}) || std::any_of(w.begin() + 1, w.end(), [](const QString &a) {
                                               return a.startsWith(QLatin1Char('/')) && !expandHome(a).startsWith(QDir::homePath());
                                           })))
        return no(QStringLiteral("zmienia uprawnienia plików"));
    if (prog == QLatin1String("find") && has(w, {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprintf", "-fls"}))
        return no(QStringLiteral("find usuwa albo uruchamia"));
    if (prog == QLatin1String("rsync") && std::any_of(w.begin() + 1, w.end(), [](const QString &a) { return a.startsWith(QLatin1String("--delete")) || a.startsWith(QLatin1String("--remove")); }))
        return no(QStringLiteral("rsync usuwa pliki"));
    if (prog == QLatin1String("crontab") && !w.contains(QLatin1String("-l")))
        return no(QStringLiteral("zmienia harmonogram"));
    if (prog == QLatin1String("rpm") && std::any_of(w.begin() + 1, w.end(), [](const QString &a) {
            return a.startsWith(QLatin1String("-i")) || a.startsWith(QLatin1String("-U")) || a.startsWith(QLatin1String("-e"))
                || a.startsWith(QLatin1String("-F")) || a.startsWith(QLatin1String("--import")) || a.startsWith(QLatin1String("--erase"));
        }))
        return no(QStringLiteral("rpm instaluje albo usuwa"));
    if (prog == QLatin1String("dmesg") && has(w, {"-c", "-C", "--clear", "--read-clear"}))
        return no(QStringLiteral("czyści dziennik jądra"));
    if (prog == QLatin1String("journalctl") && std::any_of(w.begin() + 1, w.end(), [](const QString &a) {
            return a.startsWith(QLatin1String("--vacuum")) || a == QLatin1String("--rotate") || a == QLatin1String("--flush");
        }))
        return no(QStringLiteral("czyści dziennik"));

    // Polecenia z podpoleceniami: ważne tylko niektóre
    const QString sub = subcommand(w);
    auto subIn = [&](std::initializer_list<const char *> l) {
        for (const char *x : l)
            if (sub == QLatin1String(x))
                return true;
        return false;
    };
    if (prog == QLatin1String("flatpak")
        && subIn({"install", "uninstall", "remove", "update", "upgrade", "remote-add", "remote-delete", "remote-modify", "repair",
                  "override", "mask", "pin", "permission-set", "permission-reset", "permission-remove", "config", "kill",
                  "make-current", "create-usb", "build", "build-export", "build-bundle", "build-import-bundle", "install-bundle"}))
        return no(sub == QLatin1String("install") ? QStringLiteral("instaluje program") : QStringLiteral("zmienia programy"));
    if (prog == QLatin1String("systemctl")
        && subIn({"start", "stop", "restart", "reload", "try-restart", "reload-or-restart", "try-reload-or-restart", "enable", "disable",
                  "reenable", "mask", "unmask", "preset", "preset-all", "daemon-reload", "daemon-reexec", "edit", "set-property",
                  "set-environment", "unset-environment", "import-environment", "reset-failed", "kill", "clean", "freeze", "isolate",
                  "reboot", "poweroff", "halt", "suspend", "hibernate", "hybrid-sleep", "suspend-then-hibernate", "soft-reboot",
                  "kexec", "rescue", "emergency", "default", "link", "revert", "set-default", "switch-root"}))
        return no(QStringLiteral("zmienia usługi albo zasilanie"));
    if (prog == QLatin1String("loginctl") && (sub.startsWith(QLatin1String("terminate")) || sub.startsWith(QLatin1String("kill"))
                                              || sub.startsWith(QLatin1String("lock")) || sub.startsWith(QLatin1String("enable"))
                                              || sub.startsWith(QLatin1String("disable")) || subIn({"poweroff", "reboot", "suspend", "hibernate", "attach", "flush-devices"})))
        return no(QStringLiteral("zamyka sesję albo zmienia zasilanie"));
    if ((prog == QLatin1String("bootc") || prog == QLatin1String("rpm-ostree") || prog == QLatin1String("ostree"))
        && !subIn({"status", "--version", "db", "--help"}) && !(prog == QLatin1String("ostree") && sub == QLatin1String("admin") && w.contains(QLatin1String("status"))))
        return no(QStringLiteral("zmienia system"));
    if (prog == QLatin1String("git")
        && (subIn({"push", "clean", "restore", "rebase", "rm", "filter-branch", "filter-repo", "gc", "prune", "update-ref"})
            || (sub == QLatin1String("reset") && w.contains(QLatin1String("--hard")))
            || (sub == QLatin1String("checkout") && has(w, {"--", "-f", "--force", "."}))
            || (sub == QLatin1String("branch") && has(w, {"-D", "-d", "--delete"}))
            || (sub == QLatin1String("stash") && has(w, {"drop", "clear"}))
            || (sub == QLatin1String("tag") && has(w, {"-d", "--delete"}))
            || (sub == QLatin1String("remote") && has(w, {"remove", "rm"}))
            || (sub == QLatin1String("worktree") && has(w, {"remove", "prune"}))))
        return no(QStringLiteral("git może stracić zmiany albo je wysłać"));
    if (prog == QLatin1String("nmcli")
        && has(w, {"delete", "del", "modify", "mod", "down", "off", "disconnect", "add", "edit", "import", "reload", "hostname"}))
        return no(QStringLiteral("zmienia sieć"));
    if ((prog == QLatin1String("hostnamectl") || prog == QLatin1String("timedatectl") || prog == QLatin1String("localectl"))
        && sub.startsWith(QLatin1String("set-")))
        return no(QStringLiteral("zmienia ustawienia systemu"));
    if (prog == QLatin1String("firewall-cmd")
        && !std::all_of(w.begin() + 1, w.end(), [](const QString &a) {
               return a.startsWith(QLatin1String("--list")) || a.startsWith(QLatin1String("--get")) || a.startsWith(QLatin1String("--query"))
                   || a == QLatin1String("--state") || a.startsWith(QLatin1String("--zone"));
           }))
        return no(QStringLiteral("zmienia zaporę"));
    if ((prog == QLatin1String("podman") || prog == QLatin1String("docker") || prog == QLatin1String("toolbox") || prog == QLatin1String("distrobox"))
        && (subIn({"rm", "rmi", "prune", "kill", "stop", "system", "volume", "reset"}) || has(w, {"rm", "prune"})))
        return no(QStringLiteral("usuwa kontenery"));
    if (prog == QLatin1String("gio") && subIn({"trash", "remove", "rm", "move", "mv", "set"}))
        return no(QStringLiteral("usuwa albo przenosi pliki"));
    if (prog == QLatin1String("bluetoothctl") && has(w, {"remove", "untrust", "block", "power off"}))
        return no(QStringLiteral("zmienia Bluetooth"));
    // Procesy w tle: liczy się to, co uruchamiają (po „--”)
    if ((prog == QLatin1String("aster") || prog == QLatin1String("ai")) && w.value(1) == QLatin1String("--tlo")) {
        const int dash = int(w.indexOf(QLatin1String("--"), 2));
        if (w.value(2) == QLatin1String("start"))
            return dash < 0 || dash + 1 >= w.size() ? no(QStringLiteral("brak polecenia")) : simple(w.mid(dash + 1), why, depth + 1);
        return false;
    }
    if ((prog == QLatin1String("aster") || prog == QLatin1String("ai"))
        && !(QStringList{QStringLiteral("--historia"), QStringLiteral("--rozmowa"), QStringLiteral("--stan"), QStringLiteral("--pomoc"),
                         QStringLiteral("--help"), QStringLiteral("--okna"), QStringLiteral("--pokaz"), QStringLiteral("--zminimalizuj"),
                         QStringLiteral("--maksymalizuj"), QStringLiteral("--otworz"),
                         QStringLiteral("--punkty")}.contains(w.value(1)) || (w.value(1) == QLatin1String("--model-lokalny") && w.size() <= 3 && (w.size() == 2 || w.at(2) == QLatin1String("lista")))))
        return no(QStringLiteral("zagnieżdżone pytanie albo pobieranie modelu"));
    return false;
}

bool check(const QString &command, QString *why, int depth)
{
    const Split s = split(command);
    for (const QString &t : s.overwrites)
        if (!overwriteIsHarmless(t)) {
            if (why)
                *why = QStringLiteral("nadpisuje plik %1").arg(t);
            return true;
        }
    for (const QString &in : s.inner)
        if (depth < 4 && check(in, why, depth + 1))
            return true;
    for (const QString &c : s.commands) {
        // $( zostawia „$” na końcu poprzedniego kawałka — bez znaczenia
        QString t = c;
        if (t == QLatin1String("$"))
            continue;
        if (t.endsWith(QLatin1Char('$')))
            t.chop(1);
        if (simple(words(t), why, depth))
            return true;
    }
    return false;
}

} // namespace

QString Commands::expandPath(const QString &path, const QString &workdir)
{
    QString p = expandHome(path.trimmed());
    if (!p.startsWith(QLatin1Char('/')))
        p = (workdir.isEmpty() ? QDir::homePath() : workdir) + QLatin1Char('/') + p;
    return QDir::cleanPath(p);
}

QString Commands::projectRoot(const QString &absolutePath, const QStringList &extra)
{
    static const QStringList markers{QStringLiteral(".git"), QStringLiteral("package.json"), QStringLiteral("pyproject.toml"),
                                     QStringLiteral("requirements.txt"), QStringLiteral("Cargo.toml"), QStringLiteral("go.mod"),
                                     QStringLiteral("CMakeLists.txt"), QStringLiteral("composer.json"), QStringLiteral("Gemfile"),
                                     QStringLiteral("pom.xml"), QStringLiteral("build.gradle"), QStringLiteral("deno.json"),
                                     QStringLiteral("index.html"), QStringLiteral(".aster-projekt")};
    const QString home = QDir::cleanPath(QDir::homePath());
    QString dir = QFileInfo(absolutePath).absolutePath();
    while (dir.size() > home.size() && dir.startsWith(home + QLatin1Char('/'))) {
        for (const QString &m : markers)
            if (QFileInfo::exists(dir + QLatin1Char('/') + m) || extra.contains(dir + QLatin1Char('/') + m))
                return dir;
        dir = QFileInfo(dir).absolutePath();
    }
    return {};
}

bool Commands::needsConsent(const QString &command, QString *why)
{
    const QString c = command.trimmed();
    if (c.isEmpty())
        return false;
    return check(c, why, 0);
}

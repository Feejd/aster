#include "ports.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

#include <csignal>
#include <cstdio>
#include <unistd.h>

namespace {

struct Socket {
    int port = 0;
    QString proto;
    bool local = false;    // tylko ten komputer (127.0.0.1 / ::1)
    quint64 inode = 0;
};

// /proc/net/{tcp,tcp6,udp,udp6}: adres:port szesnastkowo, stan 0A = LISTEN (UDP: 07 — gniazdo otwarte)
QList<Socket> sockets()
{
    QList<Socket> out;
    const struct { const char *file; const char *proto; bool v6; } files[] = {
        {"/proc/net/tcp", "TCP", false}, {"/proc/net/tcp6", "TCP", true}, {"/proc/net/udp", "UDP", false}, {"/proc/net/udp6", "UDP", true}};
    for (const auto &f : files) {
        QFile file(QString::fromLatin1(f.file));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        file.readLine();
        while (!file.atEnd()) {
            const QList<QByteArray> c = file.readLine().simplified().split(' ');
            if (c.size() < 10)
                continue;
            const bool tcp = qstrcmp(f.proto, "TCP") == 0;
            if (c.at(3) != (tcp ? "0A" : "07"))
                continue;
            const QByteArray local = c.at(1);
            const QByteArray addr = local.left(local.indexOf(':'));
            Socket s;
            s.port = local.mid(local.indexOf(':') + 1).toInt(nullptr, 16);
            s.proto = QString::fromLatin1(f.proto);
            s.inode = c.at(9).toULongLong();
            // 0100007F = 127.0.0.1; ::1 = 00000000000000000000000001000000
            s.local = f.v6 ? addr == "00000000000000000000000001000000" || addr.endsWith("0100007F") : addr.endsWith("7F");
            if (s.port > 0)
                out << s;
        }
    }
    return out;
}

} // namespace

Ports::Ports(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &Ports::refresh);
}

void Ports::setActive(bool on)
{
    if (on == active())
        return;
    if (on) {
        refresh();
        m_timer.start();
    } else {
        m_timer.stop();
    }
    Q_EMIT activeChanged();
}

QJsonArray Ports::scan()
{
    const QList<Socket> socks = sockets();
    QHash<quint64, int> owner;   // inode gniazda → pid (tylko procesy, których fd możemy czytać)
    const QStringList pids = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &pid : pids) {
        bool ok = false;
        const int p = pid.toInt(&ok);
        if (!ok)
            continue;
        const QDir fd(QStringLiteral("/proc/%1/fd").arg(p));
        for (const QFileInfo &fi : fd.entryInfoList(QDir::System | QDir::NoDotAndDotDot)) {
            const QString target = fi.symLinkTarget().section(QLatin1Char('/'), -1);
            if (target.startsWith(QLatin1String("socket:[")))
                owner.insert(target.mid(8).chopped(1).toULongLong(), p);
        }
    }
    QMap<QString, QJsonObject> rows;   // klucz port/proto — bez powtórek IPv4 i IPv6
    for (const Socket &s : socks) {
        const QString key = QStringLiteral("%1/%2").arg(s.port, 5, 10, QLatin1Char('0')).arg(s.proto);
        const int pid = owner.value(s.inode, 0);
        QJsonObject o = rows.value(key);
        if (o.isEmpty() || (pid && !o.value(QStringLiteral("pid")).toInt())) {
            o = QJsonObject{{QStringLiteral("port"), s.port}, {QStringLiteral("proto"), s.proto}, {QStringLiteral("pid"), pid},
                            {QStringLiteral("local"), s.local}, {QStringLiteral("mine"), pid != 0}};
            if (pid) {
                QFile comm(QStringLiteral("/proc/%1/comm").arg(pid));
                if (comm.open(QIODevice::ReadOnly))
                    o.insert(QStringLiteral("program"), QString::fromUtf8(comm.readAll()).trimmed());
                QFile cmd(QStringLiteral("/proc/%1/cmdline").arg(pid));
                if (cmd.open(QIODevice::ReadOnly)) {
                    QByteArray c = cmd.readAll();
                    c.replace('\0', ' ');
                    o.insert(QStringLiteral("command"), QString::fromUtf8(c).trimmed().left(200));
                }
                QString cwd = QFileInfo(QStringLiteral("/proc/%1/cwd").arg(pid)).symLinkTarget();
                if (cwd.startsWith(QDir::homePath()))
                    cwd.replace(0, QDir::homePath().size(), QStringLiteral("~"));
                o.insert(QStringLiteral("folder"), cwd);
            } else {
                o.insert(QStringLiteral("program"), QString());
            }
        } else if (!s.local) {
            o.insert(QStringLiteral("local"), false);   // gdziekolwiek otwarty na sieć — pokazujemy to
        }
        rows.insert(key, o);
    }
    QJsonArray out;
    for (const QJsonObject &o : std::as_const(rows))
        out.append(o);
    return out;
}

void Ports::refresh()
{
    m_ports = scan().toVariantList();
    Q_EMIT changed();
}

bool Ports::end(int pid, bool force)
{
    if (pid <= 1 || QFileInfo(QStringLiteral("/proc/%1").arg(pid)).ownerId() != getuid())
        return false;
    const bool ok = ::kill(pid, force ? SIGKILL : SIGTERM) == 0;
    QTimer::singleShot(400, this, &Ports::refresh);
    return ok;
}

void Ports::openInBrowser(int port) const
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("http://localhost:%1").arg(port)));
}

int Ports::runCli(const QStringList &args)
{
    auto print = [](const QString &s) {
        const QByteArray b = s.toUtf8();
        std::fwrite(b.constData(), 1, size_t(b.size()), stdout);
    };
    const QJsonArray ports = scan();
    if (args.value(0) == QLatin1String("zakoncz-port")) {
        const int port = args.value(1).toInt();
        for (const QJsonValue &v : ports) {
            const QJsonObject o = v.toObject();
            if (o.value(QStringLiteral("port")).toInt() != port)
                continue;
            const int pid = o.value(QStringLiteral("pid")).toInt();
            if (!pid) {
                print(QStringLiteral("Port %1 ma proces systemowy albo innego użytkownika — nie mogę go zakończyć.\n").arg(port));
                return 1;
            }
            Ports p;
            if (!p.end(pid, args.contains(QLatin1String("--teraz")))) {
                print(QStringLiteral("Nie udało się zakończyć %1 (PID %2).\n").arg(o.value(QStringLiteral("program")).toString()).arg(pid));
                return 1;
            }
            print(QStringLiteral("Zakończono %1 (PID %2), port %3 jest wolny.\n").arg(o.value(QStringLiteral("program")).toString()).arg(pid).arg(port));
            return 0;
        }
        print(QStringLiteral("Nic nie nasłuchuje na porcie %1.\n").arg(port));
        return 1;
    }
    if (args.contains(QLatin1String("--json"))) {
        print(QString::fromUtf8(QJsonDocument(ports).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
        return 0;
    }
    if (ports.isEmpty())
        print(QStringLiteral("Nic nie nasłuchuje na portach.\n"));
    for (const QJsonValue &v : ports) {
        const QJsonObject o = v.toObject();
        const QString who = o.value(QStringLiteral("pid")).toInt()
                                ? QStringLiteral("%1 (PID %2) w %3").arg(o.value(QStringLiteral("program")).toString()).arg(o.value(QStringLiteral("pid")).toInt())
                                      .arg(o.value(QStringLiteral("folder")).toString())
                                : QStringLiteral("system");
        print(QStringLiteral("%1/%2  %3  %4\n")
                  .arg(o.value(QStringLiteral("port")).toInt())
                  .arg(o.value(QStringLiteral("proto")).toString(),
                       o.value(QStringLiteral("local")).toBool() ? QStringLiteral("tylko ten komputer") : QStringLiteral("cała sieć"), who));
    }
    return 0;
}

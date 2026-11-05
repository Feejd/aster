#include "portmodel.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QUrl>
#include <algorithm>
#include <unistd.h>

namespace {

struct Socket {
    int port = 0;
    QString proto, address;
};

// Adres z /proc/net: szesnastkowo, w kolejności bajtów procesora (little-endian na x86 i ARM)
QString decodeAddress(const QByteArray &hex)
{
    if (hex.size() == 8) {
        const quint32 v = hex.toUInt(nullptr, 16);
        return QStringLiteral("%1.%2.%3.%4").arg(v & 0xff).arg((v >> 8) & 0xff).arg((v >> 16) & 0xff).arg(v >> 24);
    }
    // IPv6: cztery słowa 32-bitowe, każde odwrócone
    QByteArray bytes;
    for (int w = 0; w < 4; ++w) {
        const QByteArray word = hex.mid(w * 8, 8);
        for (int b = 3; b >= 0; --b)
            bytes.append(char(word.mid(b * 2, 2).toUInt(nullptr, 16)));
    }
    if (bytes == QByteArray(16, '\0'))
        return QStringLiteral("::");
    if (bytes == QByteArray(15, '\0') + '\1')
        return QStringLiteral("::1");
    if (bytes.startsWith(QByteArray(10, '\0') + "\xff\xff"))       // ::ffff:a.b.c.d
        return QStringLiteral("%1.%2.%3.%4").arg(uchar(bytes[12])).arg(uchar(bytes[13])).arg(uchar(bytes[14])).arg(uchar(bytes[15]));
    QStringList parts;
    for (int i = 0; i < 16; i += 2)
        parts << QString::number((uchar(bytes[i]) << 8) | uchar(bytes[i + 1]), 16);
    return parts.join(QLatin1Char(':'));
}

QString scopeOf(const QString &addr)
{
    if (addr == QLatin1String("0.0.0.0") || addr == QLatin1String("::"))
        return QStringLiteral("Wszystkie sieci");
    if (addr.startsWith(QLatin1String("127.")) || addr == QLatin1String("::1"))
        return QStringLiteral("Tylko ten komputer");
    return addr;
}

// Gniazda nasłuchujące: TCP w stanie LISTEN (0A), UDP związane z portem (bez połączonych — stan 07)
void readTable(const QString &file, const QString &proto, bool tcp, QHash<quint64, Socket> &out)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return;
    f.readLine();
    while (!f.atEnd()) {
        const QList<QByteArray> c = f.readLine().simplified().split(' ');
        if (c.size() < 10)
            continue;
        const QByteArray state = c.at(3);
        if (tcp ? state != "0A" : state != "07")
            continue;
        const QList<QByteArray> local = c.at(1).split(':');
        const QList<QByteArray> remote = c.at(2).split(':');
        if (local.size() != 2 || (!tcp && remote.value(1) != "0000"))
            continue;
        Socket s;
        s.port = local.at(1).toInt(nullptr, 16);
        s.proto = proto;
        s.address = decodeAddress(local.at(0));
        if (s.port > 0)
            out.insert(c.at(9).toULongLong(), s);
    }
}

} // namespace

PortModel::PortModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &PortModel::refresh);
}

void PortModel::setActive(bool on)
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

void PortModel::setFilter(const QString &f)
{
    if (f == m_filter)
        return;
    m_filter = f;
    Q_EMIT filterChanged();
    applyFilter();
}

void PortModel::refresh()
{
    QHash<quint64, Socket> sockets;
    readTable(QStringLiteral("/proc/net/tcp"), QStringLiteral("TCP"), true, sockets);
    readTable(QStringLiteral("/proc/net/tcp6"), QStringLiteral("TCP"), true, sockets);
    readTable(QStringLiteral("/proc/net/udp"), QStringLiteral("UDP"), false, sockets);
    readTable(QStringLiteral("/proc/net/udp6"), QStringLiteral("UDP"), false, sockets);

    // Właściciel gniazda: proces, który ma je wśród otwartych plików (czytelne tylko dla własnych procesów)
    QHash<quint64, int> owner;
    const QStringList pids = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &p : pids) {
        bool ok = false;
        const int pid = p.toInt(&ok);
        if (!ok)
            continue;
        const QString fdDir = QStringLiteral("/proc/%1/fd").arg(pid);
        const QStringList fds = QDir(fdDir).entryList(QDir::Files | QDir::System | QDir::NoDotAndDotDot);
        for (const QString &fd : fds) {
            const QString target = QFile::symLinkTarget(fdDir + QLatin1Char('/') + fd);
            if (!target.contains(QLatin1String("socket:[")))
                continue;
            const quint64 inode = target.section(QLatin1Char('['), 1).chopped(1).toULongLong();
            if (sockets.contains(inode) && !owner.contains(inode))
                owner.insert(inode, pid);
        }
    }

    QList<Entry> all;
    QSet<QString> seen;          // ten sam program na IPv4 i IPv6 — jeden wiersz
    m_hidden = 0;
    for (auto it = sockets.cbegin(); it != sockets.cend(); ++it) {
        Entry e;
        e.port = it->port;
        e.proto = it->proto;
        e.address = it->address;
        e.scope = scopeOf(it->address);
        e.pid = owner.value(it.key());
        if (e.pid) {
            QFile comm(QStringLiteral("/proc/%1/comm").arg(e.pid));
            if (comm.open(QIODevice::ReadOnly))
                e.name = QString::fromUtf8(comm.readAll()).trimmed();
            QFile cmd(QStringLiteral("/proc/%1/cmdline").arg(e.pid));
            if (cmd.open(QIODevice::ReadOnly)) {
                QList<QByteArray> args = cmd.readAll().split('\0');
                while (!args.isEmpty() && args.last().isEmpty())
                    args.removeLast();
                QStringList shown;
                for (const QByteArray &a : std::as_const(args))
                    shown << QString::fromUtf8(a);
                if (!shown.isEmpty())
                    shown[0] = QFileInfo(shown[0]).fileName();
                e.command = shown.join(QLatin1Char(' '));
            }
            e.own = QFileInfo(QStringLiteral("/proc/%1").arg(e.pid)).ownerId() == getuid();
        } else {
            e.name = QStringLiteral("System albo inny użytkownik");
            ++m_hidden;
        }
        const QString id = QStringLiteral("%1/%2/%3/%4").arg(e.proto).arg(e.port).arg(e.pid).arg(e.scope);
        if (seen.contains(id))
            continue;
        seen.insert(id);
        all << e;
    }
    std::sort(all.begin(), all.end(), [](const Entry &a, const Entry &b) {
        // Najpierw własne programy (to je zwykle trzeba zamknąć), potem po numerze portu
        if (a.own != b.own)
            return a.own;
        if (a.port != b.port)
            return a.port < b.port;
        return a.proto < b.proto;
    });
    m_all = all;
    applyFilter();
}

void PortModel::applyFilter()
{
    QList<Entry> rows;
    const QString f = m_filter.trimmed();
    for (const Entry &e : std::as_const(m_all)) {
        if (!f.isEmpty() && !QString::number(e.port).startsWith(f) && !e.name.contains(f, Qt::CaseInsensitive)
            && !e.command.contains(f, Qt::CaseInsensitive) && QString::number(e.pid) != f)
            continue;
        rows << e;
    }
    beginResetModel();
    m_rows = rows;
    endResetModel();
    Q_EMIT updated();
}

int PortModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant PortModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Entry &e = m_rows.at(index.row());
    switch (role) {
    case PortRole: return e.port;
    case ProtoRole: return e.proto;
    case AddressRole: return e.address;
    case ScopeRole: return e.scope;
    case PidRole: return e.pid;
    case NameRole: return e.name;
    case CommandRole: return e.command;
    case KeyRole: return e.pid ? QStringLiteral("p:%1").arg(e.pid) : QString();
    case OwnRole: return e.own;
    }
    return {};
}

QHash<int, QByteArray> PortModel::roleNames() const
{
    return {{PortRole, "port"}, {ProtoRole, "proto"}, {AddressRole, "address"}, {ScopeRole, "scope"}, {PidRole, "pid"},
            {NameRole, "name"}, {CommandRole, "command"}, {KeyRole, "key"}, {OwnRole, "own"}};
}

void PortModel::openInBrowser(int port) const
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("http://localhost:%1").arg(port)));
}

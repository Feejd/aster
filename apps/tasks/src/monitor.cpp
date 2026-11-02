#include "monitor.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QSysInfo>
#include <cmath>

namespace {

QByteArray readAll(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

QString readLine(const QString &path)
{
    return QString::fromUtf8(readAll(path)).trimmed();
}

qint64 nowMs()
{
    static QElapsedTimer t;
    if (!t.isValid())
        t.start();
    return t.elapsed();
}

QVariantMap stat(const QString &label, const QString &value)
{
    return {{QStringLiteral("label"), label}, {QStringLiteral("value"), value}};
}

// Ładna górna granica wykresu sieci (1, 2, 5 × 10^n)
double niceCeil(double v)
{
    if (v <= 0)
        return 1;
    const double p = std::pow(10.0, std::floor(std::log10(v)));
    for (double m : {1.0, 2.0, 5.0, 10.0})
        if (v <= m * p)
            return m * p;
    return 10 * p;
}

} // namespace

QVariantList Monitor::Series::list() const
{
    QVariantList out;
    out.reserve(values.size());
    for (double v : values)
        out.append(v);
    return out;
}

Monitor::Monitor(QObject *parent)
    : QObject(parent)
{
    // Procesor: nazwa, rdzenie, częstotliwość maksymalna
    const QString info = QString::fromUtf8(readAll(QStringLiteral("/proc/cpuinfo")));
    QSet<QString> cores;
    QString physical;
    m_threads = 0;
    for (const QString &line : info.split(QLatin1Char('\n'))) {
        const QString key = line.section(QLatin1Char(':'), 0, 0).trimmed();
        const QString value = line.section(QLatin1Char(':'), 1).trimmed();
        if (key == QLatin1String("processor"))
            ++m_threads;
        else if (key == QLatin1String("model name") && m_cpuName.isEmpty())
            m_cpuName = value;
        else if (key == QLatin1String("physical id"))
            physical = value;
        else if (key == QLatin1String("core id"))
            cores.insert(physical + QLatin1Char(':') + value);
    }
    m_threads = std::max(1, m_threads);
    m_cores = cores.isEmpty() ? m_threads : int(cores.size());
    if (m_cpuName.isEmpty()) {
        const QString model = QString::fromUtf8(readAll(QStringLiteral("/sys/firmware/devicetree/base/model"))).remove(QChar(0)).trimmed();
        const QString arch = QSysInfo::currentCpuArchitecture();
        m_cpuName = !model.isEmpty() ? model
            : arch.startsWith(QLatin1String("arm")) ? QStringLiteral("Procesor ARM (%1 rdzenie)").arg(m_threads)
                                                   : QStringLiteral("%1 procesory logiczne").arg(m_threads);
    }
    m_cpuName.replace(QRegularExpression(QStringLiteral("\\((R|TM)\\)")), QString());
    m_cpuName.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    m_maxFreq = readLine(QStringLiteral("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")).toDouble() / 1e6;   // GHz

    QSettings s;
    m_interval = s.value(QStringLiteral("interval"), 1000).toInt();
    m_timer.setInterval(m_interval > 0 ? m_interval : 1000);
    connect(&m_timer, &QTimer::timeout, this, &Monitor::tick);
    tick();
    QTimer::singleShot(250, this, &Monitor::tick);      // szybki drugi odczyt — od razu są wartości procesora
    if (m_interval > 0)
        m_timer.start();
}

Monitor *Monitor::create(QQmlEngine *, QJSEngine *)
{
    static Monitor *instance = new Monitor;
    QJSEngine::setObjectOwnership(instance, QJSEngine::CppOwnership);
    return instance;
}

void Monitor::setInterval(int ms)
{
    if (ms == m_interval)
        return;
    m_interval = ms;
    QSettings().setValue(QStringLiteral("interval"), ms);
    if (ms > 0) {
        m_timer.setInterval(ms);
        m_timer.start();
    } else {
        m_timer.stop();
    }
    Q_EMIT intervalChanged();
}

void Monitor::refreshNow()
{
    tick();
}

void Monitor::tick()
{
    const qint64 now = nowMs();
    const double secs = m_lastMs ? std::max(0.05, (now - m_lastMs) / 1000.0) : 0;
    m_lastMs = now;
    readCpu(secs);
    readMemory();
    readDisks(secs);
    readNet(secs);
    m_processes.refresh();
    publish();
    Q_EMIT updated();
}

void Monitor::readCpu(double secs)
{
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/stat")).split('\n');
    int core = 0;
    for (const QByteArray &line : lines) {
        if (!line.startsWith("cpu"))
            continue;
        const QList<QByteArray> f = line.simplified().split(' ');
        if (f.size() < 8)
            continue;
        CpuTimes t;
        for (int i = 1; i < f.size() && i <= 8; ++i)
            t.total += f.at(i).toULongLong();
        t.busy = t.total - f.at(4).toULongLong() - f.at(5).toULongLong();       // bez idle i iowait
        const bool all = f.at(0) == "cpu";
        CpuTimes &prev = all ? m_total : (core < m_coreTimes.size() ? m_coreTimes[core] : m_coreTimes.emplaceBack());
        double v = 0;
        if (secs > 0 && t.total > prev.total)
            v = std::clamp((t.busy - std::min(t.busy, prev.busy)) * 100.0 / (t.total - prev.total), 0.0, 100.0);
        prev = t;
        if (all) {
            m_cpu = v;
            if (secs > 0)
                m_cpuHistory.push(v);
        } else {
            if (m_coreHistory.size() <= core) {
                m_coreHistory.append(Series{});
                m_coreValues.append(0);
            }
            m_coreValues[core] = v;
            if (secs > 0)
                m_coreHistory[core].push(v);
            ++core;
        }
    }

    // Częstotliwość: średnia z rdzeni (cpufreq), inaczej „cpu MHz” z /proc/cpuinfo
    double sum = 0;
    int n = 0;
    for (int i = 0; i < m_threads; ++i) {
        const double khz = readLine(QStringLiteral("/sys/devices/system/cpu/cpu%1/cpufreq/scaling_cur_freq").arg(i)).toDouble();
        if (khz > 0) {
            sum += khz / 1e6;
            ++n;
        }
    }
    if (n == 0) {
        for (const QString &line : QString::fromUtf8(readAll(QStringLiteral("/proc/cpuinfo"))).split(QLatin1Char('\n')))
            if (line.startsWith(QLatin1String("cpu MHz"))) {
                sum += line.section(QLatin1Char(':'), 1).trimmed().toDouble() / 1000;
                ++n;
            }
    }
    m_freq = n ? sum / n : 0;
}

void Monitor::readMemory()
{
    QHash<QByteArray, double> m;
    for (const QByteArray &line : readAll(QStringLiteral("/proc/meminfo")).split('\n')) {
        const int colon = line.indexOf(':');
        if (colon > 0)
            m.insert(line.left(colon), line.mid(colon + 1).simplified().split(' ').value(0).toDouble() * 1024);
    }
    m_memTotal = m.value("MemTotal");
    m_memAvail = m.value("MemAvailable");
    m_memUsed = m_memTotal - m_memAvail;
    m_memCached = m.value("Cached") + m.value("Buffers") + m.value("SReclaimable");
    m_swapTotal = m.value("SwapTotal");
    m_swapUsed = m_swapTotal - m.value("SwapFree");
    m_memCommit = m.value("Committed_AS");
    m_memHistory.push(memPercent());
}

void Monitor::readDisks(double secs)
{
    static const QRegularExpression real(QStringLiteral("^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme\\d+n\\d+|mmcblk\\d+)$"));
    for (Disk &d : m_disks)
        d.seen = false;
    for (const QByteArray &line : readAll(QStringLiteral("/proc/diskstats")).split('\n')) {
        const QList<QByteArray> f = line.simplified().split(' ');
        if (f.size() < 13)
            continue;
        const QString name = QString::fromLatin1(f.at(2));
        if (!real.match(name).hasMatch())
            continue;
        const qulonglong read = f.at(5).toULongLong() * 512, written = f.at(9).toULongLong() * 512, io = f.at(12).toULongLong();
        auto it = m_disks.find(name);
        if (it == m_disks.end()) {
            Disk d;
            d.name = name;
            const QString sys = QStringLiteral("/sys/block/") + name;
            d.model = readLine(sys + QLatin1String("/device/model"));
            d.size = readLine(sys + QLatin1String("/size")).toDouble() * 512;
            const bool removable = readLine(sys + QLatin1String("/removable")) == QLatin1String("1");
            if (removable || QFileInfo(sys).canonicalFilePath().contains(QLatin1String("/usb")))
                d.type = QStringLiteral("Wymienny (USB)");
            else if (name.startsWith(QLatin1String("nvme")))
                d.type = QStringLiteral("SSD (NVMe)");
            else if (name.startsWith(QLatin1String("vd")) || name.startsWith(QLatin1String("xvd")))
                d.type = QStringLiteral("Dysk wirtualny");
            else if (readLine(sys + QLatin1String("/queue/rotational")) == QLatin1String("1"))
                d.type = QStringLiteral("HDD");
            else
                d.type = QStringLiteral("SSD");
            if (d.size <= 0)
                continue;                       // pusty czytnik kart itp.
            d.read = read;
            d.written = written;
            d.ioMs = io;
            it = m_disks.insert(name, d);
            m_diskOrder.append(name);
            std::sort(m_diskOrder.begin(), m_diskOrder.end());
        } else if (secs > 0) {
            it->readRate = (read - std::min(read, it->read)) / secs;
            it->writeRate = (written - std::min(written, it->written)) / secs;
            it->active = std::clamp((io - std::min(io, it->ioMs)) / (secs * 10.0), 0.0, 100.0);
            it->history.push(it->active);
            it->read = read;
            it->written = written;
            it->ioMs = io;
        }
        it->seen = true;
    }
    m_diskPercent = 0;
    for (auto it = m_disks.begin(); it != m_disks.end();) {
        if (!it->seen) {
            m_diskOrder.removeAll(it.key());
            it = m_disks.erase(it);
            continue;
        }
        m_diskPercent = std::max(m_diskPercent, it->active);
        ++it;
    }
}

void Monitor::readNet(double secs)
{
    static const QRegularExpression virt(QStringLiteral("^(lo|virbr|docker|veth|br-|tun|tap|vnet|podman|cni|flannel|wg)"));
    for (Net &n : m_nets)
        n.seen = false;
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/net/dev")).split('\n');
    for (int i = 2; i < lines.size(); ++i) {
        const QByteArray &line = lines.at(i);
        const int colon = line.indexOf(':');
        if (colon < 0)
            continue;
        const QString name = QString::fromLatin1(line.left(colon).trimmed());
        if (virt.match(name).hasMatch())
            continue;
        const QList<QByteArray> f = line.mid(colon + 1).simplified().split(' ');
        if (f.size() < 9)
            continue;
        const qulonglong rx = f.at(0).toULongLong(), tx = f.at(8).toULongLong();
        auto it = m_nets.find(name);
        if (it == m_nets.end()) {
            Net n;
            n.name = name;
            n.type = QFileInfo::exists(QStringLiteral("/sys/class/net/%1/wireless").arg(name)) || name.startsWith(QLatin1String("wl"))
                ? QStringLiteral("Wi‑Fi")
                : name.startsWith(QLatin1String("ww")) ? QStringLiteral("Sieć komórkowa") : QStringLiteral("Ethernet");
            n.rx = rx;
            n.tx = tx;
            it = m_nets.insert(name, n);
            m_netOrder.append(name);
        } else if (secs > 0) {
            it->rxRate = (rx - std::min(rx, it->rx)) / secs;
            it->txRate = (tx - std::min(tx, it->tx)) / secs;
            it->rxHistory.push(it->rxRate);
            it->txHistory.push(it->txRate);
            it->rx = rx;
            it->tx = tx;
        }
        it->seen = true;
    }
    for (auto it = m_nets.begin(); it != m_nets.end();) {
        if (!it->seen) {
            m_netOrder.removeAll(it.key());
            it = m_nets.erase(it);
        } else {
            ++it;
        }
    }
}

QString Monitor::uptime() const
{
    const qint64 s = qint64(readLine(QStringLiteral("/proc/uptime")).section(QLatin1Char(' '), 0, 0).toDouble());
    const qint64 d = s / 86400, h = (s / 3600) % 24, m = (s / 60) % 60, sec = s % 60;
    const QString clock = QStringLiteral("%1:%2:%3").arg(h).arg(m, 2, 10, QLatin1Char('0')).arg(sec, 2, 10, QLatin1Char('0'));
    return d > 0 ? QStringLiteral("%1 d %2").arg(d).arg(clock) : clock;
}

void Monitor::publish()
{
    const QLocale pl(QLocale::Polish);
    QVariantList out;

    QVariantList cpuStats{stat(QStringLiteral("Wykorzystanie"), percent(m_cpu))};
    if (m_freq > 0)
        cpuStats << stat(QStringLiteral("Szybkość"), pl.toString(m_freq, 'f', 2) + QStringLiteral(" GHz"));
    cpuStats << stat(QStringLiteral("Procesy"), pl.toString(m_processes.processCount()))
             << stat(QStringLiteral("Wątki"), pl.toString(m_processes.threadCount()))
             << stat(QStringLiteral("Czas działania"), uptime())
             << stat(QStringLiteral("Rdzenie"), pl.toString(m_cores))
             << stat(QStringLiteral("Procesory logiczne"), pl.toString(m_threads));
    if (m_maxFreq > 0)
        cpuStats << stat(QStringLiteral("Szybkość maksymalna"), pl.toString(m_maxFreq, 'f', 2) + QStringLiteral(" GHz"));
    out << QVariantMap{{QStringLiteral("id"), QStringLiteral("cpu")},
                       {QStringLiteral("kind"), QStringLiteral("cpu")},
                       {QStringLiteral("title"), QStringLiteral("Procesor")},
                       {QStringLiteral("device"), m_cpuName},
                       {QStringLiteral("subtitle"), percent(m_cpu) + (m_freq > 0 ? QStringLiteral("  ") + pl.toString(m_freq, 'f', 2) + QStringLiteral(" GHz") : QString())},
                       {QStringLiteral("value"), m_cpu},
                       {QStringLiteral("max"), 100},
                       {QStringLiteral("color"), QStringLiteral("#5B8CFF")},
                       {QStringLiteral("caption"), QStringLiteral("% wykorzystania")},
                       {QStringLiteral("history"), m_cpuHistory.list()},
                       {QStringLiteral("stats"), cpuStats}};

    QVariantList memStats{stat(QStringLiteral("Używana"), bytes(m_memUsed)),
                          stat(QStringLiteral("Dostępna"), bytes(m_memAvail)),
                          stat(QStringLiteral("W pamięci podręcznej"), bytes(m_memCached)),
                          stat(QStringLiteral("Przydzielona"), bytes(m_memCommit))};
    if (m_swapTotal > 0)
        memStats << stat(QStringLiteral("Plik wymiany"), bytes(m_swapUsed) + QStringLiteral(" z ") + bytes(m_swapTotal));
    out << QVariantMap{{QStringLiteral("id"), QStringLiteral("mem")},
                       {QStringLiteral("kind"), QStringLiteral("mem")},
                       {QStringLiteral("title"), QStringLiteral("Pamięć")},
                       {QStringLiteral("device"), bytes(m_memTotal)},
                       {QStringLiteral("subtitle"), bytes(m_memUsed) + QStringLiteral(" z ") + bytes(m_memTotal) + QStringLiteral(" (") + percent(memPercent()) + QLatin1Char(')')},
                       {QStringLiteral("value"), memPercent()},
                       {QStringLiteral("max"), 100},
                       {QStringLiteral("color"), QStringLiteral("#B072FF")},
                       {QStringLiteral("caption"), QStringLiteral("Używana pamięć")},
                       {QStringLiteral("history"), m_memHistory.list()},
                       {QStringLiteral("stats"), memStats}};

    int index = 0;
    for (const QString &name : std::as_const(m_diskOrder)) {
        const Disk &d = m_disks[name];
        out << QVariantMap{{QStringLiteral("id"), QLatin1String("disk:") + name},
                           {QStringLiteral("kind"), QStringLiteral("disk")},
                           {QStringLiteral("title"), QStringLiteral("Dysk %1 (%2)").arg(index++).arg(name)},
                           {QStringLiteral("device"), d.model.isEmpty() ? d.type : d.model},
                           {QStringLiteral("subtitle"), d.type + QStringLiteral("  ") + percent(d.active)},
                           {QStringLiteral("value"), d.active},
                           {QStringLiteral("max"), 100},
                           {QStringLiteral("color"), QStringLiteral("#2BC48A")},
                           {QStringLiteral("caption"), QStringLiteral("Czas aktywności")},
                           {QStringLiteral("history"), d.history.list()},
                           {QStringLiteral("stats"), QVariantList{stat(QStringLiteral("Aktywność"), percent(d.active)),
                                                                   stat(QStringLiteral("Odczyt"), rate(d.readRate)),
                                                                   stat(QStringLiteral("Zapis"), rate(d.writeRate)),
                                                                   stat(QStringLiteral("Pojemność"), bytes(d.size)),
                                                                   stat(QStringLiteral("Typ"), d.type)}}};
    }

    for (const QString &name : std::as_const(m_netOrder)) {
        const Net &n = m_nets[name];
        double peak = 0;
        for (double v : n.rxHistory.values)
            peak = std::max(peak, v);
        for (double v : n.txHistory.values)
            peak = std::max(peak, v);
        out << QVariantMap{{QStringLiteral("id"), QLatin1String("net:") + name},
                           {QStringLiteral("kind"), QStringLiteral("net")},
                           {QStringLiteral("title"), n.type},
                           {QStringLiteral("device"), name},
                           {QStringLiteral("subtitle"), QStringLiteral("↑ ") + bits(n.txRate) + QStringLiteral("  ↓ ") + bits(n.rxRate)},
                           {QStringLiteral("value"), 0},
                           {QStringLiteral("max"), niceCeil(std::max(peak * 1.15, 125000.0 / 8))},    // co najmniej 125 kb/s
                           {QStringLiteral("color"), QStringLiteral("#FF9F43")},
                           {QStringLiteral("color2"), QStringLiteral("#FFD08A")},
                           {QStringLiteral("caption"), QStringLiteral("Przepustowość")},
                           {QStringLiteral("legend"), QStringLiteral("Pobieranie")},
                           {QStringLiteral("legend2"), QStringLiteral("Wysyłanie")},
                           {QStringLiteral("history"), n.rxHistory.list()},
                           {QStringLiteral("history2"), n.txHistory.list()},
                           {QStringLiteral("stats"), QVariantList{stat(QStringLiteral("Pobieranie"), bits(n.rxRate)),
                                                                   stat(QStringLiteral("Wysyłanie"), bits(n.txRate)),
                                                                   stat(QStringLiteral("Odebrano od startu"), bytes(n.rx)),
                                                                   stat(QStringLiteral("Wysłano od startu"), bytes(n.tx)),
                                                                   stat(QStringLiteral("Karta sieciowa"), name)}}};
    }
    m_resources = out;

    m_coreList.clear();
    for (int i = 0; i < m_coreHistory.size(); ++i)
        m_coreList << QVariantMap{{QStringLiteral("value"), m_coreValues.value(i)}, {QStringLiteral("history"), m_coreHistory.at(i).list()}};
}

QString Monitor::bytes(double b) const
{
    const QLocale pl(QLocale::Polish);
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int u = 0;
    while (b >= 1024 && u < 4) {
        b /= 1024;
        ++u;
    }
    return pl.toString(b, 'f', u == 0 ? 0 : (b < 10 ? 1 : 0)) + QLatin1Char(' ') + QLatin1String(units[u]);
}

QString Monitor::rate(double bytesPerSec) const
{
    return bytesPerSec < 1 ? QStringLiteral("0 MB/s") : bytes(bytesPerSec) + QStringLiteral("/s");
}

QString Monitor::bits(double bytesPerSec) const
{
    const QLocale pl(QLocale::Polish);
    double v = bytesPerSec * 8;
    static const char *units[] = {"b/s", "kb/s", "Mb/s", "Gb/s"};
    int u = 0;
    while (v >= 1000 && u < 3) {
        v /= 1000;
        ++u;
    }
    return pl.toString(v, 'f', u == 0 || v >= 10 ? 0 : 1) + QLatin1Char(' ') + QLatin1String(units[u]);
}

QString Monitor::percent(double v) const
{
    const QLocale pl(QLocale::Polish);
    if (v > 0 && v < 0.95)
        return pl.toString(v, 'f', 1) + QLatin1Char('%');
    return pl.toString(std::round(v), 'f', 0) + QLatin1Char('%');
}

void Monitor::launch(const QString &program, const QStringList &args) const
{
    QProcess::startDetached(program, args);
}

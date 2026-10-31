#include "system.h"

#include <QDateTime>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>

#include <pwd.h>
#include <unistd.h>

static QString readFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

// Pola wyjścia „nmcli -t”: rozdzielone „:”, a „:” w wartości jest poprzedzony „\”
static QStringList nmFields(const QString &line)
{
    QStringList out;
    QString cur;
    for (int i = 0; i < line.size(); ++i) {
        if (line[i] == QLatin1Char('\\') && i + 1 < line.size()) {
            cur += line[++i];
        } else if (line[i] == QLatin1Char(':')) {
            out << cur;
            cur.clear();
        } else {
            cur += line[i];
        }
    }
    out << cur;
    return out;
}

static QString gigabytes(qint64 bytes)
{
    const double gb = bytes / 1e9;
    return gb >= 100 ? QString::number(qRound(gb)) + QStringLiteral(" GB") : QString::number(gb, 'f', 1).replace(QLatin1Char('.'), QLatin1Char(',')) + QStringLiteral(" GB");
}

static const QRegularExpression macRe(QStringLiteral("^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"));

System::System(QObject *parent)
    : QObject(parent)
{
    m_preview = !qEnvironmentVariableIsEmpty("ASTER_PREVIEW");
    m_volumeDelay.setSingleShot(true);
    m_volumeDelay.setInterval(50);
    connect(&m_volumeDelay, &QTimer::timeout, this, [this] {
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(m_volume, 'f', 3)});
    });
    if (m_preview) {
        fillPreview();
        return;
    }
    m_poll.setInterval(4000);
    connect(&m_poll, &QTimer::timeout, this, &System::refresh);
    m_poll.start();
    refresh();
}

void System::fillPreview()
{
    m_wifiAvailable = m_wifiOn = true;
    auto net = [](const QString &ssid, int signal, bool secure, bool active, bool known) {
        return QVariantMap{{QStringLiteral("ssid"), ssid}, {QStringLiteral("signal"), signal}, {QStringLiteral("secure"), secure},
                           {QStringLiteral("active"), active}, {QStringLiteral("known"), known}};
    };
    m_networks = {net(QStringLiteral("Dom 5G"), 88, true, true, true), net(QStringLiteral("Dom"), 70, true, false, true),
                  net(QStringLiteral("Kawiarnia Aster"), 54, false, false, false), net(QStringLiteral("UPC4471023"), 41, true, false, false),
                  net(QStringLiteral("Sąsiad_2.4"), 22, true, false, false)};
    m_btAvailable = m_btOn = true;
    auto dev = [](const QString &name, bool paired, bool connected, const QString &kind) {
        return QVariantMap{{QStringLiteral("mac"), QStringLiteral("00:11:22:33:44:55")}, {QStringLiteral("name"), name},
                           {QStringLiteral("paired"), paired}, {QStringLiteral("connected"), connected}, {QStringLiteral("kind"), kind}};
    };
    m_devices = {dev(QStringLiteral("Słuchawki"), true, true, QStringLiteral("headphones")), dev(QStringLiteral("Mysz MX"), true, false, QStringLiteral("mouse")),
                 dev(QStringLiteral("Głośnik w kuchni"), false, false, QStringLiteral("speaker"))};
    auto out = [](int id, const QString &name, bool def) {
        return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("default"), def}};
    };
    m_outputs = {out(47, QStringLiteral("Głośniki wbudowane"), false), out(52, QStringLiteral("Słuchawki"), true), out(55, QStringLiteral("Monitor HDMI"), false)};
    m_inputs = {out(48, QStringLiteral("Mikrofon wbudowany"), true)};
    m_volume = 0.62;
}

void System::refresh()
{
    if (m_preview)
        return;
    readNetwork();
    readBluetooth();
    readAudio();
    readDisplay();
}

void System::query(const QString &key, const QString &program, const QStringList &args, std::function<void(const QString &, int)> done)
{
    if (!key.isEmpty() && m_running.contains(key))
        return;
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        done(QString(), -1);
        return;
    }
    if (!key.isEmpty())
        m_running.insert(key);
    auto *p = new QProcess(this);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p->setProcessEnvironment(env);
    connect(p, &QProcess::finished, this, [this, p, key, done](int code) {
        m_running.remove(key);
        done(QString::fromUtf8(p->readAllStandardOutput()), code);
        p->deleteLater();
    });
    p->start(program, args);
}

// ——— O komputerze ———
QVariantMap System::about() const
{
    QVariantMap m;
    QString os;
    for (const QString &line : readFile(QStringLiteral("/etc/os-release")).split(QLatin1Char('\n')))
        if (line.startsWith(QLatin1String("PRETTY_NAME=")))
            os = line.mid(12).remove(QLatin1Char('"'));
    m.insert(QStringLiteral("os"), os.isEmpty() ? QSysInfo::prettyProductName() : os);
    m.insert(QStringLiteral("kernel"), QSysInfo::kernelVersion());
    m.insert(QStringLiteral("host"), QSysInfo::machineHostName());

    QString model = (readFile(QStringLiteral("/sys/class/dmi/id/sys_vendor")) + QLatin1Char(' ') + readFile(QStringLiteral("/sys/class/dmi/id/product_name"))).trimmed();
    if (model.isEmpty())
        model = readFile(QStringLiteral("/proc/device-tree/model")).remove(QChar(0));
    m.insert(QStringLiteral("model"), model.isEmpty() ? QStringLiteral("Komputer") : model);

    QString cpu;
    for (const QString &line : readFile(QStringLiteral("/proc/cpuinfo")).split(QLatin1Char('\n')))
        if (line.startsWith(QLatin1String("model name"))) {
            cpu = line.section(QLatin1Char(':'), 1).simplified();
            break;
        }
    if (cpu.isEmpty())
        cpu = QSysInfo::currentCpuArchitecture();
    m.insert(QStringLiteral("cpu"), cpu + QStringLiteral(" · ") + QString::number(QThread::idealThreadCount()) + QStringLiteral(" wątków"));

    qint64 memKb = 0;
    for (const QString &line : readFile(QStringLiteral("/proc/meminfo")).split(QLatin1Char('\n')))
        if (line.startsWith(QLatin1String("MemTotal:")))
            memKb = line.section(QLatin1Char(':'), 1).simplified().section(QLatin1Char(' '), 0, 0).toLongLong();
    m.insert(QStringLiteral("memory"), QString::number(qRound(memKb / 1024.0 / 1024.0)) + QStringLiteral(" GB"));

    const QStorageInfo root = QStorageInfo::root();
    m.insert(QStringLiteral("diskTotal"), gigabytes(root.bytesTotal()));
    m.insert(QStringLiteral("diskFree"), gigabytes(root.bytesAvailable()));
    m.insert(QStringLiteral("diskUsed"), root.bytesTotal() > 0 ? 1.0 - double(root.bytesAvailable()) / root.bytesTotal() : 0.0);

    const double up = readFile(QStringLiteral("/proc/uptime")).section(QLatin1Char(' '), 0, 0).toDouble();
    const int h = int(up / 3600), min = int(up / 60) % 60;
    m.insert(QStringLiteral("uptime"), h > 0 ? QStringLiteral("%1 godz. %2 min").arg(h).arg(min) : QStringLiteral("%1 min").arg(min));
    m.insert(QStringLiteral("qt"), QString::fromLatin1(qVersion()));
    return m;
}

QString System::userName() const
{
    return qEnvironmentVariable("USER", QStringLiteral("użytkownik"));
}

QString System::fullName() const
{
    if (const passwd *pw = getpwuid(getuid())) {
        const QString gecos = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        if (!gecos.isEmpty())
            return gecos;
    }
    return userName();
}

// ——— Wi‑Fi i sieć ———
void System::readNetwork()
{
    query(QStringLiteral("dev"), QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE,CONNECTION"), QStringLiteral("device")},
          [this](const QString &out, int) {
              bool wifi = false;
              QString wired;
              for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                  const QStringList f = nmFields(line);
                  if (f.size() < 3)
                      continue;
                  if (f[0] == QLatin1String("wifi"))
                      wifi = true;
                  else if (f[0] == QLatin1String("ethernet") && f[1] == QLatin1String("connected"))
                      wired = f[2];
              }
              m_wifiAvailable = wifi;
              m_wiredName = wired;
              query(QStringLiteral("radio"), QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")}, [this](const QString &radio, int) {
                  m_wifiOn = radio.trimmed() == QLatin1String("enabled");
                  if (!m_wifiAvailable || !m_wifiOn) {
                      m_networks.clear();
                      Q_EMIT networkChanged();
                      return;
                  }
                  // Znane sieci (zapisane połączenia) i widoczne sieci
                  query(QStringLiteral("known"), QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE"), QStringLiteral("connection"), QStringLiteral("show")},
                        [this](const QString &conns, int) {
                            QSet<QString> known;
                            for (const QString &line : conns.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                                const QStringList f = nmFields(line);
                                if (f.size() >= 2 && f[1] == QLatin1String("802-11-wireless"))
                                    known.insert(f[0]);
                            }
                            query(QStringLiteral("list"), QStringLiteral("nmcli"),
                                  {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"), QStringLiteral("device"), QStringLiteral("wifi"),
                                   QStringLiteral("list"), QStringLiteral("--rescan"), QStringLiteral("no")},
                                  [this, known](const QString &list, int) {
                                      QMap<QString, QVariantMap> best;
                                      for (const QString &line : list.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                                          const QStringList f = nmFields(line);
                                          if (f.size() < 4 || f[1].isEmpty())
                                              continue;
                                          const int signal = f[2].toInt();
                                          const bool active = f[0].trimmed() == QLatin1String("*");
                                          if (best.contains(f[1]) && best[f[1]].value(QStringLiteral("signal")).toInt() >= signal && !active)
                                              continue;
                                          best.insert(f[1], {{QStringLiteral("ssid"), f[1]}, {QStringLiteral("signal"), signal},
                                                             {QStringLiteral("secure"), !f[3].isEmpty() && f[3] != QLatin1String("--")},
                                                             {QStringLiteral("active"), active || best.value(f[1]).value(QStringLiteral("active")).toBool()},
                                                             {QStringLiteral("known"), known.contains(f[1])}});
                                      }
                                      QVariantList nets;
                                      for (const QVariantMap &n : best)
                                          nets << n;
                                      std::sort(nets.begin(), nets.end(), [](const QVariant &a, const QVariant &b) {
                                          const QVariantMap x = a.toMap(), y = b.toMap();
                                          if (x[QStringLiteral("active")] != y[QStringLiteral("active")])
                                              return x[QStringLiteral("active")].toBool();
                                          if (x[QStringLiteral("known")] != y[QStringLiteral("known")])
                                              return x[QStringLiteral("known")].toBool();
                                          return x[QStringLiteral("signal")].toInt() > y[QStringLiteral("signal")].toInt();
                                      });
                                      if (nets != m_networks) {
                                          m_networks = nets;
                                      }
                                      Q_EMIT networkChanged();
                                  });
                        });
              });
          });
}

void System::setWifi(bool on)
{
    m_wifiOn = on;
    if (!on)
        m_networks.clear();
    Q_EMIT networkChanged();
    if (!m_preview)
        query(QString(), QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), on ? QStringLiteral("on") : QStringLiteral("off")},
              [this](const QString &, int) { QTimer::singleShot(1500, this, &System::readNetwork); });
}

void System::scanWifi()
{
    if (m_preview || m_scanning)
        return;
    m_scanning = true;
    Q_EMIT networkChanged();
    query(QString(), QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("rescan")}, [this](const QString &, int) {
        QTimer::singleShot(2500, this, [this] {
            m_scanning = false;
            readNetwork();
        });
    });
}

void System::connectWifi(const QString &ssid, const QString &password)
{
    if (m_preview)
        return;
    m_connecting = ssid;
    Q_EMIT networkChanged();
    QStringList args;
    bool known = false;
    for (const QVariant &v : std::as_const(m_networks))
        if (v.toMap().value(QStringLiteral("ssid")).toString() == ssid)
            known = v.toMap().value(QStringLiteral("known")).toBool();
    if (known && password.isEmpty())
        args = {QStringLiteral("connection"), QStringLiteral("up"), QStringLiteral("id"), ssid};
    else if (password.isEmpty())
        args = {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid};
    else
        args = {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid, QStringLiteral("password"), password};
    query(QString(), QStringLiteral("nmcli"), args, [this, ssid](const QString &, int code) {
        m_connecting.clear();
        Q_EMIT networkChanged();
        Q_EMIT message(code == 0 ? QStringLiteral("Połączono z siecią „%1”").arg(ssid)
                                 : QStringLiteral("Nie udało się połączyć z „%1” — sprawdź hasło").arg(ssid));
        readNetwork();
    });
}

void System::disconnectWifi()
{
    if (m_preview)
        return;
    query(QString(), QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE"), QStringLiteral("device")}, [this](const QString &out, int) {
        for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList f = nmFields(line);
            if (f.size() >= 2 && f[1] == QLatin1String("wifi"))
                query(QString(), QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), f[0]},
                      [this](const QString &, int) { readNetwork(); });
        }
    });
}

// ——— Bluetooth ———
static QString deviceKind(const QString &name)
{
    const QString n = name.toLower();
    static const QRegularExpression head(QStringLiteral("buds|pods|head|słuch|sluch|wh-|wf-|earbud|jabra|bose|airpods"));
    if (head.match(n).hasMatch())
        return QStringLiteral("headphones");
    if (n.contains(QLatin1String("mouse")) || n.contains(QLatin1String("mysz")) || n.contains(QLatin1String("mx ")))
        return QStringLiteral("mouse");
    if (n.contains(QLatin1String("keyboard")) || n.contains(QLatin1String("klawiat")))
        return QStringLiteral("keyboard");
    if (n.contains(QLatin1String("speaker")) || n.contains(QLatin1String("głośn")) || n.contains(QLatin1String("jbl")) || n.contains(QLatin1String("soundbar")))
        return QStringLiteral("speaker");
    if (n.contains(QLatin1String("phone")) || n.contains(QLatin1String("galaxy")) || n.contains(QLatin1String("pixel")) || n.contains(QLatin1String("redmi")))
        return QStringLiteral("phone");
    return QStringLiteral("bluetooth");
}

static QMap<QString, QString> parseDevices(const QString &out)
{
    // „Device AA:BB:CC:DD:EE:FF Nazwa”
    QMap<QString, QString> m;
    for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts))
        if (line.startsWith(QLatin1String("Device ")))
            m.insert(line.section(QLatin1Char(' '), 1, 1), line.section(QLatin1Char(' '), 2));
    return m;
}

void System::readBluetooth()
{
    query(QStringLiteral("bt"), QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, [this](const QString &out, int) {
        m_btAvailable = out.contains(QLatin1String("Controller"));
        m_btOn = out.contains(QLatin1String("Powered: yes"));
        if (!m_btAvailable || !m_btOn) {
            m_devices.clear();
            Q_EMIT bluetoothChanged();
            return;
        }
        query(QStringLiteral("btall"), QStringLiteral("bluetoothctl"), {QStringLiteral("devices")}, [this](const QString &all, int) {
            query(QStringLiteral("btpaired"), QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Paired")}, [this, all](const QString &paired, int) {
                query(QStringLiteral("btconn"), QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Connected")},
                      [this, all, paired](const QString &connected, int) {
                          const auto a = parseDevices(all), p = parseDevices(paired), c = parseDevices(connected);
                          QVariantList list;
                          for (auto it = a.cbegin(); it != a.cend(); ++it) {
                              // Nienazwane urządzenia z wyszukiwania („AA-BB-CC…”) pomijamy
                              if (!p.contains(it.key()) && it.value().count(QLatin1Char('-')) >= 5)
                                  continue;
                              list << QVariantMap{{QStringLiteral("mac"), it.key()}, {QStringLiteral("name"), it.value()},
                                                  {QStringLiteral("paired"), p.contains(it.key())}, {QStringLiteral("connected"), c.contains(it.key())},
                                                  {QStringLiteral("kind"), deviceKind(it.value())}};
                          }
                          m_devices = list;
                          Q_EMIT bluetoothChanged();
                      });
            });
        });
    });
}

void System::setBluetooth(bool on)
{
    m_btOn = on;
    if (!on)
        m_devices.clear();
    Q_EMIT bluetoothChanged();
    if (!m_preview)
        query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("power"), on ? QStringLiteral("on") : QStringLiteral("off")},
              [this](const QString &, int) { readBluetooth(); });
}

void System::discover()
{
    if (m_preview || m_discovering)
        return;
    m_discovering = true;
    Q_EMIT bluetoothChanged();
    m_poll.setInterval(1500);
    query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("15"), QStringLiteral("scan"), QStringLiteral("on")}, [this](const QString &, int) {
        m_discovering = false;
        m_poll.setInterval(4000);
        readBluetooth();
    });
}

void System::connectDevice(const QString &mac)
{
    if (m_preview || !macRe.match(mac).hasMatch())
        return;
    bool paired = false;
    QString name = mac;
    for (const QVariant &v : std::as_const(m_devices))
        if (v.toMap().value(QStringLiteral("mac")) == mac) {
            paired = v.toMap().value(QStringLiteral("paired")).toBool();
            name = v.toMap().value(QStringLiteral("name")).toString();
        }
    auto doConnect = [this, mac, name] {
        query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("connect"), mac}, [this, name](const QString &, int code) {
            Q_EMIT message(code == 0 ? QStringLiteral("Połączono: %1").arg(name) : QStringLiteral("Nie udało się połączyć z: %1").arg(name));
            readBluetooth();
        });
    };
    if (paired)
        return doConnect();
    // Nowe urządzenie: sparuj, zaufaj (łączy się samo następnym razem), połącz
    query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("pair"), mac}, [this, mac, name, doConnect](const QString &, int code) {
        if (code != 0) {
            Q_EMIT message(QStringLiteral("Nie udało się sparować: %1").arg(name));
            return;
        }
        query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("trust"), mac}, [doConnect](const QString &, int) { doConnect(); });
    });
}

void System::disconnectDevice(const QString &mac)
{
    if (!m_preview && macRe.match(mac).hasMatch())
        query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("disconnect"), mac}, [this](const QString &, int) { readBluetooth(); });
}

void System::forgetDevice(const QString &mac)
{
    if (!m_preview && macRe.match(mac).hasMatch())
        query(QString(), QStringLiteral("bluetoothctl"), {QStringLiteral("remove"), mac}, [this](const QString &, int) { readBluetooth(); });
}

// ——— Dźwięk ———
void System::readAudio()
{
    query(QStringLiteral("status"), QStringLiteral("wpctl"), {QStringLiteral("status")}, [this](const QString &out, int) {
        // Sekcja „Audio” → „Sinks:” / „Sources:”; wpis: „ │  *   47. Nazwa urządzenia   [vol: 0.40]”
        static const QRegularExpression entry(QStringLiteral("^(\\*)?\\s*(\\d+)\\.\\s+(.+?)\\s*(\\[vol:.*\\])?$"));
        QVariantList outputs, inputs;
        bool audio = false;
        QString section;
        for (QString line : out.split(QLatin1Char('\n'))) {
            if (line.trimmed() == QLatin1String("Audio")) { audio = true; continue; }
            if (line.trimmed() == QLatin1String("Video") || line.trimmed() == QLatin1String("Settings")) { audio = false; continue; }
            if (!audio)
                continue;
            line.remove(QRegularExpression(QStringLiteral("[│├└─]")));
            const QString t = line.trimmed();
            if (t.endsWith(QLatin1Char(':'))) { section = t; continue; }
            const auto m = entry.match(t);
            if (!m.hasMatch())
                continue;
            const QVariantMap dev{{QStringLiteral("id"), m.captured(2).toInt()}, {QStringLiteral("name"), m.captured(3)}, {QStringLiteral("default"), !m.captured(1).isEmpty()}};
            if (section == QLatin1String("Sinks:"))
                outputs << dev;
            else if (section == QLatin1String("Sources:"))
                inputs << dev;
        }
        m_outputs = outputs;
        m_inputs = inputs;
        query(QStringLiteral("vol"), QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, [this](const QString &v, int) {
            static const QRegularExpression re(QStringLiteral("Volume:\\s*([0-9.]+)"));
            const auto m = re.match(v);
            if (QDateTime::currentMSecsSinceEpoch() - m_volumeTouched > 1500 && m.hasMatch())
                m_volume = qBound(0.0, m.captured(1).toDouble(), 1.0);
            m_muted = v.contains(QLatin1String("MUTED"));
            Q_EMIT audioChanged();
        });
    });
}

void System::setDefaultDevice(int id)
{
    for (QVariantList *list : {&m_outputs, &m_inputs}) {
        bool here = false;
        for (const QVariant &v : std::as_const(*list))
            here |= v.toMap().value(QStringLiteral("id")).toInt() == id;
        if (!here)
            continue;
        for (QVariant &v : *list) {
            QVariantMap m = v.toMap();
            m.insert(QStringLiteral("default"), m.value(QStringLiteral("id")).toInt() == id);
            v = m;
        }
    }
    Q_EMIT audioChanged();
    if (!m_preview)
        query(QString(), QStringLiteral("wpctl"), {QStringLiteral("set-default"), QString::number(id)}, [this](const QString &, int) { readAudio(); });
}

void System::setVolume(double value)
{
    m_volume = qBound(0.0, value, 1.0);
    m_volumeTouched = QDateTime::currentMSecsSinceEpoch();
    Q_EMIT audioChanged();
    if (!m_preview)
        m_volumeDelay.start();
}

void System::toggleMute()
{
    m_muted = !m_muted;
    Q_EMIT audioChanged();
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")});
}

// ——— Ekran ———
void System::readDisplay()
{
    query(QStringLiteral("night"), QStringLiteral("kreadconfig6"), {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"),
                                                                    QStringLiteral("--key"), QStringLiteral("Active")},
          [this](const QString &out, int) {
              const bool on = out.trimmed() == QLatin1String("true");
              if (on != m_nightLight) {
                  m_nightLight = on;
                  Q_EMIT displayChanged();
              }
          });
}

void System::setNightLight(bool on)
{
    m_nightLight = on;
    Q_EMIT displayChanged();
    if (m_preview)
        return;
    // Ciepłe światło na stałe (włącz/wyłącz ręcznie, jak „Night Shift do jutra”)
    const auto write = [](const QString &key, const QString &value) {
        QProcess::execute(QStringLiteral("kwriteconfig6"), {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"),
                                                            QStringLiteral("--key"), key, value});
    };
    write(QStringLiteral("Active"), on ? QStringLiteral("true") : QStringLiteral("false"));
    if (on) {
        write(QStringLiteral("Mode"), QStringLiteral("Constant"));
        write(QStringLiteral("NightTemperature"), QStringLiteral("4200"));
    }
    QProcess::startDetached(QStringLiteral("dbus-send"), {QStringLiteral("--session"), QStringLiteral("--dest=org.kde.KWin"), QStringLiteral("/KWin"),
                                                         QStringLiteral("org.kde.KWin.reconfigure")});
}

// ——— Różne ———
void System::setDarkMode(bool dark)
{
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("plasma-apply-colorscheme"), {dark ? QStringLiteral("BreezeDark") : QStringLiteral("BreezeLight")});
}

void System::openKcm(const QString &module)
{
    QProcess::startDetached(QStringLiteral("systemsettings"), module.isEmpty() ? QStringList() : QStringList{module});
}

void System::run(const QString &program, const QStringList &args)
{
    QProcess::startDetached(program, args);
}

void System::testNotification()
{
    QProcess::startDetached(QStringLiteral("notify-send"), {QStringLiteral("-a"), QStringLiteral("Ustawienia"), QStringLiteral("-i"), QStringLiteral("preferences-system"),
                                                           QStringLiteral("Tak wyglądają powiadomienia"), QStringLiteral("Pojawiają się pod górną wyspą i same znikają.")});
}

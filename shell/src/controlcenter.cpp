#include "controlcenter.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>

static const QString mprisPath = QStringLiteral("/org/mpris/MediaPlayer2");
static const QString mprisPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
static const QString brightnessService = QStringLiteral("org.kde.ScreenBrightness");
static const QString brightnessPath = QStringLiteral("/org/kde/ScreenBrightness");

static QString readFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

// Asynchroniczne org.freedesktop.DBus.Properties.GetAll → mapa właściwości
static void getAll(const QString &service, const QString &path, const QString &iface, QObject *ctx,
                   std::function<void(const QVariantMap &)> done)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    msg << iface;
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 800), ctx);
    QObject::connect(w, &QDBusPendingCallWatcher::finished, ctx, [w, done] {
        QDBusPendingReply<QVariantMap> r = *w;
        done(r.isError() ? QVariantMap() : r.value());
        w->deleteLater();
    });
}

ControlCenter::ControlCenter(QObject *parent)
    : QObject(parent)
{
    m_preview = !qEnvironmentVariableIsEmpty("ASTER_PREVIEW");
    m_dnd = QSettings().value(QStringLiteral("doNotDisturb"), false).toBool();

    m_poll.setInterval(8000);
    connect(&m_poll, &QTimer::timeout, this, &ControlCenter::refresh);

    // Suwaki: do systemu idzie co najwyżej jedna zmiana na ~50 ms
    m_volumeDelay.setSingleShot(true);
    m_volumeDelay.setInterval(50);
    connect(&m_volumeDelay, &QTimer::timeout, this, [this] {
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                                                          QString::number(m_volume, 'f', 3)});
    });
    m_brightnessDelay.setSingleShot(true);
    m_brightnessDelay.setInterval(50);
    connect(&m_brightnessDelay, &QTimer::timeout, this, [this] {
        const QString display = m_display;
        if (display.isEmpty())
            return;
        getAll(brightnessService, brightnessPath + QLatin1Char('/') + display, QStringLiteral("org.kde.ScreenBrightness.Display"), this,
               [this, display](const QVariantMap &p) {
                   const int max = p.value(QStringLiteral("MaxBrightness")).toInt();
                   if (max <= 0)
                       return;
                   QDBusMessage m = QDBusMessage::createMethodCall(brightnessService, brightnessPath + QLatin1Char('/') + display,
                                                                   QStringLiteral("org.kde.ScreenBrightness.Display"), QStringLiteral("SetBrightness"));
                   m << int(qRound(m_brightness * max)) << uint(0);
                   QDBusConnection::sessionBus().asyncCall(m);
               });
    });

    if (m_preview) {
        fillPreview();
        return;
    }
    refresh();
    m_poll.start();
}

void ControlCenter::fillPreview()
{
    // Do zrzutów w kontenerze: przykładowy stan zamiast pustych kafelków
    m_wifiAvailable = m_wifiOn = true;
    m_networkName = QStringLiteral("Dom 5G");
    m_btAvailable = m_btOn = true;
    m_btDevice = QStringLiteral("Słuchawki");
    m_audioAvailable = true;
    m_volume = 0.62;
    m_brightnessAvailable = true;
    m_brightness = 0.78;
    m_batteryAvailable = true;
    m_battery = 84;
    m_playerAvailable = m_playing = true;
    m_playerName = QStringLiteral("Spotify");
    m_title = QStringLiteral("Nocne miasto");
    m_artist = QStringLiteral("Aster Radio");
}

void ControlCenter::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    Q_EMIT activeChanged();
    if (m_preview)
        return;
    m_poll.setInterval(active ? 1000 : 8000);
    if (active)
        refresh();
}

void ControlCenter::refresh()
{
    if (m_preview)
        return;
    readNetwork();
    readBluetooth();
    readAudio();
    readBrightness();
    readBattery();
    readPlayer();
}

void ControlCenter::query(const QString &key, const QString &program, const QStringList &args, std::function<void(const QString &)> done)
{
    if (m_running.contains(key))
        return;
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        done(QString());
        return;
    }
    m_running.insert(key);
    auto *p = new QProcess(this);
    p->setProcessEnvironment([] {
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));   // wyjście po angielsku, łatwe do czytania
        return env;
    }());
    connect(p, &QProcess::finished, this, [this, p, key, done] {
        m_running.remove(key);
        done(QString::fromUtf8(p->readAllStandardOutput()));
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, key](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_running.remove(key);
            p->deleteLater();
        }
    });
    p->start(program, args);
}

// ——— Sieć ———
void ControlCenter::readNetwork()
{
    query(QStringLiteral("net"), QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE,CONNECTION"), QStringLiteral("device")},
          [this](const QString &out) {
              bool wifiDev = false, wired = false;
              QString name;
              for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                  const QStringList f = line.split(QLatin1Char(':'));
                  if (f.size() < 3)
                      continue;
                  const bool connected = f[1] == QLatin1String("connected");
                  if (f[0] == QLatin1String("wifi")) {
                      wifiDev = true;
                      if (connected)
                          name = QStringList(f.mid(2)).join(QLatin1Char(':')).replace(QLatin1String("\\"), QString());
                  } else if (f[0] == QLatin1String("ethernet") && connected) {
                      wired = true;
                  }
              }
              if (name.isEmpty() && wired)
                  name = QStringLiteral("Przewodowa");
              query(QStringLiteral("radio"), QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")}, [this, wifiDev, wired, name](const QString &radio) {
                  const bool on = radio.trimmed() == QLatin1String("enabled");
                  if (wifiDev != m_wifiAvailable || on != m_wifiOn || wired != m_wired || name != m_networkName) {
                      m_wifiAvailable = wifiDev;
                      m_wifiOn = on;
                      m_wired = wired;
                      m_networkName = name;
                      Q_EMIT networkChanged();
                  }
              });
          });
}

void ControlCenter::setWifi(bool on)
{
    m_wifiOn = on;
    if (!on && !m_wired)
        m_networkName.clear();
    Q_EMIT networkChanged();
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), on ? QStringLiteral("on") : QStringLiteral("off")});
}

// ——— Bluetooth ———
void ControlCenter::readBluetooth()
{
    query(QStringLiteral("bt"), QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, [this](const QString &out) {
        const bool available = out.contains(QLatin1String("Controller"));
        const bool on = out.contains(QLatin1String("Powered: yes"));
        auto apply = [this, available, on](const QString &device) {
            if (available != m_btAvailable || on != m_btOn || device != m_btDevice) {
                m_btAvailable = available;
                m_btOn = on;
                m_btDevice = device;
                Q_EMIT bluetoothChanged();
            }
        };
        if (!on)
            return apply(QString());
        query(QStringLiteral("btdev"), QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Connected")}, [apply](const QString &devs) {
            // „Device AA:BB:CC:DD:EE:FF Nazwa urządzenia”
            for (const QString &line : devs.split(QLatin1Char('\n'), Qt::SkipEmptyParts))
                if (line.startsWith(QLatin1String("Device ")))
                    return apply(line.section(QLatin1Char(' '), 2));
            apply(QString());
        });
    });
}

void ControlCenter::setBluetooth(bool on)
{
    m_btOn = on;
    if (!on)
        m_btDevice.clear();
    Q_EMIT bluetoothChanged();
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), on ? QStringLiteral("on") : QStringLiteral("off")});
}

// ——— Dźwięk ———
void ControlCenter::readAudio()
{
    query(QStringLiteral("audio"), QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, [this](const QString &out) {
        static const QRegularExpression re(QStringLiteral("Volume:\\s*([0-9.]+)"));
        const auto m = re.match(out);
        const bool available = m.hasMatch();
        const bool muted = out.contains(QLatin1String("MUTED"));
        const double volume = available ? qBound(0.0, m.captured(1).toDouble(), 1.0) : 0;
        const bool touched = QDateTime::currentMSecsSinceEpoch() - m_volumeTouched < 1500;
        if (available != m_audioAvailable || muted != m_muted || (!touched && qAbs(volume - m_volume) > 0.004)) {
            m_audioAvailable = available;
            m_muted = muted;
            if (!touched)
                m_volume = volume;
            Q_EMIT audioChanged();
        }
    });
}

void ControlCenter::setVolume(double value)
{
    m_volume = qBound(0.0, value, 1.0);
    m_volumeTouched = QDateTime::currentMSecsSinceEpoch();
    if (m_muted && m_volume > 0) {
        m_muted = false;
        if (!m_preview)
            QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("0")});
    }
    Q_EMIT audioChanged();
    if (!m_preview)
        m_volumeDelay.start();
}

void ControlCenter::toggleMute()
{
    m_muted = !m_muted;
    Q_EMIT audioChanged();
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")});
}

// ——— Jasność (PowerDevil) ———
void ControlCenter::readBrightness()
{
    getAll(brightnessService, brightnessPath, brightnessService, this, [this](const QVariantMap &p) {
        const QStringList displays = p.value(QStringLiteral("DisplaysDBusNames")).toStringList();
        if (displays.isEmpty()) {
            if (m_brightnessAvailable) {
                m_brightnessAvailable = false;
                Q_EMIT brightnessChanged();
            }
            return;
        }
        m_display = displays.first();
        getAll(brightnessService, brightnessPath + QLatin1Char('/') + displays.first(), QStringLiteral("org.kde.ScreenBrightness.Display"), this,
               [this](const QVariantMap &d) {
                   const int max = d.value(QStringLiteral("MaxBrightness")).toInt();
                   const bool available = max > 0;
                   const double value = available ? d.value(QStringLiteral("Brightness")).toDouble() / max : 1;
                   const bool touched = QDateTime::currentMSecsSinceEpoch() - m_brightnessTouched < 1500;
                   if (available != m_brightnessAvailable || (!touched && qAbs(value - m_brightness) > 0.004)) {
                       m_brightnessAvailable = available;
                       if (!touched)
                           m_brightness = value;
                       Q_EMIT brightnessChanged();
                   }
               });
    });
}

void ControlCenter::setBrightness(double value)
{
    m_brightness = qBound(0.02, value, 1.0);   // nie do zera — czarny ekran wygląda jak awaria
    m_brightnessTouched = QDateTime::currentMSecsSinceEpoch();
    Q_EMIT brightnessChanged();
    if (!m_preview)
        m_brightnessDelay.start();
}

// ——— Bateria ———
void ControlCenter::readBattery()
{
    const QDir dir(QStringLiteral("/sys/class/power_supply"));
    for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QString base = dir.filePath(name) + QLatin1Char('/');
        if (readFile(base + QStringLiteral("type")) != QLatin1String("Battery"))
            continue;
        const int level = readFile(base + QStringLiteral("capacity")).toInt();
        const QString status = readFile(base + QStringLiteral("status"));
        const bool charging = status == QLatin1String("Charging") || status == QLatin1String("Full");
        if (!m_batteryAvailable || level != m_battery || charging != m_charging) {
            m_batteryAvailable = true;
            m_battery = level;
            m_charging = charging;
            Q_EMIT batteryChanged();
        }
        return;
    }
}

// ——— Odtwarzacz (MPRIS) ———
void ControlCenter::readPlayer()
{
    QStringList services;
    if (auto *bus = QDBusConnection::sessionBus().interface()) {
        const QDBusReply<QStringList> names = bus->registeredServiceNames();
        for (const QString &n : names.value())
            if (n.startsWith(QLatin1String("org.mpris.MediaPlayer2.")))
                services << n;
    }
    if (services.isEmpty()) {
        if (m_playerAvailable) {
            m_playerAvailable = m_playing = false;
            m_playerService.clear();
            Q_EMIT playerChanged();
        }
        return;
    }
    // Zbierz stan wszystkich odtwarzaczy i pokaż ten, który gra (albo pierwszy)
    auto results = std::make_shared<QList<QPair<QString, QVariantMap>>>();
    auto left = std::make_shared<int>(services.size());
    for (const QString &service : services) {
        getAll(service, mprisPath, mprisPlayer, this, [this, service, results, left](const QVariantMap &p) {
            if (!p.isEmpty())
                results->append({service, p});
            if (--*left > 0)
                return;
            if (results->isEmpty())
                return;
            auto pick = results->first();
            for (const auto &r : *results)
                if (r.second.value(QStringLiteral("PlaybackStatus")).toString() == QLatin1String("Playing")) {
                    pick = r;
                    break;
                }
            QVariantMap meta;
            const QVariant mv = pick.second.value(QStringLiteral("Metadata"));
            if (mv.canConvert<QDBusArgument>())
                meta = qdbus_cast<QVariantMap>(mv.value<QDBusArgument>());
            else
                meta = mv.toMap();
            const QString title = meta.value(QStringLiteral("xesam:title")).toString();
            const QString artist = meta.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
            const QString art = meta.value(QStringLiteral("mpris:artUrl")).toString();
            const bool playing = pick.second.value(QStringLiteral("PlaybackStatus")).toString() == QLatin1String("Playing");
            // „org.mpris.MediaPlayer2.spotify” → „Spotify”, „…firefox.instance_1_23” → „Firefox”
            QString name = pick.first.section(QLatin1Char('.'), 3, 3);
            if (!name.isEmpty())
                name[0] = name[0].toUpper();
            if (!m_playerAvailable || pick.first != m_playerService || title != m_title || artist != m_artist || art != m_artUrl
                || playing != m_playing) {
                m_playerAvailable = true;
                m_playerService = pick.first;
                m_playerName = name;
                m_title = title;
                m_artist = artist;
                m_artUrl = art;
                m_playing = playing;
                Q_EMIT playerChanged();
            }
        });
    }
}

void ControlCenter::playerCall(const QString &method)
{
    if (m_preview || m_playerService.isEmpty())
        return;
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(m_playerService, mprisPath, mprisPlayer, method));
    QTimer::singleShot(250, this, &ControlCenter::readPlayer);
}

void ControlCenter::playPause()
{
    m_playing = !m_playing;
    Q_EMIT playerChanged();
    playerCall(QStringLiteral("PlayPause"));
}
void ControlCenter::next() { playerCall(QStringLiteral("Next")); }
void ControlCenter::previous() { playerCall(QStringLiteral("Previous")); }

// ——— Motyw i „Nie przeszkadzać” ———
void ControlCenter::setDarkMode(bool dark)
{
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("plasma-apply-colorscheme"), {dark ? QStringLiteral("BreezeDark") : QStringLiteral("BreezeLight")});
}

void ControlCenter::setDoNotDisturb(bool on)
{
    if (m_dnd == on)
        return;
    m_dnd = on;
    QSettings().setValue(QStringLiteral("doNotDisturb"), on);
    Q_EMIT doNotDisturbChanged();
}

#include "connectivity.h"

#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <algorithm>
#include <functional>

using SettingsMap = QMap<QString, QVariantMap>;
using ManagedObjects = QMap<QDBusObjectPath, SettingsMap>;
Q_DECLARE_METATYPE(SettingsMap)
Q_DECLARE_METATYPE(ManagedObjects)

static const QString bluez = QStringLiteral("org.bluez");
static const QString agentPath = QStringLiteral("/org/aster/shell/bluetoothagent");
static const QString nmService = QStringLiteral("org.freedesktop.NetworkManager");
static const QString nmPath = QStringLiteral("/org/freedesktop/NetworkManager");
static const QString propertiesIface = QStringLiteral("org.freedesktop.DBus.Properties");
static const QString deviceIface = QStringLiteral("org.bluez.Device1");
static const QString adapterIface = QStringLiteral("org.bluez.Adapter1");

// Program w tle; done dostaje wyjście i informację, czy się udał
static void run(QObject *ctx, const QString &program, const QStringList &args, std::function<void(const QString &, bool)> done)
{
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        done(QString(), false);
        return;
    }
    auto *p = new QProcess(ctx);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p->setProcessEnvironment(env);
    QObject::connect(p, &QProcess::finished, ctx, [p, done](int code, QProcess::ExitStatus status) {
        done(QString::fromUtf8(p->readAllStandardOutput()), status == QProcess::NormalExit && code == 0);
        p->deleteLater();
    });
    QObject::connect(p, &QProcess::errorOccurred, ctx, [p, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            done(QString(), false);
            p->deleteLater();
        }
    });
    p->start(program, args);
}

// Wywołanie D-Bus w tle; po odpowiedzi done dostaje wiadomość zwrotną
static void call(QObject *ctx, const QDBusConnection &bus, const QDBusMessage &msg, int timeout, std::function<void(const QDBusMessage &)> done)
{
    auto *w = new QDBusPendingCallWatcher(QDBusConnection(bus).asyncCall(msg, timeout), ctx);
    QObject::connect(w, &QDBusPendingCallWatcher::finished, ctx, [w, done] {
        done(w->reply());
        w->deleteLater();
    });
}

// Pola wyjścia „nmcli -t”: dwukropek rozdziela, a „\:” to dwukropek w treści
static QStringList splitTerse(const QString &line)
{
    QStringList fields(1);
    for (int i = 0; i < line.size(); ++i) {
        if (line[i] == QLatin1Char('\\') && i + 1 < line.size())
            fields.last() += line[++i];
        else if (line[i] == QLatin1Char(':'))
            fields.append(QString());
        else
            fields.last() += line[i];
    }
    return fields;
}

// ——— Agent parowania ———
BluetoothAgent::BluetoothAgent(Connectivity *owner)
    : QObject(owner)
    , m_owner(owner)
{
}

void BluetoothAgent::Release()
{
    m_owner->clearPairing();
}

QString BluetoothAgent::RequestPinCode(const QDBusObjectPath &device)
{
    const QString code = QStringLiteral("%1").arg(QRandomGenerator::system()->bounded(1000000), 6, 10, QLatin1Char('0'));
    m_owner->showPairing(QStringLiteral("show"), code, device.path());
    return code;
}

void BluetoothAgent::DisplayPinCode(const QDBusObjectPath &device, const QString &code)
{
    m_owner->showPairing(QStringLiteral("show"), code, device.path());
}

uint BluetoothAgent::RequestPasskey(const QDBusObjectPath &device)
{
    const uint key = QRandomGenerator::system()->bounded(1000000);
    m_owner->showPairing(QStringLiteral("show"), QStringLiteral("%1").arg(key, 6, 10, QLatin1Char('0')), device.path());
    return key;
}

void BluetoothAgent::DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered)
{
    m_owner->showPairing(QStringLiteral("show"), QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')), device.path(), entered);
}

void BluetoothAgent::ask(const QDBusObjectPath &device, const QString &code)
{
    setDelayedReply(true);
    m_pending = message();
    m_owner->showPairing(QStringLiteral("confirm"), code, device.path());
}

void BluetoothAgent::RequestConfirmation(const QDBusObjectPath &device, uint passkey)
{
    ask(device, QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')));
}

void BluetoothAgent::RequestAuthorization(const QDBusObjectPath &device)
{
    ask(device, QString());
}

void BluetoothAgent::AuthorizeService(const QDBusObjectPath &device, const QString &)
{
    ask(device, QString());
}

void BluetoothAgent::Cancel()
{
    m_pending = QDBusMessage();
    m_owner->clearPairing();
}

void BluetoothAgent::answer(bool accepted)
{
    if (m_pending.type() == QDBusMessage::InvalidMessage)
        return;
    QDBusConnection::systemBus().send(accepted ? m_pending.createReply()
                                               : m_pending.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("Odrzucono")));
    m_pending = QDBusMessage();
}

// ——— Stan ———
Connectivity::Connectivity(QObject *parent)
    : QObject(parent)
{
    m_preview = !qEnvironmentVariableIsEmpty("ASTER_PREVIEW");
    qDBusRegisterMetaType<SettingsMap>();
    qDBusRegisterMetaType<ManagedObjects>();
    connect(&m_poll, &QTimer::timeout, this, &Connectivity::poll);

    if (m_preview) {
        fillPreview();
        return;
    }
    m_agent = new BluetoothAgent(this);
    QDBusConnection::systemBus().registerObject(agentPath, m_agent, QDBusConnection::ExportAllSlots);
    registerAgent();
    // Agent ginie razem z bluetoothd, więc po jego restarcie rejestrujemy się od nowa
    auto *watcher = new QDBusServiceWatcher(bluez, QDBusConnection::systemBus(), QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &, const QString &owner) {
        m_agentRegistered = false;
        m_discovering = false;
        if (!owner.isEmpty())
            registerAgent();
    });
}

void Connectivity::fillPreview()
{
    const auto net = [](const QString &ssid, int signal, bool secure, bool active, bool saved) {
        return QVariantMap{{QStringLiteral("ssid"), ssid}, {QStringLiteral("signal"), signal}, {QStringLiteral("secure"), secure},
                           {QStringLiteral("active"), active}, {QStringLiteral("saved"), saved}};
    };
    m_wifi = {net(QStringLiteral("Dom 5G"), 88, true, true, true), net(QStringLiteral("Dom"), 70, true, false, true),
              net(QStringLiteral("Kawiarnia"), 46, false, false, false), net(QStringLiteral("Sąsiad_2.4"), 22, true, false, false)};
    const auto dev = [](const QString &path, const QString &name, const QString &icon, bool paired, bool connected) {
        return QVariantMap{{QStringLiteral("path"), path}, {QStringLiteral("name"), name}, {QStringLiteral("icon"), icon},
                           {QStringLiteral("paired"), paired}, {QStringLiteral("connected"), connected}};
    };
    m_bt = {dev(QStringLiteral("/a"), QStringLiteral("POP Mouse"), QStringLiteral("input-mouse"), true, true),
            dev(QStringLiteral("/b"), QStringLiteral("POP Icon Keys"), QStringLiteral("input-keyboard"), false, false),
            dev(QStringLiteral("/c"), QStringLiteral("Słuchawki"), QStringLiteral("audio-headset"), true, false)};
    const auto out = [](int id, const QString &name, bool active) {
        return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("active"), active}};
    };
    m_outputs = {out(1, QStringLiteral("Głośniki wbudowane"), true), out(2, QStringLiteral("Monitor HDMI"), false), out(3, QStringLiteral("Słuchawki"), false)};
    m_inputs = {out(4, QStringLiteral("Mikrofon wbudowany"), true)};
    const QByteArray pairing = qgetenv("ASTER_SHOT_PAIRING");
    if (!pairing.isEmpty()) {
        m_pairingKind = QString::fromLatin1(pairing);
        m_pairingCode = QStringLiteral("482915");
        m_pairingDevice = QStringLiteral("POP Icon Keys");
        m_pairingEntered = 2;
    }
}

void Connectivity::setPage(const QString &page)
{
    if (m_page == page)
        return;
    const bool wasBluetooth = m_page == QLatin1String("bluetooth");
    m_page = page;
    Q_EMIT pageChanged();
    if (m_preview)
        return;
    m_wifiError.clear();
    m_btError.clear();
    if (wasBluetooth)
        setDiscovery(false);
    if (page.isEmpty()) {
        m_poll.stop();
        return;
    }
    m_poll.setInterval(page == QLatin1String("wifi") ? 4000 : 1500);
    m_poll.start();
    if (page == QLatin1String("wifi"))
        readWifi(true);
    else if (page == QLatin1String("bluetooth")) {
        setDiscovery(true);
        readBluetooth();
    } else
        readAudio();
}

void Connectivity::poll()
{
    if (m_page == QLatin1String("wifi"))
        readWifi(false);
    else if (m_page == QLatin1String("bluetooth"))
        readBluetooth();
    else if (m_page == QLatin1String("audio"))
        readAudio();
}

// ——— Wi‑Fi ———
void Connectivity::readWifi(bool rescan)
{
    run(this, QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE"), QStringLiteral("device")},
        [this](const QString &out, bool) {
            for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const QStringList f = splitTerse(line);
                if (f.size() >= 2 && f[1] == QLatin1String("wifi"))
                    m_wifiIface = f[0];
            }
        });
    run(this, QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE"), QStringLiteral("connection"), QStringLiteral("show")},
        [this, rescan](const QString &saved, bool) {
            QSet<QString> known;
            for (const QString &line : saved.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const QStringList f = splitTerse(line);
                if (f.size() >= 2 && f[1] == QLatin1String("802-11-wireless"))
                    known.insert(f[0]);
            }
            run(this, QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SIGNAL,SECURITY,SSID"), QStringLiteral("device"), QStringLiteral("wifi"),
                                                QStringLiteral("list"), QStringLiteral("--rescan"), rescan ? QStringLiteral("yes") : QStringLiteral("no")},
                [this, known](const QString &out, bool) {
                    QHash<QString, QVariantMap> best;
                    for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                        const QStringList f = splitTerse(line);
                        if (f.size() < 4 || f[3].isEmpty())
                            continue;
                        const bool active = f[0].contains(QLatin1Char('*'));
                        const int signal = f[1].toInt();
                        auto it = best.find(f[3]);
                        if (it != best.end() && !active && it->value(QStringLiteral("signal")).toInt() >= signal)
                            continue;
                        best[f[3]] = {{QStringLiteral("ssid"), f[3]}, {QStringLiteral("signal"), signal}, {QStringLiteral("security"), f[2]},
                                      {QStringLiteral("secure"), !f[2].isEmpty() && f[2] != QLatin1String("--")},
                                      {QStringLiteral("enterprise"), f[2].contains(QLatin1String("802.1X"))},
                                      {QStringLiteral("active"), active}, {QStringLiteral("saved"), known.contains(f[3])}};
                    }
                    QVariantList list;
                    for (const QVariantMap &n : std::as_const(best))
                        list.append(n);
                    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
                        const QVariantMap x = a.toMap(), y = b.toMap();
                        const auto rank = [](const QVariantMap &n) { return n.value(QStringLiteral("active")).toBool() ? 2 : n.value(QStringLiteral("saved")).toBool() ? 1 : 0; };
                        if (rank(x) != rank(y))
                            return rank(x) > rank(y);
                        return x.value(QStringLiteral("signal")).toInt() > y.value(QStringLiteral("signal")).toInt();
                    });
                    if (list != m_wifi) {
                        m_wifi = list;
                        Q_EMIT wifiChanged();
                    }
                });
        });
}

void Connectivity::failWifi(const QString &message)
{
    m_wifiConnecting.clear();
    m_wifiError = message;
    Q_EMIT wifiChanged();
}

void Connectivity::connectWifi(const QString &ssid, const QString &password)
{
    if (m_preview)
        return;
    QVariantMap network;
    for (const QVariant &n : std::as_const(m_wifi))
        if (n.toMap().value(QStringLiteral("ssid")).toString() == ssid)
            network = n.toMap();
    m_wifiConnecting = ssid;
    m_wifiError.clear();
    Q_EMIT wifiChanged();

    if (network.value(QStringLiteral("saved")).toBool() && password.isEmpty()) {
        run(this, QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("up"), QStringLiteral("id"), ssid}, [this, ssid](const QString &, bool ok) {
            if (ok) {
                m_wifiConnecting.clear();
                Q_EMIT wifiChanged();
                readWifi(false);
            } else {
                failWifi(QStringLiteral("Nie udało się połączyć z siecią „%1”.").arg(ssid));
            }
        });
        return;
    }
    addWifiConnection(ssid, password, network.value(QStringLiteral("security")).toString());
}

// Przez D-Bus, nie przez nmcli: hasło w argumencie programu widziałby każdy proces w systemie
void Connectivity::addWifiConnection(const QString &ssid, const QString &password, const QString &security)
{
    QDBusMessage find = QDBusMessage::createMethodCall(nmService, nmPath, nmService, QStringLiteral("GetDeviceByIpIface"));
    find << m_wifiIface;
    call(this, QDBusConnection::systemBus(), find, 5000, [this, ssid, password, security](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
            failWifi(QStringLiteral("Nie znaleziono karty Wi‑Fi."));
            return;
        }
        const QDBusObjectPath device = reply.arguments().constFirst().value<QDBusObjectPath>();

        SettingsMap settings;
        settings[QStringLiteral("connection")] = {{QStringLiteral("id"), ssid},
                                                  {QStringLiteral("type"), QStringLiteral("802-11-wireless")},
                                                  {QStringLiteral("permissions"), QStringList{QStringLiteral("user:%1:").arg(qEnvironmentVariable("USER"))}}};
        QVariantMap wireless{{QStringLiteral("ssid"), ssid.toUtf8()}, {QStringLiteral("mode"), QStringLiteral("infrastructure")}};
        if (!password.isEmpty()) {
            const bool sae = security.contains(QLatin1String("WPA3")) && !security.contains(QLatin1String("WPA2"));
            settings[QStringLiteral("802-11-wireless-security")] = {{QStringLiteral("key-mgmt"), sae ? QStringLiteral("sae") : QStringLiteral("wpa-psk")},
                                                                    {QStringLiteral("psk"), password}};
        }
        settings[QStringLiteral("802-11-wireless")] = wireless;

        QDBusMessage add = QDBusMessage::createMethodCall(nmService, nmPath, nmService, QStringLiteral("AddAndActivateConnection"));
        add << QVariant::fromValue(settings) << QVariant::fromValue(device) << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));
        call(this, QDBusConnection::systemBus(), add, 30000, [this, ssid](const QDBusMessage &added) {
            if (added.type() == QDBusMessage::ErrorMessage || added.arguments().size() < 2) {
                failWifi(QStringLiteral("Nie udało się połączyć z siecią „%1”.").arg(ssid));
                return;
            }
            watchActivation(added.arguments().at(1).value<QDBusObjectPath>().path(), added.arguments().at(0).value<QDBusObjectPath>().path(), ssid, 0);
        });
    });
}

// Dodanie połączenia kończy się od razu, a o haśle decyduje dopiero router: czekamy na wynik
void Connectivity::watchActivation(const QString &active, const QString &settings, const QString &ssid, int attempt)
{
    QDBusMessage get = QDBusMessage::createMethodCall(nmService, active, propertiesIface, QStringLiteral("Get"));
    get << QStringLiteral("org.freedesktop.NetworkManager.Connection.Active") << QStringLiteral("State");
    call(this, QDBusConnection::systemBus(), get, 2000, [this, active, settings, ssid, attempt](const QDBusMessage &reply) {
        const int state = reply.type() == QDBusMessage::ErrorMessage ? 4 : reply.arguments().value(0).value<QDBusVariant>().variant().toInt();
        if (state == 2) {   // aktywne
            m_wifiConnecting.clear();
            Q_EMIT wifiChanged();
            readWifi(false);
        } else if (state >= 3 || attempt >= 80) {
            // Nie zostawiamy zapisanego połączenia ze złym hasłem
            QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(nmService, settings, QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("Delete")));
            failWifi(QStringLiteral("Nie udało się połączyć. Sprawdź hasło i spróbuj ponownie."));
        } else {
            QTimer::singleShot(500, this, [this, active, settings, ssid, attempt] { watchActivation(active, settings, ssid, attempt + 1); });
        }
    });
}

void Connectivity::disconnectWifi(const QString &ssid)
{
    if (m_preview)
        return;
    run(this, QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("down"), QStringLiteral("id"), ssid}, [this](const QString &, bool) { readWifi(false); });
}

void Connectivity::forgetWifi(const QString &ssid)
{
    if (m_preview)
        return;
    run(this, QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("delete"), QStringLiteral("id"), ssid}, [this](const QString &, bool) { readWifi(false); });
}

// ——— Bluetooth ———
void Connectivity::registerAgent()
{
    if (m_agentRegistered || !m_agent)
        return;
    QDBusMessage reg = QDBusMessage::createMethodCall(bluez, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("RegisterAgent"));
    reg << QVariant::fromValue(QDBusObjectPath(agentPath)) << QStringLiteral("KeyboardDisplay");
    call(this, QDBusConnection::systemBus(), reg, 3000, [this](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage)
            return;
        m_agentRegistered = true;
        QDBusMessage def = QDBusMessage::createMethodCall(bluez, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("RequestDefaultAgent"));
        def << QVariant::fromValue(QDBusObjectPath(agentPath));
        QDBusConnection::systemBus().asyncCall(def);
    });
}

void Connectivity::setDiscovery(bool on)
{
    if (m_btAdapter.isEmpty() || m_discovering == on)
        return;
    m_discovering = on;
    QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(bluez, m_btAdapter, adapterIface, on ? QStringLiteral("StartDiscovery") : QStringLiteral("StopDiscovery")));
}

void Connectivity::readBluetooth()
{
    registerAgent();
    QDBusMessage msg = QDBusMessage::createMethodCall(bluez, QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg, 3000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w] {
        w->deleteLater();
        QDBusPendingReply<ManagedObjects> reply = *w;
        if (reply.isError())
            return;
        QVariantList list;
        const ManagedObjects objects = reply.value();
        for (auto it = objects.cbegin(); it != objects.cend(); ++it) {
            if (it->contains(adapterIface))
                m_btAdapter = it.key().path();
            if (!it->contains(deviceIface))
                continue;
            const QVariantMap d = it->value(deviceIface);
            const bool paired = d.value(QStringLiteral("Paired")).toBool();
            const QString address = d.value(QStringLiteral("Address")).toString();
            const QString name = d.value(QStringLiteral("Alias")).toString();
            // Urządzenia bez nazwy to zwykle cudze telefony i opaski w pobliżu
            if (!paired && (name.isEmpty() || QString(name).replace(QLatin1Char('-'), QLatin1Char(':')) == address))
                continue;
            list.append(QVariantMap{{QStringLiteral("path"), it.key().path()}, {QStringLiteral("name"), name},
                                    {QStringLiteral("icon"), d.value(QStringLiteral("Icon")).toString()}, {QStringLiteral("paired"), paired},
                                    {QStringLiteral("connected"), d.value(QStringLiteral("Connected")).toBool()}});
        }
        std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap x = a.toMap(), y = b.toMap();
            const auto rank = [](const QVariantMap &n) { return n.value(QStringLiteral("connected")).toBool() ? 2 : n.value(QStringLiteral("paired")).toBool() ? 1 : 0; };
            if (rank(x) != rank(y))
                return rank(x) > rank(y);
            return x.value(QStringLiteral("name")).toString().localeAwareCompare(y.value(QStringLiteral("name")).toString()) < 0;
        });
        if (list != m_bt) {
            m_bt = list;
            Q_EMIT bluetoothChanged();
        }
        if (m_page == QLatin1String("bluetooth") && m_btBusy.isEmpty())
            setDiscovery(true);
    });
}

void Connectivity::finishDeviceAction(const QString &error)
{
    m_btBusy.clear();
    m_btError = error;
    Q_EMIT bluetoothChanged();
    clearPairing();
    readBluetooth();
}

void Connectivity::toggleDevice(const QString &path)
{
    if (m_preview || !m_btBusy.isEmpty())
        return;
    QVariantMap device;
    for (const QVariant &d : std::as_const(m_bt))
        if (d.toMap().value(QStringLiteral("path")).toString() == path)
            device = d.toMap();
    m_btBusy = path;
    m_btError.clear();
    Q_EMIT bluetoothChanged();
    setDiscovery(false);    // skanowanie w trakcie parowania często je zrywa

    if (device.value(QStringLiteral("connected")).toBool()) {
        call(this, QDBusConnection::systemBus(), QDBusMessage::createMethodCall(bluez, path, deviceIface, QStringLiteral("Disconnect")), 10000,
             [this](const QDBusMessage &reply) { finishDeviceAction(reply.type() == QDBusMessage::ErrorMessage ? QStringLiteral("Nie udało się rozłączyć urządzenia.") : QString()); });
    } else if (device.value(QStringLiteral("paired")).toBool()) {
        connectDevice(path);
    } else {
        pair(path);
    }
}

void Connectivity::pair(const QString &path)
{
    // Dwie minuty: tyle ma użytkownik na przepisanie kodu na klawiaturze
    call(this, QDBusConnection::systemBus(), QDBusMessage::createMethodCall(bluez, path, deviceIface, QStringLiteral("Pair")), 120000, [this, path](const QDBusMessage &reply) {
        if (reply.type() == QDBusMessage::ErrorMessage) {
            const bool cancelled = reply.errorName().contains(QLatin1String("Canceled")) || reply.errorName().contains(QLatin1String("Rejected"));
            finishDeviceAction(cancelled ? QString() : QStringLiteral("Nie udało się sparować. Włącz tryb parowania w urządzeniu i spróbuj ponownie."));
            return;
        }
        clearPairing();
        // Zaufane urządzenie samo łączy się po każdym włączeniu
        QDBusMessage trust = QDBusMessage::createMethodCall(bluez, path, propertiesIface, QStringLiteral("Set"));
        trust << deviceIface << QStringLiteral("Trusted") << QVariant::fromValue(QDBusVariant(true));
        QDBusConnection::systemBus().asyncCall(trust);
        connectDevice(path);
    });
}

void Connectivity::connectDevice(const QString &path)
{
    call(this, QDBusConnection::systemBus(), QDBusMessage::createMethodCall(bluez, path, deviceIface, QStringLiteral("Connect")), 30000,
         [this](const QDBusMessage &reply) {
             finishDeviceAction(reply.type() == QDBusMessage::ErrorMessage ? QStringLiteral("Nie udało się połączyć. Sprawdź, czy urządzenie jest włączone.") : QString());
         });
}

void Connectivity::forgetDevice(const QString &path)
{
    if (m_preview || m_btAdapter.isEmpty())
        return;
    QDBusMessage remove = QDBusMessage::createMethodCall(bluez, m_btAdapter, adapterIface, QStringLiteral("RemoveDevice"));
    remove << QVariant::fromValue(QDBusObjectPath(path));
    call(this, QDBusConnection::systemBus(), remove, 5000, [this](const QDBusMessage &) { readBluetooth(); });
}

void Connectivity::showPairing(const QString &kind, const QString &code, const QString &devicePath, int entered)
{
    QString name = devicePath;
    for (const QVariant &d : std::as_const(m_bt))
        if (d.toMap().value(QStringLiteral("path")).toString() == devicePath)
            name = d.toMap().value(QStringLiteral("name")).toString();
    if (name == devicePath)
        name = QStringLiteral("Urządzenie Bluetooth");
    m_pairingKind = kind;
    m_pairingCode = code;
    m_pairingDevice = name;
    m_pairingEntered = entered;
    Q_EMIT pairingChanged();
}

void Connectivity::clearPairing()
{
    if (m_pairingKind.isEmpty())
        return;
    m_pairingKind.clear();
    m_pairingCode.clear();
    m_pairingDevice.clear();
    m_pairingEntered = 0;
    Q_EMIT pairingChanged();
}

void Connectivity::answerPairing(bool accepted)
{
    if (m_preview)
        return;
    if (m_pairingKind == QLatin1String("confirm"))
        m_agent->answer(accepted);
    else if (!accepted && !m_btBusy.isEmpty())
        QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(bluez, m_btBusy, deviceIface, QStringLiteral("CancelPairing")));
    clearPairing();
}

// ——— Dźwięk ———
void Connectivity::readAudio()
{
    run(this, QStringLiteral("wpctl"), {QStringLiteral("status")}, [this](const QString &out, bool) {
        static const QRegularExpression item(QStringLiteral("^[\\s│├└─]*(\\*)?\\s*(\\d+)\\.\\s+(.+?)\\s*(\\[vol:.*)?$"));
        QVariantList outputs, inputs;
        QVariantList *section = nullptr;
        bool audio = false;
        for (const QString &line : out.split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("Audio")))
                audio = true;
            else if (!line.isEmpty() && line[0].isLetter())
                audio = false;
            if (!audio)
                continue;
            if (line.contains(QLatin1String("Sinks:")))
                section = &outputs;
            else if (line.contains(QLatin1String("Sources:")))
                section = &inputs;
            else if (line.contains(QLatin1Char(':')) && !line.contains(QLatin1String("[vol:")))
                section = nullptr;
            else if (section) {
                const auto m = item.match(line);
                if (m.hasMatch())
                    section->append(QVariantMap{{QStringLiteral("id"), m.captured(2).toInt()}, {QStringLiteral("name"), m.captured(3)},
                                                {QStringLiteral("active"), !m.captured(1).isEmpty()}});
            }
        }
        if (outputs != m_outputs || inputs != m_inputs) {
            m_outputs = outputs;
            m_inputs = inputs;
            Q_EMIT audioChanged();
        }
    });
}

void Connectivity::setAudioDefault(int id)
{
    if (m_preview)
        return;
    run(this, QStringLiteral("wpctl"), {QStringLiteral("set-default"), QString::number(id)}, [this](const QString &, bool) { readAudio(); });
}

#include "phone.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QFileInfo>
#include <QProcess>
#include <QUrl>

namespace {

const QString service = QStringLiteral("org.kde.kdeconnect");
const QString daemonPath = QStringLiteral("/modules/kdeconnect");
const QString daemonIface = QStringLiteral("org.kde.kdeconnect.daemon");
const QString deviceIface = QStringLiteral("org.kde.kdeconnect.device");

QString devicePath(const QString &id, const QString &plugin = {})
{
    return daemonPath + QStringLiteral("/devices/") + id + (plugin.isEmpty() ? QString() : QLatin1Char('/') + plugin);
}

QString pluginIface(const QString &plugin)
{
    return deviceIface + QLatin1Char('.') + plugin;
}

// Odczyt właściwości przez org.freedesktop.DBus.Properties (QDBusInterface::property bywa kapryśne przy braku obiektu)
QVariant prop(const QString &path, const QString &iface, const QString &name)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    msg << iface << name;
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 2000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return reply.arguments().constFirst().value<QDBusVariant>().variant();
}

QVariant invoke(const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage)
        return {};
    return reply.arguments().isEmpty() ? QVariant(true) : reply.arguments().constFirst();
}

// Liczebnik: 1 plik, 2 pliki, 5 plików
QString files(int n)
{
    if (n == 1)
        return QStringLiteral("1 plik");
    const int d = n % 10, h = n % 100;
    return QString::number(n) + (d >= 2 && d <= 4 && (h < 12 || h > 14) ? QStringLiteral(" pliki") : QStringLiteral(" plików"));
}

} // namespace

Phone::Phone(QObject *parent)
    : QObject(parent)
    , m_preview(qEnvironmentVariableIsSet("ASTER_PREVIEW"))
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(120);
    connect(&m_debounce, &QTimer::timeout, this, &Phone::reload);
    // Zapasowe odświeżanie (bateria i zasięg zmieniają się bez sygnałów, gdy telefon śpi)
    m_poll.setInterval(15000);
    connect(&m_poll, &QTimer::timeout, this, &Phone::reload);
    m_poll.start();

    QDBusConnection bus = QDBusConnection::sessionBus();
    for (const char *sig : {"deviceAdded", "deviceRemoved", "deviceVisibilityChanged", "deviceListChanged", "pairingRequestsChanged", "announcedNameChanged"})
        bus.connect(service, daemonPath, daemonIface, QString::fromLatin1(sig), this, SLOT(scheduleReload()));
    // Puste ścieżki = sygnały ze wszystkich urządzeń
    for (const char *sig : {"reachableChanged", "pairStateChanged", "nameChanged", "pluginsChanged"})
        bus.connect(service, QString(), deviceIface, QString::fromLatin1(sig), this, SLOT(scheduleReload()));
    bus.connect(service, QString(), pluginIface(QStringLiteral("battery")), QStringLiteral("refreshed"), this, SLOT(scheduleReload()));
    bus.connect(service, QString(), pluginIface(QStringLiteral("connectivity_report")), QStringLiteral("refreshed"), this, SLOT(scheduleReload()));
    for (const char *sig : {"notificationPosted", "notificationRemoved", "notificationUpdated", "allNotificationsRemoved"})
        bus.connect(service, QString(), pluginIface(QStringLiteral("notifications")), QString::fromLatin1(sig), this, SLOT(scheduleReload()));
    // Usługa wystartowała albo padła
    auto *watcher = new QDBusServiceWatcher(service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &Phone::scheduleReload);

    start();
    reload();
}

void Phone::scheduleReload()
{
    m_debounce.start();
}

void Phone::start()
{
    if (m_preview)
        return;
    QDBusConnection::sessionBus().interface()->startService(service);
    scheduleReload();
}

void Phone::reload()
{
    if (m_preview) {
        m_running = true;
        m_selfName = QStringLiteral("laptop-dominika");
        m_devices = previewDevices();
        Q_EMIT changed();
        return;
    }
    m_running = QDBusConnection::sessionBus().interface()->isServiceRegistered(service);
    QVariantList list;
    if (m_running) {
        m_selfName = invoke(daemonPath, daemonIface, QStringLiteral("announcedName")).toString();
        const QStringList ids = invoke(daemonPath, daemonIface, QStringLiteral("devices"), {false, false}).toStringList();
        for (const QString &id : ids) {
            const QVariantMap d = readDevice(id);
            // Nieosiągalne i niesparowane to tylko ślady po dawnych urządzeniach
            if (d.value(QStringLiteral("paired")).toBool() || d.value(QStringLiteral("reachable")).toBool())
                list << d;
        }
        // Najpierw sparowane, potem dostępne, potem nazwa
        std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap x = a.toMap(), y = b.toMap();
            const int rx = x.value(QStringLiteral("paired")).toBool() * 2 + x.value(QStringLiteral("reachable")).toBool();
            const int ry = y.value(QStringLiteral("paired")).toBool() * 2 + y.value(QStringLiteral("reachable")).toBool();
            if (rx != ry)
                return rx > ry;
            return x.value(QStringLiteral("name")).toString().localeAwareCompare(y.value(QStringLiteral("name")).toString()) < 0;
        });
    }
    m_devices = list;
    Q_EMIT changed();
}

QVariantMap Phone::readDevice(const QString &id) const
{
    const QString path = devicePath(id);
    QVariantMap d;
    d[QStringLiteral("id")] = id;
    d[QStringLiteral("name")] = prop(path, deviceIface, QStringLiteral("name"));
    d[QStringLiteral("type")] = prop(path, deviceIface, QStringLiteral("type"));
    d[QStringLiteral("reachable")] = prop(path, deviceIface, QStringLiteral("isReachable")).toBool();
    const bool paired = prop(path, deviceIface, QStringLiteral("isPaired")).toBool();
    const bool byPeer = prop(path, deviceIface, QStringLiteral("isPairRequestedByPeer")).toBool();
    d[QStringLiteral("paired")] = paired;
    d[QStringLiteral("requested")] = prop(path, deviceIface, QStringLiteral("isPairRequested")).toBool();
    d[QStringLiteral("requestedByPeer")] = byPeer;
    if (byPeer || !paired) {
        QVariant key = prop(path, deviceIface, QStringLiteral("verificationKey"));
        if (!key.isValid())
            key = invoke(path, deviceIface, QStringLiteral("verificationKey"));
        d[QStringLiteral("verification")] = key.toString();
    }

    const QStringList plugins = invoke(path, deviceIface, QStringLiteral("loadedPlugins")).toStringList();
    QStringList short_;
    for (const QString &p : plugins)
        short_ << QString(p).remove(QStringLiteral("kdeconnect_"));
    d[QStringLiteral("plugins")] = short_;

    int battery = -1;
    bool charging = false;
    if (short_.contains(QStringLiteral("battery"))) {
        const QVariant c = prop(devicePath(id, QStringLiteral("battery")), pluginIface(QStringLiteral("battery")), QStringLiteral("charge"));
        battery = c.isValid() ? c.toInt() : -1;
        charging = prop(devicePath(id, QStringLiteral("battery")), pluginIface(QStringLiteral("battery")), QStringLiteral("isCharging")).toBool();
    }
    d[QStringLiteral("battery")] = battery;
    d[QStringLiteral("charging")] = charging;

    QString network;
    int strength = -1;
    if (short_.contains(QStringLiteral("connectivity_report"))) {
        const QString p = devicePath(id, QStringLiteral("connectivity_report"));
        network = prop(p, pluginIface(QStringLiteral("connectivity_report")), QStringLiteral("cellularNetworkType")).toString();
        const QVariant s = prop(p, pluginIface(QStringLiteral("connectivity_report")), QStringLiteral("cellularNetworkStrength"));
        strength = s.isValid() ? s.toInt() : -1;
    }
    d[QStringLiteral("network")] = network == QLatin1String("Unknown") ? QString() : network;
    d[QStringLiteral("strength")] = strength;

    QVariantList notes;
    if (short_.contains(QStringLiteral("notifications"))) {
        const QString base = devicePath(id, QStringLiteral("notifications"));
        const QStringList ids = invoke(base, pluginIface(QStringLiteral("notifications")), QStringLiteral("activeNotifications")).toStringList();
        const QString iface = pluginIface(QStringLiteral("notifications.notification"));
        for (auto it = ids.crbegin(); it != ids.crend(); ++it) {      // najnowsze na górze
            const QString np = base + QLatin1Char('/') + *it;
            const QString icon = prop(np, iface, QStringLiteral("iconPath")).toString();
            notes << QVariantMap{
                {QStringLiteral("id"), *it},
                {QStringLiteral("app"), prop(np, iface, QStringLiteral("appName"))},
                {QStringLiteral("title"), prop(np, iface, QStringLiteral("title"))},
                {QStringLiteral("text"), prop(np, iface, QStringLiteral("text"))},
                {QStringLiteral("icon"), !icon.isEmpty() && QFileInfo::exists(icon) ? QUrl::fromLocalFile(icon).toString() : QString()},
                {QStringLiteral("dismissable"), prop(np, iface, QStringLiteral("dismissable")).toBool()},
            };
        }
    }
    d[QStringLiteral("notifications")] = notes;
    return d;
}

QString Phone::deviceName(const QString &id) const
{
    for (const QVariant &v : m_devices)
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            return v.toMap().value(QStringLiteral("name")).toString();
    return QStringLiteral("telefonu");
}

bool Phone::call(const QString &id, const QString &plugin, const QString &method, const QVariantList &args)
{
    if (m_preview)
        return true;
    const QString path = plugin.isEmpty() ? devicePath(id) : devicePath(id, plugin);
    const QString iface = plugin.isEmpty() ? deviceIface : pluginIface(plugin);
    return invoke(path, iface, method, args).isValid();
}

void Phone::setSelfName(const QString &name)
{
    if (name.trimmed().isEmpty() || m_preview)
        return;
    invoke(daemonPath, daemonIface, QStringLiteral("setAnnouncedName"), {name.trimmed()});
    scheduleReload();
}

void Phone::pair(const QString &id) { call(id, {}, QStringLiteral("requestPairing")); scheduleReload(); }
void Phone::accept(const QString &id) { call(id, {}, QStringLiteral("acceptPairing")); scheduleReload(); }
void Phone::reject(const QString &id) { call(id, {}, QStringLiteral("cancelPairing")); scheduleReload(); }
void Phone::unpair(const QString &id) { call(id, {}, QStringLiteral("unpair")); scheduleReload(); }

void Phone::ring(const QString &id)
{
    if (call(id, QStringLiteral("findmyphone"), QStringLiteral("ring")))
        Q_EMIT message(QStringLiteral("Dzwonię na ") + deviceName(id) + QStringLiteral(" — wyłączysz go na telefonie"));
}

void Phone::ping(const QString &id)
{
    if (call(id, QStringLiteral("ping"), QStringLiteral("sendPing")))
        Q_EMIT message(QStringLiteral("Wysłano powiadomienie testowe"));
}

void Phone::sendFiles(const QString &id, const QStringList &urls)
{
    if (urls.isEmpty())
        return;
    if (call(id, QStringLiteral("share"), QStringLiteral("shareUrls"), {urls}))
        Q_EMIT message(QStringLiteral("Wysyłam %1 do: %2").arg(files(urls.size()), deviceName(id)));
}

void Phone::sendText(const QString &id, const QString &text)
{
    if (text.trimmed().isEmpty())
        return;
    if (call(id, QStringLiteral("share"), QStringLiteral("shareText"), {text}))
        Q_EMIT message(QStringLiteral("Wysłano tekst do: ") + deviceName(id));
}

void Phone::sendClipboard(const QString &id)
{
    if (call(id, QStringLiteral("clipboard"), QStringLiteral("sendClipboard")))
        Q_EMIT message(QStringLiteral("Schowek jest już na telefonie — wklej go tam"));
}

// Pliki telefonu: montowanie SFTP potrafi trwać kilka sekund — w tle, potem folder w Plikach
void Phone::browse(const QString &id)
{
    if (m_preview)
        return;
    Q_EMIT message(QStringLiteral("Łączę się z plikami telefonu…"));
    const QString path = devicePath(id, QStringLiteral("sftp"));
    const QString iface = pluginIface(QStringLiteral("sftp"));
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, QStringLiteral("mountAndWait"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 30000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, path, iface](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<bool> reply = *w;
        const QString mount = invoke(path, iface, QStringLiteral("mountPoint")).toString();
        if (reply.isError() || !reply.value() || mount.isEmpty()) {
            const QString err = invoke(path, iface, QStringLiteral("getMountError")).toString();
            Q_EMIT message(QStringLiteral("Nie udało się otworzyć plików telefonu") + (err.isEmpty() ? QString() : QStringLiteral(": ") + err));
            return;
        }
        // Wspólna pamięć telefonu zwykle w podfolderze — weź pierwszy katalog z listy, jeśli jest
        const QVariantMap dirs = invoke(path, iface, QStringLiteral("getDirectories")).toMap();
        const QString target = dirs.isEmpty() ? mount : dirs.firstKey();
        if (!QProcess::startDetached(QStringLiteral("aster-files"), {target}))
            QProcess::startDetached(QStringLiteral("xdg-open"), {target});
    });
}

void Phone::dismiss(const QString &id, const QString &notification)
{
    if (m_preview)
        return;
    invoke(devicePath(id, QStringLiteral("notifications/") + notification),
           pluginIface(QStringLiteral("notifications.notification")), QStringLiteral("dismiss"));
    scheduleReload();
}

// ASTER_PREVIEW: przykładowe urządzenia do zrzutów ekranu
QVariantList Phone::previewDevices() const
{
    auto note = [](const QString &id, const QString &app, const QString &title, const QString &text) {
        return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("app"), app}, {QStringLiteral("title"), title},
                           {QStringLiteral("text"), text}, {QStringLiteral("icon"), QString()}, {QStringLiteral("dismissable"), true}};
    };
    const QStringList all = {QStringLiteral("battery"), QStringLiteral("connectivity_report"), QStringLiteral("findmyphone"),
                             QStringLiteral("share"), QStringLiteral("clipboard"), QStringLiteral("sftp"),
                             QStringLiteral("notifications"), QStringLiteral("ping")};
    return {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("p1")}, {QStringLiteral("name"), QStringLiteral("Pixel 8")},
                    {QStringLiteral("type"), QStringLiteral("phone")}, {QStringLiteral("reachable"), true},
                    {QStringLiteral("paired"), true}, {QStringLiteral("requested"), false}, {QStringLiteral("requestedByPeer"), false},
                    {QStringLiteral("battery"), 76}, {QStringLiteral("charging"), true}, {QStringLiteral("network"), QStringLiteral("5G")},
                    {QStringLiteral("strength"), 3}, {QStringLiteral("plugins"), all},
                    {QStringLiteral("notifications"), QVariantList{
                        note(QStringLiteral("1"), QStringLiteral("WhatsApp"), QStringLiteral("Mama"), QStringLiteral("Będziesz na obiedzie w niedzielę? 🍲")),
                        note(QStringLiteral("2"), QStringLiteral("Gmail"), QStringLiteral("Allegro"), QStringLiteral("Twoja paczka jest w drodze — dostawa jutro do 12:00")),
                        note(QStringLiteral("3"), QStringLiteral("Kalendarz"), QStringLiteral("Dentysta"), QStringLiteral("Jutro, 9:30 · ul. Długa 12")),
                        note(QStringLiteral("4"), QStringLiteral("mBank"), QStringLiteral("Przelew przychodzący"), QStringLiteral("Otrzymano 120,00 zł od: Jan Kowalski")),
                    }}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("t1")}, {QStringLiteral("name"), QStringLiteral("Galaxy Tab S9")},
                    {QStringLiteral("type"), QStringLiteral("tablet")}, {QStringLiteral("reachable"), true},
                    {QStringLiteral("paired"), false}, {QStringLiteral("requested"), false}, {QStringLiteral("requestedByPeer"), true},
                    {QStringLiteral("verification"), QStringLiteral("7F3A 91C2")},
                    {QStringLiteral("battery"), -1}, {QStringLiteral("charging"), false}, {QStringLiteral("network"), QString()},
                    {QStringLiteral("strength"), -1}, {QStringLiteral("plugins"), QStringList()}, {QStringLiteral("notifications"), QVariantList()}},
    };
}

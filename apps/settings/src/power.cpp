#include "power.h"

#include "util.h"

#include <QDir>

Power::Power(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    if (m_preview) {
        m_hasBattery = true;
        m_level = 84;
        m_charging = false;
        m_pluggedIn = false;
        m_health = 93;
        m_cycles = 212;
        m_minutesLeft = 372;
        m_profiles = {QStringLiteral("power-saver"), QStringLiteral("balanced"), QStringLiteral("performance")};
        m_profile = QStringLiteral("balanced");
        return;
    }
    m_poll.setInterval(10000);
    connect(&m_poll, &QTimer::timeout, this, &Power::readBattery);
    m_poll.start();
    readBattery();
    readProfiles();
}

void Power::readBattery()
{
    const QDir dir(QStringLiteral("/sys/class/power_supply"));
    bool battery = false, ac = false;
    for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        const QString base = dir.filePath(name) + QLatin1Char('/');
        const QString type = readTextFile(base + QStringLiteral("type"));
        if (type == QLatin1String("Mains"))
            ac |= readTextFile(base + QStringLiteral("online")) == QLatin1String("1");
        if (type != QLatin1String("Battery") || readTextFile(base + QStringLiteral("scope")) == QLatin1String("Device"))
            continue;
        battery = true;
        m_level = readTextFile(base + QStringLiteral("capacity")).toInt();
        const QString status = readTextFile(base + QStringLiteral("status"));
        m_charging = status == QLatin1String("Charging");
        // Energia (µWh) albo ładunek (µAh) — zależnie od sterownika
        const auto num = [&base](const char *a, const char *b) {
            const QString v = readTextFile(base + QLatin1String(a));
            return v.isEmpty() ? readTextFile(base + QLatin1String(b)).toDouble() : v.toDouble();
        };
        const double full = num("energy_full", "charge_full"), design = num("energy_full_design", "charge_full_design");
        const double now = num("energy_now", "charge_now"), rate = num("power_now", "current_now");
        m_health = design > 0 && full > 0 ? qMin(100, int(qRound(full / design * 100))) : -1;
        const QString cycles = readTextFile(base + QStringLiteral("cycle_count"));
        m_cycles = cycles.isEmpty() || cycles == QLatin1String("0") ? -1 : cycles.toInt();
        m_minutesLeft = rate > 0 ? int((m_charging ? (full - now) : now) / rate * 60) : -1;
    }
    m_hasBattery = battery;
    m_pluggedIn = ac || !battery;
    Q_EMIT changed();
}

void Power::readProfiles()
{
    // Nowa nazwa usługi (UPower) i stara (net.hadess) — obie mają ten sam interfejs
    const auto read = [this](const QString &service, const QString &path) {
        dbusGetAll(this, service, path, service, true, [this, service, path](const QVariantMap &p) {
            if (p.isEmpty())
                return;
            m_ppdService = service + QLatin1Char('|') + path;
            QStringList profiles;
            const QDBusArgument arg = p.value(QStringLiteral("Profiles")).value<QDBusArgument>();
            arg.beginArray();
            while (!arg.atEnd()) {
                QVariantMap m;
                arg >> m;
                profiles << m.value(QStringLiteral("Profile")).toString();
            }
            arg.endArray();
            // Kolejność od oszczędzania do wydajności
            QStringList ordered;
            for (const char *id : {"power-saver", "balanced", "performance"})
                if (profiles.contains(QLatin1String(id)))
                    ordered << QLatin1String(id);
            m_profiles = ordered;
            m_profile = p.value(QStringLiteral("ActiveProfile")).toString();
            Q_EMIT changed();
        });
    };
    read(QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("/org/freedesktop/UPower/PowerProfiles"));
    read(QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"));
}

void Power::setProfile(const QString &profile)
{
    m_profile = profile;
    Q_EMIT changed();
    if (m_preview || m_ppdService.isEmpty())
        return;
    const QString service = m_ppdService.section(QLatin1Char('|'), 0, 0), path = m_ppdService.section(QLatin1Char('|'), 1);
    dbusSetProperty(this, service, path, service, QStringLiteral("ActiveProfile"), profile, true, [this](const QDBusMessage &) { readProfiles(); });
}

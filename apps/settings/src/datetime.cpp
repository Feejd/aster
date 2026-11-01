#include "datetime.h"

#include "util.h"

#include <QCollator>
#include <QDateTime>
#include <QTimeZone>

static const QString td = QStringLiteral("org.freedesktop.timedate1");
static const QString tdPath = QStringLiteral("/org/freedesktop/timedate1");

// Polskie nazwy regionów i najczęstszych miast
static QString plRegion(const QString &r)
{
    static const QHash<QString, QString> m{
        {QStringLiteral("Europe"), QStringLiteral("Europa")}, {QStringLiteral("America"), QStringLiteral("Ameryka")},
        {QStringLiteral("Asia"), QStringLiteral("Azja")}, {QStringLiteral("Africa"), QStringLiteral("Afryka")},
        {QStringLiteral("Australia"), QStringLiteral("Australia")}, {QStringLiteral("Pacific"), QStringLiteral("Pacyfik")},
        {QStringLiteral("Atlantic"), QStringLiteral("Atlantyk")}, {QStringLiteral("Indian"), QStringLiteral("Ocean Indyjski")},
        {QStringLiteral("Antarctica"), QStringLiteral("Antarktyda")}, {QStringLiteral("Arctic"), QStringLiteral("Arktyka")},
    };
    return m.value(r, r);
}

static QString plCity(const QString &c)
{
    static const QHash<QString, QString> m{
        {QStringLiteral("Warsaw"), QStringLiteral("Warszawa")}, {QStringLiteral("London"), QStringLiteral("Londyn")},
        {QStringLiteral("Prague"), QStringLiteral("Praga")}, {QStringLiteral("Paris"), QStringLiteral("Paryż")},
        {QStringLiteral("Rome"), QStringLiteral("Rzym")}, {QStringLiteral("Moscow"), QStringLiteral("Moskwa")},
        {QStringLiteral("Kyiv"), QStringLiteral("Kijów")}, {QStringLiteral("Kiev"), QStringLiteral("Kijów")},
        {QStringLiteral("Vienna"), QStringLiteral("Wiedeń")}, {QStringLiteral("Lisbon"), QStringLiteral("Lizbona")},
        {QStringLiteral("Brussels"), QStringLiteral("Bruksela")}, {QStringLiteral("Copenhagen"), QStringLiteral("Kopenhaga")},
        {QStringLiteral("Athens"), QStringLiteral("Ateny")}, {QStringLiteral("Vilnius"), QStringLiteral("Wilno")},
        {QStringLiteral("Bucharest"), QStringLiteral("Bukareszt")}, {QStringLiteral("Budapest"), QStringLiteral("Budapeszt")},
        {QStringLiteral("Belgrade"), QStringLiteral("Belgrad")}, {QStringLiteral("Zurich"), QStringLiteral("Zurych")},
        {QStringLiteral("Stockholm"), QStringLiteral("Sztokholm")}, {QStringLiteral("Helsinki"), QStringLiteral("Helsinki")},
        {QStringLiteral("Dublin"), QStringLiteral("Dublin")}, {QStringLiteral("Madrid"), QStringLiteral("Madryt")},
        {QStringLiteral("Berlin"), QStringLiteral("Berlin")}, {QStringLiteral("Amsterdam"), QStringLiteral("Amsterdam")},
        {QStringLiteral("Istanbul"), QStringLiteral("Stambuł")}, {QStringLiteral("New_York"), QStringLiteral("Nowy Jork")},
        {QStringLiteral("Los_Angeles"), QStringLiteral("Los Angeles")}, {QStringLiteral("Chicago"), QStringLiteral("Chicago")},
        {QStringLiteral("Tokyo"), QStringLiteral("Tokio")}, {QStringLiteral("Shanghai"), QStringLiteral("Szanghaj")},
        {QStringLiteral("Dubai"), QStringLiteral("Dubaj")}, {QStringLiteral("Mexico_City"), QStringLiteral("Meksyk")},
        {QStringLiteral("Sao_Paulo"), QStringLiteral("São Paulo")}, {QStringLiteral("Sydney"), QStringLiteral("Sydney")},
        {QStringLiteral("Minsk"), QStringLiteral("Mińsk")}, {QStringLiteral("Riga"), QStringLiteral("Ryga")},
        {QStringLiteral("Tallinn"), QStringLiteral("Tallin")}, {QStringLiteral("Bratislava"), QStringLiteral("Bratysława")},
        {QStringLiteral("Ljubljana"), QStringLiteral("Lublana")}, {QStringLiteral("Zagreb"), QStringLiteral("Zagrzeb")},
        {QStringLiteral("Sofia"), QStringLiteral("Sofia")}, {QStringLiteral("Oslo"), QStringLiteral("Oslo")},
        {QStringLiteral("Reykjavik"), QStringLiteral("Reykjavík")}, {QStringLiteral("Canary"), QStringLiteral("Wyspy Kanaryjskie")},
    };
    QString s = m.value(c);
    if (s.isEmpty()) {
        s = c;
        s.replace(QLatin1Char('_'), QLatin1Char(' '));
    }
    return s;
}

DateTime::DateTime(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    m_timezone = QString::fromUtf8(QTimeZone::systemTimeZoneId());
    if (m_preview) {
        m_timezone = QStringLiteral("Europe/Warsaw");
        return;
    }
    read();
}

void DateTime::read()
{
    dbusGetAll(this, td, tdPath, td, true, [this](const QVariantMap &p) {
        if (p.isEmpty())
            return;
        m_timezone = p.value(QStringLiteral("Timezone"), m_timezone).toString();
        m_ntp = p.value(QStringLiteral("NTP")).toBool();
        m_canNtp = p.value(QStringLiteral("CanNTP"), true).toBool();
        Q_EMIT changed();
    });
}

QString DateTime::label(const QString &tz) const
{
    const QStringList parts = tz.split(QLatin1Char('/'));
    if (parts.size() < 2)
        return tz;
    return plCity(parts.last()) + QStringLiteral(" (") + plRegion(parts.first()) + QLatin1Char(')');
}

QVariantList DateTime::timezones() const
{
    if (!m_zones.isEmpty())
        return m_zones;
    const QDateTime now = QDateTime::currentDateTimeUtc();
    struct Z { QString id, city, region, offset; };
    QList<Z> list;
    for (const QByteArray &idb : QTimeZone::availableTimeZoneIds()) {
        const QString id = QString::fromUtf8(idb);
        const QStringList parts = id.split(QLatin1Char('/'));
        if (parts.size() < 2 || parts.first() == QLatin1String("Etc") || parts.first() == QLatin1String("SystemV") || parts.first() == QLatin1String("US"))
            continue;
        const int secs = QTimeZone(idb).offsetFromUtc(now);
        const QString offset = QStringLiteral("UTC%1%2:%3").arg(secs < 0 ? QLatin1Char('−') : QLatin1Char('+'))
                                   .arg(qAbs(secs) / 3600, 2, 10, QLatin1Char('0')).arg(qAbs(secs) % 3600 / 60, 2, 10, QLatin1Char('0'));
        list << Z{id, plCity(parts.last()), plRegion(parts.first()), offset};
    }
    QCollator c(QLocale(QStringLiteral("pl_PL")));
    std::sort(list.begin(), list.end(), [&c](const Z &a, const Z &b) { return c.compare(a.city, b.city) < 0; });
    for (const Z &z : list)
        m_zones << QVariantMap{{QStringLiteral("id"), z.id}, {QStringLiteral("city"), z.city}, {QStringLiteral("region"), z.region}, {QStringLiteral("offset"), z.offset}};
    return m_zones;
}

void DateTime::setTimezone(const QString &tz)
{
    m_timezone = tz;
    Q_EMIT changed();
    if (m_preview)
        return;
    dbusCall(this, dbusMethod(td, tdPath, td, QStringLiteral("SetTimezone"), {tz, true}), true, true, [this](const QDBusMessage &r) {
        if (r.type() != QDBusMessage::ReplyMessage)
            Q_EMIT message(QStringLiteral("Nie udało się zmienić strefy czasowej"));
        read();
    });
}

void DateTime::setNtp(bool on)
{
    m_ntp = on;
    Q_EMIT changed();
    if (m_preview)
        return;
    dbusCall(this, dbusMethod(td, tdPath, td, QStringLiteral("SetNTP"), {on, true}), true, true, [this](const QDBusMessage &) { read(); });
}

void DateTime::setTime(const QDateTime &when)
{
    if (m_preview)
        return;
    const qint64 usec = when.toUTC().toMSecsSinceEpoch() * 1000;
    dbusCall(this, dbusMethod(td, tdPath, td, QStringLiteral("SetTime"), {usec, false, true}), true, true, [this](const QDBusMessage &r) {
        Q_EMIT message(r.type() == QDBusMessage::ReplyMessage ? QStringLiteral("Ustawiono czas") : QStringLiteral("Nie udało się ustawić czasu"));
    });
}

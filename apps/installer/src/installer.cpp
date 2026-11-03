#include "installer.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimeZone>

#include <crypt.h>
#include <unistd.h>

namespace {

// Polskie nazwy częściej wybieranych miast (reszta — angielska nazwa z bazy stref czasowych)
const QHash<QString, QString> &cityNames()
{
    static const QHash<QString, QString> names = {
        {QStringLiteral("Warsaw"), QStringLiteral("Warszawa")}, {QStringLiteral("London"), QStringLiteral("Londyn")},
        {QStringLiteral("Berlin"), QStringLiteral("Berlin")}, {QStringLiteral("Prague"), QStringLiteral("Praga")},
        {QStringLiteral("Vienna"), QStringLiteral("Wiedeń")}, {QStringLiteral("Paris"), QStringLiteral("Paryż")},
        {QStringLiteral("Rome"), QStringLiteral("Rzym")}, {QStringLiteral("Madrid"), QStringLiteral("Madryt")},
        {QStringLiteral("Lisbon"), QStringLiteral("Lizbona")}, {QStringLiteral("Brussels"), QStringLiteral("Bruksela")},
        {QStringLiteral("Amsterdam"), QStringLiteral("Amsterdam")}, {QStringLiteral("Copenhagen"), QStringLiteral("Kopenhaga")},
        {QStringLiteral("Stockholm"), QStringLiteral("Sztokholm")}, {QStringLiteral("Oslo"), QStringLiteral("Oslo")},
        {QStringLiteral("Helsinki"), QStringLiteral("Helsinki")}, {QStringLiteral("Vilnius"), QStringLiteral("Wilno")},
        {QStringLiteral("Riga"), QStringLiteral("Ryga")}, {QStringLiteral("Tallinn"), QStringLiteral("Tallin")},
        {QStringLiteral("Kyiv"), QStringLiteral("Kijów")}, {QStringLiteral("Kiev"), QStringLiteral("Kijów")},
        {QStringLiteral("Minsk"), QStringLiteral("Mińsk")}, {QStringLiteral("Moscow"), QStringLiteral("Moskwa")},
        {QStringLiteral("Bratislava"), QStringLiteral("Bratysława")}, {QStringLiteral("Budapest"), QStringLiteral("Budapeszt")},
        {QStringLiteral("Bucharest"), QStringLiteral("Bukareszt")}, {QStringLiteral("Athens"), QStringLiteral("Ateny")},
        {QStringLiteral("Dublin"), QStringLiteral("Dublin")}, {QStringLiteral("Zurich"), QStringLiteral("Zurych")},
        {QStringLiteral("Istanbul"), QStringLiteral("Stambuł")}, {QStringLiteral("New_York"), QStringLiteral("Nowy Jork")},
        {QStringLiteral("Chicago"), QStringLiteral("Chicago")}, {QStringLiteral("Los_Angeles"), QStringLiteral("Los Angeles")},
        {QStringLiteral("Toronto"), QStringLiteral("Toronto")}, {QStringLiteral("Tokyo"), QStringLiteral("Tokio")},
        {QStringLiteral("Shanghai"), QStringLiteral("Szanghaj")}, {QStringLiteral("Dubai"), QStringLiteral("Dubaj")},
        {QStringLiteral("Sydney"), QStringLiteral("Sydney")}, {QStringLiteral("Reykjavik"), QStringLiteral("Reykjavik")},
    };
    return names;
}

QString regionName(const QString &r)
{
    static const QHash<QString, QString> names = {
        {QStringLiteral("Europe"), QStringLiteral("Europa")}, {QStringLiteral("America"), QStringLiteral("Ameryka")},
        {QStringLiteral("Asia"), QStringLiteral("Azja")}, {QStringLiteral("Africa"), QStringLiteral("Afryka")},
        {QStringLiteral("Australia"), QStringLiteral("Australia")}, {QStringLiteral("Pacific"), QStringLiteral("Pacyfik")},
        {QStringLiteral("Atlantic"), QStringLiteral("Atlantyk")}, {QStringLiteral("Indian"), QStringLiteral("Ocean Indyjski")},
        {QStringLiteral("Antarctica"), QStringLiteral("Antarktyda")}, {QStringLiteral("Arctic"), QStringLiteral("Arktyka")},
    };
    return names.value(r);
}

QString sizeText(qint64 bytes)
{
    const double gb = bytes / 1e9;     // jak producenci dysków (dysk „512 GB”)
    if (gb >= 1000)
        return QString::number(gb / 1000, 'f', gb >= 10000 ? 0 : 1).replace(QLatin1Char('.'), QLatin1Char(',')) + QStringLiteral(" TB");
    return QString::number(qRound(gb)) + QStringLiteral(" GB");
}

// Wartość do pliku z ustawieniami (czytanego przez sh): w pojedynczych cudzysłowach
QString shQuote(const QString &v)
{
    QString s = v;
    s.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + s + QLatin1Char('\'');
}

QString hashPassword(const QString &password)
{
    char *salt = crypt_gensalt_ra(nullptr, 0, nullptr, 0);     // domyślny algorytm systemu (yescrypt)
    if (!salt)
        return {};
    struct crypt_data data = {};
    const char *hash = crypt_r(password.toUtf8().constData(), salt, &data);
    free(salt);
    return hash && hash[0] != '*' ? QString::fromLatin1(hash) : QString();
}

} // namespace

Installer::Installer(QObject *parent)
    : QObject(parent)
    , m_preview(qEnvironmentVariableIsSet("ASTER_PREVIEW"))
{
    m_timezones = loadTimezones();
    m_fake.setInterval(120);
    connect(&m_fake, &QTimer::timeout, this, &Installer::simulate);
    // Kopiowanie trwa minutami bez komunikatów — pasek rośnie powoli (coraz wolniej) do progu bieżącego kroku
    m_logTimer.setSingleShot(true);
    m_logTimer.setInterval(500);
    connect(&m_logTimer, &QTimer::timeout, this, &Installer::logChanged);
    m_creep.setInterval(1000);
    connect(&m_creep, &QTimer::timeout, this, [this] {
        if (m_progress < m_cap) {
            m_progress += qMax(0.0005, (m_cap - m_progress) * 0.012);
            Q_EMIT progressChanged();
        }
    });
    refreshDisks();
    checkWired();
    scanWifi();
}

QVariantList Installer::languages() const
{
    auto lang = [](const char *id, const char *name, const char *native, const char *kb, const char *tz) {
        return QVariantMap{{QStringLiteral("id"), QString::fromUtf8(id)}, {QStringLiteral("name"), QString::fromUtf8(name)},
                           {QStringLiteral("native"), QString::fromUtf8(native)}, {QStringLiteral("keyboard"), QString::fromUtf8(kb)},
                           {QStringLiteral("timezone"), QString::fromUtf8(tz)}};
    };
    return {
        lang("pl_PL.UTF-8", "Polski", "Polski", "pl", "Europe/Warsaw"),
        lang("en_US.UTF-8", "Angielski (USA)", "English (US)", "us", "America/New_York"),
        lang("en_GB.UTF-8", "Angielski (Wielka Brytania)", "English (UK)", "gb", "Europe/London"),
        lang("de_DE.UTF-8", "Niemiecki", "Deutsch", "de", "Europe/Berlin"),
        lang("uk_UA.UTF-8", "Ukraiński", "Українська", "ua", "Europe/Kyiv"),
        lang("cs_CZ.UTF-8", "Czeski", "Čeština", "cz", "Europe/Prague"),
        lang("fr_FR.UTF-8", "Francuski", "Français", "fr", "Europe/Paris"),
        lang("es_ES.UTF-8", "Hiszpański", "Español", "es", "Europe/Madrid"),
        lang("it_IT.UTF-8", "Włoski", "Italiano", "it", "Europe/Rome"),
    };
}

QVariantList Installer::keyboards() const
{
    auto kb = [](const char *id, const char *layout, const char *variant, const char *name, const char *keymap) {
        return QVariantMap{{QStringLiteral("id"), QString::fromUtf8(id)}, {QStringLiteral("layout"), QString::fromUtf8(layout)},
                           {QStringLiteral("variant"), QString::fromUtf8(variant)}, {QStringLiteral("name"), QString::fromUtf8(name)},
                           {QStringLiteral("keymap"), QString::fromUtf8(keymap)}};
    };
    return {
        kb("pl", "pl", "", "Polska (programisty)", "pl2"),
        kb("pl-qwertz", "pl", "qwertz", "Polska (maszynistki, QWERTZ)", "pl2"),
        kb("us", "us", "", "Angielska (USA)", "us"),
        kb("gb", "gb", "", "Angielska (Wielka Brytania)", "uk"),
        kb("de", "de", "", "Niemiecka", "de"),
        kb("ua", "ua", "", "Ukraińska", "ua"),
        kb("cz", "cz", "", "Czeska", "cz"),
        kb("fr", "fr", "", "Francuska", "fr"),
        kb("es", "es", "", "Hiszpańska", "es"),
        kb("it", "it", "", "Włoska", "it"),
    };
}

QVariantList Installer::loadTimezones() const
{
    static const QStringList order = {QStringLiteral("Europe"), QStringLiteral("America"), QStringLiteral("Asia"),
                                      QStringLiteral("Africa"), QStringLiteral("Australia"), QStringLiteral("Pacific"),
                                      QStringLiteral("Atlantic"), QStringLiteral("Indian")};
    QList<QVariantMap> list;
    const QDateTime now = QDateTime::currentDateTimeUtc();
    for (const QByteArray &idRaw : QTimeZone::availableTimeZoneIds()) {
        const QString id = QString::fromLatin1(idRaw);
        const QStringList parts = id.split(QLatin1Char('/'));
        if (parts.size() < 2 || !order.contains(parts.first()))
            continue;
        const QString raw = parts.last();
        const int off = QTimeZone(idRaw).offsetFromUtc(now);
        const QString offset = QStringLiteral("UTC%1%2").arg(off >= 0 ? QStringLiteral("+") : QStringLiteral("−"))
                                   .arg(off % 3600 ? QStringLiteral("%1:%2").arg(qAbs(off) / 3600).arg(qAbs(off) % 3600 / 60, 2, 10, QLatin1Char('0'))
                                                   : QString::number(qAbs(off) / 3600));
        list << QVariantMap{{QStringLiteral("id"), id},
                            {QStringLiteral("city"), cityNames().value(raw, QString(raw).replace(QLatin1Char('_'), QLatin1Char(' ')))},
                            {QStringLiteral("region"), regionName(parts.first())},
                            {QStringLiteral("offset"), offset},
                            {QStringLiteral("order"), order.indexOf(parts.first())}};
    }
    std::sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        if (a.value(QStringLiteral("order")).toInt() != b.value(QStringLiteral("order")).toInt())
            return a.value(QStringLiteral("order")).toInt() < b.value(QStringLiteral("order")).toInt();
        return a.value(QStringLiteral("city")).toString().localeAwareCompare(b.value(QStringLiteral("city")).toString()) < 0;
    });
    QVariantList out;
    for (const QVariantMap &m : list)
        out << m;
    return out;
}

QString Installer::timeIn(const QString &zone) const
{
    const QTimeZone tz(zone.toLatin1());
    return QDateTime::currentDateTime().toTimeZone(tz.isValid() ? tz : QTimeZone::systemTimeZone()).toString(QStringLiteral("HH:mm"));
}

// Dyski: całe dyski (nie partycje), bez pendrive’a, z którego działa instalator, i bez zbyt małych
void Installer::refreshDisks()
{
    QVariantList found;
    if (m_preview) {
        found << QVariantMap{{QStringLiteral("path"), QStringLiteral("/dev/nvme0n1")}, {QStringLiteral("name"), QStringLiteral("Samsung SSD 980 PRO")},
                             {QStringLiteral("sizeText"), QStringLiteral("512 GB")}, {QStringLiteral("kind"), QStringLiteral("ssd")},
                             {QStringLiteral("windows"), true}, {QStringLiteral("partitions"), 4}}
              << QVariantMap{{QStringLiteral("path"), QStringLiteral("/dev/sda")}, {QStringLiteral("name"), QStringLiteral("WDC WD10EZEX")},
                             {QStringLiteral("sizeText"), QStringLiteral("1 TB")}, {QStringLiteral("kind"), QStringLiteral("hdd")},
                             {QStringLiteral("windows"), false}, {QStringLiteral("partitions"), 1}};
        m_disks = found;
        Q_EMIT disksChanged();
        return;
    }
    // Nośnik instalatora (dmsquash-live montuje go w /run/initramfs/live)
    QString liveDisk;
    {
        QProcess p;
        p.start(QStringLiteral("findmnt"), {QStringLiteral("-no"), QStringLiteral("SOURCE"), QStringLiteral("/run/initramfs/live")});
        p.waitForFinished(3000);
        const QString src = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
        if (!src.isEmpty()) {
            QProcess q;
            q.start(QStringLiteral("lsblk"), {QStringLiteral("-no"), QStringLiteral("PKNAME"), src});
            q.waitForFinished(3000);
            const QString parent = QString::fromUtf8(q.readAllStandardOutput()).trimmed();
            liveDisk = parent.isEmpty() ? src : QStringLiteral("/dev/") + parent;
        }
    }
    QProcess p;
    p.start(QStringLiteral("lsblk"), {QStringLiteral("-J"), QStringLiteral("-b"), QStringLiteral("-o"),
                                      QStringLiteral("NAME,PATH,SIZE,MODEL,TRAN,TYPE,RO,ROTA,RM,FSTYPE,PARTLABEL,LABEL")});
    p.waitForFinished(5000);
    const QJsonArray devices = QJsonDocument::fromJson(p.readAllStandardOutput()).object().value(QStringLiteral("blockdevices")).toArray();
    for (const QJsonValue &v : devices) {
        const QJsonObject d = v.toObject();
        const QString path = d.value(QStringLiteral("path")).toString();
        const qint64 size = d.value(QStringLiteral("size")).toVariant().toLongLong();
        if (d.value(QStringLiteral("type")).toString() != QLatin1String("disk") || d.value(QStringLiteral("ro")).toBool()
            || path == liveDisk || size < 20LL * 1000 * 1000 * 1000 || path.startsWith(QLatin1String("/dev/zram")))
            continue;
        bool windows = false;
        const QJsonArray parts = d.value(QStringLiteral("children")).toArray();
        for (const QJsonValue &c : parts) {
            const QJsonObject o = c.toObject();
            windows |= o.value(QStringLiteral("fstype")).toString() == QLatin1String("ntfs")
                       || o.value(QStringLiteral("partlabel")).toString().contains(QLatin1String("Microsoft"));
        }
        const QString tran = d.value(QStringLiteral("tran")).toString();
        const QString kind = tran == QLatin1String("usb") ? QStringLiteral("usb")
                           : (d.value(QStringLiteral("rota")).toBool() ? QStringLiteral("hdd") : QStringLiteral("ssd"));
        QString model = d.value(QStringLiteral("model")).toString().trimmed();
        if (model.isEmpty())
            model = kind == QLatin1String("usb") ? QStringLiteral("Dysk USB") : QStringLiteral("Dysk");
        found << QVariantMap{{QStringLiteral("path"), path}, {QStringLiteral("name"), model},
                             {QStringLiteral("sizeText"), sizeText(size)}, {QStringLiteral("size"), size},
                             {QStringLiteral("kind"), kind}, {QStringLiteral("windows"), windows},
                             {QStringLiteral("partitions"), parts.size()}};
    }
    m_disks = found;
    Q_EMIT disksChanged();
}

// ——— Sieć (nmcli) ———

void Installer::checkWired()
{
    if (m_preview) {
        m_wired = false;
        return;
    }
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p] {
        bool wired = false;
        for (const QByteArray &line : p->readAllStandardOutput().split('\n')) {
            const QList<QByteArray> f = line.split(':');
            wired |= f.size() >= 2 && f.at(0) == "ethernet" && f.at(1) == "connected";
        }
        p->deleteLater();
        if (wired != m_wired) {
            m_wired = wired;
            Q_EMIT networksChanged();
        }
    });
    p->start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE"), QStringLiteral("device")});
}

void Installer::scanWifi()
{
    if (m_preview) {
        auto net = [](const char *s, int sig, bool sec, bool act) {
            return QVariantMap{{QStringLiteral("ssid"), QString::fromUtf8(s)}, {QStringLiteral("signal"), sig},
                               {QStringLiteral("secure"), sec}, {QStringLiteral("active"), act}};
        };
        m_networks = {net("Dom_5G", 92, true, false), net("Dom", 78, true, false), net("UPC Wi-Free", 54, false, false),
                      net("Orange_Swiatlowod_A1B2", 41, true, false), net("Sąsiad", 22, true, false)};
        Q_EMIT networksChanged();
        return;
    }
    if (m_scanning)
        return;
    m_scanning = true;
    Q_EMIT networksChanged();
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p] {
        readNetworks(p->readAllStandardOutput());
        p->deleteLater();
        m_scanning = false;
        Q_EMIT networksChanged();
        checkWired();
    });
    p->start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                                      QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"), QStringLiteral("--rescan"), QStringLiteral("yes")});
}

void Installer::readNetworks(const QByteArray &out)
{
    QHash<QString, QVariantMap> best;       // ta sama sieć z kilku punktów dostępu — najsilniejszy
    m_activeSsid.clear();
    for (const QByteArray &raw : out.split('\n')) {
        // Pola rozdziela „:”, a dwukropek w nazwie sieci nmcli zapisuje jako „\:”
        QStringList f;
        QString cur;
        const QString line = QString::fromUtf8(raw);
        for (int i = 0; i < line.size(); ++i) {
            if (line.at(i) == QLatin1Char('\\') && i + 1 < line.size()) { cur += line.at(++i); continue; }
            if (line.at(i) == QLatin1Char(':')) { f << cur; cur.clear(); continue; }
            cur += line.at(i);
        }
        f << cur;
        if (f.size() < 4 || f.at(1).isEmpty())
            continue;
        const bool active = f.at(0) == QLatin1String("*");
        if (active)
            m_activeSsid = f.at(1);
        const int signal = f.at(2).toInt();
        if (best.contains(f.at(1)) && best.value(f.at(1)).value(QStringLiteral("signal")).toInt() >= signal && !active)
            continue;
        best.insert(f.at(1), QVariantMap{{QStringLiteral("ssid"), f.at(1)}, {QStringLiteral("signal"), signal},
                                         {QStringLiteral("secure"), !f.at(3).isEmpty() && f.at(3) != QLatin1String("--")},
                                         {QStringLiteral("active"), active}});
    }
    QList<QVariantMap> list = best.values();
    std::sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        if (a.value(QStringLiteral("active")).toBool() != b.value(QStringLiteral("active")).toBool())
            return a.value(QStringLiteral("active")).toBool();
        return a.value(QStringLiteral("signal")).toInt() > b.value(QStringLiteral("signal")).toInt();
    });
    m_networks.clear();
    for (const QVariantMap &m : list)
        m_networks << m;
}

void Installer::connectWifi(const QString &ssid, const QString &password)
{
    if (m_preview) {
        QTimer::singleShot(900, this, [this, ssid] {
            for (QVariant &v : m_networks) {
                QVariantMap m = v.toMap();
                m[QStringLiteral("active")] = m.value(QStringLiteral("ssid")).toString() == ssid;
                v = m;
            }
            m_activeSsid = ssid;
            Q_EMIT networksChanged();
            Q_EMIT wifiResult(true, QString());
        });
        return;
    }
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this, [this, p](int code) {
        const QString out = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        const bool wrongPassword = out.contains(QLatin1String("Secrets were required")) || out.contains(QLatin1String("802-11-wireless-security.psk"));
        Q_EMIT wifiResult(code == 0, code == 0 ? QString()
                                               : wrongPassword ? QStringLiteral("Nieprawidłowe hasło")
                                                               : QStringLiteral("Nie udało się połączyć"));
        scanWifi();
    });
    QStringList args = {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid};
    if (!password.isEmpty())
        args << QStringLiteral("password") << password;
    p->start(QStringLiteral("nmcli"), args);
}

// Układ klawiatury od razu w sesji instalatora (hasło wpisuje się już w wybranym układzie)
void Installer::setKeyboard(const QString &layout, const QString &variant)
{
    if (m_preview)
        return;
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    QDir().mkpath(dir);
    QFile f(dir + QStringLiteral("/kxkbrc"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QStringLiteral("[Layout]\nLayoutList=%1\nVariantList=%2\nUse=true\nResetOldOptions=true\n").arg(layout, variant).toUtf8());
    f.close();
    QProcess::startDetached(QStringLiteral("dbus-send"), {QStringLiteral("--session"), QStringLiteral("--type=signal"),
                                                          QStringLiteral("/Layouts"), QStringLiteral("org.kde.keyboard.reloadConfig")});
}

// „Jan Kowalski” → „jan”; bez ogonków, małe litery, cyfry dozwolone
QString Installer::usernameFor(const QString &fullName) const
{
    QString first = fullName.trimmed().section(QLatin1Char(' '), 0, 0).toLower();
    first.replace(QStringLiteral("ł"), QStringLiteral("l"));
    first = first.normalized(QString::NormalizationForm_D);
    QString out;
    for (const QChar c : std::as_const(first))
        if ((c >= QLatin1Char('a') && c <= QLatin1Char('z')) || (c.isDigit() && !out.isEmpty()))
            out += c;
    return out.left(24);
}

QString Installer::hostnameFor(const QString &username) const
{
    return username.isEmpty() ? QStringLiteral("aster") : QStringLiteral("aster-") + username;
}

// ——— Instalacja ———

void Installer::install(const QVariantMap &s)
{
    if (m_state == QLatin1String("installing"))
        return;
    m_state = QStringLiteral("installing");
    m_error.clear();
    m_log.clear();
    m_progress = 0;
    m_stage = QStringLiteral("Przygotowanie…");
    Q_EMIT stateChanged();
    Q_EMIT progressChanged();
    Q_EMIT logChanged();

    if (m_preview || qEnvironmentVariableIsSet("ASTER_INSTALL_DRYRUN")) {
        m_fake.start();
        return;
    }

    const QString hash = hashPassword(s.value(QStringLiteral("password")).toString());
    if (hash.isEmpty()) {
        m_error = QStringLiteral("Nie udało się zabezpieczyć hasła.");
        finish(false);
        return;
    }
    // Ustawienia dla skryptu (czytane przez sh); tylko dla właściciela — jest w nich skrót hasła
    const QString env = QStringLiteral("/tmp/aster-install.env");
    QFile f(env);
    f.remove();
    if (!f.open(QIODevice::WriteOnly) || !f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        m_error = QStringLiteral("Nie udało się zapisać ustawień instalacji.");
        finish(false);
        return;
    }
    auto put = [&f](const char *key, const QString &value) {
        f.write(QByteArray(key) + '=' + shQuote(value).toUtf8() + '\n');
    };
    put("DISK", s.value(QStringLiteral("disk")).toString());
    put("LOCALE", s.value(QStringLiteral("locale")).toString());
    put("XKB_LAYOUT", s.value(QStringLiteral("layout")).toString());
    put("XKB_VARIANT", s.value(QStringLiteral("variant")).toString());
    put("KEYMAP", s.value(QStringLiteral("keymap")).toString());
    put("TIMEZONE", s.value(QStringLiteral("timezone")).toString());
    put("HOSTNAME", s.value(QStringLiteral("hostname")).toString());
    put("USERNAME", s.value(QStringLiteral("username")).toString());
    put("FULLNAME", s.value(QStringLiteral("fullName")).toString());
    put("PASSWORD_HASH", hash);
    put("AUTOLOGIN", s.value(QStringLiteral("autologin")).toBool() ? QStringLiteral("1") : QStringLiteral("0"));
    put("DARK", s.value(QStringLiteral("dark")).toBool() ? QStringLiteral("1") : QStringLiteral("0"));
    put("ACCENT", s.value(QStringLiteral("accent")).toString());
    put("WALLPAPER", s.value(QStringLiteral("wallpaper")).toString());
    put("AUTO_UPDATES", s.value(QStringLiteral("autoUpdates")).toBool() ? QStringLiteral("1") : QStringLiteral("0"));
    f.close();

    m_cap = 0;
    m_creep.start();
    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_proc, &QProcess::readyRead, this, [this] {
        while (m_proc->canReadLine())
            handleLine(QString::fromUtf8(m_proc->readLine()).trimmed());
    });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        handleLine(QString::fromUtf8(m_proc->readAll()).trimmed());
        QFile::remove(QStringLiteral("/tmp/aster-install.env"));
        finish(status == QProcess::NormalExit && code == 0);
    });
    const QString script = QStringLiteral("/usr/libexec/aster-install");
    if (geteuid() == 0)
        m_proc->start(script, {env});
    else
        m_proc->start(QStringLiteral("sudo"), {QStringLiteral("-n"), script, env});
}

// Skrypt pisze „@progress 0.42”, „@stage Tekst” i „@error Tekst”; reszta trafia do szczegółów
void Installer::handleLine(const QString &text)
{
    // Paski postępu nadpisują wiersz znakiem \r — liczy się tylko ostatnia wersja wiersza
    for (QString line : text.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        if (line.contains(QLatin1Char('\r')))
            line = line.section(QLatin1Char('\r'), -1).trimmed();
        if (line.isEmpty())
            continue;
        if (line.startsWith(QLatin1String("@progress "))) {
            const QStringList v = line.mid(10).split(QLatin1Char(' '), Qt::SkipEmptyParts);
            const qreal now = qBound(0.0, v.value(0).toDouble(), 1.0);
            m_progress = qMax(m_progress, now);
            m_cap = v.size() > 1 ? qBound(now, v.at(1).toDouble(), 1.0) : now;
            Q_EMIT progressChanged();
        } else if (line.startsWith(QLatin1String("@stage "))) {
            m_stage = line.mid(7);
            Q_EMIT progressChanged();
        } else if (line.startsWith(QLatin1String("@error "))) {
            m_error = line.mid(7);
        } else {
            // Log bootc ma tysiące wierszy — trzymamy koniec i powiadamiamy co 0,5 s, nie po każdym wierszu
            // (inaczej przeliczanie tekstu w oknie zajmuje program na długie minuty)
            m_log += line + QLatin1Char('\n');
            if (m_log.size() > 60000)
                m_log = m_log.right(40000);
            if (!m_logTimer.isActive())
                m_logTimer.start();
        }
    }
}

void Installer::finish(bool ok)
{
    m_fake.stop();
    m_creep.stop();
    if (ok) {
        m_progress = 1;
        m_stage = QStringLiteral("Gotowe");
        Q_EMIT progressChanged();
    } else if (m_error.isEmpty()) {
        m_error = QStringLiteral("Instalacja została przerwana.");
    }
    m_state = ok ? QStringLiteral("done") : QStringLiteral("failed");
    Q_EMIT stateChanged();
    if (m_proc) {
        m_proc->deleteLater();
        m_proc = nullptr;
    }
}

// Podgląd: udawana instalacja z prawdziwymi etapami
void Installer::simulate()
{
    static const char *stages[] = {"Przygotowanie dysku…", "Kopiowanie systemu…", "Kopiowanie systemu…", "Kopiowanie systemu…",
                                   "Instalowanie programu rozruchowego…", "Zapisywanie Twoich ustawień…"};
    m_progress = qMin(1.0, m_progress + 0.006);
    m_stage = QString::fromUtf8(stages[qMin(5, int(m_progress * 6))]);
    m_log += QStringLiteral("[podgląd] %1%\n").arg(qRound(m_progress * 100));
    Q_EMIT progressChanged();
    Q_EMIT logChanged();
    if (m_progress >= 1)
        finish(true);
}

void Installer::reset()
{
    if (m_state == QLatin1String("installing"))
        return;
    m_state = QStringLiteral("idle");
    m_progress = 0;
    m_error.clear();
    Q_EMIT stateChanged();
    Q_EMIT progressChanged();
    refreshDisks();
}

void Installer::reboot()
{
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

void Installer::powerOff()
{
    if (!m_preview)
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
}

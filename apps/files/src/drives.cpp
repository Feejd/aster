#include "drives.h"
#include "fileops.h"

#include <Solid/Block>
#include <Solid/Device>
#include <Solid/DeviceNotifier>
#include <Solid/OpticalDrive>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <Solid/StorageVolume>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDir>
#include <QStorageInfo>
#include <QUrl>

static const QString udisks = QStringLiteral("org.freedesktop.UDisks2");

Drives::Drives(QObject *parent)
    : QObject(parent)
    , m_preview(qEnvironmentVariableIsSet("ASTER_PREVIEW"))
{
    auto *n = Solid::DeviceNotifier::instance();
    connect(n, &Solid::DeviceNotifier::deviceAdded, this, &Drives::rebuild);
    connect(n, &Solid::DeviceNotifier::deviceRemoved, this, &Drives::rebuild);
    rebuild();
}

static bool systemMount(const QString &path)
{
    static const QStringList sys{QStringLiteral("/"), QStringLiteral("/boot"), QStringLiteral("/boot/efi"), QStringLiteral("/home"),
                                 QStringLiteral("/var"), QStringLiteral("/usr"), QStringLiteral("/efi"), QStringLiteral("/sysroot")};
    return sys.contains(path) || path.startsWith(QLatin1String("/var/")) || path.startsWith(QLatin1String("/usr/"));
}

void Drives::rebuild()
{
    QVariantList out;
    if (m_preview) {
        // Przykładowy pendrive do zrzutów w kontenerze
        const QString udi = QStringLiteral("preview-usb");
        out << QVariantMap{{QStringLiteral("udi"), udi}, {QStringLiteral("name"), QStringLiteral("KINGSTON")},
                           {QStringLiteral("sizeText"), QStringLiteral("16 GB")}, {QStringLiteral("url"), QUrl::fromLocalFile(QDir::homePath()).toString()},
                           {QStringLiteral("mounted"), true}, {QStringLiteral("removable"), true},
                           {QStringLiteral("freeText"), QStringLiteral("11,2 GB wolne z 16 GB")}, {QStringLiteral("usedRatio"), 0.3},
                           {QStringLiteral("fsName"), QStringLiteral("exFAT")}, {QStringLiteral("busy"), m_busy.value(udi)}};
        m_list = out;
        Q_EMIT changed();
        return;
    }
    const auto devices = Solid::Device::listFromType(Solid::DeviceInterface::StorageAccess);
    for (const Solid::Device &d : devices) {
        const auto *access = d.as<Solid::StorageAccess>();
        const auto *volume = d.as<Solid::StorageVolume>();
        if (!access || !volume || volume->isIgnored() || volume->usage() != Solid::StorageVolume::FileSystem)
            continue;
        const QString path = access->isAccessible() ? access->filePath() : QString();
        if (!path.isEmpty() && systemMount(path))
            continue;
        // Dysk fizyczny (rodzic partycji): wymienny / podłączany na gorąco
        bool removable = false;
        QString vendor;
        for (Solid::Device p = d; p.isValid(); p = p.parent()) {
            if (const auto *drive = p.as<Solid::StorageDrive>()) {
                removable = drive->isRemovable() || drive->isHotpluggable();
                vendor = p.vendor().trimmed() + QLatin1Char(' ') + p.product().trimmed();
                break;
            }
        }
        const bool mountedElsewhere = !path.isEmpty() && (path.startsWith(QLatin1String("/run/media/")) || path.startsWith(QLatin1String("/media/"))
                                                          || path.startsWith(QLatin1String("/mnt/")));
        if (!removable && !mountedElsewhere)
            continue;                                   // partycje systemu i nieużywane dyski wewnętrzne
        const QString size = Files::formatSize(volume->size());
        QString name = volume->label().trimmed();
        if (name.isEmpty())
            name = removable ? QStringLiteral("Dysk USB") : (vendor.trimmed().isEmpty() ? QStringLiteral("Dysk") : vendor.trimmed());
        QVariantMap m{{QStringLiteral("udi"), d.udi()}, {QStringLiteral("name"), name}, {QStringLiteral("sizeText"), size},
                      {QStringLiteral("url"), path.isEmpty() ? QString() : QUrl::fromLocalFile(path).toString()},
                      {QStringLiteral("mounted"), !path.isEmpty()}, {QStringLiteral("removable"), removable},
                      {QStringLiteral("fsName"), volume->fsType()}, {QStringLiteral("busy"), m_busy.value(d.udi())}};
        if (!path.isEmpty()) {
            const QStorageInfo si(path);
            const qint64 total = si.bytesTotal(), free = si.bytesAvailable();
            m.insert(QStringLiteral("freeText"), Files::formatSize(free) + QStringLiteral(" wolne z ") + Files::formatSize(total));
            m.insert(QStringLiteral("usedRatio"), total > 0 ? double(total - free) / double(total) : 0.0);
        }
        out << m;
        // Zmiany stanu (zamontowano / odmontowano) — odśwież listę
        connect(access, &Solid::StorageAccess::accessibilityChanged, this, &Drives::rebuild, Qt::UniqueConnection);
    }
    m_list = out;
    Q_EMIT changed();
}

void Drives::setBusy(const QString &udi, const QString &what)
{
    if (what.isEmpty())
        m_busy.remove(udi);
    else
        m_busy.insert(udi, what);
    rebuild();
}

QString Drives::nameOf(const QString &udi) const
{
    for (const QVariant &v : m_list)
        if (v.toMap().value(QStringLiteral("udi")).toString() == udi)
            return v.toMap().value(QStringLiteral("name")).toString();
    return QStringLiteral("Dysk");
}

void Drives::open(const QString &udi)
{
    if (m_preview) {
        Q_EMIT opened(QUrl::fromLocalFile(QDir::homePath()).toString());
        return;
    }
    Solid::Device d(udi);
    auto *access = d.as<Solid::StorageAccess>();
    if (!access)
        return;
    if (access->isAccessible()) {
        Q_EMIT opened(QUrl::fromLocalFile(access->filePath()).toString());
        return;
    }
    connect(access, &Solid::StorageAccess::setupDone, this, [this, udi](Solid::ErrorType error, const QVariant &, const QString &) {
        Solid::Device dev(udi);
        auto *a = dev.as<Solid::StorageAccess>();
        if (error == Solid::NoError && a && a->isAccessible())
            Q_EMIT opened(QUrl::fromLocalFile(a->filePath()).toString());
        else if (error != Solid::UserCanceled)
            Q_EMIT message(QStringLiteral("Nie udało się otworzyć „%1”").arg(nameOf(udi)));
        rebuild();
    }, Qt::SingleShotConnection);
    access->setup();
}

void Drives::eject(const QString &udi)
{
    if (m_preview)
        return;
    Solid::Device d(udi);
    auto *access = d.as<Solid::StorageAccess>();
    if (!access)
        return;
    const QString name = nameOf(udi);
    const QString url = access->isAccessible() ? QUrl::fromLocalFile(access->filePath()).toString() : QString();
    if (!url.isEmpty())
        Q_EMIT ejected(url);
    setBusy(udi, QStringLiteral("Wysuwanie…"));
    // Po odmontowaniu: wyłącz zasilanie dysku (UDisks2 Drive.PowerOff), jak „Bezpieczne usuwanie” w Windows
    auto powerOff = [this, udi, name] {
        QDBusMessage get = QDBusMessage::createMethodCall(udisks, udi, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        get << QStringLiteral("org.freedesktop.UDisks2.Block") << QStringLiteral("Drive");
        const QDBusMessage r = QDBusConnection::systemBus().call(get, QDBus::Block, 3000);
        if (r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()) {
            const QString drive = r.arguments().first().value<QDBusVariant>().variant().value<QDBusObjectPath>().path();
            if (drive.length() > 1) {
                QDBusMessage off = QDBusMessage::createMethodCall(udisks, drive, QStringLiteral("org.freedesktop.UDisks2.Drive"), QStringLiteral("PowerOff"));
                off << QVariantMap();
                QDBusConnection::systemBus().asyncCall(off);
            }
        }
        setBusy(udi, {});
        Q_EMIT message(QStringLiteral("Można bezpiecznie odłączyć „%1”").arg(name));
    };
    if (!access->isAccessible()) {
        powerOff();
        return;
    }
    connect(access, &Solid::StorageAccess::teardownDone, this, [this, udi, name, powerOff](Solid::ErrorType error, const QVariant &, const QString &) {
        if (error == Solid::NoError) {
            powerOff();
            return;
        }
        setBusy(udi, {});
        if (error != Solid::UserCanceled)
            Q_EMIT message(QStringLiteral("„%1” jest w użyciu — zamknij otwarte z niego pliki i spróbuj ponownie").arg(name));
    }, Qt::SingleShotConnection);
    access->teardown();
}

int Drives::labelLimit(const QString &type) const
{
    if (type == QLatin1String("vfat"))
        return 11;
    if (type == QLatin1String("exfat"))
        return 15;
    if (type == QLatin1String("ext4"))
        return 16;
    return 32;
}

void Drives::format(const QString &udi, const QString &type, const QString &label)
{
    const QString name = nameOf(udi);
    if (m_preview) {
        Q_EMIT message(QStringLiteral("Sformatowano „%1”").arg(label.isEmpty() ? name : label));
        return;
    }
    QString l = label.trimmed().left(labelLimit(type));
    if (type == QLatin1String("vfat"))
        l = l.toUpper();
    QVariantMap options{{QStringLiteral("tear-down"), true}, {QStringLiteral("update-partition-type"), true}};
    if (!l.isEmpty())
        options.insert(QStringLiteral("label"), l);
    QDBusMessage m = QDBusMessage::createMethodCall(udisks, udi, QStringLiteral("org.freedesktop.UDisks2.Block"), QStringLiteral("Format"));
    m << type << options;
    m.setInteractiveAuthorizationAllowed(true);           // hasło administratora, gdy system o nie poprosi
    setBusy(udi, QStringLiteral("Formatowanie…"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m, 30 * 60 * 1000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, udi, name, l] {
        w->deleteLater();
        const QDBusPendingReply<> r = *w;
        setBusy(udi, {});
        if (r.isError()) {
            const QString err = r.error().name();
            if (err.contains(QLatin1String("NotAuthorized")) || err.contains(QLatin1String("Cancelled")))
                Q_EMIT message(QStringLiteral("Anulowano formatowanie"));
            else if (err.contains(QLatin1String("DeviceBusy")))
                Q_EMIT message(QStringLiteral("„%1” jest w użyciu — zamknij otwarte z niego pliki").arg(name));
            else
                Q_EMIT message(QStringLiteral("Nie udało się sformatować: %1").arg(r.error().message()));
            return;
        }
        Q_EMIT message(QStringLiteral("Sformatowano „%1”").arg(l.isEmpty() ? name : l));
        open(udi);                                         // od razu gotowy do użycia
    });
}

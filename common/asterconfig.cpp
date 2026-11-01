#include "asterconfig.h"

#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>

AsterConfig::AsterConfig(QObject *parent)
    : QObject(parent)
{
    QDir().mkpath(QFileInfo(path()).absolutePath());
    load();
    // Plik zapisywany jest przez podmianę, więc obserwujemy też katalog
    m_watcher.addPath(QFileInfo(path()).absolutePath());
    if (QFileInfo::exists(path()))
        m_watcher.addPath(path());
    auto reload = [this] {
        if (QFileInfo::exists(path()) && !m_watcher.files().contains(path()))
            m_watcher.addPath(path());
        const QVariantMap before = m_values;
        load();
        if (before != m_values)
            Q_EMIT changed();
    };
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, reload);
}

QString AsterConfig::path() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster/aster.conf");
}

QString AsterConfig::dataDir() const
{
    const QByteArray env = qgetenv("ASTER_DATA_DIR");
    if (!env.isEmpty())
        return QString::fromLocal8Bit(env);
    const QString found = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("aster"), QStandardPaths::LocateDirectory);
    return found.isEmpty() ? QStringLiteral("/usr/share/aster") : found;
}

void AsterConfig::load()
{
    QSettings s(path(), QSettings::IniFormat);
    m_values.clear();
    for (const QString &key : s.allKeys())
        m_values.insert(key, s.value(key));
}

void AsterConfig::write(const QString &key, const QVariant &value)
{
    if (m_values.value(key) == value)
        return;
    m_values.insert(key, value);
    {
        QSettings s(path(), QSettings::IniFormat);
        s.setValue(key, value);
    }
    Q_EMIT changed();
}

QVariantList AsterConfig::notifyApps() const
{
    // Zapis „id|nazwa|ikona” — prosto i czytelnie w pliku INI
    QVariantList out;
    for (const QString &entry : m_values.value(QStringLiteral("notifications/apps")).toStringList()) {
        const QStringList f = entry.split(QLatin1Char('|'));
        out << QVariantMap{{QStringLiteral("id"), f.value(0)}, {QStringLiteral("name"), f.value(1, f.value(0))}, {QStringLiteral("icon"), f.value(2)}};
    }
    return out;
}

void AsterConfig::setAppMuted(const QString &id, bool muted)
{
    QStringList list = mutedApps();
    list.removeAll(id);
    if (muted)
        list << id;
    setMutedApps(list);
}

bool AsterConfig::notificationAllowed(const QString &id, const QString &name, const QString &icon)
{
    if (id.isEmpty())
        return true;
    const QString file = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster/aster.conf");
    QSettings s(file, QSettings::IniFormat);
    QStringList apps = s.value(QStringLiteral("notifications/apps")).toStringList();
    bool known = false;
    for (const QString &a : std::as_const(apps))
        known |= a.section(QLatin1Char('|'), 0, 0) == id;
    if (!known) {
        QString clean = name;
        clean.remove(QLatin1Char('|'));
        apps << id + QLatin1Char('|') + (clean.isEmpty() ? id : clean) + QLatin1Char('|') + QString(icon).remove(QLatin1Char('|'));
        s.setValue(QStringLiteral("notifications/apps"), apps);
    }
    return !s.value(QStringLiteral("notifications/muted")).toStringList().contains(id);
}

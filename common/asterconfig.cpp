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

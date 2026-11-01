#include "conf.h"

#include "util.h"

#include <KConfigGroup>
#include <KSharedConfig>

Conf::Conf(QObject *parent)
    : QObject(parent)
{
}

static KConfigGroup groupOf(const KSharedConfig::Ptr &config, const QStringList &groups)
{
    KConfigGroup g = config->group(groups.value(0));
    for (int i = 1; i < groups.size(); ++i)
        g = g.group(groups.at(i));
    return g;
}

QVariant Conf::read(const QString &file, const QStringList &groups, const QString &key, const QVariant &fallback) const
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(file, KConfig::NoGlobals);
    config->reparseConfiguration();
    const KConfigGroup g = groupOf(config, groups);
    if (!g.hasKey(key))
        return fallback;
    if (!fallback.isValid())
        return g.readEntry(key, QString());
    return g.readEntry(key, fallback);
}

void Conf::write(const QString &file, const QStringList &groups, const QString &key, const QVariant &value)
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(file, KConfig::NoGlobals);
    KConfigGroup g = groupOf(config, groups);
    g.writeEntry(key, value, KConfig::Notify);
    config->sync();
    m_revision++;
    Q_EMIT changed();
}

void Conf::remove(const QString &file, const QStringList &groups, const QString &key)
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(file, KConfig::NoGlobals);
    KConfigGroup g = groupOf(config, groups);
    g.deleteEntry(key, KConfig::Notify);
    config->sync();
    m_revision++;
    Q_EMIT changed();
}

void Conf::reloadKWin()
{
    if (!asterPreview())
        QDBusConnection::sessionBus().send(dbusMethod(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure")));
}

void Conf::reloadKeyboard()
{
    if (asterPreview())
        return;
    QDBusConnection::sessionBus().send(QDBusMessage::createSignal(QStringLiteral("/Layouts"), QStringLiteral("org.kde.keyboard"), QStringLiteral("reloadConfig")));
    reloadKWin();
}

void Conf::reloadPower()
{
    if (asterPreview())
        return;
    const QString s = QStringLiteral("org.kde.Solid.PowerManagement");
    QDBusConnection::sessionBus().send(dbusMethod(s, QStringLiteral("/org/kde/Solid/PowerManagement"), s, QStringLiteral("reparseConfiguration")));
    QDBusConnection::sessionBus().send(dbusMethod(s, QStringLiteral("/org/kde/Solid/PowerManagement"), s, QStringLiteral("refreshStatus")));
}

void Conf::notifyGlobals(int what)
{
    if (asterPreview())
        return;
    QDBusMessage m = QDBusMessage::createSignal(QStringLiteral("/KGlobalSettings"), QStringLiteral("org.kde.KGlobalSettings"), QStringLiteral("notifyChange"));
    m << what << 0;
    QDBusConnection::sessionBus().send(m);
}

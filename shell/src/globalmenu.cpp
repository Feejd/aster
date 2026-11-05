#include "globalmenu.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QJsonDocument>

static const QString menuPath = QStringLiteral("/org/aster/AppMenu");
static const QString menuIface = QStringLiteral("org.aster.AppMenu");

GlobalMenu::GlobalMenu(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/aster/Shell/Menu"), this, QDBusConnection::ExportScriptableSlots);
}

void GlobalMenu::RegisterMenu(const QString &appId)
{
    const QString service = message().service();
    m_services.insert(appId, service);
    QDBusConnection::sessionBus().connect(service, menuPath, menuIface, QStringLiteral("Changed"), this, SLOT(onChanged()));
    auto *watcher = new QDBusServiceWatcher(service, QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForUnregistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this, appId, service, watcher] {
        watcher->deleteLater();
        if (m_services.value(appId) == service)
            m_services.remove(appId);
        refresh();
    });
    refresh();
}

void GlobalMenu::onChanged()
{
    refresh();
}

void GlobalMenu::setAppId(const QString &appId)
{
    if (m_appId == appId)
        return;
    m_appId = appId;
    refresh();
}

void GlobalMenu::refresh()
{
    const QString service = m_services.value(m_appId);
    if (service.isEmpty()) {
        if (!m_menus.isEmpty()) {
            m_menus.clear();
            Q_EMIT changed();
        }
        Q_EMIT changed();
        return;
    }
    const QString appId = m_appId;
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(service, menuPath, menuIface, QStringLiteral("Menus")), 1500), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, appId] {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError() || appId != m_appId)
            return;
        m_menus = QJsonDocument::fromJson(reply.value().toUtf8()).toVariant().toList();
        Q_EMIT changed();
    });
}

void GlobalMenu::trigger(int id)
{
    const QString service = m_services.value(m_appId);
    if (service.isEmpty())
        return;
    QDBusMessage m = QDBusMessage::createMethodCall(service, menuPath, menuIface, QStringLiteral("Trigger"));
    m << id;
    QDBusConnection::sessionBus().asyncCall(m);
}

#include "appmenu.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusServiceWatcher>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

static const QString shellService = QStringLiteral("org.aster.Shell");

AppMenu::AppMenu(QObject *parent)
    : QObject(parent)
{
    // Po restarcie powłoki trzeba zgłosić się od nowa
    auto *watcher = new QDBusServiceWatcher(shellService, QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForRegistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, &AppMenu::announce);
}

void AppMenu::announce()
{
    if (!m_exported)
        return;
    QDBusMessage m = QDBusMessage::createMethodCall(shellService, QStringLiteral("/org/aster/Shell/Menu"), QStringLiteral("org.aster.Menu"), QStringLiteral("RegisterMenu"));
    m << QGuiApplication::desktopFileName();
    QDBusConnection::sessionBus().asyncCall(m);
}

void AppMenu::setMenus(const QJSValue &menus)
{
    m_menus = menus;
    Q_EMIT menusChanged();
    if (!m_exported) {
        m_exported = QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/aster/AppMenu"), this, QDBusConnection::ExportScriptableContents);
        announce();
    }
    Q_EMIT Changed();
}

// Wartość pola: zwykła albo wyliczana teraz przez funkcję
static bool flag(const QJSValue &item, const char *name, bool fallback)
{
    QJSValue v = item.property(QLatin1String(name));
    if (v.isCallable())
        v = v.call();
    return v.isUndefined() ? fallback : v.toBool();
}

QString AppMenu::Menus()
{
    m_actions.clear();
    QJsonArray menus;
    const int count = m_menus.property(QStringLiteral("length")).toInt();
    for (int i = 0; i < count; ++i) {
        const QJSValue menu = m_menus.property(i);
        const QJSValue items = menu.property(QStringLiteral("items"));
        const int itemCount = items.property(QStringLiteral("length")).toInt();
        QJsonArray list;
        for (int j = 0; j < itemCount; ++j) {
            const QJSValue item = items.property(j);
            if (flag(item, "separator", false)) {
                list.append(QJsonObject{{QStringLiteral("separator"), true}});
                continue;
            }
            QJsonObject row{{QStringLiteral("text"), item.property(QStringLiteral("text")).toString()},
                            {QStringLiteral("enabled"), flag(item, "enabled", true)},
                            {QStringLiteral("id"), int(m_actions.size())}};
            const QJSValue key = item.property(QStringLiteral("key"));
            if (key.isString())
                row.insert(QStringLiteral("key"), key.toString());
            if (!item.property(QStringLiteral("checked")).isUndefined())
                row.insert(QStringLiteral("checked"), flag(item, "checked", false));
            m_actions.append(item.property(QStringLiteral("run")));
            list.append(row);
        }
        menus.append(QJsonObject{{QStringLiteral("title"), menu.property(QStringLiteral("title")).toString()}, {QStringLiteral("items"), list}});
    }
    return QString::fromUtf8(QJsonDocument(menus).toJson(QJsonDocument::Compact));
}

void AppMenu::Trigger(int id)
{
    if (id < 0 || id >= m_actions.size())
        return;
    QJSValue run = m_actions.at(id);
    if (run.isCallable())
        run.call();
}

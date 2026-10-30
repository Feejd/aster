#include "runtime.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QFile>
#include <QLocalSocket>

#include <unistd.h>

static const QString nService = QStringLiteral("org.freedesktop.Notifications");
static const QString nPath = QStringLiteral("/org/freedesktop/Notifications");

Runtime::Runtime(const QString &id, QObject *parent)
    : QObject(parent)
    , m_id(id)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(nService, nPath, nService, QStringLiteral("ActionInvoked"), this, SLOT(onActionInvoked(uint, QString)));
    bus.connect(nService, nPath, nService, QStringLiteral("NotificationClosed"), this, SLOT(onNotificationClosed(uint, uint)));
}

static QString serverName(const QString &id)
{
    return QStringLiteral("aster-webapp-%1-%2").arg(id).arg(getuid());
}

bool Runtime::forwardToRunning()
{
    QLocalSocket socket;
    socket.connectToServer(serverName(m_id));
    if (socket.waitForConnected(300)) {
        socket.write("show");
        socket.waitForBytesWritten(300);
        return true;
    }
    QLocalServer::removeServer(serverName(m_id));
    m_server.listen(serverName(m_id));
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *s = m_server.nextPendingConnection()) {
            s->deleteLater();
            Q_EMIT activateRequested();
        }
    });
    return false;
}

uint Runtime::notify(const QString &title, const QString &body, const QString &iconPath)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(nService, nPath, nService, QStringLiteral("Notify"));
    const QString entry = QStringLiteral("aster-webapp-") + m_id;
    msg << QString() << uint(0) << iconPath << title << body << QStringList{QStringLiteral("default"), QStringLiteral("Otwórz")}
        << QVariantMap{{QStringLiteral("desktop-entry"), entry}, {QStringLiteral("image-path"), iconPath}} << int(-1);
    const QDBusReply<uint> reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 2000);
    if (!reply.isValid())
        return 0;
    m_ours.insert(reply.value(), true);
    return reply.value();
}

void Runtime::closeNotification(uint id)
{
    if (!m_ours.contains(id))
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(nService, nPath, nService, QStringLiteral("CloseNotification"));
    msg << id;
    QDBusConnection::sessionBus().asyncCall(msg);
}

void Runtime::onActionInvoked(uint id, const QString &action)
{
    if (m_ours.contains(id) && action == QLatin1String("default"))
        Q_EMIT notificationClicked(id);
}

void Runtime::onNotificationClosed(uint id, uint)
{
    if (m_ours.remove(id))
        Q_EMIT notificationClosed(id);
}

void Runtime::setBadge(int count)
{
    if (count == m_badge)
        return;
    m_badge = count;
    QString path = QStringLiteral("/org/aster/webapp/") + m_id;
    path.replace(QLatin1Char('-'), QLatin1Char('_'));
    QDBusMessage signal = QDBusMessage::createSignal(path, QStringLiteral("com.canonical.Unity.LauncherEntry"), QStringLiteral("Update"));
    signal << QStringLiteral("application://aster-webapp-%1.desktop").arg(m_id)
           << QVariantMap{{QStringLiteral("count"), qint64(qMax(0, count))}, {QStringLiteral("count-visible"), count > 0}};
    QDBusConnection::sessionBus().send(signal);
}

QString Runtime::resource(const QString &name) const
{
    QFile f(QStringLiteral(":/qt/qml/Aster/WebApps/") + name);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

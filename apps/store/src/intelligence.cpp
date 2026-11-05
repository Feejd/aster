#include "intelligence.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QVariantMap>

static const QString kService = QStringLiteral("org.aster.Assistant");
static const QString kPath = QStringLiteral("/org/aster/Assistant");
static const QString kIface = QStringLiteral("org.aster.Assistant");

Intelligence::Intelligence(QObject *parent)
    : QObject(parent)
{
    auto bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kIface, QStringLiteral("Finished"), this, SLOT(onFinished(QString, QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("Failed"), this, SLOT(onFailed(QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("ActionRequested"), this, SLOT(onAction(QString, QString, QString, QString, bool)));
    checkStatus();
}

void Intelligence::checkStatus()
{
    auto *iface = QDBusConnection::sessionBus().interface();
    if (!iface)
        return;
    const QStringList activatable = iface->activatableServiceNames().value();
    if (!iface->isServiceRegistered(kService).value() && !activatable.contains(kService))
        return;
    auto msg = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("Status"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 8000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isError())
            return;
        const QVariantMap status = reply.value();
        m_available = status.value(QStringLiteral("ready")).toBool();
        m_badge = status.value(QStringLiteral("badge")).toString();
        Q_EMIT availableChanged();
    });
}

void Intelligence::ask(const QString &question, const QString &prompt, const QString &catalog)
{
    if (!m_available)
        return;
    cancel();
    m_question = question;
    m_starting = true;
    Q_EMIT busyChanged();
    // Źródło „pisanie”: sama odpowiedź tekstem, bez proponowania poleceń
    auto msg = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("Ask"));
    msg.setArguments({QString(), prompt, catalog, QStringLiteral("pisanie")});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 8000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, question](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        m_starting = false;
        if (reply.isError()) {
            Q_EMIT failed(question, reply.error().message());
        } else if (m_question == question) {
            m_conversation = reply.value();
        }
        Q_EMIT busyChanged();
    });
}

void Intelligence::cancel()
{
    if (m_conversation.isEmpty())
        return;
    auto msg = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("Cancel"));
    msg.setArguments({m_conversation});
    QDBusConnection::sessionBus().asyncCall(msg);
    cleanup();
}

// Pytania ze sklepu nie zaśmiecają historii rozmów z asystentem
void Intelligence::cleanup()
{
    if (m_conversation.isEmpty())
        return;
    auto msg = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("DeleteConversation"));
    msg.setArguments({m_conversation});
    QDBusConnection::sessionBus().asyncCall(msg);
    m_conversation.clear();
    Q_EMIT busyChanged();
}

void Intelligence::onFinished(const QString &conversation, const QString &text, const QString &badge)
{
    if (conversation != m_conversation)
        return;
    const QString question = m_question;
    cleanup();
    Q_EMIT answered(question, text, badge);
}

void Intelligence::onFailed(const QString &conversation, const QString &message)
{
    if (conversation != m_conversation)
        return;
    const QString question = m_question;
    cleanup();
    Q_EMIT failed(question, message);
}

// Sklep niczego nie uruchamia na prośbę modelu
void Intelligence::onAction(const QString &conversation, const QString &action, const QString &, const QString &, bool)
{
    if (conversation != m_conversation)
        return;
    auto msg = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("ActionResult"));
    msg.setArguments({conversation, action, -2, QString()});
    QDBusConnection::sessionBus().asyncCall(msg);
}

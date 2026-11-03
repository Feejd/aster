#include "assistant.h"

#include "util.h"

#include <QDBusArgument>
#include <QJsonArray>
#include <QJsonDocument>

static const QString kService = QStringLiteral("org.aster.Assistant");
static const QString kPath = QStringLiteral("/org/aster/Assistant");
static const QString kIface = QStringLiteral("org.aster.Assistant");

static QDBusMessage method(const QString &name, const QVariantList &args = {})
{
    return dbusMethod(kService, kPath, kIface, name, args);
}

Assistant::Assistant(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kIface, QStringLiteral("StatusChanged"), this, SLOT(refresh()));
    bus.connect(kService, kPath, kIface, QStringLiteral("HistoryChanged"), this, SLOT(refresh()));
    refresh();
}

void Assistant::refresh()
{
    dbusCall(this, method(QStringLiteral("Providers")), false, false, [this](const QDBusMessage &r) {
        m_available = r.type() == QDBusMessage::ReplyMessage;
        if (m_available)
            m_providers = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array().toVariantList();
        Q_EMIT changed();
    });
    dbusCall(this, method(QStringLiteral("Status")), false, false, [this](const QDBusMessage &r) {
        if (r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()) {
            m_status = qdbus_cast<QVariantMap>(r.arguments().first());
            Q_EMIT changed();
        }
    });
    dbusCall(this, method(QStringLiteral("Conversations")), false, false, [this](const QDBusMessage &r) {
        if (r.type() == QDBusMessage::ReplyMessage) {
            m_conversations = int(QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array().size());
            Q_EMIT changed();
        }
    });
}

void Assistant::configure(const QVariantMap &settings)
{
    dbusCall(this, method(QStringLiteral("Configure"), {settings}), false, false, [this](const QDBusMessage &r) {
        if (r.type() == QDBusMessage::ErrorMessage)
            Q_EMIT message(r.errorMessage());
        refresh();
    });
}

void Assistant::setProvider(const QString &id)
{
    configure({{QStringLiteral("provider"), id}});
}

void Assistant::setModel(const QString &provider, const QString &model)
{
    configure({{QStringLiteral("for"), provider}, {QStringLiteral("model"), model}});
}

void Assistant::setBaseUrl(const QString &provider, const QString &url)
{
    configure({{QStringLiteral("for"), provider}, {QStringLiteral("baseUrl"), url}});
}

void Assistant::setHistory(bool on)
{
    configure({{QStringLiteral("history"), on}});
}

void Assistant::setApiKey(const QString &provider, const QString &key)
{
    m_busy = true;
    Q_EMIT changed();
    // Portfel może zapytać o hasło — „interaktywnie”, z długim czasem oczekiwania
    dbusCall(this, method(QStringLiteral("SetApiKey"), {provider, key}), false, true, [this, key](const QDBusMessage &r) {
        m_busy = false;
        if (r.type() == QDBusMessage::ErrorMessage)
            Q_EMIT message(r.errorMessage());
        else
            Q_EMIT message(key.isEmpty() ? QStringLiteral("Klucz usunięty z portfela") : QStringLiteral("Klucz zapisany w portfelu"));
        refresh();
    });
}

void Assistant::clearHistory()
{
    dbusCall(this, method(QStringLiteral("ClearHistory")), false, false, [this](const QDBusMessage &) {
        Q_EMIT message(QStringLiteral("Historia rozmów wyczyszczona"));
        refresh();
    });
}

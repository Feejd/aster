#include "assistant.h"

#include "util.h"

#include <QDBusArgument>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

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
    bus.connect(kService, kPath, kIface, QStringLiteral("LocalModelsChanged"), this, SLOT(refreshLocal()));
    bus.connect(kService, kPath, kIface, QStringLiteral("DownloadProgress"), this, SLOT(onProgress(QString, qlonglong, qlonglong)));
    bus.connect(kService, kPath, kIface, QStringLiteral("DownloadFinished"), this, SLOT(onDownloadFinished(QString, bool, QString)));
    refresh();
    refreshLocal();
}

void Assistant::refreshLocal()
{
    dbusCall(this, method(QStringLiteral("LocalModels")), false, false, [this](const QDBusMessage &r) {
        if (r.type() != QDBusMessage::ReplyMessage)
            return;
        m_local = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).object().toVariantMap();
        // Pobieranie trwało, zanim otwarto Ustawienia — pasek postępu od razu
        const QString d = m_local.value(QStringLiteral("downloading")).toString();
        if (d != m_downloadId) {
            m_downloadId = d;
            if (d.isEmpty())
                m_received = m_total = 0;
            Q_EMIT progressChanged();
        }
        Q_EMIT localChanged();
    });
}

void Assistant::onProgress(const QString &id, qlonglong received, qlonglong total)
{
    m_downloadId = id;
    m_received = received;
    m_total = total;
    Q_EMIT progressChanged();
}

void Assistant::onDownloadFinished(const QString &id, bool ok, const QString &text)
{
    m_downloadId.clear();
    m_received = m_total = 0;
    Q_EMIT progressChanged();
    QString name = id;
    for (const QVariant &v : m_local.value(QStringLiteral("models")).toList())
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            name = v.toMap().value(QStringLiteral("name")).toString();
    Q_EMIT message(ok ? QStringLiteral("%1 pobrany — gotowy do pracy").arg(name) : text);
    refreshLocal();
    refresh();
}

void Assistant::downloadModel(const QString &id)
{
    dbusCall(this, method(QStringLiteral("DownloadModel"), {id}), false, false, [this](const QDBusMessage &r) {
        const QString error = r.type() == QDBusMessage::ReplyMessage ? r.arguments().value(0).toString() : r.errorMessage();
        if (!error.isEmpty())
            Q_EMIT message(error);
        refreshLocal();
    });
}

void Assistant::cancelDownload()
{
    dbusCall(this, method(QStringLiteral("CancelDownload")), false, false, [](const QDBusMessage &) {});
}

void Assistant::useModel(const QString &id)
{
    dbusCall(this, method(QStringLiteral("UseModel"), {id}), false, false, [this](const QDBusMessage &) {
        refreshLocal();
        refresh();
    });
}

void Assistant::deleteModel(const QString &id)
{
    dbusCall(this, method(QStringLiteral("DeleteModel"), {id}), false, false, [this](const QDBusMessage &) {
        Q_EMIT message(QStringLiteral("Model usunięty z dysku"));
        refreshLocal();
        refresh();
    });
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

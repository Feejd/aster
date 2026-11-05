#include "bus.h"
#include "engine.h"

#include <QDBusConnection>
#include <QJsonArray>
#include <QJsonDocument>
#include <memory>

static const QString kOrigin = QStringLiteral("Prośba z zewnątrz (asystent Aster albo polecenie aster-launch)");

LaunchBus::LaunchBus(Launch *launch, QObject *parent)
    : QObject(parent)
    , m_launch(launch)
{
}

QString LaunchBus::resolve(const QString &project)
{
    const QString id = m_launch->findProject(project);
    if (id.isEmpty())
        sendErrorReply(QStringLiteral("org.aster.Launch.Error.NoProject"), QStringLiteral("Nie ma projektu „%1”.").arg(project));
    return id;
}

QString LaunchBus::Projects()
{
    QJsonArray out;
    for (const QVariant &v : m_launch->projects()) {
        const QVariantMap p = v.toMap();
        out.append(QJsonObject{{QStringLiteral("name"), p.value(QStringLiteral("name")).toString()}, {QStringLiteral("type"), p.value(QStringLiteral("type")).toString()},
                               {QStringLiteral("target"), p.value(QStringLiteral("target")).toString()}, {QStringLiteral("url"), p.value(QStringLiteral("url")).toString()},
                               {QStringLiteral("current"), p.value(QStringLiteral("current")).toInt()}});
    }
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}

QString LaunchBus::Status(const QString &project)
{
    const QString id = resolve(project);
    if (id.isEmpty())
        return {};
    setDelayedReply(true);
    const QDBusMessage msg = message();
    auto conn = std::make_shared<QMetaObject::Connection>();
    *conn = connect(m_launch, &Launch::healthChecked, this, [this, conn, id, msg](const QString &pid, const QVariantMap &) {
        if (pid != id)
            return;
        disconnect(*conn);
        QDBusConnection::sessionBus().send(msg.createReply(QString::fromUtf8(QJsonDocument(m_launch->statusJson(id)).toJson(QJsonDocument::Compact))));
    });
    m_launch->checkHealth(id);
    return {};
}

void LaunchBus::runPlan(const QString &id, const QDBusMessage &msg)
{
    auto c1 = std::make_shared<QMetaObject::Connection>();
    auto c2 = std::make_shared<QMetaObject::Connection>();
    *c1 = connect(m_launch, &Launch::planFailed, this, [c1, c2, id, msg](const QString &pid, const QString &error) {
        if (pid != id)
            return;
        disconnect(*c1);
        disconnect(*c2);
        QDBusConnection::sessionBus().send(msg.createErrorReply(QStringLiteral("org.aster.Launch.Error.Plan"), error));
    });
    *c2 = connect(m_launch, &Launch::runFinished, this, [this, c1, c2, id, msg](const QString &pid, bool ok, const QString &text) {
        if (pid != id)
            return;
        disconnect(*c1);
        disconnect(*c2);
        if (!ok && text.startsWith(QLatin1String("Anulowano")))
            QDBusConnection::sessionBus().send(msg.createErrorReply(QStringLiteral("org.aster.Launch.Error.Denied"), QStringLiteral("Użytkownik nie zgodził się na zmiany.")));
        else
            QDBusConnection::sessionBus().send(msg.createReply(QString::fromUtf8(QJsonDocument(QJsonObject{
                {QStringLiteral("ok"), ok}, {QStringLiteral("message"), text}, {QStringLiteral("current"), m_launch->statusJson(id).value(QStringLiteral("current"))},
                {QStringLiteral("url"), m_launch->urlFor(id)}}).toJson(QJsonDocument::Compact))));
    });
    Q_EMIT m_launch->wantsAttention();
}

QString LaunchBus::Deploy(const QString &project)
{
    const QString id = resolve(project);
    if (id.isEmpty())
        return {};
    if (m_launch->running() || m_launch->preparing() || (!m_launch->plan().isEmpty() && m_launch->runResult().isEmpty())) {
        sendErrorReply(QStringLiteral("org.aster.Launch.Error.Busy"), QStringLiteral("Trwa inne wdrożenie albo czeka plan do potwierdzenia."));
        return {};
    }
    setDelayedReply(true);
    runPlan(id, message());
    m_launch->prepareDeploy(id, kOrigin);
    return {};
}

QString LaunchBus::Rollback(const QString &project, int version)
{
    const QString id = resolve(project);
    if (id.isEmpty())
        return {};
    if (m_launch->running() || m_launch->preparing() || (!m_launch->plan().isEmpty() && m_launch->runResult().isEmpty())) {
        sendErrorReply(QStringLiteral("org.aster.Launch.Error.Busy"), QStringLiteral("Trwa inne wdrożenie albo czeka plan do potwierdzenia."));
        return {};
    }
    const int v = version > 0 ? version : m_launch->previousVersion(id);
    if (v <= 0) {
        sendErrorReply(QStringLiteral("org.aster.Launch.Error.Plan"), QStringLiteral("Nie ma wcześniejszej wersji do przywrócenia."));
        return {};
    }
    setDelayedReply(true);
    runPlan(id, message());
    m_launch->prepareRollback(id, v, kOrigin);
    return {};
}

QString LaunchBus::Logs(const QString &project, int lines)
{
    const QString id = resolve(project);
    if (id.isEmpty())
        return {};
    setDelayedReply(true);
    const QDBusMessage msg = message();
    const QString name = m_launch->project(id).value(QStringLiteral("name")).toString();
    const int n = lines > 0 ? qMin(lines, 2000) : 200;
    const int token = m_launch->requestPermission(QStringLiteral("Udostępnić logi „%1”?").arg(name),
                                                  QStringLiteral("%1 prosi o ostatnie %2 wierszy logów produkcji. Logi mogą zawierać adresy e-mail, adresy IP albo inne dane użytkowników strony.")
                                                      .arg(kOrigin)
                                                      .arg(n),
                                                  QStringLiteral("Udostępnij"));
    auto conn = std::make_shared<QMetaObject::Connection>();
    *conn = connect(m_launch, &Launch::answered, this, [this, conn, token, id, n, msg](int t, bool ok) {
        if (t != token)
            return;
        disconnect(*conn);
        if (!ok) {
            QDBusConnection::sessionBus().send(msg.createErrorReply(QStringLiteral("org.aster.Launch.Error.Denied"), QStringLiteral("Użytkownik nie udostępnił logów.")));
            return;
        }
        auto c2 = std::make_shared<QMetaObject::Connection>();
        *c2 = connect(m_launch, &Launch::logsFetched, this, [c2, id, msg](const QString &pid, bool fine, const QString &text) {
            if (pid != id)
                return;
            disconnect(*c2);
            QDBusConnection::sessionBus().send(fine ? msg.createReply(text) : msg.createErrorReply(QStringLiteral("org.aster.Launch.Error.Logs"), text));
        });
        m_launch->fetchLogs(id, n);
    });
    return {};
}

void LaunchBus::Activate(const QString &token) { Q_EMIT activated(token); }

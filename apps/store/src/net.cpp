#include "net.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJSEngine>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>

// Pola, których sklep nie używa, a które zajmują większość odpowiedzi
static const QStringList kDrop = {
    QStringLiteral("translation"), QStringLiteral("localized_keywords"), QStringLiteral("mimetypes"), QStringLiteral("provides"),
    QStringLiteral("icons"), QStringLiteral("bundle"), QStringLiteral("launchable"), QStringLiteral("extensions"),
    QStringLiteral("built-extensions"), QStringLiteral("installs_per_day"), QStringLiteral("installs_per_country"),
    QStringLiteral("facetDistribution"), QStringLiteral("facetStats"), QStringLiteral("branding"),
};

static QJsonValue slim(const QJsonValue &v, int depth = 0)
{
    if (depth > 4)
        return v;
    if (v.isArray()) {
        QJsonArray out;
        for (const QJsonValue &item : v.toArray())
            out.append(slim(item, depth + 1));
        return out;
    }
    if (!v.isObject())
        return v;
    QJsonObject o = v.toObject();
    for (const QString &key : kDrop)
        o.remove(key);
    // Z historii wydań wystarczą ostatnie trzy
    if (o.contains(QStringLiteral("releases"))) {
        QJsonArray rel = o.value(QStringLiteral("releases")).toArray();
        while (rel.size() > 3)
            rel.removeLast();
        o.insert(QStringLiteral("releases"), rel);
    }
    for (auto it = o.begin(); it != o.end(); ++it)
        if (it.value().isObject() || it.value().isArray())
            it.value() = slim(it.value(), depth + 1);
    return o;
}

Net::Net(QObject *parent)
    : QObject(parent)
{
    m_dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/katalog");
    QDir().mkpath(m_dir);
    m_net.setTransferTimeout(20000);
}

QString Net::cacheFile(const QByteArray &key) const
{
    return m_dir + QLatin1Char('/') + QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Sha1).toHex()) + QStringLiteral(".json");
}

void Net::setOnline(bool online)
{
    if (m_online == online)
        return;
    m_online = online;
    Q_EMIT onlineChanged();
}

void Net::deliver(QJSValue cb, const QByteArray &json)
{
    if (!cb.isCallable())
        return;
    QJSEngine *engine = qjsEngine(this);
    if (!engine)
        return;
    QJSValue value(QJSValue::NullValue);
    if (!json.isEmpty())
        value = engine->globalObject().property(QStringLiteral("JSON")).property(QStringLiteral("parse")).call({QString::fromUtf8(json)});
    const QJSValue r = cb.call({value});
    if (r.isError())
        qWarning("Sklep: %s", qPrintable(r.toString()));
}

void Net::get(const QString &url, int maxAgeSeconds, const QJSValue &cb) { request(url, QByteArray(), maxAgeSeconds, cb); }

void Net::post(const QString &url, const QVariantMap &body, int maxAgeSeconds, const QJSValue &cb)
{
    request(url, QJsonDocument(QJsonObject::fromVariantMap(body)).toJson(QJsonDocument::Compact), maxAgeSeconds, cb);
}

void Net::request(const QString &url, const QByteArray &body, int maxAge, const QJSValue &cb)
{
    const QByteArray key = url.toUtf8() + '\n' + body;
    const QString file = cacheFile(key);
    QByteArray known;
    QFile cached(file);
    if (cached.open(QIODevice::ReadOnly)) {
        known = cached.readAll();
        cached.close();
        // Wywołanie z pamięci w następnym obrocie pętli, jak odpowiedź z sieci
        QTimer::singleShot(0, this, [this, cb, known] { deliver(cb, known); });
        if (QFileInfo(file).lastModified().secsTo(QDateTime::currentDateTime()) < maxAge)
            return;
    }

    auto it = m_pending.find(key);
    if (it != m_pending.end()) {
        it->append({cb, known});
        return;
    }
    m_pending.insert(key, {{cb, known}});

    QNetworkRequest req{QUrl(url)};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("AsterStore/2 (https://github.com/Feejd/aster)"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply;
    if (body.isEmpty()) {
        reply = m_net.get(req);
    } else {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        reply = m_net.post(req, body);
    }
    connect(reply, &QNetworkReply::finished, this, [this, reply, key, file] {
        reply->deleteLater();
        const QList<Waiting> waiting = m_pending.take(key);
        QByteArray data;
        const auto error = reply->error();
        if (error == QNetworkReply::NoError) {
            setOnline(true);
            QJsonParseError parse;
            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll(), &parse);
            if (parse.error == QJsonParseError::NoError) {
                const QJsonValue value = slim(doc.isArray() ? QJsonValue(doc.array()) : QJsonValue(doc.object()));
                data = value.isArray() ? QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact)
                                       : QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact);
                QSaveFile out(file);
                if (out.open(QIODevice::WriteOnly)) {
                    out.write(data);
                    out.commit();
                }
            }
        } else if (error != QNetworkReply::ContentNotFoundError && error != QNetworkReply::ProtocolInvalidOperationError) {
            setOnline(false);
        }
        for (const Waiting &w : waiting) {
            if (data.isEmpty() && !w.known.isEmpty())
                continue;           // sieć zawiodła, a dane z pamięci już poszły
            if (data == w.known)
                continue;
            deliver(w.cb, data);
        }
    });
}

QNetworkAccessManager *ImageCacheFactory::create(QObject *parent)
{
    auto *manager = new QNetworkAccessManager(parent);
    auto *cache = new QNetworkDiskCache(manager);
    cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/obrazy"));
    cache->setMaximumCacheSize(300 * 1024 * 1024);
    manager->setCache(cache);
    return manager;
}

#include "runner.h"
#include "workspace.h"

#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QMimeDatabase>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QUrl>

namespace {

bool hasHeader(const QList<QPair<QByteArray, QByteArray>> &h, const char *name)
{
    for (const auto &p : h)
        if (p.first.compare(name, Qt::CaseInsensitive) == 0)
            return true;
    return false;
}

QByteArray formEncode(const QJsonArray &form)
{
    QByteArrayList parts;
    for (const QJsonValue &v : form) {
        const QJsonObject o = v.toObject();
        if (!o.value(QLatin1String("enabled")).toBool(true) || o.value(QLatin1String("key")).toString().isEmpty())
            continue;
        parts << QUrl::toPercentEncoding(o.value(QLatin1String("key")).toString()) + '=' + QUrl::toPercentEncoding(o.value(QLatin1String("value")).toString());
    }
    return parts.join('&');
}

QString friendlyError(QNetworkReply::NetworkError e, const QString &fallback)
{
    switch (e) {
    case QNetworkReply::ConnectionRefusedError:
        return QStringLiteral("Serwer odrzucił połączenie — czy jest uruchomiony pod tym adresem i portem?");
    case QNetworkReply::HostNotFoundError:
        return QStringLiteral("Nie znaleziono serwera o tej nazwie");
    case QNetworkReply::RemoteHostClosedError:
        return QStringLiteral("Serwer zamknął połączenie bez odpowiedzi");
    case QNetworkReply::TimeoutError:
        return QStringLiteral("Serwer nie odpowiedział na czas");
    case QNetworkReply::SslHandshakeFailedError:
        return QStringLiteral("Błąd certyfikatu SSL (%1). Dla serwera testowego włącz „Pomiń sprawdzanie certyfikatu”.").arg(fallback);
    case QNetworkReply::ProtocolUnknownError:
        return QStringLiteral("Nieobsługiwany adres — zacznij od http:// albo https://");
    default:
        return fallback;
    }
}

} // namespace

Runner::Runner(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent)
    , m_nam(nam)
{
}

Runner::~Runner()
{
    if (m_reply) {
        m_reply->disconnect(this);
        m_reply->abort();
        m_reply->deleteLater();
    }
}

QList<QPair<QByteArray, QByteArray>> Runner::effectiveHeaders(const QJsonObject &req)
{
    QList<QPair<QByteArray, QByteArray>> h;
    for (const QJsonValue &v : req.value(QLatin1String("headers")).toArray()) {
        const QJsonObject o = v.toObject();
        if (!o.value(QLatin1String("enabled")).toBool(true) || o.value(QLatin1String("key")).toString().trimmed().isEmpty())
            continue;
        h.append({o.value(QLatin1String("key")).toString().trimmed().toUtf8(), o.value(QLatin1String("value")).toString().toUtf8()});
    }
    const QJsonObject body = req.value(QLatin1String("body")).toObject();
    const QString mode = body.value(QLatin1String("mode")).toString();
    const QString explicitType = body.value(QLatin1String("contentType")).toString();
    if (!hasHeader(h, "Content-Type")) {
        QByteArray type = explicitType.toUtf8();
        if (type.isEmpty()) {
            if (mode == QLatin1String("json"))
                type = "application/json";
            else if (mode == QLatin1String("text"))
                type = "text/plain; charset=utf-8";
            else if (mode == QLatin1String("urlencoded"))
                type = "application/x-www-form-urlencoded";
            else if (mode == QLatin1String("file"))
                type = QMimeDatabase().mimeTypeForFile(body.value(QLatin1String("file")).toString()).name().toUtf8();
        }
        if (!type.isEmpty() && mode != QLatin1String("form") && mode != QLatin1String("none"))
            h.append({"Content-Type", type});
    }
    const QJsonObject auth = req.value(QLatin1String("auth")).toObject();
    const QString type = auth.value(QLatin1String("type")).toString();
    if (!hasHeader(h, "Authorization")) {
        if (type == QLatin1String("bearer") && !auth.value(QLatin1String("token")).toString().isEmpty())
            h.append({"Authorization", "Bearer " + auth.value(QLatin1String("token")).toString().toUtf8()});
        else if (type == QLatin1String("basic"))
            h.append({"Authorization", "Basic " + (auth.value(QLatin1String("user")).toString() + QLatin1Char(':') + auth.value(QLatin1String("password")).toString()).toUtf8().toBase64()});
    }
    if (!hasHeader(h, "User-Agent"))
        h.append({QByteArray("User-Agent"), QByteArray("AsterPulse/1.0")});
    if (!hasHeader(h, "Accept"))
        h.append({QByteArray("Accept"), QByteArray("*/*")});
    return h;
}

void Runner::start(const QJsonObject &req, int timeoutMs)
{
    abort();
    m_aborted = false;
    m_body.clear();
    const QString method = req.value(QLatin1String("method")).toString(QStringLiteral("GET")).toUpper();
    QString urlText = Vars::fullUrl(req);
    if (!urlText.isEmpty() && !urlText.contains(QLatin1String("://")))
        urlText.prepend(QStringLiteral("http://"));
    const QUrl url(urlText, QUrl::TolerantMode);
    m_result = {{QStringLiteral("method"), method}, {QStringLiteral("url"), url.toString(QUrl::FullyEncoded)}};
    if (urlText.isEmpty() || !url.isValid() || url.host().isEmpty()) {
        m_result[QStringLiteral("url")] = urlText;
        done(urlText.isEmpty() ? QStringLiteral("Wpisz adres zapytania") : QStringLiteral("Niepoprawny adres: %1").arg(urlText));
        return;
    }
    if (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https")) {
        done(QStringLiteral("Nieobsługiwany adres — zacznij od http:// albo https://"));
        return;
    }

    QNetworkRequest nr(url);
    nr.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    nr.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    nr.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    const auto headers = effectiveHeaders(req);
    QJsonArray sent;
    for (const auto &p : headers) {
        nr.setRawHeader(p.first, p.second);
        sent.append(QJsonArray{QString::fromUtf8(p.first), QString::fromUtf8(p.second)});
    }
    m_result[QStringLiteral("requestHeaders")] = sent;

    const QJsonObject body = req.value(QLatin1String("body")).toObject();
    const QString mode = body.value(QLatin1String("mode")).toString();
    QByteArray data;
    QHttpMultiPart *multipart = nullptr;
    if (mode == QLatin1String("json") || mode == QLatin1String("text")) {
        data = body.value(QLatin1String("text")).toString().toUtf8();
    } else if (mode == QLatin1String("urlencoded")) {
        data = formEncode(body.value(QLatin1String("form")).toArray());
    } else if (mode == QLatin1String("file")) {
        QFile f(body.value(QLatin1String("file")).toString());
        if (!f.open(QIODevice::ReadOnly)) {
            done(QStringLiteral("Nie można otworzyć pliku do wysłania: %1").arg(f.fileName()));
            return;
        }
        data = f.readAll();
    } else if (mode == QLatin1String("form")) {
        multipart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        for (const QJsonValue &v : body.value(QLatin1String("form")).toArray()) {
            const QJsonObject o = v.toObject();
            const QString key = o.value(QLatin1String("key")).toString();
            if (!o.value(QLatin1String("enabled")).toBool(true) || key.isEmpty())
                continue;
            QHttpPart part;
            QByteArray safeKey = key.toUtf8();
            safeKey.replace('"', "%22");
            if (o.value(QLatin1String("type")).toString() == QLatin1String("file")) {
                auto *file = new QFile(o.value(QLatin1String("value")).toString(), multipart);
                if (!file->open(QIODevice::ReadOnly)) {
                    delete multipart;
                    done(QStringLiteral("Nie można otworzyć pliku: %1").arg(file->fileName()));
                    return;
                }
                QByteArray fname = QFileInfo(file->fileName()).fileName().toUtf8();
                fname.replace('"', "%22");
                part.setHeader(QNetworkRequest::ContentDispositionHeader, QByteArray("form-data; name=\"" + safeKey + "\"; filename=\"" + fname + "\""));
                part.setHeader(QNetworkRequest::ContentTypeHeader, QMimeDatabase().mimeTypeForFile(file->fileName()).name());
                part.setBodyDevice(file);
            } else {
                part.setHeader(QNetworkRequest::ContentDispositionHeader, QByteArray("form-data; name=\"" + safeKey + "\""));
                part.setBody(o.value(QLatin1String("value")).toString().toUtf8());
            }
            multipart->append(part);
        }
        if (!hasHeader(headers, "Content-Type"))
            nr.setRawHeader("Content-Type", "multipart/form-data; boundary=" + multipart->boundary());
    }

    m_timer.start();
    m_reply = multipart ? m_nam->sendCustomRequest(nr, method.toUtf8(), multipart)
                        : m_nam->sendCustomRequest(nr, method.toUtf8(), data);
    if (multipart)
        multipart->setParent(m_reply);
    if (req.value(QLatin1String("insecure")).toBool())
        connect(m_reply, &QNetworkReply::sslErrors, m_reply, [r = m_reply.data()] { r->ignoreSslErrors(); });
    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        m_body += m_reply->readAll();
        // Bardzo duże odpowiedzi (np. pobieranie pliku) — do 64 MB w pamięci
        if (m_body.size() > 64 * 1024 * 1024) {
            m_result[QStringLiteral("truncated")] = true;
            m_reply->abort();
        }
    });
    connect(m_reply, &QNetworkReply::finished, this, [this] { done(); });
    if (timeoutMs > 0)
        QTimer::singleShot(timeoutMs, m_reply, [this, timeoutMs] {
            m_result[QStringLiteral("timedOut")] = true;
            m_result[QStringLiteral("timeoutMs")] = timeoutMs;
            m_reply->abort();
        });
}

void Runner::abort()
{
    if (!m_reply)
        return;
    m_aborted = true;
    m_reply->abort();
}

void Runner::done(const QString &error)
{
    QNetworkReply *r = m_reply;
    m_result[QStringLiteral("timeMs")] = r ? qint64(m_timer.elapsed()) : 0;
    QString err = error;
    if (r) {
        m_body += r->readAll();
        const QVariant status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        if (status.isValid()) {
            m_result[QStringLiteral("status")] = status.toInt();
            m_result[QStringLiteral("statusText")] = QString::fromUtf8(r->attribute(QNetworkRequest::HttpReasonPhraseAttribute).toByteArray());
            QJsonArray hs;
            for (const auto &p : r->rawHeaderPairs())
                hs.append(QJsonArray{QString::fromUtf8(p.first), QString::fromUtf8(p.second)});
            m_result[QStringLiteral("headers")] = hs;
            m_result[QStringLiteral("contentType")] = QString::fromUtf8(r->rawHeader("Content-Type"));
            const QString finalUrl = r->url().toString(QUrl::FullyEncoded);
            if (finalUrl != m_result.value(QLatin1String("url")).toString())
                m_result[QStringLiteral("redirectedTo")] = finalUrl;
        }
        if (m_result.value(QLatin1String("timedOut")).toBool())
            err = QStringLiteral("Brak odpowiedzi po %1 s").arg(m_result.value(QLatin1String("timeoutMs")).toInt() / 1000.0);
        else if (m_aborted)
            err = QStringLiteral("Anulowano");
        else if (!status.isValid() && r->error() != QNetworkReply::NoError)
            err = friendlyError(r->error(), r->errorString());
        r->disconnect(this);
        r->deleteLater();
        m_reply = nullptr;
    }
    m_result[QStringLiteral("size")] = qint64(m_body.size());
    // ok — odpowiedź przyszła i nie jest błędem HTTP (kod poniżej 400)
    const int code = m_result.value(QLatin1String("status")).toInt();
    m_result[QStringLiteral("ok")] = err.isEmpty() && code > 0 && code < 400;
    if (!err.isEmpty())
        m_result[QStringLiteral("error")] = err;
    const QJsonObject result = m_result;
    const QByteArray body = m_body;
    m_body.clear();
    Q_EMIT finished(result, body);
}

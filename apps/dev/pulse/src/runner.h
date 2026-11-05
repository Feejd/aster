#pragma once

#include <QElapsedTimer>
#include <QJsonObject>
#include <QObject>
#include <QPointer>

class QNetworkAccessManager;
#include <QNetworkReply>

// Jedno zapytanie HTTP: podstawia zmienne, buduje treść i autoryzację, mierzy czas i rozmiar.
// Wynik (finished): { ok (odpowiedź z kodem < 400), method, url, status, statusText, timeMs, size, contentType,
//   headers: [[nazwa, wartość]…], requestHeaders: […], unresolved: [zmienne bez wartości], error }
class Runner : public QObject
{
    Q_OBJECT
public:
    explicit Runner(QNetworkAccessManager *nam, QObject *parent = nullptr);
    ~Runner() override;

    // req — zapytanie z już podstawionymi zmiennymi (Vars::resolveRequest); timeout w ms
    void start(const QJsonObject &req, int timeoutMs = 30000);
    void abort();
    bool running() const { return m_reply; }

    // Nagłówki, które pójdą razem z zapytaniem (jawne + Content-Type z trybu treści + autoryzacja)
    static QList<QPair<QByteArray, QByteArray>> effectiveHeaders(const QJsonObject &req);

Q_SIGNALS:
    void finished(const QJsonObject &result, const QByteArray &body);

private:
    void done(const QString &error = {});
    QNetworkAccessManager *m_nam;
    QPointer<QNetworkReply> m_reply;
    QElapsedTimer m_timer;
    QJsonObject m_result;
    QByteArray m_body;
    bool m_aborted = false;
};

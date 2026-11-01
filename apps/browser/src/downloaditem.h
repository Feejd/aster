#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantMap>

class QWebEngineDownloadRequest;

// Jeden plik na liście pobranych: trwające pobieranie (owija prośbę silnika)
// albo wpis z poprzednich uruchomień (sam zapis — plik może już nie istnieć).
class DownloadItem : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Tworzy przeglądarka")
    Q_PROPERTY(QString fileName READ fileName NOTIFY changed)
    Q_PROPERTY(QString path READ path NOTIFY changed)
    Q_PROPERTY(QString url READ url CONSTANT)
    Q_PROPERTY(qint64 received READ received NOTIFY changed)
    Q_PROPERTY(qint64 total READ total NOTIFY changed)
    Q_PROPERTY(qreal progress READ progress NOTIFY changed)
    Q_PROPERTY(qint64 speed READ speed NOTIFY changed)          // bajty na sekundę
    Q_PROPERTY(State state READ state NOTIFY changed)
    Q_PROPERTY(bool active READ active NOTIFY changed)          // trwa albo wstrzymane
    Q_PROPERTY(bool exists READ exists NOTIFY changed)
    Q_PROPERTY(qint64 time READ time CONSTANT)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    enum State { InProgress, Paused, Completed, Cancelled, Interrupted };
    Q_ENUM(State)

    DownloadItem(QWebEngineDownloadRequest *request, bool keep, QObject *parent = nullptr);
    DownloadItem(const QVariantMap &record, QObject *parent = nullptr);

    QString fileName() const;
    QString path() const;
    QString url() const { return m_url; }
    qint64 received() const;
    qint64 total() const;
    qreal progress() const;
    qint64 speed() const { return m_speed; }
    State state() const;
    bool active() const { return state() == InProgress || state() == Paused; }
    bool exists() const;
    qint64 time() const { return m_time; }
    QString error() const;
    bool keep() const { return m_keep; }        // okna prywatne nie zostawiają śladu
    QVariantMap record() const;

    Q_INVOKABLE void open();
    Q_INVOKABLE void showInFolder();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();

Q_SIGNALS:
    void changed();
    void finished();

private:
    void sample();

    QPointer<QWebEngineDownloadRequest> m_request;
    bool m_keep = true;
    QString m_url;
    qint64 m_time = 0;
    // zapis (gdy nie ma już prośby silnika)
    QString m_path;
    qint64 m_total = 0;
    State m_state = Completed;
    // prędkość
    QElapsedTimer m_clock;
    qint64 m_lastBytes = 0;
    qint64 m_speed = 0;
};

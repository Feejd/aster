#include "downloaditem.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QWebEngineDownloadRequest>

DownloadItem::DownloadItem(QWebEngineDownloadRequest *request, bool keep, QObject *parent)
    : QObject(parent)
    , m_request(request)
    , m_keep(keep)
    , m_url(request->url().toString())
    , m_time(QDateTime::currentMSecsSinceEpoch())
{
    m_clock.start();
    const auto notify = [this] { Q_EMIT changed(); };
    connect(request, &QWebEngineDownloadRequest::receivedBytesChanged, this, [this] { sample(); Q_EMIT changed(); });
    connect(request, &QWebEngineDownloadRequest::totalBytesChanged, this, notify);
    connect(request, &QWebEngineDownloadRequest::isPausedChanged, this, notify);
    connect(request, &QWebEngineDownloadRequest::downloadFileNameChanged, this, notify);
    connect(request, &QWebEngineDownloadRequest::stateChanged, this, [this](QWebEngineDownloadRequest::DownloadState) {
        // Po zakończeniu zostaje sam zapis — silnik może już skasować swoją prośbę
        if (m_request && m_request->isFinished()) {
            m_path = QDir(m_request->downloadDirectory()).filePath(m_request->downloadFileName());
            m_total = m_request->receivedBytes();
            m_state = state();
            m_speed = 0;
            Q_EMIT changed();
            Q_EMIT finished();
        } else
            Q_EMIT changed();
    });
}

DownloadItem::DownloadItem(const QVariantMap &r, QObject *parent)
    : QObject(parent)
    , m_url(r.value(QStringLiteral("url")).toString())
    , m_time(r.value(QStringLiteral("time")).toLongLong())
    , m_path(r.value(QStringLiteral("path")).toString())
    , m_total(r.value(QStringLiteral("total")).toLongLong())
    , m_state(State(r.value(QStringLiteral("state")).toInt()))
{
    // Pobieranie przerwane zamknięciem programu nie wróci samo
    if (m_state == InProgress || m_state == Paused)
        m_state = Interrupted;
}

QVariantMap DownloadItem::record() const
{
    return {{QStringLiteral("url"), m_url},
            {QStringLiteral("time"), m_time},
            {QStringLiteral("path"), path()},
            {QStringLiteral("total"), total()},
            {QStringLiteral("state"), int(state())}};
}

QString DownloadItem::fileName() const
{
    if (m_request)
        return m_request->downloadFileName();
    return QFileInfo(m_path).fileName();
}

QString DownloadItem::path() const
{
    if (m_request)
        return QDir(m_request->downloadDirectory()).filePath(m_request->downloadFileName());
    return m_path;
}

qint64 DownloadItem::received() const
{
    return m_request ? m_request->receivedBytes() : (m_state == Completed ? m_total : 0);
}

qint64 DownloadItem::total() const
{
    return m_request ? m_request->totalBytes() : m_total;
}

qreal DownloadItem::progress() const
{
    const qint64 t = total();
    if (t <= 0)
        return state() == Completed ? 1 : -1;
    return qBound(0.0, qreal(received()) / qreal(t), 1.0);
}

DownloadItem::State DownloadItem::state() const
{
    if (!m_request)
        return m_state;
    switch (m_request->state()) {
    case QWebEngineDownloadRequest::DownloadCompleted:
        return Completed;
    case QWebEngineDownloadRequest::DownloadCancelled:
        return Cancelled;
    case QWebEngineDownloadRequest::DownloadInterrupted:
        return Interrupted;
    default:
        return m_request->isPaused() ? Paused : InProgress;
    }
}

bool DownloadItem::exists() const
{
    return state() == Completed && QFileInfo::exists(path());
}

QString DownloadItem::error() const
{
    if (m_request && m_request->state() == QWebEngineDownloadRequest::DownloadInterrupted)
        return m_request->interruptReasonString();
    return QString();
}

void DownloadItem::sample()
{
    // Średnia krocząca co pół sekundy — liczba nie skacze przy każdym pakiecie
    const qint64 ms = m_clock.elapsed();
    if (ms < 500 || !m_request)
        return;
    const qint64 bytes = m_request->receivedBytes();
    const qint64 now = (bytes - m_lastBytes) * 1000 / ms;
    m_speed = m_speed ? (m_speed * 2 + now) / 3 : now;
    m_lastBytes = bytes;
    m_clock.restart();
}

void DownloadItem::open()
{
    if (exists())
        QDesktopServices::openUrl(QUrl::fromLocalFile(path()));
}

void DownloadItem::showInFolder()
{
    // Menedżer plików zaznacza plik (Pliki Aster i Dolphin obsługują FileManager1);
    // gdy nikt nie odpowie — sam katalog
    const QString file = path();
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    msg << QStringList{QUrl::fromLocalFile(file).toString()} << QString();
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 1500);
    if (reply.type() == QDBusMessage::ErrorMessage)
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(file).absolutePath()));
}

void DownloadItem::cancel()
{
    if (m_request)
        m_request->cancel();
}

void DownloadItem::pause()
{
    if (m_request)
        m_request->pause();
}

void DownloadItem::resume()
{
    if (m_request)
        m_request->resume();
}

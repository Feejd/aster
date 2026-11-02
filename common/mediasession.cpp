#include "mediasession.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

static const QString objectPath = QStringLiteral("/org/mpris/MediaPlayer2");
static const QString playerIface = QStringLiteral("org.mpris.MediaPlayer2.Player");

MediaSession::MediaSession(QObject *parent)
    : QObject(parent)
{
    m_flush.setSingleShot(true);
    m_flush.setInterval(0);
    connect(&m_flush, &QTimer::timeout, this, &MediaSession::flush);
}

MediaSession::~MediaSession()
{
    if (m_inhibited) {
        m_inhibit = false;
        updateInhibit();
    }
    if (m_registered)
        QDBusConnection::sessionBus().unregisterService(m_service);
}

void MediaSession::componentComplete()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || m_name.isEmpty() || !qEnvironmentVariable("ASTER_SHOT").isEmpty())
        return;
    m_object = new QObject(this);
    new MprisRoot(m_object, this);
    new MprisPlayer(m_object, this);
    if (!bus.registerObject(objectPath, m_object, QDBusConnection::ExportAdaptors))
        return;
    // Drugie okno tego samego programu — osobna nazwa, ta sama nazwa wyświetlana
    QString name = m_name;
    for (QChar &c : name)
        if (!c.isLetterOrNumber() || c.unicode() > 127)
            c = QLatin1Char('_');
    m_service = QStringLiteral("org.mpris.MediaPlayer2.") + name;
    if (!bus.registerService(m_service)) {
        m_service += QStringLiteral(".instance") + QString::number(QCoreApplication::applicationPid());
        if (!bus.registerService(m_service))
            return;
    }
    m_registered = true;
}

QVariantMap MediaSession::metadata() const
{
    QVariantMap m;
    if (m_title.isEmpty())
        return m;
    m.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/aster/track/") + QString::number(m_track))));
    if (m_length > 0)
        m.insert(QStringLiteral("mpris:length"), qlonglong(m_length * 1000));
    m.insert(QStringLiteral("xesam:title"), m_title);
    if (!m_artist.isEmpty())
        m.insert(QStringLiteral("xesam:artist"), QStringList{m_artist});
    if (!m_album.isEmpty())
        m.insert(QStringLiteral("xesam:album"), m_album);
    if (!m_artUrl.isEmpty())
        m.insert(QStringLiteral("mpris:artUrl"), m_artUrl);
    return m;
}

void MediaSession::markChanged(const char *property)
{
    const QString p = QString::fromLatin1(property);
    if (!m_dirty.contains(p))
        m_dirty << p;
    m_flush.start();
    Q_EMIT changed();
}

// Zebrane zmiany jednym sygnałem PropertiesChanged
void MediaSession::flush()
{
    if (!m_registered) {
        m_dirty.clear();
        return;
    }
    QVariantMap changed;
    for (const QString &p : std::as_const(m_dirty)) {
        if (p == QLatin1String("Metadata"))
            changed.insert(p, metadata());
        else if (p == QLatin1String("PlaybackStatus"))
            changed.insert(p, m_status);
        else if (p == QLatin1String("LoopStatus"))
            changed.insert(p, m_loop);
        else if (p == QLatin1String("Shuffle"))
            changed.insert(p, m_shuffle);
        else if (p == QLatin1String("Volume"))
            changed.insert(p, m_volume);
        else if (p == QLatin1String("CanGoNext"))
            changed.insert(p, m_canNext);
        else if (p == QLatin1String("CanGoPrevious"))
            changed.insert(p, m_canPrevious);
        else if (p == QLatin1String("CanSeek"))
            changed.insert(p, m_canSeek && m_length > 0);
    }
    m_dirty.clear();
    if (changed.contains(QStringLiteral("Metadata"))) {
        changed.insert(QStringLiteral("CanPlay"), !m_title.isEmpty());
        changed.insert(QStringLiteral("CanPause"), !m_title.isEmpty());
    }
    QDBusMessage sig = QDBusMessage::createSignal(objectPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
    sig << playerIface << changed << QStringList();
    QDBusConnection::sessionBus().send(sig);
}

void MediaSession::seeked(qint64 ms)
{
    m_position = ms;
    if (!m_registered)
        return;
    QDBusMessage sig = QDBusMessage::createSignal(objectPath, playerIface, QStringLiteral("Seeked"));
    sig << qlonglong(ms * 1000);
    QDBusConnection::sessionBus().send(sig);
}

void MediaSession::setStatus(const QString &s)
{
    if (s == m_status) return;
    m_status = s;
    markChanged("PlaybackStatus");
}
void MediaSession::setTitle(const QString &s)
{
    if (s == m_title) return;
    m_title = s;
    ++m_track;
    markChanged("Metadata");
}
void MediaSession::setArtist(const QString &s)
{
    if (s == m_artist) return;
    m_artist = s;
    markChanged("Metadata");
}
void MediaSession::setAlbum(const QString &s)
{
    if (s == m_album) return;
    m_album = s;
    markChanged("Metadata");
}
void MediaSession::setArtUrl(const QString &s)
{
    if (s == m_artUrl) return;
    m_artUrl = s;
    markChanged("Metadata");
}
void MediaSession::setLength(qint64 ms)
{
    if (ms == m_length) return;
    m_length = ms;
    markChanged("Metadata");
    markChanged("CanSeek");
}
void MediaSession::setCanNext(bool b)
{
    if (b == m_canNext) return;
    m_canNext = b;
    markChanged("CanGoNext");
}
void MediaSession::setCanPrevious(bool b)
{
    if (b == m_canPrevious) return;
    m_canPrevious = b;
    markChanged("CanGoPrevious");
}
void MediaSession::setCanSeek(bool b)
{
    if (b == m_canSeek) return;
    m_canSeek = b;
    markChanged("CanSeek");
}
void MediaSession::setVolume(double v)
{
    if (qFuzzyCompare(v, m_volume)) return;
    m_volume = v;
    markChanged("Volume");
}
void MediaSession::setShuffle(bool b)
{
    if (b == m_shuffle) return;
    m_shuffle = b;
    markChanged("Shuffle");
}
void MediaSession::setLoop(const QString &s)
{
    if (s == m_loop) return;
    m_loop = s;
    markChanged("LoopStatus");
}

void MediaSession::setInhibit(bool b)
{
    if (b == m_inhibit) return;
    m_inhibit = b;
    Q_EMIT changed();
    updateInhibit();
}

// Wygaszacz: Inhibit zwraca numer, którym potem zdejmuje się blokadę
void MediaSession::updateInhibit()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || m_inhibit == m_inhibited)
        return;
    const QString service = QStringLiteral("org.freedesktop.ScreenSaver");
    const QString path = QStringLiteral("/org/freedesktop/ScreenSaver");
    m_inhibited = m_inhibit;
    if (m_inhibit) {
        QDBusMessage m = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("Inhibit"));
        m << QCoreApplication::applicationName() << (m_inhibitReason.isEmpty() ? QStringLiteral("Odtwarzanie") : m_inhibitReason);
        auto *w = new QDBusPendingCallWatcher(bus.asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, service, path](QDBusPendingCallWatcher *w) {
            const QDBusPendingReply<uint> r = *w;
            w->deleteLater();
            if (r.isError())
                return;
            if (m_inhibited) {
                m_cookie = r.value();
                return;
            }
            // W międzyczasie zdjęte — oddaj od razu
            QDBusMessage m = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("UnInhibit"));
            m << r.value();
            QDBusConnection::sessionBus().asyncCall(m);
        });
    } else if (m_cookie) {
        QDBusMessage m = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("UnInhibit"));
        m << m_cookie;
        m_cookie = 0;
        if (QCoreApplication::closingDown())
            bus.call(m, QDBus::NoBlock);
        else
            bus.asyncCall(m);
    }
}

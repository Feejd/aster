#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QObject>
#include <QQmlEngine>
#include <QQmlParserStatus>
#include <QTimer>
#include <QVariantMap>

// Odtwarzacz widoczny dla systemu przez MPRIS (org.mpris.MediaPlayer2.<name>): Centrum sterowania
// Aster pokazuje tytuł i okładkę i steruje odtwarzaniem, działają też klawisze multimedialne.
// Do tego blokada wygaszania ekranu (org.freedesktop.ScreenSaver), np. gdy leci film.
// Wspólne dla Wideo i Muzyki — dołączane do modułu QML każdej z nich.
class MediaSession : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString name MEMBER m_name NOTIFY changed)                 // „Muzyka” → org.mpris.MediaPlayer2.Muzyka
    Q_PROPERTY(QString desktopEntry MEMBER m_desktopEntry NOTIFY changed) // „org.aster.music”
    Q_PROPERTY(QString status READ status WRITE setStatus NOTIFY changed) // Playing | Paused | Stopped
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY changed)
    Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY changed)
    Q_PROPERTY(QString album READ album WRITE setAlbum NOTIFY changed)
    Q_PROPERTY(QString artUrl READ artUrl WRITE setArtUrl NOTIFY changed)
    Q_PROPERTY(qint64 length READ length WRITE setLength NOTIFY changed) // ms
    Q_PROPERTY(qint64 position MEMBER m_position NOTIFY positionChanged) // ms (system pyta, nie powiadamiamy)
    Q_PROPERTY(bool canNext READ canNext WRITE setCanNext NOTIFY changed)
    Q_PROPERTY(bool canPrevious READ canPrevious WRITE setCanPrevious NOTIFY changed)
    Q_PROPERTY(bool canSeek READ canSeek WRITE setCanSeek NOTIFY changed)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY changed)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY changed)
    Q_PROPERTY(QString loop READ loop WRITE setLoop NOTIFY changed)       // None | Track | Playlist
    Q_PROPERTY(bool inhibit READ inhibit WRITE setInhibit NOTIFY changed) // nie wygaszaj ekranu
    Q_PROPERTY(QString inhibitReason MEMBER m_inhibitReason NOTIFY changed)

public:
    explicit MediaSession(QObject *parent = nullptr);
    ~MediaSession() override;

    void classBegin() override {}
    void componentComplete() override;

    QString status() const { return m_status; }
    void setStatus(const QString &s);
    QString title() const { return m_title; }
    void setTitle(const QString &s);
    QString artist() const { return m_artist; }
    void setArtist(const QString &s);
    QString album() const { return m_album; }
    void setAlbum(const QString &s);
    QString artUrl() const { return m_artUrl; }
    void setArtUrl(const QString &s);
    qint64 length() const { return m_length; }
    void setLength(qint64 ms);
    qint64 position() const { return m_position; }
    bool canNext() const { return m_canNext; }
    void setCanNext(bool b);
    bool canPrevious() const { return m_canPrevious; }
    void setCanPrevious(bool b);
    bool canSeek() const { return m_canSeek; }
    void setCanSeek(bool b);
    double volume() const { return m_volume; }
    void setVolume(double v);
    bool shuffle() const { return m_shuffle; }
    void setShuffle(bool b);
    QString loop() const { return m_loop; }
    void setLoop(const QString &s);
    bool inhibit() const { return m_inhibit; }
    void setInhibit(bool b);

    QVariantMap metadata() const;
    QString desktopEntry() const { return m_desktopEntry; }
    QString identity() const { return m_name; }

    // Przeskok w odtwarzaniu (system pokazuje nową pozycję od razu)
    Q_INVOKABLE void seeked(qint64 ms);

Q_SIGNALS:
    void changed();
    void positionChanged();
    void raiseRequested();
    void quitRequested();
    void playRequested();
    void pauseRequested();
    void playPauseRequested();
    void stopRequested();
    void nextRequested();
    void previousRequested();
    void positionRequested(qint64 ms);
    void volumeRequested(double volume);
    void shuffleRequested(bool shuffle);
    void loopRequested(const QString &loop);
    void openRequested(const QString &uri);

private:
    void markChanged(const char *property);
    void flush();
    void updateInhibit();

    QString m_name, m_desktopEntry, m_status = QStringLiteral("Stopped"), m_title, m_artist, m_album, m_artUrl;
    QString m_loop = QStringLiteral("None"), m_inhibitReason;
    qint64 m_length = 0, m_position = 0;
    bool m_canNext = false, m_canPrevious = false, m_canSeek = true, m_shuffle = false, m_inhibit = false;
    double m_volume = 1.0;
    int m_track = 0;

    bool m_registered = false;
    QString m_service;
    QObject *m_object = nullptr;
    QTimer m_flush;
    QStringList m_dirty;
    uint m_cookie = 0;
    bool m_inhibited = false;
};

// org.mpris.MediaPlayer2
class MprisRoot : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes)
    Q_PROPERTY(bool CanRaise READ yes)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ schemes)
    Q_PROPERTY(QStringList SupportedMimeTypes READ mimes)

public:
    MprisRoot(QObject *object, MediaSession *session) : QDBusAbstractAdaptor(object), s(session) {}
    bool yes() const { return true; }
    bool no() const { return false; }
    QString identity() const { return s->identity(); }
    QString desktopEntry() const { return s->desktopEntry(); }
    QStringList schemes() const { return {QStringLiteral("file")}; }
    QStringList mimes() const { return {}; }

public Q_SLOTS:
    void Raise() { Q_EMIT s->raiseRequested(); }
    void Quit() { Q_EMIT s->quitRequested(); }

private:
    MediaSession *s;
};

// org.mpris.MediaPlayer2.Player
class MprisPlayer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus WRITE setLoopStatus)
    Q_PROPERTY(double Rate READ one WRITE setRate)
    Q_PROPERTY(double MinimumRate READ one)
    Q_PROPERTY(double MaximumRate READ one)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(bool CanGoNext READ canNext)
    Q_PROPERTY(bool CanGoPrevious READ canPrevious)
    Q_PROPERTY(bool CanPlay READ hasTrack)
    Q_PROPERTY(bool CanPause READ hasTrack)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ yes)

public:
    MprisPlayer(QObject *object, MediaSession *session) : QDBusAbstractAdaptor(object), s(session) {}
    QString playbackStatus() const { return s->status(); }
    QString loopStatus() const { return s->loop(); }
    void setLoopStatus(const QString &l) { Q_EMIT s->loopRequested(l); }
    double one() const { return 1.0; }
    void setRate(double) {}
    bool shuffle() const { return s->shuffle(); }
    void setShuffle(bool b) { Q_EMIT s->shuffleRequested(b); }
    QVariantMap metadata() const { return s->metadata(); }
    double volume() const { return s->volume(); }
    void setVolume(double v) { Q_EMIT s->volumeRequested(qBound(0.0, v, 1.0)); }
    qlonglong position() const { return s->position() * 1000; }
    bool canNext() const { return s->canNext(); }
    bool canPrevious() const { return s->canPrevious(); }
    bool hasTrack() const { return !s->title().isEmpty(); }
    bool canSeek() const { return s->canSeek() && s->length() > 0; }
    bool yes() const { return true; }

public Q_SLOTS:
    void Next() { Q_EMIT s->nextRequested(); }
    void Previous() { Q_EMIT s->previousRequested(); }
    void Pause() { Q_EMIT s->pauseRequested(); }
    void PlayPause() { Q_EMIT s->playPauseRequested(); }
    void Stop() { Q_EMIT s->stopRequested(); }
    void Play() { Q_EMIT s->playRequested(); }
    void Seek(qlonglong offsetUs) { Q_EMIT s->positionRequested(qMax<qint64>(0, s->position() + offsetUs / 1000)); }
    void SetPosition(const QDBusObjectPath &, qlonglong us) { Q_EMIT s->positionRequested(us / 1000); }
    void OpenUri(const QString &uri) { Q_EMIT s->openRequested(uri); }

Q_SIGNALS:
    void Seeked(qlonglong position);

private:
    MediaSession *s;
};

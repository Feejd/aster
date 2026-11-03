#pragma once

#include <QElapsedTimer>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickAsyncImageProvider>
#include <QQuickItem>
#include <QTimer>
#include <memory>

#include <mlt++/Mlt.h>

// Podgląd montażu: MLT renderuje film w mniejszym rozmiarze, dźwięk idzie przez SDL,
// a każda pokazana klatka trafia do PreviewView (tekstura w scenie QML). Po każdej zmianie
// projektu opis MLT jest budowany od nowa, a odtwarzanie wraca w to samo miejsce.
class Player : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int position READ position NOTIFY positionChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit Player(QObject *parent = nullptr);
    ~Player() override;

    QImage image() const { return m_image; }
    int position() const { return m_position; }
    bool playing() const { return m_playing; }
    bool active() const { return m_active; }
    void setActive(bool active);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void seek(int frame);
    Q_INVOKABLE void step(int frames);

Q_SIGNALS:
    void frameChanged();
    void positionChanged();
    void playingChanged();
    void activeChanged();

private:
    QImage m_image;
    std::unique_ptr<Mlt::Profile> m_profile;
    std::unique_ptr<Mlt::Consumer> m_consumer;
    std::unique_ptr<Mlt::Producer> m_producer;
    int m_w = 0, m_h = 0;
    int m_position = 0;
    int m_length = 0;
    bool m_playing = false;
    bool m_active = true;
    QTimer m_rebuild;

    void rebuild();
    void stopConsumer();
    bool startConsumer();
    void showFrame(const QImage &image, int position);
    static void onFrameShow(mlt_properties owner, Player *self, mlt_event_data data);
};

// Obraz z podglądu, wpasowany w element z zachowaniem proporcji
class PreviewView : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(Player *player READ player WRITE setPlayer NOTIFY playerChanged)

public:
    explicit PreviewView(QQuickItem *parent = nullptr);
    Player *player() const { return m_player; }
    void setPlayer(Player *player);

Q_SIGNALS:
    void playerChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;

private:
    QPointer<Player> m_player;
    bool m_dirty = false;
};

// Eksport do pliku: MP4 (H.264/AAC), a gdy w systemie brak kodera H.264 — WebM (VP9/Opus).
class Exporter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString codec READ codec NOTIFY codecChanged)             // "h264", "vp9" albo "" (jeszcze sprawdzam)
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(bool finished READ finished NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString output READ output NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(int secondsLeft READ secondsLeft NOTIFY progressChanged)

public:
    explicit Exporter(QObject *parent = nullptr);
    ~Exporter() override;

    QString codec() const { return m_codec; }
    bool running() const { return m_consumer != nullptr; }
    bool finished() const { return m_finished; }
    QString error() const { return m_error; }
    QString output() const { return m_output; }
    double progress() const { return m_progress; }
    int secondsLeft() const { return m_secondsLeft; }

    Q_INVOKABLE void detect();                                        // sprawdź dostępne kodery (w tle)
    Q_INVOKABLE QString suggestedPath() const;                        // ~/Wideo/Nazwa projektu.mp4
    Q_INVOKABLE QString extension() const { return m_codec == QLatin1String("vp9") ? QStringLiteral("webm") : QStringLiteral("mp4"); }
    Q_INVOKABLE QSize size(int quality) const;                        // 0 — 720p, 1 — 1080p, 2 — 1080p najwyższa
    Q_INVOKABLE bool start(const QString &pathOrUrl, int quality);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reset();

Q_SIGNALS:
    void codecChanged();
    void stateChanged();
    void progressChanged();

private:
    QString m_codec, m_vcodec, m_error, m_output;
    bool m_finished = false;
    bool m_detecting = false;
    double m_progress = 0;
    int m_secondsLeft = -1;
    std::unique_ptr<Mlt::Profile> m_profile;
    std::unique_ptr<Mlt::Producer> m_producer;
    std::unique_ptr<Mlt::Consumer> m_consumer;
    QTimer m_poll;
    QElapsedTimer m_clock;
    int m_length = 0;

    void poll();
    void finish(const QString &error);
};

// Miniatury: image://mthumb/<klatka>/<ścieżka w base64> — klatka filmu albo zdjęcie
class ThumbProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};

// Kształt fali dźwięku: image://mwave/<ścieżka w base64>
class WaveProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};

#include "engine.h"
#include "project.h"

#include <QCache>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QMutex>
#include <QPainter>
#include <QRunnable>
#include <QStandardPaths>
#include <QThread>
#include <QThreadPool>
#include <QQuickWindow>
#include <QSGImageNode>

#include <mlt++/Mlt.h>

namespace {

void setupProfile(Mlt::Profile &p, int w, int h)
{
    const int g = std::gcd(w, h);
    p.set_width(w);
    p.set_height(h);
    p.set_frame_rate(Project::Fps, 1);
    p.set_sample_aspect(1, 1);
    p.set_display_aspect(w / g, h / g);
    p.set_progressive(1);
    p.set_colorspace(709);
    p.set_explicit(1);
}

} // namespace

// ——— Podgląd ———

Player::Player(QObject *parent)
    : QObject(parent)
{
    m_rebuild.setSingleShot(true);
    m_rebuild.setInterval(40);
    connect(&m_rebuild, &QTimer::timeout, this, &Player::rebuild);
    connect(Project::instance(), &Project::changed, &m_rebuild, qOverload<>(&QTimer::start));
    connect(Project::instance(), &Project::openChanged, this, [this] {
        m_position = 0;
        m_playing = false;
        Q_EMIT positionChanged();
        Q_EMIT playingChanged();
    });
    m_rebuild.start();
}

Player::~Player()
{
    stopConsumer();
    m_consumer.reset();
    m_producer.reset();
}

void Player::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    Q_EMIT activeChanged();
    if (!active) {
        pause();
        stopConsumer();          // np. na czas eksportu — nie zabieramy procesora
    } else {
        m_rebuild.start();
    }
}

void Player::setMuted(bool muted)
{
    if (m_muted == muted)
        return;
    m_muted = muted;
    if (m_consumer)
        m_consumer->set("volume", muted ? 0.0 : 1.0);
    Q_EMIT mutedChanged();
}

void Player::stopConsumer()
{
    if (m_consumer && !m_consumer->is_stopped())
        m_consumer->stop();
}

bool Player::startConsumer()
{
    // Dźwięk przez SDL (PipeWire/Pulse); gdy urządzenie dźwiękowe się nie otwiera —
    // sterownik „dummy”, żeby obraz podglądu działał i bez dźwięku
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (!m_consumer) {
            auto c = std::make_unique<Mlt::Consumer>(*m_profile, "sdl2_audio");
            if (!c->is_valid())
                c = std::make_unique<Mlt::Consumer>(*m_profile, "rtaudio");
            if (!c->is_valid())
                return false;
            c->set("terminate_on_pause", 0);
            c->set("real_time", 1);
            c->set("mlt_image_format", "rgba");
            c->set("scrub_audio", 1);
            c->set("channels", 2);
            c->set("frequency", 48000);
            c->listen("consumer-frame-show", this, reinterpret_cast<mlt_listener>(&Player::onFrameShow));
            m_consumer = std::move(c);
        }
        m_consumer->connect(*m_producer);
        m_consumer->set("volume", m_muted ? 0.0 : 1.0);
        if (m_consumer->start() == 0 && !m_consumer->is_stopped())
            return true;
        m_consumer.reset();
        qputenv("SDL_AUDIODRIVER", "dummy");
    }
    return false;
}

void Player::rebuild()
{
    Project *project = Project::instance();
    if (!project->isOpen() || !m_active) {
        stopConsumer();
        m_producer.reset();
        return;
    }
    // Podgląd w mniejszym rozmiarze: dłuższy bok 960 px
    const double k = 960.0 / qMax(project->width(), project->height());
    const int w = qRound(project->width() * k / 2) * 2, h = qRound(project->height() * k / 2) * 2;
    stopConsumer();
    if (!m_profile || w != m_w || h != m_h) {
        m_consumer.reset();
        m_producer.reset();
        m_profile = std::make_unique<Mlt::Profile>();
        setupProfile(*m_profile, w, h);
        m_w = w;
        m_h = h;
    }
    const QByteArray xml = project->xml(w, h).toUtf8();
    auto producer = std::make_unique<Mlt::Producer>(*m_profile, "xml-string", xml.constData());
    if (!producer->is_valid())
        return;
    m_producer = std::move(producer);
    m_length = qMax(1, project->duration());
    m_position = qBound(0, m_position, m_length - 1);
    if (m_playing && m_position >= m_length - 1)
        m_position = 0;
    m_producer->seek(m_position);
    m_producer->set_speed(m_playing ? 1 : 0);
    if (!startConsumer())
        qWarning("aster-montaz: nie udało się uruchomić podglądu MLT");
    else
        m_consumer->set("refresh", 1);
}

void Player::onFrameShow(mlt_properties, Player *self, mlt_event_data data)
{
    // Wątek MLT: obraz klatki do QImage i dalej do wątku głównego
    Mlt::Frame frame(Mlt::EventData(data).to_frame());
    if (!frame.is_valid())
        return;
    mlt_image_format format = mlt_image_rgba;
    int w = self->m_w, h = self->m_h;
    const uint8_t *image = frame.get_image(format, w, h);
    if (!image || format != mlt_image_rgba)
        return;
    const QImage copy = QImage(image, w, h, QImage::Format_RGBA8888).copy();
    const int position = frame.get_position();
    QMetaObject::invokeMethod(self, [self, copy, position] { self->showFrame(copy, position); }, Qt::QueuedConnection);
}

void Player::showFrame(const QImage &image, int position)
{
    m_image = image;
    Q_EMIT frameChanged();
    if (!m_producer)
        return;
    if (m_playing && position != m_position) {
        m_position = position;
        Q_EMIT positionChanged();
        if (position >= m_length - 1)
            pause();
    }
}

void Player::play()
{
    if (!m_producer || m_playing)
        return;
    if (m_position >= m_length - 1)
        seek(0);
    m_playing = true;
    m_producer->set_speed(1);
    if (m_consumer) {
        m_consumer->purge();
        m_consumer->set("refresh", 1);
    }
    Q_EMIT playingChanged();
}

void Player::pause()
{
    if (!m_playing)
        return;
    m_playing = false;
    if (m_producer) {
        m_producer->set_speed(0);
        m_producer->seek(m_position);
    }
    if (m_consumer) {
        m_consumer->purge();
        m_consumer->set("refresh", 1);
    }
    Q_EMIT playingChanged();
}

void Player::toggle()
{
    if (m_playing)
        pause();
    else
        play();
}

void Player::seek(int frame)
{
    frame = qBound(0, frame, qMax(0, m_length - 1));
    if (m_producer) {
        m_producer->seek(frame);
        if (m_consumer) {
            m_consumer->purge();
            m_consumer->set("refresh", 1);
        }
    }
    if (frame != m_position) {
        m_position = frame;
        Q_EMIT positionChanged();
    }
}

void Player::step(int frames)
{
    pause();
    seek(m_position + frames);
}

// ——— Obraz podglądu ———

PreviewView::PreviewView(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void PreviewView::setPlayer(Player *player)
{
    if (m_player == player)
        return;
    if (m_player)
        disconnect(m_player, nullptr, this, nullptr);
    m_player = player;
    if (m_player)
        connect(m_player, &Player::frameChanged, this, [this] { m_dirty = true; update(); });
    Q_EMIT playerChanged();
}

QSGNode *PreviewView::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    const QImage img = m_player ? m_player->image() : QImage();
    if (img.isNull() || width() <= 0 || height() <= 0) {
        delete old;
        return nullptr;
    }
    auto *node = static_cast<QSGImageNode *>(old);
    if (!node) {
        node = window()->createImageNode();
        node->setOwnsTexture(true);
        node->setFiltering(QSGTexture::Linear);
        m_dirty = true;
    }
    if (m_dirty) {
        node->setTexture(window()->createTextureFromImage(img));
        m_dirty = false;
    }
    const QSizeF s = QSizeF(img.size()).scaled(size(), Qt::KeepAspectRatio);
    node->setRect(QRectF((width() - s.width()) / 2, (height() - s.height()) / 2, s.width(), s.height()));
    return node;
}

// ——— Eksport ———

Exporter::Exporter(QObject *parent)
    : QObject(parent)
{
    m_poll.setInterval(200);
    connect(&m_poll, &QTimer::timeout, this, &Exporter::poll);
}

Exporter::~Exporter()
{
    if (m_consumer)
        m_consumer->stop();
}

void Exporter::detect()
{
    if (!m_codec.isEmpty() || m_detecting)
        return;
    m_detecting = true;
    // Próbne zakodowanie kilku klatek: kodery bywają wkompilowane, ale niedostępne
    // (np. OpenH264 bez biblioteki Cisco), więc sama lista z FFmpeg nie wystarcza.
    QThread *t = QThread::create([this] {
        QString found = QStringLiteral("vp9");
        QString vcodec = QStringLiteral("libvpx-vp9");
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
        const bool forceWebm = qEnvironmentVariableIsSet("ASTER_MONTAZ_WEBM");     // do testów ścieżki awaryjnej
        for (const char *candidate : {"libx264", "libopenh264"}) {
            if (forceWebm)
                break;
            const QString file = dir + QStringLiteral("/aster-montaz-test-%1.mp4").arg(QCoreApplication::applicationPid());
            QFile::remove(file);
            Mlt::Profile profile;
            setupProfile(profile, 64, 64);
            Mlt::Producer color(profile, "color", "black");
            color.set("length", 4);
            color.set_in_and_out(0, 3);
            Mlt::Consumer c(profile, "avformat", file.toUtf8().constData());
            c.set("vcodec", candidate);
            c.set("acodec", "aac");
            c.set("real_time", -1);
            c.set("terminate_on_pause", 1);
            c.connect(color);
            c.run();
            bool ok = false;
            if (QFileInfo(file).size() > 0) {
                Mlt::Producer check(profile, nullptr, file.toUtf8().constData());
                // Nazwa dekodera bywa różna (h264, libopenh264) — opis zawsze wymienia H.264
                ok = check.is_valid() && QByteArray(check.get("meta.media.0.codec.long_name")).contains("H.264");
            }
            QFile::remove(file);
            if (ok) {
                found = QStringLiteral("h264");
                vcodec = QString::fromLatin1(candidate);
                break;
            }
        }
        QMetaObject::invokeMethod(this, [this, found, vcodec] {
            m_codec = found;
            m_vcodec = vcodec;
            m_detecting = false;
            Q_EMIT codecChanged();
        }, Qt::QueuedConnection);
    });
    connect(t, &QThread::finished, t, &QObject::deleteLater);
    t->start();
}

QString Exporter::suggestedPath() const
{
    QString name = Project::instance()->name();
    name.replace(QLatin1Char('/'), QLatin1Char('-'));
    const QString dir = Project::instance()->videosDir();
    QDir().mkpath(dir);
    QString path = dir + QLatin1Char('/') + name + QLatin1Char('.') + extension();
    for (int i = 2; QFileInfo::exists(path); ++i)
        path = dir + QLatin1Char('/') + name + QStringLiteral(" (%1).").arg(i) + extension();
    return path;
}

QSize Exporter::size(int quality) const
{
    const Project *p = Project::instance();
    const double k = quality == 0 ? 720.0 / qMin(p->width(), p->height()) : 1.0;
    return QSize(qRound(p->width() * k / 2) * 2, qRound(p->height() * k / 2) * 2);
}

bool Exporter::start(const QString &pathOrUrl, int quality)
{
    if (m_consumer || m_codec.isEmpty())
        return false;
    Project *project = Project::instance();
    m_output = project->toPath(pathOrUrl);
    m_error.clear();
    m_finished = false;
    m_progress = 0;
    m_secondsLeft = -1;
    const QSize s = size(quality);
    m_profile = std::make_unique<Mlt::Profile>();
    setupProfile(*m_profile, s.width(), s.height());
    const QByteArray xml = project->xml(s.width(), s.height()).toUtf8();
    m_producer = std::make_unique<Mlt::Producer>(*m_profile, "xml-string", xml.constData());
    if (!m_producer->is_valid() || project->duration() <= 0) {
        finish(QStringLiteral("Nie udało się przygotować filmu."));
        return false;
    }
    m_length = project->duration();
    m_consumer = std::make_unique<Mlt::Consumer>(*m_profile, "avformat", m_output.toUtf8().constData());
    Mlt::Consumer &c = *m_consumer;
    const int threads = qBound(1, QThread::idealThreadCount(), 16);
    c.set("real_time", -1);
    c.set("terminate_on_pause", 1);
    c.set("threads", threads);
    c.set("channels", 2);
    c.set("frequency", 48000);
    c.set("pix_fmt", "yuv420p");
    const double pixels = double(s.width()) * s.height() / (1920.0 * 1080.0);   // do przeliczenia przepływności
    if (m_codec == QLatin1String("h264")) {
        c.set("f", "mp4");
        c.set("movflags", "+faststart");
        c.set("vcodec", m_vcodec.toUtf8().constData());
        c.set("acodec", "aac");
        c.set("ab", quality == 2 ? "256k" : quality == 1 ? "192k" : "128k");
        if (m_vcodec == QLatin1String("libx264")) {
            c.set("crf", quality == 2 ? 17 : quality == 1 ? 21 : 25);
            c.set("preset", quality == 2 ? "slow" : quality == 1 ? "medium" : "veryfast");
        } else {
            // OpenH264 nie zna CRF — sterujemy przepływnością
            const int mbit = quality == 2 ? 16 : quality == 1 ? 9 : 5;
            c.set("vb", QByteArray::number(qMax(1, qRound(mbit * (quality == 0 ? 1.0 : pixels) * 1000))) + "k");
        }
    } else {
        c.set("f", "webm");
        c.set("vcodec", "libvpx-vp9");
        c.set("acodec", "libopus");
        c.set("ab", quality == 2 ? "192k" : "128k");
        c.set("crf", quality == 2 ? 24 : quality == 1 ? 31 : 36);
        c.set("vb", "0");
        c.set("deadline", "good");
        c.set("cpu-used", quality == 2 ? 2 : quality == 1 ? 4 : 5);
        c.set("row-mt", 1);
    }
    c.connect(*m_producer);
    m_producer->seek(0);
    m_producer->set_speed(1);
    if (c.start() != 0) {
        finish(QStringLiteral("Nie udało się uruchomić kodera."));
        return false;
    }
    m_clock.start();
    m_poll.start();
    Q_EMIT stateChanged();
    Q_EMIT progressChanged();
    return true;
}

void Exporter::poll()
{
    if (!m_consumer)
        return;
    const int pos = m_producer->position();
    m_progress = qBound(0.0, double(pos) / qMax(1, m_length), 1.0);
    if (m_progress > 0.03)
        m_secondsLeft = qRound(m_clock.elapsed() / 1000.0 * (1 - m_progress) / m_progress);
    Q_EMIT progressChanged();
    if (m_consumer->is_stopped())
        finish(QFileInfo(m_output).size() > 0 ? QString() : QStringLiteral("Zapis filmu się nie powiódł."));
}

void Exporter::finish(const QString &error)
{
    m_poll.stop();
    if (m_consumer && !m_consumer->is_stopped())
        m_consumer->stop();
    m_consumer.reset();
    m_producer.reset();
    m_profile.reset();
    m_error = error;
    m_finished = error.isEmpty();
    if (m_finished) {
        m_progress = 1;
        m_secondsLeft = 0;
    }
    Q_EMIT progressChanged();
    Q_EMIT stateChanged();
}

void Exporter::cancel()
{
    if (!m_consumer)
        return;
    m_poll.stop();
    m_consumer->stop();
    m_consumer.reset();
    m_producer.reset();
    QFile::remove(m_output);
    m_progress = 0;
    m_error.clear();
    m_finished = false;
    Q_EMIT progressChanged();
    Q_EMIT stateChanged();
}

void Exporter::reset()
{
    if (m_consumer)
        return;
    m_finished = false;
    m_error.clear();
    m_progress = 0;
    Q_EMIT stateChanged();
    Q_EMIT progressChanged();
}

// ——— Miniatury ———

namespace {

QMutex cacheLock;
QCache<QString, QImage> &thumbCache()
{
    static QCache<QString, QImage> c(400);
    return c;
}

QThreadPool &thumbPool()
{
    static QThreadPool *pool = [] {
        auto *p = new QThreadPool;
        p->setMaxThreadCount(2);
        return p;
    }();
    return *pool;
}

class ThumbResponse : public QQuickImageResponse, public QRunnable
{
public:
    ThumbResponse(const QString &id, const QSize &size)
        : m_id(id), m_size(size)
    {
        setAutoDelete(false);
    }
    QQuickTextureFactory *textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(m_image); }

    void run() override
    {
        const int frame = m_id.section(QLatin1Char('/'), 0, 0).toInt();
        const QString path = QString::fromUtf8(QByteArray::fromBase64(m_id.section(QLatin1Char('/'), 1, 1).toLatin1(), QByteArray::Base64UrlEncoding));
        const QString look = m_id.section(QLatin1Char('/'), 2, 2);      // podgląd filtra kolorów (opcjonalnie)
        const int th = m_size.height() > 0 ? m_size.height() : 96;
        static const QStringList images = {QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"), QStringLiteral("webp"),
                                           QStringLiteral("bmp"), QStringLiteral("gif"), QStringLiteral("heic"), QStringLiteral("avif")};
        const bool image = images.contains(QFileInfo(path).suffix().toLower());
        if (image && look.isEmpty()) {
            QImageReader r(path);
            r.setAutoTransform(true);
            const QSize s = r.size();
            if (s.isValid())
                r.setScaledSize(QSize(qMax(1, s.width() * th / qMax(1, s.height())), th));
            m_image = r.read();
        } else {
            // Każdy wątek trzyma ostatnio otwarty film — taśma klatek jednego klipu nie otwiera pliku za każdym razem
            thread_local QString lastPath;
            thread_local std::unique_ptr<Mlt::Profile> profile;
            thread_local std::unique_ptr<Mlt::Producer> producer;
            if (lastPath != path || !producer) {
                producer.reset();
                profile = std::make_unique<Mlt::Profile>();
                setupProfile(*profile, 320, 180);
                producer = std::make_unique<Mlt::Producer>(*profile, nullptr, path.toUtf8().constData());
                lastPath = path;
                if (producer->is_valid()) {
                    const int vi = producer->get_int("video_index");
                    int w = producer->get_int(QStringLiteral("meta.media.%1.codec.width").arg(vi).toUtf8().constData());
                    int h = producer->get_int(QStringLiteral("meta.media.%1.codec.height").arg(vi).toUtf8().constData());
                    const int rot = qAbs(producer->get_int(QStringLiteral("meta.media.%1.codec.rotate").arg(vi).toUtf8().constData())) % 360;
                    if (rot == 90 || rot == 270)
                        std::swap(w, h);
                    if (image) {
                        QImageReader r(path);
                        r.setAutoTransform(true);
                        w = r.size().width();
                        h = r.size().height();
                    }
                    if (w > 0 && h > 0) {
                        // Profil w proporcjach filmu — bez czarnych pasów na miniaturze
                        const int ph = qMax(2, th / 2 * 2);
                        const int pw = qMax(2, qRound(double(w) * ph / h / 2) * 2);
                        setupProfile(*profile, pw, ph);
                        producer = std::make_unique<Mlt::Producer>(*profile, nullptr, path.toUtf8().constData());
                    }
                }
            }
            if (producer && producer->is_valid()) {
                std::vector<std::unique_ptr<Mlt::Filter>> filters;
                for (const auto &spec : Project::lookFilters(look)) {
                    auto f = std::make_unique<Mlt::Filter>(*profile, spec.first.toUtf8().constData());
                    if (!f->is_valid())
                        continue;
                    for (const auto &prop : spec.second)
                        f->set(prop.first.toUtf8().constData(), prop.second.toUtf8().constData());
                    producer->attach(*f);
                    filters.push_back(std::move(f));
                }
                producer->seek(qBound(0, frame, qMax(0, producer->get_length() - 1)));
                std::unique_ptr<Mlt::Frame> f(producer->get_frame());
                if (f && f->is_valid()) {
                    mlt_image_format fmt = mlt_image_rgba;
                    int w = profile->width(), h = profile->height();
                    f->set("consumer.deinterlacer", "onefield");
                    f->set("consumer.rescale", "bilinear");
                    const uint8_t *img = f->get_image(fmt, w, h);
                    if (img && fmt == mlt_image_rgba)
                        m_image = QImage(img, w, h, QImage::Format_RGBA8888).copy();
                }
                for (const auto &f : filters)
                    producer->detach(*f);
            }
        }
        if (!m_image.isNull()) {
            QMutexLocker lock(&cacheLock);
            thumbCache().insert(m_id + QLatin1Char('@') + QString::number(th), new QImage(m_image));
        }
        Q_EMIT finished();
    }

private:
    QString m_id;
    QSize m_size;
    QImage m_image;
    friend class ::ThumbProvider;
};

// Kształt fali: szczyty głośności każdej klatki dźwięku, rysowane jako słupki
class WaveResponse : public QQuickImageResponse, public QRunnable
{
public:
    WaveResponse(const QString &id, const QSize &size)
        : m_id(id), m_size(size)
    {
        setAutoDelete(false);
    }
    QQuickTextureFactory *textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(m_image); }

    void run() override
    {
        const QString path = QString::fromUtf8(QByteArray::fromBase64(m_id.toLatin1(), QByteArray::Base64UrlEncoding));
        QList<float> peaks;
        {
            Mlt::Profile profile;
            setupProfile(profile, 64, 36);
            Mlt::Producer p(profile, nullptr, path.toUtf8().constData());
            if (p.is_valid()) {
                p.set("video_index", -1);
                const int length = p.get_length();
                peaks.reserve(length);
                for (int i = 0; i < length; ++i) {
                    std::unique_ptr<Mlt::Frame> f(p.get_frame());
                    if (!f || !f->is_valid())
                        break;
                    mlt_audio_format fmt = mlt_audio_s16;
                    int freq = 48000, channels = 2;
                    int samples = mlt_audio_calculate_frame_samples(Project::Fps, freq, i);
                    const auto *data = static_cast<const int16_t *>(f->get_audio(fmt, freq, channels, samples));
                    int peak = 0;
                    for (int k = 0; data && k < samples * channels; ++k)
                        peak = qMax(peak, qAbs(int(data[k])));
                    peaks << peak / 32768.0f;
                }
            }
        }
        const int w = m_size.width() > 0 ? m_size.width() : 1600, h = m_size.height() > 0 ? m_size.height() : 64;
        m_image = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
        m_image.fill(Qt::transparent);
        if (!peaks.isEmpty()) {
            QPainter painter(&m_image);
            painter.setPen(Qt::NoPen);
            painter.setBrush(QColor(255, 255, 255, 150));
            const int bars = w / 3;
            for (int b = 0; b < bars; ++b) {
                const int from = int(qint64(b) * peaks.size() / bars), to = qMax(from + 1, int(qint64(b + 1) * peaks.size() / bars));
                float v = 0;
                for (int i = from; i < to && i < peaks.size(); ++i)
                    v = qMax(v, peaks.at(i));
                const qreal bh = qMax(1.0, std::sqrt(double(v)) * (h - 2));      // pierwiastek — ciche fragmenty też widać
                painter.drawRoundedRect(QRectF(b * 3, (h - bh) / 2, 2, bh), 1, 1);
            }
        }
        {
            QMutexLocker lock(&cacheLock);
            thumbCache().insert(QStringLiteral("wave:") + m_id, new QImage(m_image));
        }
        Q_EMIT finished();
    }

private:
    QString m_id;
    QSize m_size;
    QImage m_image;
    friend class ::WaveProvider;
};

} // namespace

QQuickImageResponse *WaveProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new WaveResponse(id, requestedSize);
    {
        QMutexLocker lock(&cacheLock);
        if (QImage *img = thumbCache().object(QStringLiteral("wave:") + id)) {
            response->m_image = *img;
            QMetaObject::invokeMethod(response, [response] { Q_EMIT response->finished(); }, Qt::QueuedConnection);
            return response;
        }
    }
    thumbPool().start(response);
    return response;
}

QQuickImageResponse *ThumbProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new ThumbResponse(id, requestedSize);
    {
        const int th = requestedSize.height() > 0 ? requestedSize.height() : 96;
        QMutexLocker lock(&cacheLock);
        if (QImage *img = thumbCache().object(id + QLatin1Char('@') + QString::number(th))) {
            response->m_image = *img;
            QMetaObject::invokeMethod(response, [response] { Q_EMIT response->finished(); }, Qt::QueuedConnection);
            return response;
        }
    }
    thumbPool().start(response);
    return response;
}

#include "video.h"

#include <QCollator>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QLocale>
#include <QMediaPlayer>
#include <QMimeDatabase>
#include <QPointer>
#include <QSet>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QTimer>
#include <QUrl>
#include <QVideoFrame>
#include <QVideoSink>
#include <QDBusConnection>
#include <QDBusMessage>

static const int maxRecent = 30;

Video::Video(QObject *parent)
    : QObject(parent)
{
    QSettings s;
    m_recent = s.value(QStringLiteral("recent")).toList();
}

QVariantList Video::recent() const
{
    QVariantList out;
    for (const QVariant &v : m_recent) {
        QVariantMap m = v.toMap();
        const QString path = m.value(QStringLiteral("path")).toString();
        if (!QFileInfo::exists(path))
            continue;
        m.insert(QStringLiteral("name"), fileName(path));
        m.insert(QStringLiteral("thumb"), thumb(path));
        out << m;
    }
    return out;
}

void Video::save()
{
    QSettings s;
    s.setValue(QStringLiteral("recent"), m_recent);
    Q_EMIT recentChanged();
}

void Video::remember(const QString &path, qint64 position, qint64 duration)
{
    if (path.isEmpty())
        return;
    for (int i = 0; i < m_recent.size(); ++i)
        if (m_recent.at(i).toMap().value(QStringLiteral("path")).toString() == path) {
            m_recent.removeAt(i);
            break;
        }
    // Obejrzane do końca — następnym razem od początku
    if (duration > 0 && position > duration * 0.95)
        position = 0;
    m_recent.prepend(QVariantMap{{QStringLiteral("path"), path},
                                 {QStringLiteral("position"), position},
                                 {QStringLiteral("duration"), duration},
                                 {QStringLiteral("time"), QDateTime::currentMSecsSinceEpoch()}});
    while (m_recent.size() > maxRecent)
        m_recent.removeLast();
    save();
}

void Video::forget(const QString &path)
{
    for (int i = 0; i < m_recent.size(); ++i)
        if (m_recent.at(i).toMap().value(QStringLiteral("path")).toString() == path) {
            m_recent.removeAt(i);
            save();
            return;
        }
}

void Video::clearRecent()
{
    m_recent.clear();
    save();
}

qint64 Video::resumePosition(const QString &path) const
{
    for (const QVariant &v : m_recent) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("path")).toString() != path)
            continue;
        const qint64 pos = m.value(QStringLiteral("position")).toLongLong();
        const qint64 dur = m.value(QStringLiteral("duration")).toLongLong();
        if (pos < 15000 || (dur > 0 && pos > dur * 0.95))
            return 0;
        return pos;
    }
    return 0;
}

bool Video::isVideo(const QString &path) const
{
    static QMimeDatabase db;
    const QString mime = db.mimeTypeForFile(path).name();
    return mime.startsWith(QLatin1String("video/")) || mime == QLatin1String("application/x-matroska")
        || mime == QLatin1String("application/vnd.rn-realmedia");
}

QVariantList Video::library() const
{
    QStringList roots{videosDir(), QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)};
    QVariantList out;
    QSet<QString> seen;
    for (const QString &root : roots) {
        if (root.isEmpty() || !QFileInfo(root).isDir())
            continue;
        QDirIterator it(root, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        int scanned = 0;
        while (it.hasNext() && scanned < 20000 && out.size() < 2000) {
            const QString p = it.next();
            ++scanned;
            if (seen.contains(p) || p.contains(QLatin1String("/.")) || !isVideo(p))
                continue;
            seen.insert(p);
            const QFileInfo fi(p);
            out << QVariantMap{{QStringLiteral("path"), p},
                               {QStringLiteral("name"), fileName(p)},
                               {QStringLiteral("thumb"), thumb(p)},
                               {QStringLiteral("modified"), fi.lastModified().toMSecsSinceEpoch()},
                               {QStringLiteral("size"), fi.size()}};
        }
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("modified")).toLongLong() > b.toMap().value(QStringLiteral("modified")).toLongLong();
    });
    return out;
}

QStringList Video::siblings(const QString &path) const
{
    const QFileInfo fi(path);
    QStringList out;
    const auto entries = QDir(fi.absolutePath()).entryInfoList(QDir::Files);
    for (const QFileInfo &e : entries)
        if (isVideo(e.absoluteFilePath()))
            out << e.absoluteFilePath();
    QCollator c;
    c.setNumericMode(true);
    c.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(out.begin(), out.end(), [&c](const QString &a, const QString &b) { return c.compare(a, b) < 0; });
    return out;
}

// „Film.srt”, „Film.pl.srt”, „Film.txt” (MicroDVD/MPL2) obok filmu
QStringList Video::subtitleFiles(const QString &video) const
{
    const QFileInfo fi(video);
    const QString base = fi.completeBaseName();
    static const QStringList exts{QStringLiteral("srt"), QStringLiteral("vtt"), QStringLiteral("txt"), QStringLiteral("sub")};
    QStringList out;
    const auto entries = QDir(fi.absolutePath()).entryInfoList(QDir::Files, QDir::Name);
    for (const QFileInfo &e : entries) {
        if (!exts.contains(e.suffix().toLower()))
            continue;
        const QString b = e.completeBaseName();
        if (b.compare(base, Qt::CaseInsensitive) == 0 || b.startsWith(base + QLatin1Char('.'), Qt::CaseInsensitive))
            out << e.absoluteFilePath();
    }
    return out;
}

static QString decodeText(const QByteArray &data)
{
    if (data.startsWith("\xEF\xBB\xBF"))
        return QString::fromUtf8(data.mid(3));
    if (data.startsWith("\xFF\xFE") || data.startsWith("\xFE\xFF")) {
        auto d = QStringDecoder(data.startsWith("\xFF\xFE") ? QStringDecoder::Utf16LE : QStringDecoder::Utf16BE);
        return d(data.mid(2));
    }
    QStringDecoder utf8(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
    const QString text = utf8(data);
    if (!utf8.hasError())
        return text;
    // Polskie napisy z sieci — najczęściej Windows-1250
    QStringDecoder cp("windows-1250");
    return cp.isValid() ? cp(data) : QString::fromLatin1(data);
}

static qint64 parseTime(const QString &h, const QString &m, const QString &s, const QString &ms)
{
    QString frac = ms.left(3);
    while (frac.size() < 3)
        frac += QLatin1Char('0');
    return ((h.toLongLong() * 60 + m.toLongLong()) * 60 + s.toLongLong()) * 1000 + frac.toLongLong();
}

// Znaczniki <i>, {\an8}; MicroDVD/MPL2: „|” = nowa linia, „/” na początku = kursywa
static QString cleanCue(QString t)
{
    static const QRegularExpression tags(QStringLiteral("<[^>]*>|\\{\\\\[^}]*\\}|\\{[yYcCfFsS]:[^}]*\\}"));
    t.remove(tags);
    t.replace(QLatin1Char('|'), QLatin1Char('\n'));
    QStringList lines = t.split(QLatin1Char('\n'));
    for (QString &l : lines) {
        l = l.trimmed();
        if (l.startsWith(QLatin1Char('/')))
            l = l.mid(1).trimmed();
    }
    lines.removeAll(QString());
    return lines.join(QLatin1Char('\n'));
}

QVariantList Video::loadSubtitles(const QString &path, double fps) const
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly) || f.size() > 8 * 1024 * 1024)
        return {};
    QString text = decodeText(f.readAll());
    text.replace(QStringLiteral("\r\n"), QStringLiteral("\n")).replace(QLatin1Char('\r'), QLatin1Char('\n'));
    if (fps <= 1)
        fps = 23.976;

    QVariantList cues;
    auto add = [&cues](qint64 s, qint64 e, const QString &t) {
        const QString c = cleanCue(t);
        if (!c.isEmpty() && e > s)
            cues << QVariantMap{{QStringLiteral("s"), s}, {QStringLiteral("e"), e}, {QStringLiteral("t"), c}};
    };

    static const QRegularExpression srtTime(QStringLiteral(R"((?:(\d+):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3}))"));
    static const QRegularExpression microdvd(QStringLiteral(R"(^\{(\d+)\}\{(\d*)\}(.*)$)"));
    static const QRegularExpression mpl2(QStringLiteral(R"(^\[(\d+)\]\[(\d*)\](.*)$)"));

    const QStringList lines = text.split(QLatin1Char('\n'));
    // SRT / WebVTT: czas „-->” i tekst do pustej linii
    for (int i = 0; i < lines.size(); ++i) {
        const auto m = srtTime.match(lines.at(i));
        if (!m.hasMatch())
            continue;
        const qint64 s = parseTime(m.captured(1), m.captured(2), m.captured(3), m.captured(4));
        const qint64 e = parseTime(m.captured(5), m.captured(6), m.captured(7), m.captured(8));
        QStringList body;
        while (i + 1 < lines.size() && !lines.at(i + 1).trimmed().isEmpty() && !srtTime.match(lines.at(i + 1)).hasMatch())
            body << lines.at(++i);
        add(s, e, body.join(QLatin1Char('\n')));
    }
    if (cues.isEmpty()) {
        for (const QString &line : lines) {
            if (auto m = microdvd.match(line.trimmed()); m.hasMatch()) {
                const qint64 s = qint64(m.captured(1).toLongLong() * 1000 / fps);
                qint64 e = m.captured(2).isEmpty() ? s + 3000 : qint64(m.captured(2).toLongLong() * 1000 / fps);
                if (m.captured(1) == QLatin1String("1") && m.captured(2) == QLatin1String("1"))
                    continue;                          // {1}{1}23.976 — informacja o klatkażu
                add(s, e, m.captured(3));
            } else if (auto m2 = mpl2.match(line.trimmed()); m2.hasMatch()) {
                const qint64 s = m2.captured(1).toLongLong() * 100;
                const qint64 e = m2.captured(2).isEmpty() ? s + 3000 : m2.captured(2).toLongLong() * 100;
                add(s, e, m2.captured(3));
            }
        }
    }
    std::sort(cues.begin(), cues.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("s")).toLongLong() < b.toMap().value(QStringLiteral("s")).toLongLong();
    });
    return cues;
}

QString Video::toPath(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

QUrl Video::url(const QString &path) const
{
    return QUrl::fromLocalFile(path);
}

QString Video::language(int language) const
{
    if (language <= QLocale::C)
        return {};
    QString name = QLocale(QLocale::Language(language)).nativeLanguageName();
    if (!name.isEmpty())
        name[0] = name[0].toUpper();
    return name;
}

QString Video::fileName(const QString &path) const
{
    return QFileInfo(path).completeBaseName();
}

QString Video::thumb(const QString &path) const
{
    const QFileInfo fi(path);
    return QStringLiteral("image://vthumb/") + QString::fromLatin1(path.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals))
        + QLatin1Char('_') + QString::number(fi.lastModified().toSecsSinceEpoch());
}

QString Video::time(qint64 ms) const
{
    if (ms < 0)
        ms = 0;
    const qint64 s = ms / 1000;
    const QString mm = QString::number(s / 60 % 60), ss = QStringLiteral("%1").arg(s % 60, 2, 10, QLatin1Char('0'));
    if (s >= 3600)
        return QStringLiteral("%1:%2:%3").arg(s / 3600).arg(s / 60 % 60, 2, 10, QLatin1Char('0')).arg(ss);
    return mm + QLatin1Char(':') + ss;
}

QString Video::when(qint64 msecs) const
{
    const QDate d = QDateTime::fromMSecsSinceEpoch(msecs).date();
    const QDate today = QDate::currentDate();
    if (d == today)
        return QStringLiteral("dziś");
    if (d == today.addDays(-1))
        return QStringLiteral("wczoraj");
    const QLocale pl(QLocale::Polish);
    return d.year() == today.year() ? pl.toString(d, QStringLiteral("d MMMM")) : pl.toString(d, QStringLiteral("d MMMM yyyy"));
}

void Video::showInFolder(const QString &path) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                    QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    m << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    if (!QDBusConnection::sessionBus().send(m))
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

QString Video::videosDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
}

// ——— Miniatury ———
// Odtwarzacz bez dźwięku przewija do ok. 15% filmu i bierze pierwszą klatkę po przewinięciu.
// Jedna naraz (kolejka w wątku głównym), wynik w pamięci podręcznej na dysku.
namespace {
class ThumbResponse : public QQuickImageResponse
{
public:
    QImage image;
    QQuickTextureFactory *textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(image); }
    void done(const QImage &img)
    {
        image = img;
        Q_EMIT finished();
    }
};

struct Job {
    QString path, cache;
    QSize size;
    QPointer<ThumbResponse> response;
};

class ThumbQueue : public QObject
{
public:
    static ThumbQueue *instance()
    {
        static ThumbQueue *q = [] {
            auto *t = new ThumbQueue;
            t->moveToThread(QCoreApplication::instance()->thread());
            return t;
        }();
        return q;
    }
    void add(const Job &job)
    {
        QMetaObject::invokeMethod(this, [this, job] {
            m_jobs << job;
            if (!m_busy)
                next();
        }, Qt::QueuedConnection);
    }

private:
    QList<Job> m_jobs;
    bool m_busy = false;

    void next()
    {
        while (!m_jobs.isEmpty() && !m_jobs.first().response)
            m_jobs.removeFirst();
        if (m_jobs.isEmpty()) {
            m_busy = false;
            return;
        }
        m_busy = true;
        const Job job = m_jobs.takeFirst();
        auto *player = new QMediaPlayer(this);
        auto *sink = new QVideoSink(player);
        auto *timeout = new QTimer(player);
        player->setVideoSink(sink);
        auto state = std::make_shared<int>(0);        // 0 ładowanie, 1 przewijanie, 2 gotowe
        auto frames = std::make_shared<int>(0);
        auto finish = [this, player, job, state](const QImage &img) {
            if (*state == 2)
                return;
            *state = 2;
            QImage out = img;
            if (!out.isNull()) {
                out = out.scaled(480, 480, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB32);
                QDir().mkpath(QFileInfo(job.cache).absolutePath());
                out.save(job.cache, "JPG", 85);
            }
            if (job.response)
                job.response->done(out);
            player->stop();
            player->deleteLater();
            QTimer::singleShot(0, this, [this] { next(); });
        };
        connect(sink, &QVideoSink::videoFrameChanged, player, [player, state, frames, finish](const QVideoFrame &f) {
            if (*state != 1 || !f.isValid())
                return;
            // Pierwsza klatka bywa jeszcze sprzed przewinięcia
            const qint64 target = player->property("target").toLongLong();
            if (f.startTime() >= 0 && f.startTime() / 1000 + 1500 < target && ++*frames < 4)
                return;
            finish(f.toImage());
        });
        connect(player, &QMediaPlayer::mediaStatusChanged, player, [player, state, finish](QMediaPlayer::MediaStatus s) {
            if (s == QMediaPlayer::InvalidMedia) {
                finish({});
                return;
            }
            if (*state == 0 && (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)) {
                *state = 1;
                const qint64 d = player->duration();
                const qint64 target = d > 0 ? qMin<qint64>(d * 15 / 100, 90000) : 0;
                player->setProperty("target", target);
                if (target > 0)
                    player->setPosition(target);
                player->play();
            }
        });
        connect(player, &QMediaPlayer::errorOccurred, player, [finish] { finish({}); });
        timeout->setSingleShot(true);
        connect(timeout, &QTimer::timeout, player, [finish] { finish({}); });
        timeout->start(10000);
        player->setSource(QUrl::fromLocalFile(job.path));
    }
};
} // namespace

QQuickImageResponse *VideoThumbProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new ThumbResponse;
    const QString encoded = id.section(QLatin1Char('_'), 0, -2);
    const QString path = QString::fromUtf8(QByteArray::fromBase64(encoded.toLatin1(), QByteArray::Base64UrlEncoding));
    const QFileInfo fi(path);
    const QByteArray key = QCryptographicHash::hash((path + QString::number(fi.lastModified().toSecsSinceEpoch())).toUtf8(), QCryptographicHash::Sha1).toHex();
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/aster/thumbnails/video-")
        + QString::fromLatin1(key) + QStringLiteral(".jpg");
    QImage cached;
    if (cached.load(cache)) {
        QTimer::singleShot(0, response, [response, cached] { response->done(cached); });
        return response;
    }
    if (!fi.exists()) {
        QTimer::singleShot(0, response, [response] { response->done({}); });
        return response;
    }
    // Odpowiedź żyje w wątku wczytywania; kolejka i odtwarzacz — w głównym
    response->moveToThread(QCoreApplication::instance()->thread());
    ThumbQueue::instance()->add({path, cache, requestedSize, response});
    return response;
}

#include "roll.h"

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QMimeType>
#include <QStandardPaths>
#include <QUrl>

namespace {

const QStringList photoExt = {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png")};
const QStringList videoExt = {QStringLiteral("*.mp4"), QStringLiteral("*.webm"), QStringLiteral("*.mkv")};

// Folder „Z aparatu” (albo „Camera Roll” w systemie po angielsku, jeśli już istnieje)
QString rollIn(QStandardPaths::StandardLocation loc)
{
    const QString base = QStandardPaths::writableLocation(loc);
    for (const QString &name : {QStringLiteral("Z aparatu"), QStringLiteral("Camera Roll")})
        if (QFileInfo(base + QLatin1Char('/') + name).isDir())
            return base + QLatin1Char('/') + name;
    return base + QStringLiteral("/Z aparatu");
}

QFileInfo newest(const QString &dir, const QStringList &filters)
{
    const QFileInfoList list = QDir(dir).entryInfoList(filters, QDir::Files, QDir::Time);
    return list.isEmpty() ? QFileInfo() : list.constFirst();
}

} // namespace

Roll::Roll(QObject *parent)
    : QObject(parent)
{
    findLast();
}

QString Roll::photosDir() const { return rollIn(QStandardPaths::PicturesLocation); }
QString Roll::videosDir() const { return rollIn(QStandardPaths::MoviesLocation); }

QString Roll::previewImage() const
{
    if (!qEnvironmentVariableIsSet("ASTER_PREVIEW"))
        return {};
    QDirIterator it(QStandardPaths::writableLocation(QStandardPaths::PicturesLocation), photoExt,
                    QDir::Files, QDirIterator::Subdirectories);
    return it.hasNext() ? QUrl::fromLocalFile(it.next()).toString() : QString();
}

// Ostatnie ujęcie przy starcie — nowszy plik z obu folderów
void Roll::findLast()
{
    const QFileInfo photo = newest(photosDir(), photoExt);
    const QFileInfo video = newest(videosDir(), videoExt);
    if (!photo.exists() && !video.exists())
        return;
    const bool isVideo = video.exists() && (!photo.exists() || video.lastModified() > photo.lastModified());
    m_lastIsVideo = isVideo;
    m_lastPath = isVideo ? video.absoluteFilePath() : photo.absoluteFilePath();
    const QString thumb = isVideo ? QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                                        + QStringLiteral("/last-video.jpg")
                                  : m_lastPath;
    m_lastThumb = QFileInfo::exists(thumb) ? QUrl::fromLocalFile(thumb).toString() : QString();
}

QString Roll::uniqueName(const QString &dir, const QString &prefix, const QString &ext) const
{
    QDir().mkpath(dir);
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH.mm.ss"));
    QString path = QStringLiteral("%1/%2 %3.%4").arg(dir, prefix, stamp, ext);
    for (int n = 2; QFileInfo::exists(path); ++n)
        path = QStringLiteral("%1/%2 %3 (%4).%5").arg(dir, prefix, stamp).arg(n).arg(ext);
    return path;
}

QString Roll::photoPath() const
{
    return uniqueName(photosDir(), QStringLiteral("Zdjęcie"), QStringLiteral("jpg"));
}

QString Roll::videoPath() const
{
    const QString ext = recordFormat().mimeType().preferredSuffix();
    return uniqueName(videosDir(), QStringLiteral("Film"), ext.isEmpty() ? QStringLiteral("mp4") : ext);
}

QString Roll::thumbPath() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/last-video.jpg");
}

void Roll::photoSaved(const QString &path)
{
    m_lastPath = path;
    m_lastIsVideo = false;
    m_lastThumb = QUrl::fromLocalFile(path).toString();
    Q_EMIT lastChanged();
}

void Roll::videoSaved(const QUrl &location, const QString &thumb)
{
    m_lastPath = location.isLocalFile() ? location.toLocalFile() : location.toString();
    m_lastIsVideo = true;
    // Ten sam plik miniatury przy każdym filmie — znacznik czasu w adresie omija pamięć podręczną obrazków
    m_lastThumb = thumb.isEmpty() ? QString()
                                  : QUrl::fromLocalFile(thumb).toString() + QStringLiteral("?")
                                        + QString::number(QDateTime::currentMSecsSinceEpoch());
    Q_EMIT lastChanged();
}

void Roll::openLast() const
{
    if (!m_lastPath.isEmpty() && QFileInfo::exists(m_lastPath))
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastPath));
    else
        openFolder();
}

void Roll::openFolder() const
{
    const QString dir = m_lastIsVideo ? videosDir() : photosDir();
    QDir().mkpath(dir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

void Roll::showLastInFolder() const
{
    if (m_lastPath.isEmpty())
        return openFolder();
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("ShowItems"));
    msg << QStringList{QUrl::fromLocalFile(m_lastPath).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}

// Format nagrywania: MP4 (H.264 + AAC), a gdy system nie ma tych koderów (Fedora bez RPM Fusion) — WebM (VP9/VP8 + Opus)
QMediaFormat Roll::recordFormat() const
{
    struct Choice { QMediaFormat::FileFormat file; QMediaFormat::VideoCodec video; QMediaFormat::AudioCodec audio; };
    const Choice choices[] = {
        {QMediaFormat::MPEG4, QMediaFormat::VideoCodec::H264, QMediaFormat::AudioCodec::AAC},
        {QMediaFormat::WebM, QMediaFormat::VideoCodec::VP9, QMediaFormat::AudioCodec::Opus},
        {QMediaFormat::WebM, QMediaFormat::VideoCodec::VP8, QMediaFormat::AudioCodec::Opus},
        {QMediaFormat::Matroska, QMediaFormat::VideoCodec::VP8, QMediaFormat::AudioCodec::Opus},
    };
    for (const Choice &c : choices) {
        QMediaFormat f(c.file);
        f.setVideoCodec(c.video);
        f.setAudioCodec(c.audio);
        if (f.isSupported(QMediaFormat::Encode))
            return f;
    }
    QMediaFormat fallback(QMediaFormat::MPEG4);
    return fallback;
}

// Tryb kamery: najwyższa rozdzielczość do Full HD przy co najmniej 24 kl./s (płynny podgląd i nagrywanie)
QCameraFormat Roll::bestFormat(const QCameraDevice &device) const
{
    QCameraFormat best;
    auto score = [](const QCameraFormat &f) {
        const QSize s = f.resolution();
        const qint64 area = qint64(s.width()) * s.height();
        const bool smooth = f.maxFrameRate() >= 24;
        const bool fits = s.width() <= 1920 && s.height() <= 1080;
        // Najpierw płynne i mieszczące się w Full HD, potem rozmiar, potem klatki; MJPEG/YUV bez znaczenia
        return (qint64(smooth && fits) << 50) + (area << 8) + qint64(f.maxFrameRate());
    };
    for (const QCameraFormat &f : device.videoFormats())
        if (best.isNull() || score(f) > score(best))
            best = f;
    return best;
}

QString Roll::time(qint64 ms) const
{
    const qint64 s = ms / 1000;
    if (s >= 3600)
        return QStringLiteral("%1:%2:%3").arg(s / 3600).arg(s / 60 % 60, 2, 10, QLatin1Char('0')).arg(s % 60, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(s / 60).arg(s % 60, 2, 10, QLatin1Char('0'));
}

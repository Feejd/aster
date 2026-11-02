#include "photos.h"
#include "photomodel.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QImageWriter>
#include <QLocale>
#include <QMimeData>
#include <QRunnable>
#include <QSettings>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>
#include <cmath>
#include <exiv2/exiv2.hpp>

namespace {

QString home(const QString &sub = {})
{
    return QDir::homePath() + (sub.isEmpty() ? QString() : QLatin1Char('/') + sub);
}

// Folder XDG (Obrazy, Pobrane, Pulpit) — po polsku albo po angielsku, zależnie od systemu
QString xdg(QStandardPaths::StandardLocation loc)
{
    return QStandardPaths::writableLocation(loc);
}

QString screenshotsDir()
{
    const QString pictures = xdg(QStandardPaths::PicturesLocation);
    for (const QString &name : {QStringLiteral("Zrzuty ekranu"), QStringLiteral("Screenshots")})
        if (QFileInfo(pictures + QLatin1Char('/') + name).isDir())
            return pictures + QLatin1Char('/') + name;
    return pictures + QStringLiteral("/Zrzuty ekranu");
}

QString exifString(const Exiv2::ExifData &exif, const char *key)
{
    const auto it = exif.findKey(Exiv2::ExifKey(key));
    if (it == exif.end() || it->count() == 0)
        return {};
    return QString::fromStdString(it->toString()).trimmed();
}

double exifFloat(const Exiv2::ExifData &exif, const char *key)
{
    const auto it = exif.findKey(Exiv2::ExifKey(key));
    if (it == exif.end() || it->count() == 0)
        return 0;
    return it->toFloat(0);
}

QString niceDate(const QDateTime &dt)
{
    const QLocale pl(QLocale::Polish);
    return pl.toString(dt.date(), QStringLiteral("d MMMM yyyy")) + QStringLiteral(", ") + pl.toString(dt.time(), QStringLiteral("HH:mm"));
}

QString sizeText(qint64 b)
{
    const QLocale pl(QLocale::Polish);
    if (b < 1024 * 1024)
        return pl.toString(std::max<qint64>(1, b / 1024)) + QStringLiteral(" KB");
    const double mb = b / (1024.0 * 1024.0);
    return pl.toString(mb, 'f', mb < 10 ? 1 : 0) + QStringLiteral(" MB");
}

class ThumbResponse : public QQuickImageResponse, public QRunnable
{
public:
    ThumbResponse(const QString &id, const QSize &requested)
        : m_id(id)
        , m_requested(requested)
    {
        setAutoDelete(false);
    }
    QQuickTextureFactory *textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(m_image); }
    void run() override
    {
        // id: <ścieżka w base64>_<czas zmiany>
        const int sep = m_id.lastIndexOf(QLatin1Char('_'));
        const QString path = QString::fromUtf8(QByteArray::fromBase64(m_id.left(sep).toLatin1(), QByteArray::Base64UrlEncoding));
        const int side = 360;
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/aster/thumbnails");
        const QString cached = dir + QLatin1Char('/') + QString::fromLatin1(QCryptographicHash::hash(m_id.toUtf8(), QCryptographicHash::Sha1).toHex()) + QStringLiteral(".thumb");
        if (!m_image.load(cached)) {
            QImageReader reader(path);
            reader.setAutoTransform(true);
            const QSize full = reader.size();
            if (full.isValid() && std::min(full.width(), full.height()) > side) {
                const double f = double(side) / std::min(full.width(), full.height());
                reader.setScaledSize(QSize(std::max(1, int(std::round(full.width() * f))), std::max(1, int(std::round(full.height() * f)))));
            }
            m_image = reader.read();
            if (!m_image.isNull() && std::min(m_image.width(), m_image.height()) > side)
                m_image = m_image.scaled(m_image.size().scaled(side, side, Qt::KeepAspectRatioByExpanding), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            if (!m_image.isNull()) {
                QDir().mkpath(dir);
                // Bez przezroczystości — JPEG (mniejszy), z nią — PNG; obie pod tą samą nazwą (QImage rozpozna format)
                m_image.save(cached, m_image.hasAlphaChannel() ? "PNG" : "JPG", 86);
            }
        }
        if (m_requested.isValid() && !m_image.isNull() && (m_image.width() > m_requested.width() * 2 || m_image.height() > m_requested.height() * 2))
            m_image = m_image.scaled(m_requested.expandedTo(QSize(1, 1)) * 2, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        Q_EMIT finished();
    }

private:
    QString m_id;
    QSize m_requested;
    QImage m_image;
};

} // namespace

QQuickImageResponse *ThumbProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new ThumbResponse(id, requestedSize);
    static QThreadPool *pool = [] {
        auto *p = new QThreadPool;
        p->setMaxThreadCount(std::max(2, QThread::idealThreadCount() - 1));
        return p;
    }();
    pool->start(response);
    return response;
}

Photos::Photos(QObject *parent)
    : QObject(parent)
{
    Exiv2::LogMsg::setLevel(Exiv2::LogMsg::mute);
}

QVariantList Photos::places() const
{
    const QString pictures = xdg(QStandardPaths::PicturesLocation);
    const QString downloads = xdg(QStandardPaths::DownloadLocation);
    const QString desktop = xdg(QStandardPaths::DesktopLocation);
    QVariantList out{
        QVariantMap{{QStringLiteral("id"), QStringLiteral("all")}, {QStringLiteral("name"), QStringLiteral("Wszystkie zdjęcia")},
                    {QStringLiteral("icon"), QStringLiteral("image")}, {QStringLiteral("roots"), QStringList{pictures, downloads, desktop}},
                    {QStringLiteral("colors"), QStringList{QStringLiteral("#FFB0DC"), QStringLiteral("#B23DE0")}}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("screenshots")}, {QStringLiteral("name"), QStringLiteral("Zrzuty ekranu")},
                    {QStringLiteral("icon"), QStringLiteral("screenshot")}, {QStringLiteral("roots"), QStringList{screenshotsDir()}},
                    {QStringLiteral("colors"), QStringList{QStringLiteral("#A6E0FF"), QStringLiteral("#5A55EE")}}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("downloads")}, {QStringLiteral("name"), QStringLiteral("Pobrane")},
                    {QStringLiteral("icon"), QStringLiteral("download")}, {QStringLiteral("roots"), QStringList{downloads}},
                    {QStringLiteral("colors"), QStringList{QStringLiteral("#86EFAC"), QStringLiteral("#16A34A")}}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("desktop")}, {QStringLiteral("name"), QStringLiteral("Pulpit")},
                    {QStringLiteral("icon"), QStringLiteral("desktop")}, {QStringLiteral("roots"), QStringList{desktop}},
                    {QStringLiteral("colors"), QStringList{QStringLiteral("#8EA2FF"), QStringLiteral("#5B5BD6")}}},
    };
    const QStringList folders = QSettings().value(QStringLiteral("folders")).toStringList();
    for (const QString &f : folders)
        out << QVariantMap{{QStringLiteral("id"), QLatin1String("folder:") + f}, {QStringLiteral("name"), folderName(f)},
                           {QStringLiteral("icon"), QStringLiteral("folder")}, {QStringLiteral("roots"), QStringList{f}},
                           {QStringLiteral("colors"), QStringList{QStringLiteral("#74CCFF"), QStringLiteral("#2457E6")}},
                           {QStringLiteral("removable"), true}, {QStringLiteral("path"), f}};
    return out;
}

QString Photos::folderName(const QString &path) const
{
    if (QDir::cleanPath(path) == QDir::homePath())
        return QStringLiteral("Folder domowy");
    const QString name = QFileInfo(QDir::cleanPath(path)).fileName();
    return name.isEmpty() ? path : name;
}

QString Photos::plural(int n) const
{
    const int t = n % 100, u = n % 10;
    const QString word = n == 1 ? QStringLiteral("zdjęcie") : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? QStringLiteral("zdjęcia") : QStringLiteral("zdjęć");
    return QLocale(QLocale::Polish).toString(n) + QLatin1Char(' ') + word;
}

void Photos::addFolder(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    const QString path = QDir::cleanPath(url.isLocalFile() ? url.toLocalFile() : pathOrUrl);
    if (!QFileInfo(path).isDir())
        return;
    QSettings s;
    QStringList folders = s.value(QStringLiteral("folders")).toStringList();
    if (!folders.contains(path)) {
        folders << path;
        s.setValue(QStringLiteral("folders"), folders);
        Q_EMIT placesChanged();
    }
}

void Photos::removeFolder(const QString &path)
{
    QSettings s;
    QStringList folders = s.value(QStringLiteral("folders")).toStringList();
    if (folders.removeAll(path)) {
        s.setValue(QStringLiteral("folders"), folders);
        Q_EMIT placesChanged();
    }
}

QVariantMap Photos::info(const QString &path) const
{
    const QFileInfo fi(path);
    QImageReader reader(path);
    reader.setAutoTransform(true);
    QSize size = reader.size();
    const QImageIOHandler::Transformations t = reader.transformation();
    if (t & QImageIOHandler::TransformationRotate90)
        size.transpose();
    const QLocale pl(QLocale::Polish);
    QVariantMap out{{QStringLiteral("path"), path},
                    {QStringLiteral("name"), fi.fileName()},
                    {QStringLiteral("folder"), fi.absolutePath()},
                    {QStringLiteral("folderName"), folderName(fi.absolutePath())},
                    {QStringLiteral("size"), sizeText(fi.size())},
                    {QStringLiteral("format"), QString::fromLatin1(reader.format()).toUpper()},
                    {QStringLiteral("modified"), niceDate(fi.lastModified())}};
    if (size.isValid()) {
        out.insert(QStringLiteral("dimensions"), QStringLiteral("%1 × %2").arg(size.width()).arg(size.height()));
        out.insert(QStringLiteral("megapixels"), pl.toString(size.width() * double(size.height()) / 1e6, 'f', 1) + QStringLiteral(" Mpx"));
    }

    try {
        auto image = Exiv2::ImageFactory::open(path.toStdString());
        image->readMetadata();
        const Exiv2::ExifData &exif = image->exifData();
        if (!exif.empty()) {
            const QString taken = exifString(exif, "Exif.Photo.DateTimeOriginal");
            const QDateTime dt = QDateTime::fromString(taken, QStringLiteral("yyyy:MM:dd HH:mm:ss"));
            if (dt.isValid())
                out.insert(QStringLiteral("taken"), niceDate(dt));
            QString make = exifString(exif, "Exif.Image.Make"), model = exifString(exif, "Exif.Image.Model");
            if (!make.isEmpty() && model.startsWith(make, Qt::CaseInsensitive))
                make.clear();
            const QString camera = (make + QLatin1Char(' ') + model).trimmed();
            if (!camera.isEmpty())
                out.insert(QStringLiteral("camera"), camera);
            const QString lens = exifString(exif, "Exif.Photo.LensModel");
            if (!lens.isEmpty())
                out.insert(QStringLiteral("lens"), lens);
            QStringList settings;
            if (const double f = exifFloat(exif, "Exif.Photo.FNumber"); f > 0)
                settings << QStringLiteral("f/") + pl.toString(f, 'f', f < 10 && std::fmod(f, 1.0) > 0.05 ? 1 : 0);
            if (const double e = exifFloat(exif, "Exif.Photo.ExposureTime"); e > 0)
                settings << (e >= 1 ? pl.toString(e, 'f', e < 10 ? 1 : 0) : QStringLiteral("1/%1").arg(std::round(1 / e))) + QStringLiteral(" s");
            if (const double iso = exifFloat(exif, "Exif.Photo.ISOSpeedRatings"); iso > 0)
                settings << QStringLiteral("ISO %1").arg(qRound(iso));
            if (const double fl = exifFloat(exif, "Exif.Photo.FocalLength"); fl > 0)
                settings << pl.toString(fl, 'f', std::fmod(fl, 1.0) > 0.05 ? 1 : 0) + QStringLiteral(" mm");
            if (!settings.isEmpty())
                out.insert(QStringLiteral("settings"), settings.join(QStringLiteral(" · ")));
        }
    } catch (const std::exception &) {
        // Plik bez metadanych albo w formacie, którego exiv2 nie zna — zostają podstawowe dane
    }
    return out;
}

bool Photos::rotate(const QString &path, bool clockwise)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    // JPEG: tylko znacznik orientacji w EXIF — obraz nie jest kodowany od nowa, więc nie traci jakości
    if (suffix == QLatin1String("jpg") || suffix == QLatin1String("jpeg") || suffix == QLatin1String("jpe") || suffix == QLatin1String("jfif")) {
        try {
            auto image = Exiv2::ImageFactory::open(path.toStdString());
            image->readMetadata();
            Exiv2::ExifData &exif = image->exifData();
            int o = 1;
            const auto it = exif.findKey(Exiv2::ExifKey("Exif.Image.Orientation"));
            if (it != exif.end() && it->count() > 0)
                o = int(it->toInt64(0));
            static const int cw[] = {0, 6, 0, 8, 0, 0, 3, 0, 1};      // 1→6→3→8→1 (bez odbić lustrzanych)
            static const int ccw[] = {0, 8, 0, 6, 0, 0, 1, 0, 3};
            if (o == 1 || o == 3 || o == 6 || o == 8) {
                exif["Exif.Image.Orientation"] = uint16_t(clockwise ? cw[o] : ccw[o]);
                image->writeMetadata();
                return true;
            }
        } catch (const std::exception &) {
        }
    }
    // Inne formaty (i JPEG z odbiciem lustrzanym): obrót obrazu i zapis w tym samym formacie
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QByteArray format = reader.format();
    QImage img = reader.read();
    if (img.isNull() || !QImageWriter::supportedImageFormats().contains(format)) {
        Q_EMIT message(QStringLiteral("Tego zdjęcia nie da się obrócić"));
        return false;
    }
    img = img.transformed(QTransform().rotate(clockwise ? 90 : -90));
    QImageWriter writer(path, format);
    writer.setQuality(95);
    if (!writer.write(img)) {
        Q_EMIT message(QStringLiteral("Nie udało się zapisać obróconego zdjęcia"));
        return false;
    }
    return true;
}

bool Photos::trash(const QString &path)
{
    QString inTrash;
    if (!QFile::moveToTrash(path, &inTrash)) {
        Q_EMIT message(QStringLiteral("Nie udało się przenieść zdjęcia do kosza"));
        return false;
    }
    m_original = path;
    m_trashed = inTrash;
    return true;
}

QString Photos::undoTrash()
{
    if (m_trashed.isEmpty() || QFileInfo::exists(m_original))
        return {};
    if (!QFile::rename(m_trashed, m_original))
        return {};
    // Wpis kosza (Trash/info/<nazwa>.trashinfo) — bez niego plik nie wisi w Koszu
    const QFileInfo t(m_trashed);
    QFile::remove(t.absolutePath() + QStringLiteral("/../info/") + t.fileName() + QStringLiteral(".trashinfo"));
    const QString restored = m_original;
    m_trashed.clear();
    m_original.clear();
    return restored;
}

void Photos::copy(const QString &path) const
{
    auto *mime = new QMimeData;
    mime->setUrls({QUrl::fromLocalFile(path)});
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QImage img = reader.read();
    if (!img.isNull())
        mime->setImageData(img);
    QGuiApplication::clipboard()->setMimeData(mime);
}

void Photos::showInFolder(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

QString Photos::wallpaperCopy(const QString &path) const
{
    // Kopia, bo zdjęcie może zostać przeniesione albo usunięte; nowa nazwa — powłoka wczyta ją od nowa
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster");
    QDir().mkpath(dir);
    for (const QString &old : QDir(dir).entryList({QStringLiteral("wallpaper-*")}, QDir::Files))
        QFile::remove(dir + QLatin1Char('/') + old);
    const QString target = dir + QStringLiteral("/wallpaper-%1.%2").arg(QDateTime::currentMSecsSinceEpoch()).arg(QFileInfo(path).suffix().toLower());
    return QFile::copy(path, target) ? target : QString();
}

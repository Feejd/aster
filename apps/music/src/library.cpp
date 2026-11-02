#include "library.h"

#include <QCollator>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSet>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QtConcurrent>

#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>

namespace {

const QStringList audioSuffixes{
    QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("ogg"), QStringLiteral("oga"), QStringLiteral("opus"),
    QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("wav"), QStringLiteral("wma"), QStringLiteral("aiff"),
    QStringLiteral("aif"), QStringLiteral("ape"), QStringLiteral("wv"), QStringLiteral("mka"), QStringLiteral("alac"),
};

QString cacheDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/aster/music");
}

QString str(const TagLib::String &s)
{
    return QString::fromStdString(s.to8Bit(true)).trimmed();
}

QString prop(const TagLib::PropertyMap &p, const char *key)
{
    const auto it = p.find(key);
    if (it == p.end() || it->second.isEmpty())
        return {};
    return str(it->second.front());
}

int leadingNumber(const QString &s)
{
    int n = 0, i = 0;
    while (i < s.size() && s.at(i).isDigit())
        n = n * 10 + s.at(i++).digitValue();
    return n;
}

// Tagi jednego pliku; brak tytułu → nazwa pliku bez numeru („01 Żagle.mp3” → „Żagle”)
QVariantMap readTags(const QString &path, QByteArray *picture)
{
    const QFileInfo fi(path);
    QVariantMap t;
    t.insert(QStringLiteral("path"), path);
    t.insert(QStringLiteral("mtime"), fi.lastModified().toSecsSinceEpoch());
    TagLib::FileRef f(QFile::encodeName(path).constData(), true, TagLib::AudioProperties::Average);
    QString title, artist, album, albumArtist, genre;
    int track = 0, disc = 0, year = 0;
    qint64 duration = 0;
    if (!f.isNull()) {
        if (f.tag()) {
            title = str(f.tag()->title());
            artist = str(f.tag()->artist());
            album = str(f.tag()->album());
            genre = str(f.tag()->genre());
            track = int(f.tag()->track());
            year = int(f.tag()->year());
        }
        const TagLib::PropertyMap props = f.properties();
        albumArtist = prop(props, "ALBUMARTIST");
        disc = leadingNumber(prop(props, "DISCNUMBER"));
        if (f.audioProperties())
            duration = f.audioProperties()->lengthInMilliseconds();
        if (picture) {
            const auto pics = f.complexProperties("PICTURE");
            for (const auto &p : pics) {
                const auto it = p.find("data");
                if (it != p.end()) {
                    const TagLib::ByteVector data = it->second.toByteVector();
                    *picture = QByteArray(data.data(), int(data.size()));
                    break;
                }
            }
        }
    }
    if (title.isEmpty()) {
        title = fi.completeBaseName();
        static const QRegularExpression num(QStringLiteral("^\\d{1,3}[\\s._-]+"));
        title.remove(num);
        title.replace(QLatin1Char('_'), QLatin1Char(' '));
    }
    t.insert(QStringLiteral("title"), title);
    t.insert(QStringLiteral("artist"), artist);
    t.insert(QStringLiteral("album"), album);
    t.insert(QStringLiteral("albumArtist"), albumArtist);
    t.insert(QStringLiteral("genre"), genre);
    t.insert(QStringLiteral("track"), track);
    t.insert(QStringLiteral("disc"), disc);
    t.insert(QStringLiteral("year"), year);
    t.insert(QStringLiteral("duration"), duration);
    return t;
}

QString albumKey(const QVariantMap &t)
{
    const QString album = t.value(QStringLiteral("album")).toString();
    const QString aa = t.value(QStringLiteral("albumArtist")).toString();
    const QString dir = QFileInfo(t.value(QStringLiteral("path")).toString()).absolutePath();
    if (album.isEmpty())
        return QStringLiteral("dir:") + dir;          // bez albumu — jeden „album” na folder
    if (!aa.isEmpty())
        return aa.toLower() + QChar(0x1f) + album.toLower();
    return dir + QChar(0x1f) + album.toLower();       // składanka bez wykonawcy albumu — po folderze
}

// Okładka albumu: z tagów albo obraz w folderze; zapisywana raz, pomniejszona
QString saveCover(const QString &key, const QByteArray &embedded, const QString &dir)
{
    const QString file = cacheDir() + QStringLiteral("/covers/")
        + QString::fromLatin1(QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex()) + QStringLiteral(".jpg");
    if (QFileInfo::exists(file))
        return file;
    if (embedded.isEmpty() && dir.isEmpty())
        return {};
    QImage img;
    if (!embedded.isEmpty())
        img.loadFromData(embedded);
    if (img.isNull()) {
        static const QStringList names{QStringLiteral("cover"), QStringLiteral("folder"), QStringLiteral("front"), QStringLiteral("album"), QStringLiteral("albumart")};
        const auto entries = QDir(dir).entryInfoList({QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"), QStringLiteral("*.webp")}, QDir::Files);
        for (const QFileInfo &e : entries)
            if (names.contains(e.completeBaseName().toLower()) && img.load(e.absoluteFilePath()))
                break;
        if (img.isNull() && entries.size() == 1)
            img.load(entries.first().absoluteFilePath());
    }
    if (img.isNull())
        return {};
    QDir().mkpath(QFileInfo(file).absolutePath());
    img.scaled(600, 600, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB32).save(file, "JPG", 88);
    return file;
}

// Cały skan (w osobnym wątku): pliki → tagi (z pamięci, gdy plik się nie zmienił) → okładki
QVariantList scan(const QStringList &roots)
{
    QHash<QString, QVariantMap> cached;
    {
        QFile f(cacheDir() + QStringLiteral("/library.json"));
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
            for (const QJsonValue &v : arr) {
                const QVariantMap m = v.toObject().toVariantMap();
                cached.insert(m.value(QStringLiteral("path")).toString(), m);
            }
        }
    }
    QVariantList tracks;
    QSet<QString> seen;
    QHash<QString, QString> covers;             // klucz albumu → plik okładki
    QSet<QString> coverTried;
    for (const QString &root : roots) {
        QDirIterator it(root, QDir::Files, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
        while (it.hasNext() && tracks.size() < 100000) {
            const QString path = it.next();
            if (seen.contains(path) || path.contains(QLatin1String("/.")) || !audioSuffixes.contains(it.fileInfo().suffix().toLower()))
                continue;
            seen.insert(path);
            QVariantMap t = cached.value(path);
            if (t.isEmpty() || t.value(QStringLiteral("mtime")).toLongLong() != it.fileInfo().lastModified().toSecsSinceEpoch())
                t = readTags(path, nullptr);
            const QString key = albumKey(t);
            t.insert(QStringLiteral("albumKey"), key);
            // Okładka raz na album: gotowa w pamięci podręcznej, z tagów tego utworu albo obraz z folderu
            if (!coverTried.contains(key)) {
                coverTried.insert(key);
                const QString dir = QFileInfo(path).absolutePath();
                QString cover = saveCover(key, {}, QString());
                if (cover.isEmpty()) {
                    QByteArray picture;
                    readTags(path, &picture);
                    cover = saveCover(key, picture, dir);
                }
                covers.insert(key, cover);
            }
            tracks << t;
        }
    }
    for (QVariant &v : tracks) {
        QVariantMap t = v.toMap();
        t.insert(QStringLiteral("cover"), covers.value(t.value(QStringLiteral("albumKey")).toString()));
        v = t;
    }
    // Zapamiętaj
    QJsonArray arr;
    for (const QVariant &v : std::as_const(tracks))
        arr.append(QJsonObject::fromVariantMap(v.toMap()));
    QDir().mkpath(cacheDir());
    QSaveFile f(cacheDir() + QStringLiteral("/library.json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
        f.commit();
    }
    return tracks;
}

} // namespace

Library::Library(QObject *parent)
    : QObject(parent)
{
    // Najpierw to, co już znamy (natychmiast), potem skan w tle
    QFile f(cacheDir() + QStringLiteral("/library.json"));
    if (f.open(QIODevice::ReadOnly)) {
        QVariantList list;
        const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
        for (const QJsonValue &v : arr)
            list << v.toObject().toVariantMap();
        apply(list);
    }
    rescan();
}

QStringList Library::roots() const
{
    QStringList r{musicDir()};
    const QStringList extra = QSettings().value(QStringLiteral("folders")).toStringList();
    for (const QString &p : extra)
        if (!r.contains(p))
            r << p;
    return r;
}

QVariantList Library::folders() const
{
    QVariantList out;
    const QStringList r = roots();
    for (int i = 0; i < r.size(); ++i)
        out << QVariantMap{{QStringLiteral("path"), r.at(i)},
                           {QStringLiteral("name"), QFileInfo(r.at(i)).fileName()},
                           {QStringLiteral("removable"), i > 0}};
    return out;
}

void Library::rescan()
{
    const int gen = ++m_generation;
    if (!m_loading) {
        m_loading = true;
        Q_EMIT loadingChanged();
    }
    const QStringList r = roots();
    auto future = QtConcurrent::run([r] { return scan(r); });
    auto *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this, [this, watcher, gen] {
        watcher->deleteLater();
        if (gen != m_generation)
            return;
        apply(watcher->result());
        m_loading = false;
        Q_EMIT loadingChanged();
    });
    watcher->setFuture(future);
}

void Library::addFolder(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    const QString path = QDir::cleanPath(url.isLocalFile() ? url.toLocalFile() : pathOrUrl);
    QSettings s;
    QStringList list = s.value(QStringLiteral("folders")).toStringList();
    if (path.isEmpty() || list.contains(path) || path == musicDir())
        return;
    list << path;
    s.setValue(QStringLiteral("folders"), list);
    Q_EMIT foldersChanged();
    rescan();
}

void Library::removeFolder(const QString &path)
{
    QSettings s;
    QStringList list = s.value(QStringLiteral("folders")).toStringList();
    list.removeAll(path);
    s.setValue(QStringLiteral("folders"), list);
    Q_EMIT foldersChanged();
    rescan();
}

// Utwory → albumy → wykonawcy (posortowane po polsku)
void Library::apply(const QVariantList &input)
{
    QCollator c(QLocale(QLocale::Polish));
    c.setNumericMode(true);
    c.setCaseSensitivity(Qt::CaseInsensitive);
    const QString unknownArtist = QStringLiteral("Nieznany wykonawca");

    struct Album {
        QString key, title, artist, cover, folder;
        int year = 0;
        qint64 duration = 0;
        QSet<QString> artists;
        QVariantList tracks;
    };
    QHash<QString, Album> albums;
    QVariantList tracks;
    tracks.reserve(input.size());
    for (const QVariant &v : input) {
        QVariantMap t = v.toMap();
        const QString key = t.value(QStringLiteral("albumKey")).toString();
        const QString artist = t.value(QStringLiteral("artist")).toString();
        if (artist.isEmpty())
            t.insert(QStringLiteral("artist"), unknownArtist);
        Album &a = albums[key];
        if (a.key.isEmpty()) {
            a.key = key;
            a.title = t.value(QStringLiteral("album")).toString();
            if (a.title.isEmpty())
                a.title = QFileInfo(QFileInfo(t.value(QStringLiteral("path")).toString()).absolutePath()).fileName();
            a.artist = t.value(QStringLiteral("albumArtist")).toString();
            a.cover = t.value(QStringLiteral("cover")).toString();
            a.folder = QFileInfo(t.value(QStringLiteral("path")).toString()).absolutePath();
        }
        a.year = qMax(a.year, t.value(QStringLiteral("year")).toInt());
        a.duration += t.value(QStringLiteral("duration")).toLongLong();
        a.artists.insert(t.value(QStringLiteral("artist")).toString());
        if (a.cover.isEmpty())
            a.cover = t.value(QStringLiteral("cover")).toString();
        tracks << t;
    }
    // Wykonawca albumu: z tagu, jedyny wykonawca utworów albo „Różni wykonawcy”
    for (auto it = albums.begin(); it != albums.end(); ++it)
        if (it->artist.isEmpty())
            it->artist = it->artists.size() == 1 ? *it->artists.begin() : QStringLiteral("Różni wykonawcy");
    for (QVariant &v : tracks) {
        QVariantMap t = v.toMap();
        const Album &a = albums[t.value(QStringLiteral("albumKey")).toString()];
        t.insert(QStringLiteral("albumTitle"), a.title);
        t.insert(QStringLiteral("albumArtistShown"), a.artist);
        if (t.value(QStringLiteral("cover")).toString().isEmpty())
            t.insert(QStringLiteral("cover"), a.cover);
        v = t;
    }
    std::sort(tracks.begin(), tracks.end(), [&c](const QVariant &va, const QVariant &vb) {
        const QVariantMap a = va.toMap(), b = vb.toMap();
        int r = c.compare(a.value(QStringLiteral("albumArtistShown")).toString(), b.value(QStringLiteral("albumArtistShown")).toString());
        if (r) return r < 0;
        r = c.compare(a.value(QStringLiteral("albumTitle")).toString(), b.value(QStringLiteral("albumTitle")).toString());
        if (r) return r < 0;
        if (a.value(QStringLiteral("disc")).toInt() != b.value(QStringLiteral("disc")).toInt())
            return a.value(QStringLiteral("disc")).toInt() < b.value(QStringLiteral("disc")).toInt();
        if (a.value(QStringLiteral("track")).toInt() != b.value(QStringLiteral("track")).toInt())
            return a.value(QStringLiteral("track")).toInt() < b.value(QStringLiteral("track")).toInt();
        return c.compare(a.value(QStringLiteral("path")).toString(), b.value(QStringLiteral("path")).toString()) < 0;
    });
    m_byPath.clear();
    for (int i = 0; i < tracks.size(); ++i) {
        const QVariantMap t = tracks.at(i).toMap();
        m_byPath.insert(t.value(QStringLiteral("path")).toString(), i);
        albums[t.value(QStringLiteral("albumKey")).toString()].tracks << t;
    }

    QVariantList albumList;
    QHash<QString, QVariantList> byArtist;
    QHash<QString, int> artistSongs;
    QHash<QString, QString> artistCover;
    for (const Album &a : std::as_const(albums)) {
        QVariantMap m{{QStringLiteral("key"), a.key}, {QStringLiteral("title"), a.title}, {QStringLiteral("artist"), a.artist},
                      {QStringLiteral("year"), a.year}, {QStringLiteral("cover"), a.cover}, {QStringLiteral("duration"), a.duration},
                      {QStringLiteral("count"), a.tracks.size()}, {QStringLiteral("folder"), a.folder}};
        albumList << m;
        for (const QString &artist : a.artists) {
            artistSongs[artist] += 0;
            if (artistCover.value(artist).isEmpty())
                artistCover[artist] = a.cover;
        }
        byArtist[a.artist] << m;
    }
    for (const QVariant &v : std::as_const(tracks))
        artistSongs[v.toMap().value(QStringLiteral("artist")).toString()]++;
    std::sort(albumList.begin(), albumList.end(), [&c](const QVariant &a, const QVariant &b) {
        return c.compare(a.toMap().value(QStringLiteral("title")).toString(), b.toMap().value(QStringLiteral("title")).toString()) < 0;
    });
    m_albumIndex.clear();
    for (int i = 0; i < albumList.size(); ++i)
        m_albumIndex.insert(albumList.at(i).toMap().value(QStringLiteral("key")).toString(), i);

    QVariantList artistList;
    for (auto it = artistSongs.cbegin(); it != artistSongs.cend(); ++it)
        artistList << QVariantMap{{QStringLiteral("name"), it.key()}, {QStringLiteral("songs"), it.value()},
                                  {QStringLiteral("albums"), byArtist.value(it.key()).size()}, {QStringLiteral("cover"), artistCover.value(it.key())}};
    std::sort(artistList.begin(), artistList.end(), [&c, &unknownArtist](const QVariant &a, const QVariant &b) {
        const QString na = a.toMap().value(QStringLiteral("name")).toString(), nb = b.toMap().value(QStringLiteral("name")).toString();
        if ((na == unknownArtist) != (nb == unknownArtist))
            return nb == unknownArtist;
        return c.compare(na, nb) < 0;
    });

    // Lista utworów albumu trzymana osobno (album() ją zwraca), żeby siatka albumów była lekka
    m_albumTracks.clear();
    for (const Album &a : std::as_const(albums))
        m_albumTracks.insert(a.key, a.tracks);
    m_tracks = tracks;
    m_albums = albumList;
    m_artists = artistList;
    Q_EMIT changed();
}

QVariantMap Library::album(const QString &key) const
{
    const int i = m_albumIndex.value(key, -1);
    if (i < 0)
        return {};
    QVariantMap m = m_albums.at(i).toMap();
    m.insert(QStringLiteral("tracks"), m_albumTracks.value(key));
    return m;
}

QVariantMap Library::artist(const QString &name) const
{
    QVariantList albums, tracks;
    QSet<QString> keys;
    for (const QVariant &v : m_tracks) {
        const QVariantMap t = v.toMap();
        if (t.value(QStringLiteral("artist")).toString() != name && t.value(QStringLiteral("albumArtistShown")).toString() != name)
            continue;
        tracks << t;
        keys.insert(t.value(QStringLiteral("albumKey")).toString());
    }
    for (const QVariant &v : m_albums)
        if (keys.contains(v.toMap().value(QStringLiteral("key")).toString()))
            albums << v;
    std::sort(albums.begin(), albums.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("year")).toInt() > b.toMap().value(QStringLiteral("year")).toInt();
    });
    return {{QStringLiteral("name"), name}, {QStringLiteral("albums"), albums}, {QStringLiteral("tracks"), tracks}};
}

QVariantList Library::tracksFor(const QStringList &paths) const
{
    QVariantList out;
    for (const QString &p : paths) {
        const int i = m_byPath.value(p, -1);
        if (i >= 0) {
            out << m_tracks.at(i);
            continue;
        }
        if (!QFileInfo::exists(p))
            continue;
        // Spoza biblioteki (np. otwarty z Plików)
        QByteArray picture;
        QVariantMap t = readTags(p, &picture);
        const QString key = albumKey(t);
        t.insert(QStringLiteral("albumKey"), key);
        t.insert(QStringLiteral("cover"), saveCover(key, picture, QFileInfo(p).absolutePath()));
        if (t.value(QStringLiteral("artist")).toString().isEmpty())
            t.insert(QStringLiteral("artist"), QStringLiteral("Nieznany wykonawca"));
        t.insert(QStringLiteral("albumTitle"), t.value(QStringLiteral("album")));
        out << t;
    }
    return out;
}

void Library::openFiles(const QStringList &files)
{
    Q_EMIT openRequested(files);
}

void Library::showInFolder(const QString &path) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                    QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    m << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    if (!QDBusConnection::sessionBus().send(m))
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

QString Library::time(qint64 ms) const
{
    const qint64 s = qMax<qint64>(0, ms) / 1000;
    if (s >= 3600)
        return QStringLiteral("%1:%2:%3").arg(s / 3600).arg(s / 60 % 60, 2, 10, QLatin1Char('0')).arg(s % 60, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(s / 60).arg(s % 60, 2, 10, QLatin1Char('0'));
}

QString Library::total(qint64 ms) const
{
    const qint64 min = (ms + 30000) / 60000;
    if (min >= 60)
        return QStringLiteral("%1 godz. %2 min").arg(min / 60).arg(min % 60);
    return QStringLiteral("%1 min").arg(qMax<qint64>(1, min));
}

static QString plural(int n, const char *one, const char *few, const char *many)
{
    const int d = n % 10, h = n % 100;
    const char *w = n == 1 ? one : (d >= 2 && d <= 4 && (h < 12 || h > 14)) ? few : many;
    return QString::number(n) + QLatin1Char(' ') + QString::fromUtf8(w);
}

QString Library::songs(int n) const { return plural(n, "utwór", "utwory", "utworów"); }
QString Library::albumsCount(int n) const { return plural(n, "album", "albumy", "albumów"); }

QString Library::musicDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
}

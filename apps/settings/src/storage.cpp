#include "storage.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <QtConcurrent>

#include <sys/stat.h>

namespace {

// Zajęte miejsce (bloki na dysku, nie długość pliku) bez wchodzenia w dowiązania i inne systemy plików
qint64 du(const QString &path, dev_t dev)
{
    struct stat st;
    const QByteArray p = QFile::encodeName(path);
    if (::lstat(p.constData(), &st) != 0 || st.st_dev != dev)
        return 0;
    qint64 sum = qint64(st.st_blocks) * 512;
    if (!S_ISDIR(st.st_mode))
        return sum;
    QDirIterator it(path, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    while (it.hasNext())
        sum += du(it.next(), dev);
    return sum;
}

struct Scan {
    QVariantList categories, largest;
    qint64 total = 0, used = 0;
};

QString human(qint64 bytes)
{
    const QLocale pl(QLocale::Polish);
    if (bytes < 1000)
        return pl.toString(bytes) + QStringLiteral(" B");
    const char *units[] = {"KB", "MB", "GB", "TB"};
    double v = bytes;
    int u = -1;
    while (v >= 1000 && u < 3) {
        v /= 1000;
        ++u;
    }
    return pl.toString(v, 'f', v < 10 ? 1 : 0) + QLatin1Char(' ') + QLatin1String(units[u]);
}

Scan run()
{
    Scan s;
    const QString home = QDir::homePath();
    const QStorageInfo root = QStorageInfo::root();
    s.total = root.bytesTotal();
    s.used = root.bytesTotal() - root.bytesFree();
    struct stat hs;
    ::lstat(QFile::encodeName(home).constData(), &hs);
    struct stat rs;
    ::lstat("/", &rs);

    auto loc = [](QStandardPaths::StandardLocation l) { return QDir::cleanPath(QStandardPaths::writableLocation(l)); };
    struct Cat {
        const char *id, *name, *color, *icon;
        QString path;
        qint64 size = 0;
    };
    QList<Cat> cats{
        {"docs", "Dokumenty", "#3B82F6", "doc", loc(QStandardPaths::DocumentsLocation)},
        {"pictures", "Obrazy", "#EC4899", "image", loc(QStandardPaths::PicturesLocation)},
        {"videos", "Wideo", "#8B5CF6", "video", loc(QStandardPaths::MoviesLocation)},
        {"music", "Muzyka", "#F97316", "music", loc(QStandardPaths::MusicLocation)},
        {"downloads", "Pobrane", "#14B8A6", "download", loc(QStandardPaths::DownloadLocation)},
        {"desktop", "Pulpit", "#0EA5E9", "desktop", loc(QStandardPaths::DesktopLocation)},
        {"temp", "Pliki tymczasowe", "#EAB308", "clock", home + QStringLiteral("/.cache")},
        {"trash", "Kosz", "#94A3B8", "trash", home + QStringLiteral("/.local/share/Trash")},
        {"flatpak", "Aplikacje (Flatpak)", "#22C55E", "apps", home + QStringLiteral("/.local/share/flatpak")},
    };
    // Kategorie z folderu domowego; reszta domowego → „Inne pliki”
    QHash<QString, int> byPath;
    for (int i = 0; i < cats.size(); ++i)
        if (!cats[i].path.isEmpty() && cats[i].path != home)
            byPath.insert(cats[i].path, i);
    qint64 other = 0;
    QList<QPair<QString, qint64>> top;
    QDirIterator it(home, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    while (it.hasNext()) {
        const QString p = it.next();
        if (p == home + QStringLiteral("/.local")) {
            // .local: kosz i Flatpak osobno, reszta — inne
            QDirIterator lt(p, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden);
            while (lt.hasNext()) {
                const QString lp = lt.next();
                if (lp == p + QStringLiteral("/share")) {
                    QDirIterator st(lp, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden);
                    while (st.hasNext()) {
                        const QString sp = st.next();
                        const qint64 sz = du(sp, hs.st_dev);
                        if (byPath.contains(sp))
                            cats[byPath.value(sp)].size += sz;
                        else
                            other += sz;
                    }
                } else {
                    other += du(lp, hs.st_dev);
                }
            }
            continue;
        }
        const qint64 sz = du(p, hs.st_dev);
        if (byPath.contains(p))
            cats[byPath.value(p)].size += sz;
        else
            other += sz;
        if (it.fileInfo().isDir() && !it.fileName().startsWith(QLatin1Char('.')))
            top.append({p, sz});
    }
    // Największe foldery: w folderze domowym i o poziom niżej w dużych kategoriach
    for (const Cat &c : std::as_const(cats)) {
        if (c.path.isEmpty() || QString::fromLatin1(c.id) == QLatin1String("temp") || QString::fromLatin1(c.id) == QLatin1String("trash"))
            continue;
        QDirIterator sub(c.path, QDir::Dirs | QDir::NoDotAndDotDot);
        while (sub.hasNext()) {
            const QString p = sub.next();
            top.append({p, du(p, hs.st_dev)});
        }
    }
    std::sort(top.begin(), top.end(), [](const auto &a, const auto &b) { return a.second > b.second; });
    for (int i = 0; i < top.size() && s.largest.size() < 8; ++i) {
        if (top.at(i).second < 1024 * 1024)
            break;
        QString rel = top.at(i).first.mid(home.size() + 1);
        s.largest << QVariantMap{{QStringLiteral("name"), rel}, {QStringLiteral("path"), top.at(i).first},
                                 {QStringLiteral("size"), top.at(i).second}, {QStringLiteral("sizeText"), human(top.at(i).second)}};
    }

    qint64 homeSum = other;
    for (const Cat &c : std::as_const(cats))
        homeSum += c.size;
    // Flatpak systemowy liczony do aplikacji
    qint64 systemFlatpak = QFileInfo::exists(QStringLiteral("/var/lib/flatpak")) ? du(QStringLiteral("/var/lib/flatpak"), rs.st_dev) : 0;
    for (Cat &c : cats)
        if (QString::fromLatin1(c.id) == QLatin1String("flatpak"))
            c.size += systemFlatpak;
    // System i aplikacje: wszystko zajęte na dysku poza folderem domowym (gdy dom jest na tym samym dysku)
    const qint64 system = qMax<qint64>(0, s.used - (hs.st_dev == rs.st_dev ? homeSum : 0) - systemFlatpak);

    QVariantList list;
    list << QVariantMap{{QStringLiteral("id"), QStringLiteral("system")}, {QStringLiteral("name"), QStringLiteral("System i aplikacje")},
                        {QStringLiteral("size"), system}, {QStringLiteral("sizeText"), human(system)}, {QStringLiteral("color"), QStringLiteral("#64748B")},
                        {QStringLiteral("icon"), QStringLiteral("aster")}, {QStringLiteral("path"), QString()}};
    for (const Cat &c : std::as_const(cats)) {
        if (c.size <= 0 && QString::fromLatin1(c.id) != QLatin1String("temp") && QString::fromLatin1(c.id) != QLatin1String("trash"))
            continue;
        list << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(c.id)}, {QStringLiteral("name"), QString::fromUtf8(c.name)},
                            {QStringLiteral("size"), c.size}, {QStringLiteral("sizeText"), human(c.size)}, {QStringLiteral("color"), QString::fromLatin1(c.color)},
                            {QStringLiteral("icon"), QString::fromLatin1(c.icon)}, {QStringLiteral("path"), c.path}};
    }
    list << QVariantMap{{QStringLiteral("id"), QStringLiteral("other")}, {QStringLiteral("name"), QStringLiteral("Inne pliki")},
                        {QStringLiteral("size"), other}, {QStringLiteral("sizeText"), human(other)}, {QStringLiteral("color"), QStringLiteral("#A78BFA")},
                        {QStringLiteral("icon"), QStringLiteral("folder")}, {QStringLiteral("path"), home}};
    std::sort(list.begin() + 1, list.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("size")).toLongLong() > b.toMap().value(QStringLiteral("size")).toLongLong();
    });
    s.categories = list;
    return s;
}

} // namespace

Storage::Storage(QObject *parent)
    : QObject(parent)
{
}

QString Storage::size(qint64 bytes) const
{
    return human(bytes);
}

QString Storage::summary() const
{
    if (m_total <= 0)
        return {};
    return human(m_used) + QStringLiteral(" zajęte z ") + human(m_total);
}

QVariantList Storage::drives() const
{
    QVariantList out;
    const auto volumes = QStorageInfo::mountedVolumes();
    for (const QStorageInfo &v : volumes) {
        const QString dev = QString::fromUtf8(v.device());
        const QString path = v.rootPath();
        if (!v.isValid() || !v.isReady() || !dev.startsWith(QLatin1String("/dev/")) || dev.startsWith(QLatin1String("/dev/loop")))
            continue;
        const bool system = path == QLatin1String("/");
        if (!system && !path.startsWith(QLatin1String("/run/media/")) && !path.startsWith(QLatin1String("/media/")) && !path.startsWith(QLatin1String("/mnt/")))
            continue;
        const qint64 total = v.bytesTotal(), free = v.bytesAvailable();
        out << QVariantMap{{QStringLiteral("name"), system ? QStringLiteral("Dysk systemowy") : (v.displayName().isEmpty() ? QFileInfo(path).fileName() : v.displayName())},
                           {QStringLiteral("path"), path}, {QStringLiteral("system"), system},
                           {QStringLiteral("freeText"), human(free) + QStringLiteral(" wolne z ") + human(total)},
                           {QStringLiteral("usedRatio"), total > 0 ? double(total - free) / double(total) : 0.0}};
    }
    return out;
}

void Storage::scan()
{
    if (m_scanning)
        return;
    m_scanning = true;
    Q_EMIT changed();
    auto *w = new QFutureWatcher<Scan>(this);
    connect(w, &QFutureWatcher<Scan>::finished, this, [this, w] {
        w->deleteLater();
        const Scan s = w->result();
        m_categories = s.categories;
        m_largest = s.largest;
        m_total = s.total;
        m_used = s.used;
        m_scanning = false;
        Q_EMIT changed();
    });
    w->setFuture(QtConcurrent::run(run));
}

static void clearDir(const QString &dir)
{
    QDirIterator it(dir, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    while (it.hasNext()) {
        const QString p = it.next();
        const QFileInfo fi = it.fileInfo();
        if (fi.isDir() && !fi.isSymLink())
            QDir(p).removeRecursively();
        else
            QFile::remove(p);
    }
}

// Pamięć podręczna programów — odtwarzają ją same (miniatury, pliki z sieci itp.)
void Storage::cleanTemp()
{
    const QString cache = QDir::homePath() + QStringLiteral("/.cache");
    auto *w = new QFutureWatcher<void>(this);
    connect(w, &QFutureWatcher<void>::finished, this, [this, w] {
        w->deleteLater();
        Q_EMIT message(QStringLiteral("Usunięto pliki tymczasowe"));
        scan();
    });
    w->setFuture(QtConcurrent::run([cache] { clearDir(cache); }));
}

void Storage::emptyTrash()
{
    const QString trash = QDir::homePath() + QStringLiteral("/.local/share/Trash");
    auto *w = new QFutureWatcher<void>(this);
    connect(w, &QFutureWatcher<void>::finished, this, [this, w] {
        w->deleteLater();
        Q_EMIT message(QStringLiteral("Kosz jest pusty"));
        scan();
    });
    w->setFuture(QtConcurrent::run([trash] {
        clearDir(trash + QStringLiteral("/files"));
        clearDir(trash + QStringLiteral("/info"));
        QFile::remove(trash + QStringLiteral("/metadata"));
    }));
}

void Storage::open(const QString &path) const
{
    QProcess::startDetached(QStringLiteral("aster-files"), {path.isEmpty() ? QStringLiteral("/") : path});
}

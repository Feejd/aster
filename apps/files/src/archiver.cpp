#include "archiver.h"

#include <KProtocolInfo>

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QStringDecoder>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>
#include <QtConcurrent>

#include <archive.h>
#include <archive_entry.h>

namespace {

struct Result {
    bool ok = false;
    bool needPassword = false;
    bool wrongPassword = false;
    QString message;
    QString path;
};

QString localPath(const QString &urlOrPath)
{
    const QUrl url(urlOrPath);
    return url.isLocalFile() ? url.toLocalFile() : urlOrPath;
}

// „Zdjęcia.tar.gz” → „Zdjęcia”
QString archiveBaseName(const QString &path)
{
    QString name = QFileInfo(path).fileName();
    static const QStringList multi{QStringLiteral(".tar.gz"), QStringLiteral(".tar.xz"), QStringLiteral(".tar.bz2"),
                                   QStringLiteral(".tar.zst"), QStringLiteral(".tar.lz"), QStringLiteral(".tar.lzma")};
    for (const QString &m : multi)
        if (name.endsWith(m, Qt::CaseInsensitive))
            return name.left(name.size() - m.size());
    const int dot = name.lastIndexOf(QLatin1Char('.'));
    return dot > 0 ? name.left(dot) : name;
}

// Wolna nazwa w folderze: „Raport”, „Raport (2)”…; ext — z kropką albo pusty
QString freePath(const QString &dir, const QString &base, const QString &ext)
{
    QString p = dir + QLatin1Char('/') + base + ext;
    for (int n = 2; QFileInfo::exists(p) || QFileInfo(p).isSymLink(); ++n)
        p = dir + QLatin1Char('/') + base + QStringLiteral(" (%1)").arg(n) + ext;
    return p;
}

// Nazwa wpisu: UTF-8, a gdy nie jest poprawnym UTF-8 — CP852 (ZIP-y z polskiego Windowsa)
QString entryName(archive_entry *e)
{
    const char *raw = archive_entry_pathname(e);
    if (raw) {
        const QByteArray bytes(raw);
        QStringDecoder utf8(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
        const QString s = utf8(bytes);
        if (!utf8.hasError())
            return s;
        QStringDecoder cp("IBM852");
        if (cp.isValid())
            return cp(bytes);
        return QString::fromLatin1(bytes);
    }
    const char *u = archive_entry_pathname_utf8(e);
    return u ? QString::fromUtf8(u) : QString();
}

// Bezpieczna ścieżka względna albo pusta (wpis pomijany)
QString safeRelative(QString name)
{
    name.replace(QLatin1Char('\\'), QLatin1Char('/'));
    while (name.startsWith(QLatin1String("./")))
        name = name.mid(2);
    if (name.startsWith(QLatin1Char('/')) || name.isEmpty())
        return {};
    const QStringList parts = name.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    for (const QString &p : parts)
        if (p == QLatin1String(".."))
            return {};
    return parts.join(QLatin1Char('/'));
}

// ZIP bez znacznika UTF-8: nazwy z polskiego Windowsa są w CP852, a z Linuksa/macOS — zwykle w UTF-8.
// Szybki przegląd (tylko nagłówki): jeśli któraś nazwa nie jest poprawnym UTF-8 — CP852.
QByteArray zipCharset(const QString &path)
{
    archive *a = archive_read_new();
    archive_read_support_format_zip(a);
    archive_read_set_options(a, "zip:hdrcharset=UTF-8");
    QByteArray cs = "UTF-8";
    if (archive_read_open_filename(a, QFile::encodeName(path).constData(), 1 << 16) == ARCHIVE_OK) {
        archive_entry *e;
        int rc, n = 0;
        while ((rc = archive_read_next_header(a, &e)) != ARCHIVE_EOF && rc >= ARCHIVE_WARN && n++ < 5000) {
            const char *raw = archive_entry_pathname(e);
            bool valid = raw != nullptr;
            if (valid) {
                QStringDecoder utf8(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
                (void)utf8(QByteArray(raw));
                valid = !utf8.hasError();
            }
            if (rc == ARCHIVE_WARN || !valid) {
                cs = "CP852";
                break;
            }
            archive_read_data_skip(a);
        }
    }
    archive_read_free(a);
    return cs;
}

bool isPasswordError(archive *a)
{
    const QString err = QString::fromUtf8(archive_error_string(a) ? archive_error_string(a) : "").toLower();
    return err.contains(QLatin1String("passphrase")) || err.contains(QLatin1String("decrypt")) || err.contains(QLatin1String("password"))
        || err.contains(QLatin1String("encrypted"));
}

Result doExtract(const QString &archivePath, const QString &destDir, const QString &password, std::atomic<double> &progress,
                 std::atomic<bool> &cancel)
{
    Result r;
    const qint64 total = qMax<qint64>(1, QFileInfo(archivePath).size());
    archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    if (!password.isEmpty())
        archive_read_add_passphrase(a, password.toUtf8().constData());
    static QMimeDatabase db;
    if (db.mimeTypeForFile(archivePath).name() == QLatin1String("application/zip"))
        archive_read_set_options(a, ("zip:hdrcharset=" + zipCharset(archivePath)).constData());
    if (archive_read_open_filename(a, QFile::encodeName(archivePath).constData(), 1 << 16) != ARCHIVE_OK) {
        r.message = QStringLiteral("Nie udało się otworzyć archiwum — plik jest uszkodzony albo to nie archiwum");
        archive_read_free(a);
        return r;
    }

    // Najpierw do ukrytego folderu tymczasowego obok; na końcu jedna rzecz w środku → ona sama,
    // więcej → folder z nazwą archiwum. Anulowanie / błąd → folder tymczasowy znika.
    const QString parent = destDir.isEmpty() ? QFileInfo(archivePath).absolutePath() : destDir;
    const QString temp = freePath(parent, QStringLiteral(".aster-wypakowywanie-") + archiveBaseName(archivePath), QString());
    if (!QDir().mkpath(temp)) {
        r.message = QStringLiteral("Brak uprawnień do zapisu w tym folderze");
        archive_read_free(a);
        return r;
    }

    archive *disk = archive_write_disk_new();
    // Ścieżki są bezwzględne (do folderu tymczasowego), więc ochronę robimy sami: safeRelative()
    // odrzuca „..” i „/”, a wpisy pod dowiązaniem symbolicznym z tego samego archiwum są pomijane
    archive_write_disk_set_options(disk, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_SECURE_NODOTDOT);
    archive_write_disk_set_standard_lookup(disk);

    QStringList links;                                   // dowiązania symboliczne z archiwum (względne)
    bool failed = false, sawEncrypted = false;
    int skipped = 0, count = 0;
    archive_entry *e = nullptr;
    int rc;
    while (!cancel && (rc = archive_read_next_header(a, &e)) != ARCHIVE_EOF) {
        if (rc < ARCHIVE_WARN) {
            failed = true;
            if (isPasswordError(a))
                sawEncrypted = true;
            break;
        }
        if (archive_entry_is_encrypted(e)) {
            sawEncrypted = true;
            if (password.isEmpty()) {
                r.needPassword = true;
                failed = true;
                break;
            }
        }
        const QString rel = safeRelative(entryName(e));
        const bool underLink = std::any_of(links.cbegin(), links.cend(), [&rel](const QString &l) { return rel.startsWith(l + QLatin1Char('/')); });
        if (rel.isEmpty() || underLink) {
            ++skipped;
            archive_read_data_skip(a);
            continue;
        }
        archive_entry_set_pathname_utf8(e, (temp + QLatin1Char('/') + rel).toUtf8().constData());
        if (const char *link = archive_entry_hardlink(e)) {
            const QString l = safeRelative(QString::fromUtf8(link));
            if (l.isEmpty()) {
                ++skipped;
                archive_read_data_skip(a);
                continue;
            }
            archive_entry_set_hardlink_utf8(e, (temp + QLatin1Char('/') + l).toUtf8().constData());
        }
        if (archive_entry_filetype(e) == AE_IFLNK)
            links << rel;
        // Foldery bez prawa zapisu/wejścia (zdarza się w ZIP-ach) — i tak do otwarcia
        if (archive_entry_filetype(e) == AE_IFDIR)
            archive_entry_set_perm(e, archive_entry_perm(e) | 0700);
        else if (archive_entry_filetype(e) == AE_IFREG)
            archive_entry_set_perm(e, archive_entry_perm(e) | 0600);
        if (archive_write_header(disk, e) < ARCHIVE_WARN) {
            ++skipped;
            continue;
        }
        const void *buf;
        size_t size;
        la_int64_t offset;
        while (!cancel) {
            rc = archive_read_data_block(a, &buf, &size, &offset);
            if (rc == ARCHIVE_EOF)
                break;
            if (rc < ARCHIVE_WARN) {
                failed = true;
                if (sawEncrypted || isPasswordError(a)) {
                    sawEncrypted = true;
                    if (password.isEmpty())
                        r.needPassword = true;
                    else
                        r.wrongPassword = true;
                }
                break;
            }
            if (archive_write_data_block(disk, buf, size, offset) < ARCHIVE_WARN) {
                failed = true;
                r.message = QStringLiteral("Brak miejsca na dysku albo brak uprawnień do zapisu");
                break;
            }
            progress = qMin(0.99, double(archive_filter_bytes(a, -1)) / total);
        }
        archive_write_finish_entry(disk);
        if (failed)
            break;
        ++count;
    }
    archive_write_close(disk);
    archive_write_free(disk);
    archive_read_free(a);

    if (cancel || failed) {
        QDir(temp).removeRecursively();
        if (cancel)
            r.message = QStringLiteral("Anulowano wypakowywanie");
        else if (r.needPassword)
            r.message = QStringLiteral("To archiwum jest chronione hasłem");
        else if (r.wrongPassword)
            r.message = QStringLiteral("Nieprawidłowe hasło");
        else if (r.message.isEmpty())
            r.message = sawEncrypted ? QStringLiteral("Nie udało się odszyfrować archiwum (ten rodzaj szyfrowania nie jest obsługiwany)")
                                     : QStringLiteral("Archiwum jest uszkodzone — wypakowano tylko część i usunięto ją");
        return r;
    }

    const QStringList inside = QDir(temp).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    if (inside.size() == 1) {
        const QFileInfo only(temp + QLatin1Char('/') + inside.first());
        const QString ext = only.isDir() ? QString() : (only.suffix().isEmpty() ? QString() : QLatin1Char('.') + only.suffix());
        const QString base = only.isDir() ? only.fileName() : only.completeBaseName();
        const QString target = freePath(parent, base, ext);
        QDir().rename(only.absoluteFilePath(), target);
        QDir().rmdir(temp);
        r.path = target;
    } else {
        const QString target = freePath(parent, archiveBaseName(archivePath), QString());
        QDir().rename(temp, target);
        r.path = target;
    }
    r.ok = true;
    r.message = skipped > 0 ? QStringLiteral("Wypakowano „%1” (pominięto niebezpieczne wpisy: %2)").arg(QFileInfo(r.path).fileName()).arg(skipped)
                            : QStringLiteral("Wypakowano „%1”").arg(QFileInfo(r.path).fileName());
    progress = 1;
    return r;
}

Result doCompress(const QStringList &paths, const QString &out, const QString &format, const QString &password,
                  std::atomic<double> &progress, std::atomic<bool> &cancel)
{
    Result r;
    // Lista: (pełna ścieżka, nazwa w archiwum) — względem folderu pierwszego elementu
    QList<QPair<QString, QString>> items;
    qint64 total = 0;
    for (const QString &p : paths) {
        const QFileInfo fi(p);
        const QDir base = fi.absoluteDir();
        items.append({fi.absoluteFilePath(), fi.fileName()});
        if (fi.isDir() && !fi.isSymLink()) {
            QDirIterator it(fi.absoluteFilePath(), QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
                            QDirIterator::Subdirectories);
            while (it.hasNext()) {
                const QString f = it.next();
                items.append({f, base.relativeFilePath(f)});
                if (it.fileInfo().isFile() && !it.fileInfo().isSymLink())
                    total += it.fileInfo().size();
            }
        } else if (fi.isFile()) {
            total += fi.size();
        }
    }
    total = qMax<qint64>(1, total);

    const QString part = QFileInfo(out).absolutePath() + QStringLiteral("/.") + QFileInfo(out).fileName() + QStringLiteral(".part");
    archive *a = archive_write_new();
    if (format == QLatin1String("7z")) {
        archive_write_set_format_7zip(a);
    } else if (format.startsWith(QLatin1String("tar"))) {
        archive_write_set_format_pax_restricted(a);
        if (format == QLatin1String("tar.gz"))
            archive_write_add_filter_gzip(a);
        else if (format == QLatin1String("tar.xz"))
            archive_write_add_filter_xz(a);
        else if (format == QLatin1String("tar.zst"))
            archive_write_add_filter_zstd(a);
    } else {
        archive_write_set_format_zip(a);
        if (!password.isEmpty()) {
            if (archive_write_set_options(a, "zip:encryption=aes256") != ARCHIVE_OK
                || archive_write_set_passphrase(a, password.toUtf8().constData()) != ARCHIVE_OK) {
                r.message = QStringLiteral("Szyfrowanie ZIP nie jest dostępne w tym systemie");
                archive_write_free(a);
                return r;
            }
        }
    }
    if (archive_write_open_filename(a, QFile::encodeName(part).constData()) != ARCHIVE_OK) {
        r.message = QStringLiteral("Brak uprawnień do zapisu w tym folderze");
        archive_write_free(a);
        return r;
    }
    archive *disk = archive_read_disk_new();
    archive_read_disk_set_standard_lookup(disk);
    archive_read_disk_set_symlink_physical(disk);

    bool failed = false;
    qint64 done = 0;
    QByteArray buf(1 << 16, Qt::Uninitialized);
    for (const auto &[path, name] : std::as_const(items)) {
        if (cancel)
            break;
        archive_entry *e = archive_entry_new();
        const QByteArray native = QFile::encodeName(path);
        archive_entry_copy_sourcepath(e, native.constData());
        if (archive_read_disk_entry_from_file(disk, e, -1, nullptr) != ARCHIVE_OK) {
            archive_entry_free(e);
            continue;                                   // np. gniazdo albo brak dostępu — pomiń
        }
        archive_entry_set_pathname_utf8(e, name.toUtf8().constData());
        if (archive_write_header(a, e) < ARCHIVE_WARN) {
            archive_entry_free(e);
            failed = true;
            break;
        }
        if (archive_entry_filetype(e) == AE_IFREG && archive_entry_size(e) > 0) {
            QFile f(path);
            if (f.open(QIODevice::ReadOnly)) {
                while (!cancel) {
                    const qint64 n = f.read(buf.data(), buf.size());
                    if (n <= 0)
                        break;
                    if (archive_write_data(a, buf.constData(), size_t(n)) < 0) {
                        failed = true;
                        break;
                    }
                    done += n;
                    progress = qMin(0.99, double(done) / total);
                }
            }
        }
        archive_entry_free(e);
        if (failed)
            break;
    }
    archive_read_free(disk);
    if (archive_write_close(a) != ARCHIVE_OK)
        failed = true;
    archive_write_free(a);

    if (cancel || failed) {
        QFile::remove(part);
        r.message = cancel ? QStringLiteral("Anulowano pakowanie") : QStringLiteral("Nie udało się spakować — brak miejsca na dysku?");
        return r;
    }
    QFile::rename(part, out);
    r.ok = true;
    r.path = out;
    r.message = QStringLiteral("Spakowano do „%1”").arg(QFileInfo(out).fileName());
    progress = 1;
    return r;
}

} // namespace

Archiver::Archiver(QObject *parent)
    : QObject(parent)
    , m_tick(new QTimer(this))
{
    // Postęp z wątków — odświeżany kilka razy na sekundę, gdy coś trwa
    m_tick->setInterval(200);
    connect(m_tick, &QTimer::timeout, this, &Archiver::jobsChanged);
}

Archiver::~Archiver()
{
    for (const auto &j : std::as_const(m_jobs))
        j->cancel = true;
    QThreadPool::globalInstance()->waitForDone(5000);
}

QVariantList Archiver::jobs() const
{
    QVariantList out;
    for (const auto &j : m_jobs)
        out << QVariantMap{{QStringLiteral("id"), j->id}, {QStringLiteral("title"), j->title},
                           {QStringLiteral("progress"), j->progress.load()}, {QStringLiteral("extract"), j->extract}};
    return out;
}

std::shared_ptr<Archiver::Job> Archiver::addJob(const QString &title, bool extract)
{
    auto job = std::make_shared<Job>();
    job->id = m_next++;
    job->title = title;
    job->extract = extract;
    m_jobs << job;
    m_tick->start();
    Q_EMIT jobsChanged();
    return job;
}

void Archiver::removeJob(int id)
{
    for (int i = 0; i < m_jobs.size(); ++i)
        if (m_jobs.at(i)->id == id) {
            m_jobs.removeAt(i);
            break;
        }
    if (m_jobs.isEmpty())
        m_tick->stop();
    Q_EMIT jobsChanged();
}

void Archiver::cancel(int id)
{
    for (const auto &j : std::as_const(m_jobs))
        if (j->id == id)
            j->cancel = true;
}

bool Archiver::isArchive(const QString &url) const
{
    static QMimeDatabase db;
    const QString path = localPath(url);
    if (!QFileInfo(path).isFile())
        return false;
    static const QStringList mimes{
        QStringLiteral("application/zip"), QStringLiteral("application/x-7z-compressed"), QStringLiteral("application/vnd.rar"),
        QStringLiteral("application/x-rar"), QStringLiteral("application/x-tar"), QStringLiteral("application/x-compressed-tar"),
        QStringLiteral("application/x-xz-compressed-tar"), QStringLiteral("application/x-bzip2-compressed-tar"),
        QStringLiteral("application/x-zstd-compressed-tar"), QStringLiteral("application/x-cd-image"), QStringLiteral("application/vnd.ms-cab-compressed"),
        QStringLiteral("application/x-lzma-compressed-tar"), QStringLiteral("application/x-cpio"), QStringLiteral("application/x-iso9660-image"),
    };
    return mimes.contains(db.mimeTypeForFile(path).name());
}

QString Archiver::browseUrl(const QString &url) const
{
    static QMimeDatabase db;
    const QString path = localPath(url);
    if (!QFileInfo(path).isFile())
        return {};
    const QString mime = db.mimeTypeForFile(path).name();
    QString scheme;
    if (mime == QLatin1String("application/zip"))
        scheme = QStringLiteral("zip");
    else if (mime == QLatin1String("application/x-tar") || mime == QLatin1String("application/x-compressed-tar")
             || mime == QLatin1String("application/x-xz-compressed-tar") || mime == QLatin1String("application/x-bzip2-compressed-tar"))
        scheme = QStringLiteral("tar");
    if (scheme.isEmpty() || !KProtocolInfo::isKnownProtocol(scheme))
        return {};
    QUrl u = QUrl::fromLocalFile(path + QLatin1Char('/'));
    u.setScheme(scheme);
    return u.toString();
}

QString Archiver::archiveOf(const QString &url) const
{
    const QUrl u(url);
    if (u.scheme() != QLatin1String("zip") && u.scheme() != QLatin1String("tar"))
        return {};
    QString path = u.path();
    while (!path.isEmpty() && path != QLatin1String("/")) {
        if (QFileInfo(path).isFile())
            return QUrl::fromLocalFile(path).toString();
        path = path.section(QLatin1Char('/'), 0, -2);
    }
    return {};
}

QString Archiver::suggestedName(const QStringList &urls, const QString &format) const
{
    if (urls.isEmpty())
        return {};
    const QFileInfo fi(localPath(urls.first()));
    const QString base = fi.isDir() ? fi.fileName() : fi.completeBaseName();
    const QString ext = QLatin1Char('.') + (format.isEmpty() ? QStringLiteral("zip") : format);
    return QFileInfo(freePath(fi.absolutePath(), base.isEmpty() ? QStringLiteral("Archiwum") : base, ext)).fileName();
}

int Archiver::extract(const QString &archiveUrl, const QString &destDirUrl, const QString &password)
{
    const QString path = localPath(archiveUrl);
    const QString dest = destDirUrl.isEmpty() ? QString() : localPath(destDirUrl);
    auto job = addJob(QStringLiteral("Wypakowywanie „%1”").arg(QFileInfo(path).fileName()), true);
    auto future = QtConcurrent::run([job, path, dest, password] { return doExtract(path, dest, password, job->progress, job->cancel); });
    auto *w = new QFutureWatcher<Result>(this);
    connect(w, &QFutureWatcher<Result>::finished, this, [this, w, job, archiveUrl, destDirUrl] {
        w->deleteLater();
        const Result r = w->result();
        removeJob(job->id);
        if (r.needPassword || r.wrongPassword)
            Q_EMIT passwordNeeded(archiveUrl, destDirUrl, r.wrongPassword);
        else
            Q_EMIT finished(job->id, r.ok, r.message, r.path.isEmpty() ? QString() : QUrl::fromLocalFile(r.path).toString());
    });
    w->setFuture(future);
    return job->id;
}

int Archiver::compress(const QStringList &urls, const QString &name, const QString &format, const QString &password)
{
    QStringList paths;
    for (const QString &u : urls)
        paths << localPath(u);
    if (paths.isEmpty())
        return 0;
    QString fileName = name.trimmed();
    fileName.replace(QLatin1Char('/'), QLatin1Char('-'));
    const QString ext = QLatin1Char('.') + format;
    if (!fileName.endsWith(ext, Qt::CaseInsensitive))
        fileName += ext;
    const QString dir = QFileInfo(paths.first()).absolutePath();
    const QString out = freePath(dir, fileName.left(fileName.size() - ext.size()), ext);
    auto job = addJob(QStringLiteral("Pakowanie do „%1”").arg(QFileInfo(out).fileName()), false);
    auto future = QtConcurrent::run([job, paths, out, format, password] { return doCompress(paths, out, format, password, job->progress, job->cancel); });
    auto *w = new QFutureWatcher<Result>(this);
    connect(w, &QFutureWatcher<Result>::finished, this, [this, w, job] {
        w->deleteLater();
        const Result r = w->result();
        removeJob(job->id);
        Q_EMIT finished(job->id, r.ok, r.message, r.path.isEmpty() ? QString() : QUrl::fromLocalFile(r.path).toString());
    });
    w->setFuture(future);
    return job->id;
}

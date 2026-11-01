#include "fileops.h"

#include <KIO/CopyJob>
#include <KIO/DeleteJob>
#include <KIO/EmptyTrashJob>
#include <KIO/FileUndoManager>
#include <KIO/MkdirJob>
#include <KIO/OpenUrlJob>
#include <KIO/RestoreJob>
#include <KIO/StoredTransferJob>

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QMimeData>
#include <QMimeDatabase>
#include <QProcess>
#include <QStandardPaths>
#include <QStorageInfo>

using KIO::FileUndoManager;

static const QLatin1String cutMime("application/x-kde-cutselection");

static QString trashFilesDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash/files");
}

Files::Files(QObject *parent)
    : QObject(parent)
{
    connect(FileUndoManager::self(), &FileUndoManager::undoAvailable, this, &Files::undoChanged);
    connect(FileUndoManager::self(), &FileUndoManager::undoTextChanged, this, &Files::undoChanged);
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &Files::clipboardChanged);

    QDir().mkpath(trashFilesDir());
    m_trashWatcher.addPath(trashFilesDir());
    connect(&m_trashWatcher, &QFileSystemWatcher::directoryChanged, this, &Files::trashChanged);
}

QString Files::formatSize(KIO::filesize_t bytes)
{
    // Jednostki dziesiętne jak w Windowsie/macOS, przecinek po polsku: 1,4 MB
    const QLocale pl(QLocale::Polish);
    if (bytes < 1000)
        return pl.toString(static_cast<qulonglong>(bytes)) + QStringLiteral(" B");
    const char *units[] = {"KB", "MB", "GB", "TB"};
    double v = bytes;
    int u = -1;
    while (v >= 1000 && u < 3) {
        v /= 1000;
        ++u;
    }
    return pl.toString(v, 'f', v < 10 ? 1 : 0) + QLatin1Char(' ') + QLatin1String(units[u]);
}

bool Files::canUndo() const
{
    return FileUndoManager::self()->isUndoAvailable();
}

QString Files::undoText() const
{
    return FileUndoManager::self()->undoText();
}

QStringList Files::clipboardUrls() const
{
    QStringList out;
    if (const QMimeData *mime = QGuiApplication::clipboard()->mimeData())
        for (const QUrl &u : mime->urls())
            out << u.toString();
    return out;
}

bool Files::clipboardCut() const
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    return mime && mime->data(cutMime) == "1";
}

int Files::trashCount() const
{
    return QDir(trashFilesDir()).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot).size();
}

QString Files::homeUrl() const
{
    return QUrl::fromLocalFile(QDir::homePath()).toString();
}

QVariantList Files::places() const
{
    struct Place {
        QStandardPaths::StandardLocation loc;
        const char *name;
        const char *icon;
    };
    const Place list[] = {
        {QStandardPaths::DesktopLocation, "Pulpit", "desktop"},
        {QStandardPaths::DocumentsLocation, "Dokumenty", "doc"},
        {QStandardPaths::DownloadLocation, "Pobrane", "download"},
        {QStandardPaths::PicturesLocation, "Obrazy", "image"},
        {QStandardPaths::MusicLocation, "Muzyka", "music"},
        {QStandardPaths::MoviesLocation, "Wideo", "video"},
    };
    QVariantList out;
    out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Folder domowy")},
                       {QStringLiteral("icon"), QStringLiteral("home")},
                       {QStringLiteral("url"), homeUrl()}};
    for (const Place &p : list) {
        const QString path = QStandardPaths::writableLocation(p.loc);
        if (path.isEmpty() || path == QDir::homePath() || !QFileInfo(path).isDir())
            continue;
        out << QVariantMap{{QStringLiteral("name"), QString::fromUtf8(p.name)},
                           {QStringLiteral("icon"), QString::fromLatin1(p.icon)},
                           {QStringLiteral("url"), QUrl::fromLocalFile(path).toString()}};
    }
    return out;
}

QVariantMap Files::systemDrive() const
{
    const QStorageInfo root = QStorageInfo::root();
    const qint64 total = root.bytesTotal();
    const qint64 free = root.bytesAvailable();
    return {
        {QStringLiteral("url"), QStringLiteral("file:///")},
        {QStringLiteral("freeText"), formatSize(free) + QStringLiteral(" wolne z ") + formatSize(total)},
        {QStringLiteral("usedRatio"), total > 0 ? double(total - free) / double(total) : 0.0},
    };
}

QString Files::displayName(const QString &urlString) const
{
    const QUrl url(urlString);
    if (url.scheme() == QLatin1String("trash"))
        return url.path().length() > 1 ? url.fileName() : QStringLiteral("Kosz");
    if (!url.isLocalFile())
        return url.toDisplayString();
    const QString path = QDir::cleanPath(url.toLocalFile());
    if (path == QDir::homePath())
        return QStringLiteral("Folder domowy");
    if (path == QLatin1String("/"))
        return QStringLiteral("Komputer");
    for (const QVariant &v : places()) {
        const QVariantMap m = v.toMap();
        if (QUrl(m.value(QStringLiteral("url")).toString()).toLocalFile() == path)
            return m.value(QStringLiteral("name")).toString();
    }
    return QFileInfo(path).fileName();
}

QVariantList Files::crumbs(const QString &urlString) const
{
    QVariantList out;
    const QUrl url(urlString);
    if (url.scheme() == QLatin1String("trash")) {
        out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Kosz")}, {QStringLiteral("url"), QStringLiteral("trash:/")}};
        return out;
    }
    if (!url.isLocalFile()) {
        out << QVariantMap{{QStringLiteral("name"), url.toDisplayString()}, {QStringLiteral("url"), urlString}};
        return out;
    }
    const QString path = QDir::cleanPath(url.toLocalFile());
    const QString home = QDir::homePath();
    QString base = QStringLiteral("/");
    QString rest = path;
    if (path == home || path.startsWith(home + QLatin1Char('/'))) {
        base = home;
        rest = path.mid(home.length());
    }
    out << QVariantMap{{QStringLiteral("name"), displayName(QUrl::fromLocalFile(base).toString())},
                       {QStringLiteral("url"), QUrl::fromLocalFile(base).toString()}};
    QString acc = base;
    for (const QString &part : rest.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
        acc = QDir::cleanPath(acc + QLatin1Char('/') + part);
        const QString u = QUrl::fromLocalFile(acc).toString();
        out << QVariantMap{{QStringLiteral("name"), displayName(u)}, {QStringLiteral("url"), u}};
    }
    return out;
}

QString Files::parentUrl(const QString &urlString) const
{
    const QUrl url(urlString);
    if (url.isLocalFile() && QDir::cleanPath(url.toLocalFile()) == QLatin1String("/"))
        return {};
    if (url.scheme() == QLatin1String("trash") && url.path().length() <= 1)
        return {};
    return url.adjusted(QUrl::StripTrailingSlash).adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash).toString();
}

QString Files::freeName(const QUrl &dir, const QString &base, const QString &ext) const
{
    const QString d = dir.toLocalFile();
    QString name = base + ext;
    for (int i = 2; QFileInfo::exists(d + QLatin1Char('/') + name); ++i)
        name = base + QLatin1Char(' ') + QString::number(i) + ext;
    return name;
}

QString Files::newFolder(const QString &dirUrl)
{
    const QUrl dir(dirUrl);
    const QString name = freeName(dir, QStringLiteral("Nowy folder"), {});
    const QUrl target = dir.adjusted(QUrl::StripTrailingSlash).toString() + QLatin1Char('/') + name;
    KIO::MkdirJob *job = KIO::mkdir(QUrl(target));
    FileUndoManager::self()->recordJob(FileUndoManager::Mkdir, {}, QUrl(target), job);
    watch(job);
    return name;
}

QString Files::newTextFile(const QString &dirUrl)
{
    const QUrl dir(dirUrl);
    const QString name = freeName(dir, QStringLiteral("Nowy dokument"), QStringLiteral(".txt"));
    const QUrl target(dir.adjusted(QUrl::StripTrailingSlash).toString() + QLatin1Char('/') + name);
    KIO::StoredTransferJob *job = KIO::storedPut(QByteArray(), target, -1, KIO::HideProgressInfo);
    FileUndoManager::self()->recordJob(FileUndoManager::Put, {}, target, job);
    watch(job);
    return name;
}

QString Files::rename(const QString &urlString, const QString &newName)
{
    const QString name = newName.trimmed();
    const QUrl src(urlString);
    if (name.isEmpty())
        return QStringLiteral("Nazwa nie może być pusta.");
    if (name.contains(QLatin1Char('/')))
        return QStringLiteral("Nazwa nie może zawierać znaku „/”.");
    if (name == src.fileName())
        return {};
    QUrl target = src.adjusted(QUrl::RemoveFilename);
    target.setPath(target.path() + name);
    if (target.isLocalFile() && QFileInfo::exists(target.toLocalFile()))
        return QStringLiteral("„%1” już tu jest.").arg(name);
    KIO::CopyJob *job = KIO::moveAs(src, target, KIO::HideProgressInfo);
    FileUndoManager::self()->recordJob(FileUndoManager::Rename, {src}, target, job);
    watch(job);
    return {};
}

QList<QUrl> Files::toUrls(const QStringList &urls)
{
    QList<QUrl> out;
    for (const QString &u : urls)
        out << QUrl(u);
    return out;
}

void Files::copy(const QStringList &urls, const QString &destDir)
{
    if (urls.isEmpty())
        return;
    KIO::CopyJob *job = KIO::copy(toUrls(urls), QUrl(destDir));
    job->setAutoRename(true);
    FileUndoManager::self()->recordCopyJob(job);
    watch(job);
}

void Files::move(const QStringList &urls, const QString &destDir)
{
    if (urls.isEmpty())
        return;
    if (QUrl(destDir).scheme() == QLatin1String("trash")) {
        trash(urls);
        return;
    }
    KIO::CopyJob *job = KIO::move(toUrls(urls), QUrl(destDir));
    job->setAutoRename(true);
    FileUndoManager::self()->recordCopyJob(job);
    watch(job);
}

void Files::trash(const QStringList &urls)
{
    if (urls.isEmpty())
        return;
    const QList<QUrl> list = toUrls(urls);
    KIO::CopyJob *job = KIO::trash(list);
    FileUndoManager::self()->recordJob(FileUndoManager::Trash, list, QUrl(QStringLiteral("trash:/")), job);
    watch(job);
}

void Files::restore(const QStringList &urls)
{
    if (!urls.isEmpty())
        watch(KIO::restoreFromTrash(toUrls(urls)));
}

void Files::deletePermanently(const QStringList &urls)
{
    if (!urls.isEmpty())
        watch(KIO::del(toUrls(urls)));
}

void Files::emptyTrash()
{
    watch(KIO::emptyTrash());
}

void Files::undo()
{
    FileUndoManager::self()->undo();
}

void Files::setClipboard(const QStringList &urls, bool cut)
{
    auto *mime = new QMimeData;
    mime->setUrls(toUrls(urls));
    mime->setData(cutMime, cut ? "1" : "0");
    QGuiApplication::clipboard()->setMimeData(mime);
}

int Files::paste(const QString &destDir)
{
    const QStringList urls = clipboardUrls();
    if (urls.isEmpty())
        return 0;
    if (clipboardCut()) {
        move(urls, destDir);
        QGuiApplication::clipboard()->clear();
    } else {
        copy(urls, destDir);
    }
    return urls.size();
}

void Files::open(const QString &url)
{
    auto *job = new KIO::OpenUrlJob(QUrl(url));
    watch(job);
    job->start();
}

void Files::openTerminal(const QString &dirUrl)
{
    const QUrl url(dirUrl);
    QProcess::startDetached(QStringLiteral("aster-terminal"),
                            {QStringLiteral("--workdir"), url.isLocalFile() ? url.toLocalFile() : QDir::homePath()});
}

QString Files::previewText(const QString &urlString) const
{
    const QUrl url(urlString);
    if (!url.isLocalFile())
        return {};
    const QMimeType mime = QMimeDatabase().mimeTypeForFile(url.toLocalFile());
    if (!mime.inherits(QStringLiteral("text/plain")))
        return {};
    QFile f(url.toLocalFile());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.read(6000));
}

void Files::watch(KJob *job)
{
    connect(job, &KJob::result, this, [this, job] {
        if (job->error() && job->error() != KIO::ERR_USER_CANCELED)
            Q_EMIT failed(job->errorString());
    });
}

#include "photomodel.h"

#include <QCollator>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QLocale>
#include <QSet>
#include <QUrl>
#include <QtConcurrent>
#include <algorithm>

namespace {

const QSet<QString> &extensions()
{
    static const QSet<QString> ext{
        QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("jpe"), QStringLiteral("jfif"), QStringLiteral("png"),
        QStringLiteral("gif"), QStringLiteral("webp"), QStringLiteral("bmp"), QStringLiteral("tif"), QStringLiteral("tiff"),
        QStringLiteral("heic"), QStringLiteral("heif"), QStringLiteral("avif"), QStringLiteral("jxl"), QStringLiteral("qoi"),
        QStringLiteral("dng"), QStringLiteral("cr2"), QStringLiteral("cr3"), QStringLiteral("nef"), QStringLiteral("arw"),
        QStringLiteral("orf"), QStringLiteral("rw2"), QStringLiteral("raf"), QStringLiteral("ico"), QStringLiteral("tga"),
        QStringLiteral("psd"), QStringLiteral("xcf"), QStringLiteral("kra"), QStringLiteral("exr"), QStringLiteral("hdr"),
    };
    return ext;
}

QVector<PhotoModel::Photo> scanFolder(const QString &dir)
{
    QVector<PhotoModel::Photo> out;
    const QFileInfoList list = QDir(dir).entryInfoList(QDir::Files | QDir::Readable);
    for (const QFileInfo &fi : list)
        if (PhotoModel::isPhoto(fi.fileName()))
            out.append({fi.absoluteFilePath(), fi.fileName(), fi.lastModified().toMSecsSinceEpoch()});
    QCollator collator(QLocale(QLocale::Polish));
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(out.begin(), out.end(), [&collator](const auto &a, const auto &b) { return collator.compare(a.name, b.name) < 0; });
    return out;
}

QVector<PhotoModel::Photo> scanLibrary(const QStringList &roots)
{
    QVector<PhotoModel::Photo> out;
    QSet<QString> seen;
    for (const QString &root : roots) {
        if (!QFileInfo(root).isDir())
            continue;
        QDirIterator it(root, QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
        const int rootDepth = QDir::cleanPath(root).count(QLatin1Char('/'));
        while (it.hasNext() && out.size() < 50000) {
            const QFileInfo fi = it.nextFileInfo();
            const QString path = fi.absoluteFilePath();
            // Ukryte foldery (np. .cache) i bardzo głęboko zagnieżdżone pomijamy
            if (path.contains(QLatin1String("/.")) || path.count(QLatin1Char('/')) - rootDepth > 6)
                continue;
            if (!PhotoModel::isPhoto(fi.fileName()) || seen.contains(path))
                continue;
            seen.insert(path);
            out.append({path, fi.fileName(), fi.lastModified().toMSecsSinceEpoch()});
        }
    }
    std::sort(out.begin(), out.end(), [](const auto &a, const auto &b) { return a.mtime > b.mtime; });
    return out;
}

} // namespace

PhotoModel::PhotoModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_watcher, &QFutureWatcher<QVector<Photo>>::finished, this, [this] {
        if (m_watcher.property("generation").toInt() != m_generation)
            return;
        beginResetModel();
        m_items = m_watcher.result();
        endResetModel();
        m_loading = false;
        Q_EMIT loadingChanged();
        Q_EMIT countChanged();
        Q_EMIT loaded();
    });
}

bool PhotoModel::isPhoto(const QString &fileName)
{
    const int dot = fileName.lastIndexOf(QLatin1Char('.'));
    return dot > 0 && extensions().contains(fileName.mid(dot + 1).toLower());
}

QString PhotoModel::thumbUrl(const QString &path, qint64 mtime)
{
    // Ścieżka w base64 — w adresie obrazka nie ma wtedy znaków do kodowania; czas zmiany odświeża miniaturę
    return QStringLiteral("image://thumb/") + QString::fromLatin1(path.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals))
        + QLatin1Char('_') + QString::number(mtime);
}

int PhotoModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant PhotoModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Photo &p = m_items.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole: return p.name;
    case PathRole: return p.path;
    case ThumbRole: return thumbUrl(p.path, p.mtime);
    case UrlRole: return QUrl::fromLocalFile(p.path).toString();
    case ModifiedRole: return QDateTime::fromMSecsSinceEpoch(p.mtime);
    case MonthRole: return monthAt(index.row());
    case AnimatedRole: return p.name.endsWith(QLatin1String(".gif"), Qt::CaseInsensitive) || p.name.endsWith(QLatin1String(".webp"), Qt::CaseInsensitive);
    }
    return {};
}

QHash<int, QByteArray> PhotoModel::roleNames() const
{
    return {{PathRole, "path"}, {NameRole, "name"}, {ThumbRole, "thumb"}, {UrlRole, "url"},
            {ModifiedRole, "modified"}, {MonthRole, "month"}, {AnimatedRole, "animated"}};
}

void PhotoModel::start(const QString &folder, const QStringList &roots)
{
    m_folder = folder;
    m_roots = roots;
    m_loading = true;
    Q_EMIT loadingChanged();
    const int gen = ++m_generation;
    m_watcher.setProperty("generation", gen);
    m_watcher.setFuture(folder.isEmpty() ? QtConcurrent::run(scanLibrary, roots) : QtConcurrent::run(scanFolder, folder));
}

void PhotoModel::openFolder(const QString &dir)
{
    start(QDir::cleanPath(dir), {});
}

void PhotoModel::openLibrary(const QStringList &roots)
{
    start(QString(), roots);
}

void PhotoModel::reload()
{
    start(m_folder, m_roots);
}

int PhotoModel::indexOf(const QString &path) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).path == path)
            return i;
    return -1;
}

QVariantMap PhotoModel::get(int row) const
{
    if (row < 0 || row >= m_items.size())
        return {};
    const QModelIndex i = index(row);
    return {{QStringLiteral("path"), data(i, PathRole)}, {QStringLiteral("name"), data(i, NameRole)},
            {QStringLiteral("thumb"), data(i, ThumbRole)}, {QStringLiteral("url"), data(i, UrlRole)},
            {QStringLiteral("animated"), data(i, AnimatedRole)}};
}

void PhotoModel::removeAt(int row)
{
    if (row < 0 || row >= m_items.size())
        return;
    beginRemoveRows({}, row, row);
    m_items.remove(row);
    endRemoveRows();
    Q_EMIT countChanged();
}

void PhotoModel::touch(int row)
{
    if (row < 0 || row >= m_items.size())
        return;
    m_items[row].mtime = QFileInfo(m_items.at(row).path).lastModified().toMSecsSinceEpoch();
    Q_EMIT dataChanged(index(row), index(row));
}

QString PhotoModel::monthAt(int row) const
{
    if (row < 0 || row >= m_items.size())
        return {};
    const QDate d = QDateTime::fromMSecsSinceEpoch(m_items.at(row).mtime).date();
    // Mianownik („listopad 2026”), nie dopełniacz z formatu daty
    return QLocale(QLocale::Polish).standaloneMonthName(d.month()) + QLatin1Char(' ') + QString::number(d.year());
}

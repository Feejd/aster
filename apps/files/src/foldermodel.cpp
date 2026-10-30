#include "foldermodel.h"
#include "fileops.h"

#include <KCoreDirLister>
#include <KIO/UDSEntry>

#include <QCollator>
#include <QFileInfo>
#include <QUrlQuery>

#include <algorithm>

FolderModel::FolderModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_lister(new KCoreDirLister(this))
{
    m_lister->setAutoErrorHandlingEnabled(false);
    m_lister->setDelayedMimeTypes(false);

    // Lister zgłasza zmiany porcjami — zbieramy je i przebudowujemy listę raz
    m_rebuildTimer.setSingleShot(true);
    m_rebuildTimer.setInterval(40);
    connect(&m_rebuildTimer, &QTimer::timeout, this, &FolderModel::rebuild);
    const auto schedule = [this] { m_rebuildTimer.start(); };
    connect(m_lister, &KCoreDirLister::itemsAdded, this, schedule);
    connect(m_lister, &KCoreDirLister::itemsDeleted, this, schedule);
    connect(m_lister, &KCoreDirLister::refreshItems, this, schedule);
    connect(m_lister, &KCoreDirLister::clear, this, schedule);
    connect(m_lister, &KCoreDirLister::started, this, [this] { setLoading(true); });
    connect(m_lister, qOverload<>(&KCoreDirLister::completed), this, [this] {
        setLoading(false);
        m_rebuildTimer.start();
    });
    connect(m_lister, qOverload<>(&KCoreDirLister::canceled), this, [this] { setLoading(false); });

    // Wyszukiwanie rusza chwilę po ostatnim naciśnięciu klawisza
    m_searchTimer.setSingleShot(true);
    m_searchTimer.setInterval(250);
    connect(&m_searchTimer, &QTimer::timeout, this, &FolderModel::relist);
}

int FolderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QHash<int, QByteArray> FolderModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UrlRole, "url"},
        {IsDirRole, "isDir"},
        {SizeRole, "size"},
        {SizeTextRole, "sizeText"},
        {ModifiedRole, "modified"},
        {IconRole, "iconName"},
        {KindRole, "kind"},
        {IsImageRole, "isImage"},
        {LocalPathRole, "localPath"},
        {WhereRole, "where"},
    };
}

QUrl FolderModel::itemUrl(const KFileItem &item) const
{
    // Wyniki wyszukiwania mają adres „filenamesearch:”; prawdziwy plik jest w targetUrl()
    if (item.url().scheme() == QLatin1String("filenamesearch"))
        return item.targetUrl();
    return item.url();
}

QVariant FolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const KFileItem &item = m_items.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return item.text();
    case UrlRole:
        return itemUrl(item).toString();
    case IsDirRole:
        return item.isDir();
    case SizeRole:
        return item.isDir() ? 0 : static_cast<qint64>(item.size());
    case SizeTextRole:
        return item.isDir() ? QString() : Files::formatSize(item.size());
    case ModifiedRole:
        return item.time(KFileItem::ModificationTime);
    case IconRole:
        return item.iconName();
    case KindRole:
        return item.isDir() ? QStringLiteral("Folder") : item.mimeComment();
    case IsImageRole: {
        const QString mime = item.mimetype();
        return item.mostLocalUrl().isLocalFile() && mime.startsWith(QLatin1String("image/"))
            && mime != QLatin1String("image/svg+xml") && item.size() < 40 * 1024 * 1024;
    }
    case LocalPathRole:
        return item.mostLocalUrl().isLocalFile() ? item.mostLocalUrl().toLocalFile() : QString();
    case WhereRole: {
        // W koszu: skąd plik pochodzi; w wynikach wyszukiwania: w jakim folderze leży
        const QString original = item.entry().stringValue(KIO::UDSEntry::UDS_EXTRA);
        if (!original.isEmpty())
            return QFileInfo(original).path();
        const QUrl u = itemUrl(item);
        return u.isLocalFile() ? QFileInfo(u.toLocalFile()).path() : u.adjusted(QUrl::RemoveFilename).toDisplayString();
    }
    }
    return {};
}

void FolderModel::setUrl(const QUrl &url)
{
    if (url == m_url)
        return;
    m_url = url;
    m_search.clear();
    Q_EMIT searchChanged();
    Q_EMIT urlChanged();
    relist();
}

void FolderModel::setSearch(const QString &search)
{
    if (search == m_search)
        return;
    m_search = search;
    Q_EMIT searchChanged();
    m_searchTimer.start();
}

void FolderModel::setSortKey(const QString &key)
{
    if (key == m_sortKey)
        return;
    m_sortKey = key;
    Q_EMIT sortChanged();
    rebuild();
}

void FolderModel::setAscending(bool ascending)
{
    if (ascending == m_ascending)
        return;
    m_ascending = ascending;
    Q_EMIT sortChanged();
    rebuild();
}

void FolderModel::setShowHidden(bool show)
{
    if (show == m_showHidden)
        return;
    m_showHidden = show;
    m_lister->setShowHiddenFiles(show);
    m_lister->emitChanges();
    Q_EMIT showHiddenChanged();
}

void FolderModel::setLoading(bool loading)
{
    if (loading == m_loading)
        return;
    m_loading = loading;
    Q_EMIT loadingChanged();
}

void FolderModel::relist()
{
    if (!m_url.isValid())
        return;
    QUrl target = m_url;
    if (!m_search.trimmed().isEmpty()) {
        // Wyszukiwanie po nazwach w tym folderze i wszystkich podfolderach (worker KIO „filenamesearch”)
        target = QUrl(QStringLiteral("filenamesearch:"));
        QUrlQuery q;
        q.addQueryItem(QStringLiteral("search"), m_search.trimmed());
        q.addQueryItem(QStringLiteral("url"), m_url.toString());
        q.addQueryItem(QStringLiteral("checkContent"), QStringLiteral("no"));
        target.setQuery(q);
    }
    m_lister->openUrl(target, KCoreDirLister::Reload);
}

void FolderModel::rebuild()
{
    QList<KFileItem> items = m_lister->items();

    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    const QString key = m_sortKey;
    const bool asc = m_ascending;
    std::stable_sort(items.begin(), items.end(), [&](const KFileItem &a, const KFileItem &b) {
        if (a.isDir() != b.isDir())
            return a.isDir();
        int c = 0;
        if (key == QLatin1String("date"))
            c = a.time(KFileItem::ModificationTime) < b.time(KFileItem::ModificationTime) ? -1
              : a.time(KFileItem::ModificationTime) > b.time(KFileItem::ModificationTime) ? 1 : 0;
        else if (key == QLatin1String("size"))
            c = a.size() < b.size() ? -1 : a.size() > b.size() ? 1 : 0;
        else if (key == QLatin1String("kind"))
            c = collator.compare(a.mimeComment(), b.mimeComment());
        if (c == 0)
            c = collator.compare(a.text(), b.text());
        return asc ? c < 0 : c > 0;
    });

    // Ten sam zestaw w tej samej kolejności → tylko odśwież dane (bez skakania widoku)
    bool same = items.size() == m_items.size();
    for (int i = 0; same && i < items.size(); ++i)
        same = items.at(i).url() == m_items.at(i).url();
    if (same) {
        m_items = items;
        if (!m_items.isEmpty())
            Q_EMIT dataChanged(index(0), index(m_items.size() - 1));
        return;
    }

    beginResetModel();
    m_items = items;
    endResetModel();
    Q_EMIT countChanged();
}

QVariantMap FolderModel::get(int row) const
{
    QVariantMap out;
    if (row < 0 || row >= m_items.size())
        return out;
    const QHash<int, QByteArray> roles = roleNames();
    for (auto it = roles.cbegin(); it != roles.cend(); ++it)
        out.insert(QString::fromLatin1(it.value()), data(index(row), it.key()));
    return out;
}

int FolderModel::indexOfUrl(const QString &url) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (itemUrl(m_items.at(i)).toString() == url)
            return i;
    return -1;
}

int FolderModel::indexOfName(const QString &name) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).text() == name)
            return i;
    return -1;
}

QString FolderModel::sizeText(const QStringList &urls) const
{
    KIO::filesize_t total = 0;
    for (const KFileItem &item : m_items)
        if (!item.isDir() && urls.contains(itemUrl(item).toString()))
            total += item.size();
    return Files::formatSize(total);
}

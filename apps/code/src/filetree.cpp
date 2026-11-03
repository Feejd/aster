#include "filetree.h"

#include <QCollator>
#include <QDir>
#include <QFileInfo>

FileTree::FileTree(QObject *parent)
    : QAbstractListModel(parent)
{
    m_refresh.setSingleShot(true);
    m_refresh.setInterval(150);
    connect(&m_refresh, &QTimer::timeout, this, &FileTree::refresh);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_refresh.start(); });
}

int FileTree::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant FileTree::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Node &n = m_rows.at(index.row());
    switch (role) {
    case PathRole: return n.path;
    case NameRole: return n.name;
    case DepthRole: return n.depth;
    case IsDirRole: return n.dir;
    case ExpandedRole: return n.dir && m_expanded.contains(n.path);
    case GitRole: {
        if (const QString own = m_git.value(n.path); !own.isEmpty())
            return own;
        if (n.dir && m_gitDirs.contains(n.path))
            return m_gitDirs.value(n.path);
        // W nowym (nieśledzonym) folderze git zgłasza tylko folder — wszystko w nim jest nowe
        QString p = n.path.section(QLatin1Char('/'), 0, -2);
        while (p.size() > m_root.size()) {
            if (m_git.value(p) == QLatin1String("U"))
                return QStringLiteral("U");
            p = p.section(QLatin1Char('/'), 0, -2);
        }
        return QString();
    }
    case IgnoredRole: {
        // Plik pomijany przez .gitignore albo leżący w takim folderze (build/, node_modules/)
        if (m_ignored.isEmpty())
            return false;
        QString p = n.path;
        while (p.size() > m_root.size()) {
            if (m_ignored.contains(p))
                return true;
            p = p.section(QLatin1Char('/'), 0, -2);
        }
        return false;
    }
    }
    return {};
}

QHash<int, QByteArray> FileTree::roleNames() const
{
    return {{PathRole, "path"}, {NameRole, "name"}, {DepthRole, "depth"}, {IsDirRole, "isDir"},
            {ExpandedRole, "expanded"}, {GitRole, "git"}, {IgnoredRole, "ignored"}};
}

void FileTree::setRoot(const QString &root)
{
    m_root = root;
    m_expanded.clear();
    beginResetModel();
    m_rows.clear();
    if (!root.isEmpty())
        build(m_rows, root, 0);
    endResetModel();
    rewatch();
    Q_EMIT countChanged();
    Q_EMIT expandedChanged();
}

void FileTree::setExpanded(const QStringList &dirs)
{
    for (const QString &d : dirs)
        if (d.startsWith(m_root) && QFileInfo(d).isDir())
            m_expanded.insert(d);
    refresh();
    Q_EMIT expandedChanged();
}

void FileTree::setGit(const QHash<QString, QString> &files, const QHash<QString, QString> &dirs, const QSet<QString> &ignored)
{
    if (files == m_git && dirs == m_gitDirs && ignored == m_ignored)
        return;
    m_git = files;
    m_gitDirs = dirs;
    m_ignored = ignored;
    if (!m_rows.isEmpty())
        Q_EMIT dataChanged(index(0), index(int(m_rows.size()) - 1), {GitRole, IgnoredRole});
}

void FileTree::build(QVector<Node> &out, const QString &dir, int depth) const
{
    QDir d(dir);
    QFileInfoList list = d.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    QCollator coll;
    coll.setNumericMode(true);
    coll.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(list.begin(), list.end(), [&](const QFileInfo &a, const QFileInfo &b) {
        if (a.isDir() != b.isDir())
            return a.isDir();
        return coll.compare(a.fileName(), b.fileName()) < 0;
    });
    for (const QFileInfo &fi : std::as_const(list)) {
        if (fi.fileName() == QLatin1String(".git"))
            continue;
        const QString path = fi.absoluteFilePath();
        out.append({path, fi.fileName(), depth, fi.isDir()});
        if (fi.isDir() && m_expanded.contains(path) && depth < 40)
            build(out, path, depth + 1);
    }
}

void FileTree::apply(const QVector<Node> &rows)
{
    // Wspólny początek i koniec zostają; środek — usunięcie i wstawienie (zwykle tylko jedno z nich)
    const int oldN = int(m_rows.size()), newN = int(rows.size());
    int p = 0;
    while (p < oldN && p < newN && m_rows[p] == rows[p])
        ++p;
    int s = 0;
    while (s < oldN - p && s < newN - p && m_rows[oldN - 1 - s] == rows[newN - 1 - s])
        ++s;
    if (oldN - p - s > 0) {
        beginRemoveRows({}, p, oldN - s - 1);
        m_rows.remove(p, oldN - p - s);
        endRemoveRows();
    }
    if (newN - p - s > 0) {
        beginInsertRows({}, p, newN - s - 1);
        for (int i = p; i < newN - s; ++i)
            m_rows.insert(i, rows[i]);
        endInsertRows();
    }
    // Głębokość i nazwa się nie zmieniają przy tej samej ścieżce; rozwinięcie — tak
    if (!m_rows.isEmpty())
        Q_EMIT dataChanged(index(0), index(int(m_rows.size()) - 1), {ExpandedRole});
    if (oldN != newN)
        Q_EMIT countChanged();
}

void FileTree::refresh()
{
    if (m_root.isEmpty())
        return;
    // Foldery, które zniknęły, przestają być rozwinięte
    for (auto it = m_expanded.begin(); it != m_expanded.end();)
        it = QFileInfo(*it).isDir() ? std::next(it) : m_expanded.erase(it);
    QVector<Node> rows;
    build(rows, m_root, 0);
    apply(rows);
    rewatch();
}

void FileTree::rewatch()
{
    QStringList want{m_root};
    for (const QString &d : std::as_const(m_expanded))
        want << d;
    const QStringList have = m_watcher.directories();
    for (const QString &d : have)
        if (!want.contains(d))
            m_watcher.removePath(d);
    for (const QString &d : std::as_const(want))
        if (!d.isEmpty() && !have.contains(d) && QFileInfo(d).isDir())
            m_watcher.addPath(d);
}

void FileTree::toggle(int row)
{
    if (row < 0 || row >= m_rows.size() || !m_rows[row].dir)
        return;
    const QString path = m_rows[row].path;
    if (m_expanded.contains(path))
        m_expanded.remove(path);
    else
        m_expanded.insert(path);
    refresh();
    Q_EMIT expandedChanged();
}

void FileTree::expandPath(const QString &dir)
{
    if (dir.isEmpty() || dir == m_root || m_expanded.contains(dir))
        return;
    m_expanded.insert(dir);
    refresh();
    Q_EMIT expandedChanged();
}

int FileTree::reveal(const QString &path)
{
    if (!path.startsWith(m_root + QLatin1Char('/')))
        return -1;
    bool changed = false;
    QString dir = QFileInfo(path).absolutePath();
    while (dir.size() > m_root.size()) {
        if (!m_expanded.contains(dir)) {
            m_expanded.insert(dir);
            changed = true;
        }
        dir = QFileInfo(dir).absolutePath();
    }
    if (changed) {
        refresh();
        Q_EMIT expandedChanged();
    }
    return indexOf(path);
}

int FileTree::indexOf(const QString &path) const
{
    for (int i = 0; i < m_rows.size(); ++i)
        if (m_rows[i].path == path)
            return i;
    return -1;
}

void FileTree::collapseAll()
{
    m_expanded.clear();
    refresh();
    Q_EMIT expandedChanged();
}

QString FileTree::pathAt(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows[row].path : QString();
}

bool FileTree::isDirAt(int row) const
{
    return row >= 0 && row < m_rows.size() && m_rows[row].dir;
}

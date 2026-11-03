#pragma once

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QHash>
#include <QQmlEngine>
#include <QSet>
#include <QTimer>

// Drzewo plików projektu jako płaska lista (wiersz = plik albo folder z głębokością) — ListView
// w QML rysuje wcięcia. Rozwinięte foldery są obserwowane i odświeżają się same; zmiany
// listy idą jako wstawienia/usunięcia wierszy, więc widok nie skacze na początek.
class FileTree : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Drzewo plików należy do Project")
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles { PathRole = Qt::UserRole + 1, NameRole, DepthRole, IsDirRole, ExpandedRole, GitRole, IgnoredRole };

    explicit FileTree(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_rows.size()); }

    void setRoot(const QString &root);
    void setExpanded(const QStringList &dirs);
    QStringList expandedDirs() const { return QStringList(m_expanded.cbegin(), m_expanded.cend()); }
    // Stan gita: plik → litera (M, A, D, U, R, C); foldery ze zmianami wewnątrz; pliki pomijane (.gitignore)
    void setGit(const QHash<QString, QString> &files, const QHash<QString, QString> &dirs, const QSet<QString> &ignored);

    Q_INVOKABLE void toggle(int row);
    Q_INVOKABLE void expandPath(const QString &dir);
    Q_INVOKABLE int reveal(const QString &path);          // rozwija foldery nad plikiem, zwraca wiersz
    Q_INVOKABLE int indexOf(const QString &path) const;
    Q_INVOKABLE void collapseAll();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE bool isDirAt(int row) const;

Q_SIGNALS:
    void countChanged();
    void expandedChanged();

private:
    struct Node {
        QString path, name;
        int depth = 0;
        bool dir = false;
        bool operator==(const Node &o) const { return path == o.path && dir == o.dir; }
    };
    void build(QVector<Node> &out, const QString &dir, int depth) const;
    void apply(const QVector<Node> &rows);
    void rewatch();

    QString m_root;
    QVector<Node> m_rows;
    QSet<QString> m_expanded;
    QHash<QString, QString> m_git, m_gitDirs;
    QSet<QString> m_ignored;
    QFileSystemWatcher m_watcher;
    QTimer m_refresh;
};

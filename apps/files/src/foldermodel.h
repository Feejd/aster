#pragma once

#include <KFileItem>

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QTimer>
#include <QUrl>

class KCoreDirLister;

// Zawartość jednego folderu (albo wyniki wyszukiwania w nim i podfolderach) jako płaska lista.
// Dane daje KIO (KCoreDirLister), więc działają też kosz (trash:/) i zmiany na bieżąco.
// Sortowanie: foldery zawsze pierwsze, nazwy porównywane „naturalnie” (Plik 2 < Plik 10).
class FolderModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(QString sortKey READ sortKey WRITE setSortKey NOTIFY sortChanged)
    Q_PROPERTY(bool ascending READ ascending WRITE setAscending NOTIFY sortChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        UrlRole,
        IsDirRole,
        SizeRole,
        SizeTextRole,
        ModifiedRole,
        IconRole,
        KindRole,
        IsImageRole,
        LocalPathRole,
        WhereRole,
    };
    Q_ENUM(Role)

    explicit FolderModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QUrl url() const { return m_url; }
    void setUrl(const QUrl &url);
    QString search() const { return m_search; }
    void setSearch(const QString &search);
    QString sortKey() const { return m_sortKey; }
    void setSortKey(const QString &key);
    bool ascending() const { return m_ascending; }
    void setAscending(bool ascending);
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool show);
    bool loading() const { return m_loading; }
    int count() const { return m_items.size(); }

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int indexOfUrl(const QString &url) const;
    Q_INVOKABLE int indexOfName(const QString &name) const;
    // Łączny rozmiar zaznaczonych plików (foldery liczone jako 0), np. „4,2 MB”
    Q_INVOKABLE QString sizeText(const QStringList &urls) const;

Q_SIGNALS:
    void urlChanged();
    void searchChanged();
    void sortChanged();
    void showHiddenChanged();
    void loadingChanged();
    void countChanged();

private:
    void relist();
    void rebuild();
    void setLoading(bool loading);
    QUrl itemUrl(const KFileItem &item) const;

    KCoreDirLister *m_lister;
    QList<KFileItem> m_items;
    QTimer m_rebuildTimer;
    QTimer m_searchTimer;
    QUrl m_url;
    QString m_search;
    QString m_sortKey = QStringLiteral("name");
    bool m_ascending = true;
    bool m_showHidden = false;
    bool m_loading = false;
};

#pragma once

#include <QAbstractListModel>
#include <QJsonValue>
#include <QQmlEngine>
#include <QVector>

// Odpowiedź JSON jako płaska lista widocznych wierszy drzewa (ListView w QML): zwijanie, rozwijanie,
// wyszukiwanie po kluczach i wartościach (pokazuje trafienia i drogę do nich). Węzły trzymane raz,
// lista widocznych przebudowywana tylko po zmianie — lekko także dla dużych odpowiedzi.
class JsonTreeModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("z Pulse.tree")
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int matches READ matches NOTIFY filterChanged)
    Q_PROPERTY(int nodeCount READ nodeCount NOTIFY reset)
    Q_PROPERTY(bool valid READ valid NOTIFY reset)

public:
    enum Roles { DepthRole = Qt::UserRole + 1, KeyRole, ValueRole, KindRole, ExpandableRole, ExpandedRole, CountRole, MatchRole, IndexKeyRole, LastRole };
    explicit JsonTreeModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_rows.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setJson(const QJsonValue &root);
    void clear();
    bool valid() const { return !m_nodes.isEmpty(); }
    int nodeCount() const { return int(m_nodes.size()); }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    int matches() const { return m_matchCount; }

    Q_INVOKABLE void toggle(int row);
    Q_INVOKABLE void expandAll();
    Q_INVOKABLE void collapseAll();
    // Do schowka: wartość węzła (obiekt/tablica jako sformatowany JSON) i ścieżka w stylu $.users[0].name
    Q_INVOKABLE QString valueText(int row) const;
    Q_INVOKABLE QString pathText(int row) const;

Q_SIGNALS:
    void filterChanged();
    void reset();

private:
    struct Node {
        QString key;
        QJsonValue value;          // dla obiektów i tablic — cała wartość (QJsonValue dzieli dane, kopia jest tania)
        int parent = -1;
        int depth = 0;
        int firstChild = -1;
        int childCount = 0;
        bool expanded = false;
        bool indexKey = false;     // element tablicy (klucz to numer)
        bool last = false;         // ostatni w rodzicu (bez przecinka)
    };
    void rebuildRows();
    void visit(int n, bool inMatch);
    bool isMatch(int n) const;
    QString preview(const QJsonValue &v) const;

    QVector<Node> m_nodes;
    QVector<int> m_rows;
    QVector<int> m_roots;
    QVector<char> m_keep;          // przy wyszukiwaniu: węzeł trafiony albo na drodze do trafienia
    QString m_filter;
    int m_matchCount = 0;
};

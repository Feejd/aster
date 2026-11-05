#pragma once

#include <QAbstractListModel>
#include <QStringList>

// Linie logu dla ListView: dopisywanie na końcu bez przeładowania widoku, limit linii, filtr tekstu
class LineModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
public:
    explicit LineModel(int limit, QObject *parent = nullptr) : QAbstractListModel(parent), m_limit(limit) {}

    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_shown.size()); }
    QVariant data(const QModelIndex &index, int role) const override
    {
        if (role != Qt::DisplayRole || index.row() < 0 || index.row() >= m_shown.size()) return {};
        return m_shown.at(index.row());
    }
    QHash<int, QByteArray> roleNames() const override { return { { Qt::DisplayRole, "line" } }; }

    int count() const { return int(m_shown.size()); }
    QString filter() const { return m_filter; }
    const QStringList &all() const { return m_all; }

    void setFilter(const QString &f)
    {
        if (f == m_filter) return;
        m_filter = f;
        beginResetModel();
        m_shown.clear();
        for (const QString &l : std::as_const(m_all)) if (matches(l)) m_shown << l;
        endResetModel();
        Q_EMIT filterChanged();
        Q_EMIT countChanged();
    }
    void append(const QStringList &lines)
    {
        m_all += lines;
        QStringList add;
        for (const QString &l : lines) if (matches(l)) add << l;
        if (!add.isEmpty()) {
            beginInsertRows({}, int(m_shown.size()), int(m_shown.size() + add.size() - 1));
            m_shown += add;
            endInsertRows();
        }
        if (m_all.size() > m_limit) m_all = m_all.mid(m_all.size() - m_limit);
        if (m_shown.size() > m_limit) {
            const int drop = int(m_shown.size()) - m_limit;
            beginRemoveRows({}, 0, drop - 1);
            m_shown = m_shown.mid(drop);
            endRemoveRows();
        }
        Q_EMIT countChanged();
    }
    void clear()
    {
        beginResetModel();
        m_all.clear();
        m_shown.clear();
        endResetModel();
        Q_EMIT countChanged();
    }

Q_SIGNALS:
    void countChanged();
    void filterChanged();

private:
    bool matches(const QString &l) const { return m_filter.isEmpty() || l.contains(m_filter, Qt::CaseInsensitive); }
    int m_limit;
    QString m_filter;
    QStringList m_all, m_shown;
};

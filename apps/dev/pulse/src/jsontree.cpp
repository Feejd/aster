#include "jsontree.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

JsonTreeModel::JsonTreeModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

QHash<int, QByteArray> JsonTreeModel::roleNames() const
{
    return {{DepthRole, "depth"}, {KeyRole, "key"}, {ValueRole, "value"}, {KindRole, "kind"}, {ExpandableRole, "expandable"},
            {ExpandedRole, "expanded"}, {CountRole, "count"}, {MatchRole, "match"}, {IndexKeyRole, "indexKey"}, {LastRole, "last"}};
}

static QString kindOf(const QJsonValue &v)
{
    switch (v.type()) {
    case QJsonValue::Object: return QStringLiteral("object");
    case QJsonValue::Array: return QStringLiteral("array");
    case QJsonValue::String: return QStringLiteral("string");
    case QJsonValue::Double: return QStringLiteral("number");
    case QJsonValue::Bool: return QStringLiteral("bool");
    default: return QStringLiteral("null");
    }
}

static QString scalarText(const QJsonValue &v)
{
    switch (v.type()) {
    case QJsonValue::String: {
        QString s = v.toString();
        s.replace(QLatin1Char('\\'), QLatin1String("\\\\")).replace(QLatin1Char('"'), QLatin1String("\\\"")).replace(QLatin1Char('\n'), QLatin1String("\\n"));
        return QLatin1Char('"') + s + QLatin1Char('"');
    }
    case QJsonValue::Double: {
        const double d = v.toDouble();
        // Liczby całkowite bez „e+” i części ułamkowej
        if (d == qint64(d) && qAbs(d) < 1e15)
            return QString::number(qint64(d));
        return QString::number(d, 'g', 15);
    }
    case QJsonValue::Bool: return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    default: return QStringLiteral("null");
    }
}

QString JsonTreeModel::preview(const QJsonValue &v) const
{
    // Zwinięty obiekt: { id: 1, name: "Ala", … }
    QString out;
    if (v.isObject()) {
        const QJsonObject o = v.toObject();
        QStringList parts;
        for (auto it = o.begin(); it != o.end() && parts.size() < 4; ++it)
            parts << it.key() + QStringLiteral(": ") + (it->isObject() ? QStringLiteral("{…}") : it->isArray() ? QStringLiteral("[…]") : scalarText(*it).left(24));
        out = QStringLiteral("{ ") + parts.join(QStringLiteral(", ")) + (o.size() > 4 ? QStringLiteral(", … }") : QStringLiteral(" }"));
        if (o.isEmpty())
            out = QStringLiteral("{}");
    } else {
        const QJsonArray a = v.toArray();
        QStringList parts;
        for (int i = 0; i < a.size() && parts.size() < 5; ++i)
            parts << (a.at(i).isObject() ? QStringLiteral("{…}") : a.at(i).isArray() ? QStringLiteral("[…]") : scalarText(a.at(i)).left(20));
        out = QStringLiteral("[ ") + parts.join(QStringLiteral(", ")) + (a.size() > 5 ? QStringLiteral(", … ]") : QStringLiteral(" ]"));
        if (a.isEmpty())
            out = QStringLiteral("[]");
    }
    return out.size() > 120 ? out.left(119) + QChar(0x2026) : out;
}

QVariant JsonTreeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Node &n = m_nodes.at(m_rows.at(index.row()));
    switch (role) {
    case DepthRole: return n.depth;
    case KeyRole: return n.key;
    case ValueRole: return (n.value.isObject() || n.value.isArray()) ? preview(n.value) : scalarText(n.value).left(2000);
    case KindRole: return kindOf(n.value);
    case ExpandableRole: return n.childCount > 0;
    case ExpandedRole: return n.expanded || (!m_filter.isEmpty() && !isMatch(m_rows.at(index.row())) && n.childCount > 0);
    case CountRole: return n.childCount;
    case MatchRole: return !m_filter.isEmpty() && isMatch(m_rows.at(index.row()));
    case IndexKeyRole: return n.indexKey;
    case LastRole: return n.last;
    }
    return {};
}

void JsonTreeModel::setJson(const QJsonValue &root)
{
    beginResetModel();
    m_nodes.clear();
    m_roots.clear();
    m_rows.clear();
    // Wszerz: dzieci każdego węzła leżą obok siebie (firstChild … firstChild + childCount)
    auto addChildren = [this](int parent, const QJsonValue &v, int depth) {
        const int first = int(m_nodes.size());
        int count = 0;
        if (v.isObject()) {
            const QJsonObject o = v.toObject();
            for (auto it = o.begin(); it != o.end(); ++it, ++count)
                m_nodes.append({it.key(), *it, parent, depth, -1, 0, false, false, false});
        } else if (v.isArray()) {
            const QJsonArray a = v.toArray();
            for (int i = 0; i < a.size(); ++i, ++count)
                m_nodes.append({QString::number(i), a.at(i), parent, depth, -1, 0, false, true, false});
        }
        if (count > 0)
            m_nodes[first + count - 1].last = true;
        return std::pair{first, count};
    };
    if (root.isObject() || root.isArray()) {
        auto [first, count] = addChildren(-1, root, 0);
        for (int i = 0; i < count; ++i)
            m_roots.append(first + i);
    } else if (!root.isUndefined()) {
        m_nodes.append({QString(), root, -1, 0, -1, 0, false, false, true});
        m_roots.append(0);
    }
    for (int i = 0; i < m_nodes.size(); ++i) {
        const QJsonValue v = m_nodes.at(i).value;
        if (!v.isObject() && !v.isArray())
            continue;
        auto [first, count] = addChildren(i, v, m_nodes.at(i).depth + 1);
        m_nodes[i].firstChild = count ? first : -1;
        m_nodes[i].childCount = count;
    }
    // Na start: małe odpowiedzi rozwinięte całe, większe — pierwszy poziom
    const bool small = m_nodes.size() <= 150;
    for (Node &n : m_nodes)
        n.expanded = n.childCount > 0 && (small || (n.depth == 0 && m_nodes.size() <= 3000) || (n.depth == 0 && m_roots.size() == 1));
    m_keep.clear();
    m_matchCount = 0;
    m_filter.clear();
    rebuildRows();
    endResetModel();
    Q_EMIT reset();
    Q_EMIT filterChanged();
}

void JsonTreeModel::clear()
{
    beginResetModel();
    m_nodes.clear();
    m_roots.clear();
    m_rows.clear();
    m_keep.clear();
    m_matchCount = 0;
    endResetModel();
    Q_EMIT reset();
}

bool JsonTreeModel::isMatch(int n) const
{
    if (m_filter.isEmpty())
        return false;
    const Node &node = m_nodes.at(n);
    if (!node.indexKey && node.key.contains(m_filter, Qt::CaseInsensitive))
        return true;
    if (node.value.isObject() || node.value.isArray())
        return false;
    return (node.value.isString() ? node.value.toString() : scalarText(node.value)).contains(m_filter, Qt::CaseInsensitive);
}

void JsonTreeModel::visit(int n, bool inMatch)
{
    m_rows.append(n);
    const Node &node = m_nodes.at(n);
    if (node.childCount == 0)
        return;
    const bool filtering = !m_filter.isEmpty();
    const bool match = filtering && isMatch(n);
    if (filtering && !inMatch && !match) {
        // Węzeł na drodze do trafienia — pokazujemy tylko gałęzie z trafieniami
        for (int c = node.firstChild; c < node.firstChild + node.childCount; ++c)
            if (m_keep.at(c))
                visit(c, false);
        return;
    }
    if (!node.expanded)
        return;
    for (int c = node.firstChild; c < node.firstChild + node.childCount; ++c)
        visit(c, inMatch || match);
}

void JsonTreeModel::rebuildRows()
{
    m_rows.clear();
    if (!m_filter.isEmpty()) {
        m_keep.fill(0, m_nodes.size());
        m_matchCount = 0;
        for (int i = int(m_nodes.size()) - 1; i >= 0; --i)
            if (isMatch(i)) {
                ++m_matchCount;
                for (int p = i; p >= 0 && !m_keep.at(p); p = m_nodes.at(p).parent)
                    m_keep[p] = 1;
            }
        for (int r : m_roots)
            if (m_keep.at(r))
                visit(r, false);
        return;
    }
    for (int r : m_roots)
        visit(r, false);
}

void JsonTreeModel::setFilter(const QString &f)
{
    const QString t = f.trimmed();
    if (t == m_filter)
        return;
    beginResetModel();
    m_filter = t;
    if (m_filter.isEmpty())
        m_matchCount = 0;
    rebuildRows();
    endResetModel();
    Q_EMIT filterChanged();
}

void JsonTreeModel::toggle(int row)
{
    if (row < 0 || row >= m_rows.size())
        return;
    const int n = m_rows.at(row);
    Node &node = m_nodes[n];
    if (node.childCount == 0)
        return;
    // Przy wyszukiwaniu węzły na drodze do trafień są zawsze otwarte
    if (!m_filter.isEmpty() && !isMatch(n))
        return;
    // Wstawiamy/usuwamy tylko potomków (zawsze ciągły blok pod wierszem) — lista nie przeskakuje
    const QVector<int> before = m_rows;
    node.expanded = !node.expanded;
    rebuildRows();
    const int delta = int(m_rows.size() - before.size());
    if (delta > 0) {
        QVector<int> after = m_rows;
        m_rows = before;
        beginInsertRows({}, row + 1, row + delta);
        m_rows = after;
        endInsertRows();
    } else if (delta < 0) {
        QVector<int> after = m_rows;
        m_rows = before;
        beginRemoveRows({}, row + 1, row - delta);
        m_rows = after;
        endRemoveRows();
    }
    Q_EMIT dataChanged(index(row), index(row), {ExpandedRole, ValueRole});
}

void JsonTreeModel::expandAll()
{
    beginResetModel();
    for (Node &n : m_nodes)
        n.expanded = n.childCount > 0;
    rebuildRows();
    endResetModel();
}

void JsonTreeModel::collapseAll()
{
    beginResetModel();
    for (Node &n : m_nodes)
        n.expanded = false;
    rebuildRows();
    endResetModel();
}

QString JsonTreeModel::valueText(int row) const
{
    if (row < 0 || row >= m_rows.size())
        return {};
    const QJsonValue v = m_nodes.at(m_rows.at(row)).value;
    if (v.isObject())
        return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Indented)).trimmed();
    if (v.isArray())
        return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Indented)).trimmed();
    return v.isString() ? v.toString() : scalarText(v);
}

QString JsonTreeModel::pathText(int row) const
{
    if (row < 0 || row >= m_rows.size())
        return {};
    static const QRegularExpression ident(QStringLiteral("^[A-Za-z_$][A-Za-z0-9_$]*$"));
    QStringList parts;
    for (int n = m_rows.at(row); n >= 0; n = m_nodes.at(n).parent) {
        const Node &node = m_nodes.at(n);
        if (node.indexKey)
            parts.prepend(QLatin1Char('[') + node.key + QLatin1Char(']'));
        else if (ident.match(node.key).hasMatch())
            parts.prepend(QLatin1Char('.') + node.key);
        else
            parts.prepend(QStringLiteral("[\"") + node.key + QStringLiteral("\"]"));
    }
    return QLatin1Char('$') + parts.join(QString());
}

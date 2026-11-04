#include "gridmodel.h"

#include <QFontMetrics>
#include <QJsonDocument>
#include <QJsonObject>

namespace {
bool isBinary(const QVariant &v)
{
    if (v.metaType().id() != QMetaType::QByteArray)
        return false;
    const QByteArray b = v.toByteArray();
    return b.contains('\0') || QString::fromUtf8(b).contains(QChar::ReplacementCharacter);
}
bool isNumber(const QVariant &v)
{
    switch (v.metaType().id()) {
    case QMetaType::Int: case QMetaType::UInt: case QMetaType::LongLong: case QMetaType::ULongLong:
    case QMetaType::Double: case QMetaType::Float:
        return true;
    default:
        return false;
    }
}
} // namespace

GridModel::GridModel(QObject *parent)
    : QAbstractTableModel(parent)
{
}

int GridModel::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : int(m_rows.size()); }

int GridModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_columns.size()) - (m_target.rowid ? 1 : 0);
}

QStringList GridModel::columns() const { return m_target.rowid ? m_columns.mid(1) : m_columns; }
QStringList GridModel::types() const { return m_target.rowid ? m_types.mid(1) : m_types; }

QVariant GridModel::current(int row, int dcol) const
{
    const auto e = m_edits.constFind(row);
    if (e != m_edits.cend()) {
        const auto c = e->constFind(dcol);
        if (c != e->cend())
            return *c;
    }
    return m_rows.at(row).value(dcol);
}

QVariant GridModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const int r = index.row(), dc = dataCol(index.column());
    const QVariant v = current(r, dc);
    switch (role) {
    case Qt::DisplayRole:
    case TextRole:
        return v.isNull() ? QStringLiteral("NULL") : Db::cellText(v, 160);
    case FullRole:
        return Db::cellText(v);
    case NullRole:
        return v.isNull();
    case EditedRole:
        return m_edits.contains(r) && m_edits.value(r).contains(dc);
    case StateRole: {
        const State s = m_state.at(r);
        return s == Inserted ? QStringLiteral("new") : (s == Deleted || s == InsertedDeleted) ? QStringLiteral("deleted") : QString();
    }
    case NumericRole: {
        // numeric/decimal przychodzą jako dokładny tekst — też do prawej
        static const QStringList numeric{QStringLiteral("int"), QStringLiteral("qlonglong"), QStringLiteral("double"),
                                         QStringLiteral("uint"), QStringLiteral("qulonglong"), QStringLiteral("float")};
        return isNumber(v) || (!v.isNull() && numeric.contains(m_types.value(dc)));
    }
    }
    return {};
}

QVariant GridModel::headerData(int section, Qt::Orientation o, int role) const
{
    if (role != Qt::DisplayRole)
        return {};
    if (o == Qt::Vertical)
        return section + 1;
    return columns().value(section);
}

QHash<int, QByteArray> GridModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}, {TextRole, "text"}, {NullRole, "isNull"}, {EditedRole, "edited"},
            {StateRole, "rowState"}, {NumericRole, "numeric"}, {FullRole, "full"}};
}

void GridModel::setResult(const QStringList &columns, const QStringList &types, const QVariantList &rows, const Target &target)
{
    beginResetModel();
    m_columns = columns;
    m_types = types;
    m_target = target;
    m_rows.clear();
    m_state.clear();
    m_edits.clear();
    m_rows.reserve(rows.size());
    for (const QVariant &r : rows) {
        m_rows << r.toList();
        m_state << Normal;
    }
    endResetModel();
    Q_EMIT layoutReset();
    Q_EMIT rowsChanged();
    Q_EMIT changesChanged();
}

void GridModel::appendRows(const QVariantList &rows)
{
    if (rows.isEmpty())
        return;
    // Nowe (niezapisane) wiersze zostają na końcu — wczytane dochodzą przed nimi
    int firstNew = int(m_rows.size());
    while (firstNew > 0 && (m_state.at(firstNew - 1) == Inserted || m_state.at(firstNew - 1) == InsertedDeleted))
        --firstNew;
    if (firstNew != m_rows.size()) {
        // rzadkie: dopisujemy po resecie, żeby nie przenumerowywać zmian
        beginResetModel();
        QList<QVariantList> tail = m_rows.mid(firstNew);
        QList<State> tailState = m_state.mid(firstNew);
        QHash<int, QHash<int, QVariant>> edits;
        for (auto it = m_edits.cbegin(); it != m_edits.cend(); ++it)
            edits.insert(it.key() >= firstNew ? it.key() + int(rows.size()) : it.key(), it.value());
        m_rows = m_rows.mid(0, firstNew);
        m_state = m_state.mid(0, firstNew);
        for (const QVariant &r : rows) {
            m_rows << r.toList();
            m_state << Normal;
        }
        m_rows += tail;
        m_state += tailState;
        m_edits = edits;
        endResetModel();
    } else {
        beginInsertRows({}, int(m_rows.size()), int(m_rows.size() + rows.size() - 1));
        for (const QVariant &r : rows) {
            m_rows << r.toList();
            m_state << Normal;
        }
        endInsertRows();
    }
    Q_EMIT rowsChanged();
}

void GridModel::clear() { setResult({}, {}, {}); }

int GridModel::changeCount() const
{
    int n = 0;
    for (int r = 0; r < m_rows.size(); ++r) {
        const State s = m_state.at(r);
        if (s == Deleted || s == Inserted)
            ++n;
        else if (s == Normal && m_edits.contains(r))
            ++n;
    }
    return n;
}

bool GridModel::cellEditable(int row, int col) const
{
    if (!editable() || row < 0 || row >= m_rows.size() || col < 0 || col >= columnCount())
        return false;
    if (m_state.at(row) == Deleted || m_state.at(row) == InsertedDeleted)
        return false;
    return !isBinary(m_rows.at(row).value(dataCol(col)));
}

bool GridModel::setCell(int row, int col, const QString &text, bool null)
{
    if (!cellEditable(row, col))
        return false;
    const int dc = dataCol(col);
    const QVariant orig = m_rows.at(row).value(dc);
    const bool same = m_state.at(row) == Normal
        && (null ? orig.isNull() : (!orig.isNull() && Db::cellText(orig) == text));
    if (same) {
        if (m_edits.contains(row)) {
            m_edits[row].remove(dc);
            if (m_edits[row].isEmpty())
                m_edits.remove(row);
        }
    } else {
        // Kolumna liczbowa i tekst wygląda jak liczba — zapisujemy liczbę (podgląd bez cudzysłowów)
        QVariant val = null ? QVariant() : QVariant(text);
        static const QStringList numeric{QStringLiteral("int"), QStringLiteral("qlonglong"), QStringLiteral("double"),
                                         QStringLiteral("uint"), QStringLiteral("qulonglong"), QStringLiteral("float")};
        if (!null && numeric.contains(m_types.value(dc))) {
            bool ok = false;
            const qlonglong i = text.trimmed().toLongLong(&ok);
            if (ok) {
                val = i;
            } else {
                const double d = QString(text.trimmed()).replace(QLatin1Char(','), QLatin1Char('.')).toDouble(&ok);
                if (ok)
                    val = d;
            }
        }
        m_edits[row][dc] = val;
    }
    const QModelIndex i = index(row, col);
    Q_EMIT dataChanged(i, i);
    Q_EMIT changesChanged();
    return true;
}

void GridModel::revertCell(int row, int col)
{
    if (!m_edits.contains(row))
        return;
    m_edits[row].remove(dataCol(col));
    if (m_edits[row].isEmpty())
        m_edits.remove(row);
    const QModelIndex i = index(row, col);
    Q_EMIT dataChanged(i, i);
    Q_EMIT changesChanged();
}

int GridModel::addRow()
{
    if (!editable())
        return -1;
    const int r = int(m_rows.size());
    beginInsertRows({}, r, r);
    QVariantList empty;
    for (int i = 0; i < m_columns.size(); ++i)
        empty << QVariant();
    m_rows << empty;
    m_state << Inserted;
    endInsertRows();
    Q_EMIT rowsChanged();
    Q_EMIT changesChanged();
    return r;
}

void GridModel::toggleDelete(int row)
{
    if (!editable() || row < 0 || row >= m_rows.size())
        return;
    State &s = m_state[row];
    s = s == Normal ? Deleted : s == Deleted ? Normal : s == Inserted ? InsertedDeleted : Inserted;
    Q_EMIT dataChanged(index(row, 0), index(row, columnCount() - 1));
    Q_EMIT changesChanged();
}

void GridModel::revertAll()
{
    // Nowe wiersze znikają, reszta wraca do stanu z bazy
    int keep = int(m_rows.size());
    while (keep > 0 && (m_state.at(keep - 1) == Inserted || m_state.at(keep - 1) == InsertedDeleted))
        --keep;
    beginResetModel();
    m_rows = m_rows.mid(0, keep);
    m_state = m_state.mid(0, keep);
    for (State &s : m_state)
        s = Normal;
    m_edits.clear();
    endResetModel();
    Q_EMIT rowsChanged();
    Q_EMIT changesChanged();
}

QString GridModel::cell(int row, int col) const
{
    if (row < 0 || row >= m_rows.size())
        return {};
    return Db::cellText(current(row, dataCol(col)));
}

bool GridModel::isNull(int row, int col) const
{
    if (row < 0 || row >= m_rows.size())
        return true;
    return current(row, dataCol(col)).isNull();
}

QVariantList GridModel::rowValues(int row) const
{
    QVariantList out;
    if (row < 0 || row >= m_rows.size())
        return out;
    const QStringList cols = columns(), ty = types();
    for (int c = 0; c < cols.size(); ++c) {
        const QVariant v = current(row, dataCol(c));
        out << QVariantMap{{QStringLiteral("name"), cols.at(c)}, {QStringLiteral("type"), ty.value(c)},
                           {QStringLiteral("value"), Db::cellText(v)}, {QStringLiteral("null"), v.isNull()},
                           {QStringLiteral("editable"), cellEditable(row, c)}};
    }
    return out;
}

int GridModel::suggestedWidth(int col) const
{
    // Szerokość z nazwy kolumny i pierwszych wierszy (ok. 7,2 px na znak przy 12 px Geist)
    int chars = int(columns().value(col).size()) + 3;
    const int dc = dataCol(col);
    for (int r = 0; r < std::min<int>(int(m_rows.size()), 60); ++r)
        chars = std::max(chars, int(Db::cellText(m_rows.at(r).value(dc), 160).size()));
    return std::clamp(int(chars * 7.2) + 26, 64, 340);
}

QString GridModel::copyText(int row, int col, bool wholeRow) const
{
    if (!wholeRow)
        return cell(row, col);
    QStringList parts;
    for (int c = 0; c < columnCount(); ++c)
        parts << cell(row, c);
    return parts.join(QLatin1Char('\t'));
}

QVariantList GridModel::allRowsAsMaps() const
{
    QVariantList out;
    const QStringList cols = columns();
    for (int r = 0; r < m_rows.size(); ++r) {
        QVariantMap m;
        for (int c = 0; c < cols.size(); ++c)
            m.insert(cols.at(c), Db::jsonValue(current(r, dataCol(c))));
        out << m;
    }
    return out;
}

// Polecenie dla jednego wiersza: SQL z „?”, wartości i czytelna wersja do podglądu
QVariantList GridModel::buildChange(int row, QString *sql, QString *text) const
{
    const Db::Kind k = m_target.kind;
    const QString table = Db::qualified(k, m_target.schema, m_target.table);
    QVariantList binds;
    auto where = [&](QStringList *parts, QStringList *shown) {
        for (int key : m_target.keys) {
            const QString name = m_target.rowid && key == 0 ? QStringLiteral("rowid") : Db::quoteIdent(k, m_columns.at(key));
            const QVariant v = m_rows.at(row).value(key);
            if (v.isNull()) {
                *parts << name + QStringLiteral(" IS NULL");
                *shown << name + QStringLiteral(" IS NULL");
            } else {
                *parts << name + QStringLiteral(" = ?");
                *shown << name + QStringLiteral(" = ") + Db::literal(v);
                binds << v;
            }
        }
    };
    const State s = m_state.at(row);
    const QHash<int, QVariant> edits = m_edits.value(row);
    QList<int> cols = edits.keys();
    std::sort(cols.begin(), cols.end());
    if (s == Deleted) {
        QStringList w, ws;
        where(&w, &ws);
        *sql = QStringLiteral("DELETE FROM %1 WHERE %2").arg(table, w.join(QStringLiteral(" AND ")));
        *text = QStringLiteral("DELETE FROM %1 WHERE %2;").arg(table, ws.join(QStringLiteral(" AND ")));
    } else if (s == Inserted) {
        QStringList names, marks, vals;
        for (int c : std::as_const(cols)) {
            names << Db::quoteIdent(k, m_columns.at(c));
            marks << QStringLiteral("?");
            vals << Db::literal(edits.value(c));
            binds << edits.value(c);
        }
        if (names.isEmpty()) {
            *sql = k == Db::Kind::MySQL ? QStringLiteral("INSERT INTO %1 () VALUES ()").arg(table) : QStringLiteral("INSERT INTO %1 DEFAULT VALUES").arg(table);
            *text = *sql + QLatin1Char(';');
        } else {
            *sql = QStringLiteral("INSERT INTO %1 (%2) VALUES (%3)").arg(table, names.join(QStringLiteral(", ")), marks.join(QStringLiteral(", ")));
            *text = QStringLiteral("INSERT INTO %1 (%2) VALUES (%3);").arg(table, names.join(QStringLiteral(", ")), vals.join(QStringLiteral(", ")));
        }
    } else {
        QStringList set, shown;
        for (int c : std::as_const(cols)) {
            set << Db::quoteIdent(k, m_columns.at(c)) + QStringLiteral(" = ?");
            shown << Db::quoteIdent(k, m_columns.at(c)) + QStringLiteral(" = ") + Db::literal(edits.value(c));
            binds << edits.value(c);
        }
        QStringList w, ws;
        where(&w, &ws);
        *sql = QStringLiteral("UPDATE %1 SET %2 WHERE %3").arg(table, set.join(QStringLiteral(", ")), w.join(QStringLiteral(" AND ")));
        *text = QStringLiteral("UPDATE %1 SET %2 WHERE %3;").arg(table, shown.join(QStringLiteral(", ")), ws.join(QStringLiteral(" AND ")));
    }
    return binds;
}

QVariantList GridModel::preview() const
{
    QVariantList out;
    for (int r = 0; r < m_rows.size(); ++r) {
        const State s = m_state.at(r);
        if (s == InsertedDeleted || (s == Normal && !m_edits.contains(r)))
            continue;
        QString sql, text;
        buildChange(r, &sql, &text);
        out << QVariantMap{{QStringLiteral("kind"), s == Deleted ? QStringLiteral("delete") : s == Inserted ? QStringLiteral("insert") : QStringLiteral("update")},
                           {QStringLiteral("text"), text}, {QStringLiteral("row"), r}};
    }
    return out;
}

QVariantList GridModel::changes() const
{
    QVariantList out;
    for (int r = 0; r < m_rows.size(); ++r) {
        const State s = m_state.at(r);
        if (s == InsertedDeleted || (s == Normal && !m_edits.contains(r)))
            continue;
        QString sql, text;
        const QVariantList binds = buildChange(r, &sql, &text);
        out << QVariantMap{{QStringLiteral("sql"), sql}, {QStringLiteral("binds"), binds}};
    }
    return out;
}

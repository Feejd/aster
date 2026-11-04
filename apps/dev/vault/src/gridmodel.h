#pragma once

#include "dbcore.h"

#include <QAbstractTableModel>
#include <QHash>
#include <QQmlEngine>
#include <QSet>

// Tabela, do której idą zmiany z siatki
struct GridTarget {
    Db::Kind kind = Db::Kind::SQLite;
    QString schema, table;
    QList<int> keys;      // kolumny klucza (indeksy w danych)
    bool rowid = false;   // kolumna 0 to ukryty rowid SQLite
    QString reason;       // dlaczego bez edycji
};

// Siatka wierszy: wynik zapytania (tylko do odczytu) albo zawartość tabeli z edycją.
// Zmiany (komórki, nowe wiersze, usunięte) czekają tutaj, aż użytkownik obejrzy je w podglądzie
// i zatwierdzi — wtedy changes() daje polecenia z parametrami do wykonania w jednej transakcji.
class GridModel : public QAbstractTableModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Siatkę tworzy Vault")
    Q_PROPERTY(QStringList columns READ columns NOTIFY layoutReset)
    Q_PROPERTY(QStringList types READ types NOTIFY layoutReset)
    Q_PROPERTY(int rows READ rows NOTIFY rowsChanged)
    Q_PROPERTY(bool editable READ editable NOTIFY layoutReset)
    Q_PROPERTY(QString readOnlyReason READ readOnlyReason NOTIFY layoutReset)
    Q_PROPERTY(int changeCount READ changeCount NOTIFY changesChanged)

public:
    enum Roles { TextRole = Qt::UserRole + 1, NullRole, EditedRole, StateRole, NumericRole, FullRole };

    using Target = GridTarget;

    explicit GridModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QVariant headerData(int section, Qt::Orientation o, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setResult(const QStringList &columns, const QStringList &types, const QVariantList &rows, const Target &target = Target());
    void appendRows(const QVariantList &rows);
    void clear();

    QStringList columns() const;
    QStringList types() const;
    int rows() const { return int(m_rows.size()); }
    bool editable() const { return !m_target.table.isEmpty() && m_target.reason.isEmpty(); }
    QString readOnlyReason() const { return m_target.reason; }
    int changeCount() const;
    const Target &target() const { return m_target; }

    Q_INVOKABLE bool setCell(int row, int col, const QString &text, bool null);
    Q_INVOKABLE void revertCell(int row, int col);
    Q_INVOKABLE int addRow();
    Q_INVOKABLE void toggleDelete(int row);
    Q_INVOKABLE void revertAll();
    Q_INVOKABLE QString cell(int row, int col) const;           // pełna wartość
    Q_INVOKABLE bool isNull(int row, int col) const;
    Q_INVOKABLE bool cellEditable(int row, int col) const;
    Q_INVOKABLE QVariantList rowValues(int row) const;          // [{ name, type, value, null }] — panel wiersza
    Q_INVOKABLE int suggestedWidth(int col) const;
    Q_INVOKABLE QString copyText(int row, int col, bool wholeRow) const;
    Q_INVOKABLE QVariantList preview() const;                   // [{ kind: update|insert|delete, text }]
    QVariantList changes() const;                               // [{ sql, binds }]
    // Wynik z wiersza do JSON/CSV dla „Kopiuj jako”
    QVariantList allRowsAsMaps() const;

Q_SIGNALS:
    void layoutReset();
    void rowsChanged();
    void changesChanged();

private:
    enum State { Normal, Inserted, Deleted, InsertedDeleted };
    int dataCol(int col) const { return col + (m_target.rowid ? 1 : 0); }
    QVariant current(int row, int dcol) const;
    QVariantList buildChange(int row, QString *sql, QString *text) const;

    QStringList m_columns, m_types;      // z ukrytym rowid na początku, jeśli jest
    QList<QVariantList> m_rows;
    QList<State> m_state;
    QHash<int, QHash<int, QVariant>> m_edits;
    Target m_target;
};

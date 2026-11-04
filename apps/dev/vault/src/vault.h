#pragma once

#include "dbcore.h"
#include "gridmodel.h"

#include <QObject>
#include <QQmlEngine>
#include <QThread>

// Wątek roboczy: jedno połączenie z bazą, zadania po kolei — okno nie zamarza przy wolnych zapytaniach
class DbWorker : public QObject
{
    Q_OBJECT
public:
    Q_INVOKABLE void job(int id, const QString &op, const QVariantMap &args);
Q_SIGNALS:
    void finished(int id, const QString &op, const QVariantMap &result);
private:
    QString m_name = QStringLiteral("vault-ui");
    Db::Kind m_kind = Db::Kind::SQLite;
    bool m_open = false;
};

// Stan okna Aster Vault: zapisane połączenia, otwarta baza, tabela z edycją, edytor zapytań
class Vault : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList connections READ connections NOTIFY connectionsChanged)
    Q_PROPERTY(QVariantList recentFiles READ recentFiles NOTIFY connectionsChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)                 // start | connecting | open
    Q_PROPERTY(QVariantMap current READ current NOTIFY stateChanged)
    Q_PROPERTY(QString kindName READ kindName NOTIFY stateChanged)
    Q_PROPERTY(bool readOnly READ readOnly NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QStringList databases READ databases NOTIFY objectsChanged)
    Q_PROPERTY(QString database READ database NOTIFY objectsChanged)
    Q_PROPERTY(QVariantList objects READ objects NOTIFY objectsChanged)
    Q_PROPERTY(QStringList tableNames READ tableNames NOTIFY objectsChanged)
    Q_PROPERTY(QVariantList drivers READ drivers CONSTANT)

    // Otwarta tabela
    Q_PROPERTY(QString tableSchema READ tableSchema NOTIFY tableChanged)
    Q_PROPERTY(QString tableName READ tableName NOTIFY tableChanged)
    Q_PROPERTY(QVariantMap tableInfo READ tableInfo NOTIFY tableInfoChanged)  // kolumny, indeksy, klucze, DDL
    Q_PROPERTY(GridModel *table READ table CONSTANT)
    Q_PROPERTY(QString filter READ filter NOTIFY tableChanged)
    Q_PROPERTY(QString order READ order NOTIFY tableChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY tableLoaded)
    Q_PROPERTY(bool tableLoading READ tableLoading NOTIFY tableLoaded)
    Q_PROPERTY(QString tableError READ tableError NOTIFY tableLoaded)

    // Zapytania
    Q_PROPERTY(GridModel *result READ result CONSTANT)
    Q_PROPERTY(QVariantMap lastRun READ lastRun NOTIFY lastRunChanged)       // { ok, error, ms, messages, truncated, select, affected, sql }
    Q_PROPERTY(bool running READ running NOTIFY lastRunChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)

public:
    explicit Vault(QObject *parent = nullptr);
    ~Vault() override;

    QVariantList connections() const { return m_connections; }
    QVariantList recentFiles() const;
    QString state() const { return m_state; }
    QVariantMap current() const { return m_current; }
    QString kindName() const { return Db::kindName(Db::kindOf(m_current)); }
    bool readOnly() const { return m_current.value(QStringLiteral("readOnly")).toBool(); }
    QString error() const { return m_error; }
    bool busy() const { return m_pending > 0; }
    QStringList databases() const { return m_databases; }
    QString database() const { return m_current.value(QStringLiteral("database")).toString(); }
    QVariantList objects() const { return m_objects; }
    QStringList tableNames() const;
    QVariantList drivers() const;
    QString tableSchema() const { return m_tableSchema; }
    QString tableName() const { return m_tableName; }
    QVariantMap tableInfo() const { return m_tableInfo; }
    GridModel *table() const { return m_table; }
    QString filter() const { return m_filter; }
    QString order() const { return m_order; }
    bool hasMore() const { return m_hasMore; }
    bool tableLoading() const { return m_tableLoading; }
    QString tableError() const { return m_tableError; }
    GridModel *result() const { return m_result; }
    QVariantMap lastRun() const { return m_lastRun; }
    bool running() const { return m_running; }
    QVariantList history() const;

    // Połączenia
    Q_INVOKABLE QString saveConnection(const QVariantMap &conn, const QString &password);
    Q_INVOKABLE void removeConnection(const QString &id);
    Q_INVOKABLE QVariantMap connection(const QString &id) const;
    Q_INVOKABLE bool hasPassword(const QString &id) const;
    Q_INVOKABLE void testConnection(const QVariantMap &conn, const QString &password);
    Q_INVOKABLE void open(const QString &id, const QString &password = QString());
    Q_INVOKABLE void openFile(const QString &pathOrUrl, bool create = false);
    Q_INVOKABLE void close();
    Q_INVOKABLE void useDatabase(const QString &name);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void clearError() { setError(QString()); }

    // Tabela
    Q_INVOKABLE void selectTable(const QString &schemaName, const QString &name);
    Q_INVOKABLE void setFilter(const QString &where);
    Q_INVOKABLE void sortBy(const QString &column);       // kolejno: rosnąco → malejąco → bez
    Q_INVOKABLE void loadMore();
    Q_INVOKABLE void reloadTable();
    Q_INVOKABLE void commitChanges();

    // Zapytania
    Q_INVOKABLE bool risky(const QString &sql) const;
    Q_INVOKABLE void runQuery(const QString &sql);
    Q_INVOKABLE QString statementAt(const QString &text, int cursor) const;  // polecenie pod kursorem
    Q_INVOKABLE QVariantList completions(const QString &text, int cursor) const;
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE QString selectSql(const QString &schemaName, const QString &name) const;

    // Eksport: what = table | result; format = csv | json
    Q_INVOKABLE void exportTo(const QString &what, const QString &pathOrUrl, const QString &format);
    Q_INVOKABLE QString suggestedExportPath(const QString &what, const QString &format) const;
    Q_INVOKABLE void copy(const QString &text) const;
    Q_INVOKABLE QString toLocalPath(const QString &url) const;
    Q_INVOKABLE bool fileExists(const QString &path) const;
    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE QString formatMs(qint64 ms) const;

Q_SIGNALS:
    void connectionsChanged();
    void stateChanged();
    void errorChanged();
    void busyChanged();
    void objectsChanged();
    void tableChanged();
    void tableInfoChanged();
    void tableLoaded();
    void lastRunChanged();
    void historyChanged();
    void passwordNeeded(const QString &id, const QString &message);
    void tested(bool ok, const QString &message);
    void message(const QString &text);
    void committed(bool ok, const QString &message);

private:
    int post(const QString &op, const QVariantMap &args = {});
    void onFinished(int id, const QString &op, const QVariantMap &r);
    void setError(const QString &e);
    void setState(const QString &s);
    void connectWith(const QVariantMap &conn, const QString &password);
    void loadPage(bool append);
    QString tableQuery(bool withLimit) const;
    void touchConnection(const QString &id);

    QThread m_thread;
    DbWorker *m_worker = nullptr;
    int m_seq = 0, m_pending = 0;
    int m_tableJob = -1, m_queryJob = -1;
    QVariantList m_connections;
    QString m_state = QStringLiteral("start");
    QVariantMap m_current;
    QString m_password;            // tylko w pamięci, na czas otwartego połączenia
    QString m_error;
    QStringList m_databases;
    QVariantList m_objects;
    QVariantMap m_columns;         // { tabela: [kolumny] } — podpowiedzi
    QString m_tableSchema, m_tableName, m_filter, m_order, m_tableError;
    QVariantMap m_tableInfo;
    bool m_hasMore = false, m_tableLoading = false, m_running = false;
    int m_offset = 0;
    GridModel *m_table = nullptr;
    GridModel *m_result = nullptr;
    QVariantMap m_lastRun;
    QString m_lastSql;
};

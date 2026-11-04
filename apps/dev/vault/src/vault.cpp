#include "vault.h"

#include "secrets.h"
#include "store.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSet>
#include <QSqlDatabase>
#include <QStandardPaths>
#include <QUrl>

namespace {
constexpr int kPage = 200;          // wierszy tabeli na raz
constexpr int kMaxResult = 2000;    // wierszy wyniku zapytania w siatce (eksport bierze wszystkie)

const QStringList &keywords()
{
    static const QStringList k = QStringLiteral(
        "SELECT FROM WHERE AND OR NOT NULL IS IN LIKE ILIKE BETWEEN EXISTS JOIN LEFT RIGHT INNER OUTER FULL CROSS ON USING "
        "GROUP BY ORDER ASC DESC HAVING LIMIT OFFSET DISTINCT AS CASE WHEN THEN ELSE END UNION ALL INTERSECT EXCEPT "
        "INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE VIEW INDEX UNIQUE PRIMARY KEY FOREIGN REFERENCES DEFAULT "
        "ALTER ADD COLUMN DROP RENAME TO TRUNCATE BEGIN COMMIT ROLLBACK TRANSACTION WITH RECURSIVE RETURNING EXPLAIN "
        "ANALYZE SHOW DESCRIBE PRAGMA COUNT SUM AVG MIN MAX COALESCE CAST LOWER UPPER LENGTH SUBSTR TRIM NOW TRUE FALSE "
        "INTEGER TEXT VARCHAR BOOLEAN DATE TIMESTAMP NUMERIC REAL BLOB SERIAL BIGINT").split(QLatin1Char(' '));
    return k;
}

// Granice poleceń (średniki poza napisami i komentarzami)
QList<QPair<int, int>> statementRanges(const QString &sql)
{
    QList<QPair<int, int>> out;
    int start = 0;
    const int n = int(sql.size());
    for (int i = 0; i < n; ++i) {
        const QChar c = sql.at(i);
        const QChar next = i + 1 < n ? sql.at(i + 1) : QChar();
        if (c == QLatin1Char('-') && next == QLatin1Char('-')) {
            const int e = int(sql.indexOf(QLatin1Char('\n'), i));
            i = e < 0 ? n : e;
        } else if (c == QLatin1Char('/') && next == QLatin1Char('*')) {
            const int e = int(sql.indexOf(QLatin1String("*/"), i + 2));
            i = e < 0 ? n : e + 1;
        } else if (c == QLatin1Char('\'') || c == QLatin1Char('"') || c == QLatin1Char('`')) {
            int j = i + 1;
            while (j < n && sql.at(j) != c)
                ++j;
            i = j;
        } else if (c == QLatin1Char(';')) {
            out << qMakePair(start, i);
            start = i + 1;
        }
    }
    out << qMakePair(start, n);
    return out;
}
} // namespace

// ——— Wątek roboczy ———

void DbWorker::job(int id, const QString &op, const QVariantMap &a)
{
    QVariantMap r;
    if (op == QLatin1String("connect") || op == QLatin1String("test")) {
        const QVariantMap conn = a.value(QStringLiteral("conn")).toMap();
        const QString name = op == QLatin1String("test") ? QStringLiteral("vault-test") : m_name;
        QString err;
        const bool ok = Db::open(name, conn, a.value(QStringLiteral("password")).toString(), conn.value(QStringLiteral("readOnly")).toBool(), &err);
        r.insert(QStringLiteral("ok"), ok);
        r.insert(QStringLiteral("error"), err);
        if (op == QLatin1String("test")) {
            if (ok) {
                QSqlDatabase db = QSqlDatabase::database(name, false);
                const Db::Kind k = Db::kindOf(conn);
                r.insert(QStringLiteral("count"), Db::objects(db, k).size());
            }
            Db::close(name);
        } else if (ok) {
            m_open = true;
            m_kind = Db::kindOf(conn);
            QSqlDatabase db = QSqlDatabase::database(m_name, false);
            r.insert(QStringLiteral("databases"), Db::databases(db, m_kind));
            r.insert(QStringLiteral("objects"), Db::objects(db, m_kind));
            r.insert(QStringLiteral("columns"), Db::allColumns(db, m_kind));
        }
    } else if (op == QLatin1String("close")) {
        Db::close(m_name);
        m_open = false;
        r.insert(QStringLiteral("ok"), true);
    } else if (!m_open) {
        r.insert(QStringLiteral("ok"), false);
        r.insert(QStringLiteral("error"), QStringLiteral("Brak połączenia z bazą"));
    } else {
        QSqlDatabase db = QSqlDatabase::database(m_name, false);
        if (op == QLatin1String("refresh")) {
            r.insert(QStringLiteral("ok"), true);
            r.insert(QStringLiteral("databases"), Db::databases(db, m_kind));
            r.insert(QStringLiteral("objects"), Db::objects(db, m_kind));
            r.insert(QStringLiteral("columns"), Db::allColumns(db, m_kind));
        } else if (op == QLatin1String("schema")) {
            r = Db::schema(db, m_kind, a.value(QStringLiteral("schema")).toString(), a.value(QStringLiteral("table")).toString());
            r.insert(QStringLiteral("ok"), true);
        } else if (op == QLatin1String("page")) {
            r = Db::run(db, a.value(QStringLiteral("sql")).toString(), a.value(QStringLiteral("limit")).toInt());
            r.insert(QStringLiteral("append"), a.value(QStringLiteral("append")));
        } else if (op == QLatin1String("query")) {
            r = Db::runScript(db, a.value(QStringLiteral("sql")).toString(), kMaxResult, a.value(QStringLiteral("readOnly")).toBool());
        } else if (op == QLatin1String("apply")) {
            r = Db::applyChanges(db, a.value(QStringLiteral("changes")).toList());
        } else if (op == QLatin1String("export")) {
            r = Db::exportQuery(db, a.value(QStringLiteral("sql")).toString(), a.value(QStringLiteral("path")).toString(),
                                a.value(QStringLiteral("format")).toString());
        }
    }
    Q_EMIT finished(id, op, r);
}

// ——— Vault ———

Vault::Vault(QObject *parent)
    : QObject(parent)
    , m_table(new GridModel(this))
    , m_result(new GridModel(this))
{
    m_connections = Store::connections();
    m_worker = new DbWorker;
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(m_worker, &DbWorker::finished, this, &Vault::onFinished, Qt::QueuedConnection);
    m_thread.start();
}

Vault::~Vault()
{
    QMetaObject::invokeMethod(m_worker, "job", Qt::BlockingQueuedConnection, Q_ARG(int, 0), Q_ARG(QString, QStringLiteral("close")), Q_ARG(QVariantMap, {}));
    m_thread.quit();
    m_thread.wait(3000);
}

int Vault::post(const QString &op, const QVariantMap &args)
{
    const int id = ++m_seq;
    ++m_pending;
    Q_EMIT busyChanged();
    QMetaObject::invokeMethod(m_worker, "job", Qt::QueuedConnection, Q_ARG(int, id), Q_ARG(QString, op), Q_ARG(QVariantMap, args));
    return id;
}

void Vault::setError(const QString &e)
{
    if (e == m_error)
        return;
    m_error = e;
    Q_EMIT errorChanged();
}

void Vault::setState(const QString &s)
{
    m_state = s;
    Q_EMIT stateChanged();
}

QVariantList Vault::recentFiles() const
{
    QVariantList out;
    for (const QVariant &v : m_connections)
        if (v.toMap().value(QStringLiteral("kind")).toString() == QLatin1String("sqlite"))
            out << v;
    return out;
}

QStringList Vault::tableNames() const
{
    QStringList out;
    for (const QVariant &o : m_objects) {
        const QVariantMap m = o.toMap();
        const QString s = m.value(QStringLiteral("schema")).toString();
        const bool prefix = !s.isEmpty() && Db::kindOf(m_current) == Db::Kind::Postgres && s != QLatin1String("public");
        out << (prefix ? s + QLatin1Char('.') : QString()) + m.value(QStringLiteral("name")).toString();
    }
    return out;
}

QVariantList Vault::drivers() const
{
    QVariantList out;
    const QList<QPair<QString, Db::Kind>> kinds{{QStringLiteral("sqlite"), Db::Kind::SQLite}, {QStringLiteral("postgres"), Db::Kind::Postgres},
                                                {QStringLiteral("mysql"), Db::Kind::MySQL}};
    for (const auto &k : kinds)
        out << QVariantMap{{QStringLiteral("kind"), k.first}, {QStringLiteral("name"), Db::kindName(k.second)},
                           {QStringLiteral("available"), Db::driverAvailable(k.second)}, {QStringLiteral("port"), Db::defaultPort(k.second)}};
    return out;
}

QVariantList Vault::history() const
{
    return Store::history(m_current.value(QStringLiteral("id")).toString(), 200);
}

// ——— Połączenia ———

QVariantMap Vault::connection(const QString &id) const
{
    for (const QVariant &v : m_connections)
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            return v.toMap();
    return {};
}

bool Vault::hasPassword(const QString &id) const
{
    QString err;
    return !Secrets::get(id, &err).isEmpty();
}

QString Vault::saveConnection(const QVariantMap &input, const QString &password)
{
    QVariantMap conn = input;
    QString id = conn.value(QStringLiteral("id")).toString();
    if (id.isEmpty()) {
        id = Store::newId();
        conn.insert(QStringLiteral("id"), id);
    }
    if (conn.value(QStringLiteral("name")).toString().trimmed().isEmpty()) {
        const QString file = conn.value(QStringLiteral("file")).toString();
        conn.insert(QStringLiteral("name"), !file.isEmpty() ? QFileInfo(file).fileName()
                                                            : conn.value(QStringLiteral("database")).toString() + QStringLiteral(" @ ") + conn.value(QStringLiteral("host")).toString());
    }
    if (!conn.contains(QStringLiteral("agent")))
        conn.insert(QStringLiteral("agent"), true);
    bool found = false;
    for (QVariant &v : m_connections) {
        if (v.toMap().value(QStringLiteral("id")).toString() == id) {
            QVariantMap merged = v.toMap();
            for (auto it = conn.cbegin(); it != conn.cend(); ++it)
                merged.insert(it.key(), it.value());
            v = merged;
            found = true;
        }
    }
    if (!found)
        m_connections.prepend(conn);
    Store::saveConnections(m_connections);
    // Hasło: do portfela albo nigdzie (pytanie przy każdym połączeniu)
    if (conn.value(QStringLiteral("kind")).toString() != QLatin1String("sqlite")) {
        QString err;
        if (!conn.value(QStringLiteral("savePassword")).toBool())
            Secrets::remove(id, &err);
        else if (!password.isEmpty() && !Secrets::set(id, conn.value(QStringLiteral("name")).toString(), password, &err))
            Q_EMIT message(err.isEmpty() ? QStringLiteral("Nie udało się zapisać hasła w portfelu") : err);
    }
    Q_EMIT connectionsChanged();
    return id;
}

void Vault::removeConnection(const QString &id)
{
    for (int i = 0; i < m_connections.size(); ++i)
        if (m_connections.at(i).toMap().value(QStringLiteral("id")).toString() == id)
            m_connections.removeAt(i--);
    Store::saveConnections(m_connections);
    QString err;
    Secrets::remove(id, &err);
    Store::clearHistory(id);
    Q_EMIT connectionsChanged();
}

void Vault::touchConnection(const QString &id)
{
    for (int i = 0; i < m_connections.size(); ++i) {
        QVariantMap m = m_connections.at(i).toMap();
        if (m.value(QStringLiteral("id")).toString() == id) {
            m.insert(QStringLiteral("lastUsed"), QDateTime::currentDateTime().toString(Qt::ISODate));
            m_connections.removeAt(i);
            m_connections.prepend(m);
            Store::saveConnections(m_connections);
            Q_EMIT connectionsChanged();
            return;
        }
    }
}

void Vault::testConnection(const QVariantMap &conn, const QString &password)
{
    QString pw = password;
    if (pw.isEmpty() && !conn.value(QStringLiteral("id")).toString().isEmpty() && conn.value(QStringLiteral("savePassword")).toBool()) {
        QString err;
        pw = Secrets::get(conn.value(QStringLiteral("id")).toString(), &err);
    }
    post(QStringLiteral("test"), {{QStringLiteral("conn"), conn}, {QStringLiteral("password"), pw}});
}

void Vault::open(const QString &id, const QString &password)
{
    const QVariantMap conn = connection(id);
    if (conn.isEmpty())
        return;
    QString pw = password;
    if (Db::kindOf(conn) != Db::Kind::SQLite && pw.isEmpty()) {
        if (conn.value(QStringLiteral("savePassword")).toBool()) {
            QString err;
            pw = Secrets::get(id, &err);
            if (pw.isEmpty() && !err.isEmpty())
                Q_EMIT message(err);
        } else if (conn.value(QStringLiteral("askPassword"), true).toBool()) {
            Q_EMIT passwordNeeded(id, QString());
            return;
        }
    }
    connectWith(conn, pw);
}

void Vault::connectWith(const QVariantMap &conn, const QString &password)
{
    if (m_state == QLatin1String("open"))
        post(QStringLiteral("close"));
    m_current = conn;
    m_password = password;
    m_objects.clear();
    m_databases.clear();
    m_columns.clear();
    m_tableName.clear();
    m_tableSchema.clear();
    m_tableInfo.clear();
    m_table->clear();
    m_result->clear();
    m_lastRun.clear();
    setError(QString());
    setState(QStringLiteral("connecting"));
    Q_EMIT objectsChanged();
    Q_EMIT tableChanged();
    Q_EMIT tableInfoChanged();
    Q_EMIT lastRunChanged();
    post(QStringLiteral("connect"), {{QStringLiteral("conn"), conn}, {QStringLiteral("password"), password}});
}

void Vault::openFile(const QString &pathOrUrl, bool create)
{
    const QString path = QFileInfo(toLocalPath(pathOrUrl)).absoluteFilePath();
    if (!create && !QFileInfo(path).isFile()) {
        setError(QStringLiteral("Nie ma pliku %1").arg(path));
        return;
    }
    QString id;
    for (const QVariant &v : std::as_const(m_connections))
        if (v.toMap().value(QStringLiteral("file")).toString() == path)
            id = v.toMap().value(QStringLiteral("id")).toString();
    if (id.isEmpty())
        id = saveConnection({{QStringLiteral("kind"), QStringLiteral("sqlite")}, {QStringLiteral("file"), path},
                             {QStringLiteral("name"), QFileInfo(path).fileName()}}, QString());
    open(id);
}

void Vault::close()
{
    post(QStringLiteral("close"));
    m_current.clear();
    m_password.clear();
    m_objects.clear();
    m_databases.clear();
    m_tableName.clear();
    m_table->clear();
    m_result->clear();
    m_lastRun.clear();
    setError(QString());
    setState(QStringLiteral("start"));
    Q_EMIT objectsChanged();
    Q_EMIT tableChanged();
    Q_EMIT lastRunChanged();
    Q_EMIT historyChanged();
}

void Vault::useDatabase(const QString &name)
{
    if (name == database())
        return;
    QVariantMap conn = m_current;
    conn.insert(QStringLiteral("database"), name);
    connectWith(conn, m_password);
}

void Vault::refresh()
{
    if (m_state == QLatin1String("open"))
        post(QStringLiteral("refresh"));
}

// ——— Tabela ———

QString Vault::tableQuery(bool withLimit) const
{
    const Db::Kind k = Db::kindOf(m_current);
    QString sql = QStringLiteral("SELECT ");
    if (m_table->target().rowid)
        sql += QStringLiteral("rowid AS \"__rowid__\", ");
    sql += QStringLiteral("* FROM ") + Db::qualified(k, m_tableSchema, m_tableName);
    if (!m_filter.trimmed().isEmpty())
        sql += QStringLiteral(" WHERE ") + m_filter.trimmed();
    if (!m_order.isEmpty()) {
        sql += QStringLiteral(" ORDER BY ") + m_order;
    } else {
        // Bez ORDER BY serwer może zwracać wiersze w dowolnej kolejności — strony (OFFSET) by się mieszały
        QStringList pk;
        if (m_table->target().rowid)
            pk << QStringLiteral("rowid");
        else
            for (const QString &c : m_tableInfo.value(QStringLiteral("primaryKey")).toStringList())
                pk << Db::quoteIdent(k, c);
        if (!pk.isEmpty())
            sql += QStringLiteral(" ORDER BY ") + pk.join(QStringLiteral(", "));
    }
    if (withLimit)
        sql += QStringLiteral(" LIMIT %1 OFFSET %2").arg(kPage + 1).arg(m_offset);
    return sql;
}

QString Vault::selectSql(const QString &schemaName, const QString &name) const
{
    return QStringLiteral("SELECT * FROM %1 LIMIT 100;").arg(Db::qualified(Db::kindOf(m_current), schemaName, name));
}

void Vault::selectTable(const QString &schemaName, const QString &name)
{
    m_tableSchema = schemaName;
    m_tableName = name;
    m_filter.clear();
    m_order.clear();
    m_tableInfo.clear();
    m_tableError.clear();
    m_table->clear();
    m_hasMore = false;
    m_tableLoading = true;
    Q_EMIT tableChanged();
    Q_EMIT tableInfoChanged();
    Q_EMIT tableLoaded();
    // Najpierw struktura (klucz główny decyduje o edycji), potem pierwsza strona
    m_tableJob = post(QStringLiteral("schema"), {{QStringLiteral("schema"), schemaName}, {QStringLiteral("table"), name}});
}

void Vault::loadPage(bool append)
{
    if (m_tableName.isEmpty())
        return;
    if (!append)
        m_offset = 0;
    m_tableLoading = true;
    Q_EMIT tableLoaded();
    m_tableJob = post(QStringLiteral("page"), {{QStringLiteral("sql"), tableQuery(true)}, {QStringLiteral("limit"), kPage}, {QStringLiteral("append"), append}});
}

void Vault::setFilter(const QString &where)
{
    m_filter = where;
    Q_EMIT tableChanged();
    loadPage(false);
}

void Vault::sortBy(const QString &column)
{
    const QString q = Db::quoteIdent(Db::kindOf(m_current), column);
    if (m_order == q)
        m_order = q + QStringLiteral(" DESC");
    else if (m_order == q + QStringLiteral(" DESC"))
        m_order.clear();
    else
        m_order = q;
    Q_EMIT tableChanged();
    loadPage(false);
}

void Vault::loadMore()
{
    if (!m_hasMore || m_tableLoading)
        return;
    m_offset += kPage;
    loadPage(true);
}

void Vault::reloadTable() { loadPage(false); }

void Vault::commitChanges()
{
    const QVariantList changes = m_table->changes();
    if (changes.isEmpty() || readOnly())
        return;
    post(QStringLiteral("apply"), {{QStringLiteral("changes"), changes}});
}

// ——— Zapytania ———

bool Vault::risky(const QString &sql) const
{
    for (const QString &s : Db::splitStatements(sql))
        if (Db::isRisky(s))
            return true;
    return false;
}

void Vault::runQuery(const QString &sql)
{
    if (m_state != QLatin1String("open") || sql.trimmed().isEmpty())
        return;
    m_running = true;
    m_lastSql = sql;
    Q_EMIT lastRunChanged();
    m_queryJob = post(QStringLiteral("query"), {{QStringLiteral("sql"), sql}, {QStringLiteral("readOnly"), readOnly()}});
}

QString Vault::statementAt(const QString &text, int cursor) const
{
    for (const auto &r : statementRanges(text)) {
        if (cursor >= r.first && cursor <= r.second) {
            const QString s = text.mid(r.first, r.second - r.first).trimmed();
            if (!s.isEmpty())
                return s;
        }
    }
    // Kursor za ostatnim średnikiem w pustym miejscu — poprzednie polecenie
    const auto ranges = statementRanges(text.left(cursor));
    for (int i = int(ranges.size()) - 1; i >= 0; --i) {
        const QString s = text.mid(ranges.at(i).first, ranges.at(i).second - ranges.at(i).first).trimmed();
        if (!s.isEmpty())
            return s;
    }
    return {};
}

QVariantList Vault::completions(const QString &text, int cursor) const
{
    const QString before = text.left(cursor);
    static const QRegularExpression wordRe(QStringLiteral("([A-Za-z_][\\w$]*\\.)?([\\w$]*)$"));
    const auto m = wordRe.match(before);
    const QString qualifier = m.captured(1).chopped(m.captured(1).isEmpty() ? 0 : 1);
    const QString prefix = m.captured(2);

    // Tabele wymienione w zapytaniu i ich skróty: FROM klienci k, JOIN zamowienia AS z
    QHash<QString, QString> alias;
    QStringList used;
    static const QRegularExpression fromRe(QStringLiteral("\\b(?:FROM|JOIN|UPDATE|INTO|TABLE)\\s+([\\w$.\"`]+)(?:\\s+(?:AS\\s+)?([A-Za-z_]\\w*))?"),
                                           QRegularExpression::CaseInsensitiveOption);
    static const QSet<QString> notAlias{QStringLiteral("WHERE"), QStringLiteral("JOIN"), QStringLiteral("ON"), QStringLiteral("LEFT"),
                                        QStringLiteral("RIGHT"), QStringLiteral("INNER"), QStringLiteral("GROUP"), QStringLiteral("ORDER"),
                                        QStringLiteral("LIMIT"), QStringLiteral("SET"), QStringLiteral("VALUES"), QStringLiteral("USING"),
                                        QStringLiteral("OUTER"), QStringLiteral("CROSS"), QStringLiteral("FULL"), QStringLiteral("HAVING"),
                                        QStringLiteral("UNION"), QStringLiteral("NATURAL")};
    auto it = fromRe.globalMatch(text);
    while (it.hasNext()) {
        const auto fm = it.next();
        QString t = fm.captured(1);
        t.remove(QLatin1Char('"')).remove(QLatin1Char('`'));
        // „public.tabela” → „tabela”
        if (t.startsWith(QLatin1String("public.")))
            t = t.mid(7);
        if (!m_columns.contains(t)) {
            // bez wielkości liter
            for (auto c = m_columns.cbegin(); c != m_columns.cend(); ++c)
                if (c.key().compare(t, Qt::CaseInsensitive) == 0)
                    t = c.key();
        }
        if (!m_columns.contains(t))
            continue;
        used << t;
        alias.insert(t.toLower(), t);
        if (!fm.captured(2).isEmpty() && !notAlias.contains(fm.captured(2).toUpper()))
            alias.insert(fm.captured(2).toLower(), t);
    }

    QVariantList out;
    const QString p = prefix.toLower();
    auto add = [&](const QString &label, const QString &kind, const QString &detail) {
        if (out.size() >= 60)
            return;
        if (!p.isEmpty() && !label.toLower().startsWith(p))
            return;
        out << QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("insert"), label}, {QStringLiteral("kind"), kind},
                           {QStringLiteral("detail"), detail}};
    };

    if (!qualifier.isEmpty()) {
        const QString t = alias.value(qualifier.toLower(), m_columns.contains(qualifier) ? qualifier : QString());
        if (!t.isEmpty())
            for (const QString &c : m_columns.value(t).toStringList())
                add(c, QStringLiteral("column"), t);
        // Schemat PostgreSQL: „sklep.” → tabele w nim
        for (auto c = m_columns.cbegin(); c != m_columns.cend(); ++c)
            if (c.key().startsWith(qualifier + QLatin1Char('.')))
                add(c.key().mid(qualifier.size() + 1), QStringLiteral("table"), qualifier);
        return out;
    }

    // Po FROM/JOIN/INTO/UPDATE najpierw tabele, gdzie indziej — kolumny użytych tabel
    static const QRegularExpression lastKw(QStringLiteral("\\b(FROM|JOIN|INTO|UPDATE|TABLE|SELECT|WHERE|BY|SET|ON|AND|OR|HAVING)\\b[^\\w]*[\\w$]*$"),
                                           QRegularExpression::CaseInsensitiveOption);
    const QString kw = lastKw.match(before).captured(1).toUpper();
    const bool tablesFirst = kw == QLatin1String("FROM") || kw == QLatin1String("JOIN") || kw == QLatin1String("INTO")
        || kw == QLatin1String("UPDATE") || kw == QLatin1String("TABLE");
    auto addTables = [&] {
        for (const QString &t : tableNames())
            add(t, QStringLiteral("table"), QString());
    };
    auto addColumns = [&] {
        QSet<QString> seen;
        for (const QString &t : std::as_const(used))
            for (const QString &c : m_columns.value(t).toStringList())
                if (!seen.contains(c)) {
                    seen.insert(c);
                    add(c, QStringLiteral("column"), t);
                }
    };
    if (tablesFirst) {
        addTables();
    } else {
        addColumns();
        addTables();
    }
    if (!p.isEmpty())
        for (const QString &k : keywords())
            add(k, QStringLiteral("keyword"), QString());
    return out;
}

void Vault::clearHistory()
{
    Store::clearHistory(m_current.value(QStringLiteral("id")).toString());
    Q_EMIT historyChanged();
}

// ——— Eksport i drobiazgi ———

QString Vault::suggestedExportPath(const QString &what, const QString &format) const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty() || !QDir(dir).exists())
        dir = QDir::homePath();
    const QString base = what == QLatin1String("table") && !m_tableName.isEmpty() ? m_tableName : QStringLiteral("wynik");
    return dir + QLatin1Char('/') + base + QLatin1Char('.') + format;
}

void Vault::exportTo(const QString &what, const QString &pathOrUrl, const QString &format)
{
    QString sql;
    if (what == QLatin1String("table")) {
        sql = tableQuery(false);
    } else {
        sql = m_lastRun.value(QStringLiteral("sql")).toString();
        if (!m_lastRun.value(QStringLiteral("select")).toBool())
            sql.clear();
    }
    if (sql.isEmpty()) {
        Q_EMIT message(QStringLiteral("Nie ma czego wyeksportować"));
        return;
    }
    // Wynik zapytania w trybie tylko do odczytu też musi być zapytaniem tylko do odczytu
    if (readOnly() && !Db::isReadOnlyStatement(sql))
        return;
    post(QStringLiteral("export"), {{QStringLiteral("sql"), sql}, {QStringLiteral("path"), toLocalPath(pathOrUrl)}, {QStringLiteral("format"), format}});
}

void Vault::copy(const QString &text) const { QGuiApplication::clipboard()->setText(text); }

QString Vault::toLocalPath(const QString &url) const
{
    const QUrl u(url);
    return u.isLocalFile() ? u.toLocalFile() : url;
}

bool Vault::fileExists(const QString &path) const { return QFileInfo::exists(toLocalPath(path)); }

QString Vault::homePath() const { return QDir::homePath(); }

QString Vault::formatMs(qint64 ms) const
{
    if (ms < 1000)
        return QStringLiteral("%1 ms").arg(ms);
    return QStringLiteral("%1 s").arg(QString::number(ms / 1000.0, 'f', ms < 10000 ? 2 : 1).replace(QLatin1Char('.'), QLatin1Char(',')));
}

// ——— Wyniki z wątku ———

void Vault::onFinished(int id, const QString &op, const QVariantMap &r)
{
    --m_pending;
    Q_EMIT busyChanged();
    const bool ok = r.value(QStringLiteral("ok")).toBool();
    const QString err = r.value(QStringLiteral("error")).toString();

    if (op == QLatin1String("test")) {
        Q_EMIT tested(ok, ok ? QStringLiteral("Połączono — obiektów w bazie: %1").arg(r.value(QStringLiteral("count")).toInt()) : err);
    } else if (op == QLatin1String("connect")) {
        if (!ok) {
            const QString id2 = m_current.value(QStringLiteral("id")).toString();
            setState(QStringLiteral("start"));
            setError(err);
            const QString low = err.toLower();
            if (Db::kindOf(m_current) != Db::Kind::SQLite && (low.contains(QLatin1String("hasło")) || low.contains(QLatin1String("password"))))
                Q_EMIT passwordNeeded(id2, err);
            return;
        }
        m_databases = r.value(QStringLiteral("databases")).toStringList();
        m_objects = r.value(QStringLiteral("objects")).toList();
        m_columns = r.value(QStringLiteral("columns")).toMap();
        touchConnection(m_current.value(QStringLiteral("id")).toString());
        setState(QStringLiteral("open"));
        Q_EMIT objectsChanged();
        Q_EMIT historyChanged();
    } else if (op == QLatin1String("refresh")) {
        if (ok) {
            m_databases = r.value(QStringLiteral("databases")).toStringList();
            m_objects = r.value(QStringLiteral("objects")).toList();
            m_columns = r.value(QStringLiteral("columns")).toMap();
            Q_EMIT objectsChanged();
        }
    } else if (op == QLatin1String("schema")) {
        if (id != m_tableJob)
            return;
        m_tableInfo = r;
        Q_EMIT tableInfoChanged();
        // Klucz do edycji: klucz główny, w SQLite bez niego — ukryty rowid; widoki i tabele bez klucza tylko do odczytu
        GridModel::Target t;
        t.kind = Db::kindOf(m_current);
        t.schema = m_tableSchema;
        t.table = m_tableName;
        const QStringList pk = r.value(QStringLiteral("primaryKey")).toStringList();
        if (readOnly())
            t.reason = QStringLiteral("Połączenie tylko do odczytu");
        else if (r.value(QStringLiteral("type")).toString() == QLatin1String("view"))
            t.reason = QStringLiteral("Widok — dane zmienia się w tabelach, z których powstaje");
        else if (pk.isEmpty() && t.kind == Db::Kind::SQLite && !r.value(QStringLiteral("ddl")).toString().contains(QLatin1String("WITHOUT ROWID"), Qt::CaseInsensitive))
            t.rowid = true;
        else if (pk.isEmpty())
            t.reason = QStringLiteral("Tabela bez klucza głównego — nie da się wskazać, który wiersz zmienić");
        // Kolumny klucza poznamy po nagłówku strony; tymczasowo pusty model z celem
        m_table->setResult({}, {}, {}, t);
        m_tableJob = -1;
        loadPage(false);
    } else if (op == QLatin1String("page")) {
        if (id != m_tableJob)
            return;
        m_tableLoading = false;
        if (!ok) {
            m_tableError = err;
            m_hasMore = false;
            Q_EMIT tableLoaded();
            return;
        }
        m_tableError.clear();
        m_hasMore = r.value(QStringLiteral("truncated")).toBool();
        if (r.value(QStringLiteral("append")).toBool()) {
            m_table->appendRows(r.value(QStringLiteral("rows")).toList());
        } else {
            GridModel::Target t = m_table->target();
            const QStringList cols = r.value(QStringLiteral("columns")).toStringList();
            t.keys.clear();
            if (t.rowid) {
                t.keys << 0;
            } else {
                for (const QString &k : m_tableInfo.value(QStringLiteral("primaryKey")).toStringList()) {
                    const int i = int(cols.indexOf(k));
                    if (i >= 0)
                        t.keys << i;
                }
                if (t.keys.isEmpty() && t.reason.isEmpty())
                    t.reason = QStringLiteral("Tabela bez klucza głównego — nie da się wskazać, który wiersz zmienić");
            }
            m_table->setResult(cols, r.value(QStringLiteral("types")).toStringList(), r.value(QStringLiteral("rows")).toList(), t);
        }
        Q_EMIT tableLoaded();
    } else if (op == QLatin1String("query")) {
        if (id != m_queryJob)
            return;
        m_running = false;
        m_lastRun = r;
        m_lastRun.remove(QStringLiteral("rows"));
        if (ok && r.value(QStringLiteral("select")).toBool())
            m_result->setResult(r.value(QStringLiteral("columns")).toStringList(), r.value(QStringLiteral("types")).toStringList(),
                                r.value(QStringLiteral("rows")).toList());
        else if (ok)
            m_result->clear();
        Store::addHistory({{QStringLiteral("conn"), m_current.value(QStringLiteral("id"))}, {QStringLiteral("sql"), m_lastSql.trimmed()},
                           {QStringLiteral("ok"), ok}, {QStringLiteral("ms"), r.value(QStringLiteral("ms"))},
                           {QStringLiteral("rows"), r.value(QStringLiteral("rows")).toList().size()}, {QStringLiteral("error"), err}});
        Q_EMIT lastRunChanged();
        Q_EMIT historyChanged();
        // Zmiana struktury (CREATE/DROP/ALTER) — odśwież listę tabel
        static const QRegularExpression ddl(QStringLiteral("\\b(CREATE|DROP|ALTER|RENAME)\\b"), QRegularExpression::CaseInsensitiveOption);
        if (ok && ddl.match(m_lastSql).hasMatch())
            refresh();
    } else if (op == QLatin1String("apply")) {
        if (ok) {
            Q_EMIT committed(true, QStringLiteral("Zapisano zmiany"));
            loadPage(false);
        } else {
            Q_EMIT committed(false, err);
        }
    } else if (op == QLatin1String("export")) {
        if (ok)
            Q_EMIT message(QStringLiteral("Zapisano %1 (wierszy: %2)").arg(QFileInfo(r.value(QStringLiteral("path")).toString()).fileName()).arg(r.value(QStringLiteral("rows")).toInt()));
        else
            Q_EMIT message(err);
    }
}

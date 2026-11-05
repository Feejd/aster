#include "dbcore.h"

#include <QDateTime>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QRegularExpression>
#include <QSqlDriver>
#include <QSqlError>
#include <QSqlField>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QTextStream>

namespace Db {

Kind kindOf(const QVariantMap &conn)
{
    const QString k = conn.value(QStringLiteral("kind")).toString();
    if (k == QLatin1String("postgres"))
        return Kind::Postgres;
    if (k == QLatin1String("mysql"))
        return Kind::MySQL;
    return Kind::SQLite;
}

QString kindName(Kind k)
{
    switch (k) {
    case Kind::Postgres: return QStringLiteral("PostgreSQL");
    case Kind::MySQL: return QStringLiteral("MySQL / MariaDB");
    default: return QStringLiteral("SQLite");
    }
}

QString qtDriver(Kind k)
{
    switch (k) {
    case Kind::Postgres: return QStringLiteral("QPSQL");
    case Kind::MySQL: return QStringLiteral("QMYSQL");
    default: return QStringLiteral("QSQLITE");
    }
}

bool driverAvailable(Kind k) { return QSqlDatabase::isDriverAvailable(qtDriver(k)); }

int defaultPort(Kind k) { return k == Kind::Postgres ? 5432 : k == Kind::MySQL ? 3306 : 0; }

// Komunikaty sterowników są po angielsku — najczęstsze przekładamy, resztę zostawiamy (z kodem błędu)
static QString friendly(const QSqlError &e)
{
    QString t = e.databaseText().trimmed();
    if (t.isEmpty())
        t = e.driverText().trimmed();
    const QString low = t.toLower();
    if (low.contains(QLatin1String("password authentication failed")) || low.contains(QLatin1String("access denied")))
        return QStringLiteral("Złe hasło albo użytkownik (%1)").arg(t);
    if (low.contains(QLatin1String("connection refused")) || low.contains(QLatin1String("can't connect")))
        return QStringLiteral("Serwer nie odpowiada pod tym adresem i portem (%1)").arg(t);
    if (low.contains(QLatin1String("could not translate host name")) || low.contains(QLatin1String("unknown mysql server host")))
        return QStringLiteral("Nie znaleziono serwera o tej nazwie (%1)").arg(t);
    if (low.contains(QLatin1String("read-only transaction")) || low.contains(QLatin1String("read only transaction"))
        || low.contains(QLatin1String("attempt to write a readonly database")))
        return QStringLiteral("Połączenie tylko do odczytu — zmiany są zablokowane (%1)").arg(t);
    return t;
}

bool open(const QString &name, const QVariantMap &conn, const QString &password, bool readOnly, QString *error)
{
    const Kind k = kindOf(conn);
    if (!driverAvailable(k)) {
        if (error)
            *error = QStringLiteral("Brak sterownika %1 w systemie (pakiet qt6-qtbase-%2)")
                         .arg(kindName(k), k == Kind::Postgres ? QStringLiteral("postgresql") : QStringLiteral("mysql"));
        return false;
    }
    close(name);
    QSqlDatabase db = QSqlDatabase::addDatabase(qtDriver(k), name);
    QStringList setup;
    if (k == Kind::SQLite) {
        const QString file = conn.value(QStringLiteral("file")).toString();
        if (readOnly && !QFileInfo::exists(file)) {
            if (error)
                *error = QStringLiteral("Nie ma pliku %1").arg(file);
            return false;
        }
        db.setDatabaseName(file);
        db.setConnectOptions(readOnly ? QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=3000") : QStringLiteral("QSQLITE_BUSY_TIMEOUT=3000"));
        setup << QStringLiteral("PRAGMA foreign_keys = ON");
    } else {
        db.setHostName(conn.value(QStringLiteral("host"), QStringLiteral("localhost")).toString());
        const int port = conn.value(QStringLiteral("port")).toInt();
        db.setPort(port > 0 ? port : defaultPort(k));
        QString database = conn.value(QStringLiteral("database")).toString();
        if (database.isEmpty() && k == Kind::Postgres)
            database = QStringLiteral("postgres");
        db.setDatabaseName(database);
        db.setUserName(conn.value(QStringLiteral("user")).toString());
        db.setPassword(password);
        // numeric/decimal jako dokładny tekst (kwoty!), nie zaokrąglony double
        db.setNumericalPrecisionPolicy(QSql::HighPrecision);
        if (k == Kind::Postgres) {
            db.setConnectOptions(QStringLiteral("connect_timeout=8;application_name=aster-vault"));
            if (readOnly)
                setup << QStringLiteral("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY") << QStringLiteral("SET statement_timeout = 30000");
        } else {
            db.setConnectOptions(QStringLiteral("MYSQL_OPT_CONNECT_TIMEOUT=8"));
            setup << QStringLiteral("SET NAMES utf8mb4");
            if (readOnly)
                setup << QStringLiteral("SET SESSION TRANSACTION READ ONLY") << QStringLiteral("SET SESSION max_execution_time = 30000")
                      << QStringLiteral("SET SESSION max_statement_time = 30");
        }
    }
    if (!db.open()) {
        if (error)
            *error = friendly(db.lastError());
        return false;
    }
    for (const QString &s : std::as_const(setup)) {
        QSqlQuery q(db);
        // Zabezpieczenie tylko do odczytu musi się udać; limity czasu różnią się między MySQL a MariaDB
        if (!q.exec(s) && s.contains(QLatin1String("READ ONLY"))) {
            if (error)
                *error = friendly(q.lastError());
            return false;
        }
    }
    return true;
}

void close(const QString &name)
{
    if (!QSqlDatabase::contains(name))
        return;
    {
        QSqlDatabase db = QSqlDatabase::database(name, false);
        db.close();
    }
    QSqlDatabase::removeDatabase(name);
}

// ——— Pomocnicze ———

static QList<QVariantList> select(QSqlDatabase &db, const QString &sql, const QVariantList &binds = {}, QString *error = nullptr)
{
    QList<QVariantList> out;
    QSqlQuery q(db);
    q.setForwardOnly(true);
    bool ok;
    if (binds.isEmpty()) {
        ok = q.exec(sql);
    } else {
        ok = q.prepare(sql);
        for (const QVariant &b : binds)
            q.addBindValue(b);
        ok = ok && q.exec();
    }
    if (!ok) {
        if (error)
            *error = friendly(q.lastError());
        return out;
    }
    const int n = q.record().count();
    while (q.next()) {
        QVariantList row;
        row.reserve(n);
        for (int i = 0; i < n; ++i)
            row << q.value(i);
        out << row;
    }
    return out;
}

QString quoteIdent(Kind k, const QString &name)
{
    if (k == Kind::MySQL)
        return QLatin1Char('`') + QString(name).replace(QLatin1Char('`'), QLatin1String("``")) + QLatin1Char('`');
    return QLatin1Char('"') + QString(name).replace(QLatin1Char('"'), QLatin1String("\"\"")) + QLatin1Char('"');
}

QString qualified(Kind k, const QString &schemaName, const QString &table)
{
    if (schemaName.isEmpty() || k == Kind::SQLite || (k == Kind::Postgres && schemaName == QLatin1String("public")))
        return quoteIdent(k, table);
    return quoteIdent(k, schemaName) + QLatin1Char('.') + quoteIdent(k, table);
}

QString literal(const QVariant &v)
{
    if (v.isNull() || !v.isValid())
        return QStringLiteral("NULL");
    switch (v.metaType().id()) {
    case QMetaType::Int: case QMetaType::UInt: case QMetaType::LongLong: case QMetaType::ULongLong:
    case QMetaType::Double: case QMetaType::Float:
        return cellText(v);
    case QMetaType::Bool:
        return v.toBool() ? QStringLiteral("TRUE") : QStringLiteral("FALSE");
    default:
        return QLatin1Char('\'') + cellText(v).replace(QLatin1Char('\''), QLatin1String("''")) + QLatin1Char('\'');
    }
}

QString cellText(const QVariant &v, int maxLen)
{
    if (v.isNull() || !v.isValid())
        return {};
    QString t;
    switch (v.metaType().id()) {
    case QMetaType::QByteArray: {
        const QByteArray b = v.toByteArray();
        const QString s = QString::fromUtf8(b);
        if (!s.contains(QChar::ReplacementCharacter) && !b.contains('\0'))
            t = s;
        else
            return QStringLiteral("‹dane binarne, %1 B›").arg(b.size());
        break;
    }
    case QMetaType::Double:
    case QMetaType::Float:
        t = QString::number(v.toDouble(), 'g', 15);
        break;
    case QMetaType::QDateTime:
    {
        // Tak, jak zapisano w bazie (bez przeliczania stref i bez „.000Z”)
        const QDateTime dt = v.toDateTime();
        t = dt.toString(dt.time().msec() ? QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz") : QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        break;
    }
    case QMetaType::QDate:
        t = v.toDate().toString(Qt::ISODate);
        break;
    case QMetaType::QTime:
        t = v.toTime().toString(Qt::ISODate);
        break;
    case QMetaType::Bool:
        t = v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
        break;
    default:
        t = v.toString();
    }
    if (maxLen > 0) {
        if (t.size() > maxLen)
            t = t.left(maxLen) + QStringLiteral("…");
        t.replace(QLatin1Char('\n'), QStringLiteral("↵ ")).replace(QLatin1Char('\r'), QString()).replace(QLatin1Char('\t'), QLatin1Char(' '));
    }
    return t;
}

QVariant jsonValue(const QVariant &v)
{
    if (v.isNull() || !v.isValid())
        return QVariant::fromValue(nullptr);
    switch (v.metaType().id()) {
    case QMetaType::Int: case QMetaType::UInt: case QMetaType::LongLong: case QMetaType::ULongLong:
    case QMetaType::Double: case QMetaType::Float: case QMetaType::Bool:
        return v;
    case QMetaType::QByteArray: {
        const QByteArray b = v.toByteArray();
        const QString s = QString::fromUtf8(b);
        if (!s.contains(QChar::ReplacementCharacter) && !b.contains('\0'))
            return s;
        return QStringLiteral("base64:") + QString::fromLatin1(b.toBase64());
    }
    default:
        return cellText(v);
    }
}

// ——— Struktura ———

QStringList databases(QSqlDatabase &db, Kind k)
{
    QStringList out;
    QString sql;
    if (k == Kind::Postgres)
        sql = QStringLiteral("SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1");
    else if (k == Kind::MySQL)
        sql = QStringLiteral("SHOW DATABASES");
    else
        return out;
    for (const QVariantList &r : select(db, sql))
        out << r.value(0).toString();
    return out;
}

QVariantList objects(QSqlDatabase &db, Kind k)
{
    QVariantList out;
    QString sql;
    if (k == Kind::SQLite)
        sql = QStringLiteral("SELECT '', name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name");
    else if (k == Kind::Postgres)
        sql = QStringLiteral("SELECT table_schema, table_name, CASE table_type WHEN 'VIEW' THEN 'view' ELSE 'table' END "
                             "FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') "
                             "AND table_schema NOT LIKE 'pg_toast%' AND table_schema NOT LIKE 'pg_temp%' "
                             "ORDER BY table_schema <> 'public', table_schema, 3, 2");
    else
        sql = QStringLiteral("SELECT table_schema, table_name, CASE table_type WHEN 'VIEW' THEN 'view' ELSE 'table' END "
                             "FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY 3, 2");
    for (const QVariantList &r : select(db, sql))
        out << QVariantMap{{QStringLiteral("schema"), r.value(0).toString()}, {QStringLiteral("name"), r.value(1).toString()},
                           {QStringLiteral("type"), r.value(2).toString()}};
    return out;
}

static QVariantMap column(const QString &name, const QString &type, bool nullable, const QVariant &def, bool pk)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("type"), type}, {QStringLiteral("nullable"), nullable},
            {QStringLiteral("default"), def.isNull() ? QString() : def.toString()}, {QStringLiteral("pk"), pk}};
}

QVariantMap schema(QSqlDatabase &db, Kind k, const QString &schemaName, const QString &table)
{
    QVariantList columns, indexes, fks;
    QStringList pk;
    QString ddl, type = QStringLiteral("table"), error;

    if (k == Kind::SQLite) {
        const QString q = quoteIdent(k, table);
        const auto info = select(db, QStringLiteral("SELECT type, sql FROM sqlite_master WHERE name = ?"), {table});
        if (!info.isEmpty()) {
            type = info.first().value(0).toString();
            ddl = info.first().value(1).toString();
        }
        QList<QPair<int, QString>> pkCols;
        for (const QVariantList &r : select(db, QStringLiteral("PRAGMA table_info(%1)").arg(q), {}, &error)) {
            const int pkPos = r.value(5).toInt();
            columns << column(r.value(1).toString(), r.value(2).toString(), r.value(3).toInt() == 0 && pkPos == 0, r.value(4), pkPos > 0);
            if (pkPos > 0)
                pkCols << qMakePair(pkPos, r.value(1).toString());
        }
        std::sort(pkCols.begin(), pkCols.end());
        for (const auto &p : pkCols)
            pk << p.second;
        for (const QVariantList &r : select(db, QStringLiteral("PRAGMA index_list(%1)").arg(q))) {
            QStringList cols;
            for (const QVariantList &c : select(db, QStringLiteral("PRAGMA index_info(%1)").arg(quoteIdent(k, r.value(1).toString()))))
                cols << c.value(2).toString();
            indexes << QVariantMap{{QStringLiteral("name"), r.value(1).toString()}, {QStringLiteral("columns"), cols.join(QStringLiteral(", "))},
                                   {QStringLiteral("unique"), r.value(2).toInt() == 1}, {QStringLiteral("primary"), r.value(3).toString() == QLatin1String("pk")}};
        }
        QMap<int, QVariantMap> byId;
        for (const QVariantList &r : select(db, QStringLiteral("PRAGMA foreign_key_list(%1)").arg(q))) {
            QVariantMap &f = byId[r.value(0).toInt()];
            f[QStringLiteral("name")] = QStringLiteral("fk_%1").arg(r.value(0).toInt());
            f[QStringLiteral("refTable")] = r.value(2).toString();
            f[QStringLiteral("columns")] = (f.value(QStringLiteral("columns")).toString().isEmpty() ? QString() : f.value(QStringLiteral("columns")).toString() + QStringLiteral(", ")) + r.value(3).toString();
            f[QStringLiteral("refColumns")] = (f.value(QStringLiteral("refColumns")).toString().isEmpty() ? QString() : f.value(QStringLiteral("refColumns")).toString() + QStringLiteral(", ")) + r.value(4).toString();
        }
        for (const QVariantMap &f : std::as_const(byId))
            fks << f;
    } else if (k == Kind::Postgres) {
        const QVariantList b{schemaName, table};
        const auto rel = select(db, QStringLiteral("SELECT c.relkind, CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid, true) END "
                                                   "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ? AND c.relname = ?"), b, &error);
        if (!rel.isEmpty() && (rel.first().value(0).toString() == QLatin1String("v") || rel.first().value(0).toString() == QLatin1String("m"))) {
            type = QStringLiteral("view");
            ddl = QStringLiteral("CREATE VIEW %1 AS\n%2").arg(qualified(k, schemaName, table), rel.first().value(1).toString().trimmed());
        }
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT i.relname, ix.indisunique, ix.indisprimary, pg_get_indexdef(ix.indexrelid), "
                 "array_to_string(ARRAY(SELECT a.attname FROM unnest(ix.indkey) WITH ORDINALITY k(n, o) "
                 "JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = k.n ORDER BY k.o), ', ') "
                 "FROM pg_index ix JOIN pg_class t ON t.oid = ix.indrelid JOIN pg_class i ON i.oid = ix.indexrelid "
                 "JOIN pg_namespace n ON n.oid = t.relnamespace WHERE n.nspname = ? AND t.relname = ? ORDER BY NOT ix.indisprimary, i.relname"), b)) {
            indexes << QVariantMap{{QStringLiteral("name"), r.value(0).toString()}, {QStringLiteral("columns"), r.value(4).toString()},
                                   {QStringLiteral("unique"), r.value(1).toBool()}, {QStringLiteral("primary"), r.value(2).toBool()},
                                   {QStringLiteral("definition"), r.value(3).toString()}};
            if (r.value(2).toBool())
                pk = r.value(4).toString().split(QStringLiteral(", "), Qt::SkipEmptyParts);
        }
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT a.attname, format_type(a.atttypid, a.atttypmod), NOT a.attnotnull, pg_get_expr(d.adbin, d.adrelid) "
                 "FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace "
                 "LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum "
                 "WHERE n.nspname = ? AND c.relname = ? AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum"), b, &error))
            columns << column(r.value(0).toString(), r.value(1).toString(), r.value(2).toBool(), r.value(3), pk.contains(r.value(0).toString()));
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT con.conname, "
                 "(SELECT string_agg(a.attname, ', ' ORDER BY k.o) FROM unnest(con.conkey) WITH ORDINALITY k(n, o) "
                 " JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.n), "
                 "CASE WHEN nf.nspname = 'public' THEN cf.relname ELSE nf.nspname || '.' || cf.relname END, "
                 "(SELECT string_agg(a.attname, ', ' ORDER BY k.o) FROM unnest(con.confkey) WITH ORDINALITY k(n, o) "
                 " JOIN pg_attribute a ON a.attrelid = con.confrelid AND a.attnum = k.n) "
                 "FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace "
                 "JOIN pg_class cf ON cf.oid = con.confrelid JOIN pg_namespace nf ON nf.oid = cf.relnamespace "
                 "WHERE con.contype = 'f' AND n.nspname = ? AND c.relname = ? ORDER BY 1"), b))
            fks << QVariantMap{{QStringLiteral("name"), r.value(0).toString()}, {QStringLiteral("columns"), r.value(1).toString()},
                               {QStringLiteral("refTable"), r.value(2).toString()}, {QStringLiteral("refColumns"), r.value(3).toString()}};
        if (type == QLatin1String("table")) {
            // Przybliżony CREATE TABLE z katalogu (PostgreSQL nie ma SHOW CREATE TABLE)
            QStringList lines;
            for (const QVariant &c : std::as_const(columns)) {
                const QVariantMap m = c.toMap();
                QString l = QStringLiteral("  %1 %2").arg(quoteIdent(k, m.value(QStringLiteral("name")).toString()), m.value(QStringLiteral("type")).toString());
                if (!m.value(QStringLiteral("default")).toString().isEmpty())
                    l += QStringLiteral(" DEFAULT ") + m.value(QStringLiteral("default")).toString();
                if (!m.value(QStringLiteral("nullable")).toBool())
                    l += QStringLiteral(" NOT NULL");
                lines << l;
            }
            for (const QVariantList &r : select(db, QStringLiteral(
                     "SELECT con.conname, pg_get_constraintdef(con.oid) FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid "
                     "JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ? AND c.relname = ? AND con.contype <> 'n' ORDER BY con.contype <> 'p', 1"), b))
                lines << QStringLiteral("  CONSTRAINT %1 %2").arg(quoteIdent(k, r.value(0).toString()), r.value(1).toString());
            ddl = QStringLiteral("CREATE TABLE %1 (\n%2\n);").arg(qualified(k, schemaName, table), lines.join(QStringLiteral(",\n")));
            for (const QVariant &i : std::as_const(indexes))
                if (!i.toMap().value(QStringLiteral("primary")).toBool())
                    ddl += QLatin1Char('\n') + i.toMap().value(QStringLiteral("definition")).toString() + QLatin1Char(';');
        }
    } else {
        const QVariantList b{table};
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT column_name, column_type, is_nullable = 'YES', column_default, column_key = 'PRI' "
                 "FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? ORDER BY ordinal_position"), b, &error)) {
            columns << column(r.value(0).toString(), r.value(1).toString(), r.value(2).toBool(), r.value(3), r.value(4).toBool());
        }
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT index_name, MIN(non_unique) = 0, GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ', ') "
                 "FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? "
                 "GROUP BY index_name ORDER BY index_name <> 'PRIMARY', index_name"), b)) {
            const bool primary = r.value(0).toString() == QLatin1String("PRIMARY");
            indexes << QVariantMap{{QStringLiteral("name"), r.value(0).toString()}, {QStringLiteral("columns"), r.value(2).toString()},
                                   {QStringLiteral("unique"), r.value(1).toBool()}, {QStringLiteral("primary"), primary}};
            if (primary)
                pk = r.value(2).toString().split(QStringLiteral(", "), Qt::SkipEmptyParts);
        }
        for (const QVariantList &r : select(db, QStringLiteral(
                 "SELECT constraint_name, GROUP_CONCAT(column_name ORDER BY ordinal_position SEPARATOR ', '), referenced_table_name, "
                 "GROUP_CONCAT(referenced_column_name ORDER BY ordinal_position SEPARATOR ', ') FROM information_schema.key_column_usage "
                 "WHERE table_schema = DATABASE() AND table_name = ? AND referenced_table_name IS NOT NULL "
                 "GROUP BY constraint_name, referenced_table_name ORDER BY 1"), b))
            fks << QVariantMap{{QStringLiteral("name"), r.value(0).toString()}, {QStringLiteral("columns"), r.value(1).toString()},
                               {QStringLiteral("refTable"), r.value(2).toString()}, {QStringLiteral("refColumns"), r.value(3).toString()}};
        const auto t = select(db, QStringLiteral("SELECT table_type FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?"), b);
        if (!t.isEmpty() && t.first().value(0).toString() == QLatin1String("VIEW"))
            type = QStringLiteral("view");
        const auto c = select(db, QStringLiteral("SHOW CREATE %1 %2").arg(type == QLatin1String("view") ? QStringLiteral("VIEW") : QStringLiteral("TABLE"), quoteIdent(k, table)));
        if (!c.isEmpty())
            ddl = c.first().value(1).toString();
    }
    QVariantMap out{{QStringLiteral("schema"), schemaName}, {QStringLiteral("table"), table}, {QStringLiteral("type"), type},
                    {QStringLiteral("columns"), columns}, {QStringLiteral("indexes"), indexes}, {QStringLiteral("foreignKeys"), fks},
                    {QStringLiteral("primaryKey"), pk}, {QStringLiteral("ddl"), ddl}};
    if (columns.isEmpty() && !error.isEmpty())
        out.insert(QStringLiteral("error"), error);
    return out;
}

QVariantMap allColumns(QSqlDatabase &db, Kind k)
{
    QVariantMap out;
    QList<QVariantList> rows;
    if (k == Kind::SQLite) {
        // pragma_table_info jako funkcja tabelaryczna (SQLite ≥ 3.16) — jedno zapytanie dla wszystkich tabel
        rows = select(db, QStringLiteral("SELECT m.name, p.name FROM sqlite_master m, pragma_table_info(m.name) p "
                                         "WHERE m.type IN ('table','view') AND m.name NOT LIKE 'sqlite_%' ORDER BY m.name, p.cid"));
    } else if (k == Kind::Postgres) {
        rows = select(db, QStringLiteral("SELECT CASE WHEN table_schema = 'public' THEN table_name ELSE table_schema || '.' || table_name END, column_name "
                                         "FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema') "
                                         "ORDER BY 1, ordinal_position LIMIT 20000"));
    } else {
        rows = select(db, QStringLiteral("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = DATABASE() "
                                         "ORDER BY table_name, ordinal_position LIMIT 20000"));
    }
    QString current;
    QStringList cols;
    for (const QVariantList &r : std::as_const(rows)) {
        const QString t = r.value(0).toString();
        if (t != current) {
            if (!current.isEmpty())
                out.insert(current, cols);
            current = t;
            cols.clear();
        }
        cols << r.value(1).toString();
    }
    if (!current.isEmpty())
        out.insert(current, cols);
    return out;
}

// ——— Zapytania ———

QStringList splitStatements(const QString &sql)
{
    QStringList out;
    QString cur;
    const int n = int(sql.size());
    for (int i = 0; i < n; ++i) {
        const QChar c = sql.at(i);
        const QChar next = i + 1 < n ? sql.at(i + 1) : QChar();
        if (c == QLatin1Char('-') && next == QLatin1Char('-')) {
            const int end = int(sql.indexOf(QLatin1Char('\n'), i));
            const int stop = end < 0 ? n : end;
            cur += sql.mid(i, stop - i);
            i = stop - 1;
        } else if (c == QLatin1Char('/') && next == QLatin1Char('*')) {
            const int end = int(sql.indexOf(QLatin1String("*/"), i + 2));
            const int stop = end < 0 ? n : end + 2;
            cur += sql.mid(i, stop - i);
            i = stop - 1;
        } else if (c == QLatin1Char('\'') || c == QLatin1Char('"') || c == QLatin1Char('`')) {
            int j = i + 1;
            while (j < n) {
                if (sql.at(j) == c) {
                    if (j + 1 < n && sql.at(j + 1) == c) { j += 2; continue; }
                    break;
                }
                if (sql.at(j) == QLatin1Char('\\') && c == QLatin1Char('\'')) { j += 2; continue; }
                ++j;
            }
            cur += sql.mid(i, j - i + 1);
            i = j;
        } else if (c == QLatin1Char('$')) {
            // Dolarowe cudzysłowy PostgreSQL: $$ … $$ albo $znacznik$ … $znacznik$
            static const QRegularExpression tag(QStringLiteral("^\\$([A-Za-z_][A-Za-z0-9_]*)?\\$"));
            const auto m = tag.matchView(QStringView(sql).mid(i));
            if (m.hasMatch()) {
                const QString t = m.captured(0);
                const int end = int(sql.indexOf(t, i + t.size()));
                const int stop = end < 0 ? n : end + int(t.size());
                cur += sql.mid(i, stop - i);
                i = stop - 1;
            } else {
                cur += c;
            }
        } else if (c == QLatin1Char(';')) {
            if (!cur.trimmed().isEmpty())
                out << cur.trimmed();
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.trimmed().isEmpty())
        out << cur.trimmed();
    // Same komentarze nie są poleceniem
    QStringList real;
    for (const QString &s : std::as_const(out)) {
        QString t = s;
        static const QRegularExpression comments(QStringLiteral("--[^\\n]*|/\\*.*?\\*/"), QRegularExpression::DotMatchesEverythingOption);
        if (!t.remove(comments).trimmed().isEmpty())
            real << s;
    }
    return real;
}

// Słowa polecenia poza napisami, cudzysłowami i komentarzami — wielkimi literami
static QStringList words(const QString &statement)
{
    QStringList out;
    const int n = int(statement.size());
    QString w;
    auto flush = [&] { if (!w.isEmpty()) { out << w.toUpper(); w.clear(); } };
    for (int i = 0; i < n; ++i) {
        const QChar c = statement.at(i);
        const QChar next = i + 1 < n ? statement.at(i + 1) : QChar();
        if (c == QLatin1Char('-') && next == QLatin1Char('-')) {
            flush();
            const int e = int(statement.indexOf(QLatin1Char('\n'), i));
            i = e < 0 ? n : e;
        } else if (c == QLatin1Char('/') && next == QLatin1Char('*')) {
            flush();
            const int e = int(statement.indexOf(QLatin1String("*/"), i + 2));
            i = e < 0 ? n : e + 1;
        } else if (c == QLatin1Char('\'') || c == QLatin1Char('"') || c == QLatin1Char('`')) {
            flush();
            int j = i + 1;
            while (j < n && statement.at(j) != c)
                ++j;
            i = j;
            out << QStringLiteral("·");   // znacznik wartości/nazwy
        } else if (c.isLetterOrNumber() || c == QLatin1Char('_')) {
            w += c;
        } else {
            flush();
            if (c == QLatin1Char('='))
                out << QStringLiteral("=");
        }
    }
    flush();
    return out;
}

bool isReadOnlyStatement(const QString &statement)
{
    const QStringList w = words(statement);
    if (w.isEmpty())
        return false;
    static const QStringList first{QStringLiteral("SELECT"), QStringLiteral("WITH"), QStringLiteral("SHOW"), QStringLiteral("EXPLAIN"),
                                   QStringLiteral("DESCRIBE"), QStringLiteral("DESC"), QStringLiteral("VALUES"), QStringLiteral("TABLE"),
                                   QStringLiteral("PRAGMA")};
    if (!first.contains(w.first()))
        return false;
    static const QStringList banned{QStringLiteral("INSERT"), QStringLiteral("UPDATE"), QStringLiteral("DELETE"), QStringLiteral("MERGE"),
                                    QStringLiteral("DROP"), QStringLiteral("CREATE"), QStringLiteral("ALTER"), QStringLiteral("TRUNCATE"),
                                    QStringLiteral("GRANT"), QStringLiteral("REVOKE"), QStringLiteral("COPY"), QStringLiteral("CALL"),
                                    QStringLiteral("LOCK"), QStringLiteral("VACUUM"), QStringLiteral("REINDEX"), QStringLiteral("ATTACH"),
                                    QStringLiteral("DETACH"), QStringLiteral("INTO"), QStringLiteral("OUTFILE"), QStringLiteral("DUMPFILE"),
                                    QStringLiteral("ANALYZE"), QStringLiteral("COMMIT"), QStringLiteral("ROLLBACK"), QStringLiteral("BEGIN")};
    for (const QString &x : w)
        if (banned.contains(x))
            return false;
    if (w.first() == QLatin1String("PRAGMA") && w.contains(QStringLiteral("=")))
        return false;
    return true;
}

bool isRisky(const QString &statement)
{
    const QStringList w = words(statement);
    if (w.isEmpty())
        return false;
    if (w.first() == QLatin1String("DROP") || w.first() == QLatin1String("TRUNCATE"))
        return true;
    if ((w.first() == QLatin1String("DELETE") || w.first() == QLatin1String("UPDATE")) && !w.contains(QStringLiteral("WHERE")))
        return true;
    if (w.first() == QLatin1String("ALTER") && w.contains(QStringLiteral("DROP")))
        return true;
    return false;
}

QVariantMap run(QSqlDatabase &db, const QString &statement, int maxRows, const QVariantList &binds)
{
    QElapsedTimer t;
    t.start();
    QSqlQuery q(db);
    q.setForwardOnly(true);
    bool ok;
    if (binds.isEmpty()) {
        ok = q.exec(statement);
    } else {
        ok = q.prepare(statement);
        for (const QVariant &b : binds)
            q.addBindValue(b);
        ok = ok && q.exec();
    }
    QVariantMap out{{QStringLiteral("ok"), ok}, {QStringLiteral("sql"), statement}};
    if (!ok) {
        out.insert(QStringLiteral("error"), friendly(q.lastError()));
        out.insert(QStringLiteral("ms"), t.elapsed());
        return out;
    }
    if (q.isSelect()) {
        const QSqlRecord rec = q.record();
        QStringList columns, types;
        for (int i = 0; i < rec.count(); ++i) {
            columns << rec.fieldName(i);
            types << QString::fromLatin1(rec.field(i).metaType().name());
        }
        QVariantList rows;
        bool truncated = false;
        while (q.next()) {
            if (maxRows > 0 && rows.size() >= maxRows) {
                truncated = true;
                break;
            }
            QVariantList row;
            row.reserve(rec.count());
            for (int i = 0; i < rec.count(); ++i)
                row << q.value(i);
            rows << QVariant(row);
        }
        out.insert(QStringLiteral("select"), true);
        out.insert(QStringLiteral("columns"), columns);
        out.insert(QStringLiteral("types"), types);
        out.insert(QStringLiteral("rows"), rows);
        out.insert(QStringLiteral("truncated"), truncated);
    } else {
        out.insert(QStringLiteral("select"), false);
        out.insert(QStringLiteral("affected"), q.numRowsAffected());
    }
    out.insert(QStringLiteral("ms"), t.elapsed());
    return out;
}

static QString plural(int n, const char *one, const char *few, const char *many)
{
    const int t = n % 100, u = n % 10;
    return QString::number(n) + QLatin1Char(' ')
        + QString::fromUtf8(n == 1 ? one : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? few : many);
}

QVariantMap runScript(QSqlDatabase &db, const QString &sql, int maxRows, bool readOnly)
{
    const QStringList statements = splitStatements(sql);
    if (statements.isEmpty())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Brak polecenia do wykonania")}};
    QVariantMap last, lastSelect;
    QStringList messages;
    qint64 ms = 0;
    for (int i = 0; i < statements.size(); ++i) {
        const QString &s = statements.at(i);
        if (readOnly && !isReadOnlyStatement(s)) {
            QVariantMap e{{QStringLiteral("ok"), false}, {QStringLiteral("index"), i}, {QStringLiteral("sql"), s},
                          {QStringLiteral("error"), QStringLiteral("Tylko do odczytu: dozwolone są SELECT, WITH, SHOW, EXPLAIN, DESCRIBE i PRAGMA bez zmian")}};
            e.insert(QStringLiteral("messages"), messages);
            return e;
        }
        QVariantMap r = run(db, s, maxRows);
        ms += r.value(QStringLiteral("ms")).toLongLong();
        if (!r.value(QStringLiteral("ok")).toBool()) {
            r.insert(QStringLiteral("index"), i);
            r.insert(QStringLiteral("messages"), messages);
            if (statements.size() > 1)
                r[QStringLiteral("error")] = QStringLiteral("Polecenie %1 z %2: %3").arg(i + 1).arg(statements.size()).arg(r.value(QStringLiteral("error")).toString());
            return r;
        }
        if (r.value(QStringLiteral("select")).toBool()) {
            lastSelect = r;
            messages << plural(int(r.value(QStringLiteral("rows")).toList().size()), "wiersz", "wiersze", "wierszy")
                    + (r.value(QStringLiteral("truncated")).toBool() ? QStringLiteral(" (pierwsze)") : QString());
        } else {
            const int a = r.value(QStringLiteral("affected")).toInt();
            messages << (a >= 0 ? QStringLiteral("Zmieniono: ") + plural(a, "wiersz", "wiersze", "wierszy") : QStringLiteral("Wykonano"));
        }
        last = r;
    }
    QVariantMap out = lastSelect.isEmpty() ? last : lastSelect;
    out.insert(QStringLiteral("statements"), int(statements.size()));
    out.insert(QStringLiteral("messages"), messages);
    out.insert(QStringLiteral("ms"), ms);
    return out;
}

QVariantMap applyChanges(QSqlDatabase &db, const QVariantList &changes)
{
    if (!db.transaction())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), friendly(db.lastError())}};
    int affected = 0;
    for (int i = 0; i < changes.size(); ++i) {
        const QVariantMap c = changes.at(i).toMap();
        QSqlQuery q(db);
        bool ok = q.prepare(c.value(QStringLiteral("sql")).toString());
        for (const QVariant &b : c.value(QStringLiteral("binds")).toList())
            q.addBindValue(b);
        ok = ok && q.exec();
        if (!ok) {
            const QString e = friendly(q.lastError());
            db.rollback();
            return {{QStringLiteral("ok"), false}, {QStringLiteral("index"), i},
                    {QStringLiteral("error"), QStringLiteral("Zmiana %1: %2 — nic nie zapisano").arg(i + 1).arg(e)}};
        }
        affected += std::max(0, q.numRowsAffected());
    }
    if (!db.commit()) {
        const QString e = friendly(db.lastError());
        db.rollback();
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), e}};
    }
    return {{QStringLiteral("ok"), true}, {QStringLiteral("affected"), affected}};
}

static QString csvField(const QString &s)
{
    if (s.contains(QLatin1Char(',')) || s.contains(QLatin1Char('"')) || s.contains(QLatin1Char('\n')) || s.contains(QLatin1Char('\r')))
        return QLatin1Char('"') + QString(s).replace(QLatin1Char('"'), QLatin1String("\"\"")) + QLatin1Char('"');
    return s;
}

QVariantMap exportQuery(QSqlDatabase &db, const QString &statement, const QString &path, const QString &format)
{
    QSqlQuery q(db);
    q.setForwardOnly(true);
    if (!q.exec(statement))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), friendly(q.lastError())}};
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Nie można zapisać pliku: %1").arg(f.errorString())}};
    QTextStream out(&f);
    out.setEncoding(QStringConverter::Utf8);
    const QSqlRecord rec = q.record();
    QStringList names;
    for (int i = 0; i < rec.count(); ++i)
        names << rec.fieldName(i);
    int rows = 0;
    const bool json = format == QLatin1String("json");
    if (json) {
        out << "[";
    } else {
        QStringList h;
        for (const QString &n : std::as_const(names))
            h << csvField(n);
        out << h.join(QLatin1Char(',')) << "\r\n";
    }
    while (q.next()) {
        if (json) {
            QJsonObject o;
            for (int i = 0; i < rec.count(); ++i)
                o.insert(names.at(i), QJsonValue::fromVariant(jsonValue(q.value(i))));
            out << (rows ? ",\n  " : "\n  ") << QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
        } else {
            QStringList l;
            for (int i = 0; i < rec.count(); ++i)
                l << csvField(cellText(q.value(i)));
            out << l.join(QLatin1Char(',')) << "\r\n";
        }
        ++rows;
    }
    if (json)
        out << (rows ? "\n]\n" : "]\n");
    out.flush();
    return {{QStringLiteral("ok"), true}, {QStringLiteral("rows"), rows}, {QStringLiteral("path"), path}};
}

} // namespace Db

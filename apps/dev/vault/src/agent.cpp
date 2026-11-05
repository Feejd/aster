#include "agent.h"

#include "dbcore.h"
#include "secrets.h"
#include "store.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSqlDatabase>
#include <QTextStream>
#include <cstdio>
#include <unistd.h>

namespace {

constexpr int kCellMax = 500;     // dłuższe wartości skracane — odpowiedź ma być mała dla modelu

QJsonObject fail(const QString &e) { return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), e}}; }

QJsonObject describe(const QVariantMap &c)
{
    const Db::Kind k = Db::kindOf(c);
    QJsonObject o{{QStringLiteral("id"), c.value(QStringLiteral("id")).toString()}, {QStringLiteral("name"), c.value(QStringLiteral("name")).toString()},
                  {QStringLiteral("kind"), c.value(QStringLiteral("kind"), QStringLiteral("sqlite")).toString()},
                  {QStringLiteral("engine"), Db::kindName(k)}, {QStringLiteral("agentAccess"), c.value(QStringLiteral("agent"), true).toBool()}};
    if (k == Db::Kind::SQLite) {
        o.insert(QStringLiteral("file"), c.value(QStringLiteral("file")).toString());
    } else {
        o.insert(QStringLiteral("host"), c.value(QStringLiteral("host")).toString());
        o.insert(QStringLiteral("port"), c.value(QStringLiteral("port")).toInt() > 0 ? c.value(QStringLiteral("port")).toInt() : Db::defaultPort(k));
        o.insert(QStringLiteral("database"), c.value(QStringLiteral("database")).toString());
    }
    return o;
}

// Otwiera połączenie tylko do odczytu; nazwa połączenia Qt w *name
bool openReadOnly(const QString &key, QString *name, QVariantMap *conn, QString *error)
{
    *conn = Store::find(key);
    if (conn->isEmpty()) {
        *error = QStringLiteral("Nie ma połączenia „%1” (aster-vault --list pokazuje zapisane)").arg(key);
        return false;
    }
    if (!conn->value(QStringLiteral("agent"), true).toBool()) {
        *error = QStringLiteral("Połączenie „%1” nie pozwala na dostęp spoza okna Aster Vault (ustawienie w oknie połączenia)").arg(conn->value(QStringLiteral("name")).toString());
        return false;
    }
    QString password;
    if (Db::kindOf(*conn) != Db::Kind::SQLite && conn->value(QStringLiteral("savePassword")).toBool()) {
        QString err;
        password = Secrets::get(conn->value(QStringLiteral("id")).toString(), &err);
    }
    static int seq = 0;
    *name = QStringLiteral("vault-agent-%1").arg(++seq);
    return Db::open(*name, *conn, password, true, error);
}

QJsonValue shortValue(const QVariant &v)
{
    const QVariant j = Db::jsonValue(v);
    if (j.metaType().id() == QMetaType::QString) {
        const QString s = j.toString();
        if (s.size() > kCellMax)
            return s.left(kCellMax) + QStringLiteral("…");
    }
    return QJsonValue::fromVariant(j);
}

} // namespace

QJsonObject Agent::list()
{
    QJsonArray out;
    for (const QVariant &c : Store::connections())
        out << describe(c.toMap());
    return {{QStringLiteral("ok"), true}, {QStringLiteral("connections"), out}};
}

QJsonObject Agent::schema(const QString &key, const QString &table)
{
    QString name, error;
    QVariantMap conn;
    if (!openReadOnly(key, &name, &conn, &error))
        return fail(error);
    QJsonObject out{{QStringLiteral("ok"), true}, {QStringLiteral("connection"), describe(conn)}};
    {
        QSqlDatabase db = QSqlDatabase::database(name, false);
        const Db::Kind k = Db::kindOf(conn);
        if (table.isEmpty()) {
            // Wszystkie tabele z kolumnami — tyle zwykle wystarcza modelowi do napisania zapytania
            const QVariantMap cols = Db::allColumns(db, k);
            QJsonArray objs;
            for (const QVariant &o : Db::objects(db, k)) {
                const QVariantMap m = o.toMap();
                const QString s = m.value(QStringLiteral("schema")).toString(), t = m.value(QStringLiteral("name")).toString();
                const QString full = k == Db::Kind::Postgres && s != QLatin1String("public") ? s + QLatin1Char('.') + t : t;
                QJsonObject j{{QStringLiteral("name"), full}, {QStringLiteral("type"), m.value(QStringLiteral("type")).toString()},
                              {QStringLiteral("columns"), QJsonArray::fromStringList(cols.value(full).toStringList())}};
                objs << j;
            }
            out.insert(QStringLiteral("objects"), objs);
            if (k != Db::Kind::SQLite)
                out.insert(QStringLiteral("databases"), QJsonArray::fromStringList(Db::databases(db, k)));
        } else {
            QString s, t = table;
            const int dot = int(table.indexOf(QLatin1Char('.')));
            if (dot > 0 && k == Db::Kind::Postgres) {
                s = table.left(dot);
                t = table.mid(dot + 1);
            } else if (k == Db::Kind::Postgres) {
                s = QStringLiteral("public");
            }
            const QVariantMap sc = Db::schema(db, k, s, t);
            if (sc.value(QStringLiteral("columns")).toList().isEmpty()) {
                out = fail(sc.contains(QStringLiteral("error")) ? sc.value(QStringLiteral("error")).toString()
                                                                 : QStringLiteral("Nie ma tabeli ani widoku „%1”").arg(table));
            } else {
                out.insert(QStringLiteral("table"), QJsonObject::fromVariantMap(sc));
            }
        }
    }
    Db::close(name);
    return out;
}

QJsonObject Agent::query(const QString &key, const QString &sql, int limit)
{
    const QStringList statements = Db::splitStatements(sql);
    if (statements.size() != 1)
        return fail(statements.isEmpty() ? QStringLiteral("Brak zapytania") : QStringLiteral("Jedno zapytanie naraz"));
    if (!Db::isReadOnlyStatement(statements.first()))
        return fail(QStringLiteral("Tylko do odczytu: dozwolone są SELECT, WITH, SHOW, EXPLAIN, DESCRIBE i PRAGMA bez zmian"));
    QString name, error;
    QVariantMap conn;
    if (!openReadOnly(key, &name, &conn, &error))
        return fail(error);
    QJsonObject out;
    {
        QSqlDatabase db = QSqlDatabase::database(name, false);
        const int lim = std::clamp(limit > 0 ? limit : 100, 1, 1000);
        const QVariantMap r = Db::run(db, statements.first(), lim);
        if (!r.value(QStringLiteral("ok")).toBool()) {
            out = fail(r.value(QStringLiteral("error")).toString());
        } else {
            QJsonArray rows;
            for (const QVariant &row : r.value(QStringLiteral("rows")).toList()) {
                QJsonArray a;
                for (const QVariant &v : row.toList())
                    a << shortValue(v);
                rows << a;
            }
            out = {{QStringLiteral("ok"), true}, {QStringLiteral("columns"), QJsonArray::fromStringList(r.value(QStringLiteral("columns")).toStringList())},
                   {QStringLiteral("rows"), rows}, {QStringLiteral("rowCount"), rows.size()},
                   {QStringLiteral("truncated"), r.value(QStringLiteral("truncated")).toBool()}, {QStringLiteral("ms"), r.value(QStringLiteral("ms")).toLongLong()}};
        }
    }
    Db::close(name);
    return out;
}

// ——— Terminal ———

namespace {

QString pad(const QString &s, int w) { return s + QString(std::max(0, w - int(s.size())), QLatin1Char(' ')); }

void printTable(QTextStream &out, const QStringList &head, const QList<QStringList> &rows)
{
    QList<int> w;
    for (const QString &h : head)
        w << int(h.size());
    for (const QStringList &r : rows)
        for (int i = 0; i < r.size() && i < w.size(); ++i)
            w[i] = std::min(60, std::max(w[i], int(r.at(i).size())));
    auto line = [&](const QStringList &cells) {
        QStringList parts;
        for (int i = 0; i < head.size(); ++i) {
            QString c = cells.value(i);
            if (c.size() > 60)
                c = c.left(59) + QStringLiteral("…");
            parts << pad(c, w.at(i));
        }
        out << parts.join(QStringLiteral(" │ ")).trimmed() << '\n';
    };
    line(head);
    QStringList sep;
    for (int x : w)
        sep << QString(x, QChar(0x2500));
    out << sep.join(QStringLiteral("─┼─")) << '\n';
    for (const QStringList &r : rows)
        line(r);
}

QString text(const QJsonValue &v)
{
    if (v.isNull())
        return QStringLiteral("NULL");
    if (v.isDouble())
        return QString::number(v.toDouble(), 'g', 15);
    if (v.isBool())
        return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    return v.toString().replace(QLatin1Char('\n'), QStringLiteral("↵ "));
}

void usage(QTextStream &out)
{
    out << "Aster Vault — bazy danych SQLite, PostgreSQL i MySQL/MariaDB\n\n"
           "  aster-vault [PLIK.db]                    okno programu (opcjonalnie od razu z plikiem SQLite)\n"
           "  aster-vault --list                       zapisane połączenia\n"
           "  aster-vault --schema POŁĄCZENIE [TABELA] tabele i kolumny albo struktura jednej tabeli\n"
           "  aster-vault --query POŁĄCZENIE \"SQL\"     wynik zapytania (tylko do odczytu)\n"
           "      --limit N   najwyżej N wierszy (domyślnie 100, maks. 1000)\n"
           "      --json      wynik w JSON (dla programów i asystenta)\n"
           "  aster-vault --service                    usługa D-Bus org.aster.Vault (uruchamiana sama)\n\n"
           "POŁĄCZENIE to nazwa albo identyfikator zapisanego połączenia, albo ścieżka pliku SQLite.\n"
           "Polecenia w terminalu i asystent tylko czytają — zmiany robi się w oknie programu.\n";
}

} // namespace

int Agent::runCli(const QStringList &args)
{
    QTextStream out(stdout), err(stderr);
    const bool json = args.contains(QStringLiteral("--json"));
    int limit = 100;
    QStringList pos;
    QString mode;
    for (int i = 1; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a == QLatin1String("--json"))
            continue;
        if (a == QLatin1String("--limit") && i + 1 < args.size()) {
            limit = args.at(++i).toInt();
        } else if (a == QLatin1String("--list") || a == QLatin1String("--schema") || a == QLatin1String("--query")
                   || a == QLatin1String("--help") || a == QLatin1String("-h")) {
            mode = a;
        } else {
            pos << a;
        }
    }
    if (mode == QLatin1String("--help") || mode == QLatin1String("-h")) {
        usage(out);
        return 0;
    }
    QJsonObject r;
    if (mode == QLatin1String("--list")) {
        r = list();
    } else if (mode == QLatin1String("--schema")) {
        if (pos.isEmpty()) {
            usage(err);
            return 2;
        }
        r = schema(pos.at(0), pos.value(1));
    } else {
        if (pos.size() < 2) {
            usage(err);
            return 2;
        }
        // SQL z kilku argumentów (bez cudzysłowu) albo „-” — ze standardowego wejścia
        QString sql = pos.mid(1).join(QLatin1Char(' '));
        if (sql == QLatin1String("-"))
            sql = QTextStream(stdin).readAll();
        r = query(pos.at(0), sql, limit);
    }

    if (json) {
        out << QString::fromUtf8(QJsonDocument(r).toJson(QJsonDocument::Indented));
        return r.value(QStringLiteral("ok")).toBool() ? 0 : 1;
    }
    if (!r.value(QStringLiteral("ok")).toBool()) {
        err << "aster-vault: " << r.value(QStringLiteral("error")).toString() << '\n';
        return 1;
    }
    if (mode == QLatin1String("--list")) {
        QList<QStringList> rows;
        for (const QJsonValue &v : r.value(QStringLiteral("connections")).toArray()) {
            const QJsonObject c = v.toObject();
            const QString where = c.value(QStringLiteral("kind")).toString() == QLatin1String("sqlite")
                ? c.value(QStringLiteral("file")).toString()
                : QStringLiteral("%1:%2/%3").arg(c.value(QStringLiteral("host")).toString()).arg(c.value(QStringLiteral("port")).toInt()).arg(c.value(QStringLiteral("database")).toString());
            rows << QStringList{c.value(QStringLiteral("name")).toString(), c.value(QStringLiteral("engine")).toString(), where};
        }
        if (rows.isEmpty())
            out << "Brak zapisanych połączeń — dodaj je w oknie Aster Vault.\n";
        else
            printTable(out, {QStringLiteral("Nazwa"), QStringLiteral("Baza"), QStringLiteral("Gdzie")}, rows);
    } else if (mode == QLatin1String("--schema") && pos.size() < 2) {
        for (const QJsonValue &v : r.value(QStringLiteral("objects")).toArray()) {
            const QJsonObject o = v.toObject();
            QStringList cols;
            for (const QJsonValue &c : o.value(QStringLiteral("columns")).toArray())
                cols << c.toString();
            out << (o.value(QStringLiteral("type")).toString() == QLatin1String("view") ? "widok  " : "tabela ") << o.value(QStringLiteral("name")).toString()
                << " (" << cols.join(QStringLiteral(", ")) << ")\n";
        }
    } else if (mode == QLatin1String("--schema")) {
        const QJsonObject t = r.value(QStringLiteral("table")).toObject();
        QList<QStringList> rows;
        for (const QJsonValue &v : t.value(QStringLiteral("columns")).toArray()) {
            const QJsonObject c = v.toObject();
            rows << QStringList{c.value(QStringLiteral("name")).toString(), c.value(QStringLiteral("type")).toString(),
                                c.value(QStringLiteral("nullable")).toBool() ? QString() : QStringLiteral("NOT NULL"),
                                c.value(QStringLiteral("pk")).toBool() ? QStringLiteral("klucz") : QString(), c.value(QStringLiteral("default")).toString()};
        }
        printTable(out, {QStringLiteral("Kolumna"), QStringLiteral("Typ"), QString(), QString(), QStringLiteral("Domyślnie")}, rows);
        const QJsonArray idx = t.value(QStringLiteral("indexes")).toArray();
        if (!idx.isEmpty()) {
            out << "\nIndeksy:\n";
            for (const QJsonValue &v : idx)
                out << "  " << v.toObject().value(QStringLiteral("name")).toString() << " (" << v.toObject().value(QStringLiteral("columns")).toString() << ")"
                    << (v.toObject().value(QStringLiteral("unique")).toBool() ? " unikalny" : "") << '\n';
        }
        const QJsonArray fks = t.value(QStringLiteral("foreignKeys")).toArray();
        if (!fks.isEmpty()) {
            out << "\nKlucze obce:\n";
            for (const QJsonValue &v : fks)
                out << "  " << v.toObject().value(QStringLiteral("columns")).toString() << " → " << v.toObject().value(QStringLiteral("refTable")).toString()
                    << " (" << v.toObject().value(QStringLiteral("refColumns")).toString() << ")\n";
        }
    } else {
        QStringList head;
        for (const QJsonValue &c : r.value(QStringLiteral("columns")).toArray())
            head << c.toString();
        QList<QStringList> rows;
        for (const QJsonValue &row : r.value(QStringLiteral("rows")).toArray()) {
            QStringList l;
            for (const QJsonValue &v : row.toArray())
                l << text(v);
            rows << l;
        }
        printTable(out, head, rows);
        out << "\n(" << rows.size() << (r.value(QStringLiteral("truncated")).toBool() ? "+" : "") << " w., "
            << r.value(QStringLiteral("ms")).toInteger() << " ms)\n";
    }
    return 0;
}

// ——— D-Bus ———

VaultService::VaultService(QObject *parent)
    : QObject(parent)
{
    m_idle.setSingleShot(true);
    m_idle.setInterval(5 * 60 * 1000);
    connect(&m_idle, &QTimer::timeout, qApp, &QCoreApplication::quit);
    m_idle.start();
}

static QString toJson(const QJsonObject &o) { return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact)); }

QString VaultService::Connections()
{
    m_idle.start();
    return toJson(Agent::list());
}

QString VaultService::Schema(const QString &connection, const QString &table)
{
    m_idle.start();
    return toJson(Agent::schema(connection, table));
}

QString VaultService::Query(const QString &connection, const QString &sql, int limit)
{
    m_idle.start();
    return toJson(Agent::query(connection, sql, limit));
}

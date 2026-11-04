#pragma once

#include <QSqlDatabase>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// Wspólny rdzeń baz danych Aster Vault — bez interfejsu i bez wątków, używany przez okno (w wątku roboczym),
// polecenie w terminalu i usługę D-Bus dla asystenta.
//
// Połączenie to QVariantMap: { id, name, kind: sqlite|postgres|mysql, file, host, port, database, user,
// readOnly, savePassword, color }. Hasło nie jest częścią zapisanego połączenia — przychodzi z portfela.
namespace Db {

enum class Kind { SQLite, Postgres, MySQL };
Kind kindOf(const QVariantMap &conn);
QString kindName(Kind k);                  // „SQLite”, „PostgreSQL”, „MySQL / MariaDB”
QString qtDriver(Kind k);                  // QSQLITE, QPSQL, QMYSQL
bool driverAvailable(Kind k);
int defaultPort(Kind k);

// Otwiera połączenie o nazwie `name` (QSqlDatabase::addDatabase). readOnly — tryb tylko do odczytu na
// poziomie bazy (SQLite: plik otwarty do odczytu, PostgreSQL/MySQL: transakcje READ ONLY) i limit czasu zapytań.
bool open(const QString &name, const QVariantMap &conn, const QString &password, bool readOnly, QString *error);
void close(const QString &name);

// Struktura bazy
QStringList databases(QSqlDatabase &db, Kind k);
// [{ schema, name, type: table|view }]
QVariantList objects(QSqlDatabase &db, Kind k);
// { columns: [{ name, type, nullable, default, pk }], indexes: [{ name, columns, unique, primary }],
//   foreignKeys: [{ name, columns, refTable, refColumns }], primaryKey: [..], ddl, type }
QVariantMap schema(QSqlDatabase &db, Kind k, const QString &schemaName, const QString &table);
// Kolumny wszystkich tabel naraz — do podpowiedzi w edytorze: { "tabela": ["kol", …] }
QVariantMap allColumns(QSqlDatabase &db, Kind k);

// Zapytania
QStringList splitStatements(const QString &sql);
bool isReadOnlyStatement(const QString &statement);
bool isRisky(const QString &statement);    // DROP, TRUNCATE, DELETE/UPDATE bez WHERE
// Jedno polecenie. { ok, error, columns, types, rows: [[…]], affected, truncated, ms, select }
QVariantMap run(QSqlDatabase &db, const QString &statement, int maxRows, const QVariantList &binds = {});
// Wiele poleceń po kolei; wynik ostatniego z wierszami (albo ostatniego w ogóle) + { statements, messages }
QVariantMap runScript(QSqlDatabase &db, const QString &sql, int maxRows, bool readOnly);
// Zmiany z siatki w jednej transakcji: [{ sql, binds }]
QVariantMap applyChanges(QSqlDatabase &db, const QVariantList &changes);

QString quoteIdent(Kind k, const QString &name);
QString qualified(Kind k, const QString &schemaName, const QString &table);
QString literal(const QVariant &v);        // do podglądu zmian: 'tekst', 12, NULL
QString cellText(const QVariant &v, int maxLen = 0);   // wartość w siatce i w eksporcie
QVariant jsonValue(const QVariant &v);

// Eksport wyniku zapytania do pliku (wszystkie wiersze, strumieniowo). format: csv|json
QVariantMap exportQuery(QSqlDatabase &db, const QString &statement, const QString &path, const QString &format);

} // namespace Db

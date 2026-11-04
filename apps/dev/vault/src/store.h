#pragma once

#include <QVariantList>
#include <QVariantMap>

// Zapisane połączenia (~/.config/aster-vault/connections.json — bez haseł, te są w portfelu)
// i historia zapytań (~/.local/share/aster-vault/history.json).
namespace Store {
QVariantList connections();
void saveConnections(const QVariantList &list);
// Po identyfikatorze, nazwie (bez wielkości liter) albo ścieżce pliku SQLite (wtedy połączenie doraźne)
QVariantMap find(const QString &idOrName);
QString newId();

QVariantList history(const QString &connectionId = QString(), int limit = 200);
void addHistory(const QVariantMap &entry);   // { conn, sql, ok, rows, ms, error }
void clearHistory(const QString &connectionId);
}

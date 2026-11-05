#pragma once

#include <QJsonObject>
#include <QString>

// Polecenie cURL ⇄ zapytanie Pulse (format z workspace.h).
// Import rozumie to, co dają przeglądarki („Kopiuj jako cURL”) i dokumentacje API: -X, -H, -d/--data*,
// --data-urlencode, --json, -F, -u, -A, -b, -e, -G, -I, -k, --url, cudzysłowy '…', "…", $'…' i \ na końcu wiersza.
namespace Curl {
QJsonObject parse(const QString &command, QString *error = nullptr);
// multiline — każda opcja w nowym wierszu (z \), jak w dokumentacjach
QString build(const QJsonObject &req, bool multiline = true);
// Słowa jak w powłoce (bez rozwijania zmiennych)
QStringList split(const QString &command, QString *error = nullptr);
}

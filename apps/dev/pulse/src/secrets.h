#pragma once

#include <QMap>
#include <QString>

// Sekrety środowisk (tokeny, hasła) w portfelu systemu przez Secret Service (org.freedesktop.secrets —
// w Aster daje go KWallet, gdzie indziej np. GNOME Keyring). Do plików obszaru roboczego trafia tylko nazwa zmiennej.
// Wywołania są blokujące; gdy portfel jest zamknięty, czekają na okienko z hasłem (do 2 minut).
namespace Secrets {
// Wartość wpisu o tych atrybutach albo pusty napis; error — opis problemu (brak portfela, odmowa…)
QString read(const QMap<QString, QString> &attrs, QString *error = nullptr);
// Zapis (zastępuje wpis o tych samych atrybutach); pusta wartość usuwa wpis
bool write(const QMap<QString, QString> &attrs, const QString &label, const QString &value, QString *error = nullptr);
// Czy w sesji jest portfel
bool available();
}

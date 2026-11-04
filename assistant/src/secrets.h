#pragma once

#include <QString>

// Klucze API w portfelu systemu przez Secret Service (org.freedesktop.secrets — w Aster daje go KWallet,
// ksecretd; w innych środowiskach np. GNOME Keyring). Nic nie trafia do plików konfiguracyjnych.
// Wywołania są blokujące; gdy portfel jest zamknięty, czekają na okienko z hasłem (do 2 minut).
namespace Secrets {
// Klucz dostawcy albo pusty napis; error — opis problemu (brak portfela, odmowa…)
QString read(const QString &provider, QString *error = nullptr);
// Zapis; pusty klucz usuwa wpis
bool write(const QString &provider, const QString &label, const QString &key, QString *error = nullptr);
}

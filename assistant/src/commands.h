#pragma once

#include <QString>

// Polecenia, które agent chce uruchomić: które zrobić od razu, a o które najpierw zapytać.
//
// Domyślnie (Ustawienia → Aster Intelligence → „Pytaj o zgodę”: tylko przy ważnych) agent działa sam, a pyta tylko
// przed tym, czego nie da się łatwo cofnąć albo co sięga poza konto użytkownika: instalacja i usuwanie programów,
// usuwanie i nadpisywanie plików, uprawnienia administratora, aktualizacja i restart systemu, zatrzymywanie
// programów i usług, zmiany dysków, sieci i kont, skrypty z internetu. Otwieranie programów, tworzenie folderów,
// kopiowanie, głośność, jasność, sprawdzanie — bez pytania.
// Tryb ostrożny („przy każdej zmianie”) — bez pytania tylko polecenia, które niczego nie zmieniają (readOnly).
namespace Commands {
// Tylko odczyt: znane polecenia, które niczego nie zmieniają, bez przekierowań do plików, podstawień i łańcuchów
bool readOnly(const QString &command);
// Ważne — trzeba zapytać; why: krótko, czemu (do testów i dziennika)
bool needsConsent(const QString &command, QString *why = nullptr);
}

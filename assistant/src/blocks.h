#pragma once

#include <QList>
#include <QString>

// Bloki w odpowiedzi agenta (```…```), czytane wierszami — także w bloku z czterema „`”, w którym może być ``` (np. README):
//   ```bash            polecenie do uruchomienia (sh, shell, zsh, console — to samo)
//   ```plik:ŚCIEŻKA     cała treść pliku do zapisania
//   ```zmiana:ŚCIEŻKA   zamiana fragmentów istniejącego pliku:
//                        <<<<<<< STARE
//                        dokładny dotychczasowy fragment
//                        =======
//                        nowy fragment
//                        >>>>>>> NOWE
// Wspólne dla usługi (co uruchomić), terminala i panelu (czego nie pokazywać jako tekst).
namespace Blocks {

struct Block {
    QString kind;        // bash | plik | zmiana | inny
    QString arg;         // ścieżka przy plik/zmiana
    QString body;
    qsizetype start = 0; // początek wiersza otwierającego
    qsizetype end = 0;   // za wierszem zamykającym (albo koniec tekstu, gdy blok niedomknięty)
    bool closed = false;
};

QList<Block> parse(const QString &text);
// Pierwsze polecenie z zamkniętego bloku powłoki (wiersze „$ ” bez znaku zachęty, bez komentarzy)
QString command(const QList<Block> &blocks);
// Tekst do pokazania: bez bloków powłoki, a pliki jako krótkie wiersze („Zapisuję plik app.py”)
QString display(const QString &text);
// Do historii wysyłanej modelowi: treść plików zastąpiona krótką notką (model może przeczytać plik ponownie)
QString compact(const QString &text);

struct Hunk {
    QString before;
    QString after;
};
// Bloki zmian z treści ```zmiana; pusta lista — nic nie rozpoznano
QList<Hunk> hunks(const QString &body);

} // namespace Blocks

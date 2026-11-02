# Aster

Prosty i ładny system dla osób przesiadających się z Windowsa.
Baza: Fedora z KDE (KWin, Wayland). Na wierzchu własna powłoka **aster-shell**.

## Co gdzie jest

| Folder | Zawartość |
|---|---|
| `prototype/` | Interaktywny prototyp całego pulpitu (QML + PySide6, działa na Macu). Wzór wyglądu i zachowania. |
| `shell/` | Prawdziwa powłoka: C++/Qt 6 + QML. Tapeta z widżetami, dok, górny pasek z dynamiczną wyspą, Start i centrum sterowania jako warstwy Wayland. |
| `apps/files/` | Pliki — menedżer plików (KIO: kosz, kopiowanie w tle, cofanie, wyszukiwanie). |
| `apps/browser/` | Przeglądarka — silnik Qt WebEngine (Chromium), wygląd Aster: karty i okna (też prywatne), historia, ulubione, pobrane, blokowanie śledzenia, przywracanie sesji. |
| `apps/webapps/` | Aplikacje webowe — strony jako natywne programy (okno, ikona, powiadomienia, liczniki w doku). |
| `apps/store/` | Sklep — programy z Flathub (flatpak), wygląd jak App Store. |
| `apps/terminal/` | Terminal — emulacja libvterm, własne rysowanie (ramki i bloki bez szczelin), karty, historia z wyszukiwaniem, linki, schematy kolorów, Ctrl+C/Ctrl+V jak w Windows. |
| `apps/tasks/` | Menedżer zadań (Ctrl+Shift+Esc) — procesy pogrupowane po programach jak w Windows, „Zakończ zadanie”, właściwości, wykresy procesora, pamięci, dysków i sieci; dane prosto z `/proc` i `/sys`. |
| `apps/photos/` | Zdjęcia — biblioteka zdjęć z kilku folderów, oglądanie z miniaturami folderu, powiększanie, informacje z aparatu (exiv2), obrót bez utraty jakości, kosz z cofaniem, tapeta z własnego zdjęcia. |
| `apps/pdf/` | Podgląd PDF — strony z cieniem na szarym tle (QtPdf), spis treści i miniatury, szukanie, zaznaczanie tekstu, linki, hasło, drukowanie, wracanie do ostatnio czytanej strony. |
| `apps/editor/` | Edytor tekstu — karty, niezapisane karty wracają po ponownym otwarciu, szukaj/zamień, numery wierszy, kolorowanie kodu (KSyntaxHighlighting), pliki z Windows (Windows-1250, CRLF). |
| `apps/calculator/` | Kalkulator — standardowy i naukowy, historia, wynik na żywo, procenty jak w Windows, polski zapis liczb; `ASTER_TEST=1` sprawdza obliczenia. |
| `apps/video/` | Wideo — ostatnio oglądane z miejscem, w którym przerwano, napisy SRT/VTT/MicroDVD/MPL2 (także Windows-1250), ścieżki dźwięku, prędkość, następny film z folderu. |
| `apps/music/` | Muzyka — albumy z okładkami, wykonawcy, utwory, kolejka, losowo i powtarzanie; biblioteka z tagów (TagLib). |
| `common/mediasession.*` | Wspólne dla Wideo i Muzyki: MPRIS (Centrum sterowania, klawisze multimedialne) i blokada wygaszacza podczas filmu. |
| `apps/portal/` | Okna systemowe dla xdg-desktop-portal — na razie „Otwórz / Zapisz” dla wszystkich programów (Flathub, Qt/KDE, GTK). |
| `apps/settings/` | Ustawienia — komplet działów (sieć, Bluetooth, dźwięk, powiadomienia, wygląd, ekran, zasilanie, mysz, klawiatura i skróty, drukarki, data, język, aplikacje, dostępność, prywatność, konta) bez odsyłania do ustawień KDE. |
| `common/` | Wspólny wygląd: motyw i ikony liniowe (moduł QML `Aster.Ui`). |
| `session/` | Sesja logowania „Aster”: KWin i usługi Plasmy, ale zamiast plasmashell działa aster-shell. |
| `image/` | Szkic obrazu systemu (Fedora Kinoite + Aster), do zbudowania i instalacji jako atomowy system. |
| `data/wallpapers/` | Tapety: „Aura” z projektu UI (`tools/make_aura.py`, domyślna), „Aster Bloom” (`tools/make_bloom.py`) i krajobrazy (`tools/make_wallpapers.py`). |
| `tools/` | Skrypty: przygotowanie maszyny wirtualnej, uruchamianie powłoki w trakcie pracy, tapety. |
| `docs/` | Architektura i instrukcja maszyny wirtualnej. |

## Jak to działa

```
KWin (okna, animacje, rozmycie)  ←  zostaje z KDE
Usługi Plasmy (dźwięk, sieć, ustawienia, powiadomienia)  ←  zostają
plasmashell (pulpit KDE)  ✗  wyłączony w sesji Aster
aster-shell (nasz pulpit)  ←  tapeta, dok, wyspa, Start, centrum sterowania…
```

## Plan

Szczegóły etapów: [docs/PLAN.md](docs/PLAN.md).

Prototyp uruchamiasz na Macu: `cd prototype && python main.py` (z PySide6).
Praca nad prawdziwą powłoką: zobacz [docs/MASZYNA-WIRTUALNA.md](docs/MASZYNA-WIRTUALNA.md).

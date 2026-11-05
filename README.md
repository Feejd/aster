# Aster

Prosty i ładny system dla osób przesiadających się z Windowsa.
Baza: Fedora z KDE (KWin, Wayland). Na wierzchu własna powłoka **aster-shell**.

## Aster Pixel na dowolnym Linuksie

Program Aster Pixel (dawniej Grafika: posty, plakaty, zaproszenia, CV) działa też poza Astrem — na Fedorze, Ubuntu, Mincie,
Debianie, Archu i innych. Instalacja jedną komendą w terminalu:

```sh
curl -fsSL https://raw.githubusercontent.com/Feejd/aster/main/tools/install-grafika.sh | sh
```

Skrypt w razie potrzeby instaluje Flatpak, a potem Aster Pixel (paczka z wydania „aplikacje”, budowana przez
`.github/workflows/flatpak.yml`). Ponowne uruchomienie aktualizuje program.
Odinstalowanie: `flatpak uninstall --user org.aster.grafika`.

Narzędzia AI w Aster Pixel (usuwanie tła, magiczna gumka, wyodrębnianie obiektu kliknięciem, pędzlem albo lassem)
działają na komputerze, przez ONNX Runtime, na małych modelach o wolnych licencjach: ISNet (Apache 2.0, 179 MB),
MobileSAM (Apache 2.0, 45 MB) i MI-GAN (MIT, 28 MB). Modele pobierają się przy pierwszym użyciu do
`~/.local/share/aster-grafika/models`; zdjęcia nigdzie nie są wysyłane.

## Co gdzie jest

| Folder | Zawartość |
|---|---|
| `prototype/` | Interaktywny prototyp całego pulpitu (QML + PySide6, działa na Macu). Wzór wyglądu i zachowania. |
| `shell/` | Prawdziwa powłoka: C++/Qt 6 + QML. Tapeta z widżetami, dok, górny pasek z dynamiczną wyspą, Start i centrum sterowania jako warstwy Wayland. |
| `apps/files/` | Pliki — menedżer plików (KIO: kosz, kopiowanie w tle, cofanie, wyszukiwanie); archiwa przez libarchive: ZIP/TAR jak folder, Wypakuj wszystko, Kompresuj (ZIP z hasłem, 7z, TAR); pendrive’y: Wysuń, Formatuj (UDisks2). |
| `apps/browser/` | Przeglądarka — silnik Qt WebEngine (Chromium), wygląd Aster: karty i okna (też prywatne), historia, ulubione, pobrane, blokowanie śledzenia, przywracanie sesji. |
| `apps/webapps/` | Aplikacje webowe — strony jako natywne programy (okno, ikona, powiadomienia, liczniki w doku). |
| `apps/store/` | Sklep — programy z Flathub (flatpak), wygląd jak App Store. |
| `apps/terminal/` | Terminal — emulacja libvterm, własne rysowanie (ramki i bloki bez szczelin), karty, historia z wyszukiwaniem, linki, schematy kolorów, Ctrl+C/Ctrl+V jak w Windows. |
| `apps/tasks/` | Menedżer zadań (Ctrl+Shift+Esc) — procesy pogrupowane po programach jak w Windows, „Zakończ zadanie”, właściwości, wykresy procesora, pamięci, dysków i sieci; dane prosto z `/proc` i `/sys`. |
| `apps/photos/` | Zdjęcia — biblioteka zdjęć z kilku folderów, oglądanie z miniaturami folderu, powiększanie, informacje z aparatu (exiv2), obrót bez utraty jakości, kosz z cofaniem, tapeta z własnego zdjęcia. |
| `apps/pdf/` | Podgląd PDF — strony z cieniem na szarym tle (QtPdf), spis treści i miniatury, szukanie, zaznaczanie tekstu, linki, hasło, drukowanie, wracanie do ostatnio czytanej strony. |
| `apps/editor/` | Edytor tekstu — karty, niezapisane karty wracają po ponownym otwarciu, szukaj/zamień, numery wierszy, kolorowanie kodu (KSyntaxHighlighting), pliki z Windows (Windows-1250, CRLF). |
| `apps/code/` | Aster Code — edytor kodu dla przesiadających się z VS Code: folder projektu z drzewem plików (nowy plik/folder, zmiana nazwy, kosz), karty z podglądem, kolorowanie składni, wcięcia i komentarze (Ctrl+/), przenoszenie wierszy (Alt+↑/↓), paleta Ctrl+P / Ctrl+Shift+P, szukanie w pliku i w całym projekcie, terminal na dole (Ctrl+`), git: gałąź, zmiany przy marginesie, dodawanie, zatwierdzanie, wysyłanie i pobieranie, podgląd różnic; serwery języków (LSP): podpowiedzi, F12 — definicja, opis po najechaniu, błędy w panelu Problemy. |
| `apps/calculator/` | Kalkulator — standardowy i naukowy, historia, wynik na żywo, procenty jak w Windows, polski zapis liczb; `ASTER_TEST=1` sprawdza obliczenia. |
| `apps/video/` | Wideo — ostatnio oglądane z miejscem, w którym przerwano, napisy SRT/VTT/MicroDVD/MPL2 (także Windows-1250), ścieżki dźwięku, prędkość, następny film z folderu. |
| `apps/music/` | Muzyka — albumy z okładkami, wykonawcy, utwory, kolejka, losowo i powtarzanie; biblioteka z tagów (TagLib). |
| `apps/camera/` | Kamera — zdjęcia i filmy z kamery internetowej, samowyzwalacz, siatka, lustro; zapis do „Z aparatu” (zamiast Kamoso). |
| `apps/montaz/` | Montaż (nazwa robocza) — prosty edytor filmów na MLT: formaty 9:16 / 16:9 / 1:1, oś czasu z wideo, napisami i muzyką, przycinanie i dzielenie, przenikanie, prędkość, głośność; eksport MP4 (H.264/AAC), a bez kodera H.264 — WebM. |
| `apps/studio/` | Studio (nazwa robocza) — studio nagrań w duchu BandLaba: szablony gatunków (Trap, Drill, Boom bap, Lo-fi, House, Pop), Beat Maker i 808 syntezowane w programie, nagrywanie z odliczaniem, pętle, efekty z presetami (wokal trap, echo, ciepło), mastering, mikser, eksport do MP3/WAV/OGG/FLAC. Silnik: PipeWire w wątku czasu rzeczywistego + libsndfile. |
| `apps/scanner/` | Skaner — SANE (USB i sieciowe przez sane-airscan): podgląd z kadrem, szyba lub podajnik, strony do PDF albo JPG/PNG (zamiast Skanlite). |
| `apps/grafika/` | Aster Pixel (dawniej Grafika) — posty, relacje, plakaty, zaproszenia, CV, miniaturki YouTube i slajdy bez internetu: gotowe rozmiary, 16 własnych szablonów, tekst, kształty, zdjęcia, tło; zapis sam w Dokumenty/Grafiki (plik `.grafika` = ZIP z JSON, opis w `docs/grafika-format.md`), eksport PNG/JPG/PDF. |
| `apps/phone/` | Telefon — KDE Connect przez D-Bus: bateria i zasięg, parowanie z kodem, znajdź telefon, pliki i schowek, pliki telefonu, powiadomienia. |
| `apps/installer/` | Instalator — na cały ekran z pendrive’a: język, klawiatura, Wi‑Fi, strefa, dysk, konto, wygląd; `bootc install to-disk` (ISO: `tools/build-iso.sh`). |
| `apps/emoji/` | Panel emoji i znaków (Win+.) — szukanie po polsku, odcienie skóry, kaomoji, symbole; wstawia do aktywnego programu. Dane: `tools/make-emoji-data.py` (Unicode + CLDR). |
| `common/mediasession.*` | Wspólne dla Wideo i Muzyki: MPRIS (Centrum sterowania, klawisze multimedialne) i blokada wygaszacza podczas filmu. |
| `apps/portal/` | Okna systemowe dla xdg-desktop-portal — na razie „Otwórz / Zapisz” dla wszystkich programów (Flathub, Qt/KDE, GTK). |
| `apps/settings/` | Ustawienia — komplet działów (sieć, Bluetooth, dźwięk, powiadomienia, wygląd, ekran, zasilanie, mysz, klawiatura i skróty, drukarki, data, język, aplikacje, dostępność, prywatność, konta, pamięć dysku) bez odsyłania do ustawień KDE. |
| `common/` | Wspólny wygląd: motyw i ikony liniowe (moduł QML `Aster.Ui`). |
| `session/` | Sesja logowania „Aster”: KWin i usługi Plasmy, ale zamiast plasmashell działa aster-shell. |
| `image/` | Szkic obrazu systemu (Fedora Kinoite + Aster), do zbudowania i instalacji jako atomowy system. |
| `data/wallpapers/` | Tapety: Grzbiety (domyślna), Mgła, Pasma i Papier, każda jasna i ciemna (`tools/make-wallpapers.py`) |
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

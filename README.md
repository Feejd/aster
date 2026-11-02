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

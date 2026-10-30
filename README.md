# Aster

Prosty i ładny system dla osób przesiadających się z Windowsa.
Baza: Fedora z KDE (KWin, Wayland). Na wierzchu własna powłoka **aster-shell**.

## Co gdzie jest

| Folder | Zawartość |
|---|---|
| `prototype/` | Interaktywny prototyp całego pulpitu (QML + PySide6, działa na Macu). Wzór wyglądu i zachowania. |
| `shell/` | Prawdziwa powłoka: C++/Qt 6 + QML. Tapeta, dok, Start, górna wyspa jako warstwy Wayland. |
| `apps/files/` | Pliki — menedżer plików (KIO: kosz, kopiowanie w tle, cofanie, wyszukiwanie). |
| `apps/browser/` | Przeglądarka — silnik Qt WebEngine (Chromium), wygląd Aster. |
| `apps/webapps/` | Aplikacje webowe — strony jako natywne programy (okno, ikona, powiadomienia, liczniki w doku). |
| `common/` | Wspólny wygląd: motyw i ikony liniowe (moduł QML `Aster.Ui`). |
| `session/` | Sesja logowania „Aster”: KWin i usługi Plasmy, ale zamiast plasmashell działa aster-shell. |
| `image/` | Szkic obrazu systemu (Fedora Kinoite + Aster), do zbudowania i instalacji jako atomowy system. |
| `data/wallpapers/` | Tapety (generowane przez `tools/make_wallpapers.py`). |
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

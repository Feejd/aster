# Aster

Prosty i ładny system dla osób przesiadających się z Windowsa.
Baza: Fedora z KDE (KWin, Wayland). Na wierzchu własna powłoka **aster-shell**.

## Co gdzie jest

| Folder | Zawartość |
|---|---|
| `prototype/` | Interaktywny prototyp całego pulpitu (QML + PySide6, działa na Macu). Wzór wyglądu i zachowania. |
| `shell/` | Prawdziwa powłoka: C++/Qt 6 + QML. Tapeta, dok, górna wyspa jako warstwy Wayland. |
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

1. **Powłoka w maszynie wirtualnej** — tapeta, dok z prawdziwymi oknami, górna wyspa z zegarem. ← *teraz*
2. Start z wyszukiwaniem, centrum sterowania (dźwięk, Wi‑Fi, jasność), powiadomienia w wyspie.
3. Wygląd okien: własne dekoracje KWin (okrągłe przyciski), styl Qt, ikony, kursor, ekran logowania.
4. Obraz systemu (`image/`), instalator, aktualizacje w tle.
5. Własne aplikacje: Pliki, Ustawienia, Sklep — przeniesione z prototypu.

Prototyp uruchamiasz na Macu: `cd prototype && python main.py` (z PySide6).
Praca nad prawdziwą powłoką: zobacz [docs/MASZYNA-WIRTUALNA.md](docs/MASZYNA-WIRTUALNA.md).

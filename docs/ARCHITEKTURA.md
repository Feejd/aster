# Architektura

## Warstwy

- **KWin** (z KDE) — kompozytor Wayland: okna, animacje, rozmycie tła (efekt *blur*),
  przyciąganie okien, pełny ekran. Konfigurujemy go i dopisujemy efekty, nie piszemy od zera.
- **Usługi Plasmy** — PipeWire (dźwięk), NetworkManager, BlueZ, powiadomienia, ustawienia systemu.
  Powłoka korzysta z nich przez gotowe moduły QML (np. `org.kde.taskmanager`).
- **aster-shell** — nasz pulpit. Jeden proces Qt 6, kilka okien-warstw (`wlr-layer-shell` przez LayerShellQt):

| Okno | Warstwa | Rezerwuje miejsce | Opis |
|---|---|---|---|
| `WallpaperWindow` | background | nie | tapeta dzień/noc |
| `DockWindow` | top | 84 px na dole | trzy wyspy: wyszukiwanie, dok, zegar |
| `HorizonWindow` | top | nie | górna wyspa |

## Szkło

W prototypie rozmycie liczył sam QML. W prawdziwej powłoce rozmywa **KWin**: okno zgłasza
prostokąty wysp przez `Platform.setBlur()` (KWindowEffects), a QML rysuje tylko półprzezroczysty
odcień, krawędź i cień. Dzięki temu rozmyte jest to, co naprawdę leży pod spodem (okna, tapeta).

## Dok

`TaskManager.TasksModel` z plasma-workspace daje przypięte aplikacje i działające okna w jednej liście:
klik aktywuje/uruchamia/minimalizuje, środkowy klik otwiera nowe okno. Dok publikuje położenie ikon
(`requestPublishDelegateGeometry`), więc KWin animuje minimalizację do właściwej ikony.

## Sesja

`startaster` ustawia `ASTER_SESSION=1`, maskuje (tylko do wylogowania) `plasma-plasmashell.service`
i uruchamia zwykłe `startplasma-wayland`. Usługa `aster-shell.service` startuje tylko w tej sesji.

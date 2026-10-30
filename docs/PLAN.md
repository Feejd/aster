# Plan prac

Kolejność: najpierw rzeczy, które użytkownik widzi i dotyka codziennie, potem wygląd całości,
na końcu obraz systemu i własne aplikacje. Każdy etap kończy się czymś, co działa w maszynie wirtualnej.

## Etap 1 — powłoka działa ✅ (prawie)
- [x] Tapeta dzień/noc, dok z prawdziwymi oknami, górna wyspa z datą
- [x] Rozmycie KWin pod wyspami, kliknięcia tylko w wyspy
- [ ] Kilka monitorów (dok i tapeta na każdym ekranie)

## Etap 2 — Start, centrum sterowania, powiadomienia
- [ ] **Start** z prototypu: wyszukiwanie aplikacji, plików i ustawień, przypięte, ostatnie pliki,
      blokada/wyłączanie. Dane z KDE (lista aplikacji, ostatnie dokumenty), uruchamianie przez KIO.
- [ ] **Centrum sterowania**: głośność i wyjście dźwięku (plasma-pa), Wi‑Fi i Bluetooth (plasma-nm,
      bluedevil), jasność i bateria (PowerDevil), tryb ciemny jednym kliknięciem.
- [ ] **Górna wyspa**: chowanie i wysuwanie jak w prototypie, prawdziwe powiadomienia
      (serwer powiadomień z plasma-workspace), panel „Dziś” z kalendarzem i odtwarzaczem (MPRIS).
- [ ] Skróty klawiszowe: Super = Start, Super+A = centrum sterowania.

## Etap 3 — spójny wygląd całego systemu
- [ ] **Ramki okien** (dekoracja KWin): okrągłe kolorowe przyciski, pasek tytułu jak w prototypie.
- [ ] **Efekty KWin**: zasysanie do doku (Magic Lamp), szybsze animacje, przyciąganie do krawędzi.
- [ ] **Kolory i styl aplikacji Qt/KDE**: akcent, zaokrąglenia, czcionka Inter w całym systemie.
- [ ] Ikony i kursor, ekran logowania (SDDM) i ekran blokady w stylu Aster.
- [ ] Wygląd aplikacji GTK (Firefox, LibreOffice) dopasowany do reszty.

## Etap 4 — prawdziwy system do zainstalowania
- [ ] Obraz systemu (`image/Containerfile`) budowany automatycznie przy każdej zmianie.
- [ ] Instalator z ekranem powitalnym („Przesiadasz się z Windowsa?”: przeniesienie plików, konto).
- [ ] Aktualizacje w tle z możliwością cofnięcia (atomowa Fedora), sklep aplikacji z Flathub.
- [ ] Test na prawdziwym laptopie (x86_64).

## Etap 5 — własne aplikacje
- [ ] Ustawienia Aster (proste, jak w prototypie), oparte na modułach KDE.
- [ ] Pliki (menedżer plików z prototypu) i Sklep.
- [ ] Asystent pod klawiszem.

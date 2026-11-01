# Plan prac

Kolejność: najpierw rzeczy, które użytkownik widzi i dotyka codziennie, potem wygląd całości,
na końcu obraz systemu i własne aplikacje. Każdy etap kończy się czymś, co działa w maszynie wirtualnej.

## Etap 1 — powłoka działa ✅ (prawie)
- [x] Tapeta dzień/noc, dok z prawdziwymi oknami, górna wyspa z datą
- [x] Rozmycie KWin pod wyspami, kliknięcia tylko w wyspy
- [ ] Kilka monitorów (dok i tapeta na każdym ekranie)

## Etap 2 — Start, centrum sterowania, powiadomienia
- [x] **Start** z prototypu (pierwsza wersja): wyszukiwanie aplikacji, plików i ustawień, przypięte, ostatnie pliki,
      blokada/wyłączanie. Dane z KDE (lista aplikacji, ostatnie dokumenty), uruchamianie przez KIO.
- [x] **Centrum sterowania** (prawa wyspa doku): Wi‑Fi/sieć (nmcli), Bluetooth (bluetoothctl), „Nie przeszkadzać”,
      ciemny motyw, jasność (PowerDevil), głośność (PipeWire), odtwarzacz (MPRIS), zrzut ekranu, ustawienia, bateria
- [ ] Centrum sterowania: lista sieci Wi‑Fi i urządzeń Bluetooth do wyboru, wybór wyjścia dźwięku
- [x] Powiadomienia systemowe pod górną wyspą (powłoka jest serwerem powiadomień)
- [x] **Nowy układ powłoki**: górny pasek z trzech wysp (aktywny program z tytułem okna, dynamiczna wyspa, stan systemu),
      jeden dok z powiększaniem ikon, podskakiwaniem przy uruchamianiu i Koszem, widżety na pulpicie (kalendarz, bateria, teraz gra)
- [x] Dynamiczna wyspa: godzina, okładka i korektor przy muzyce, data po najechaniu, powiadomienie rozlewa wyspę w kartę
- [ ] Dynamiczna wyspa: postęp pobierania i kopiowania plików, nagrywanie ekranu, minutnik; panel „Dziś” po kliknięciu
- [ ] Menu aktywnego programu na lewej wyspie paska (globalne menu KDE)
- [x] Super = Start
- [ ] Super+A = centrum sterowania

## Etap 3 — spójny wygląd całego systemu
- [ ] **Ramki okien** (dekoracja KWin): okrągłe kolorowe przyciski, pasek tytułu jak w prototypie.
- [ ] **Efekty KWin**: zasysanie do doku (Magic Lamp), szybsze animacje, przyciąganie do krawędzi.
- [x] Okna aplikacji Aster: trójwarstwowy cień zależny od fokusu, szklany rant i odblask, „zorza” w kolorze akcentu,
      kolorowe przyciski okna, sprężyste otwieranie (wspólne WindowShadow / WindowSheen / WindowButtons w Aster.Ui)
- [ ] **Kolory i styl aplikacji Qt/KDE**: akcent, zaokrąglenia, czcionka Geist w całym systemie.
- [ ] Ikony i kursor, ekran logowania (SDDM) i ekran blokady w stylu Aster.
- [ ] Wygląd aplikacji GTK (Firefox, LibreOffice) dopasowany do reszty.

## Etap 4 — prawdziwy system do zainstalowania
- [ ] Obraz systemu (`image/Containerfile`) budowany automatycznie przy każdej zmianie.
- [ ] Instalator z ekranem powitalnym („Przesiadasz się z Windowsa?”: przeniesienie plików, konto).
- [ ] Aktualizacje w tle z możliwością cofnięcia (atomowa Fedora), sklep aplikacji z Flathub.
- [ ] Test na prawdziwym laptopie (x86_64).

## Etap 5 — własne aplikacje
- [x] Ustawienia Aster (`apps/settings`): Wi‑Fi (lista sieci, hasło), Bluetooth (parowanie), dźwięk (wyjścia i wejścia),
      powiadomienia, ogólne (o tym komputerze), wygląd (jasny/ciemny, kolor akcentu), tapeta, pulpit i dok, ekran (nocne światło), konto;
      wspólna konfiguracja `~/.config/aster/aster.conf` (Config w Aster.Ui) zmienia się na żywo we wszystkich programach
- [ ] Ustawienia: programy przypięte do doku, rozmiar tekstu, data i czas, język, użytkownicy — bez modułów KDE
- [x] Pliki — pierwsza wersja (KIO: kosz, kopiowanie, cofanie, wyszukiwanie, podgląd)
- [ ] Pliki: dyski USB i sieciowe, „Otwórz za pomocą”, właściwości, przeciąganie do innych aplikacji
- [x] Przeglądarka — pierwsza wersja (Qt WebEngine/Chromium: karty, ulubione, historia, pobieranie, uprawnienia, szukanie na stronie)
- [ ] Przeglądarka: blokowanie reklam, tryb prywatny, przywracanie kart po restarcie, import zakładek z Chrome/Edge
- [x] Aplikacje webowe — strony jako programy: własne okno w kolorze aplikacji, ikona-kafelek, ekran powitalny, powiadomienia systemowe, liczniki w doku, osobne logowanie, katalog polecanych, instalacja z przeglądarki
- [x] Aplikacje webowe: nawigacja strony w oknie Aster — boczne menu jako natywny pasek boczny, górne zakładki w pasku tytułu, pasek strony jako pasek tytułu (przeciąganie)
- [x] Aplikacje webowe: sekcje i liczniki menu, główny przycisk strony, natywna wyszukiwarka, kolory okna z kolorów strony (też ciemnych), czcionka Geist i akcent Aster w treści, natywne dymki i okna alert/confirm/prompt
- [x] Aplikacje webowe: natywne nakładki dla popularnych serwisów (YouTube): pasek boczny i tytuł Aster, wyszukiwarka z podpowiedziami, konto, treść na szkle okna
- [ ] Nakładki dla kolejnych serwisów: YouTube Music, Gmail, Spotify, WhatsApp, Messenger, Notion, ChatGPT
- [ ] Aplikacje z Androida (APK) przez Waydroid jako zwykłe programy w Starcie i doku
- [ ] Aplikacje webowe: działanie w tle po zamknięciu okna (komunikatory), kilka kont jednej aplikacji, ustawienia aplikacji
- [x] Sklep — Flathub przez flatpak (bez hasła): Odkrywaj (polecenie dnia, odpowiedniki programów z Windowsa, ranking, nowości), kategorie, wyszukiwanie, strona aplikacji, instalacja z postępem, zainstalowane, aktualizacje
- [ ] Sklep: aplikacje webowe i z Androida w jednym miejscu, oceny i recenzje, programy systemowe (RPM)
- [ ] Asystent pod klawiszem.

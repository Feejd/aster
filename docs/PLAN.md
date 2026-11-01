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
- [x] Okna jak w profesjonalnych systemach: pasek boczny na lekko przezroczystym szkle, treść na głębokim,
      prawie nieprzezroczystym panelu (w ciemnym motywie niemal czerń; GlassPane), rogi 24 px, bez „zorzy”
- [x] Okna aplikacji webowych: pasek tytułu jako szkło w kolorze serwisu
- [ ] **Kolory i styl aplikacji Qt/KDE**: akcent, zaokrąglenia, czcionka Geist w całym systemie.
- [x] Start jak w macOS: ekran Plymouth ze znakiem Aster i paskiem postępu, bez tekstu jądra i systemd, ukryte menu GRUB,
      nazwa systemu „Aster 1.0”, od razu sesja Aster (`tools/install-vm.sh` w maszynie wirtualnej, `image/` w obrazie)
- [x] Ekran logowania Aster (motyw SDDM: rozmyta tapeta, zegar, karta użytkownika, inne osoby, zasilanie);
      SDDM zamiast Plasma Login Managera z Fedory 44 (ten nie przyjmuje własnych motywów)
- [x] Ekran blokady Aster (pakiet powłoki org.aster.shell dla kscreenlocker): wygląd ekranu logowania, PAM, Caps Lock, uśpienie
- [ ] Ikony i kursor w stylu Aster.
- [ ] Wygląd aplikacji GTK (Firefox, LibreOffice) dopasowany do reszty.

## Etap 3b — system bez programów Fedory/KDE (najpierw to, potem programy użytkowe)
Cel: po instalacji użytkownik widzi wyłącznie Aster. Program KDE usuwamy z obrazu dopiero wtedy, gdy jego zastępca działa.

Okna systemowe (używają ich wszystkie programy, więc najważniejsze):
- [ ] Okno „Otwórz / Zapisz jako” — własny portal xdg-desktop-portal (FileChooser) w stylu Plików
- [ ] Prośba o hasło administratora — własny agent polkit (zamiast polkit-kde-agent)
- [ ] Hasło Wi‑Fi/VPN i parowanie Bluetooth z powłoki; pęk kluczy (hasło po zalogowaniu) bez okien KWallet
- [ ] Ekran logowania i blokady, instalator i pierwsze uruchomienie, aktualizacje systemu (bootc) w Ustawieniach

Programy:
- [x] Pliki (Dolphin), Przeglądarka (Firefox), Terminal (Konsole), Sklep (Discover), Ustawienia (Ustawienia systemowe)
- [ ] Menedżer zadań (Plasma System Monitor) — Ctrl+Shift+Esc, „Zakończ zadanie”, obciążenie, programy przy starcie
- [ ] Zdjęcia (Gwenview) i Podgląd PDF (Okular)
- [ ] Edytor tekstu (Kate, KWrite), Wideo (Dragon/Haruna), Muzyka (Elisa), Kalkulator (KCalc)
- [ ] Spakuj / Wypakuj w Plikach (Ark); Dyski: formatowanie pendrive’a i zajęte miejsce (Partition Manager, Filelight)
- [ ] Panel emoji i znaków (Win+.), Kamera, Skaner, Telefon (KDE Connect z wyglądem Aster)

Usuwanie z obrazu (`image/Containerfile`, `dnf remove` po zbudowaniu zastępców):
- [ ] Programy: dolphin, konsole, kate, kwrite, okular, gwenview, elisa, dragon/haruna, kcalc, ark, discover,
      plasma-systemmonitor, kinfocenter, kwalletmanager, ksystemlog, kmail/kontact, akregator, gry KDE, plasma-welcome
- [ ] Zostaje infrastruktura bez okien: KWin, biblioteki Plasmy (powiadomienia, zadania), KIO, PowerDevil, PipeWire,
      NetworkManager, BlueZ, kded; KDE-owe okna systemowe znikają dopiero po zrobieniu własnych (portal, polkit)
- [ ] Ustawienia KDE (systemsettings) ukryte w Starcie, ale zostają dla zaawansowanych

## Etap 4 — prawdziwy system do zainstalowania
- [ ] Obraz systemu (`image/Containerfile`) budowany automatycznie przy każdej zmianie.
- [ ] Instalator z ekranem powitalnym („Przesiadasz się z Windowsa?”: przeniesienie plików, konto).
- [ ] Aktualizacje w tle z możliwością cofnięcia (atomowa Fedora), sklep aplikacji z Flathub.
- [ ] Test na prawdziwym laptopie (x86_64).

## Etap 5 — własne aplikacje
- [x] Ustawienia Aster (`apps/settings`): Wi‑Fi (lista sieci, hasło), Bluetooth (parowanie), dźwięk (wyjścia i wejścia),
      powiadomienia, ogólne (o tym komputerze), wygląd (jasny/ciemny, kolor akcentu), tapeta, pulpit i dok, ekran (nocne światło), konto;
      wspólna konfiguracja `~/.config/aster/aster.conf` (Config w Aster.Ui) zmienia się na żywo we wszystkich programach
- [x] Ustawienia kompletne, bez odsyłania do Ustawień KDE/Fedory: konto (zdjęcie, imię, hasło, inne osoby),
      sieć (szczegóły, DNS, VPN z pliku, hotspot, zapamiętane sieci), dźwięk programów i mikrofonu, powiadomienia
      każdego programu, ekran (układ monitorów, rozdzielczość, odświeżanie, skalowanie, obrót, jasność, harmonogram
      nocnego światła), zasilanie i bateria, pulpit i okna (narożniki, przyciąganie, animacje, pulpity), mysz i touchpad,
      klawiatura i skróty, drukarki, data i czas, język i region, aplikacje domyślne i autostart, dostępność,
      prywatność i bezpieczeństwo (blokada, zapora, historia plików), nazwa komputera
- [ ] Ustawienia: programy przypięte do doku, rozmiar tekstu w programach Aster, kopie zapasowe, aktualizacje systemu
- [x] Pliki — pierwsza wersja (KIO: kosz, kopiowanie, cofanie, wyszukiwanie, podgląd)
- [ ] Pliki: dyski USB i sieciowe, „Otwórz za pomocą”, właściwości, przeciąganie do innych aplikacji
- [x] Przeglądarka — pierwsza wersja (Qt WebEngine/Chromium: karty, ulubione, historia, pobieranie, uprawnienia, szukanie na stronie)
- [x] Przeglądarka 1.0: jedna kopia programu z wieloma oknami, okna prywatne, przywracanie kart (wczytywane dopiero po kliknięciu),
      blokowanie śledzenia, podpowiedzi wyszukiwarki i uzupełnianie adresu, strony Historia / Pobrane / Ustawienia,
      wybór wyszukiwarki, pasek ulubionych, powiększenie zapamiętane dla witryny, PDF, narzędzia dewelopera,
      okna stron i logowania w stylu Aster, ekran po awarii strony i przy błędzie certyfikatu, powiadomienia systemowe
- [x] Terminal (`apps/terminal`): libvterm na pseudoterminalu, karty na pasku okna, historia przewijania z wyszukiwaniem,
      zaznaczanie (słowo, linia), linki (Ctrl+klik), przeciąganie plików, schematy kolorów, czcionka i kursor,
      powiadomienie o końcu długiego polecenia, „Otwórz w Terminalu” w Plikach, domyślny terminal systemu
- [ ] Terminal: podział okna na panele, profile (SSH, inne powłoki), przywracanie kart po ponownym uruchomieniu
- [ ] Przeglądarka: import zakładek i haseł z Chrome/Edge/Firefox, menedżer haseł, synchronizacja, rozszerzenia
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

## Etap 6 — programy użytkowe Aster (po Etapie 3b)
- [ ] Aster Code — edytor kodu w stylu Aster
- [ ] Kolejne programy według potrzeb (notatki, poczta i kalendarz, biuro jako nakładki albo własne)

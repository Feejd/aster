# Plan prac

Kolejność: najpierw rzeczy, które użytkownik widzi i dotyka codziennie, potem wygląd całości,
na końcu obraz systemu i własne aplikacje. Każdy etap kończy się czymś, co działa w maszynie wirtualnej.

## Etap 1 — powłoka działa ✅ (prawie)
- [x] Tapeta dzień/noc, dok z prawdziwymi oknami, górna wyspa z datą
- [x] Rozmycie KWin pod wyspami, kliknięcia tylko w wyspy
- [x] Kilka monitorów: tapeta i górny pasek na każdym ekranie, dok, Start i powiadomienia na głównym

## Etap 2 — Start, centrum sterowania, powiadomienia
- [x] **Start** z prototypu (pierwsza wersja): wyszukiwanie aplikacji, plików i ustawień, przypięte, ostatnie pliki,
      blokada/wyłączanie. Dane z KDE (lista aplikacji, ostatnie dokumenty), uruchamianie przez KIO.
- [x] **Centrum sterowania** (prawa wyspa doku): Wi‑Fi/sieć (nmcli), Bluetooth (bluetoothctl), „Nie przeszkadzać”,
      ciemny motyw, jasność (PowerDevil), głośność (PipeWire), odtwarzacz (MPRIS), zrzut ekranu, ustawienia, bateria
- [x] Centrum sterowania: listy sieci Wi‑Fi (z hasłem) i urządzeń Bluetooth (kody parowania w panelu), wybór wyjścia i wejścia dźwięku; do sprawdzenia na prawdziwym Wi‑Fi i Bluetooth
- [x] Powiadomienia systemowe pod górną wyspą (powłoka jest serwerem powiadomień)
- [x] **Nowy układ powłoki**: górny pasek z trzech wysp (aktywny program z tytułem okna, dynamiczna wyspa, stan systemu),
      jeden dok z powiększaniem ikon, podskakiwaniem przy uruchamianiu i Koszem, widżety na pulpicie (kalendarz, bateria, teraz gra)
- [x] Dynamiczna wyspa: godzina, okładka i korektor przy muzyce, data po najechaniu, powiadomienie rozlewa wyspę w kartę
- [x] Dok chowa się, gdy okno na niego zachodzi, i wraca od dolnej krawędzi (do wyłączenia w Ustawieniach); lista okien programu po najechaniu i menu pod prawym przyciskiem
- [ ] Dok: miniatury okien (PipeWire), przypinanie programów z menu
- [x] Nowe okna na środku ekranu, kolejne schodkowo (`shell/kwinscripts/asteruklad`), Super+góra/dół jak w Windowsie
- [ ] Dynamiczna wyspa: postęp pobierania i kopiowania plików, nagrywanie ekranu, minutnik; panel „Dziś” po kliknięciu
- [ ] Menu aktywnego programu na lewej wyspie paska (globalne menu KDE)
- [x] Super = Start
- [x] Super+A = centrum sterowania

## Etap 3 — spójny wygląd całego systemu
- [x] **Ramki okien** (dekoracja KWin, `shell/decoration`): kolorowe przyciski i wygląd jak w programach Aster dla programów bez własnego paska.
- [x] **Efekty KWin** (`shell/effects/asterokna`): spójne otwieranie i zamykanie okien, zasysanie do doku (Magic Lamp), krótsze animacje; do sprawdzenia na prawdziwym GPU (VM renderuje programowo i KWin wyłącza tam animacje).
- [x] Okna aplikacji Aster: trójwarstwowy cień zależny od fokusu, szklany rant i odblask, „zorza” w kolorze akcentu,
      kolorowe przyciski okna, sprężyste otwieranie (wspólne WindowShadow / WindowSheen / WindowButtons w Aster.Ui)
- [x] Okna jak w profesjonalnych systemach: pasek boczny na lekko przezroczystym szkle, treść na głębokim,
      prawie nieprzezroczystym panelu (w ciemnym motywie niemal czerń; GlassPane), rogi 24 px, bez „zorzy”
- [x] Okna aplikacji webowych: pasek tytułu jako szkło w kolorze serwisu
- [x] **Kolory i czcionka programów Qt/KDE i GTK**: schematy Aster (`data/color-schemes`), Geist i JetBrains Mono w całym systemie; zaokrąglenia kontrolek wciąż z Breeze.
- [x] Start jak w macOS: ekran Plymouth ze znakiem Aster i paskiem postępu, bez tekstu jądra i systemd, ukryte menu GRUB,
      nazwa systemu „Aster 1.0”, od razu sesja Aster (`tools/install-vm.sh` w maszynie wirtualnej, `image/` w obrazie)
- [x] Ekran logowania Aster (motyw SDDM: rozmyta tapeta, zegar, karta użytkownika, inne osoby, zasilanie);
      SDDM zamiast Plasma Login Managera z Fedory 44 (ten nie przyjmuje własnych motywów)
- [x] Ekran blokady Aster (pakiet powłoki org.aster.shell dla kscreenlocker): wygląd ekranu logowania, PAM, Caps Lock, uśpienie
- [x] Kursor Aster (`tools/make-cursors.py`, budowany z CMake): grafit z białą obwódką i miękkim cieniem, kółko ładowania
      w akcencie Aster; 29 kształtów + wszystkie nazwy CSS/X11, SVG dla KWin (ostry w każdej skali) i Xcursor 24–96;
      domyślny w KDE, GTK i na ekranie logowania
- [ ] Ikony w stylu Aster.
- [ ] Wygląd aplikacji GTK (Firefox, LibreOffice) dopasowany do reszty.

## Etap 3b — system bez programów Fedory/KDE (najpierw to, potem programy użytkowe)
Cel: po instalacji użytkownik widzi wyłącznie Aster. Program KDE usuwamy z obrazu dopiero wtedy, gdy jego zastępca działa.

Okna systemowe (używają ich wszystkie programy, więc najważniejsze):
- [x] Okno „Otwórz / Zapisz jako” — portal xdg-desktop-portal Aster (`apps/portal`): miejsca, ścieżka, szukanie, miniatury,
      filtry, nowy folder, pytanie o nadpisanie; w sesji Aster także dla programów Qt/KDE i GTK
- [x] Prośba o hasło administratora — agent polkit w powłoce (okno Aster: kto prosi, o co, wybór administratora, ponowna próba)
- [ ] Hasło Wi‑Fi/VPN i parowanie Bluetooth z powłoki; pęk kluczy (hasło po zalogowaniu) bez okien KWallet
- [ ] Ekran logowania i blokady, instalator i pierwsze uruchomienie, aktualizacje systemu (bootc) w Ustawieniach

Programy:
- [x] Pliki (Dolphin), Przeglądarka (Firefox), Terminal (Konsole), Sklep (Discover), Ustawienia (Ustawienia systemowe)
- [x] Menedżer zadań — zakładka Porty (Aster Radar): kto nasłuchuje na którym porcie, program i PID, „Dostępny z” (wszystkie sieci / tylko ten komputer), wyszukiwanie po porcie, „Otwórz” w przeglądarce i „Zakończ” (`aster-tasks ports`)
- [x] Menedżer zadań (Plasma System Monitor) — `apps/tasks`: Ctrl+Shift+Esc, procesy pogrupowane po programach, „Zakończ zadanie”
      (cudze procesy przez polkit), właściwości, wydajność: procesor (też każdy rdzeń), pamięć, dyski, sieć; programy po zalogowaniu → Ustawienia
- [x] Zdjęcia (Gwenview) — `apps/photos`: biblioteka (Obrazy, Pobrane, Pulpit, zrzuty, dodane foldery), oglądanie z paskiem
      miniatur, powiększanie, informacje EXIF, obrót JPEG bez utraty jakości, kosz z „Cofnij”, pokaz slajdów, „Ustaw jako tapetę”
- [x] Podgląd PDF (Okular) — `apps/pdf`: strony na QtPdf, spis treści i miniatury, szukanie, zaznaczanie i kopiowanie tekstu, linki,
      powiększenie i obrót, hasło, właściwości, drukowanie, ostatnie dokumenty z zapamiętaną stroną
- [x] Edytor tekstu (Kate, KWrite) — `apps/editor`: karty, sesja z niezapisanymi kartami (jak Notatnik w Windows 11), szukaj/zamień,
      przejdź do wiersza, numery wierszy, kolorowanie KSyntaxHighlighting, Windows-1250 i CRLF, zmiany pliku na dysku
- [x] Kalkulator (KCalc) — `apps/calculator`: standardowy i naukowy, historia, kolejność działań, procenty jak w Windows,
      polski zapis liczb, long double (0,1 + 0,2 = 0,3), testy obliczeń (ASTER_TEST=1)
- [x] Wideo (Dragon/Haruna) — `apps/video`: ekran startowy z miniaturami i „Ostatnio oglądane” (wznawianie), odtwarzacz
      na całe okno z chowanym sterowaniem, napisy z pliku (SRT, VTT, MicroDVD, MPL2; UTF-8 i Windows-1250), ścieżki
      dźwięku, prędkość, następny film z folderu z odliczaniem, okno dopasowane do proporcji, brak wygaszania ekranu
- [x] Muzyka (Elisa) — `apps/music`: albumy, wykonawcy, utwory, kolejka; losowo, powtarzanie, skróty jak w Windows
      Media Player; okładki z tagów albo cover.jpg; kolejka przetrwa zamknięcie; MPRIS dla Centrum sterowania
- [ ] Kodeki H.264/HEVC/AAC w pełnym zakresie (ffmpeg z RPM Fusion — decyzja przy obrazie systemu)
- [x] Spakuj / Wypakuj w Plikach (Ark) — libarchive: ZIP/TAR przeglądane jak folder, „Wypakuj wszystko” (bez zbędnego
      zagnieżdżenia), 7z/RAR/ISO, „Kompresuj do pliku ZIP” i „Kompresuj…” (ZIP z hasłem AES-256, 7z, TAR), postęp z anulowaniem,
      polskie nazwy z ZIP-ów z Windows (CP852), ochrona przed „../” i dowiązaniami
- [x] Dyski (Partition Manager, Filelight) — pendrive’y i karty w pasku Plików (Solid): otwieranie, „Wysuń” (odmontowanie
      i wyłączenie zasilania), „Formatuj…” przez UDisks2 (exFAT/FAT32/NTFS/ext4, nazwa dysku); Ustawienia → Pamięć:
      kategorie jak „Magazyn” w Windows, największe foldery, czyszczenie plików tymczasowych i kosza, lista dysków
- [x] Panel emoji i znaków (Win+.) — `apps/emoji`: polskie nazwy i wyszukiwanie z CLDR (także bez ogonków), ostatnio
      używane, odcień skóry, kaomoji, symbole (waluty, matematyka, strzałki, litery); wklejanie do aktywnego programu
      (KWin fake-input, Ctrl+V) z przywróceniem schowka; wybierak KDE przeniesiony z Win+.
- [x] Kamera (Kamoso) — `apps/camera`, jak „Aparat” w Windows: obraz na całe okno, Zdjęcie/Film, samowyzwalacz 2/5/10 s,
      siatka, lustrzane odbicie, wybór kamery, nagrywanie z dźwiękiem (MP4, a bez koderów z RPM Fusion — WebM);
      zapis do Obrazy/Z aparatu i Wideo/Z aparatu, miniatura ostatniego ujęcia otwiera Zdjęcia lub Wideo
- [x] Skaner (Skanlite) — `apps/scanner`, przez SANE: skanery USB i sieciowe (sane-airscan), podgląd z kadrem do
      przeciągnięcia, szyba albo podajnik (wszystkie kartki naraz), kolor/szarości, rozdzielczość z podpowiedzią;
      strony do obrócenia i ułożenia, zapis jako jeden PDF (Dokumenty/Skany) albo JPG/PNG (Obrazy/Skany)
- [x] Grafika (nazwa robocza) — `apps/grafika`, szybkie grafiki dla zwykłych ludzi, bez internetu: ekran startowy
      z gotowymi rozmiarami (post, relacja, A4, plakat A3, slajd, miniaturka YouTube, okładka Facebook, własny),
      własne projekty z miniaturami i 16 szablonów (Instagram, relacje, plakaty, zaproszenia, CV, YouTube, slajdy, dyplom);
      edytor: tekst z czcionkami systemu (rozmiar, kolor, wyrównanie, odstępy, obrys, cień), kształty (prostokąt
      z zaokrągleniem, koło, trójkąt, gwiazda, serce, linia, strzałka), zdjęcia z dysku / przeciągnięte / wklejone,
      tło (kolor, przejście, zdjęcie); przeciąganie z przyciąganiem do środka i krawędzi, uchwyty, obrót, warstwy,
      cofnij/ponów, skróty; zapis sam (Dokumenty/Grafiki, `.grafika` = ZIP z JSON), eksport PNG/JPG (1×, 2×) i PDF
      (wektorowy, w formacie do druku); jedno rysowanie (QPainter) dla ekranu i eksportu
- [x] Aster Pixel: układ programu graficznego, warstwy z trybami mieszania, krycie, maski warstw (pędzel, wygaszanie,
      zaznaczenie AI), warstwy korekcyjne, krzywe, tony i kolor na zdjęciach
- [ ] Aster Pixel, kierunek Photoshop z prostszym interfejsem. Zasada: proste działa od razu (gotowe wyglądy, „Popraw
      automatycznie”, AI), a pełna kontrola czeka w zwijanych sekcjach i panelu warstw, nigdy na drodze. Kolejność:
  - [x] malowanie po pikselach: warstwa pikselowa, pędzel z twardością i kryciem, gumka, wypełnianie, pipeta
  - [x] retusz: Korektor AI, stempel, rozjaśnianie i ściemnianie, rozmazywanie, rozmywanie
  - [ ] pędzle: nacisk tabletu, kształty pędzla, malowanie w trybach mieszania
  - [x] prawdziwe zaznaczenia: prostokąt, elipsa, lasso, różdżka, kolor, główny obiekt i obiekt kliknięciem (AI), dodawanie,
        odejmowanie, część wspólna, wtapianie, powiększanie, przesuwanie; kopia i wycięcie na warstwę, wypełnianie,
        wypełnienie AI, maska z zaznaczenia; zaznaczenie obowiązuje przy malowaniu, retuszu i korekcjach
  - [ ] zaznaczenia, dalej: tryb podglądu maski, zapisywanie zaznaczeń, przekształcanie zaznaczonych pikseli, wielokąt
  - [x] przekształcenia: perspektywa i zniekształcenie czterema rogami (Ctrl+T), przycinanie strony do zaznaczenia
  - [ ] przekształcenia, dalej: siatka wypaczania, narzędzie kadrowania płótna, obrót i skala w jednym trybie
  - [ ] warstwy: foldery, maski przycinające, style warstw (obrys, poświata, faza), inteligentne filtry
  - [ ] filtry: wyostrzanie, rozmycie gaussowskie i ruchu, szum, histogram przy krzywej
  - [ ] pliki: import i eksport PSD, zapis WebP, TIFF, profile kolorów, 16 bitów
  - [x] AI po ludzku: karta Magia AI (wyodrębnij, usuń, zaznacz, rozmyj), kliknięcie w rzecz, pasek działań przy zaznaczeniu
  - [x] wypełnianie z opisu: stable-diffusion.cpp (`aster-pixel-gen`) z DreamShaper 8 Inpainting (GGUF, 1,9 GB). Przy częściowej
        masce oba sprawdzone modele ignorują opis, więc: obiekt powstaje na czystym tle i wycina go ISNet, duży obszar to cały kadr
        z opisu, a pusty opis to uzupełnienie z otoczenia (cfg 2)
  - [ ] wypełnianie z opisu, dalej: model w wydaniu „modele”, próba Vulkana na RX 6500 XT i czas na Acerze, tłumaczenie opisów
        przez Aster Intelligence (dziś słownik najczęstszych słów), dopasowanie światła obiektu do zdjęcia, opcja w chmurze
  - [ ] AI: powiększanie zdjęć
- [ ] Stare pomysły: usuwanie tła ze zdjęć bez internetu (rembg / U²-Net przez ONNX Runtime), paczki szablonów
      i grafik do pobrania ze Sklepu Aster, wiele stron w projekcie (karuzela, prezentacja), zaznaczanie kilku elementów
      i grupy, przycinanie zdjęć i filtry, przyciąganie przy zmianie rozmiaru, własne kolory marki, Flatpak w Sklepie Aster
- [x] Telefon (okna KDE Connect) — `apps/phone`, jak „Łącze z telefonem” w Windows, przez D-Bus z kdeconnectd:
      urządzenia z baterią i zasięgiem, parowanie z kodem do porównania, „Znajdź telefon”, wysyłanie plików (także
      przeciąganiem na okno) i schowka, pliki telefonu w Plikach (SFTP), powiadomienia z telefonu z zamykaniem
- [ ] Telefon, dalej: SMS-y i rozmowy, odpowiadanie na powiadomienia, sterowanie muzyką na telefonie

Usuwanie z obrazu (`image/debloat.sh`, wołany z `image/Containerfile`):
- [x] Programy zastąpione przez Aster: dolphin, konsole, kate, kwrite, okular, gwenview, elisa, dragon/haruna, kamoso,
      skanlite, kcalc, ark, filelight, partitionmanager, kcharselect, discover, plasma-systemmonitor, kinfocenter,
      kwalletmanager, ksystemlog, kmail/kontact/akregator i reszta PIM, Kleopatra, NeoChat, Qrca, Skanpage, KDebugSettings,
      khelpcenter, plasma-welcome, drkonqi, ABRT, Fedora Media Writer, LibreOffice, gry KDE
      — bez sprzątania „niepotrzebnych” zależności (dnf zabrałby flatpak, fwupd, sshfs); próba: `--dry-run`
- [x] Zostaje infrastruktura bez okien (sprawdzane po usunięciu — inaczej budowa obrazu się przerywa): KWin, Plasma,
      KIO z kio-extras, PowerDevil, PipeWire, NetworkManager, BlueZ, kdeconnectd (z pakietem kde-connect), flatpak, fwupd
- [x] Ustawienia KDE (systemsettings), edytor menu, okna KDE Connect, Klipper — ukryte w Starcie; Ustawienia KDE
      otwiera Ustawienia Aster → Ogólne → „Zaawansowane ustawienia (KDE)”; w maszynie wirtualnej install-vm.sh
      ukrywa zastąpione programy w Starcie (pakiety zostają, całkiem usuwa je `sudo sh image/debloat.sh`)
- [ ] Sprawdzić listę na prawdziwym obrazie Kinoite przy pierwszej budowie (Etap 4)

## Etap 4 — prawdziwy system do zainstalowania
- [ ] Obraz systemu (`image/Containerfile`) budowany automatycznie przy każdej zmianie.
- [x] Instalator Aster (`apps/installer`) — pendrive startuje od razu w instalatorze na cały ekran (KWin jako kiosk,
      bez trybu „wypróbuj”): język, klawiatura (działa od razu), Wi‑Fi, strefa czasowa, dysk (z ostrzeżeniem o Windows),
      konto, wygląd (jasny/ciemny, akcent, tapeta), aktualizacje automatyczne, podsumowanie; instalacja `bootc install
      to-disk` z obrazu na nośniku (bez internetu), postęp z podpowiedziami, potem ponowne uruchomienie prosto do pulpitu.
      Konto i wygląd zakłada `aster-firstboot` przy pierwszym starcie. ISO: `sudo tools/build-iso.sh [skąd aktualizacje]`
- [ ] Zbudować i przetestować ISO (Linux z ~30 GB miejsca albo GitHub Actions): rozruch, instalacja, pierwszy start
- [ ] Instalator, dalej: szyfrowanie dysku, instalacja obok Windows, „Przesiadasz się z Windowsa?” (przeniesienie plików)
- [x] Aktualizacje w tle bez samoczynnego restartu (`aster-update.timer`), powiadomienie i centrum sterowania, strona w Ustawieniach z powrotem do poprzedniej wersji; sklep aplikacji z Flathub.
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
- [ ] Aster Intelligence (dawniej Asystent Aster) — rozpisany niżej; gotowe A1 (usługa, `aster` w terminalu, Ustawienia),
      A2 (wyspa, panel), A2.5 (wygląd jak Apple Intelligence, narzędzia do pisania) i A3 (agent, który sam działa).

## Etap 6 — programy użytkowe Aster (po Etapie 3b)
- [x] Montaż (nazwa robocza, `apps/montaz`) — prosty edytor filmów na TikTok/Reels/YouTube i z wakacji, na MLT
      (silnik Kdenlive/Shotcut): nowy projekt 9:16 / 16:9 / 1:1 (albo od razu z upuszczonych plików — format z pierwszego
      filmu), import filmów, zdjęć i muzyki (przeciąganiem i z okna), oś czasu z ścieżkami wideo / tekst / muzyka,
      przycinanie krawędzi, dzielenie w miejscu głowicy (S), przesuwanie, usuwanie, przybliżanie, podgląd z dźwiękiem
      i klatka po klatce, 6 stylów napisów, przenikanie 0,5/1 s, głośność klipu i muzyki (wyciszanie na końcu),
      prędkość 0,25–3×, kadr „wypełnij”/„zmieść”, cofanie; projekty zapisują się same (JSON), zapis do MLT XML;
      eksport MP4 (H.264 przez x264 albo OpenH264 + AAC) w 720p/1080p, a bez kodera H.264 — WebM (VP9/Opus) z wyjaśnieniem
- [x] Montaż 2: filtry kolorów (Żywy, Ciepły, Chłodny, Pogodny, Kino, Retro, Czarno-biały — z miniaturami klipu)
      i korekta jasności, kontrastu, nasycenia; animacje napisów (pojawianie, wjazd od dołu i z boku, pisanie litera
      po literze); rozjaśnienie z czerni i ściemnienie na końcu filmu (obraz i dźwięk); kształt fali muzyki na osi;
      muzyka w tle przycinana przy dodaniu do długości filmu; test przeciągania myszą (krok drag: w ASTER_OPEN)
- [x] Montaż 3: napisy z mowy — whisper.cpp (pakiet whisper-cpp, offline, na procesorze), model „Szybki” (base,
      ok. 150 MB) albo „Dokładny” (small, ok. 490 MB) pobierany przy pierwszym użyciu do ~/.local/share/Aster/aster-montaz/models;
      polski, angielski albo wykrywanie języka; krótkie napisy (do ~34 znaków) w wybranym stylu, zwykłe i edytowalne,
      ponowne rozpoznanie zastępuje poprzednie; pomijanie ciszy i typowych „halucynacji” Whispera (np. Amara.org)
- [x] Montaż 4: 13 nowoczesnych przejść (przenikanie, przez czerń, błysk, rozmycie, przesunięcie, w górę, wsunięcie,
      smuga, przybliżenie, oddalenie, obrót, kurtyna, koło) z animowanymi podglądami, długością 0,3–1 s, „Zastosuj do
      wszystkich” i rombami przejść na osi; ruch kamery (najazd, odjazd, w lewo/prawo, puls, drgania); rozmyte tło
      (poziomy film w pionowym kadrze i odwrotnie); odbicie lustrzane; napisy przeciągane po podglądzie (przyciąganie
      do środka), wielkość i kolor liter; zmiana formatu projektu w każdej chwili
- [x] Montaż 5: druga ścieżka obrazu — nakładki (film albo zdjęcie/naklejka PNG z przezroczystością) nad głównym
      obrazem: obraz w obrazie, przeciąganie i zmiana wielkości na podglądzie, obrót, widoczność, kształt (prostokąt,
      zaokrąglony, koło), pojawianie się (pojawianie, wyskok, wjazd), usuwanie zielonego/niebieskiego tła z czułością,
      głośność; nachodzące na siebie nakładki w osobnych wierszach osi; dodawanie przyciskiem, przeciągnięciem
      z multimediów albo upuszczeniem pliku na ścieżkę nakładek
- [x] Montaż 6: napisy karaoke — czasy słów z whisper.cpp (tokeny sklejane w słowa) zapisane w napisie; tryby
      Karaoke (kolor wypowiadanego słowa), Ramka słowa, Słowo po słowie (jedno duże słowo), Narastanie; wybór w oknie
      „Napisy z mowy” i w animacjach każdego napisu (napisy pisane ręcznie dostają czasy proporcjonalne do długości słów)
- [x] Montaż 7: naklejki — 12 własnych wzorów Aster rysowanych w programie (Subskrybuj, Obserwuj, Polub, Link
      w opisie, Nowość, Część 1, strzałka, kółko, dymek, Wow, serce, iskry) i wszystkie emoji z polskim wyszukiwaniem
      (dane panelu emoji Aster, rysowane z Noto Color Emoji do PNG); karta „Naklejki” obok multimediów, klik dodaje
      naklejkę jako nakładkę w miejscu głowicy (z wyskokiem, przeciąganiem, obrotem)
- [x] Montaż 8: nagrywanie lektora — przycisk „Lektor”, pasek z poziomem mikrofonu, odliczanie 3‑2‑1, nagranie
      od miejsca głowicy przy odtwarzanym (wyciszonym) filmie, zapis WAV (QAudioSource) do nagrań projektu, nagranie
      na ścieżce dźwięku jako „Lektor N”; automatyczne przyciszanie muzyki i dźwięku filmu pod lektorem (−14 dB,
      można wyłączyć); muzyka i lektor nachodzące na siebie w osobnych wierszach osi
- [x] Montaż 9: odszumianie głosu — dla klipu z dźwiękiem, muzyki i lektora: „Lekkie” (RNNoise, 90%) albo „Mocne”
      (RNNoise 100% i bramka — cisza między słowami) oraz „Wyraźny głos” (bez dudnienia, pasmo 3 kHz, kompresor);
      nagranie lektora od razu lekko odszumione i wyraźne; afftdn z ffmpeg w MLT nie działa (zmienia liczbę próbek)
- [ ] Montaż, dalej: efekty głosu, naklejki animowane (GIF/WebP, Lottie),
      własne naklejki użytkownika z wycinaniem tła,
      klatki kluczowe położenia i skali, cofanie klipu i stop-klatka,
      płynna zmiana prędkości, cięcia do rytmu muzyki, wyciszanie początku/końca klipu, obrót o 90°, szablony,
      fala dźwięku także w klipach wideo, kilka ścieżek wideo (obraz w obrazie), wyciszanie muzyki pod mową, zatrzymanie klatki,
      szablony, nagrywanie lektora, eksport w 60 kl./s i 4K; docelowo rozdawany jako Flatpak przez Sklep Aster
- [ ] Montaż: ostateczna nazwa programu (propozycje: Klaps, Kadr, Ujęcie) i kodeki H.264 na systemach bez OpenH264
- [ ] Aster Code — edytor kodu w stylu Aster
- [x] Aster Vault (`apps/dev/vault`, `aster-vault`, Start → Narzędzia developera) — bazy danych dla programistów:
  - [x] SQLite (plik: otwórz / nowa baza), PostgreSQL i MySQL/MariaDB przez Qt SQL (QSQLITE/QPSQL/QMYSQL — w obrazie
        `qt6-qtbase-postgresql`, `qt6-qtbase-mysql`); zapisane połączenia w `~/.config/aster-vault/connections.json`
        (bez haseł), hasła w portfelu przez Secret Service (KWallet/gnome-keyring) albo pytanie przy połączeniu;
        „Sprawdź” w formularzu, tryb tylko do odczytu (blokada w bazie: plik SQLite do odczytu, transakcje READ ONLY)
  - [x] pasek boczny: tabele i widoki (schematy PostgreSQL w grupach), szukanie, przełączanie baz na serwerze
  - [x] Dane: siatka (wątek roboczy, strony po 200 wierszy, stały porządek po kluczu), filtr WHERE, sortowanie
        nagłówkiem, edycja w miejscu / w oknie wiersza (długie i wielowierszowe wartości, NULL), dodawanie i usuwanie;
        zmiany czekają na podgląd poleceń SQL i zapis w jednej transakcji (błąd → nic nie zapisane); klucz główny,
        w SQLite bez niego — ukryty rowid; widoki i tabele bez klucza tylko do odczytu (z wyjaśnieniem)
  - [x] Struktura: kolumny (typ, NULL, domyślna wartość, klucz), indeksy, klucze obce (klik — tabela docelowa), definicja
  - [x] SQL: edytor z kolorowaniem (własne, bez KSyntaxHighlighting), podpowiedzi tabel/kolumn (także po skrótach
        „k.” z FROM/JOIN), Ctrl+Enter — polecenie pod kursorem, Ctrl+Shift+Enter — całość, pytanie przed DROP/TRUNCATE
        i UPDATE/DELETE bez WHERE, wynik (do 2000 wierszy w siatce), historia (`~/.local/share/aster-vault/history.json`)
  - [x] eksport tabeli (z filtrem) i wyniku do CSV/JSON — strumieniowo, wszystkie wiersze
  - [x] dla asystenta i terminala, tylko odczyt: `aster-vault --list | --schema POŁ [TABELA] | --query POŁ "SQL"
        [--limit N] [--json]` i usługa D-Bus `org.aster.Vault` (/org/aster/Vault: Connections, Schema, Query —
        JSON w napisie; uruchamiana na żądanie, koniec po 5 min); filtr poleceń + blokada READ ONLY w bazie,
        limit 30 s, zgoda per połączenie („Dostęp dla asystenta i terminala”); działa bez usługi asystenta
  - [x] Flatpak `apps/dev/vault/flatpak/org.aster.vault.yml` (libpq, mariadb-connector-c i wtyczki qsqlpsql/qsqlmysql
        z qtbase 6.11 — runtime KDE ma tylko SQLite); w workflow i `tools/install-apps.sh` jako `vault`
  - [x] Sprawdzone w kontenerze: przykładowa baza SQLite, PostgreSQL 18 (hasło SCRAM, schematy, numeric, jsonb, tablice),
        MariaDB; portfel gnome-keyring (zapis z okna → odczyt z CLI i D-Bus); zrzuty w jasnym i ciemnym motywie
  - [ ] Dalej: kilka kart zapytań, EXPLAIN jako drzewo, edytor JSON/jsonb, tunel SSH, import CSV, diagram relacji,
        przerywanie długiego zapytania; budowa Flatpaka sprawdzona tylko częściowo (wtyczki sqldrivers z qtbase
        zbudowane samodzielnie w kontenerze) — pierwsze przejście w GitHub Actions do obejrzenia; dwuklik pliku .db
        (MimeType) i ikona motywu `server-database` do sprawdzenia w VM
- [x] Studio (nazwa robocza) — `apps/studio`, proste studio nagrań dla amatorów (nagrać wokal i gitarę, ułożyć pętle,
      zmiksować piosenkę); pierwsza wersja w drzewie, docelowo Flatpak w Sklepie Aster:
  - [x] projekt = folder w Muzyka/Studio: `projekt.json` (tempo, metrum, ścieżki, klipy w ramkach 48 kHz) + `audio/`
        (nagrania i kopie importowanych plików) + `Eksport/`; ostatnie projekty na ekranie startowym, zapis przy zamknięciu
  - [x] tempo (z „Wystukaj”), metrum, metronom (akcent na raz), odliczanie taktu przed nagraniem
  - [x] nagrywanie na zaznaczoną ścieżkę (jedna gotowa naraz, kanał wejścia: oba/lewy/prawy), kształt fali na żywo,
        kompensacja opóźnień wejścia i wyjścia z PipeWire + ręczna korekta; nagranie zapisuje się od razu (WAV 24 bity)
  - [x] oś czasu z siatką taktów: przesuwanie klipów (także między ścieżkami), przycinanie, dzielenie, pętla
        (wydłużanie prawym brzegiem, faza pętli zachowana przy przycinaniu i dzieleniu), duplikowanie, przyciąganie
        do taktu/miary/ósemki/szesnastki (Shift — bez), powiększanie, cofanie i ponawianie
  - [x] import WAV/FLAC/OGG/Opus/MP3 przeciąganiem lub z okna (libsndfile; przepróbkowanie libsamplerate)
  - [x] mikser: głośność (−∞…+6 dB), panorama, wycisz/solo, wskaźniki poziomu, suma z ochroną przed przesterowaniem
  - [x] wybór wyjścia i wejścia dźwięku (urządzenia z PipeWire), poziom wejścia
  - [x] eksport miksu (ten sam kod co odsłuch) do MP3, WAV 16 bit, OGG Vorbis, FLAC
  - [ ] Nazwa programu (propozycje: „Próba”, „Scena”, „Nuta”)
  - [x] efekty na ścieżkach (`src/dsp.h`, bez alokacji w wątku audio): korektor 3-pasmowy + usuwanie dudnienia
        (80 Hz), kompresor jednym suwakiem, wspólny pogłos z wielkością sali; gotowe brzmienia (Wokal, Gitara, Bas,
        Perkusja, Radio, Daleko); panel z prawej (E) z brzmieniem ścieżki i ustawieniami klipu
  - [x] głośność klipu, narastanie i wyciszanie (uchwyty na klipie i suwaki w panelu)
  - [x] region pętli odtwarzania do ćwiczenia (C, przeciąganie po linijce, „Ćwicz w pętli” z menu klipu) —
        zawijanie w środku bloku audio, sprawdzone przez PipeWire w kontenerze
  - [x] nowe nagranie zastępuje to, co było pod nim na ścieżce (stare klipy przycięte/podzielone, Ctrl+Z przywraca)
  - [x] Kierunek „zrób kawałek, który brzmi”: Beat Maker (`src/beatsynth.*`) — perkusja i bas 808 syntezowane
        w programie (bez sampli, nic obcego), zestawy Trap / Drill / Boom bap / Lo-fi / House / Pop, siatka szesnastek
        z malowaniem, rolki hi-hatów ×2–×4, ciche uderzenia, swing, 1/2/4 takty; 808 z mini-pianinem w skali molowej,
        tonacją i ślizgiem; wzór → pętla audio w `audio/_bit-N.wav` (gra z mikserem, efektami, eksportem; zmiana tempa
        przelicza pętle)
  - [x] szablony gatunków przy nowym projekcie i na ekranie startowym: bit, 808, dwie ścieżki wokalu z łańcuchem
        efektów, mastering gatunku — wystarczy nagrać głos (podkład Trap: −8,6 dBFS RMS, szczyt −0,2 dBFS)
  - [x] efekty jak w trapie: echo zgrane z tempem (1/4, 1/8, 1/8 z kropką, ping-pong), ciepło/przester;
        presety w grupach (Wokal pop, Wokal trap, Rap, Chórki; Gitara, Bas, Perkusja, 808; Radio, Lo-fi, Daleko)
  - [x] mastering sumy: korektor, kompresor „sklejający”, szerokość stereo, dociśnięcie do ogranicznika z wyprzedzeniem;
        presety Trap / hip-hop, Pop, Ciepły, Głośny, Lo-fi
  - [x] autotune (`src/tune.h`): wykrywanie wysokości YIN (sygnał zmniejszony do 12 kHz, co ~5 ms, 70–1000 Hz),
        dociąganie do najbliższej nuty tonacji projektu (moll/dur, „Jak w 808”), szybkość od naturalnej do „efektu
        trap”, przesuwanie wysokości linią opóźniającą z dwoma odczytami co okres głosu; w presetach Wokal trap (90%),
        Wokal pop, Chórki. Test: A4 −40 c → ±3 c, 302 Hz → D4, ześlizg przyciągnięty do nut a-moll; na żywo nadąża
  - [ ] Dalej: autotune dokładniejszy przy dużych przesunięciach (PSOLA z zachowaniem formantów), wybór nut ręcznie
        (edytor wysokości jak w programach do korekcji), de-esser, bramka szumów, wtyczki LV2 (lilv)
  - [x] ścieżka Akordy: brzmienia Pianino, Klawisze elektryczne (FM), Pad (rozstrojone piły), Pluck (Karplus–Strong),
        Dzwonki (FM), Lead; rytmy (cały takt, półnuty, staccato, arpeggio ósemki/szesnastki), oktawa, septymy; progresje
        (Smutna, Mroczna, Epicka, Rozmarzona, Z nadzieją, Dwa akordy) i akord na każdy takt z nazwami w tonacji projektu
        (np. fis-moll → D-dur → A-dur → E-dur); prowadzenie głosów (najbliższy przewrót); zmiana tonacji przelicza akordy;
        szablony gatunków mają gotową ścieżkę akordów; nieużywane pętle „_…” sprzątane przy zamknięciu projektu
  - [x] piano roll (ścieżka Melodia): klawiatura C2–C7, siatka szesnastek na 1–8 taktów, klik dodaje nutę (długość
        1/16…cała), przeciąganie przesuwa, prawy brzeg zmienia długość, prawy klik / dwuklik usuwa; wiersze tonacji
        podświetlone, „Tylko nuty skali”; te same brzmienia co Akordy; „Zamień na nuty” przenosi akordy do piano rolla
        bez zmiany brzmienia (eksport identyczny)
  - [x] odsłuch: klik w piano rollu, na klawiaturze ekranowej, w Beat Makerze (krok i nazwa wiersza) i w nutach 808
        od razu gra dźwięk — 8 głosów odsłuchu w wątku audio, także przy zatrzymanym transporcie
  - [x] klawiatura komputera jak pianino w piano rollu (A S D F G H J K / W E T Y U O, Z/X — oktawa), wciśnięte
        klawisze podświetlone; „Nagrywaj nuty” — granie w trakcie odtwarzania zapisuje nuty wyrównane do szesnastek
  - [x] klawiatury MIDI na USB (`src/midiinput.*`, sekwencer ALSA — przez niego PipeWire pokazuje urządzenia MIDI):
        samo podłącza się do każdej klawiatury, także wpiętej w trakcie pracy; nuty z siłą uderzenia do odsłuchu
        i nagrywania w piano rollu (bez otwartego piano rolla — odsłuch na ścieżce Melodia/Akordy); lista klawiatur
        w ustawieniach dźwięku; bez sekwencera po cichu nic nie robi. W kontenerze nie ma /dev/snd/seq — prawdziwą
        klawiaturę sprawdzić w maszynie wirtualnej (przekazanie USB)
  - [x] granie na żywo: 16 głosów syntezatora w wątku audio (`src/synthvoice.h` — ten sam głos liczy też nuty
        ścieżek), polecenia przez kolejkę bez blokad; nuta brzmi, dopóki klawisz (komputer, MIDI, klawiatura ekranowa)
        jest wciśnięty, potem wybrzmiewa jak instrument; przy braku wolnego głosu zabierany najstarszy
  - [x] granie na żywo przez efekty ścieżki: głosy przypisane do ścieżki wchodzą do miksera przed jej łańcuchem
        (autotune, korektor, przester, kompresor, głośność, panorama, pogłos, echo, mastering); mikser pracuje też przy
        zatrzymanym transporcie (bez klipów), więc słychać ogony pogłosu i echa; wycisz/solo obowiązują
  - [ ] Dalej: pedał sustain, pokrętła klawiatury do suwaków, kopiowanie taktów, biblioteka pętli,
        przełącznik A/B masteringu
  - [x] udostępnianie bez serwera (`src/share.*`): arkusz „Udostępnij” z okładką generowaną z kształtu fali piosenki,
        tytułu i wykonawcy; piosenka jako MP3 z tagami i okładką (TagLib) w <projekt>/Udostępnione; projekt do remiksu
        jako paczka ZIP (libarchive, tylko używane pliki); wysyłka na sparowany telefon (KDE Connect), e-mailem
        (xdg-email z załącznikiem), schowek (wklejenie w komunikatorze/Plikach), „Pokaż w folderze”; otwarcie paczki
        od znajomego (ekran startowy) tworzy nowy projekt „(remiks)” — bez nadpisywania
  - [ ] Dalej (społecznościowo, jak BandLab): link do odsłuchu i wspólna praca na żywo — wymaga serwera Aster;
        wideo z okładką i falą do social mediów (ffmpeg); typ pliku paczki w systemie (dwuklik otwiera Studio)
  - [ ] Dalej: instrumenty MIDI (klawiatura na ekranie i z USB, pianino, perkusja, syntezator — np. FluidSynth z SoundFontem
        na wolnej licencji), ścieżki MIDI z edytorem nut
  - [ ] Dalej: biblioteka pętli i sampli na wolnych licencjach (CC0 / CC-BY, np. własne nagrania), dopasowanie pętli
        do tempa projektu (rubberband — jest w Fedorze), podgląd pętli przed wstawieniem
  - [ ] Dalej: odsłuch wejścia (z ostrzeżeniem o sprzężeniu), nagrywanie w pętli z wieloma podejściami (comping),
        automatyka głośności
  - [ ] Dalej: kilka ścieżek nagrywanych naraz z interfejsu wielokanałowego, zmiana tempa w trakcie piosenki,
        stroik do gitary, eksport pojedynczych ścieżek, udostępnianie (wysłanie e-mailem/do telefonu)
  - [ ] Sprawdzić w maszynie wirtualnej i na laptopie: nagrywanie z prawdziwego mikrofonu i interfejsu USB,
        przełączanie urządzeń w trakcie, zachowanie przy niedoborach bufora (xrun)

- [x] Aster Pulse — `apps/dev/pulse`, testowanie API (jak Postman) dla programistów, Start → Narzędzia developera
      (`Categories=Development`), Flatpak `org.aster.pulse`:
  - [x] zapytania GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS: parametry (zsynchronizowane z adresem), nagłówki,
        treść JSON (kolory, formatowanie, błąd z numerem wiersza), tekst, formularz, pola z plikami (multipart),
        plik; autoryzacja Bearer i Basic; pomijanie sprawdzania certyfikatu dla serwerów testowych
  - [x] odpowiedź: kod, czas, rozmiar; drzewo JSON ze zwijaniem, podglądem zwiniętych węzłów i wyszukiwaniem
        (trafienia + droga do nich), kopiowanie wartości i ścieżki `$.a[0].b`; surowa treść, nagłówki wysłane
        i odebrane, obrazki, zapis do pliku
  - [x] obszar roboczy = folder z plikami JSON (`<projekt>/pulse/` — do repozytorium, albo `~/Dokumenty/Pulse`):
        `pulse.json` (środowiska ze zmiennymi `{{baseUrl}}`, wybrane środowisko) + `<kolekcja>.json`; tajne
        zmienne w portfelu (Secret Service: KWallet/GNOME Keyring), w pliku zostaje sama nazwa; odświeżanie po
        zmianie plików z zewnątrz (git pull, agent)
  - [x] historia (`~/.local/share/aster-pulse/history.json`, 300 ostatnich, także z terminala i od agenta),
        import cURL (wklejenie do paska adresu albo Ctrl+I; Bearer → Autoryzacja, ?a=1 → Parametry) i eksport do
        cURL (tajne zostają jako `{{nazwa}}`)
  - [x] dla agenta asystenta: `aster-pulse run kolekcja/zapytanie --env lokalne` (oraz `send`, `list`, `curl`,
        `import`) zwraca wynik jako JSON, kod wyjścia 0/2/1; usługa D-Bus `org.aster.pulse` `/org/aster/Pulse`,
        interfejs `org.aster.Pulse` (Run, RunWith, Send, List, Curl, ImportCurl) — wystawia ją okno albo
        `aster-pulse --dbus` uruchamiane na żądanie; działa bez usługi asystenta
  - [x] sprawdzone w kontenerze z `tools/pulse-test-server.py` (JSON, 401/Bearer, Basic, multipart, przekierowanie,
        204, obrazek, 5000 elementów, przekroczony czas) i atrapą portfela; zrzuty jasne i ciemne
  - [ ] Dalej: karty z kilkoma otwartymi zapytaniami, skrypty/asercje po odpowiedzi (np. „status = 200”,
        zapis tokenu z odpowiedzi do zmiennej), uruchamianie całej kolekcji, import kolekcji Postmana/OpenAPI,
        ciasteczka, WebSocket i GraphQL; narzędzie asystenta wołające org.aster.Pulse (po scaleniu gałęzi asystenta)
  - [ ] Sprawdzić na prawdziwym KWin: okna wyboru plików (portal), odblokowanie KWallet przy pierwszej tajnej zmiennej

### Studio — wybór silnika dźwięku
Wybór: **bezpośrednio PipeWire** (`pw_stream`, wątek czasu rzeczywistego PipeWire) + **libsndfile** (odczyt i zapis
WAV/FLAC/OGG/Opus/MP3) + **libsamplerate** (przepróbkowanie importu do 48 kHz). Wszystko w repozytoriach Fedory 44
(`pipewire-devel`, `libsndfile-devel`, `libsamplerate-devel`), małe, na licencjach MIT/LGPL/BSD.

Dlaczego nie gotowy silnik: Tracktion Engine stoi na JUCE (GPLv3 albo licencja komercyjna, JUCE nie ma w Fedorze),
dokłada kilkaset tysięcy wierszy C++ i własny model projektu — za dużo jak na pierwsze proste studio. Własny silnik
wystarczy do ścieżek audio, a efekty dołożymy przez LV2 (lilv, też w Fedorze). Rubberband (GPL, w Fedorze) wejdzie
przy dopasowaniu pętli do tempa. JACK API niepotrzebne — PipeWire i tak je emuluje, a natywny `pw_stream` daje wybór
urządzenia (`target.object`) i opóźnienia (`pw_stream_get_time_n`).

Zasady w kodzie (`apps/studio/src/engine.*`):
- dźwięk w wątku czasu rzeczywistego PipeWire (`PW_STREAM_FLAG_RT_PROCESS`), bez blokad i bez alokacji;
- stan miksu to niezmienna migawka (`Snapshot`) budowana w wątku interfejsu i podawana przez wymianę wskaźnika
  atomowego; starą migawkę wątek audio oddaje przez kolejkę i zwalnia ją wątek interfejsu;
- nagranie: wątek audio wkłada próbki do bufora pierścieniowego (jeden pisze, jeden czyta), osobny wątek zapisuje WAV;
- odtwarzanie i eksport używają tego samego miksera (`Renderer`), więc eksport brzmi jak odsłuch;
- test w kontenerze (wirtualne głośniki i pętla zwrotna z wyjścia do wejścia): nagrany metronom wypada 5 ms
  (jeden kwant pętli zwrotnej) po mierze.
- [x] Aster Code — edytor kodu w stylu Aster (pierwsza wersja): okno startowe z ostatnimi folderami, `aster-code ŚCIEŻKA`, drzewo plików (nowy plik/folder, zmiana nazwy, kosz, ikony typów, stan gita), karty z podglądem i kropką niezapisanych zmian, kolorowanie składni (KSyntaxHighlighting), numery wierszy, bieżący wiersz, dopasowanie nawiasów, Tab/Shift+Tab, Ctrl+/, Alt+↑/↓, Shift+Alt+↑/↓, paleta (Ctrl+P pliki, Ctrl+Shift+P polecenia, Ctrl+G wiersz), szukanie w pliku (Ctrl+F/H) i w projekcie (Ctrl+Shift+F), terminal na dole (Ctrl+`), git w tle (gałąź, zmienione pliki, zmiany przy marginesie), pasek stanu, karty projektu wracają przy ponownym otwarciu
- [x] Aster Code: serwery języków (LSP) — podpowiedzi przy pisaniu i Ctrl+Spacja, przejdź do definicji (F12, Ctrl+klik), opis po najechaniu, błędy i ostrzeżenia (podkreślenie, kropka przy wierszu, panel Problemy Ctrl+Shift+M, liczniki na pasku stanu); clangd, qmlls, pylsp/pyright, typescript-language-server, rust-analyzer, gopls, bash-language-server — brakujący serwer: polecenie instalacji na pasku stanu; menu edytora pod prawym przyciskiem; domykanie nawiasów i cudzysłowów
- [x] Aster Code: zmiana nazwy symbolu w całym projekcie (F2; zmiany w kartach do przejrzenia, jeden krok cofania na plik), odwołania (Shift+F12, panel Odwołania z wyróżnioną nazwą), formatowanie dokumentu (Shift+Alt+F)
- [x] Aster Code: szybkie poprawki (Ctrl+., żarówka przy wierszu z problemem; zmiany i polecenia serwera, workspace/applyEdit), symbole pliku (Ctrl+Shift+O, „@” w palecie, z zagnieżdżeniem) i projektu (Ctrl+T, „#”), podpowiedź parametrów po „(” i „,” (gdy serwer ją ma — qmlls nie)
- [ ] Aster Code: LSP dalej — formatowanie przy zapisie, podświetlanie semantyczne, wskazówki w tekście (inlay hints), clangd domyślnie w obrazie
- [x] Aster Code: git w widoku zmian — pliki dodane do zatwierdzenia i pozostałe (+ dodaj, − wycofaj, ↶ odrzuć z potwierdzeniem, nowe pliki do Kosza), opis i „Zatwierdź” (Ctrl+Enter; bez dodanych — wszystkie zmiany), poprawienie ostatniego zatwierdzenia, wysyłanie/pobieranie/synchronizacja (pierwsza gałąź — „Opublikuj”), zrozumiałe komunikaty błędów (logowanie, brak serwera, rozbieżne zmiany), podgląd różnic pliku, ostatnie zatwierdzenia
- [x] Aster Code: gałęzie (wybór z paska stanu i widoku zmian: przełącz — także zdalną, nowa z wpisanej nazwy, połącz z bieżącą, usuń), odkładanie i przywracanie zmian (stash), pojedyncze fragmenty w podglądzie różnic (dodaj, wycofaj, odrzuć z potwierdzeniem)
- [x] Aster Code: konflikty łączenia — bloki w edytorze (moja wersja zielona, przychodząca niebieska) z przyciskami „Zostaw moją / Weź przychodzącą / Obie”, sekcja Konflikty i baner łączenia w widoku zmian (opis z MERGE_MSG, „Przerwij łączenie”, blokada zatwierdzenia z nierozwiązanymi konfliktami); autor wiersza przy kursorze (git blame z treścią edytora, także niezapisaną; włączany w menu)
- [x] Aster Code: historia pliku w pasku bocznym (git log --follow, +/− na wpis): zmiany pliku w zatwierdzeniu, „Przywróć tę wersję” do edytora (bez zapisu), lista plików zatwierdzenia (także z ostatnich zatwierdzeń w widoku zmian), kopiowanie skrótu; z menu karty, drzewa i palety
- [x] Aster Code: historia lokalna — każdy zapis pliku (także bez gita, do 100 wersji, bez plików z sekretami) na osi czasu razem z zatwierdzeniami, porównanie i „Przywróć tę wersję”; git bez poleceń: „Włącz wersje”, podpis autora w dwóch polach przy pierwszym zatwierdzeniu, „Opublikuj” bez zdalnego repozytorium prowadzi do logowania GitHub; terminal: „Brakuje programu X” z przyciskiem Zainstaluj; karta powitalna przy pierwszym uruchomieniu
- [ ] Aster Code: git dalej — porównanie dwóch dowolnych wersji, zatwierdzenia łączące w historii pliku, logowanie do GitHuba bez terminala
- [x] Aster Code: wiele kursorów — Ctrl+D (następne wystąpienie), Ctrl+Shift+L (wszystkie), Alt+klik, Ctrl+Alt+↑/↓; pisanie, kasowanie, strzałki, Home/End, Enter, Tab i nawiasy przy wszystkich naraz (jeden krok cofania); kopiowanie i wklejanie po jednym wierszu na kursor; licznik kursorów na pasku stanu; domykanie nawiasów
- [x] Aster Code: zamiana w całym projekcie — pole „Zamień na” w szukaniu (grupy $1 przy wyrażeniach), podgląd w wynikach, zamiana wszystkiego (z potwierdzeniem), w pliku i pojedynczego trafienia; otwarte karty zmieniane w edytorze (do cofnięcia), pozostałe pliki na dysku z zachowaniem kodowania; szukanie widzi treść niezapisanych kart
- [x] Aster Code: zwijanie bloków (z wcięć, klamra w osobnym wierszu — nagłówkiem wiersz nad nią): strzałki w marginesie, „⋯” za zwiniętym wierszem, Ctrl+Shift+[ / ], Ctrl+K Ctrl+0 / Ctrl+K Ctrl+J, rozwijanie przy wejściu kursorem; minimapa w kolorach składni z widoczną częścią, błędami i trafieniami szukania (klik i przeciąganie przewijają)
- [x] Aster Code: podział edytora na dwie grupy kart (Ctrl+\\, Ctrl+1/Ctrl+2, „Podziel w prawo” i „Przenieś do drugiej grupy” w menu karty): osobne paski kart i ścieżki, ten sam plik w obu grupach zsynchronizowany na bieżąco (TextOps.link), wspólny zapis i serwer języka
- [x] Aster Code: ustawienia (Ctrl+,, menu, paleta) z szukaniem: rozmiar i czcionka, zawijanie, minimapa, domykanie nawiasów, podpowiedzi przy pisaniu, wcięcie nowych plików; samozapis (po chwili / przy zmianie okna), formatowanie, usuwanie spacji i końcowy wiersz przy zapisie; autor wiersza, sprawdzanie serwera gita co 5 minut; serwery języków (włącz/wyłącz, stan każdego, polecenie instalacji do schowka)
- [x] Aster Code: zadania (Ctrl+Shift+B, paleta „Uruchom zadanie…”) wykrywane z package.json (npm/pnpm/yarn/bun), Makefile, CMake, meson, Cargo, go.mod, justfile i Pythona, własne polecenia zapamiętywane na projekt; karta „Zadanie” z wyjściem (zatrzymaj, powtórz, klikalne plik:wiersz:kolumna), błędy gcc/clang, tsc, rustc, go i Pythona w panelu Problemy, w edytorze i na pasku stanu
- [x] Aster Code: debugowanie przez DAP (gdb -i dap, lldb-dap, debugpy): punkty przerwania (F9, klik obok numeru), F5 — start (program zapamiętany na projekt albo najnowszy plik ELF; .py — bieżący plik) i dalej, F10/F11/Shift+F11 kroki, F6 wstrzymaj, Shift+F5 stop; pasek sterowania nad edytorem, strzałka i podświetlenie wiersza zatrzymania, panel Debugowanie: stos (wybór ramki), zmienne rozwijane, konsola z wyjściem programu i wyrażeniami (:polecenie — dla debugera)
- [x] Aster Code: ▶ Uruchom (Ctrl+F5) — serwery deweloperskie ze wszystkich projektów w folderze (frontend/, backend/…; npm/pnpm/yarn, FastAPI/uvicorn, Flask, Django, make run, cargo run, go run, skrypty z pyproject) naraz, każdy z własnymi logami w karcie Zadania; adres serwera z wyjścia, sprawdzony połączeniem — sam otwiera podgląd (frontend przed API)
- [x] Aster Code: podgląd strony obok edytora (QtWebEngine): przeładowanie po zapisie, konsola przeglądarki (console.log/warn/error, błędy wczytania), telefon (390 px, przeglądarka telefonu) / komputer, wstecz/dalej, otwórz w przeglądarce
- [x] Aster Code: kontener projektu (toolbox, a bez niego distrobox) zakładany z paska stanu albo palety, z pakietami Fedory dobranymi do projektu (package.json → nodejs, pyproject → python3-pip, CMake → gcc-c++ …); zadania, terminal (toolbox enter), serwery języków i debuger działają w nim, w systemie nic nie przybywa; z Flatpaka polecenia idą przez flatpak-spawn --host (niesprawdzone na prawdziwym toolboxie — test z udawanym)
- [x] Aster Code: sekrety projektu w portfelu systemu (Secret Service: KWallet/ksecretd, gnome-keyring) — jeden wpis na projekt, ekran Sekrety (pokaż, kopiuj, usuń, dodaj), przeniesienie .env do portfela (w pliku zostają nazwy), wstrzykiwanie do zadań (plik 0600 w /run/user kasowany przez powłokę, działa też w kontenerze i z Flatpaka) i debugera; redact() i wykluczenie plików .env — dla agenta
- [x] Aster Code: „Nowa aplikacja” (ekran startowy, menu, paleta) — frontend Vite + React (Vitest), backend FastAPI (pytest) albo Node/Express (node:test), baza SQLite albo PostgreSQL (zadanie „baza danych” w kontenerze), proxy /api, .env.example, README, .gitignore, pierwsze zatwierdzenie; potem kontener z pakietami i instalacja zależności jako zadania; własne zadania z .aster/zadania.json (sprawdzone: testy obu backendów i frontendu, ▶ Uruchom z podglądem)
- [x] Aster Code: panel agenta (Ctrl+Shift+I, Aster Intelligence przez usługę aster-assistant): kontekst do włączenia (otwarty plik, zaznaczenie, problemy z serwerów języków i kompilatora, git, środowisko) bez plików .env i wartości sekretów; polecenia agenta w kontenerze projektu (bezpieczne od razu, reszta po kliknięciu); zmiany jako bloki aster-edit/aster-file → różnice do akceptacji plik po pliku (podgląd, Zastosuj/Odrzuć, wszystko naraz), zastosowane zapisywane; pasek „co agent robi” w panelu i na pasku stanu (sprawdzone z usługą z gałęzi claude/asystent i udawanym modelem)
- [x] Aster Code: różnice obok siebie (przełącznik w podglądzie różnic i w Ustawieniach, zapamiętany) — także dla zatwierdzeń z historii i zmian od agenta
- [x] Aster Code: wdrożenie jednym kliknięciem (⇪ na pasku kart, paleta) — własny serwer przez SSH (budowanie, rsync z wykluczeniem node_modules/.venv/.git/.env, polecenie po wdrożeniu), GitHub Pages, Netlify, Vercel, Cloudflare Pages (klucze z Sekretów projektu); ustawienia w .aster/wdrozenie.json, wdrożenie jako zadanie z logami, adres strony po zakończeniu (sprawdzone: SSH na localhost; hostingi — niesprawdzone, bez kont)
- [x] Aster Code: logowanie do GitHuba bez terminala — przez przeglądarkę (gh auth login --web: kod jednorazowy w Aster Code, gh auth setup-git) albo tokenem w portfelu (pomocnik haseł gita z tokenem przy wysyłaniu i pobieraniu, także dla gh-pages); nowe repozytorium na GitHubie i pierwsze wysłanie jednym kliknięciem
- [x] Aster Code: poprawki przed wydaniem — wynik poleceń agenta bez sekretów (wartości z portfela i .env, zmienne o tajnych nazwach, znane kształty kluczy), polecenia czytające .env, klucze i środowisko nie uruchamiają się; Flatpak: dostęp do portfela i usługi asystenta, git przez flatpak-spawn; zmiana od agenta liczona na aktualnej treści pliku; kopie niezapisanych kart przywracane po awarii; haki testowe tylko z -DASTER_CODE_TEST_HOOKS=ON
- [x] Aster Code, kierunek „najbardziej intuicyjny edytor” (miara: nie trzeba znać skrótu, nazwy funkcji ani polecenia): pole „Co chcesz zrobić?” — pliki, polecenia, ustawienia, szukanie w kodzie, wiersz, agent (zdanie idzie najpierw do agenta), bez polskich znaków; podpisy przycisków z ikoną; pusty edytor z działaniami; „Przygotuj projekt” (języki, serwery języków, zależności w kontenerze jednym kliknięciem); „Napraw” przy problemach i w żarówce, „Wyjaśnij i napraw” oraz „Zainstaluj” przy nieudanych zadaniach
- [ ] Aster Code, intuicyjność dalej: historia lokalna (cofnięcie do dowolnego zapisu bez gita), pierwsze uruchomienie, zrozumiałe błędy w terminalu, język git po ludzku
- [ ] Aster Code: debugowanie dalej — warunkowe punkty przerwania, obserwowane wyrażenia, podgląd wartości po najechaniu, punkty przerwania zapamiętane i przesuwane przy edycji, przekazanie wejścia do programu; zadania z pliku .aster/zadania.json, kilka zadań naraz, serwer deweloperski w tle
- [ ] Aster Code: więcej grup i podział w pionie, zaznaczanie prostokątne (Shift+Alt+przeciągnięcie), zwijanie z serwera języka (foldingRange), zwinięte bloki w minimapie, przeciąganie kart między grupami
- [ ] Aster Code: kilka terminali, zadania (uruchom/zbuduj), debugowanie (DAP), rozszerzenia i ustawienia (motywy, skróty z VS Code)
- [x] Aster Harbor (`apps/dev/harbor`, `aster-harbor`, Start → Narzędzia developera) — kontenery i środowiska
      programisty: toolboxy i kontenery podmana (stan, obraz, porty jako odnośniki do localhost, CPU/RAM z `podman stats`,
      odświeżanie co 3 s tylko przy widocznym oknie), start/stop/restart/usuń (z pytaniem), logi na żywo od dołu
      (`podman logs -f`, filtr, zawijanie, kopiowanie, wyróżnione błędy i ostrzeżenia), terminal w środku (Terminal Aster:
      `toolbox enter` albo `podman exec`), projekty compose (wykrywane po etykietach kontenerów albo dodany folder
      z compose.yaml / docker-compose.yml; usługi ze stanem i portami, `podman compose up -d` z postępem i `down`),
      obrazy (rozmiar, czy używane, usuwanie, „Usuń nieużywane” z podsumowaniem zwolnionego miejsca), kreator „Nowe
      środowisko” (Node.js, Python, Go, Rust, C/C++, PHP, Java, Ruby, pusta Fedora → `toolbox create` + `dnf install`,
      nazwa i folder projektu, kroki z wyjściem poleceń, potem terminal albo Aster Code). Podman przez CLI z `--format json`
      (w Flatpaku `flatpak-spawn --host`); `podman-compose` dodany do obrazu. Dla agenta asystenta: `aster-harbor list|images|
      logs|start|stop|restart` (`--json`) i D-Bus `org.aster.Harbor` (/org/aster/Harbor: List, Images, Logs, Start, Stop,
      Restart; usługa na żądanie, kończy się po 5 min). Flatpak: `apps/dev/harbor/flatpak/org.aster.harbor.yml`.
      Sprawdzone na prawdziwym podmanie 5.8 (osobny kontener z podmanem, toolboxem i podman-compose)
- [ ] Aster Harbor dalej: wolumeny i sieci, budowanie obrazu z Containerfile, pobieranie obrazu z wyszukiwarką,
      szczegóły kontenera (zmienne, montowania), eksport/import środowiska, devcontainer.json, podpięcie
      narzędzi Harbora do asystenta (po scaleniu gałęzi asystenta), test na prawdziwym Asterze (VM)
- [x] Aster Launch — wdrożenia aplikacji (`apps/dev/launch`, `aster-launch`, Start → Narzędzia developera):
      projekty z folderu (wykrycie: statyczna strona — też Vite/React/Astro z budowaniem, Node.js, Python, Dockerfile,
      Docker Compose); cel: własny serwer przez SSH (klucz z ~/.ssh albo nowy ed25519, „Dodaj na serwer hasłem” —
      ssh-copy-id w Terminalu, sprawdzenie serwera tylko do odczytu) albo Netlify / Vercel / Cloudflare Pages przez ich
      CLI (wykrycie programu, instalacja `npm -g --prefix ~/.local`, logowanie w przeglądarce, stan konta);
      na serwerze: /srv/aster-launch/<nazwa>/releases/vN + `current`, wysyłka rsync (niezmienione pliki jako
      twarde dowiązania do poprzedniej wersji), usługa systemd `aster-<nazwa>` (DynamicUser, ochrona systemu) albo
      kontener podman/docker (obraz na wersję), Caddy z plikiem w Caddyfile.d — domena z automatycznym HTTPS,
      bez domeny port serwera; doinstalowanie brakujących programów (dnf/apt); sprawdzenie DNS domeny (rekord A
      vs adres serwera, domeny lokalne); KAŻDA zmiana najpierw jako plan z dokładnymi poleceniami i skryptami
      i dopiero po „Wykonaj”; przebieg na żywo, przerwanie; sprawdzenie strony po wdrożeniu (curl, także przed
      zmianą DNS — `--resolve`); historia wersji z gitem (zatwierdzenie, niezatwierdzone zmiany), zdarzenia,
      przywrócenie wersji jednym kliknięciem (na serwerze tylko przełączenie, w hostingach ponowne wdrożenie kopii
      albo `vercel rollback`), sprzątanie — zostaje N ostatnich wersji; logi produkcji na żywo (journalctl / podman
      logs przez SSH) z filtrem; polecenie `aster-launch lista|status|wdroz|przywroc|logi|dodaj` (potwierdzenie
      [t/N] tylko z terminala, nie ze stdin; bez terminala — plan w oknie); D-Bus `org.aster.Launch`
      (Projects, Status, Deploy, Rollback, Logs — wdrożenie, przywrócenie i logi zawsze czekają na zgodę w oknie);
      Flatpak `org.aster.launch` (ssh/rsync/CLI z systemu przez flatpak-spawn --host).
      Test: kontener Fedora 44 z systemd, sshd, Caddy i podmanem — strona statyczna (domena .internal, HTTPS z urzędu
      Caddy), aplikacja Python (systemd), Dockerfile (podman), przywracanie, logi, sprzątanie, D-Bus z odmową i zgodą
- [ ] Aster Launch, dalej: zmienne środowiskowe i sekrety aplikacji (portfel systemu → plik env na serwerze),
      użytkownik bez roota z sudo (niesprawdzone), bazy danych obok aplikacji, kilka serwerów naraz, wdrożenie po
      każdym push (hook gita), podgląd zmian plików przed wysyłką (rsync --dry-run), logi z hostingów, powiadomienie
      po wdrożeniu, prawdziwe Netlify/Vercel/Cloudflare (sprawdzone tylko z atrapą CLI)
- [ ] Kolejne programy według potrzeb (notatki, poczta i kalendarz, biuro jako nakładki albo własne)

## Aster Intelligence (dawniej Asystent Aster)
Jeden agent dla całego systemu — nie czat z radami, tylko ktoś, kto sam sprawdza i naprawia (za zgodą): na górnym pasku, w osobnym panelu i w terminalu. Odpowiada model w chmurze
albo lokalny — zawsze widać który, a nic nie wychodzi z komputera bez zgody.

**Gdzie mieszka**
- **Wyspa na górnym pasku** (Super+Spacja albo klik w wyspę): wyspa rozlewa się w pole pytania. Krótka odpowiedź na
  jedno pytanie albo polecenie („włącz tryb ciemny”, „ile to 15% z 240”, „przetłumacz na angielski: …”) pojawia się
  w wyspie i znika jak powiadomienie.
- **Panel z prawej** (warstwa jak centrum sterowania): otwiera się sam, gdy rozmowa ma więcej niż jedną wymianę albo
  odpowiedź jest długa (lista kroków, kod, tabela). Historia rozmów, kopiowanie, wklejanie plików i zrzutów,
  przypięcie panelu na stałe, „Nowa rozmowa”.
- **Terminal** — polecenie `aster` (`ai` jako skrót) w każdym terminalu:
  - `aster "jak spakować folder do zip"` — odpowiedź od razu, strumieniowo;
  - `aster` bez argumentów — rozmowa w terminalu (wiele wiadomości), `/nowa`, `/model`, `/wyjdz`;
  - potok: `journalctl -b -p err | aster "co tu jest nie tak?"`, `git diff | aster "napisz opis commita"`;
  - asystent może zaproponować komendę — pokazuje ją i pyta [T/n] przed uruchomieniem, nigdy sam.
  - Terminal Aster: Ctrl+Shift+A otwiera rozmowę z kontekstem ostatniego polecenia i jego błędu.

**Jak działa**
- Usługa `aster-assistant` (D-Bus `org.aster.Assistant`, sesja użytkownika) — jedna dla wyspy, panelu i terminala:
  rozmowy, strumień odpowiedzi, narzędzia, historia (lokalnie, w ~/.local/share/aster/asystent, do wyłączenia).
- Dostawcy przez API zgodne z OpenAI (DeepSeek, OpenAI, Gemini, OpenRouter, Mistral, lokalny llama.cpp/Ollama)
  oraz Anthropic (Claude). Klucze API w portfelu systemu (Secret Service / KWallet), nie w plikach.
- **Model lokalny (offline):** llama.cpp (`llama-server`) z małym modelem 3–4B (Q4, ok. 2–3 GB) pobieranym na życzenie;
  wystarcza do poleceń systemowych, streszczeń i tłumaczeń, działa też na słabym sprzęcie (i3, 8 GB — wolniej).
  Tryb „Najpierw lokalnie”: proste rzeczy lokalnie, trudniejsze — do chmury po zgodzie.
- **Narzędzia (function calling)** z potwierdzeniem przy każdej zmianie w systemie: tryb ciemny, jasność, głośność,
  Wi‑Fi, Bluetooth, Nie przeszkadzać; otwieranie programów i ustawień; wyszukiwanie plików (Baloo) i ich otwieranie;
  przypomnienia i minutnik (dynamiczna wyspa); komendy w terminalu (pokazane i potwierdzone).
- **Kontekst na życzenie:** zaznaczony tekst, schowek, plik przeciągnięty do panelu, zrzut okna — tylko po kliknięciu,
  nigdy w tle.

**Prywatność**
- Przy pierwszym uruchomieniu wybór: tylko lokalnie / chmura (dostawca + klucz) / najpierw lokalnie.
- Każda odpowiedź ma znaczek „Na tym komputerze” albo „Chmura: <dostawca>”; dostawcy z serwerami poza UE są opisani
  wprost (np. DeepSeek — serwery w Chinach).
- Bez telemetrii; historia tylko lokalnie; „Wyczyść historię” jednym kliknięciem.

**Ustawienia → Asystent:** dostawca i model, klucz API, model lokalny (pobierz / usuń, rozmiar), skrót klawiszowy,
historia, uprawnienia narzędzi (np. „zawsze pytaj przed komendą”).

**Etapy**
- [x] A1. Usługa `aster-assistant` (`assistant/`: Qt Core/Network/DBus, bez GUI; startuje na żądanie przez D-Bus,
      kończy się po 15 min bezczynności) + polecenie `aster`/`ai` (jedno pytanie strumieniowo, rozmowa z `/nowa`,
      `/model` — z ostrzeżeniem, gdzie trafią pytania, i wpisaniem klucza bez echa — `/wyjdz`, potok jako kontekst;
      komendy z bloków ```bash pokazywane z pytaniem [T/n], ryzykowne — sudo, rm -r, dd, systemctl… — domyślnie „nie”).
      Dostawcy: lokalny llama.cpp (domyślny — nic nie wychodzi bez wyboru chmury), Ollama, Mistral (UE), DeepSeek
      (Chiny), OpenAI, Claude (Anthropic Messages), Gemini, OpenRouter. Klucze przez Secret Service (KWallet/ksecretd)
      — własna obsługa przez D-Bus, bez nowych zależności; w pliku tylko „klucz jest”. Historia w
      ~/.local/share/aster/asystent (pliki 0600, do wyłączenia i wyczyszczenia). Ustawienia → Asystent: dostawca
      (zgoda z opisem serwerów przy wyborze chmury), model, adres serwera lokalnego, klucz, historia.
      Testy bez klucza: `tools/asystent-atrapa.py` (atrapa API OpenAI i Anthropic ze strumieniem), zmienne
      `ASTER_ASSISTANT_URL` / `ASTER_ASSISTANT_API_KEY` dla usługi.
- [x] A2. Wyspa: Super+Spacja (kglobalaccel przez D-Bus) albo klik — pole pytania w wyspie (klawiatura warstwy
      przełączana na „exclusive” tylko na czas pytania), krótka odpowiedź ze znaczkiem i znika po 12 s; dopytanie,
      długa odpowiedź (kod, lista, tabela) albo błąd → panel z prawej (`AssistantWindow.qml`): rozmowa w Markdown,
      znaczek „Na tym komputerze” / „Chmura: <dostawca>” przy każdej odpowiedzi, kopiowanie, „Nowa rozmowa”,
      historia (otwieranie, usuwanie), podpowiedzi pierwszych pytań. Zrzuty: `ASTER_SHOT_ASK="pytanie|dopytanie"`,
      `ASTER_OPEN_ASSISTANT=1`. Do sprawdzenia na prawdziwym KWin: fokus klawiatury wyspy i Super+Spacja.
- [ ] A2+. Panel: przypięcie na stałe, wklejanie plików i zrzutów (razem z A5); wybór przy pierwszym uruchomieniu
      (tylko lokalnie / chmura / najpierw lokalnie — razem z A4)
- [x] A2.5. Nazwa Aster Intelligence i wygląd jak Apple Intelligence: tęczowa poświata krążąca wokół wyspy (i od środka
      jej krawędzi), poświata na krawędziach ekranu, gdy model myśli (`EdgeGlowWindow.qml`, warstwa overlay
      przezroczysta dla myszy, schowana, gdy nie świeci), kula z krążącymi kolorami zamiast iskry, migoczące „Myślę…”,
      sprężyste wejście wyspy, odpowiedź wyłaniająca się z dołu, „Kopiuj” w wyspie, obwódka pola w panelu.
      Narzędzia do pisania: zaznaczony tekst (podstawowe zaznaczenie Waylanda, inaczej schowek; hasła z menedżerów
      haseł pomijane) → Popraw błędy, Przeredaguj, Przyjaźniej, Profesjonalnie, Zwięźlej, Streść, Najważniejsze punkty
      (źródło „pisanie”: sam wynik, bez komentarzy) albo własne polecenie do tego tekstu. Test: `ASTER_SHOT_SELECTION`,
      `ASTER_SHOT_ASK=-` (samo otwarcie), `ASTER_SHOT_GLOW=1`.
- [x] A3. Agent: model pisze jedno polecenie w ```bash ze zdaniem po ludzku („Zainstalować Google Chrome?”); usługa
      urywa odpowiedź po bloku (bez zgadywania wyniku) i wysyła `ActionRequested`; powłoka (karta w panelu: zdanie,
      „Tak, zrób to” / „Nie”, szczegóły z poleceniem i wynikiem, „Otwórz w Terminalu”) albo `aster` (w bieżącym
      folderze, [T/n]) uruchamia je i odsyła wynik `ActionResult`, a model działa dalej (do 10 poleceń na pytanie).
      Polecenia tylko do odczytu (lista w `Service::isSafeCommand`: df, journalctl, systemctl status, flatpak list…)
      — od razu i bez klawiatury; wszystko inne, w tym instalacja, po zgodzie; odmowa kończy działanie. W powłoce sudo
      → pkexec (okno hasła), programy Aster (aster-files…) startują osobno. Prompt: najpierw programy Aster (lista
      z poleceniami), Flatpak z Flathub, nigdy dnf, nie wymyślać programów. `aster-terminal --wpisz POLECENIE`
      wpisuje bez Entera.
- [ ] A3+. Narzędzia systemowe bez powłoki (tryb ciemny, jasność, Wi‑Fi przez D-Bus); Ctrl+Shift+A w Terminalu Aster;
      zgoda „zawsze pozwalaj na to polecenie”
- [x] A4. Model lokalny dobrany do sprzętu: katalog Gemma 3 1B / 4B / 12B (GGUF Q4_K_M z ggml-org na Hugging Face),
      polecany według pamięci i rdzeni (1B do 8 GB / 4 rdzeni, 4B od 12 GB i 6 rdzeni, 12B od 32 GB i 8 rdzeni; poniżej
      minimum nie da się pobrać). Ustawienia → Aster Intelligence → „Model na tym komputerze”: sprzęt, Pobierz z paskiem
      postępu i Przerwij (wznawianie z pliku .part, samo ponawia po zerwaniu połączenia), Używaj, Usuń. llama-server
      (pakiet llama-cpp w obrazie) jako `aster-llama.service` bez autostartu: usługa asystenta włącza go przy pytaniu
      i czeka na /health, a wyłącza, gdy sama kończy pracę po kwadransie bezczynności — model nie zajmuje pamięci, gdy
      nikt nie pyta. Parametry z ~/.config/aster/llama.env (wątki i kontekst według sprzętu), nadpisania w
      llama-local.env. Dla instalatora: `aster --model-lokalny auto` (lista: `aster --model-lokalny`).
- [ ] A4+. Pierwsze uruchomienie / instalator: „Czy chcesz korzystać z Aster Intelligence?” → tak: `aster --model-lokalny auto`
      w tle (albo wybór chmury), nie: wyspa bez asystenta; tryb offline i „Najpierw lokalnie”
- [x] A4.5. Zgoda tylko na ważne sprawy (assistant/src/commands.cpp): sam otwiera programy, tworzy foldery, kopiuje,
      zmienia głośność; pyta przed instalacją/usuwaniem programów, usuwaniem i nadpisywaniem plików, pkexec, restartem,
      zatrzymywaniem programów i usług, zmianami sieci, dysków i kont, skryptami (Ustawienia: „Pytaj o zgodę” — tylko przy
      ważnych / przy każdej zmianie). Pamięć rozmów: streszczenia ostatnich 8 rozmów w prompcie (streszcza model w chmurze
      w tle; rozmowy z modelem lokalnym — bez modelu i nigdy do chmury), `aster --historia [słowa]`, `aster --rozmowa ID`
      — panel sam otwiera znalezioną rozmowę. Przycisk Aster Intelligence w prawej wyspie (za Centrum sterowania)
      otwiera panel z rozmowami
- [x] A4.6. Niebieski motyw (poświata, kula, panel). Kropla rozmowy pod prawą wyspą: bieżąca rozmowa się w nią chowa
      (panel rozlewa się z niej i w nią wraca), bez rozmowy kropli nie ma; myśli — poświata, czeka na zgodę — pulsuje.
      Okna i programy: powłoka wystawia D-Bus org.aster.Shell (ListWindows, WindowAction, OpenApp), w terminalu
      `aster --okna`, `--pokaz/--zminimalizuj/--maksymalizuj/--zamknij-okno OKNO`, `aster --otworz PROGRAM [pliki]`,
      `aster --instaluj code|grafika|montaz|studio…` (Flatpak z wydania „aplikacje”) — agent sam doinstalowuje brakujące
- [ ] A5. Kontekst: zaznaczony tekst, pliki, zrzut okna; przypomnienia i minutnik w wyspie

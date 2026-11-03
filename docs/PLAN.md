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
- [ ] Montaż, dalej: naklejki animowane (GIF/WebP, Lottie), własne naklejki użytkownika z wycinaniem tła,
      klatki kluczowe położenia i skali, nagrywanie lektora, cofanie klipu i stop-klatka,
      płynna zmiana prędkości, cięcia do rytmu muzyki, wyciszanie początku/końca klipu, obrót o 90°, szablony,
      fala dźwięku także w klipach wideo, kilka ścieżek wideo (obraz w obrazie), wyciszanie muzyki pod mową, zatrzymanie klatki,
      szablony, nagrywanie lektora, eksport w 60 kl./s i 4K; docelowo rozdawany jako Flatpak przez Sklep Aster
- [ ] Montaż: ostateczna nazwa programu (propozycje: Klaps, Kadr, Ujęcie) i kodeki H.264 na systemach bez OpenH264
- [ ] Aster Code — edytor kodu w stylu Aster
- [ ] Kolejne programy według potrzeb (notatki, poczta i kalendarz, biuro jako nakładki albo własne)

.pragma library

// Katalog Aster: to my decydujemy, co polecamy. Własne opisy po polsku, werdykty z zaletami i wadami,
// zadania i przesiadka z Windowsa. Skąd program fizycznie przychodzi (Flatpak, paczka Aster, strona), to szczegół.
//
// Odnośnik do programu (ref): identyfikator Flatpaka („org.gimp.GIMP”), „aster:montaz” albo „web:spotify”.
// Fakty redakcyjne wpisujemy tylko, gdy jesteśmy ich pewni; czego nie ma, karta programu podaje jako „nie sprawdziliśmy”.
//   cat      dział katalogu
//   pl       nasz opis jednym zdaniem
//   tags     słowa do wyszukiwania (także potoczne i po angielsku)
//   good/bad werdykt: konkretne zalety i wady
//   offline  "tak" | "czesc" | "nie"   czy działa bez internetu
//   account  "nie" | "opcja" | "tak"   czy trzeba zakładać konto
//   cost     "free" | "freemium" | "paid"
//   ads      true, gdy pokazuje reklamy
//   heavy    0 lekki, 1 średni, 2 ciężki dla komputera (pamięć i procesor)
//   web      klucz wersji webowej, gdy jest sensowną lżejszą alternatywą
// Czwarte źródło, „get:”: programy, których nie ma jako Flatpak. Instaluje je aster-get prosto od producenta, do katalogu domowego.

var categories = [
    { id: "gry", name: "Gry", icon: "game" },
    { id: "ai", name: "Sztuczna inteligencja", icon: "sparkle" },
    { id: "internet", name: "Internet", icon: "globe" },
    { id: "rozmowy", name: "Rozmowy i poczta", icon: "send" },
    { id: "filmy", name: "Filmy i seriale", icon: "film" },
    { id: "muzyka", name: "Muzyka", icon: "music" },
    { id: "biuro", name: "Biuro i nauka", icon: "doc" },
    { id: "grafika", name: "Grafika i 3D", icon: "image" },
    { id: "wideo", name: "Tworzenie wideo", icon: "clapper" },
    { id: "kod", name: "Programowanie", icon: "code" },
    { id: "narzedzia", name: "Narzędzia", icon: "tool" }
];

var apps = {
    // ——— Biuro i nauka ———
    "org.libreoffice.LibreOffice": { cat: "biuro", pl: "Pełny pakiet biurowy: dokumenty, arkusze, prezentacje, bez opłat i bez konta.",
        tags: "office word excel powerpoint dokument arkusz prezentacja tekst biuro pisanie docx xlsx pptx writer calc impress",
        good: ["Otwiera pliki Worda, Excela i PowerPointa", "Działa w całości bez internetu", "Zero opłat, zero konta"],
        bad: ["Wygląda bardziej jak Office sprzed lat", "Skomplikowane dokumenty z Worda potrafią się rozjechać"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.onlyoffice.desktopeditors": { cat: "biuro", pl: "Pakiet biurowy najbliższy wyglądem Microsoft Office, wierny przy plikach .docx.",
        tags: "office word excel powerpoint docx xlsx pptx dokument arkusz prezentacja",
        good: ["Układ wstążki jak w Office", "Bardzo wierny przy plikach Microsoftu"],
        bad: ["Zbudowany na przeglądarce, zużywa dużo pamięci", "Zajmuje ponad gigabajt"],
        offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "md.obsidian.Obsidian": { cat: "biuro", pl: "Notatki w zwykłych plikach, połączone ze sobą jak własna Wikipedia.",
        tags: "notatki notes markdown wiedza notion onenote", offline: "tak", account: "opcja", cost: "freemium", heavy: 1 },
    "net.cozic.joplin_desktop": { cat: "biuro", pl: "Otwarte notatki z synchronizacją, dobry następca OneNote i Evernote.",
        tags: "notatki notes onenote evernote markdown", offline: "tak", account: "opcja", cost: "free", heavy: 1 },
    "org.zotero.Zotero": { cat: "biuro", pl: "Zbiera źródła do pracy naukowej i sam układa bibliografię.",
        tags: "bibliografia studia praca licencjacka magisterska cytowania endnote mendeley", offline: "czesc", account: "opcja", cost: "free" },
    "org.kde.okular": { cat: "biuro", pl: "Czytnik PDF z podkreślaniem, notatkami i podpisami.",
        tags: "pdf adobe reader acrobat czytnik podpis", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.gnome.Papers": { cat: "biuro", pl: "Prosty, szybki czytnik PDF bez zbędnych przycisków.",
        tags: "pdf czytnik dokumenty adobe reader", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.github.xournalpp.xournalpp": { cat: "biuro", pl: "Odręczne notatki i pisanie po PDF-ach rysikiem albo myszą.",
        tags: "notatki rysik tablet pdf podpis odręczne", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.github.jeromerobert.pdfarranger": { cat: "biuro", pl: "Łączy, dzieli i obraca strony PDF przeciąganiem.",
        tags: "pdf połącz scal podziel strony obróć", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.mozilla.thunderbird": { cat: "rozmowy", pl: "Poczta, kalendarz i kontakty w jednym programie, działa z każdą skrzynką.",
        tags: "poczta mail email outlook kalendarz kontakty",
        good: ["Obsługuje Gmaila, Outlooka, Onet, WP i inne", "Poczta dostępna też bez internetu", "Bez reklam"],
        bad: ["Konfiguracja kont firmowych Microsoft bywa kłopotliwa"],
        offline: "czesc", account: "nie", cost: "free", heavy: 1 },
    "eu.betterbird.Betterbird": { cat: "internet", pl: "Thunderbird z poprawkami i kilkoma wygodnymi dodatkami.",
        tags: "poczta mail email outlook", offline: "czesc", account: "nie", cost: "free", heavy: 1 },
    "org.gnome.Calendar": { cat: "biuro", pl: "Prosty kalendarz, który łączy się z kontami online.",
        tags: "kalendarz terminy spotkania", offline: "czesc", account: "nie", cost: "free", heavy: 0 },
    "io.github.alainm23.planify": { cat: "biuro", pl: "Listy zadań i projekty, następca Todoist bez abonamentu.",
        tags: "zadania todo lista planowanie todoist microsoft to do", offline: "tak", account: "opcja", cost: "free", heavy: 0 },
    "net.ankiweb.Anki": { cat: "biuro", pl: "Fiszki, które same pilnują, kiedy powtórzyć materiał.",
        tags: "fiszki nauka języki powtórki szkoła studia angielski", offline: "tak", account: "opcja", cost: "free", heavy: 0 },
    "org.kde.gcompris": { cat: "biuro", pl: "Ponad sto gier edukacyjnych dla dzieci od 2 do 10 lat, po polsku.",
        tags: "dzieci edukacja przedszkole szkoła nauka gry", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.tuxpaint.Tuxpaint": { cat: "biuro", pl: "Rysowanie dla najmłodszych, zamknięte i bezpieczne.",
        tags: "dzieci rysowanie paint", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.stellarium.Stellarium": { cat: "biuro", pl: "Planetarium: nocne niebo z Twojego miejsca, tak jak je widać.",
        tags: "astronomia gwiazdy niebo planety nauka", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.kde.kalgebra": { cat: "biuro", pl: "Kalkulator naukowy z wykresami funkcji.",
        tags: "matematyka wykresy funkcje kalkulator szkoła", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.calibre_ebook.calibre": { cat: "biuro", pl: "Biblioteka e-booków: porządkuje, konwertuje i wysyła na czytnik.",
        tags: "ebook kindle czytnik książki epub mobi", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "com.github.johnfactotum.Foliate": { cat: "biuro", pl: "Spokojne czytanie e-booków bez niczego, co rozprasza.",
        tags: "ebook książki epub czytnik", offline: "tak", account: "nie", cost: "free", heavy: 0 },

    // ——— Grafika i zdjęcia ———
    "org.gimp.GIMP": { cat: "grafika", pl: "Najmocniejszy darmowy edytor zdjęć: warstwy, maski, retusz.",
        tags: "photoshop zdjęcia obróbka retusz edycja grafika psd warstwy",
        good: ["Warstwy, maski i retusz jak w programach płatnych", "Otwiera pliki .psd", "Ogromna liczba poradników"],
        bad: ["Trzeba się go nauczyć, skróty są inne niż w Photoshopie", "Pliki .psd z efektami tracą część warstw"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.kde.krita": { cat: "grafika", pl: "Malowanie cyfrowe na tablecie, ulubieniec ilustratorów.",
        tags: "rysowanie malowanie tablet ilustracja digital art photoshop komiks animacja procreate clip studio",
        good: ["Świetne pędzle i obsługa tabletów", "Malowanie na warstwach, animacja poklatkowa", "Profesjonalne narzędzie za darmo"],
        bad: ["Do retuszu zdjęć lepszy jest GIMP"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.inkscape.Inkscape": { cat: "grafika", pl: "Grafika wektorowa: logo, plakaty, ikony do druku w każdym rozmiarze.",
        tags: "illustrator corel coreldraw wektor svg logo plakat ulotka",
        good: ["Pełne narzędzie do wektorów", "Natywnie zapisuje SVG"],
        bad: ["Pliki .ai i .cdr otwiera tylko częściowo"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.darktable.Darktable": { cat: "grafika", pl: "Wywoływanie zdjęć RAW i katalog fotografii, odpowiednik Lightrooma.",
        tags: "lightroom raw zdjęcia fotografia aparat wywoływanie", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "com.rawtherapee.RawTherapee": { cat: "grafika", pl: "Precyzyjna obróbka RAW dla tych, którzy lubią suwaki.",
        tags: "raw zdjęcia fotografia lightroom", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.kde.digikam": { cat: "grafika", pl: "Porządkuje dziesiątki tysięcy zdjęć, rozpoznaje też twarze.",
        tags: "zdjęcia album biblioteka twarze porządkowanie katalog", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "org.blender.Blender": { cat: "grafika", pl: "Modelowanie 3D, animacja i efekty na poziomie studiów filmowych.",
        tags: "3d modelowanie animacja render maya 3ds max cinema4d", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "org.freecad.FreeCAD": { cat: "grafika", pl: "Projektowanie techniczne i części do druku 3D.",
        tags: "cad autocad fusion projektowanie druk 3d inżynieria solidworks", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "net.scribus.Scribus": { cat: "grafika", pl: "Skład do druku: ulotki, gazetki, książki.",
        tags: "indesign skład druk dtp ulotka gazetka publisher", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.pencil2d.Pencil2D": { cat: "grafika", pl: "Prosta animacja rysunkowa, klatka po klatce.",
        tags: "animacja rysowanie kreskówka", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.github.PintaProject.Pinta": { cat: "grafika", pl: "Prosty edytor obrazów z warstwami, jak Paint.NET.",
        tags: "paint.net paint proste obrazek", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.kde.kolourpaint": { cat: "grafika", pl: "Zwyczajny Paint: wklej, dorysuj strzałkę, zapisz.",
        tags: "paint rysowanie proste obrazek", offline: "tak", account: "nie", cost: "free", heavy: 0 },

    // ——— Wideo i muzyka ———
    "org.kde.kdenlive": { cat: "wideo", pl: "Pełny montaż wideo na wielu ścieżkach, z napisami i efektami.",
        tags: "premiere montaż film wideo edycja youtube napisy davinci clipchamp vegas",
        good: ["Wiele ścieżek, przejścia, napisy", "Darmowy bez znaków wodnych", "Automatyczne napisy z mowy"],
        bad: ["Długie projekty 4K męczą słabszy komputer", "Projekty z Premiere trzeba zaczynać od nowa"],
        offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "org.shotcut.Shotcut": { cat: "wideo", pl: "Montaż prostszy niż Kdenlive, dobry na początek.",
        tags: "montaż film wideo edycja clipchamp", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.openshot.OpenShot": { cat: "wideo", pl: "Najłatwiejszy montaż: przeciągasz klipy i gotowe.",
        tags: "montaż film wideo proste", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "fr.handbrake.ghb": { cat: "wideo", pl: "Zmniejsza i konwertuje filmy bez utraty jakości widocznej dla oka.",
        tags: "konwersja wideo zmniejsz film mp4 kompresja", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "com.obsproject.Studio": { cat: "wideo", pl: "Nagrywanie ekranu i transmisje na żywo, standard twórców.",
        tags: "nagrywanie ekranu stream twitch youtube transmisja nagraj ekran",
        good: ["Nagrywa ekran i gry bez limitów", "Bez znaku wodnego", "Standard wśród streamerów"],
        bad: ["Na początku sporo ustawień"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.videolan.VLC": { cat: "wideo", pl: "Odtworzy każdy film, jaki mu dasz.",
        tags: "odtwarzacz film wideo mkv media player windows media", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "io.mpv.Mpv": { cat: "wideo", pl: "Lekki odtwarzacz bez interfejsu, świetny na słabym komputerze.",
        tags: "odtwarzacz film wideo lekki", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "tv.kodi.Kodi": { cat: "wideo", pl: "Domowe centrum multimedialne na telewizor.",
        tags: "telewizor media center filmy biblioteka", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.audacityteam.Audacity": { cat: "wideo", pl: "Nagrywanie i przycinanie dźwięku, wybór podcasterów.",
        tags: "dźwięk audio nagrywanie podcast mikrofon mp3 wytnij",
        offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.ardour.Ardour": { cat: "wideo", pl: "Prawdziwe studio nagraniowe do muzyki.",
        tags: "daw muzyka nagrywanie studio pro tools cubase fl studio ableton", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "org.musescore.MuseScore": { cat: "wideo", pl: "Pisanie nut, od szkolnego zadania po partyturę.",
        tags: "nuty partytura muzyka sibelius finale", offline: "tak", account: "opcja", cost: "free", heavy: 1 },
    "com.spotify.Client": { cat: "wideo", pl: "Oficjalny Spotify: muzyka i podcasty z abonamentem albo reklamami.",
        tags: "muzyka streaming podcast playlisty",
        good: ["Praktycznie cała muzyka świata", "Wspólne konto na telefonie i komputerze"],
        bad: ["Bezpłatnie z reklamami", "Zamknięty kod, bez internetu tylko w Premium"],
        offline: "czesc", account: "tak", cost: "freemium", ads: true, heavy: 1, web: "spotify" },
    "org.strawberrymusicplayer.strawberry": { cat: "wideo", pl: "Porządny odtwarzacz własnej kolekcji muzyki.",
        tags: "muzyka mp3 flac odtwarzacz biblioteka winamp foobar itunes", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.github.wwmm.easyeffects": { cat: "wideo", pl: "Korektor i efekty dla całego dźwięku w systemie.",
        tags: "dźwięk equalizer korektor mikrofon szumy", offline: "tak", account: "nie", cost: "free", heavy: 0 },

    // ——— Gry ———
    "com.valvesoftware.Steam": { cat: "gry", pl: "Twoja biblioteka Steam. Większość gier z Windowsa działa dzięki Protonowi.",
        tags: "gry granie proton windows games",
        good: ["Tysiące gier z Windowsa działa bez konfiguracji", "Te same konto i zakupy co na Windowsie"],
        bad: ["Gry z zabezpieczeniem antycheat (np. część strzelanek online) potrafią nie działać"],
        offline: "czesc", account: "tak", cost: "free", heavy: 1 },
    "com.heroicgameslauncher.hgl": { cat: "gry", pl: "Gry z Epic Games, GOG i Amazona w jednym miejscu.",
        tags: "epic games gog amazon gry launcher fortnite", offline: "czesc", account: "tak", cost: "free", heavy: 1 },
    "net.lutris.Lutris": { cat: "gry", pl: "Instaluje gry spoza Steama gotowymi przepisami.",
        tags: "gry battle.net ubisoft ea windows", offline: "czesc", account: "opcja", cost: "free", heavy: 1 },
    "org.prismlauncher.PrismLauncher": { cat: "gry", pl: "Minecraft z modami i wieloma wersjami naraz.",
        tags: "minecraft mody gry", offline: "czesc", account: "tak", cost: "free", heavy: 1 },
    "com.mojang.Minecraft": { cat: "gry", pl: "Oficjalny launcher Minecrafta w wersji Java.",
        tags: "minecraft gry", offline: "czesc", account: "tak", cost: "paid", heavy: 1 },
    "net.supertuxkart.SuperTuxKart": { cat: "gry", pl: "Wyścigi gokartów na kanapie, także przez internet.",
        tags: "gry wyścigi dzieci mario kart", offline: "tak", account: "opcja", cost: "free", heavy: 1 },
    "org.luanti.luanti": { cat: "gry", pl: "Otwarty świat z klocków, dużo lżejszy od Minecrafta.",
        tags: "gry klocki minecraft dzieci lekka", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.openttd.OpenTTD": { cat: "gry", pl: "Budowa imperium transportowego, nieśmiertelna klasyka.",
        tags: "gry strategia transport pociągi", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.libretro.RetroArch": { cat: "gry", pl: "Stare konsole w jednym programie.",
        tags: "emulator retro konsola nes snes psx", offline: "tak", account: "nie", cost: "free", heavy: 1 },
    "com.usebottles.bottles": { cat: "gry", pl: "Uruchamia programy .exe z Windowsa w odizolowanych „butelkach”.",
        tags: "exe windows wine programy z windowsa uruchom",
        good: ["Najprostszy sposób na program .exe", "Każdy program w osobnym, bezpiecznym środowisku"],
        bad: ["Nie każdy program zadziała, zwłaszcza wymagające Adobe i Autodesk"],
        offline: "tak", account: "nie", cost: "free", heavy: 1 },

    // ——— Internet i rozmowy ———
    "org.mozilla.firefox": { cat: "internet", pl: "Niezależna przeglądarka, która nie żyje ze zbierania Twoich danych.",
        tags: "przeglądarka internet www chrome edge", offline: "nie", account: "opcja", cost: "free", heavy: 1 },
    "com.google.Chrome": { cat: "internet", pl: "Oficjalny Chrome z Twoim kontem i rozszerzeniami.",
        tags: "przeglądarka internet www google", offline: "nie", account: "opcja", cost: "free", heavy: 2 },
    "com.brave.Browser": { cat: "internet", pl: "Szybka przeglądarka na silniku Chrome, sama blokuje reklamy.",
        tags: "przeglądarka internet adblock prywatność chrome", offline: "nie", account: "nie", cost: "free", heavy: 1 },
    "com.microsoft.Edge": { cat: "internet", pl: "Edge z Windowsa z tym samym kontem i zakładkami.",
        tags: "przeglądarka internet microsoft", offline: "nie", account: "opcja", cost: "free", heavy: 2 },
    "com.discordapp.Discord": { cat: "internet", pl: "Serwery, czaty głosowe i społeczności graczy.",
        tags: "czat rozmowy serwery gry głosowy",
        good: ["Serwery, kanały głosowe, udostępnianie ekranu"],
        bad: ["Zjada dużo pamięci, na 8 GB lepsza jest wersja webowa", "Zamknięty kod"],
        offline: "nie", account: "tak", cost: "freemium", heavy: 2, web: "discord" },
    "org.telegram.desktop": { cat: "internet", pl: "Szybki komunikator z natywnym, lekkim programem.",
        tags: "czat komunikator wiadomości", offline: "nie", account: "tak", cost: "freemium", heavy: 0 },
    "org.signal.Signal": { cat: "internet", pl: "Najbardziej prywatny komunikator, wszystko szyfrowane.",
        tags: "czat komunikator prywatność szyfrowanie", offline: "nie", account: "tak", cost: "free", heavy: 1 },
    "com.slack.Slack": { cat: "internet", pl: "Firmowy czat. W przeglądarce działa równie dobrze i lżej.",
        tags: "praca firma czat zespół", offline: "nie", account: "tak", cost: "freemium", heavy: 2, web: "slack" },
    "us.zoom.Zoom": { cat: "internet", pl: "Spotkania wideo; do udziału wystarczy link.",
        tags: "wideo spotkania wideokonferencja lekcje online", offline: "nie", account: "opcja", cost: "freemium", heavy: 2 },
    "org.jitsi.jitsi-meet": { cat: "internet", pl: "Rozmowy wideo bez kont i bez limitu czasu.",
        tags: "wideo spotkania rozmowy", offline: "nie", account: "nie", cost: "free", heavy: 1 },
    "org.qbittorrent.qBittorrent": { cat: "internet", pl: "Pobieranie przez torrenty bez reklam, inaczej niż w uTorrencie.",
        tags: "torrent pobieranie utorrent", offline: "nie", account: "nie", cost: "free", heavy: 0 },
    "org.filezillaproject.Filezilla": { cat: "internet", pl: "Wysyłanie plików na serwer przez FTP.",
        tags: "ftp sftp serwer strona www", offline: "nie", account: "nie", cost: "free", heavy: 0 },
    "com.nextcloud.desktopclient.nextcloud": { cat: "internet", pl: "Synchronizacja plików z własnym Nextcloudem.",
        tags: "chmura dysk synchronizacja onedrive google drive dropbox", offline: "czesc", account: "tak", cost: "free", heavy: 0 },
    "com.dropbox.Client": { cat: "internet", pl: "Oficjalny Dropbox: Twój folder w chmurze.",
        tags: "chmura dysk synchronizacja", offline: "czesc", account: "tak", cost: "freemium", heavy: 1 },
    "com.rustdesk.RustDesk": { cat: "internet", pl: "Zdalna pomoc na odległość, otwarta wersja TeamViewera.",
        tags: "pulpit zdalny teamviewer anydesk pomoc zdalna", offline: "nie", account: "nie", cost: "free", heavy: 0 },

    // ——— Programowanie ———
    "com.vscodium.codium": { cat: "kod", pl: "Edytor Visual Studio Code bez telemetrii Microsoftu.",
        tags: "edytor kod programowanie ide vscode python javascript", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "com.visualstudio.code": { cat: "kod", pl: "Oficjalny Visual Studio Code z rozszerzeniami Microsoftu.",
        tags: "edytor kod programowanie ide vscode python javascript", offline: "tak", account: "opcja", cost: "free", heavy: 2 },
    "dev.zed.Zed": { cat: "kod", pl: "Bardzo szybki nowy edytor kodu, z pracą w zespole.",
        tags: "edytor kod programowanie", offline: "tak", account: "opcja", cost: "free", heavy: 1 },
    "org.kde.kate": { cat: "kod", pl: "Lekki edytor tekstu i kodu, następca Notepada++.",
        tags: "notepad++ notatnik edytor tekst kod", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.jetbrains.IntelliJ-IDEA-Community": { cat: "kod", pl: "Rozbudowane środowisko do Javy i Kotlina.",
        tags: "java kotlin ide programowanie", offline: "tak", account: "opcja", cost: "free", heavy: 2 },
    "io.dbeaver.DBeaverCommunity": { cat: "kod", pl: "Praca z każdą bazą danych w jednym oknie.",
        tags: "baza danych sql postgres mysql", offline: "tak", account: "nie", cost: "free", heavy: 2 },
    "com.getpostman.Postman": { cat: "kod", pl: "Testowanie API, standard w wielu firmach.",
        tags: "api rest http testowanie", offline: "czesc", account: "tak", cost: "freemium", heavy: 2 },

    // ——— Narzędzia ———
    "com.bitwarden.desktop": { cat: "narzedzia", pl: "Menedżer haseł z synchronizacją między urządzeniami.",
        tags: "hasła password manager lastpass 1password bezpieczeństwo", offline: "czesc", account: "tak", cost: "freemium", heavy: 1 },
    "org.keepassxc.KeePassXC": { cat: "narzedzia", pl: "Hasła w jednym zaszyfrowanym pliku, bez chmury.",
        tags: "hasła password keepass bezpieczeństwo", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.localsend.localsend_app": { cat: "narzedzia", pl: "Wysyła pliki między komputerem a telefonem po Wi-Fi, bez kabla.",
        tags: "wyślij plik telefon airdrop udostępnianie przenieś pliki", offline: "czesc", account: "nie", cost: "free", heavy: 0 },
    "org.flameshot.Flameshot": { cat: "narzedzia", pl: "Zrzuty ekranu ze strzałkami i zamazywaniem.",
        tags: "zrzut ekranu screenshot wycinek snipping tool lightshot", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "org.gnome.DejaDup": { cat: "narzedzia", pl: "Kopie zapasowe: ustawiasz raz i masz spokój.",
        tags: "kopia zapasowa backup", offline: "czesc", account: "nie", cost: "free", heavy: 0 },
    "org.cryptomator.Cryptomator": { cat: "narzedzia", pl: "Szyfruje pliki, zanim trafią do chmury.",
        tags: "szyfrowanie chmura bezpieczeństwo", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "io.github.peazip.PeaZip": { cat: "narzedzia", pl: "Rozpakowuje wszystko, od .zip po .rar i .7z.",
        tags: "zip rar 7z winrar 7-zip archiwum rozpakuj", offline: "tak", account: "nie", cost: "free", heavy: 0 },
    "com.github.tchx84.Flatseal": { cat: "narzedzia", pl: "Zmieniasz uprawnienia programów po swojemu.",
        tags: "uprawnienia prywatność bezpieczeństwo", offline: "tak", account: "nie", cost: "free", heavy: 0 }
};

// Aplikacje webowe: okno z własną ikoną w Starcie, zero miejsca na dysku
var web = {
    word: { name: "Word w przeglądarce", url: "https://www.office.com/launch/word", color: "#185ABD", category: "biuro", cat: "biuro", pl: "Prawdziwy Word od Microsoftu, także z Twoim OneDrive.",
        tags: "word office microsoft 365 docx", offline: "nie", account: "tak", cost: "freemium" },
    excel: { name: "Excel w przeglądarce", url: "https://www.office.com/launch/excel", color: "#107C41", category: "biuro", cat: "biuro", pl: "Prawdziwy Excel od Microsoftu, bez instalowania.",
        tags: "excel office arkusz xlsx", offline: "nie", account: "tak", cost: "freemium" },
    powerpoint: { name: "PowerPoint w przeglądarce", url: "https://www.office.com/launch/powerpoint", color: "#C43E1C", category: "biuro", cat: "biuro", pl: "Prawdziwy PowerPoint od Microsoftu, bez instalowania.",
        tags: "powerpoint prezentacja pptx office", offline: "nie", account: "tak", cost: "freemium" },
    outlook: { name: "Outlook", url: "https://outlook.live.com/mail/", color: "#0F6CBD", category: "internet", cat: "internet", pl: "Twoja poczta Microsoftu w osobnym oknie.",
        tags: "poczta mail hotmail", offline: "nie", account: "tak", cost: "free" },
    teams: { name: "Teams", url: "https://teams.microsoft.com/", color: "#5B5FC7", category: "internet", cat: "internet", pl: "Spotkania i czaty w pracy i w szkole.",
        tags: "spotkania lekcje szkoła praca", offline: "nie", account: "tak", cost: "freemium" },
    gmail: { name: "Gmail", url: "https://mail.google.com/", color: "#D93025", category: "internet", cat: "internet", pl: "Poczta Google w osobnym oknie, z powiadomieniami.",
        tags: "poczta mail google", offline: "nie", account: "tak", cost: "free" },
    whatsapp: { name: "WhatsApp", url: "https://web.whatsapp.com/", color: "#00A884", category: "internet", cat: "internet", pl: "Twoje czaty z telefonu na dużym ekranie.",
        tags: "czat komunikator wiadomości", offline: "nie", account: "tak", cost: "free" },
    messenger: { name: "Messenger", url: "https://www.messenger.com/", color: "#0866FF", category: "internet", cat: "internet", pl: "Wiadomości z Facebooka bez Facebooka.",
        tags: "czat komunikator facebook", offline: "nie", account: "tak", cost: "free" },
    discord: { name: "Discord (lekki)", url: "https://discord.com/app", color: "#5865F2", category: "internet", cat: "internet", pl: "Ten sam Discord bez osobnego ciężkiego programu.",
        tags: "czat rozmowy serwery", offline: "nie", account: "tak", cost: "freemium" },
    slack: { name: "Slack (lekki)", url: "https://app.slack.com/client", color: "#4A154B", category: "internet", cat: "internet", pl: "Firmowy czat bez osobnego ciężkiego programu.",
        tags: "praca firma czat", offline: "nie", account: "tak", cost: "freemium" },
    spotify: { name: "Spotify (lekki)", url: "https://open.spotify.com/", color: "#1DB954", category: "multimedia", cat: "wideo", pl: "Spotify w osobnym oknie, bez instalowania programu.",
        tags: "muzyka streaming", offline: "nie", account: "tak", cost: "freemium", ads: true },
    youtube: { name: "YouTube", url: "https://www.youtube.com/", color: "#FF0033", category: "multimedia", cat: "wideo", pl: "YouTube jako osobna aplikacja, z paskiem Astera.",
        tags: "filmy wideo", offline: "nie", account: "opcja", cost: "freemium", ads: true },
    canva: { name: "Canva", url: "https://www.canva.com/", color: "#7D2AE8", category: "grafika", cat: "grafika", pl: "Plakaty i posty z gotowych szablonów, bez umiejętności graficznych.",
        tags: "plakat grafika social media szablony prezentacja", offline: "nie", account: "tak", cost: "freemium" },
    figma: { name: "Figma", url: "https://www.figma.com/", color: "#A259FF", category: "grafika", cat: "grafika", pl: "Projektowanie interfejsów, z pracą w zespole.",
        tags: "ui ux projektowanie interfejs", offline: "nie", account: "tak", cost: "freemium" },
    notion: { name: "Notion", url: "https://www.notion.so/", color: "#37352F", category: "biuro", cat: "biuro", pl: "Notatki, bazy i projekty w jednym miejscu.",
        tags: "notatki projekty", offline: "nie", account: "tak", cost: "freemium" },
    photopea: { name: "Photopea", url: "https://www.photopea.com/", color: "#18A497", category: "grafika", cat: "grafika", pl: "Edytor bardzo podobny do Photoshopa, wiernie otwiera pliki .psd.",
        tags: "photoshop psd zdjęcia edycja grafika", offline: "czesc", account: "nie", cost: "freemium", ads: true }
};

// Aplikacje Aster: są w systemie, a gdy ich brakuje, instalują się z paczki Flatpak (wydanie „aplikacje”)
var aster = {
    montaz: { name: "Montaż", id: "org.aster.montaz", exec: "aster-montaz", cat: "wideo", pl: "Montaż wideo Astera: szybkie cięcia, napisy i szablony, prosto od pierwszego uruchomienia.", tags: "film wideo montaż napisy youtube", offline: "tak", account: "nie", cost: "free" },
    grafika: { name: "Grafika", id: "org.aster.grafika", exec: "aster-grafika", cat: "grafika", pl: "Plakaty, posty i prezentacje z szablonów Astera.", tags: "plakat post grafika canva szablony", offline: "tak", account: "nie", cost: "free" },
    studio: { name: "Studio", id: "org.aster.studio", exec: "aster-studio", cat: "wideo", pl: "Proste studio muzyczne: nagraj, ułóż, zmiksuj piosenkę.", tags: "muzyka nagrywanie piosenka daw", offline: "tak", account: "nie", cost: "free" },
    code: { name: "Aster Code", id: "org.aster.code", exec: "aster-code", cat: "kod", pl: "Edytor kodu z asystentem, wbudowany w system.", tags: "edytor kod programowanie", offline: "tak", account: "nie", cost: "free" },
    editor: { name: "Edytor", id: "org.aster.editor", exec: "aster-editor", cat: "narzedzia", pl: "Notatnik: szybkie zapiski i zwykłe pliki tekstowe.", tags: "notatnik tekst notatki", offline: "tak", account: "nie", cost: "free" },
    pdf: { name: "PDF", id: "org.aster.pdf", exec: "aster-pdf", cat: "biuro", pl: "Czytanie i przeglądanie PDF-ów, wbudowane w Astera.", tags: "pdf czytnik", offline: "tak", account: "nie", cost: "free" },
    photos: { name: "Zdjęcia", id: "org.aster.photos", exec: "aster-photos", cat: "grafika", pl: "Przeglądanie i szybka poprawa zdjęć.", tags: "zdjęcia galeria", offline: "tak", account: "nie", cost: "free" },
    music: { name: "Muzyka", id: "org.aster.music", exec: "aster-music", cat: "wideo", pl: "Odtwarzacz Twojej muzyki z dysku.", tags: "muzyka mp3 odtwarzacz", offline: "tak", account: "nie", cost: "free" },
    video: { name: "Wideo", id: "org.aster.video", exec: "aster-video", cat: "wideo", pl: "Odtwarzacz filmów Astera.", tags: "film odtwarzacz wideo", offline: "tak", account: "nie", cost: "free" },
    vault: { name: "Vault", id: "org.aster.vault", exec: "aster-vault", cat: "kod", pl: "Klient baz danych dla programistów.", tags: "baza danych sql", offline: "czesc", account: "nie", cost: "free" },
    pulse: { name: "Pulse", id: "org.aster.pulse", exec: "aster-pulse", cat: "kod", pl: "Testowanie API bez zakładania konta.", tags: "api rest http postman", offline: "czesc", account: "nie", cost: "free" },
    harbor: { name: "Harbor", id: "org.aster.harbor", exec: "aster-harbor", cat: "kod", pl: "Kontenery i środowiska programistyczne w jednym oknie.", tags: "docker podman kontenery", offline: "czesc", account: "nie", cost: "free" },
    launch: { name: "Launch", id: "org.aster.launch", exec: "aster-launch", cat: "kod", pl: "Publikowanie projektów z komputera do internetu.", tags: "wdrożenie deploy serwer", offline: "nie", account: "opcja", cost: "free" }
};

// Zadania: sklep zaczyna się od tego, co chcesz zrobić. Każde to mały przewodnik redakcyjny.
// tone: odcień kafla (kąt barwy); picks: role opisują miejsce programu w zestawie; on: zaznaczone od razu
var tasks = [
    { id: "ai", title: "Porozmawiać z AI", hue: 255, icon: "sparkle",
      lede: "Asystent w osobnym oknie, bez instalowania, albo pełna aplikacja. Modele na własnym komputerze wymagają dużo pamięci.",
      tags: "ai chat claude chatgpt gemini asystent sztuczna inteligencja zapytać",
      picks: [ { ref: "get:claude-desktop", role: "Pełna aplikacja", why: "Czat, Cowork i Claude Code w jednym oknie.", on: false },
               { ref: "web:chatgpt", role: "W przeglądarce", why: "Najpopularniejszy asystent, bez instalowania.", on: true },
               { ref: "web:gemini", role: "W przeglądarce", why: "Dobrze łączy się z kontem Google.", on: false },
               { ref: "ai.lmstudio.lm-studio", role: "Bez chmury", why: "Modele działają na Twoim komputerze.", on: false } ] },
    { id: "film", title: "Zmontować film", hue: 350, icon: "clapper",
      lede: "Wakacje, film na YouTube, praca na zaliczenie. Do krótkich rzeczy wystarczy wbudowany Montaż, do dłuższych Kdenlive.",
      tags: "film wideo montaż wakacje youtube tiktok napisy klip zmontować przytnij",
      picks: [ { ref: "aster:montaz", role: "Już masz", why: "Wystarczy na filmy z telefonu, napisy i krótkie klipy.", on: false },
               { ref: "org.kde.kdenlive", role: "Najlepszy wybór", why: "Pełny montaż na wielu ścieżkach, bez znaków wodnych.", on: true },
               { ref: "org.shotcut.Shotcut", role: "Prostszy", why: "Mniej przycisków, łatwiej zacząć.", on: false },
               { ref: "fr.handbrake.ghb", role: "Dodatek", why: "Zmniejszy gotowy film, żeby dało się go wysłać.", on: false },
               { ref: "org.audacityteam.Audacity", role: "Dodatek", why: "Oczyści dźwięk i nagra lektora.", on: false } ] },
    { id: "zdjecia", title: "Poprawić zdjęcia", hue: 28, icon: "image",
      lede: "Do zwykłego poprawiania wystarczy to, co masz. Warstwy i retusz daje GIMP, a RAW z aparatu darktable.",
      tags: "zdjęcia fotka obróbka retusz photoshop lightroom raw aparat poprawić kolory tło wytnij",
      picks: [ { ref: "aster:photos", role: "Już masz", why: "Przycinanie, jasność i kolory.", on: false },
               { ref: "org.gimp.GIMP", role: "Najlepszy wybór", why: "Warstwy, maski i retusz jak w programach płatnych.", on: true },
               { ref: "web:photopea", role: "W przeglądarce", why: "Najwierniej otwiera pliki .psd.", on: false },
               { ref: "org.darktable.Darktable", role: "Do RAW", why: "Gdy robisz zdjęcia aparatem, nie telefonem.", on: false },
               { ref: "org.kde.digikam", role: "Do porządków", why: "Gdy masz tysiące zdjęć i szukasz twarzy.", on: false } ] },
    { id: "rysowanie", title: "Rysować i projektować", hue: 300, icon: "brush",
      lede: "Malowanie na tablecie, logo do druku, plakat na szybko. Każde z tych zadań ma inny najlepszy program.",
      tags: "rysować rysowanie malowanie tablet logo plakat ilustracja wektor grafika projektować",
      picks: [ { ref: "org.kde.krita", role: "Do malowania", why: "Najlepsze pędzle i obsługa tabletów.", on: true },
               { ref: "org.inkscape.Inkscape", role: "Do logo i druku", why: "Wektory skalują się do każdego rozmiaru.", on: false },
               { ref: "aster:grafika", role: "Już masz", why: "Plakaty i posty z szablonów.", on: false },
               { ref: "web:canva", role: "W przeglądarce", why: "Gdy liczy się szablon i szybkość, a nie swoboda.", on: false },
               { ref: "org.blender.Blender", role: "Do 3D", why: "Modele i animacja, wymaga mocnego komputera.", on: false } ] },
    { id: "dokumenty", title: "Pisać dokumenty", hue: 215, icon: "doc",
      lede: "Word, Excel i PowerPoint mają dobre zamienniki. Jeśli Twoje pliki są skomplikowane, zostań przy prawdziwym Office w oknie przeglądarki.",
      tags: "dokument word excel powerpoint pisać tekst arkusz prezentacja praca office docx faktura cv",
      picks: [ { ref: "org.libreoffice.LibreOffice", role: "Najlepszy wybór", why: "Wszystko w jednym, bez internetu i bez opłat.", on: true },
               { ref: "org.onlyoffice.desktopeditors", role: "Najbliżej Office", why: "Znajomy układ, wierny przy .docx, ale cięższy.", on: false },
               { ref: "web:word", role: "Oryginał", why: "Prawdziwy Word, gdy formatowanie musi się zgadzać co do piksela.", on: false },
               { ref: "web:excel", role: "Oryginał", why: "Prawdziwy Excel, także dla plików z OneDrive.", on: false } ] },
    { id: "szkola", title: "Uczyć się", hue: 150, icon: "book",
      lede: "Zestaw do szkoły i na studia: dokumenty, fiszki, notatki i bibliografia do pracy.",
      tags: "szkoła nauka studia lekcje uczeń student fiszki notatki praca licencjacka matura",
      picks: [ { ref: "org.libreoffice.LibreOffice", role: "Dokumenty", why: "Referaty, arkusze i prezentacje.", on: true },
               { ref: "net.ankiweb.Anki", role: "Fiszki", why: "Pilnuje powtórek, sprawdzone na językach i na medycynie.", on: true },
               { ref: "com.github.xournalpp.xournalpp", role: "Notatki", why: "Pisanie po PDF-ach i odręczne notatki.", on: false },
               { ref: "org.zotero.Zotero", role: "Na studia", why: "Sam układa bibliografię.", on: false },
               { ref: "org.kde.gcompris", role: "Dla dzieci", why: "Gry edukacyjne dla najmłodszych.", on: false },
               { ref: "web:teams", role: "Lekcje online", why: "Gdy szkoła pracuje w Teams.", on: false } ] },
    { id: "gry", title: "Grać", hue: 265, icon: "game",
      lede: "Większość gier z Windowsa działa. Zacznij od Steama, a Heroic odda Ci biblioteki z Epica i GOG-a.",
      tags: "gry grać granie steam epic gog proton minecraft fortnite wiedźmin cyberpunk",
      picks: [ { ref: "com.valvesoftware.Steam", role: "Najlepszy wybór", why: "Proton uruchamia gry z Windowsa bez konfiguracji.", on: true },
               { ref: "com.heroicgameslauncher.hgl", role: "Epic i GOG", why: "Twoje biblioteki spoza Steama.", on: false },
               { ref: "net.lutris.Lutris", role: "Reszta", why: "Battle.net i inne launchery.", on: false },
               { ref: "org.prismlauncher.PrismLauncher", role: "Minecraft", why: "Mody i wiele wersji naraz.", on: false },
               { ref: "net.supertuxkart.SuperTuxKart", role: "Za darmo", why: "Wyścigi na kanapie, także dla dzieci.", on: false } ] },
    { id: "rozmowy", title: "Być w kontakcie", hue: 195, icon: "send",
      lede: "Większość komunikatorów najlżej działa w osobnym oknie przeglądarki. Oddzielny program ma sens tam, gdzie jest naprawdę natywny.",
      tags: "rozmowy komunikator czat whatsapp messenger discord telegram signal wideo spotkania teams zoom",
      picks: [ { ref: "web:whatsapp", role: "W przeglądarce", why: "Bez miejsca na dysku, z powiadomieniami.", on: true },
               { ref: "web:messenger", role: "W przeglądarce", why: "Wiadomości bez otwierania Facebooka.", on: false },
               { ref: "web:discord", role: "Lżejszy", why: "Ten sam Discord, bez osobnego programu na dysku.", on: false },
               { ref: "org.telegram.desktop", role: "Natywny", why: "Lekki, szybki, prawdziwy program.", on: false },
               { ref: "org.signal.Signal", role: "Prywatny", why: "Najlepsze szyfrowanie.", on: false },
               { ref: "web:teams", role: "Do pracy", why: "Spotkania i czaty firmowe.", on: false } ] },
    { id: "poczta", title: "Ogarnąć pocztę", hue: 45, icon: "mail",
      lede: "Jeden program na wszystkie skrzynki albo poczta w oknie, które wygląda jak aplikacja.",
      tags: "poczta mail email outlook gmail kalendarz skrzynka",
      picks: [ { ref: "org.mozilla.thunderbird", role: "Najlepszy wybór", why: "Wszystkie skrzynki w jednym miejscu, także bez internetu.", on: true },
               { ref: "web:outlook", role: "Oryginał", why: "Jeśli masz pocztę Microsoftu i chcesz mieć wszystko jak dawniej.", on: false },
               { ref: "web:gmail", role: "Oryginał", why: "Gmail w osobnym oknie.", on: false } ] },
    { id: "muzyka", title: "Tworzyć muzykę", hue: 330, icon: "music",
      lede: "Od pierwszej piosenki po miks. Studio Astera wystarczy na start, a Ardour to prawdziwe studio.",
      tags: "muzyka tworzyć nagrać piosenka bit produkcja mikrofon podcast nuty",
      picks: [ { ref: "aster:studio", role: "Już masz", why: "Nagraj, ułóż i zmiksuj bez nauki.", on: false },
               { ref: "org.audacityteam.Audacity", role: "Nagrywanie", why: "Podcast, wokal, przycinanie dźwięku.", on: true },
               { ref: "org.ardour.Ardour", role: "Mocniejszy", why: "Wiele ścieżek, wtyczki, prawdziwy miks.", on: false },
               { ref: "org.musescore.MuseScore", role: "Nuty", why: "Partytury z odsłuchem.", on: false } ] },
    { id: "ogladanie", title: "Oglądać i słuchać", hue: 240, icon: "play",
      lede: "Filmy z dysku, muzyka ze Spotify albo z własnej kolekcji.",
      tags: "oglądać filmy muzyka słuchać spotify vlc youtube serial odtwarzacz",
      picks: [ { ref: "org.videolan.VLC", role: "Najlepszy wybór", why: "Otwiera każdy format.", on: true },
               { ref: "web:spotify", role: "Lżejszy", why: "Spotify bez instalowania programu.", on: false },
               { ref: "com.spotify.Client", role: "Pełny program", why: "Gdy chcesz muzyki offline w Premium.", on: false },
               { ref: "web:youtube", role: "W przeglądarce", why: "YouTube jako osobne okno.", on: false },
               { ref: "org.strawberrymusicplayer.strawberry", role: "Własna muzyka", why: "Dla kolekcji MP3 i FLAC.", on: false } ] },
    { id: "nagrywanie", title: "Nagrywać ekran", hue: 10, icon: "camera",
      lede: "Poradnik, gra albo prezentacja. OBS nagrywa wszystko, bez znaków wodnych i limitów.",
      tags: "nagrać nagrywanie ekranu ekran stream transmisja poradnik zrzut twitch",
      picks: [ { ref: "com.obsproject.Studio", role: "Najlepszy wybór", why: "Standard: nagrywanie i transmisje.", on: true },
               { ref: "org.flameshot.Flameshot", role: "Zrzuty", why: "Szybki zrzut ze strzałkami.", on: false } ] },
    { id: "programowanie", title: "Programować", hue: 175, icon: "code",
      lede: "Edytor kodu masz już w systemie. Jeśli pracujesz w zespole z rozszerzeniami VS Code, weź VSCodium.",
      tags: "programowanie kod python javascript java edytor ide git terminal",
      picks: [ { ref: "aster:code", role: "Już masz", why: "Edytor z asystentem, wbudowany w system.", on: false },
               { ref: "get:claude-code", role: "Agent AI", why: "Claude pisze i poprawia kod w Twoim terminalu.", on: false },
               { ref: "get:cursor", role: "Edytor z AI", why: "Najpopularniejszy edytor zbudowany wokół AI.", on: false },
               { ref: "com.vscodium.codium", role: "Najlepszy wybór", why: "VS Code bez telemetrii Microsoftu.", on: true },
               { ref: "com.visualstudio.code", role: "Oryginał", why: "Gdy potrzebujesz rozszerzeń tylko od Microsoftu.", on: false },
               { ref: "com.jetbrains.IntelliJ-IDEA-Community", role: "Java", why: "Najmocniejsze do Javy i Kotlina.", on: false } ] },
    { id: "pdf", title: "Pracować z PDF", hue: 0, icon: "doc",
      lede: "Czytanie masz w systemie. Do podpisów, notatek i układania stron są lepsze, wyspecjalizowane narzędzia.",
      tags: "pdf podpis podpisać połączyć scalić strony wypełnić adobe acrobat",
      picks: [ { ref: "aster:pdf", role: "Już masz", why: "Czytanie i przeglądanie.", on: false },
               { ref: "org.kde.okular", role: "Podpisy i notatki", why: "Wypełnianie, komentarze, podpis.", on: true },
               { ref: "com.github.jeromerobert.pdfarranger", role: "Układanie stron", why: "Łączenie, dzielenie, obracanie.", on: true },
               { ref: "com.github.xournalpp.xournalpp", role: "Pisanie po PDF", why: "Odręczne notatki rysikiem.", on: false } ] },
    { id: "bezpieczenstwo", title: "Zadbać o bezpieczeństwo", hue: 130, icon: "shield",
      lede: "Trzy rzeczy, które robią największą różnicę: menedżer haseł, kopie zapasowe i szyfrowanie tego, co trafia do chmury.",
      tags: "bezpieczeństwo hasła kopia zapasowa backup szyfrowanie prywatność vpn",
      picks: [ { ref: "org.keepassxc.KeePassXC", role: "Hasła bez chmury", why: "Zaszyfrowany plik, który należy do Ciebie.", on: true },
               { ref: "com.bitwarden.desktop", role: "Hasła z synchronizacją", why: "Na telefonie i komputerze.", on: false },
               { ref: "org.gnome.DejaDup", role: "Kopie zapasowe", why: "Ustawiasz raz i robi się samo.", on: true },
               { ref: "org.cryptomator.Cryptomator", role: "Szyfrowanie", why: "Chmura widzi tylko szyfr.", on: false } ] },
    { id: "pliki", title: "Przenieść pliki", hue: 200, icon: "upload",
      lede: "Z telefonu na komputer, do chmury albo ze starego archiwum.",
      tags: "pliki przenieść telefon chmura zip rar rozpakować dysk synchronizacja",
      picks: [ { ref: "org.localsend.localsend_app", role: "Z telefonu", why: "Po Wi-Fi, bez kabla i bez konta.", on: true },
               { ref: "io.github.peazip.PeaZip", role: "Archiwa", why: "Rozpakuje też .rar i .7z.", on: false },
               { ref: "com.nextcloud.desktopclient.nextcloud", role: "Chmura", why: "Jeśli masz własnego Nextclouda.", on: false },
               { ref: "com.dropbox.Client", role: "Chmura", why: "Oficjalny Dropbox.", on: false } ] },
    { id: "windows", title: "Uruchomić program .exe", hue: 225, icon: "windows",
      lede: "Zanim sięgniesz po .exe, sprawdź, czy nie ma odpowiednika w katalogu. Gdy naprawdę trzeba, Bottles uruchomi wiele programów z Windowsa.",
      tags: "exe windows wine program z windowsa uruchomić instalator msi",
      picks: [ { ref: "com.usebottles.bottles", role: "Najlepszy wybór", why: "Każdy program w osobnym, bezpiecznym środowisku.", on: true },
               { ref: "com.valvesoftware.Steam", role: "Gry", why: "Do gier Proton działa lepiej niż Bottles.", on: false } ] }
];

// Przesiadka z Windowsa: program → czym go zastąpić i co naprawdę stanie się z Twoimi plikami.
// keep: oryginał, który można zachować (zwykle webowy); files: uczciwa informacja o plikach
var windows = [
    { group: "Biuro", name: "Word", pick: "org.libreoffice.LibreOffice", keep: "web:word", files: "Pliki .docx otworzysz od razu. Rozbudowane szablony mogą się przesunąć." },
    { group: "Biuro", name: "Excel", pick: "org.libreoffice.LibreOffice", keep: "web:excel", files: "Pliki .xlsx działają. Makra VBA trzeba sprawdzić, część nie zadziała." },
    { group: "Biuro", name: "PowerPoint", pick: "org.libreoffice.LibreOffice", keep: "web:powerpoint", files: "Prezentacje się otworzą. Animacje i czcionki warto obejrzeć przed pokazem." },
    { group: "Biuro", name: "OneNote", pick: "net.cozic.joplin_desktop", files: "Notatek z OneNote nie przeniesiesz jednym kliknięciem." },
    { group: "Biuro", name: "Outlook", pick: "org.mozilla.thunderbird", keep: "web:outlook", files: "Konto dodasz w kilka minut, poczta zostaje na serwerze." },
    { group: "Biuro", name: "Teams", pick: "web:teams", files: "To ten sam Teams, w osobnym oknie." },
    { group: "Biuro", name: "Adobe Reader", pick: "aster:pdf", alt: "org.kde.okular", files: "PDF-y działają od razu, także formularze." },
    { group: "Biuro", name: "Notatnik", pick: "aster:editor", alt: "org.kde.kate", files: "Pliki .txt działają bez zmian." },

    { group: "Grafika", name: "Photoshop", pick: "org.gimp.GIMP", keep: "web:photopea", files: "GIMP otworzy .psd, ale efekty warstw i inteligentne obiekty mogą się spłaszczyć. Photopea radzi sobie z nimi lepiej." },
    { group: "Grafika", name: "Lightroom", pick: "org.darktable.Darktable", files: "Pliki RAW działają. Twoich ustawień z Lightrooma nie przeniesiesz w całości." },
    { group: "Grafika", name: "Illustrator", pick: "org.inkscape.Inkscape", files: "Eksportuj z Illustratora do SVG. Pliki .ai otworzą się częściowo." },
    { group: "Grafika", name: "CorelDRAW", pick: "org.inkscape.Inkscape", files: "Pliki .cdr otwierają się częściowo, eksport do SVG działa pewniej." },
    { group: "Grafika", name: "Paint", pick: "org.kde.kolourpaint", files: "Obrazki działają bez zmian." },
    { group: "Grafika", name: "Canva", pick: "web:canva", files: "To ta sama Canva, Twoje projekty są na koncie." },
    { group: "Grafika", name: "AutoCAD", pick: "org.freecad.FreeCAD", files: "Pliki .dwg nie są w pełni obsługiwane. Tu bez AutoCADa będzie ciężko." },

    { group: "Wideo i dźwięk", name: "Premiere Pro", pick: "org.kde.kdenlive", files: "Projektów .prproj nie otworzysz. Materiały wideo działają normalnie." },
    { group: "Wideo i dźwięk", name: "CapCut / Clipchamp", pick: "aster:montaz", alt: "org.kde.kdenlive", files: "Projekty zostają w tamtych programach, nagrania działają." },
    { group: "Wideo i dźwięk", name: "Filmy i TV", pick: "org.videolan.VLC", files: "Wszystkie filmy działają." },
    { group: "Wideo i dźwięk", name: "Spotify", pick: "web:spotify", alt: "com.spotify.Client", files: "To Twoje konto i Twoje playlisty." },
    { group: "Wideo i dźwięk", name: "FL Studio", pick: "org.ardour.Ardour", files: "Projektów .flp nie otworzysz. Wtyczki z Windowsa zwykle nie działają." },
    { group: "Wideo i dźwięk", name: "OBS Studio", pick: "com.obsproject.Studio", files: "Ten sam program, ustawienia wyeksportujesz z profilu." },

    { group: "Internet", name: "Chrome", pick: "com.google.Chrome", files: "Zaloguj się na konto Google, a zakładki i hasła wrócą." },
    { group: "Internet", name: "Edge", pick: "com.microsoft.Edge", files: "Zaloguj się na konto Microsoft, a zakładki i hasła wrócą." },
    { group: "Internet", name: "WhatsApp", pick: "web:whatsapp", files: "Twoje czaty pojawią się po zeskanowaniu kodu telefonem." },
    { group: "Internet", name: "Messenger", pick: "web:messenger", files: "To Twoje konto i Twoje rozmowy." },
    { group: "Internet", name: "Discord", pick: "web:discord", alt: "com.discordapp.Discord", files: "To Twoje konto i Twoje serwery." },
    { group: "Internet", name: "Zoom", pick: "us.zoom.Zoom", files: "Dołączasz do spotkań tak samo, linkiem." },
    { group: "Internet", name: "TeamViewer", pick: "com.rustdesk.RustDesk", files: "Druga strona też musi mieć RustDeska." },

    { group: "Narzędzia", name: "WinRAR / 7-Zip", pick: "io.github.peazip.PeaZip", files: "Otworzy .zip, .rar i .7z." },
    { group: "Narzędzia", name: "Notepad++", pick: "org.kde.kate", files: "Pliki tekstowe działają bez zmian." },
    { group: "Narzędzia", name: "Visual Studio Code", pick: "com.vscodium.codium", files: "Rozszerzenia zainstalujesz ponownie, większość jest dostępna." },
    { group: "Narzędzia", name: "Narzędzie Wycinanie", pick: "org.flameshot.Flameshot", files: "Zrzuty zapisują się jako zwykłe obrazki." },
    { group: "Narzędzia", name: "OneDrive", pick: "web:word", files: "Pliki znajdziesz po zalogowaniu w Wordzie w przeglądarce. Synchronizacji folderu nie ma." },

    { group: "Gry", name: "Steam", pick: "com.valvesoftware.Steam", files: "Twoje gry są na koncie. Większość działa, kilka tytułów z antycheatem nie." },
    { group: "Gry", name: "Epic Games", pick: "com.heroicgameslauncher.hgl", files: "Zaloguj się, gry pobiorą się ponownie." },
    { group: "Gry", name: "GOG Galaxy", pick: "com.heroicgameslauncher.hgl", files: "Zaloguj się, gry pobiorą się ponownie." },
    { group: "Gry", name: "Minecraft", pick: "org.prismlauncher.PrismLauncher", files: "Światy skopiujesz z folderu .minecraft. Wersja Bedrock nie działa, tylko Java." }
];

// ——— Szeroki katalog: to, czego ludzie naprawdę szukają ———
// [nasz opis, słowa do szukania, fakty]
function more(cat, table) {
    for (var id in table) {
        var row = table[id], extra = row[2] || {};
        var entry = { cat: cat, pl: row[0], tags: row[1] || "" };
        for (var k in extra) entry[k] = extra[k];
        if (!apps[id]) apps[id] = entry;
    }
}
var FREE = { account: "nie", cost: "free" };

more("internet", {
    "app.zen_browser.zen": ["Spokojna przeglądarka z kartami z boku, oparta na Firefoksie.", "przeglądarka internet arc firefox", FREE],
    "io.gitlab.librewolf-community": ["Firefox nastawiony na prywatność, bez telemetrii.", "przeglądarka prywatność firefox", FREE],
    "org.chromium.Chromium": ["Otwarta podstawa Chrome, bez usług Google.", "przeglądarka chrome", FREE],
    "com.vivaldi.Vivaldi": ["Przeglądarka dla lubiących ustawiać wszystko po swojemu.", "przeglądarka chrome", { cost: "free" }],
    "com.opera.Opera": ["Opera z darmowym VPN-em przeglądarkowym.", "przeglądarka vpn", { cost: "free" }],
    "com.opera.opera-gx": ["Przeglądarka dla graczy z limitem użycia pamięci.", "przeglądarka gry gx", { cost: "free" }],
    "net.waterfox.waterfox": ["Niezależna przeglądarka oparta na Firefoksie.", "przeglądarka firefox", FREE],
    "one.ablaze.floorp": ["Firefox z dużą ilością ustawień wyglądu.", "przeglądarka firefox", FREE],
    "net.mullvad.MullvadBrowser": ["Przeglądarka maksymalnie utrudniająca śledzenie.", "przeglądarka prywatność", FREE],
    "io.github.ungoogled_software.ungoogled_chromium": ["Chromium bez powiązań z Google.", "przeglądarka chrome prywatność", FREE],
    "org.torproject.torbrowser-launcher": ["Instaluje Tor Browser do anonimowego przeglądania.", "tor anonimowość darknet", FREE],
    "org.freedownloadmanager.Manager": ["Menedżer pobierania z wznawianiem plików.", "pobieranie idm download", { cost: "free" }],
    "org.jdownloader.JDownloader": ["Pobieranie z serwisów z plikami, wiele naraz.", "pobieranie download", { cost: "free" }],
    "com.transmissionbt.Transmission": ["Prosty, lekki klient torrentów.", "torrent pobieranie", FREE],
    "org.kde.ktorrent": ["Klient torrentów z KDE, z wtyczkami.", "torrent pobieranie", FREE]
});
more("rozmowy", {
    "dev.vencord.Vesktop": ["Discord z lepszym udostępnianiem ekranu i dźwięku na Linuksie.", "discord vencord czat", { account: "tak", heavy: 2 }],
    "com.rtosta.zapzap": ["WhatsApp w osobnym oknie, z ikoną w zasobniku.", "whatsapp czat", { account: "tak", cost: "free", offline: "nie" }],
    "com.github.IsmaelMartinez.teams_for_linux": ["Microsoft Teams jako program, nieoficjalny, ale popularny.", "teams microsoft spotkania", { account: "tak", offline: "nie" }],
    "im.riot.Riot": ["Komunikator sieci Matrix, szyfrowany i niezależny.", "matrix czat element", { account: "tak", cost: "free", offline: "nie" }],
    "com.viber.Viber": ["Rozmowy i wiadomości Viber na komputerze.", "czat rozmowy telefon", { account: "tak", cost: "free", offline: "nie" }],
    "com.tencent.WeChat": ["WeChat, główny komunikator w Chinach.", "czat chiny", { account: "tak", offline: "nie" }],
    "me.proton.Mail": ["Szyfrowana poczta Proton jako program.", "poczta mail szyfrowanie", { account: "tak", cost: "freemium" }],
    "com.getmailspring.Mailspring": ["Ładny program pocztowy z kontem opcjonalnie.", "poczta mail", { account: "tak", cost: "freemium" }],
    "com.tutanota.Tutanota": ["Szyfrowana poczta i kalendarz Tuta.", "poczta mail szyfrowanie", { account: "tak", cost: "freemium" }],
    "org.gnome.Evolution": ["Poczta, kalendarz i zadania, dobrze działa z Exchange.", "poczta exchange outlook", FREE]
});
more("filmy", {
    "com.stremio.Stremio": ["Filmy i seriale z dodatków w jednym wyszukiwarce.", "filmy seriale streaming", { account: "opcja", cost: "free" }],
    "io.freetubeapp.FreeTube": ["YouTube bez reklam i bez śledzenia.", "youtube filmy bez reklam", FREE],
    "rocks.shy.VacuumTube": ["YouTube w wygodnym widoku jak na telewizorze.", "youtube tv", FREE],
    "org.jellyfin.JellyfinDesktop": ["Twoje własne Netflix: filmy z domowego serwera.", "jellyfin serwer media", { cost: "free" }],
    "tv.plex.PlexDesktop": ["Filmy z domowego serwera Plex i darmowa telewizja.", "plex serwer media", { account: "tak", cost: "freemium" }],
    "org.kde.haruna": ["Przyjemny odtwarzacz wideo z KDE.", "odtwarzacz film", FREE],
    "io.github.celluloid_player.Celluloid": ["Prosta nakładka na mpv.", "odtwarzacz film", FREE],
    "com.makemkv.MakeMKV": ["Zgrywa filmy z płyt DVD i Blu-ray.", "dvd blu-ray zgrywanie", { cost: "freemium" }],
    "org.nickvision.tubeconverter": ["Pobiera filmy i muzykę z YouTube i innych stron.", "pobieranie youtube mp3 yt-dlp", FREE]
});
more("muzyka", {
    "com.mastermindzh.tidal-hifi": ["Tidal jako program, z jakością hi-fi.", "tidal streaming", { account: "tak", cost: "paid" }],
    "com.plexamp.Plexamp": ["Muzyka z Twojego serwera Plex.", "plex muzyka", { account: "tak", cost: "freemium" }],
    "de.haeckerfelix.Shortwave": ["Radia internetowe z całego świata.", "radio internetowe", FREE],
    "org.mixxx.Mixxx": ["Darmowy program dla DJ-ów.", "dj miksowanie virtual dj serato", FREE],
    "fm.reaper.Reaper": ["Tanie, profesjonalne studio nagraniowe.", "daw nagrywanie studio", { cost: "paid" }],
    "com.bitwig.BitwigStudio": ["Nowoczesna produkcja muzyki, podobna do Abletona.", "daw ableton produkcja", { cost: "paid" }],
    "org.tenacityaudio.Tenacity": ["Audacity bez telemetrii.", "audio nagrywanie", FREE],
    "org.musicbrainz.Picard": ["Porządkuje tagi w kolekcji MP3.", "tagi mp3 kolekcja", FREE],
    "org.gnome.Rhythmbox3": ["Klasyczny odtwarzacz muzyki.", "muzyka odtwarzacz", FREE]
});
more("biuro", {
    "com.wps.Office": ["Pakiet biurowy bardzo podobny do Microsoft Office.", "office word excel", { cost: "freemium" }],
    "com.collaboraoffice.Office": ["LibreOffice w nowocześniejszym wydaniu.", "office dokument", FREE],
    "com.logseq.Logseq": ["Notatki połączone w sieć pomysłów.", "notatki wiedza roam", { cost: "free" }],
    "com.adobe.Reader": ["Prawdziwy Adobe Reader, stary, ale działa.", "pdf adobe", { cost: "free" }],
    "com.todoist.Todoist": ["Popularna lista zadań na wszystkie urządzenia.", "zadania todo", { account: "tak", cost: "freemium" }],
    "com.ticktick.TickTick": ["Zadania, kalendarz i nawyki.", "zadania todo", { account: "tak", cost: "freemium" }],
    "org.gnucash.GnuCash": ["Księgowość domowa i małej firmy.", "finanse budżet księgowość", FREE],
    "org.geogebra.GeoGebra": ["Matematyka: wykresy, geometria, algebra.", "matematyka szkoła wykresy", { cost: "free" }]
});
more("grafika", {
    "com.bambulab.BambuStudio": ["Przygotowanie wydruków na drukarki Bambu Lab.", "druk 3d drukarka slicer", FREE],
    "com.orcaslicer.OrcaSlicer": ["Slicer do wielu drukarek 3D.", "druk 3d drukarka slicer", FREE],
    "com.prusa3d.PrusaSlicer": ["Slicer od Prusa Research.", "druk 3d drukarka prusa", FREE],
    "com.ultimaker.cura": ["Popularny slicer do drukarek 3D.", "druk 3d drukarka", FREE],
    "com.xnview.XnViewMP": ["Przeglądarka i konwerter zdjęć, także masowo.", "zdjęcia konwersja irfanview", { cost: "free" }],
    "com.jgraph.drawio.desktop": ["Schematy i diagramy bez internetu.", "diagram schemat visio", FREE],
    "org.upscayl.Upscayl": ["Powiększa zdjęcia dzięki AI, na Twoim komputerze.", "ai zdjęcia powiększanie", FREE],
    "org.kicad.KiCad": ["Projektowanie płytek elektronicznych.", "elektronika pcb", FREE],
    "org.godotengine.Godot": ["Silnik do tworzenia własnych gier.", "gry tworzenie silnik", FREE],
    "com.unity.UnityHub": ["Silnik Unity do tworzenia gier.", "gry tworzenie silnik", { account: "tak", cost: "freemium", heavy: 2 }],
    "com.google.EarthPro": ["Google Earth na komputerze.", "mapy ziemia google", { cost: "free" }]
});
more("wideo", {
    "no.mifi.losslesscut": ["Tnie filmy bez utraty jakości i w kilka sekund.", "cięcie wideo", FREE],
    "com.dec05eba.gpu_screen_recorder": ["Nagrywanie ekranu i gier prawie bez obciążenia.", "nagrywanie ekran gry shadowplay", FREE],
    "org.gnome.gitlab.YaLTeR.VideoTrimmer": ["Szybkie przycięcie filmu, nic więcej.", "przytnij wideo", FREE]
});
more("ai", {
    "ai.lmstudio.lm-studio": ["Modele AI na własnym komputerze, w wygodnym oknie.", "ai llm model lokalny chat", { offline: "tak", account: "nie", cost: "free", heavy: 2 }],
    "ai.jan.Jan": ["Otwarty asystent AI działający lokalnie.", "ai llm lokalny chat", { offline: "tak", account: "nie", cost: "free", heavy: 2 }],
    "com.jeffser.Alpaca": ["Rozmowy z lokalnymi modelami, proste jak czat.", "ai ollama lokalny", { offline: "tak", account: "nie", cost: "free", heavy: 2 }],
    "ai.opencode.opencode": ["Otwarty agent AI do programowania.", "ai kod agent", { cost: "free" }],
    "net.sapples.LiveCaptions": ["Napisy na żywo do wszystkiego, co gra na komputerze.", "napisy transkrypcja", { offline: "tak", account: "nie", cost: "free" }]
});
more("gry", {
    "org.vinegarhq.Sober": ["Roblox na Linuksie, wersja, której używa większość graczy.", "roblox gry", { account: "tak", heavy: 1 }],
    "org.vinegarhq.Vinegar": ["Roblox Studio do tworzenia własnych światów.", "roblox studio", { account: "tak", cost: "free" }],
    "io.github.Faugus.faugus-launcher": ["Prosty sposób na gry .exe spoza Steama.", "launcher proton gry", FREE],
    "ru.linux_gaming.PortProton": ["Gry i launchery z Windowsa jednym kliknięciem.", "launcher proton gry epic", FREE],
    "com.modrinth.ModrinthApp": ["Minecraft z modami z serwisu Modrinth.", "minecraft mody", { account: "tak", cost: "free" }],
    "com.overwolf.curseforge": ["Mody do Minecrafta i innych gier z CurseForge.", "minecraft mody", { account: "opcja", cost: "free" }],
    "io.mrarm.mcpelauncher": ["Minecraft Bedrock na Linuksie.", "minecraft bedrock", { account: "tak", cost: "paid" }],
    "com.lunarclient.LunarClient": ["Klient Minecrafta do PvP, z lepszą wydajnością.", "minecraft pvp", { account: "tak", cost: "free" }],
    "io.itch.itch": ["Tysiące gier niezależnych, wiele za darmo.", "gry indie", { account: "opcja", cost: "free" }],
    "com.moonlight_stream.Moonlight": ["Gra z mocnego komputera strumieniowana na ten.", "strumieniowanie nvidia sunshine", FREE],
    "dev.lizardbyte.app.Sunshine": ["Serwer do strumieniowania gier na inne urządzenia.", "strumieniowanie moonlight", FREE],
    "com.valvesoftware.SteamLink": ["Gry z Twojego komputera ze Steamem, przez sieć.", "steam strumieniowanie", { account: "tak", cost: "free" }],
    "com.parsecgaming.parsec": ["Granie zdalne ze znajomymi, także na jednym komputerze.", "zdalne granie", { account: "tak", cost: "freemium" }],
    "io.github.streetpea.Chiaki4deck": ["Zdalne granie na PlayStation 4 i 5.", "playstation ps5 remote play", { cost: "free" }],
    "org.DolphinEmu.dolphin-emu": ["Gry z GameCube i Wii.", "emulator nintendo wii", FREE],
    "net.pcsx2.PCSX2": ["Gry z PlayStation 2.", "emulator ps2 playstation", FREE],
    "net.rpcs3.RPCS3": ["Gry z PlayStation 3, potrzebny mocny komputer.", "emulator ps3 playstation", { account: "nie", cost: "free", heavy: 2 }],
    "org.ppsspp.PPSSPP": ["Gry z PSP, działa nawet na starym sprzęcie.", "emulator psp playstation", FREE],
    "info.cemu.Cemu": ["Gry z Wii U.", "emulator nintendo wii u", FREE],
    "io.github.ryubing.Ryujinx": ["Gry z Nintendo Switch.", "emulator switch nintendo", FREE],
    "dev.eden_emu.eden": ["Drugi emulator Nintendo Switch.", "emulator switch nintendo", FREE],
    "app.xemu.xemu": ["Gry z pierwszego Xboksa.", "emulator xbox", FREE],
    "net.kuribo64.melonDS": ["Gry z Nintendo DS.", "emulator nds nintendo", FREE],
    "io.mgba.mGBA": ["Gry z Game Boya Advance.", "emulator gba nintendo", FREE],
    "org.azahar_emu.Azahar": ["Gry z Nintendo 3DS.", "emulator 3ds nintendo", FREE],
    "org.flycast.Flycast": ["Gry z Dreamcasta.", "emulator sega dreamcast", FREE],
    "org.scummvm.ScummVM": ["Klasyczne gry przygodowe na nowym komputerze.", "retro przygodówki", FREE],
    "net.retrodeck.retrodeck": ["Wszystkie stare konsole w jednej aplikacji.", "emulator retro", FREE],
    "com.fightcade.Fightcade": ["Klasyczne bijatyki przez internet.", "bijatyki arcade", { account: "tak", cost: "free" }],
    "net.davidotek.pupgui2": ["Doinstalowuje nowsze wersje Protona.", "proton ge wine gry", FREE],
    "com.vysp3r.ProtonPlus": ["Prosty menedżer wersji Protona.", "proton wine gry", FREE],
    "com.github.Matoking.protontricks": ["Naprawianie gier ze Steama, które nie chcą ruszyć.", "proton winetricks", FREE],
    "io.github.benjamimgois.goverlay": ["Licznik klatek i temperatur w grach.", "mangohud fps nakładka msi afterburner", FREE],
    "org.openrgb.OpenRGB": ["Podświetlenie RGB wszystkich urządzeń w jednym miejscu.", "rgb led razer corsair", FREE],
    "io.github.ilya_zlobintsev.LACT": ["Ustawienia i podkręcanie karty graficznej.", "gpu karta graficzna amd nvidia", FREE],
    "sh.ppy.osu": ["Rytmiczna klasyka, darmowa.", "gra rytm", { account: "opcja", cost: "free" }],
    "com.github.k4zmu2a.spacecadetpinball": ["Pinball znany z Windows XP.", "gra pinball xp", FREE],
    "com.play0ad.zeroad": ["Darmowa strategia jak Age of Empires.", "gra strategia aoe", FREE],
    "com.github.Anuken.Mindustry": ["Budowanie fabryk i obrona bazy.", "gra strategia", { cost: "free" }],
    "net.veloren.airshipper": ["Otwarty świat RPG z klocków, online.", "gra rpg", FREE],
    "org.xonotic.Xonotic": ["Szybka strzelanka arenowa.", "gra fps", FREE],
    "org.gnome.Chess": ["Szachy z komputerem.", "gra szachy", FREE],
    "org.gnome.Mines": ["Saper, jak w Windowsie.", "gra saper", FREE],
    "org.gnome.Sudoku": ["Sudoku z poziomami trudności.", "gra sudoku", FREE]
});
more("kod", {
    "com.google.AndroidStudio": ["Oficjalne narzędzie do aplikacji na Androida.", "android java kotlin", { cost: "free", heavy: 2 }],
    "com.jetbrains.PyCharm-Professional": ["Środowisko do Pythona od JetBrains.", "python ide jetbrains", { cost: "freemium", heavy: 2 }],
    "com.jetbrains.WebStorm": ["Środowisko do JavaScriptu i TypeScriptu.", "javascript typescript jetbrains", { cost: "paid", heavy: 2 }],
    "com.jetbrains.Rider": ["Środowisko do C# i .NET.", "c# dotnet jetbrains unity", { cost: "paid", heavy: 2 }],
    "com.jetbrains.CLion": ["Środowisko do C i C++.", "c++ jetbrains", { cost: "paid", heavy: 2 }],
    "com.jetbrains.GoLand": ["Środowisko do języka Go.", "go golang jetbrains", { cost: "paid", heavy: 2 }],
    "io.github.shiftey.Desktop": ["GitHub Desktop na Linuksa, utrzymywany przez społeczność.", "git github", { account: "opcja", cost: "free" }],
    "com.axosoft.GitKraken": ["Graficzny klient Gita.", "git", { account: "tak", cost: "freemium", heavy: 2 }],
    "cc.arduino.IDE2": ["Programowanie płytek Arduino.", "arduino elektronika", { cost: "free" }],
    "io.podman_desktop.PodmanDesktop": ["Kontenery w oknie, jak Docker Desktop.", "docker kontenery", { cost: "free", heavy: 2 }],
    "org.wireshark.Wireshark": ["Podgląd ruchu sieciowego.", "sieć pakiety", FREE],
    "com.usebruno.Bruno": ["Testowanie API bez konta i chmury.", "api postman", FREE],
    "rest.insomnia.Insomnia": ["Testowanie API, alternatywa dla Postmana.", "api rest", { cost: "freemium" }],
    "io.beekeeperstudio.Studio": ["Wygodny klient baz danych.", "sql baza danych", { cost: "freemium" }],
    "com.mongodb.Compass": ["Oficjalny klient bazy MongoDB.", "mongodb baza", { cost: "free" }]
});
more("narzedzia", {
    "it.mijorus.gearlever": ["Zarządza programami w formacie AppImage.", "appimage", FREE],
    "io.github.flattool.Warehouse": ["Dokładne porządki w Flatpakach.", "flatpak porządki", FREE],
    "io.missioncenter.MissionCenter": ["Menedżer zadań jak w Windows 11.", "menedżer zadań procesor pamięć", FREE],
    "org.fedoraproject.MediaWriter": ["Tworzy bootowalny pendrive z Linuksem.", "pendrive usb iso rufus", FREE],
    "io.gitlab.adhami3310.Impression": ["Nagrywanie obrazów ISO na pendrive.", "pendrive usb iso rufus balena", FREE],
    "org.raspberrypi.rpi-imager": ["Wgrywa system na kartę Raspberry Pi.", "raspberry", FREE],
    "org.kde.filelight": ["Pokazuje, co zajmuje miejsce na dysku.", "dysk miejsce windirstat", FREE],
    "org.freefilesync.FreeFileSync": ["Synchronizacja folderów i kopie zapasowe.", "kopia synchronizacja", { cost: "free" }],
    "org.bleachbit.BleachBit": ["Czyści niepotrzebne pliki, jak CCleaner.", "ccleaner czyszczenie", FREE],
    "com.anydesk.Anydesk": ["Znany program do zdalnego pulpitu.", "pulpit zdalny pomoc", { cost: "freemium" }],
    "org.remmina.Remmina": ["Łączenie ze zdalnymi komputerami przez RDP i VNC.", "rdp vnc zdalny", FREE],
    "org.gnome.Boxes": ["Maszyny wirtualne na dwa kliknięcia.", "wirtualizacja virtualbox windows", FREE],
    "com.protonvpn.www": ["VPN z darmowym planem, ze Szwajcarii.", "vpn prywatność", { account: "tak", cost: "freemium", offline: "nie" }],
    "com.surfshark.Surfshark": ["Oficjalny program Surfshark VPN.", "vpn", { account: "tak", cost: "paid", offline: "nie" }],
    "org.mozilla.vpn": ["VPN od Mozilli.", "vpn", { account: "tak", cost: "paid", offline: "nie" }],
    "dev.deedles.Trayscale": ["Tailscale w zasobniku systemowym.", "tailscale vpn sieć", { cost: "free" }],
    "me.proton.Pass": ["Menedżer haseł od Proton.", "hasła", { account: "tak", cost: "freemium" }],
    "com.onepassword.OnePassword": ["Menedżer haseł 1Password.", "hasła", { account: "tak", cost: "paid" }],
    "io.ente.auth": ["Kody dwuskładnikowe z kopią w chmurze.", "2fa authenticator kody", { cost: "free" }],
    "com.belmoussaoui.Authenticator": ["Kody dwuskładnikowe na komputerze.", "2fa authenticator kody", FREE],
    "org.deskflow.deskflow": ["Jedna mysz i klawiatura na kilka komputerów.", "synergy barrier", FREE]
});

function moreWeb(cat, category, table) {
    for (var id in table) {
        var row = table[id], extra = row[3] || {};
        var entry = { name: row[0], url: row[1], cat: cat, category: category, pl: row[2], tags: extra.tags || "", color: extra.color || "", offline: "nie", account: "tak", cost: "freemium" };
        for (var k in extra) entry[k] = extra[k];
        if (!web[id]) web[id] = entry;
    }
}
moreWeb("ai", "narzedzia", {
    claude: ["Claude", "https://claude.ai/", "Asystent AI od Anthropic, w osobnym oknie.", { color: "#D97757", tags: "ai chat anthropic" }],
    chatgpt: ["ChatGPT", "https://chatgpt.com/", "Najpopularniejszy asystent AI, od OpenAI.", { color: "#10A37F", tags: "ai chat openai gpt" }],
    gemini: ["Gemini", "https://gemini.google.com/", "Asystent AI od Google.", { color: "#4285F4", tags: "ai chat google bard" }],
    copilot: ["Microsoft Copilot", "https://copilot.microsoft.com/", "Asystent AI od Microsoftu.", { color: "#0078D4", tags: "ai chat bing" }],
    perplexity: ["Perplexity", "https://www.perplexity.ai/", "Wyszukiwarka, która odpowiada ze źródłami.", { color: "#20808D", tags: "ai wyszukiwarka" }],
    deepseek: ["DeepSeek", "https://chat.deepseek.com/", "Asystent AI z Chin.", { color: "#4D6BFE", tags: "ai chat" }],
    grok: ["Grok", "https://grok.com/", "Asystent AI od xAI.", { color: "#111111", tags: "ai chat" }],
    lechat: ["Le Chat", "https://chat.mistral.ai/", "Europejski asystent AI od Mistrala.", { color: "#FA520F", tags: "ai mistral" }],
    notebooklm: ["NotebookLM", "https://notebooklm.google.com/", "Rozmowa z Twoimi dokumentami od Google.", { color: "#4285F4", tags: "ai notatki" }]
});
moreWeb("internet", "internet", {
    allegro: ["Allegro", "https://allegro.pl/", "Największe polskie zakupy online.", { color: "#FF5A00", tags: "zakupy", account: "opcja", cost: "free" }],
    olx: ["OLX", "https://www.olx.pl/", "Ogłoszenia lokalne.", { color: "#002F34", tags: "ogłoszenia zakupy", account: "opcja", cost: "free" }],
    instagram: ["Instagram", "https://www.instagram.com/", "Zdjęcia i relacje znajomych.", { color: "#E4405F", tags: "social", cost: "free" }],
    facebook: ["Facebook", "https://www.facebook.com/", "Znajomi i grupy.", { color: "#0866FF", tags: "social", cost: "free" }],
    tiktok: ["TikTok", "https://www.tiktok.com/", "Krótkie filmy.", { color: "#111111", tags: "social wideo", account: "opcja", cost: "free" }],
    xtwitter: ["X", "https://x.com/", "Dawny Twitter.", { color: "#111111", tags: "twitter social", cost: "free" }],
    reddit: ["Reddit", "https://www.reddit.com/", "Forum o wszystkim.", { color: "#FF4500", tags: "forum social", account: "opcja", cost: "free" }],
    linkedin: ["LinkedIn", "https://www.linkedin.com/", "Sieć zawodowa.", { color: "#0A66C2", tags: "praca", cost: "free" }],
    pinterest: ["Pinterest", "https://www.pinterest.com/", "Pomysły i inspiracje.", { color: "#E60023", tags: "inspiracje", cost: "free" }]
});
moreWeb("rozmowy", "internet", {
    gmeet: ["Google Meet", "https://meet.google.com/", "Spotkania wideo Google.", { color: "#00897B", tags: "wideo spotkania", account: "opcja", cost: "free" }],
    onet: ["Poczta Onet", "https://poczta.onet.pl/", "Poczta Onet w osobnym oknie.", { color: "#D9001B", tags: "poczta mail", cost: "free" }],
    wp: ["Poczta WP", "https://poczta.wp.pl/", "Poczta Wirtualnej Polski.", { color: "#D90000", tags: "poczta mail", cost: "free" }],
    interia: ["Poczta Interia", "https://poczta.interia.pl/", "Poczta Interii.", { color: "#FF6600", tags: "poczta mail", cost: "free" }]
});
moreWeb("filmy", "multimedia", {
    netflix: ["Netflix", "https://www.netflix.com/", "Filmy i seriale.", { color: "#E50914", cost: "paid", tags: "filmy seriale vod" }],
    disney: ["Disney+", "https://www.disneyplus.com/", "Disney, Marvel, Star Wars, Pixar.", { color: "#0E2A6B", cost: "paid", tags: "filmy seriale vod marvel" }],
    max: ["HBO Max", "https://www.hbomax.com/", "Seriale HBO i filmy Warnera.", { color: "#5822B4", cost: "paid", tags: "filmy seriale vod hbo" }],
    prime: ["Prime Video", "https://www.primevideo.com/", "Filmy i seriale Amazona.", { color: "#00A8E1", cost: "paid", tags: "filmy seriale vod amazon" }],
    appletv: ["Apple TV", "https://tv.apple.com/", "Seriale i filmy Apple.", { color: "#111111", cost: "paid", tags: "filmy seriale vod" }],
    skyshowtime: ["SkyShowtime", "https://www.skyshowtime.com/", "Filmy Paramount i Universal.", { color: "#7A2BF5", cost: "paid", tags: "filmy seriale vod" }],
    player: ["Player", "https://player.pl/", "Seriale i programy TVN.", { color: "#E4002B", tags: "tvn vod seriale polskie", account: "opcja", ads: true }],
    tvpvod: ["TVP VOD", "https://vod.tvp.pl/", "Publiczna telewizja na żądanie.", { color: "#0049A5", tags: "tvp vod seriale polskie", account: "opcja", cost: "free", ads: true }],
    twitch: ["Twitch", "https://www.twitch.tv/", "Transmisje na żywo.", { color: "#9146FF", tags: "streamy gry", account: "opcja", cost: "free", ads: true }]
});
moreWeb("muzyka", "multimedia", {
    ytmusic: ["YouTube Music", "https://music.youtube.com/", "Muzyka z YouTube.", { color: "#FF0033", tags: "muzyka", account: "opcja", ads: true }],
    applemusic: ["Apple Music", "https://music.apple.com/", "Twoja biblioteka Apple Music.", { color: "#FA2D48", cost: "paid", tags: "muzyka" }],
    tidalweb: ["Tidal", "https://listen.tidal.com/", "Muzyka w wysokiej jakości.", { color: "#111111", cost: "paid", tags: "muzyka" }],
    soundcloud: ["SoundCloud", "https://soundcloud.com/", "Muzyka niezależnych twórców.", { color: "#FF5500", tags: "muzyka", account: "opcja", ads: true }],
    deezer: ["Deezer", "https://www.deezer.com/", "Streaming muzyki.", { color: "#A238FF", tags: "muzyka", ads: true }]
});
moreWeb("biuro", "biuro", {
    gdocs: ["Dokumenty Google", "https://docs.google.com/document/", "Edytor tekstu w chmurze.", { color: "#4285F4", tags: "word dokument", cost: "free" }],
    gsheets: ["Arkusze Google", "https://docs.google.com/spreadsheets/", "Arkusze w chmurze.", { color: "#0F9D58", tags: "excel arkusz", cost: "free" }],
    gslides: ["Prezentacje Google", "https://docs.google.com/presentation/", "Prezentacje w chmurze.", { color: "#F4B400", tags: "powerpoint prezentacja", cost: "free" }],
    gdrive: ["Dysk Google", "https://drive.google.com/", "Twoje pliki w chmurze.", { color: "#34A853", tags: "chmura dysk", cost: "freemium" }],
    gcal: ["Kalendarz Google", "https://calendar.google.com/", "Terminy i spotkania.", { color: "#4285F4", tags: "kalendarz", cost: "free" }],
    gphotos: ["Zdjęcia Google", "https://photos.google.com/", "Twoje zdjęcia z telefonu.", { color: "#FBBC04", tags: "zdjęcia chmura" }],
    onedrive: ["OneDrive", "https://onedrive.live.com/", "Twoje pliki Microsoft w chmurze.", { color: "#0364B8", tags: "chmura dysk" }],
    icloud: ["iCloud", "https://www.icloud.com/", "Zdjęcia, notatki i pliki z iPhone'a.", { color: "#3693F3", tags: "apple iphone chmura" }],
    trello: ["Trello", "https://trello.com/", "Tablice z zadaniami.", { color: "#0C66E4", tags: "zadania kanban" }],
    miro: ["Miro", "https://miro.com/app/", "Tablica do pracy w zespole.", { color: "#FFD02F", tags: "tablica" }]
});
moreWeb("gry", "gry", {
    geforcenow: ["GeForce NOW", "https://play.geforcenow.com/", "Gry z chmury NVIDII, bez mocnego komputera.", { color: "#76B900", tags: "chmura nvidia granie" }],
    xboxcloud: ["Xbox Cloud Gaming", "https://www.xbox.com/play", "Game Pass w przeglądarce.", { color: "#107C10", cost: "paid", tags: "xbox chmura game pass" }],
    luna: ["Amazon Luna", "https://luna.amazon.com/", "Gry z chmury Amazona.", { color: "#7E3BF2", tags: "chmura amazon" }]
});

// Programy prosto od producenta. Adresy są sprawdzane testem test/check-catalog.mjs.
// site: strona producenta, mb: orientacyjny rozmiar pobrania, unofficial: producent nie wspiera tej drogi na Fedorze
var get = {
    "claude-desktop": { name: "Claude", site: "claude.ai", cat: "ai", pl: "Oficjalna aplikacja Claude: czat, Cowork i Claude Code.", tags: "ai anthropic chat claude code", type: "deb", mb: 136,
        apt: { base: "https://downloads.claude.ai/claude-desktop/apt/stable", package: "claude-desktop" }, account: "tak", cost: "freemium", unofficial: "Anthropic wydaje tę aplikację dla Ubuntu i Debiana, na Asterze działa z rozpakowanej paczki .deb.",
        command: "Pobierze oficjalną paczkę .deb z downloads.claude.ai i rozpakuje ją do ~/.local/share/aster-get" },
    "claude-code": { name: "Claude Code", site: "claude.ai", cat: "ai", pl: "Agent Claude do programowania, w terminalu.", tags: "ai anthropic kod agent cli", type: "script", cli: true, mb: 80, url: { x86_64: "https://claude.ai/install.sh", aarch64: "https://claude.ai/install.sh" },
        account: "tak", cost: "freemium", commandName: "claude", removeBin: [".local/bin/claude"], command: "curl -fsSL https://claude.ai/install.sh | bash" },
    "codex": { name: "Codex CLI", site: "openai.com", cat: "ai", pl: "Agent OpenAI do programowania, w terminalu.", tags: "ai openai kod agent cli", type: "tar", cli: true, mb: 120, account: "tak", cost: "freemium",
        gh: { repo: "openai/codex", asset: { x86_64: "^codex-x86_64-unknown-linux-musl\\.tar\\.gz$", aarch64: "^codex-aarch64-unknown-linux-musl\\.tar\\.gz$" } }, execByArch: { x86_64: "codex-x86_64-unknown-linux-musl", aarch64: "codex-aarch64-unknown-linux-musl" }, commandName: "codex" },
    "cursor": { name: "Cursor", site: "cursor.com", cat: "ai", pl: "Edytor kodu zbudowany wokół AI.", tags: "ai edytor kod vscode", type: "appimage", mb: 327, account: "tak", cost: "freemium", heavy: 2,
        url: { x86_64: "https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/latest", aarch64: "https://api2.cursor.sh/updates/download/golden/linux-arm64/cursor/latest" } },
    "devin-desktop": { name: "Windsurf (Devin)", site: "windsurf.com", cat: "ai", pl: "Edytor kodu z agentem AI, dawniej Windsurf.", tags: "ai edytor kod windsurf codeium", type: "tar", mb: 200, account: "tak", cost: "freemium", heavy: 2, exec: "devin-desktop",
        jsonUrl: { x86_64: "https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest" } },
    "ollama": { name: "Ollama", site: "ollama.com", cat: "ai", pl: "Uruchamia modele AI na Twoim komputerze, w terminalu.", tags: "ai llm lokalny model cli", type: "tar", cli: true, mb: 1500, exec: "bin/ollama", account: "nie", cost: "free", offline: "tak", heavy: 2,
        url: { x86_64: "https://ollama.com/download/ollama-linux-amd64.tar.zst", aarch64: "https://ollama.com/download/ollama-linux-arm64.tar.zst" } },
    "warp": { name: "Warp", site: "warp.dev", cat: "kod", pl: "Nowoczesny terminal z AI.", tags: "terminal ai", type: "appimage", mb: 200, account: "opcja", cost: "freemium",
        url: { x86_64: "https://app.warp.dev/download?package=appimage", aarch64: "https://app.warp.dev/download?package=appimage_arm64" } },
    "jetbrains-toolbox": { name: "JetBrains Toolbox", site: "jetbrains.com", cat: "kod", pl: "Instaluje i aktualizuje wszystkie IDE JetBrains.", tags: "intellij pycharm ide", type: "tar", mb: 156, exec: "bin/jetbrains-toolbox", account: "opcja", cost: "free",
        url: { x86_64: "https://data.services.jetbrains.com/products/download?code=TBA&platform=linux&type=release", aarch64: "https://data.services.jetbrains.com/products/download?code=TBA&platform=linuxARM64&type=release" } },
    "bun": { name: "Bun", site: "bun.sh", cat: "kod", pl: "Szybkie środowisko JavaScript, w terminalu.", tags: "javascript node npm cli", type: "script", cli: true, mb: 40, url: { x86_64: "https://bun.sh/install", aarch64: "https://bun.sh/install" }, account: "nie", cost: "free", removeBin: [".bun/bin/bun"], command: "curl -fsSL https://bun.sh/install | bash" },
    "uv": { name: "uv", site: "astral.sh", cat: "kod", pl: "Bardzo szybki menedżer pakietów Pythona.", tags: "python pip cli", type: "script", cli: true, mb: 20, url: { x86_64: "https://astral.sh/uv/install.sh", aarch64: "https://astral.sh/uv/install.sh" }, account: "nie", cost: "free", removeBin: [".local/bin/uv", ".local/bin/uvx"], command: "curl -LsSf https://astral.sh/uv/install.sh | sh" },
    "rustup": { name: "Rust", site: "rust-lang.org", cat: "kod", pl: "Język Rust z oficjalnym instalatorem rustup.", tags: "rust cargo cli", type: "script", cli: true, mb: 400, args: ["-y"], url: { x86_64: "https://sh.rustup.rs", aarch64: "https://sh.rustup.rs" }, account: "nie", cost: "free", command: "curl https://sh.rustup.rs -sSf | sh -s -- -y" }
};

// Launchery spoza Linuksa: Lutris ma do nich gotowe instalatory
var via = {
    battlenet: { name: "Battle.net", site: "battle.net", cat: "gry", pl: "WoW, Diablo, Overwatch, CoD. Instaluje się przez Lutris.", tags: "blizzard wow diablo overwatch launcher", slug: "battlenet", host: "net.lutris.Lutris" },
    eaapp: { name: "EA app", site: "ea.com", cat: "gry", pl: "Gry EA, np. The Sims i FC. Instaluje się przez Lutris.", tags: "ea origin sims launcher", slug: "ea-app", host: "net.lutris.Lutris" },
    ubisoft: { name: "Ubisoft Connect", site: "ubisoft.com", cat: "gry", pl: "Assassin's Creed, Far Cry. Instaluje się przez Lutris.", tags: "ubisoft uplay launcher", slug: "ubisoft-connect", host: "net.lutris.Lutris" },
    rockstar: { name: "Rockstar Launcher", site: "rockstargames.com", cat: "gry", pl: "GTA i Red Dead. Instaluje się przez Lutris.", tags: "gta rockstar launcher", slug: "rockstar-games-launcher", host: "net.lutris.Lutris" },
    goggalaxy: { name: "GOG Galaxy", site: "gog.com", cat: "gry", pl: "Oryginalny launcher GOG. Instaluje się przez Lutris.", tags: "gog launcher", slug: "gog-galaxy", host: "net.lutris.Lutris" }
};

// Półki katalogu: kolejność to kolejność znajomości, najbardziej znane pierwsze
var shelves = {
    gry: [
        { title: "Launchery i sklepy", refs: ["com.valvesoftware.Steam", "com.heroicgameslauncher.hgl", "via:battlenet", "via:eaapp", "via:ubisoft", "via:rockstar", "via:goggalaxy", "net.lutris.Lutris", "io.itch.itch", "io.github.Faugus.faugus-launcher", "ru.linux_gaming.PortProton", "com.usebottles.bottles"] },
        { title: "Roblox i Minecraft", refs: ["org.vinegarhq.Sober", "org.vinegarhq.Vinegar", "com.mojang.Minecraft", "org.prismlauncher.PrismLauncher", "com.modrinth.ModrinthApp", "com.overwolf.curseforge", "io.mrarm.mcpelauncher", "com.lunarclient.LunarClient"] },
        { title: "Granie w chmurze i zdalnie", refs: ["web:geforcenow", "web:xboxcloud", "web:luna", "com.valvesoftware.SteamLink", "com.moonlight_stream.Moonlight", "dev.lizardbyte.app.Sunshine", "com.parsecgaming.parsec", "io.github.streetpea.Chiaki4deck"] },
        { title: "Konsole i emulatory", refs: ["org.libretro.RetroArch", "net.retrodeck.retrodeck", "net.pcsx2.PCSX2", "org.DolphinEmu.dolphin-emu", "org.ppsspp.PPSSPP", "io.github.ryubing.Ryujinx", "dev.eden_emu.eden", "net.rpcs3.RPCS3", "info.cemu.Cemu", "app.xemu.xemu", "org.azahar_emu.Azahar", "net.kuribo64.melonDS", "io.mgba.mGBA", "org.flycast.Flycast", "org.scummvm.ScummVM", "com.fightcade.Fightcade"] },
        { title: "Narzędzia dla graczy", refs: ["web:discord", "dev.vencord.Vesktop", "net.davidotek.pupgui2", "com.vysp3r.ProtonPlus", "com.github.Matoking.protontricks", "io.github.benjamimgois.goverlay", "org.openrgb.OpenRGB", "io.github.ilya_zlobintsev.LACT", "com.obsproject.Studio", "com.dec05eba.gpu_screen_recorder"] },
        { title: "Darmowe gry", refs: ["net.supertuxkart.SuperTuxKart", "sh.ppy.osu", "com.play0ad.zeroad", "org.luanti.luanti", "org.openttd.OpenTTD", "com.github.Anuken.Mindustry", "net.veloren.airshipper", "org.xonotic.Xonotic", "com.github.k4zmu2a.spacecadetpinball", "org.gnome.Chess", "org.gnome.Mines", "org.gnome.Sudoku"] }
    ],
    ai: [
        { title: "Asystenci", refs: ["get:claude-desktop", "web:chatgpt", "web:gemini", "web:claude", "web:copilot", "web:perplexity", "web:deepseek", "web:grok", "web:lechat", "web:notebooklm"] },
        { title: "AI do programowania", refs: ["get:claude-code", "get:cursor", "get:codex", "get:devin-desktop", "ai.opencode.opencode", "dev.zed.Zed", "get:warp"] },
        { title: "Modele na Twoim komputerze", refs: ["ai.lmstudio.lm-studio", "get:ollama", "ai.jan.Jan", "com.jeffser.Alpaca", "net.sapples.LiveCaptions", "org.upscayl.Upscayl"] }
    ],
    internet: [
        { title: "Przeglądarki", refs: ["com.google.Chrome", "org.mozilla.firefox", "com.microsoft.Edge", "com.brave.Browser", "com.opera.Opera", "com.opera.opera-gx", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "app.zen_browser.zen", "io.gitlab.librewolf-community", "net.waterfox.waterfox", "one.ablaze.floorp", "net.mullvad.MullvadBrowser", "io.github.ungoogled_software.ungoogled_chromium", "org.torproject.torbrowser-launcher"] },
        { title: "Społeczności", refs: ["web:instagram", "web:facebook", "web:tiktok", "web:xtwitter", "web:reddit", "web:linkedin", "web:pinterest"] },
        { title: "Zakupy", refs: ["web:allegro", "web:olx"] },
        { title: "Pobieranie", refs: ["org.qbittorrent.qBittorrent", "com.transmissionbt.Transmission", "org.kde.ktorrent", "org.freedownloadmanager.Manager", "org.jdownloader.JDownloader", "org.filezillaproject.Filezilla"] }
    ],
    rozmowy: [
        { title: "Komunikatory", refs: ["web:whatsapp", "web:messenger", "com.discordapp.Discord", "web:discord", "org.telegram.desktop", "org.signal.Signal", "com.rtosta.zapzap", "com.viber.Viber", "dev.vencord.Vesktop", "im.riot.Riot", "com.tencent.WeChat"] },
        { title: "Spotkania i praca", refs: ["web:teams", "us.zoom.Zoom", "web:gmeet", "com.slack.Slack", "web:slack", "org.jitsi.jitsi-meet", "com.github.IsmaelMartinez.teams_for_linux"] },
        { title: "Poczta", refs: ["org.mozilla.thunderbird", "web:gmail", "web:outlook", "web:onet", "web:wp", "web:interia", "me.proton.Mail", "eu.betterbird.Betterbird", "org.gnome.Evolution", "com.getmailspring.Mailspring", "com.tutanota.Tutanota"] }
    ],
    filmy: [
        { title: "Serwisy", refs: ["web:netflix", "web:youtube", "web:disney", "web:max", "web:prime", "web:player", "web:tvpvod", "web:skyshowtime", "web:appletv", "web:twitch"] },
        { title: "Odtwarzacze", refs: ["org.videolan.VLC", "aster:video", "io.mpv.Mpv", "org.kde.haruna", "io.github.celluloid_player.Celluloid", "tv.kodi.Kodi", "com.stremio.Stremio", "org.jellyfin.JellyfinDesktop", "tv.plex.PlexDesktop"] },
        { title: "YouTube po swojemu", refs: ["io.freetubeapp.FreeTube", "rocks.shy.VacuumTube", "org.nickvision.tubeconverter", "com.makemkv.MakeMKV"] }
    ],
    muzyka: [
        { title: "Słuchanie", refs: ["com.spotify.Client", "web:spotify", "web:ytmusic", "web:applemusic", "web:tidalweb", "com.mastermindzh.tidal-hifi", "web:soundcloud", "web:deezer", "aster:music", "org.strawberrymusicplayer.strawberry", "com.plexamp.Plexamp", "de.haeckerfelix.Shortwave", "org.gnome.Rhythmbox3"] },
        { title: "Tworzenie", refs: ["aster:studio", "org.audacityteam.Audacity", "org.ardour.Ardour", "fm.reaper.Reaper", "com.bitwig.BitwigStudio", "org.mixxx.Mixxx", "org.musescore.MuseScore", "org.tenacityaudio.Tenacity"] },
        { title: "Dźwięk i kolekcja", refs: ["com.github.wwmm.easyeffects", "org.musicbrainz.Picard"] }
    ],
    biuro: [
        { title: "Pakiety biurowe", refs: ["org.libreoffice.LibreOffice", "org.onlyoffice.desktopeditors", "web:word", "web:excel", "web:powerpoint", "web:gdocs", "web:gsheets", "web:gslides", "com.wps.Office", "com.collaboraoffice.Office"] },
        { title: "Chmura", refs: ["web:gdrive", "web:onedrive", "web:icloud", "web:gphotos", "com.dropbox.Client", "com.nextcloud.desktopclient.nextcloud"] },
        { title: "Notatki i zadania", refs: ["web:notion", "md.obsidian.Obsidian", "net.cozic.joplin_desktop", "com.logseq.Logseq", "com.todoist.Todoist", "com.ticktick.TickTick", "web:trello", "web:miro", "web:gcal", "org.gnome.Calendar", "io.github.alainm23.planify"] },
        { title: "PDF i e-booki", refs: ["aster:pdf", "org.kde.okular", "com.adobe.Reader", "org.gnome.Papers", "com.github.jeromerobert.pdfarranger", "com.github.xournalpp.xournalpp", "com.calibre_ebook.calibre", "com.github.johnfactotum.Foliate"] },
        { title: "Nauka", refs: ["net.ankiweb.Anki", "org.zotero.Zotero", "org.geogebra.GeoGebra", "org.stellarium.Stellarium", "org.kde.gcompris", "org.tuxpaint.Tuxpaint", "org.kde.kalgebra", "org.gnucash.GnuCash"] }
    ],
    grafika: [
        { title: "Zdjęcia i rysowanie", refs: ["org.gimp.GIMP", "web:photopea", "org.kde.krita", "web:canva", "aster:grafika", "aster:photos", "org.inkscape.Inkscape", "org.darktable.Darktable", "com.rawtherapee.RawTherapee", "org.kde.digikam", "com.xnview.XnViewMP", "com.github.PintaProject.Pinta", "org.kde.kolourpaint", "org.upscayl.Upscayl", "web:figma"] },
        { title: "3D i projektowanie", refs: ["org.blender.Blender", "org.freecad.FreeCAD", "net.scribus.Scribus", "com.jgraph.drawio.desktop", "org.kicad.KiCad", "com.google.EarthPro"] },
        { title: "Druk 3D", refs: ["com.bambulab.BambuStudio", "com.orcaslicer.OrcaSlicer", "com.prusa3d.PrusaSlicer", "com.ultimaker.cura"] },
        { title: "Tworzenie gier", refs: ["org.godotengine.Godot", "com.unity.UnityHub", "org.pencil2d.Pencil2D"] }
    ],
    wideo: [
        { title: "Montaż", refs: ["aster:montaz", "org.kde.kdenlive", "org.shotcut.Shotcut", "org.openshot.OpenShot", "no.mifi.losslesscut", "org.gnome.gitlab.YaLTeR.VideoTrimmer"] },
        { title: "Nagrywanie i konwersja", refs: ["com.obsproject.Studio", "com.dec05eba.gpu_screen_recorder", "fr.handbrake.ghb", "org.flameshot.Flameshot"] }
    ],
    kod: [
        { title: "Edytory", refs: ["com.visualstudio.code", "get:cursor", "aster:code", "com.vscodium.codium", "dev.zed.Zed", "org.kde.kate", "get:warp"] },
        { title: "JetBrains i Android", refs: ["get:jetbrains-toolbox", "com.jetbrains.IntelliJ-IDEA-Community", "com.jetbrains.PyCharm-Professional", "com.jetbrains.WebStorm", "com.jetbrains.Rider", "com.jetbrains.CLion", "com.jetbrains.GoLand", "com.google.AndroidStudio"] },
        { title: "Git, API i bazy danych", refs: ["io.github.shiftey.Desktop", "com.axosoft.GitKraken", "aster:pulse", "com.getpostman.Postman", "com.usebruno.Bruno", "rest.insomnia.Insomnia", "aster:vault", "io.dbeaver.DBeaverCommunity", "io.beekeeperstudio.Studio", "com.mongodb.Compass"] },
        { title: "Języki i narzędzia", refs: ["get:rustup", "get:bun", "get:uv", "aster:harbor", "aster:launch", "io.podman_desktop.PodmanDesktop", "cc.arduino.IDE2", "org.wireshark.Wireshark"] }
    ],
    narzedzia: [
        { title: "Hasła i bezpieczeństwo", refs: ["com.bitwarden.desktop", "com.onepassword.OnePassword", "org.keepassxc.KeePassXC", "me.proton.Pass", "com.belmoussaoui.Authenticator", "io.ente.auth", "org.cryptomator.Cryptomator"] },
        { title: "VPN", refs: ["com.protonvpn.www", "com.surfshark.Surfshark", "org.mozilla.vpn", "dev.deedles.Trayscale"] },
        { title: "Pulpit zdalny", refs: ["com.rustdesk.RustDesk", "com.anydesk.Anydesk", "org.remmina.Remmina", "org.deskflow.deskflow"] },
        { title: "Pliki i dysk", refs: ["org.localsend.localsend_app", "io.github.peazip.PeaZip", "org.kde.filelight", "org.bleachbit.BleachBit", "org.gnome.DejaDup", "org.freefilesync.FreeFileSync", "org.flameshot.Flameshot"] },
        { title: "System", refs: ["io.missioncenter.MissionCenter", "org.gnome.Boxes", "org.fedoraproject.MediaWriter", "io.gitlab.adhami3310.Impression", "org.raspberrypi.rpi-imager", "com.github.tchx84.Flatseal", "io.github.flattool.Warehouse", "it.mijorus.gearlever", "com.github.wwmm.easyeffects"] }
    ]
};

// Strona główna: to, co ludzie znają
var top = ["com.google.Chrome", "web:whatsapp", "com.spotify.Client", "get:claude-desktop", "com.valvesoftware.Steam", "com.discordapp.Discord",
           "web:netflix", "org.videolan.VLC", "web:chatgpt", "org.libreoffice.LibreOffice", "org.telegram.desktop", "web:messenger",
           "com.obsproject.Studio", "org.gimp.GIMP", "com.visualstudio.code", "us.zoom.Zoom", "web:word", "org.qbittorrent.qBittorrent"];
var homeAi = ["get:claude-desktop", "web:chatgpt", "web:gemini", "get:cursor", "get:claude-code", "ai.lmstudio.lm-studio"];
var homeGames = ["com.valvesoftware.Steam", "com.heroicgameslauncher.hgl", "via:battlenet", "org.vinegarhq.Sober", "org.prismlauncher.PrismLauncher", "web:geforcenow"];

// Programy bez wersji na ARM (test pilnuje, żeby lista była aktualna)
var x86Only = ["ai.jan.Jan", "cc.arduino.IDE2", "com.adobe.Reader", "com.bitwig.BitwigStudio", "com.discordapp.Discord", "com.dropbox.Client", "com.fightcade.Fightcade", "com.google.AndroidStudio", "com.google.EarthPro", "com.heroicgameslauncher.hgl", "com.lunarclient.LunarClient", "com.mastermindzh.tidal-hifi", "com.microsoft.Edge", "com.modrinth.ModrinthApp", "com.mojang.Minecraft", "com.mongodb.Compass", "com.obsproject.Studio", "com.opera.Opera", "com.opera.opera-gx", "com.overwolf.curseforge", "com.parsecgaming.parsec", "com.plexamp.Plexamp", "com.slack.Slack", "com.spotify.Client", "com.todoist.Todoist", "com.tutanota.Tutanota", "com.ultimaker.cura", "com.unity.UnityHub", "com.usebottles.bottles", "com.usebruno.Bruno", "com.valvesoftware.Steam", "com.valvesoftware.SteamLink", "com.viber.Viber", "com.wps.Office", "com.xnview.XnViewMP", "fr.handbrake.ghb", "info.cemu.Cemu", "io.ente.auth", "io.github.Faugus.faugus-launcher", "io.itch.itch", "net.lutris.Lutris", "net.mullvad.MullvadBrowser", "net.pcsx2.PCSX2", "net.retrodeck.retrodeck", "net.waterfox.waterfox", "org.blender.Blender", "org.freedownloadmanager.Manager", "org.freefilesync.FreeFileSync", "org.geogebra.GeoGebra", "org.mozilla.thunderbird", "org.torproject.torbrowser-launcher", "org.upscayl.Upscayl", "org.vinegarhq.Sober", "org.vinegarhq.Vinegar", "rest.insomnia.Insomnia", "ru.linux_gaming.PortProton", "sh.ppy.osu", "tv.plex.PlexDesktop", "us.zoom.Zoom"];

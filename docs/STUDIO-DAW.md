# Studio jako pełnoprawny DAW

Cel: program do robienia muzyki od zera do gotowego numeru, o układzie znanym z FL Studio (rack kanałów, wzory,
playlista, piano roll, mikser, przeglądarka), ale z własnym wyglądem Astera, własnymi ikonami i własnym kodem.
Wtyczki VST3 mają działać naprawdę: instrumenty i efekty, z własnymi oknami, zapisane w projekcie i w eksporcie.

## Co się zmienia w środku
Dzisiejsze Studio: ścieżka = pas osi czasu + stały łańcuch efektów; wzory bitów renderowane do plików WAV.
DAW: osobno kanały (co gra), wzory (kiedy gra), playlista (układ utworu) i mikser (jak brzmi).

- **Kanały** — sampler, syntezatory Studia albo instrument VST3; każdy wysyła dźwięk na wybrany insert miksera.
- **Wzory** — kroki i nuty wielu kanałów; grane na żywo nutami z dokładnością do próbki, nie jako WAV.
- **Playlista** — pasy niezwiązane z kanałami; klipy wzorów, audio i automatyki. Tryb WZÓR / UTWÓR.
- **Mikser** — inserty z sekcją wtyczek (natywne i VST3), głośność, panorama, wysyłki i routing między insertami,
  master; kompensacja opóźnień wtyczek.
- **Automatyka** — klipy sterujące dowolnym parametrem, także parametrami VST3.
- **Efekty natywne** — obecny łańcuch (autotune, korektor, de-esser, kompresor, przester, dubel, pogłos, echo)
  staje się zwykłymi wtyczkami w slotach insertu. Nagrywanie, podejścia, punch-in, tekst, odszumianie i bit z pliku zostają.
- Stare projekty otwierają się po konwersji: ścieżka audio → pas playlisty + insert z efektami, wzór → kanały + wzór.

## Wtyczki na Linuksie: co jest pewne, a co nie
- VST3 SDK jest na licencji MIT i w repozytoriach Fedory (`vst3sdk-devel`). Host: `apps/studio/src/vst3host.*`.
- VST3 na Linuksie zna tylko X11, Aster działa na Waylandzie: okno wtyczki to osobne okno X11 przez XWayland.
- Host opiera się na `PlugProvider` z SDK, który wymaga `IConnectionPoint`; rzadkie wtyczki bez niego się nie załadują.
- Każda wtyczka działa we własnym procesie, więc jej awaria nie zamyka programu. Po awarii wraca z ostatnio zapisanym stanem.
- **Wtyczki linuksowe** (natywne `.vst3`): działają bezpośrednio. CLAP (nagłówki w Fedorze) dojdzie po VST3.
- **Wtyczki z Windowsa** (większość komercyjnych): wymagają mostka yabridge + Wine. yabridge nie ma w Fedorze, trzeba
  go zbudować do obrazu. Działa tylko na x86_64 i część wtyczek (zwłaszcza z aktywacją online) może nie ruszyć —
  obietnica „każdy VST działa” byłaby nieprawdziwa. Sprawdzenie wymaga maszyny x86 (VM albo laptop), nie kontenera ARM.

## Etapy
Każdy etap zostawia działający program i kończy się commitem.

1. [x] Wtyczki VST3 jako efekty na ścieżkach: skan, okna, stan w projekcie, eksport (zalążek slotów miksera).
       Sprawdzone na wtyczkach Zam (aarch64, Xvfb). Nie sprawdzone: instrumenty, wtyczki komercyjne, prawdziwy XWayland.
2. [x] Silnik i model: inserty (głośność, efekty, wtyczki, wysyłki, grupy bez wyjścia na master), kanały
       z instrumentami (sampler, syntezator, 808, VST3), wzory grane nutami co do próbki, klipy wzorów na playliście,
       tryb WZÓR, format projektu 2 (stare otwierają się same). Kod: `src/rack.cpp`, `src/instrument.h`.
       Ten sam kod gra na żywo i w eksporcie. Bez interfejsu: dostęp przez API Studia, zmienia to etap 3.
       Jeszcze nie: efekty natywne jako osobne sloty i zamiana starych ścieżek Beat Makera na kanały (etap 3).
3. [~] Interfejs: przeglądarka, rack z krokami i wzorami, playlista z klipami wzorów i trybem WZÓR/UTWÓR,
       mikser na insertach z wtyczkami i wysyłkami, piano roll kanału, instrumenty VST3 także z klawiatury MIDI.
       Beat Maker zastąpiony: stare wzory i szablony gatunków zamieniają się na kanały i wzory.
       Zostało: efekty natywne jako osobne sloty, przeciąganie z przeglądarki na playlistę.
4. [x] Automatyka (klipy z krzywą: głośność, panorama, efekty, parametry VST3, głośność kanału), kompensacja
       opóźnień wtyczek (także w wysyłkach, metronomie, nagrywaniu i eksporcie), sidechain Studia i wejście boczne
       VST3, zamrażanie insertów do pliku. Jeszcze nie: nagrywanie automatyki ruchem suwaka, krzywe nieliniowe.
5. [x] Sampler: obwiednia ADSR, zakres, pętla, wstecz, strojenie, filtr, grupy ucinania, plasterki (na uderzenia
       i po równo, układanie we wzorze), dopasowanie do tempa (Rubber Band). Biblioteka w folderze obok projektów,
       upuszczanie plików na rack, zapisane ustawienia kanałów i insertów. Własnej paczki sampli jeszcze nie ma.
6. [~] Wtyczki w osobnym procesie (`aster-plugin-host`, `src/remote.*`): dźwięk przez pamięć współdzieloną, awaria
       nie zamyka Studia, wtyczkę można uruchomić ponownie; skan też w procesach pomocniczych, z pamięcią wyników.
       CLAP (`src/claphost.cpp`). Wtyczki z Windowsa: skrypt `tools/aster-wtyczki-windows` (Wine + yabridge),
       NIESPRAWDZONY: wymaga komputera x86_64, kontener i maszyna wirtualna to ARM.

## Do sprawdzenia na prawdziwym komputerze
- Cały interfejs na prawdziwym ekranie: rack, mikser, piano roll, krzywe, panel kanału, przeciąganie.
- Opóźnienie odsłuchu i dropouty: wtyczki w osobnym procesie czekają najwyżej tyle, ile trwa blok, a spóźniony blok
  gra bez wtyczki. Pod obciążeniem to słyszalny trzask; liczby na prawdziwym sprzęcie jeszcze nie ma.
- Okna wtyczek przez prawdziwy XWayland (do tej pory Xvfb). Okno CLAP nie było otwierane.
- Komercyjne wtyczki VST3 i CLAP, instrumenty z GUI.
- yabridge 5.1.1 z Wine 11 z Fedory: zgodność niepotwierdzona, wtyczki z aktywacją online mogą nie ruszyć.

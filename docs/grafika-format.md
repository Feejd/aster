# Format projektu Aster Pixel (`.grafika`)

Plik projektu to zwykłe archiwum ZIP (można je otworzyć dowolnym programem do archiwów):

| Plik w archiwum | Zawartość |
|---|---|
| `project.json` | strona, tło i elementy (opis niżej) |
| `images/<skrót>.<rozszerzenie>` | zdjęcia użyte w projekcie, w oryginalnej postaci (nazwa = początek SHA-1 treści) |
| `fonts/<rodzina>/<plik>.ttf` | czcionki pobrane z Google Fonts, użyte w tekstach — na innym komputerze tekst wygląda tak samo |
| `thumbnail.png` | miniatura (dłuższy bok 512 px) do ekranu startowego i menedżera plików |

Szablony programu (`apps/grafika/templates/*.json`) to sam `project.json` bez zdjęć.

## project.json

```json
{
  "format": "aster-grafika", "version": 1,
  "name": "Urodziny", "category": "Zaproszenie",
  "width": 1748, "height": 2480,
  "print": { "width": 148, "height": 210 },
  "background": { "type": "radial", "color": "#ffffff", "color2": "#dde7ff" },
  "elements": [ … od spodu do wierzchu … ],
  "pages": [ { "background": { … }, "elements": [ … ] }, … ],
  "page": 0,
  "guides": { "x": [540], "y": [120, 960] }
}
```

- Strony: `pages` — wszystkie strony (każda ze swoim tłem i elementami), wszystkie w rozmiarze `width` × `height`;
  `page` — strona otwarta przy zapisie. `background` i `elements` na wierzchu to ta sama strona (zapis jednostronicowy
  i szablony mają tylko je). PDF zawiera wszystkie strony; PNG/JPG — jedną albo każdą do pliku `nazwa-1`, `nazwa-2`…
  Miniatura pliku pokazuje pierwszą stronę.
- Prowadnice: `guides` (opcjonalne) — własne linie pomocnicze wspólne dla wszystkich stron, w pikselach projektu:
  `x` — pionowe, `y` — poziome. Widać je i przyciągają tylko przy włączonych linijkach; nie trafiają do eksportu.

- Wymiary w pikselach projektu. `print` (opcjonalne) — rozmiar do druku w mm; PDF ma wtedy dokładnie ten format,
  a bez niego stronę liczy się jak ekran (96 pikseli na cal).
- Kolory jako `#rrggbb` albo z przezroczystością `#aarrggbb`.
- Tło: `type` = `color` (`color`), `gradient` (`color` → `color2`, `angle` w stopniach jak w CSS: 0 — ku górze, 180 — w dół),
  `radial` (od środka `color` do brzegów `color2`), `image` (`src` — plik z `images/`, `imageOpacity`, pod spodem `color`).

## Warstwy

Każdy element to warstwa. Oprócz `opacity` i `hidden` może mieć:

- `blend` — tryb mieszania z tym, co pod spodem: `multiply`, `screen`, `overlay`, `darken`, `lighten`, `colorDodge`,
  `colorBurn`, `hardLight`, `softLight`, `difference`, `exclusion` (brak pola — zwykły). Strona z takim trybem składa się
  na obrazie, więc w PDF jest wtedy jednym obrazem (ok. 300 dpi, najwyżej 60 Mpx), a nie wektorami.
- `layerMask` — plik maski z `images/` (PNG w skali szarości, najczęściej dłuższy bok 1024 px): jasność to widoczność
  warstwy, białe widać, czarne ukryte. Maska pokrywa pole elementu i obraca się razem z nim. Oryginał warstwy się nie
  zmienia. `layerMaskOff: true` wyłącza maskę bez jej usuwania.

`adjust` to warstwa korekcyjna: nic nie rysuje, tylko zmienia wszystko, co leży pod nią na stronie (cała strona, `x`, `y`,
`w`, `h` bez znaczenia). Obowiązują `opacity`, `hidden`, `layerMask` oraz pola korekcji: `brightness`, `contrast`,
`saturation`, `exposure`, `shadows`, `highlights`, `temperature`, `tint` (−1–1), `hue` (stopnie, −180–180) i `curves` —
krzywe `{ rgb, r, g, b }`, każda to lista punktów `[x, y]` (0–1) od ciemnych do jasnych. Zdjęcie (`image`) przyjmuje
`exposure`, `shadows`, `highlights`, `temperature`, `tint`, `hue` i `curves` tak samo, tylko dla siebie.

## Elementy

Wspólne pola: `id`, `type`, `x`, `y`, `w`, `h` (lewy górny róg i rozmiar przed obrotem), `rotation` (stopnie, zgodnie
z ruchem wskazówek, wokół środka), `opacity` (0–1), `hidden` (ukryty — nie ma go na stronie ani w eksporcie),
`locked` (zablokowany — nie da się go przesunąć ani zmienić, dopóki się go nie odblokuje), `group` (elementy z tym samym
napisem tworzą grupę — zaznaczają się i przesuwają razem). Miękki cień (każdy rodzaj): `shadow: true` i `shadowBlur`,
`shadowDist` (px), `shadowAngle` (stopnie, 0 — w górę), `shadowOpacity` (0–1), `shadowColor`; tekst z samym `shadow`
(bez `shadowBlur`) ma dawny twardy cień.

- `text`: `text` (wiersze rozdzielone `\n`), `font` (rodzina), `size` (px), `weight` (100–900), `italic`, `underline`,
  `caps` (wielkie litery), `color`, `align` (`left` / `center` / `right`), `spacing` (odstęp liter w częściach wielkości
  czcionki), `lineHeight` (wysokość wiersza w wielkościach czcionki), `outline` (grubość obrysu w częściach wielkości) i
  `outlineColor`, `bg` (kolor tła pod każdym wierszem) z `bgPadding` i `bgRadius` (w wielkościach czcionki), `curve`
(−1–1, tekst po łuku w górę albo w dół, jeden wiersz), `list` (`bullet` albo `number` — punkty lub numery przed akapitami),
`color2` i `gradientAngle` (przejście kolorów liter). Tekst łamie się do szerokości `w`; `h` program liczy sam.
- `shape`: `shape` = `rect` (`radius`), `ellipse`, `triangle`, `star`, `heart`, `bubble`, `burst`, `ribbon`, `arrowBlock`,
  `pentagon`, `octagon`, `hexagon`, `cross`, `line`, `arrow`, `doubleArrow`; `fill` (pusty — bez
  wypełnienia), `fill2` i `gradientAngle` (przejście kolorów; `gradient: "radial"` — od środka), `stroke`, `strokeWidth`, `dash`. Linia i strzałka biegną
  poziomo przez środek pola, kolor z `stroke`.
- `image`: `src` (plik z `images/`), wypełnia pole i jest przycinane („cover”) wokół punktu `focusX`, `focusY` (0–1),
  `radius` albo `mask` (`ellipse`, `arch`, `leaf`, `blob`, `hexagon`, `heart`, `star`, `triangle`), `zoom` (≥ 1 — powiększenie kadru), `flipX` (odbicie lustrzane),
  `brightness`, `contrast`, `saturation` (−1–1), `blur` i `vignette` (0–1), `filter` (`gray`, `sepia`, `warm`, `cool`, `fade`, `vivid`,
  `duotone` z kolorami `duo1` — cienie i `duo2` — światła), `removeBg` z `bgTolerance` (0–1, usunięcie jednolitego tła).
  Narzędzia AI (usuwanie tła, gumka, wyodrębnianie) nie dodają pól: wynik to nowe zdjęcie w `images/` (PNG
  z przezroczystością), a element dostaje jego `src` — poprzednie zdjęcie zostaje w historii cofania. Rozmycie tła
  zapamiętuje `bgBlur` (siła 0–1), `bgBlurSrc` (ostre zdjęcie) i `bgBlurOut` (wynik): dopóki `src` = `bgBlurOut`,
  zmiana siły liczy od ostrego zdjęcia zamiast rozmywać drugi raz.
  `pixel: true` — warstwa pikselowa: przezroczysty PNG na całą stronę, po którym się maluje. Malowanie i retusz
  nie dodają pól, wynik każdej kreski to nowe zdjęcie w `images/` (cofanie wraca do poprzedniego).
  `stroke` i `strokeWidth` — obramowanie wzdłuż kształtu zdjęcia (w całości wewnątrz ramki).
  `credit` — podpis autora, gdy licencja go wymaga (zdjęcia CC BY z Wikimedia Commons).
  Bez `src` element jest miejscem na zdjęcie (np. w szablonie) — zdjęcie upuszczone na nie trafia do środka ramki.
- `code`: `kind` (`qr`, `code128`, `ean13`), `data` albo dla Wi-Fi `qrType: "wifi"` z `ssid` i `pass`; `color` (kod),
  `bg` (tło, puste — przezroczyste). Rysowany jako kształt (ostry w PDF), biblioteka KDE Prison.
- `chart`: `chart` (`column`, `bar`, `line`, `pie`, `donut`), `data` — lista `{ label, value, color }`, `values` (false —
  bez liczb), `size` (wielkość napisów), `color` (napisy), `font`.
- `table`: `cells` — wiersze tabeli, każdy to lista tekstów komórek (wiersze i kolumny dzielą pole po równo);
  `header` (domyślnie true — pierwszy wiersz to pogrubiony nagłówek) z `headerFill` i `headerColor`, `fill` (tło komórek),
  `stripe` (kolor co drugiego wiersza), `lines` = `rows` (linie między wierszami) / `grid` (siatka z obramowaniem) / `none`,
  `stroke` i `strokeWidth` (linie), `color`, `size`, `font`, `align` (`left` / `center` / `right`), `radius`.
- `draw`: rysunek odręczny (jedna kreska) — `points` (płaska lista `x, y, x, y…` w częściach pola elementu, 0–1;
  linia biegnie gładko przez środki kolejnych odcinków), `stroke` (kolor), `strokeWidth` (px), `pen` = `pen` (pisak),
  `marker`, `highlighter` (zakreślacz — półprzezroczysty, płaskie końce) albo `neon` (świecąca poświata z jasnym rdzeniem).
  Pole elementu obejmuje kreskę z marginesem na grubość; zmiana rozmiaru rozciąga rysunek.
- `vector`: `src` (plik SVG z `images/` — ikona albo naklejka), rysowana ostro w każdym rozmiarze; `color` zastępuje
  `currentColor` (jednokolorowe ikony), `flipX`.

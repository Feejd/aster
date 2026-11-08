#!/usr/bin/env python3
# Szablony Aster Pixel — zwykłe pliki projektu bez zdjęć (miejsca na zdjęcia są puste, zdjęcie upuszczone na nie wchodzi
# do środka). Każdy pokazuje coś, co program potrafi: tryby mieszania, maski, korekcje, perspektywę, rysowanie,
# tabele, wykresy, kody QR, wiele stron.
#   python3 tools/make-grafika-templates.py apps/grafika/templates
import json, os, sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.endswith(".json"):
        os.remove(os.path.join(OUT, f))


# ——— Elementy ———

def T(text, x, y, w, size, font="Inter", weight=400, color="#141518", align="left", **kw):
    d = dict(type="text", text=text, x=x, y=y, w=w, size=size, font=font, weight=weight, color=color, align=align, lineHeight=1.1)
    d.update(kw)
    return d

def S(shape, x, y, w, h, fill="", **kw):
    d = dict(type="shape", shape=shape, x=x, y=y, w=w, h=h, fill=fill)
    d.update(kw)
    return d

def R(x, y, w, h, fill, radius=0, **kw):
    return S("rect", x, y, w, h, fill, radius=radius, **kw)

# Miękka plama światła: koło z przejściem do przezroczystości (z trybem mieszania wygląda jak poświata)
def BLOB(cx, cy, d, color, opacity=1, blend=None):
    e = S("ellipse", cx - d / 2, cy - d / 2, d, d, color, fill2="#00" + color[1:], gradient="radial", opacity=opacity)
    if blend:
        e["blend"] = blend
    return e

# Miejsce na zdjęcie
def P(x, y, w, h, **kw):
    d = dict(type="image", src="", x=x, y=y, w=w, h=h)
    d.update(kw)
    return d

# Kreska rysowana ręką: punkty strony → pole elementu i punkty w częściach pola
def DR(points, pen, color, width, **kw):
    pad = width * 2.2 if pen == "neon" else width / 2 + 2
    xs = [p[0] for p in points]; ys = [p[1] for p in points]
    x0, y0 = min(xs) - pad, min(ys) - pad
    w, h = max(xs) + pad - x0, max(ys) + pad - y0
    flat = []
    for px, py in points:
        flat += [round((px - x0) / w, 4), round((py - y0) / h, 4)]
    d = dict(type="draw", pen=pen, stroke=color, strokeWidth=width, points=flat, x=round(x0, 1), y=round(y0, 1), w=round(w, 1), h=round(h, 1))
    d.update(kw)
    return d

def TABLE(x, y, w, h, cells, **kw):
    d = dict(type="table", cells=cells, x=x, y=y, w=w, h=h)
    d.update(kw)
    return d

def CHART(x, y, w, h, kind, data, **kw):
    d = dict(type="chart", chart=kind, data=[{"label": l, "value": v, **({"color": c} if c else {})} for l, v, c in data], x=x, y=y, w=w, h=h)
    d.update(kw)
    return d

def QR(x, y, side, data, color="#141518", bg="#FFFFFF"):
    return dict(type="code", kind="qr", data=data, color=color, bg=bg, x=x, y=y, w=side, h=side)

# Warstwa korekcyjna na całą stronę
def ADJ(W, H, **kw):
    d = dict(type="adjust", x=0, y=0, w=W, h=H)
    d.update(kw)
    return d

def neon(color, size):
    return dict(shadow=True, shadowBlur=round(size * 0.45), shadowDist=0, shadowOpacity=0.95, shadowColor=color)

def soft(blur, dist, opacity=0.28, color="#000000", angle=180):
    return dict(shadow=True, shadowBlur=blur, shadowDist=dist, shadowAngle=angle, shadowOpacity=opacity, shadowColor=color)

# Perspektywa: górna krawędź węższa o t z każdej strony (części pola)
def persp(t):
    return [t, 0, 1 - t, 0, 1, 1, 0, 1]

grad = lambda a, b, angle=180: {"type": "gradient", "color": a, "color2": b, "angle": angle}
radial = lambda a, b: {"type": "radial", "color": a, "color2": b}
solid = lambda c: {"type": "color", "color": c}

# pages — kolejne strony [(tło, elementy), …] za pierwszą
def save(fname, name, category, w, h, bg, elements, print_=None, pages=None):
    doc = {"format": "aster-grafika", "version": 1, "name": name, "category": category, "width": w, "height": h}
    if print_:
        doc["print"] = {"width": print_[0], "height": print_[1]}
    n = 0
    all_pages = []
    for pbg, pels in [(bg, elements)] + list(pages or []):
        out = []
        for e in pels:
            n += 1
            e = dict(e)
            e["id"] = "e%d" % n
            out.append(e)
        all_pages.append({"background": pbg, "elements": out})
    doc["background"] = all_pages[0]["background"]
    doc["elements"] = all_pages[0]["elements"]
    if len(all_pages) > 1:
        doc["pages"] = all_pages
    with open(os.path.join(OUT, fname), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)


# ——— Media społecznościowe ———

# Poświaty w trybie Ekran, neonowa kreska, tekst świecący i sam obrys, napis po łuku, kod QR
save("01-neon-party.json", "Neon Night", "Instagram", 1080, 1080, solid("#08080F"), [
    BLOB(240, 260, 980, "#FF2D95", 0.9, "screen"),
    BLOB(880, 820, 1100, "#3A4BFF", 0.95, "screen"),
    BLOB(860, 180, 620, "#00E5FF", 0.55, "screen"),
    T("NIGHT", 60, 190, 960, 250, "Bebas Neue", 400, "#FFFFFF", "center", **neon("#FF2D95", 250)),
    T("PARTY", 60, 430, 960, 250, "Bebas Neue", 400, "#00FFFFFF", "center", outline=0.025, outlineColor="#7DF9FF", **neon("#00E5FF", 200)),
    DR([(150, 760), (290, 700), (430, 780), (570, 700), (710, 780), (850, 700), (930, 740)], "neon", "#FFE600", 9),
    T("sobota · 22:00 · klub Aura", 140, 820, 800, 44, "Inter", 600, "#FFFFFF", "center", curve=-0.18, spacing=0.06),
    R(892, 892, 136, 136, "#FFFFFF", 22),
    QR(904, 904, 112, "https://klubaura.pl/bilety"),
])

# Napis z przejściem kolorów w perspektywie, wybuch z cieniem, zakreślacz pod tekstem
save("02-mega-wyprzedaz.json", "Mega wyprzedaż", "Instagram", 1080, 1080, grad("#FFE66D", "#FF9F43", 160), [
    S("burst", 620, 90, 380, 380, "#FF3D6E", rotation=12, **soft(40, 18, 0.3, "#7A1F00")),
    T("-70%", 640, 210, 340, 124, "Anton", 400, "#FFFFFF", "center", rotation=12),
    T("MEGA", 80, 300, 700, 150, "Anton", 400, "#1B1C20"),
    T("WYPRZEDAŻ", 50, 450, 980, 190, "Anton", 400, "#1B1C20", "center", color2="#FF3D6E", gradientAngle=90, warpN=persp(0.05)),
    DR([(110, 812), (970, 806)], "highlighter", "#FFFFFF", 70),
    T("cały sklep · tylko do niedzieli", 90, 782, 900, 52, "Inter", 800, "#1B1C20", "center"),
    T("sklep.pl", 90, 930, 900, 36, "Inter", 600, "#5B3200", "center", spacing=0.12),
])

# Zdjęcie wygaszone maską, tekst szeryfowy, przycisk-pigułka, strzałka narysowana pisakiem
save("03-nowa-kolekcja.json", "Nowa kolekcja", "Relacja", 1080, 1920, grad("#F4EAE1", "#E6D3C3", 180), [
    P(0, 0, 1080, 1300, layerMask="fade:180:0.55:1"),
    T("Nowa", 80, 1080, 920, 190, "Playfair Display", 400, "#2B1E16"),
    T("kolekcja", 80, 1270, 920, 190, "Playfair Display", 400, "#2B1E16", italic=True),
    T("JESIEŃ / ZIMA 2026", 86, 1520, 800, 40, "Inter", 600, "#7B6252", spacing=0.18),
    R(80, 1640, 440, 116, "#2B1E16", 58, **soft(30, 14, 0.25)),
    T("Zobacz w sklepie", 80, 1673, 440, 44, "Inter", 600, "#F4EAE1", "center"),
    DR([(570, 1760), (650, 1690), (760, 1700), (830, 1650)], "pen", "#2B1E16", 7),
    DR([(790, 1640), (830, 1650), (812, 1690)], "pen", "#2B1E16", 7),
])

# Wykresy (pierścień, słupki), duże liczby na kartach, poświata
save("04-infografika.json", "Rok w liczbach", "Relacja", 1080, 1920, grad("#111827", "#1E293B", 180), [
    BLOB(900, 260, 900, "#6366F1", 0.6, "screen"),
    BLOB(160, 1600, 900, "#14B8A6", 0.45, "screen"),
    T("Rok w liczbach", 80, 150, 920, 104, "Inter", 800, "#FFFFFF", spacing=-0.02),
    T("Podsumowanie 2026 naszej pracowni", 84, 290, 900, 40, "Inter", 400, "#A5B4CC"),
    R(80, 420, 920, 600, "#FFFFFF", 48, opacity=0.06),
    CHART(130, 470, 820, 500, "donut", [("Online", 58, "#818CF8"), ("Sklep", 27, "#2DD4BF"), ("Targi", 15, "#FBBF24")], size=34, color="#E2E8F0", font="Inter"),
    R(80, 1060, 445, 300, "#FFFFFF", 40, opacity=0.06),
    T("12 400", 110, 1110, 400, 96, "Inter", 800, "#FFFFFF"),
    T("zamówień", 112, 1230, 400, 38, "Inter", 500, "#A5B4CC"),
    R(555, 1060, 445, 300, "#FFFFFF", 40, opacity=0.06),
    T("4,9 ★", 585, 1110, 400, 96, "Inter", 800, "#FBBF24"),
    T("średnia ocen", 587, 1230, 400, 38, "Inter", 500, "#A5B4CC"),
    R(80, 1400, 920, 420, "#FFFFFF", 48, opacity=0.06),
    CHART(120, 1440, 840, 340, "column", [("I", 18, "#818CF8"), ("II", 26, "#818CF8"), ("III", 31, "#818CF8"), ("IV", 44, "#2DD4BF")], size=30, color="#E2E8F0", font="Inter"),
])

# Produkt z cieniem i odbiciem (lustro + wygaszenie), poświata, cena
save("05-premiera.json", "Premiera produktu", "Instagram", 1080, 1080, radial("#FFFFFF", "#DCE3EE"), [
    BLOB(540, 470, 820, "#A5B4FC", 0.55, "multiply"),
    P(330, 170, 420, 520, radius=36, **soft(60, 30, 0.3, "#1E293B")),
    P(330, 690, 420, 520, radius=36, rotation=180, flipX=True, opacity=0.35, layerMask="fade:0:0.55:1"),
    T("NOWOŚĆ", 80, 80, 500, 32, "Inter", 700, "#4F46E5", spacing=0.3),
    T("Aster One", 80, 120, 500, 76, "Inter", 800, "#0F172A"),
    R(780, 820, 220, 90, "#0F172A", 45),
    T("399 zł", 780, 840, 220, 46, "Inter", 700, "#FFFFFF", "center"),
])

# Dwa zdjęcia obok siebie, etykiety-pigułki, strzałka markerem
save("06-przed-i-po.json", "Przed i po", "Instagram", 1080, 1080, solid("#F2F3F5"), [
    P(40, 140, 490, 760, radius=32),
    P(550, 140, 490, 760, radius=32),
    R(70, 170, 160, 64, "#FFFFFF", 32),
    T("PRZED", 70, 186, 160, 30, "Inter", 700, "#141518", "center", spacing=0.1),
    R(850, 170, 160, 64, "#141518", 32),
    T("PO", 850, 186, 160, 30, "Inter", 700, "#FFFFFF", "center", spacing=0.1),
    T("Metamorfoza salonu", 40, 40, 1000, 64, "Inter", 800, "#141518", "center"),
    DR([(420, 980), (540, 1010), (660, 975)], "marker", "#FF5A36", 12),
    DR([(630, 955), (660, 975), (632, 1003)], "marker", "#FF5A36", 12),
    T("3 dni pracy · 2 400 zł", 40, 955, 460, 36, "Inter", 600, "#5B6270"),
])

# Karuzela: trzy strony, zakreślacz pod słowami kluczowymi, numery w kołach
save("07-karuzela-porady.json", "3 porady na lepsze zdjęcia", "Instagram", 1080, 1080, solid("#FFF4E3"), [
    T("3 porady", 80, 320, 920, 150, "Inter", 800, "#1C1917"),
    DR([(90, 560), (840, 552)], "highlighter", "#FFB347", 90),
    T("na lepsze zdjęcia telefonem", 80, 510, 920, 84, "Inter", 700, "#1C1917"),
    T("przesuń →", 80, 900, 920, 40, "Inter", 600, "#A16207"),
], pages=[
    (solid("#FFF4E3"), [
        S("ellipse", 80, 120, 140, 140, "#1C1917"), T("1", 80, 150, 140, 80, "Inter", 800, "#FFF4E3", "center"),
        T("Światło z boku", 80, 340, 920, 100, "Inter", 800, "#1C1917"),
        DR([(84, 470), (560, 466)], "highlighter", "#FFB347", 60),
        T("Stań bokiem do okna — twarz dostaje miękki cień i głębię.", 80, 500, 900, 56, "Inter", 500, "#44403C", lineHeight=1.3),
    ]),
    (solid("#FFF4E3"), [
        S("ellipse", 80, 120, 140, 140, "#1C1917"), T("2", 80, 150, 140, 80, "Inter", 800, "#FFF4E3", "center"),
        T("Trójpodział kadru", 80, 340, 920, 100, "Inter", 800, "#1C1917"),
        DR([(84, 470), (640, 466)], "highlighter", "#FFB347", 60),
        T("Najważniejszą rzecz ustaw na przecięciu linii siatki, nie na środku.", 80, 500, 900, 56, "Inter", 500, "#44403C", lineHeight=1.3),
    ]),
])

# Plamy w trybie Mnożenie na jasnym tle, duży tytuł
save("08-okladka-fb.json", "Okładka studia", "Facebook", 1640, 624, solid("#F7F7F5"), [
    BLOB(1250, 120, 900, "#FF8A65", 0.85, "multiply"),
    BLOB(1520, 560, 800, "#7C9CFF", 0.85, "multiply"),
    BLOB(1050, 600, 600, "#FFD54F", 0.7, "multiply"),
    T("Studio Forma", 120, 200, 900, 120, "Inter", 800, "#141518", spacing=-0.02),
    T("projektowanie wnętrz · Kraków", 124, 350, 900, 42, "Inter", 500, "#5B6270"),
])

# ——— YouTube i prezentacje ———

# Zdjęcie z korekcją (kontrast, nasycenie), poświata za osobą, tekst z grubym obrysem, neonowa strzałka
save("09-yt-miniatura.json", "To zmienia wszystko", "YouTube", 1280, 720, grad("#1F2937", "#0B0F19", 135), [
    ADJ(1280, 720, contrast=0.18, saturation=0.25, shadows=0.15),
    BLOB(980, 420, 760, "#FFE600", 0.8, "screen"),
    P(720, 40, 520, 680, mask="blob"),
    T("TO ZMIENIA", 50, 120, 700, 128, "Anton", 400, "#FFFFFF", outline=0.07, outlineColor="#0B0F19", rotation=-3),
    T("WSZYSTKO", 50, 270, 700, 150, "Anton", 400, "#FFE600", outline=0.07, outlineColor="#0B0F19", rotation=-3),
    DR([(160, 560), (300, 600), (470, 560), (600, 500)], "neon", "#FF3B3B", 10),
    DR([(560, 486), (600, 500), (582, 540)], "neon", "#FF3B3B", 10),
])

# Trzy slajdy: tytuł z poświatą, wykresy na kartach, tabela planu
save("10-raport.json", "Raport roczny", "Slajd", 1920, 1080, solid("#0E1020"), [
    BLOB(1500, 180, 1300, "#5B5BFF", 0.85, "screen"),
    BLOB(1760, 960, 900, "#00C2A8", 0.6, "screen"),
    T("RAPORT 2026", 124, 330, 1200, 36, "Inter", 700, "#8C91FF", spacing=0.3),
    T("Rok, który nas\nzaskoczył", 120, 390, 1300, 150, "Inter", 800, "#FFFFFF", spacing=-0.02),
    T("Wyniki, liczby i plan na kolejny rok", 124, 740, 1200, 52, "Inter", 400, "#B9BCD0"),
], pages=[
    (solid("#F4F5F8"), [
        T("Sprzedaż rośnie co kwartał", 120, 100, 1600, 84, "Inter", 800, "#141518"),
        R(120, 250, 1050, 720, "#FFFFFF", 40),
        CHART(170, 300, 950, 620, "column", [("I kw.", 120, "#5B5BFF"), ("II kw.", 180, "#5B5BFF"), ("III kw.", 240, "#5B5BFF"), ("IV kw.", 310, "#00C2A8")], size=32, color="#3A3D46", font="Inter"),
        R(1220, 250, 580, 340, "#5B5BFF", 40),
        T("+158%", 1270, 310, 480, 140, "Inter", 800, "#FFFFFF"),
        T("wzrost rok do roku", 1274, 470, 480, 40, "Inter", 500, "#DADBFF"),
        R(1220, 630, 580, 340, "#FFFFFF", 40),
        CHART(1260, 670, 500, 260, "donut", [("Online", 62, "#5B5BFF"), ("Sklepy", 38, "#00C2A8")], size=30, color="#3A3D46", font="Inter"),
    ]),
    (solid("#FFFFFF"), [
        T("Plan na 2027", 120, 100, 1600, 84, "Inter", 800, "#141518"),
        TABLE(120, 260, 1680, 640, [["Cel", "Termin", "Odpowiada"], ["Nowy sklep w Gdańsku", "marzec", "Anna"],
                                    ["Aplikacja mobilna", "czerwiec", "Tomek"], ["Program lojalnościowy", "wrzesień", "Ola"]],
              header=True, headerFill="#141518", headerColor="#FFFFFF", fill="#FFFFFF", stripe="#F4F5F8", lines="none",
              color="#141518", size=40, font="Inter", radius=28),
    ]),
])

# ——— Druk ———

# Zdjęcie na całą stronę, korekcja czarno-biała z krzywą, kolor w trybie Mnożenie (duotone), tytuł w perspektywie,
# tabela występów, kod QR do biletów
save("11-plakat-festiwal.json", "Letnie brzmienie", "Plakat", 3508, 4961, solid("#111111"), [
    P(0, 1350, 3508, 1500, layerMask="fade:180:0.6:1"),
    ADJ(3508, 4961, saturation=-1, curves={"rgb": [[0, 0], [0.25, 0.14], [0.75, 0.9], [1, 1]]}),
    R(0, 0, 3508, 4961, "#FF3D6E", blend="multiply"),
    T("LETNIE\nBRZMIENIE", 150, 300, 3208, 760, "Anton", 400, "#FFFFFF", "center", lineHeight=0.95, warpN=persp(0.06)),
    T("FESTIWAL MUZYKI · 18–20 LIPCA", 200, 2700, 3108, 150, "Inter", 800, "#FFFFFF", "center", spacing=0.12),
    TABLE(300, 3020, 2908, 980, [["Piątek", "Sobota", "Niedziela"], ["Nocne Tramwaje", "Lato w Mieście", "Ciche Fale"],
                                 ["Echo Parku", "Dziewczyny z Portu", "Złote Godziny"]],
          header=True, headerFill="#FFFFFF", headerColor="#E0245E", fill="", lines="rows", stroke="#66FFFFFF",
          strokeWidth=6, color="#FFFFFF", size=110, font="Inter", align="center", radius=60),
    T("Park Miejski, scena nad stawem", 300, 4330, 2300, 140, "Inter", 700, "#FFFFFF"),
    T("wstęp za okazaniem biletu", 300, 4510, 2300, 100, "Inter", 400, "#FFD6E2"),
    R(2740, 4160, 520, 520, "#FFFFFF", 60),
    QR(2780, 4200, 440, "https://festiwal.pl/bilety"),
], (297, 420))

# Zdjęcie w łuku, tytuł szeryfowy, cennik w tabeli z paskami, podkreślenie markerem, QR do menu
save("12-menu-kawiarni.json", "Menu kawiarni", "Menu", 2480, 3508, solid("#F6F0E6"), [
    P(1380, 220, 900, 1320, mask="arch", **soft(80, 40, 0.18, "#3B2A1E")),
    T("Café", 200, 300, 1100, 340, "Playfair Display", 700, "#2E2219"),
    T("Aster", 200, 640, 1100, 340, "Playfair Display", 400, "#B5651D", italic=True),
    T("świeżo palona kawa · domowe ciasta", 200, 1070, 1100, 60, "Inter", 500, "#6B5A4A"),
    DR([(200, 1200), (700, 1186), (1040, 1204)], "marker", "#B5651D", 14),
    TABLE(200, 1720, 2080, 1080, [["Kawa", "Mała", "Duża"], ["Espresso", "9 zł", "12 zł"], ["Cappuccino", "13 zł", "16 zł"],
                                  ["Latte owsiane", "15 zł", "18 zł"], ["Flat white", "14 zł", "17 zł"], ["Matcha latte", "16 zł", "19 zł"]],
          header=True, headerFill="#2E2219", headerColor="#F6F0E6", fill="", stripe="#EDE2D1", lines="none",
          color="#2E2219", size=62, font="Inter", radius=44),
    T("Pełne menu i ciasta dnia", 200, 3020, 1500, 70, "Inter", 700, "#2E2219"),
    T("zeskanuj kod telefonem", 200, 3110, 1500, 52, "Inter", 400, "#6B5A4A"),
    QR(1980, 2940, 300, "https://cafeaster.pl/menu", "#2E2219", "#F6F0E6"),
], (210, 297))

# Zdjęcie w kole z obramowaniem, wykres umiejętności, tabela doświadczenia, QR do profilu
save("13-cv.json", "CV nowoczesne", "CV", 2480, 3508, solid("#FFFFFF"), [
    R(0, 0, 820, 3508, "#131A2E"),
    P(160, 220, 500, 500, mask="ellipse", stroke="#FFFFFF", strokeWidth=18),
    T("KONTAKT", 140, 860, 560, 44, "Inter", 700, "#8C9BC4", spacing=0.2),
    T("anna.nowak@poczta.pl\n+48 600 100 200\nKraków", 140, 940, 560, 46, "Inter", 400, "#FFFFFF", lineHeight=1.6),
    T("UMIEJĘTNOŚCI", 140, 1300, 560, 44, "Inter", 700, "#8C9BC4", spacing=0.2),
    CHART(120, 1380, 600, 700, "bar", [("Figma", 95, "#7C9CFF"), ("Badania", 80, "#7C9CFF"), ("HTML/CSS", 70, "#7C9CFF"), ("Animacja", 60, "#7C9CFF")],
          size=36, color="#FFFFFF", font="Inter", values=False),
    T("PROFIL", 140, 2780, 560, 44, "Inter", 700, "#8C9BC4", spacing=0.2),
    R(140, 2860, 300, 300, "#FFFFFF", 24),
    QR(160, 2880, 260, "https://portfolio.example/anna"),
    T("Anna Nowak", 980, 230, 1400, 190, "Inter", 800, "#131A2E", spacing=-0.02),
    T("Projektantka produktów cyfrowych", 984, 460, 1400, 72, "Inter", 500, "#5B6270"),
    T("O mnie", 980, 700, 1400, 70, "Inter", 800, "#131A2E"),
    T("Projektuję aplikacje, z których ludzie korzystają chętnie i bez instrukcji. Łączę badania z prototypowaniem.",
      980, 800, 1360, 52, "Inter", 400, "#3D4048", lineHeight=1.45),
    T("Doświadczenie", 980, 1200, 1400, 70, "Inter", 800, "#131A2E"),
    TABLE(980, 1310, 1360, 900, [["Lata", "Firma i stanowisko"], ["2023–", "Nowa Aplikacja · starsza projektantka"],
                                 ["2020–23", "Studio Pixel · projektantka UX"], ["2018–20", "Agencja Kreska · młodsza projektantka"]],
          header=True, headerFill="#EEF1FA", headerColor="#131A2E", fill="", lines="rows", stroke="#E6E7EA",
          strokeWidth=3, color="#3D4048", size=44, font="Inter", radius=24),
    T("Wykształcenie", 980, 2400, 1400, 70, "Inter", 800, "#131A2E"),
    T("Akademia Sztuk Pięknych w Krakowie\nWzornictwo, 2018", 980, 2500, 1360, 52, "Inter", 400, "#3D4048", lineHeight=1.45),
], (210, 297))

# Imiona pismem odręcznym, zdjęcie w łuku z miękkim brzegiem, ozdobnik narysowany cienkim pisakiem, QR do potwierdzenia
save("14-zaproszenie-slub.json", "Zaproszenie ślubne", "Zaproszenie", 1748, 2480, solid("#FBF8F3"), [
    P(474, 200, 800, 1000, mask="arch", layerMask="radial:0.75:1"),
    T("Julia & Marek", 100, 1260, 1548, 210, "Great Vibes", 400, "#5C4A3D", "center"),
    DR([(574, 1540), (740, 1510), (874, 1546), (1008, 1510), (1174, 1540)], "pen", "#B79E83", 4),
    T("z radością zapraszają na ślub i wesele", 200, 1600, 1348, 64, "Lora", 400, "#6B5A4A", "center", italic=True),
    T("12 września 2026 · 15:00", 200, 1760, 1348, 76, "Lora", 700, "#3D3027", "center"),
    T("Kościół św. Anny, Kraków · przyjęcie w Dworku pod Lipami", 200, 1880, 1348, 50, "Inter", 400, "#6B5A4A", "center", lineHeight=1.4),
    QR(774, 2080, 200, "https://slub.example/potwierdz", "#5C4A3D", "#FBF8F3"),
    T("potwierdź przybycie", 574, 2300, 600, 40, "Inter", 500, "#8C7A6B", "center"),
], (148, 210))

# Napis z przejściem kolorów po łuku, konfetti narysowane markerami, gwiazdki
save("15-kartka-urodziny.json", "Sto lat!", "Kartka", 1748, 1240, grad("#FFE0EC", "#D8F3FF", 135), [
    DR([(160, 180), (230, 150)], "marker", "#FF3D6E", 16), DR([(1500, 200), (1560, 260)], "marker", "#7F5AF0", 16),
    DR([(260, 1000), (330, 1050)], "marker", "#FFB300", 16), DR([(1420, 980), (1480, 940)], "marker", "#00B3A4", 16),
    DR([(1250, 140), (1300, 120)], "marker", "#FFB300", 16), DR([(420, 120), (470, 170)], "marker", "#00B3A4", 16),
    S("star", 1500, 760, 120, 120, "#FFB300", rotation=14), S("star", 170, 600, 90, 90, "#7F5AF0", rotation=-10),
    T("Sto lat!", 200, 330, 1348, 300, "Pacifico", 400, "#FF3D6E", "center", color2="#7F5AF0", gradientAngle=90, curve=0.22),
    T("Wszystkiego najlepszego, dużo uśmiechu\ni samych dobrych dni!", 250, 800, 1248, 60, "Inter", 500, "#3D3A4B", "center", lineHeight=1.4),
], (148, 105))

# Dwie strony: przód z poświatami, tył z kodem QR i danymi
save("16-wizytowka.json", "Wizytówka", "Wizytówka", 1063, 591, solid("#0E0F12"), [
    BLOB(860, 80, 700, "#6C5CE7", 0.9, "screen"),
    BLOB(1000, 520, 560, "#00CEC9", 0.7, "screen"),
    T("Marta Lis", 70, 230, 700, 76, "Inter", 800, "#FFFFFF", spacing=-0.02),
    T("fotografka", 74, 320, 700, 34, "Inter", 500, "#B7B9C4", spacing=0.08),
], (90, 50), pages=[
    (solid("#FFFFFF"), [
        T("Marta Lis", 70, 90, 600, 52, "Inter", 800, "#0E0F12"),
        T("+48 600 700 800\nmarta@lisfoto.pl\nlisfoto.pl", 70, 190, 600, 34, "Inter", 400, "#3D4048", lineHeight=1.6),
        R(760, 160, 240, 240, "#F2F3F5", 28),
        QR(780, 180, 200, "https://lisfoto.pl"),
    ]),
])

# Ulotka: zakreślacz, cennik w tabeli, kod QR, kółko narysowane pisakiem
save("17-ulotka-korepetycje.json", "Korepetycje z matematyki", "Ulotka", 1748, 2480, solid("#FFFFFF"), [
    R(0, 0, 1748, 820, "#2D6BFF"),
    BLOB(1500, 120, 900, "#7FB2FF", 0.7, "screen"),
    T("Matematyka\nbez stresu", 130, 190, 1500, 170, "Inter", 800, "#FFFFFF", spacing=-0.02),
    T("korepetycje dla szkoły podstawowej i liceum", 134, 620, 1500, 56, "Inter", 500, "#DCE6FF"),
    DR([(130, 1010), (940, 1004)], "highlighter", "#FFE066", 80),
    T("Pierwsza lekcja gratis", 130, 965, 1500, 80, "Inter", 800, "#141518"),
    TABLE(130, 1180, 1488, 640, [["Zajęcia", "Czas", "Cena"], ["Indywidualne", "60 min", "90 zł"], ["W parze", "60 min", "60 zł / os."], ["Przed egzaminem", "90 min", "130 zł"]],
          header=True, headerFill="#141518", headerColor="#FFFFFF", fill="", stripe="#F2F5FF", lines="none",
          color="#141518", size=52, font="Inter", radius=36),
    T("Zapisy", 130, 1960, 900, 80, "Inter", 800, "#141518"),
    T("tel. 600 300 400\nlub zeskanuj kod", 130, 2070, 900, 54, "Inter", 400, "#3D4048", lineHeight=1.45),
    QR(1250, 1940, 368, "https://korki.example/zapisy"),
    DR([(1210, 1920), (1450, 1890), (1650, 1980), (1650, 2290), (1420, 2350), (1220, 2300), (1200, 1990), (1250, 1915)], "pen", "#2D6BFF", 6),
], (148, 210))

# Plan tygodnia w kolorowej tabeli-siatce
save("18-plan-tygodnia.json", "Plan tygodnia", "Plan", 3508, 2480, solid("#F7F7F5"), [
    T("Mój tydzień", 200, 160, 2000, 190, "Inter", 800, "#141518", spacing=-0.02),
    DR([(205, 380), (980, 372)], "highlighter", "#B8F2E6", 70),
    T("planuj spokojnie, po jednym kroku", 210, 360, 2000, 64, "Inter", 500, "#3D4048"),
    TABLE(200, 600, 3108, 1700, [["", "Pon", "Wt", "Śr", "Czw", "Pt"], ["Rano", "", "", "", "", ""], ["Południe", "", "", "", "", ""],
                                 ["Popołudnie", "", "", "", "", ""], ["Wieczór", "", "", "", "", ""]],
          header=True, headerFill="#141518", headerColor="#FFFFFF", fill="#FFFFFF", stripe="#EEF6F4", lines="grid",
          stroke="#E6E7EA", strokeWidth=4, color="#141518", size=64, font="Inter", align="center", radius=48),
], (297, 210))

print("szablonów:", len([f for f in os.listdir(OUT) if f.endswith(".json")]))

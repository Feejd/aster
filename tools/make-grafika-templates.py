#!/usr/bin/env python3
# Generuje szablony Grafiki — zwykłe pliki projektu bez zdjęć (miejsca na zdjęcia są puste):
#   python3 tools/make-grafika-templates.py apps/grafika/templates
import json, os, sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.endswith(".json"):
        os.remove(os.path.join(OUT, f))

def T(text, x, y, w, size, font="Geist", weight=400, color="#16181D", align="center", **kw):
    d = dict(type="text", text=text, x=x, y=y, w=w, size=size, font=font, weight=weight, color=color, align=align)
    d.setdefault("lineHeight", 1.15)
    d.update(kw)
    return d

def S(shape, x, y, w, h, fill="", **kw):
    d = dict(type="shape", shape=shape, x=x, y=y, w=w, h=h, fill=fill)
    d.update(kw)
    return d

def R(x, y, w, h, fill, radius=0, **kw):
    return S("rect", x, y, w, h, fill, radius=radius, **kw)

def LINE(x, y, w, color, width, **kw):
    return S("line", x, y - max(24, width * 4) / 2, w, max(24, width * 4), "", stroke=color, strokeWidth=width, **kw)

# Puste miejsce na zdjęcie (zdjęcie upuszczone albo kliknięte w panelu trafia do środka)
def P(x, y, w, h, **kw):
    d = dict(type="image", src="", x=x, y=y, w=w, h=h)
    d.update(kw)
    return d

def shadow(blur, dist=0, angle=160, opacity=0.35, color=None):
    d = dict(shadow=True, shadowBlur=blur, shadowDist=dist, shadowAngle=angle, shadowOpacity=opacity)
    if color:
        d["shadowColor"] = color
    return d

# pages — kolejne strony [(tło, elementy), …] za pierwszą (karuzela, wizytówka dwustronna, prezentacja)
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

grad = lambda a, b, angle=180: {"type": "gradient", "color": a, "color2": b, "angle": angle}
radial = lambda a, b: {"type": "radial", "color": a, "color2": b}
solid = lambda c: {"type": "color", "color": c}

# ——— Instagram (1080×1080) ———
save("01-wyprzedaz.json", "Wyprzedaż", "Instagram", 1080, 1080, grad("#FF9A8B", "#FF4F81", 135), [
    S("ellipse", -160, -180, 560, 560, "#FFFFFF", opacity=0.14),
    S("ellipse", 760, 720, 480, 480, "#FFFFFF", opacity=0.12),
    T("WIELKA", 90, 250, 900, 92, "Inter Display", 800, "#FFFFFF", spacing=0.12, caps=True),
    T("WYPRZEDAŻ", 40, 350, 1000, 140, "Inter Display", 900, "#FFFFFF", caps=True, shadow=True, shadowColor="#40B0003A"),
    S("ellipse", 390, 560, 300, 300, "#FFE600", rotation=-8),
    T("-50%", 390, 660, 300, 84, "Inter Display", 900, "#E0234E", rotation=-8),
    T("tylko w ten weekend · sklep.pl", 90, 930, 900, 38, "Geist", 500, "#FFFFFF"),
])
save("02-cytat-dnia.json", "Cytat dnia", "Instagram", 1080, 1080, solid("#F5F1EA"), [
    T("“", 90, 120, 900, 300, "Noto Serif", 700, "#C8A97E", lineHeight=1.0),
    T("Najlepszy moment na zasadzenie drzewa był dwadzieścia lat temu. Drugi najlepszy jest teraz.", 120, 390, 840, 64, "Noto Serif", 400, "#2B2B2B", italic=True, lineHeight=1.3),
    LINE(480, 800, 120, "#C8A97E", 4),
    T("PRZYSŁOWIE CHIŃSKIE", 140, 840, 800, 28, "Geist", 600, "#7A6A55", spacing=0.2, caps=True),
])
save("03-nowosc.json", "Nowość w menu", "Instagram", 1080, 1080, solid("#14161C"), [
    R(70, 70, 940, 940, "", 48, stroke="#FFB300", strokeWidth=4),
    T("NOWOŚĆ", 140, 170, 800, 40, "Geist", 700, "#FFB300", spacing=0.4),
    T("Sernik baskijski", 110, 260, 860, 120, "Noto Serif", 700, "#FFFFFF", lineHeight=1.05),
    T("kremowy w środku, przypieczony z wierzchu — od piątku w naszej kawiarni", 170, 560, 740, 40, "Geist", 400, "#C9CCD6", lineHeight=1.35),
    S("ellipse", 440, 740, 200, 200, "#FFB300"),
    T("14 zł", 440, 805, 200, 64, "Inter Display", 900, "#14161C"),
])

# ——— Relacje (1080×1920) ———
save("04-story-zapraszamy.json", "Zapraszamy", "Relacja", 1080, 1920, radial("#FFB199", "#E8457C"), [
    S("star", 120, 220, 120, 120, "#FFFFFF", opacity=0.8, rotation=12),
    S("star", 840, 360, 80, 80, "#FFFFFF", opacity=0.7, rotation=-10),
    S("star", 780, 1500, 140, 140, "#FFFFFF", opacity=0.6),
    T("Zapraszamy", 40, 580, 1000, 180, "Z003", 400, "#FFFFFF", shadow=True, shadowColor="#40A01050"),
    T("na dzień otwarty", 90, 820, 900, 84, "Geist", 700, "#FFFFFF"),
    R(240, 1080, 600, 130, "#FFFFFF", 65),
    T("sobota · 12:00", 240, 1112, 600, 58, "Geist", 700, "#E8457C"),
    T("ul. Kwiatowa 7, Kraków", 90, 1290, 900, 44, "Geist", 500, "#FFFFFF"),
])
save("05-story-pytanie.json", "Pytanie do Was", "Relacja", 1080, 1920, grad("#7F5AF0", "#2CB1BC", 160), [
    T("PYTANIE DO WAS", 90, 380, 900, 52, "Geist", 800, "#FFFFFF", spacing=0.25),
    R(110, 540, 860, 720, "#FFFFFF", 56),
    T("Kawa czy herbata na dobry początek dnia?", 170, 630, 740, 76, "Inter Display", 800, "#1F1B3A", lineHeight=1.1),
    R(190, 1040, 320, 110, "#7F5AF0", 55),
    T("Kawa", 190, 1065, 320, 52, "Geist", 700, "#FFFFFF"),
    R(570, 1040, 320, 110, "#2CB1BC", 55),
    T("Herbata", 570, 1065, 320, 52, "Geist", 700, "#FFFFFF"),
    T("odpowiedz w wiadomości ↓", 90, 1360, 900, 42, "Geist", 500, "#FFFFFF", opacity=0.9),
])

# ——— Plakaty ———
save("06-plakat-koncert.json", "Koncert w parku", "Plakat", 3508, 4961, grad("#0F2027", "#2C5364", 180), [
    S("ellipse", 1754 - 1300, 600, 2600, 2600, "#FFB300", opacity=0.92),
    S("ellipse", 1754 - 1000, 900, 2000, 2000, "#FF7043", opacity=0.9),
    T("KONCERT", 200, 1500, 3108, 620, "Inter Display", 900, "#FFFFFF", spacing=0.02, shadow=True),
    T("W PARKU", 200, 2150, 3108, 380, "Inter Display", 300, "#FFFFFF", spacing=0.3),
    LINE(1254, 3420, 1000, "#FFB300", 22),
    T("Sobota, 21 czerwca · 19:00", 200, 3580, 3108, 190, "Geist", 700, "#FFFFFF"),
    T("Park Miejski, scena przy fontannie · wstęp wolny", 300, 3880, 2908, 130, "Geist", 400, "#C9D6E2"),
    T("zespoły z naszej okolicy · strefa dla dzieci · food trucki", 300, 4400, 2908, 88, "Geist", 500, "#FFB300", caps=True, spacing=0.06),
], (297, 420))
save("07-plakat-kiermasz.json", "Kiermasz ciast", "Plakat", 2480, 3508, solid("#FFF4E0"), [
    R(0, 0, 2480, 900, "#E85D75"),
    S("heart", 1040, 640, 400, 360, "#FFFFFF"),
    T("Kiermasz", 140, 1180, 2200, 420, "Z003", 400, "#E85D75"),
    T("CIAST DOMOWYCH", 140, 1640, 2200, 210, "Inter Display", 900, "#4A2C2A", spacing=0.06),
    T("Cały dochód przeznaczamy na wycieczkę klasy 3b", 300, 2000, 1880, 110, "Geist", 400, "#6B4E45", lineHeight=1.3),
    R(540, 2520, 1400, 320, "#4A2C2A", 160),
    T("niedziela · 10:00–14:00", 540, 2610, 1400, 120, "Geist", 700, "#FFF4E0"),
    T("Szkoła Podstawowa nr 5, hol główny", 140, 3060, 2200, 100, "Geist", 500, "#6B4E45"),
], (210, 297))

# ——— Zaproszenia ———
save("08-zaproszenie-urodziny.json", "Urodziny", "Zaproszenie", 1748, 2480, radial("#FFFFFF", "#DDE7FF"), [
    S("star", 180, 200, 180, 180, "#FFB300", rotation=-12),
    S("star", 1380, 320, 140, 140, "#FF7AA2", rotation=15),
    S("ellipse", 1320, 1980, 260, 260, "#7AD3FF", opacity=0.8),
    S("ellipse", 150, 2050, 180, 180, "#B4F07A", opacity=0.8),
    T("Zapraszam na moje", 120, 520, 1508, 110, "Geist", 600, "#3D4A7A"),
    T("urodziny!", 80, 680, 1588, 360, "Z003", 400, "#FF5A8A"),
    T("Kuba kończy 7 lat", 120, 1150, 1508, 120, "Inter Display", 800, "#3D4A7A"),
    LINE(674, 1400, 400, "#FFB300", 12, dash=True),
    T("sobota, 14 marca, godz. 15:00\nSala zabaw „Bajka”, ul. Leśna 3", 120, 1500, 1508, 84, "Geist", 500, "#3D4A7A", lineHeight=1.45),
    T("Potwierdź do 7 marca: 600 100 200", 120, 1820, 1508, 66, "Geist", 400, "#6B78A8"),
], (148, 210))
save("09-zaproszenie-slub.json", "Ślub", "Zaproszenie", 1748, 2480, solid("#FBF8F3"), [
    R(90, 90, 1568, 2300, "", 0, stroke="#C8A97E", strokeWidth=6),
    R(130, 130, 1488, 2220, "", 0, stroke="#C8A97E", strokeWidth=2),
    T("Z radością zapraszamy na nasz ślub", 220, 420, 1308, 70, "Noto Serif", 400, "#7A6A55", italic=True),
    T("Anna", 200, 640, 1348, 300, "Z003", 400, "#3B3226"),
    T("&", 200, 930, 1348, 160, "Noto Serif", 400, "#C8A97E", italic=True),
    T("Piotr", 200, 1080, 1348, 300, "Z003", 400, "#3B3226"),
    LINE(724, 1500, 300, "#C8A97E", 4),
    T("12 WRZEŚNIA 2026 · GODZ. 16:00", 220, 1620, 1308, 54, "Geist", 600, "#3B3226", spacing=0.1),
    T("Kościół św. Anny w Wilanowie\nprzyjęcie w Dworku pod Lipami", 220, 1760, 1308, 66, "Noto Serif", 400, "#7A6A55", lineHeight=1.5),
], (148, 210))

# ——— CV (A4) ———
side = "#24324A"
save("10-cv.json", "CV — nowoczesne", "CV", 2480, 3508, solid("#FFFFFF"), [
    R(0, 0, 820, 3508, side),
    S("ellipse", 160, 190, 500, 500, "#3A4D6E", stroke="#FFFFFF", strokeWidth=10),
    T("zaznacz i kliknij\n„Zamień…”", 170, 380, 480, 40, "Geist", 400, "#9FB0CC", lineHeight=1.4),
    # Miejsce na zdjęcie: bez pliku rysuje się jako lekko przyciemnione pole, „Zamień…” wstawia zdjęcie
    dict(type="image", src="", x=175, y=205, w=470, h=470, mask="ellipse"),
    T("KONTAKT", 120, 820, 600, 52, "Geist", 700, "#FFFFFF", align="left", spacing=0.2),
    T("600 100 200\nanna.nowak@poczta.pl\nKraków", 120, 910, 620, 50, "Geist", 400, "#D7DEEA", align="left", lineHeight=1.6),
    T("UMIEJĘTNOŚCI", 120, 1240, 600, 52, "Geist", 700, "#FFFFFF", align="left", spacing=0.2),
    T("Obsługa klienta\nArkusze kalkulacyjne\nPrawo jazdy kat. B\nAngielski (B2)", 120, 1330, 620, 50, "Geist", 400, "#D7DEEA", align="left", lineHeight=1.6),
    T("ZAINTERESOWANIA", 120, 1760, 640, 44, "Geist", 700, "#FFFFFF", align="left", spacing=0.2),
    T("Rower, fotografia, gotowanie", 120, 1850, 620, 50, "Geist", 400, "#D7DEEA", align="left", lineHeight=1.5),
    T("Anna Nowak", 980, 230, 1380, 180, "Inter Display", 800, side, align="left"),
    T("SPECJALISTKA DS. OBSŁUGI KLIENTA", 985, 440, 1380, 56, "Geist", 600, "#5B7CFA", align="left", spacing=0.12),
    LINE(985, 600, 1380, "#E1E6EF", 4),
    T("Doświadczenie", 985, 690, 1380, 80, "Inter Display", 700, side, align="left"),
    T("2021 – obecnie · Biuro Podróży Słońce", 985, 820, 1380, 52, "Geist", 700, "#2B2D42", align="left"),
    T("Doradzam klientom przy wyborze wyjazdów, prowadzę rezerwacje i dbam o stałych klientów.", 985, 900, 1380, 48, "Geist", 400, "#5B6270", align="left", lineHeight=1.45),
    T("2018 – 2021 · Sklep Domowy, Kraków", 985, 1130, 1380, 52, "Geist", 700, "#2B2D42", align="left"),
    T("Sprzedaż, obsługa kasy i zamówień, przygotowanie ekspozycji.", 985, 1210, 1380, 48, "Geist", 400, "#5B6270", align="left", lineHeight=1.45),
    T("Wykształcenie", 985, 1450, 1380, 80, "Inter Display", 700, side, align="left"),
    T("2015 – 2018 · Technikum Ekonomiczne w Krakowie", 985, 1580, 1380, 52, "Geist", 700, "#2B2D42", align="left"),
    T("Technik ekonomista", 985, 1660, 1380, 48, "Geist", 400, "#5B6270", align="left"),
    T("Wyrażam zgodę na przetwarzanie moich danych osobowych dla potrzeb niezbędnych do realizacji procesu rekrutacji.", 985, 3260, 1380, 34, "Geist", 400, "#9AA2B2", align="left", lineHeight=1.4),
], (210, 297))

# ——— YouTube (1280×720) ———
save("11-yt-poradnik.json", "Poradnik", "YouTube", 1280, 720, radial("#3A3F58", "#0B0C12"), [
    R(-40, 470, 1360, 290, "#FFE600", rotation=-4),
    T("JAK TO", 60, 90, 760, 170, "Inter Display", 900, "#FFFFFF", align="left", outline=0.05, outlineColor="#000000"),
    T("ZROBIĆ?", 60, 250, 860, 190, "Inter Display", 900, "#FFE600", align="left", outline=0.05, outlineColor="#000000"),
    T("w 5 minut", 80, 545, 700, 110, "Inter Display", 900, "#111111", align="left", rotation=-4),
    S("arrow", 820, 300, 340, 90, "", stroke="#FF3D3D", strokeWidth=26, rotation=28),
    S("ellipse", 980, 80, 220, 220, "#FF3D3D"),
    T("NOWE", 980, 155, 220, 54, "Inter Display", 900, "#FFFFFF"),
])
save("12-yt-vlog.json", "Vlog z podróży", "YouTube", 1280, 720, grad("#43E97B", "#2563EB", 120), [
    S("triangle", 700, 260, 640, 520, "#14532D", opacity=0.55),
    S("triangle", 900, 160, 520, 620, "#0B3B22", opacity=0.7),
    S("ellipse", 1080, 60, 120, 120, "#FFF4C2"),
    T("TYDZIEŃ", 70, 150, 760, 150, "Inter Display", 900, "#FFFFFF", align="left", shadow=True),
    T("w górach", 70, 300, 760, 170, "Z003", 400, "#FFFFFF", align="left", shadow=True),
    R(76, 520, 360, 76, "#111111", 38),
    T("VLOG #12", 76, 535, 360, 44, "Geist", 800, "#FFFFFF", spacing=0.1),
])

# ——— Slajdy (1920×1080) ———
save("13-slajd-tytul.json", "Slajd tytułowy", "Slajd", 1920, 1080, solid("#FFFFFF"), [
    R(0, 0, 760, 1080, "#5B7CFA", fill2="#7F5AF0", gradientAngle=160),
    S("ellipse", 460, 640, 600, 600, "#FFFFFF", opacity=0.12),
    T("Q3 2026", 120, 140, 560, 54, "Geist", 700, "#FFFFFF", align="left", spacing=0.15),
    T("Plan działań na nowy sezon", 900, 330, 900, 120, "Inter Display", 800, "#16181D", align="left", lineHeight=1.05),
    LINE(905, 640, 160, "#5B7CFA", 10),
    T("Zespół sprzedaży · spotkanie 15 września", 905, 700, 900, 44, "Geist", 400, "#5B6270", align="left"),
])
save("14-slajd-punkty.json", "Slajd z punktami", "Slajd", 1920, 1080, solid("#F7F8FB"), [
    T("Trzy rzeczy na ten kwartał", 140, 120, 1640, 90, "Inter Display", 800, "#16181D", align="left"),
    R(140, 340, 500, 560, "#FFFFFF", 36, stroke="#E1E6EF", strokeWidth=3),
    R(710, 340, 500, 560, "#FFFFFF", 36, stroke="#E1E6EF", strokeWidth=3),
    R(1280, 340, 500, 560, "#FFFFFF", 36, stroke="#E1E6EF", strokeWidth=3),
    S("ellipse", 200, 400, 110, 110, "#5B7CFA"),
    S("ellipse", 770, 400, 110, 110, "#22B07D"),
    S("ellipse", 1340, 400, 110, 110, "#FF7043"),
    T("1", 200, 420, 110, 64, "Inter Display", 800, "#FFFFFF"),
    T("2", 770, 420, 110, 64, "Inter Display", 800, "#FFFFFF"),
    T("3", 1340, 420, 110, 64, "Inter Display", 800, "#FFFFFF"),
    T("Nowi klienci", 200, 570, 400, 46, "Geist", 700, "#16181D", align="left"),
    T("Szybka obsługa", 770, 570, 400, 46, "Geist", 700, "#16181D", align="left"),
    T("Mniej kosztów", 1340, 570, 400, 46, "Geist", 700, "#16181D", align="left"),
    T("Kampania w lokalnych mediach i polecenia od stałych klientów.", 200, 660, 390, 36, "Geist", 400, "#5B6270", align="left", lineHeight=1.4),
    T("Odpowiedź na każde zapytanie w ciągu jednego dnia.", 770, 660, 390, 36, "Geist", 400, "#5B6270", align="left", lineHeight=1.4),
    T("Wspólne zamówienia materiałów i mniej papieru w biurze.", 1340, 660, 390, 36, "Geist", 400, "#5B6270", align="left", lineHeight=1.4),
])

# ——— Inne ———
save("15-okladka-kawiarnia.json", "Okładka kawiarni", "Facebook", 1640, 624, solid("#2B1D16"), [
    S("ellipse", 1180, -200, 700, 700, "#C8865A", opacity=0.35),
    S("ellipse", 1320, 300, 500, 500, "#E8B48A", opacity=0.25),
    T("Kawiarnia", 120, 120, 1000, 90, "Geist", 300, "#E8B48A", align="left", spacing=0.3, caps=True),
    T("Pod Lipami", 110, 210, 1300, 170, "Noto Serif", 700, "#FFF4E0", align="left", italic=True),
    T("codziennie 8:00–20:00 · ciasta z własnej piekarni", 120, 470, 1100, 42, "Geist", 400, "#E8D2BF", align="left"),
])
save("16-dyplom.json", "Dyplom", "Dyplom", 3508, 2480, radial("#FFFFFF", "#F1EBDD"), [
    R(120, 120, 3268, 2240, "", 0, stroke="#B8934A", strokeWidth=24),
    R(200, 200, 3108, 2080, "", 0, stroke="#B8934A", strokeWidth=6),
    S("star", 1604, 330, 300, 300, "#E0B44C"),
    T("DYPLOM", 300, 700, 2908, 300, "C059", 700, "#3B3226", spacing=0.2),
    T("dla", 300, 1040, 2908, 110, "Noto Serif", 400, "#7A6A55", italic=True),
    T("Zosi Kowalskiej", 300, 1180, 2908, 300, "Z003", 400, "#8A5A12"),
    T("za zajęcie pierwszego miejsca w konkursie recytatorskim", 500, 1560, 2508, 110, "Noto Serif", 400, "#3B3226", lineHeight=1.35),
    LINE(500, 2050, 800, "#7A6A55", 5),
    LINE(2208, 2050, 800, "#7A6A55", 5),
    T("data", 500, 2090, 800, 64, "Noto Serif", 400, "#7A6A55", italic=True),
    T("podpis", 2208, 2090, 800, 64, "Noto Serif", 400, "#7A6A55", italic=True),
], (297, 210))


# ════════ Druga seria: czcionki z Google Fonts (wbudowane w program), miejsca na zdjęcia, cienie, wiele stron ════════

# ——— Instagram ———
save("17-promocja-zdjecie.json", "Nowa kolekcja", "Instagram", 1080, 1350, solid("#FFF6EC"), [
    P(70, 70, 940, 780, radius=40),
    T("NOWA KOLEKCJA", 60, 890, 960, 150, "Bebas Neue", 400, "#1E1B18", spacing=0.02),
    T("−30% na wszystko do niedzieli", 120, 1060, 840, 46, "Poppins", 600, "#FFFFFF", bg="#FF5A36", bgPadding=0.4, bgRadius=0.5),
    T("sklep.pl · darmowa dostawa od 150 zł", 120, 1200, 840, 32, "Poppins", 400, "#6B625A"),
])
save("18-porady-karuzela.json", "Porady — karuzela", "Instagram", 1080, 1350, solid("#1F3A5F"), [
    S("ellipse", 640, -220, 700, 700, "#FFD166", opacity=0.18),
    S("ellipse", -260, 980, 620, 620, "#FFFFFF", opacity=0.06),
    T("5 sposobów na", 90, 420, 900, 76, "Poppins", 600, "#FFFFFF", align="left"),
    T("lepszy sen", 80, 510, 920, 170, "Playfair Display", 700, "#FFD166", align="left", italic=True, lineHeight=1.0),
    T("Zapisz, żeby nie zgubić — i podeślij komuś, kto ciągle ziewa.", 90, 760, 780, 38, "Poppins", 400, "#C9D6E8", align="left", lineHeight=1.4),
    T("przesuń  →", 690, 1200, 300, 36, "Poppins", 600, "#FFD166", align="right"),
], pages=[
    (solid("#F4F1EA"), [
        T("01", 90, 120, 400, 240, "Abril Fatface", 400, "#1F3A5F", align="left", lineHeight=1.0),
        T("Stała pora", 90, 420, 900, 90, "Poppins", 800, "#1F3A5F", align="left"),
        T("Kładź się i wstawaj o tej samej godzinie — także w weekend. Organizm szybko się przyzwyczai.", 90, 560, 880, 46, "Lora", 400, "#3E4652", align="left", lineHeight=1.45),
        R(90, 1180, 120, 12, "#FFD166", 6),
        T("2 / 5", 690, 1160, 300, 32, "Poppins", 600, "#8A93A3", align="right"),
    ]),
    (solid("#F4F1EA"), [
        T("02", 90, 120, 400, 240, "Abril Fatface", 400, "#1F3A5F", align="left", lineHeight=1.0),
        T("Bez ekranu przed snem", 90, 420, 900, 90, "Poppins", 800, "#1F3A5F", align="left"),
        T("Godzinę przed snem odłóż telefon. Zamiast tego książka, ciepła herbata albo krótki spacer.", 90, 660, 880, 46, "Lora", 400, "#3E4652", align="left", lineHeight=1.45),
        R(90, 1180, 120, 12, "#FFD166", 6),
        T("3 / 5", 690, 1160, 300, 32, "Poppins", 600, "#8A93A3", align="right"),
    ]),
])
save("19-opinia-klienta.json", "Opinia klienta", "Instagram", 1080, 1080, solid("#EEF3FF"), [
    R(80, 120, 920, 840, "#FFFFFF", 40, **shadow(50, 18, 180, 0.16)),
    *[S("star", 330 + i * 86, 200, 70, 70, "#FFB400") for i in range(5)],
    T("„Najlepsza obsługa w mieście! Wszystko na czas, z uśmiechem i bez nerwów. Polecam każdemu.”", 150, 330, 780, 50, "Lora", 400, "#1F2633", italic=True, lineHeight=1.4),
    P(470, 690, 140, 140, mask="ellipse"),
    T("Anna, stała klientka", 200, 860, 680, 34, "Poppins", 600, "#1F2633"),
])
save("20-komunikat.json", "Ważny komunikat", "Instagram", 1080, 1080, solid("#FFE14D"), [
    T("WAŻNE!", 60, 140, 960, 230, "Anton", 400, "#16181D", lineHeight=1.0),
    R(90, 440, 900, 130, "#16181D", 20),
    T("Zmiana godzin otwarcia", 90, 470, 900, 58, "Poppins", 800, "#FFE14D"),
    T("Od 1 grudnia zapraszamy\npon.–pt. 9:00–17:00\nsob. 9:00–13:00", 120, 640, 840, 54, "Poppins", 600, "#16181D", lineHeight=1.4),
    T("Dziękujemy za wyrozumiałość!", 120, 930, 840, 34, "Poppins", 400, "#4A4426"),
])
save("21-wydarzenie.json", "Wydarzenie", "Instagram", 1080, 1350, grad("#2A1B5C", "#7B2FF7", 160), [
    R(90, 110, 260, 300, "#FFFFFF", 30, **shadow(40, 14, 180, 0.3)),
    T("14", 90, 140, 260, 170, "Abril Fatface", 400, "#2A1B5C", lineHeight=1.0),
    T("LISTOPADA", 90, 330, 260, 34, "Poppins", 800, "#7B2FF7", spacing=0.08),
    T("Wieczór planszówek", 80, 520, 920, 120, "Montserrat", 800, "#FFFFFF", align="left", lineHeight=1.05),
    T("Gry dla każdego, herbata i ciasto. Wstęp wolny — przyjdź z przyjaciółmi!", 90, 820, 860, 42, "Poppins", 400, "#E3D9FF", align="left", lineHeight=1.4),
    T("godz. 18:00 · Biblioteka Miejska", 90, 1150, 900, 40, "Poppins", 600, "#FFFFFF", align="left", bg="#33FFFFFF", bgPadding=0.5),
])
save("22-przed-i-po.json", "Przed i po", "Instagram", 1080, 1080, solid("#FFFFFF"), [
    P(0, 0, 536, 1080),
    P(544, 0, 536, 1080),
    T("PRZED", 40, 960, 456, 44, "Poppins", 800, "#FFFFFF", bg="#16181D", bgPadding=0.4, bgRadius=0.3, spacing=0.06),
    T("PO", 584, 960, 456, 44, "Poppins", 800, "#16181D", bg="#FFE14D", bgPadding=0.4, bgRadius=0.3, spacing=0.06),
])

# ——— Relacje ———
save("23-story-odliczanie.json", "Odliczanie", "Relacja", 1080, 1920, radial("#FF7EB3", "#5B2C83"), [
    T("Jeszcze", 90, 420, 900, 80, "Poppins", 600, "#FFFFFF"),
    T("3", 90, 520, 900, 620, "Abril Fatface", 400, "#FFFFFF", lineHeight=1.0, **shadow(60, 0, 0, 0.8, "#FF2D95")),
    T("dni", 90, 1150, 900, 130, "Poppins", 800, "#FFFFFF"),
    T("do premiery!", 90, 1330, 900, 110, "Pacifico", 400, "#FFE14D"),
])
save("24-story-nowy-produkt.json", "Nowy produkt", "Relacja", 1080, 1920, solid("#F2E8DF"), [
    P(140, 220, 800, 1000, mask="arch"),
    T("NOWOŚĆ", 90, 1270, 900, 190, "Bebas Neue", 400, "#3B2A20", spacing=0.04),
    T("Ręcznie robiona świeca sojowa o zapachu wanilii i drzewa sandałowego", 140, 1480, 800, 44, "Lora", 400, "#5E4A3D", italic=True, lineHeight=1.4),
    R(290, 1680, 500, 110, "#3B2A20", 55),
    T("Sprawdź w sklepie", 290, 1712, 500, 42, "Poppins", 600, "#F2E8DF"),
])
save("25-story-polecamy.json", "Polaroidy", "Relacja", 1080, 1920, solid("#E9F1EC"), [
    T("Weekendowe inspiracje", 60, 150, 960, 120, "Caveat", 700, "#24443A"),
    R(150, 360, 560, 640, "#FFFFFF", 6, rotation=-6, **shadow(40, 16, 170, 0.25)),
    P(185, 395, 490, 500, rotation=-6),
    R(380, 1000, 560, 640, "#FFFFFF", 6, rotation=5, **shadow(40, 16, 170, 0.25)),
    P(415, 1035, 490, 500, rotation=5),
    T("las · kawa · dobra książka", 60, 1730, 960, 70, "Caveat", 400, "#24443A"),
])

# ——— Plakaty i ulotki (A4, A3, A5) ———
strips = []
for i in range(8):
    cx = 155 + i * 310
    # Pionowe przerywane linie między karteczkami i numer telefonu w poprzek każdej
    strips.append(LINE(cx - 155 - 250, 3184, 500, "#9AA0A8", 4, rotation=90, dash=True) if i else None)
    strips.append(T("Tel. 600 000 000", cx - 250, 3184 - 23, 500, 40, "Poppins", 600, "#16181D", rotation=-90))
strips = [e for e in strips if e]
save("26-ogloszenie-sprzedam.json", "Sprzedam — z karteczkami", "Plakat", 2480, 3508, solid("#FFFFFF"), [
    T("SPRZEDAM", 120, 150, 2240, 420, "Anton", 400, "#16181D", lineHeight=1.0),
    P(240, 680, 2000, 1300, radius=30),
    T("Rower miejski, 3 biegi, koszyk i błotniki. Mało używany, stan bardzo dobry.", 240, 2080, 2000, 90, "Poppins", 400, "#2A2E36", lineHeight=1.35),
    T("450 zł", 240, 2420, 2000, 220, "Poppins", 800, "#E53935"),
    LINE(0, 2860, 2480, "#9AA0A8", 4, dash=True),
] + strips, (210, 297))
save("27-zaginal-pies.json", "Zaginął pies", "Plakat", 2480, 3508, solid("#FFFFFF"), [
    R(0, 0, 2480, 560, "#E53935"),
    T("ZAGINĄŁ PIES", 80, 110, 2320, 340, "Anton", 400, "#FFFFFF", lineHeight=1.0),
    P(240, 700, 2000, 1500, radius=40),
    T("Reksio", 240, 2290, 2000, 200, "Montserrat", 800, "#16181D"),
    T("Mały, rudy, z białą łatką na piersi. Ostatnio widziany przy parku na ul. Lipowej. Jest przyjazny, ale płochliwy.", 300, 2560, 1880, 80, "Poppins", 400, "#2A2E36", lineHeight=1.4),
    R(0, 3060, 2480, 448, "#16181D"),
    T("Pomóż! Tel. 600 000 000", 80, 3190, 2320, 150, "Poppins", 800, "#FFE14D"),
], (210, 297))
confetti = []
cols = ["#FF5A5F", "#FFB400", "#00A699", "#7B61FF", "#FF7AB6"]
import random
rnd = random.Random(7)
for i in range(26):
    x, y = rnd.randint(80, 3400), rnd.randint(1500, 4800)
    if 600 < x < 2900 and 1700 < y < 4200:
        continue
    confetti.append(S(rnd.choice(["ellipse", "star", "rect"]), x, y, rnd.randint(50, 120), rnd.randint(50, 120), rnd.choice(cols), rotation=rnd.randint(0, 90)))
save("28-festyn.json", "Festyn rodzinny", "Plakat", 3508, 4961, grad("#7FD3FF", "#FFF5D6", 180), [
    S("ellipse", 2500, 220, 760, 760, "#FFD23F", **shadow(160, 0, 0, 0.6, "#FFB400")),
    *confetti,
    T("FESTYN", 200, 900, 3108, 900, "Bebas Neue", 400, "#E53935", curve=0.3, **shadow(30, 18, 180, 0.25)),
    T("RODZINNY", 200, 1950, 3108, 500, "Bebas Neue", 400, "#1F3A5F", spacing=0.06),
    R(700, 2620, 2108, 700, "#FFFFFF", 80, opacity=0.92, **shadow(60, 20, 180, 0.15)),
    T("niedziela 8 czerwca\ngodz. 12:00–20:00", 700, 2700, 2108, 190, "Poppins", 800, "#1F3A5F", lineHeight=1.25),
    T("dmuchańce · loteria · grill · koncert na koniec", 400, 3520, 2708, 120, "Poppins", 600, "#1F3A5F"),
    T("Boisko przy Szkole Podstawowej nr 3 · wstęp wolny", 400, 3760, 2708, 100, "Poppins", 400, "#3E5A78"),
], (297, 420))
def menu_section(title, y, items):
    out = [T(title, 200, y, 2080, 130, "Playfair Display", 700, "#2B2118", align="left", italic=True),
           LINE(200, y + 190, 2080, "#C8B49A", 4)]
    yy = y + 250
    for name, desc, price in items:
        out += [T(name, 200, yy, 1700, 66, "Poppins", 600, "#2B2118", align="left"),
                T(price, 1880, yy, 400, 66, "Poppins", 600, "#9C6B30", align="right"),
                T(desc, 200, yy + 86, 1700, 46, "Lora", 400, "#6B5D4D", align="left", italic=True)]
        yy += 220
    return out
save("29-menu.json", "Menu restauracji", "Menu", 2480, 3508, solid("#FAF6EF"), [
    T("Menu", 200, 150, 2080, 420, "Great Vibes", 400, "#2B2118", lineHeight=1.0),
    T("BISTRO POD KASZTANAMI", 200, 600, 2080, 60, "Poppins", 600, "#9C6B30", spacing=0.3),
    *menu_section("Zupy", 860, [("Żurek na zakwasie", "z jajkiem i białą kiełbasą", "18 zł"), ("Krem z dyni", "z prażonymi pestkami", "16 zł")]),
    *menu_section("Dania główne", 1600, [("Pierogi ruskie", "okraszone cebulką, 8 sztuk", "26 zł"), ("Schabowy z ziemniakami", "z kapustą zasmażaną", "34 zł"), ("Placki po węgiersku", "z gulaszem wołowym", "36 zł")]),
    *menu_section("Desery", 2560, [("Szarlotka na ciepło", "z gałką lodów waniliowych", "16 zł"), ("Sernik", "według przepisu babci", "15 zł")]),
], (210, 297))
save("30-ulotka-korepetycje.json", "Korepetycje — ulotka", "Ulotka", 1748, 2480, solid("#0E4D64"), [
    S("ellipse", 1100, -300, 1000, 1000, "#13A89E", opacity=0.35),
    T("Korepetycje\nz matematyki", 140, 260, 1468, 190, "Montserrat", 800, "#FFFFFF", align="left", lineHeight=1.05),
    T("Szkoła podstawowa · liceum · matura", 140, 760, 1468, 60, "Poppins", 400, "#BFE7EA", align="left"),
    *[S("ellipse", 150, 1000 + i * 160, 44, 44, "#FFD166") for i in range(3)],
    *[T(t, 240, 990 + i * 160, 1350, 56, "Poppins", 600, "#FFFFFF", align="left") for i, t in enumerate(["Cierpliwie i od podstaw", "Zajęcia u ucznia albo online", "Pierwsza lekcja za pół ceny"])],
    R(140, 1620, 700, 150, "#FFD166", 75),
    T("60 zł / godz.", 140, 1660, 700, 62, "Poppins", 800, "#0E4D64"),
    T("Tel. 600 000 000", 140, 2050, 1468, 120, "Montserrat", 800, "#FFFFFF", align="left"),
    T("mgr Jan Kowalski", 140, 2220, 1468, 56, "Poppins", 400, "#BFE7EA", align="left"),
], (148, 210))

# ——— Zaproszenia i kartki ———
save("31-zaproszenie-komunia.json", "Pierwsza Komunia", "Zaproszenie", 1748, 2480, solid("#FFFFFF"), [
    R(80, 80, 1588, 2320, "", 20, stroke="#C9A55C", strokeWidth=6),
    S("star", 824, 220, 100, 100, "#C9A55C"),
    T("Zaproszenie", 100, 400, 1548, 260, "Great Vibes", 400, "#8A6A2F"),
    T("na uroczystość Pierwszej Komunii Świętej", 200, 760, 1348, 70, "Lora", 400, "#3E3524", italic=True, lineHeight=1.35),
    T("Zosi", 100, 1000, 1548, 220, "Playfair Display", 700, "#3E3524"),
    LINE(624, 1330, 500, "#C9A55C", 4),
    T("niedziela, 18 maja, godz. 11:00\nkościół pw. św. Józefa", 160, 1420, 1428, 66, "Lora", 400, "#3E3524", lineHeight=1.5),
    T("Po uroczystości zapraszamy na obiad do restauracji „Pod Lipą”.", 220, 1800, 1308, 54, "Lora", 400, "#6B5D4D", italic=True, lineHeight=1.45),
], (148, 210))
save("32-zaproszenie-18.json", "Osiemnastka", "Zaproszenie", 1748, 2480, solid("#0B0B1A"), [
    T("18", 100, 300, 1548, 900, "Abril Fatface", 400, "#FFFFFF", lineHeight=1.0, **shadow(90, 0, 0, 0.95, "#FF2D95")),
    T("urodziny", 100, 1240, 1548, 260, "Pacifico", 400, "#3DF5FF", **shadow(50, 0, 0, 0.8, "#00B3FF")),
    T("Kasi", 100, 1560, 1548, 150, "Poppins", 800, "#FFFFFF"),
    T("sobota, 22 marca · od 20:00\nKlub „Neon”, ul. Długa 5", 160, 1850, 1428, 66, "Poppins", 400, "#C8C8E8", lineHeight=1.5),
], (148, 210))
snow = [S("ellipse", rnd.randint(0, 1700), rnd.randint(0, 1200), s, s, "#FFFFFF", opacity=0.5) for s in [rnd.randint(10, 26) for _ in range(40)]]
save("33-kartka-swiateczna.json", "Kartka świąteczna", "Kartka", 1748, 1240, solid("#0F3D2E"), snow + [
    S("star", 824, 120, 100, 100, "#F2C14E", **shadow(40, 0, 0, 0.8, "#F2C14E")),
    T("Wesołych Świąt", 60, 330, 1628, 230, "Great Vibes", 400, "#F5E6C8"),
    T("i szczęśliwego Nowego Roku", 80, 690, 1588, 80, "Lora", 400, "#E8D9B5", italic=True),
    T("życzy rodzina Nowaków", 80, 950, 1588, 50, "Poppins", 400, "#A9C4B8"),
], (148, 105))
balloons = []
for i, (x, c) in enumerate([(160, "#FF5A5F"), (330, "#FFB400"), (1290, "#7B61FF"), (1460, "#00A699")]):
    y = 140 + (i % 2) * 120
    balloons += [LINE(x + 60, y + 330, 260, "#B7A8B0", 3, rotation=90), S("ellipse", x, y, 130, 170, c, **shadow(20, 8, 160, 0.2))]
save("34-kartka-urodzinowa.json", "Kartka urodzinowa", "Kartka", 1748, 1240, solid("#FFF0F5"), balloons + [
    T("Sto lat!", 300, 330, 1148, 300, "Pacifico", 400, "#E0336E"),
    T("Wszystkiego najlepszego,\nzdrowia i samych słonecznych dni", 300, 760, 1148, 60, "Poppins", 600, "#5B3448", lineHeight=1.4),
], (148, 105))

# ——— Wizytówka (90 × 50 mm, dwie strony) ———
save("35-wizytowka.json", "Wizytówka", "Wizytówka", 1063, 591, solid("#16181D"), [
    R(70, 250, 80, 8, "#FFB400", 4),
    T("Anna Nowak", 70, 140, 900, 80, "Montserrat", 800, "#FFFFFF", align="left"),
    T("PROJEKTANTKA WNĘTRZ", 70, 290, 900, 30, "Poppins", 600, "#FFB400", align="left", spacing=0.15),
], (90, 50), pages=[
    (solid("#FFFFFF"), [
        T("tel. 600 000 000\nanna@pracownia.pl\nul. Długa 5, Kraków", 70, 150, 900, 40, "Poppins", 400, "#16181D", align="left", lineHeight=1.6),
        T("pracownia.pl", 70, 450, 900, 34, "Poppins", 800, "#E0A100", align="left"),
    ]),
])

# ——— Prezentacja (4 slajdy) ———
save("36-prezentacja.json", "Prezentacja — 4 slajdy", "Slajd", 1920, 1080, grad("#141E30", "#243B55", 135), [
    T("Plan na nowy rok", 160, 360, 1600, 150, "Montserrat", 800, "#FFFFFF", align="left"),
    T("Spotkanie zespołu · styczeń", 160, 560, 1600, 56, "Poppins", 400, "#AFC3DD", align="left"),
    R(160, 700, 160, 10, "#FFB400", 5),
], pages=[
    (solid("#F7F8FB"), [
        T("O czym porozmawiamy", 160, 140, 1600, 90, "Montserrat", 800, "#141E30", align="left"),
        *[S("ellipse", 170, 350 + i * 150, 40, 40, "#FFB400") for i in range(4)],
        *[T(t, 250, 340 + i * 150, 1400, 56, "Poppins", 400, "#2A3446", align="left") for i, t in enumerate(["Co się udało w zeszłym roku", "Nasze cele", "Kto czym się zajmuje", "Pytania"])],
    ]),
    (solid("#FFFFFF"), [
        P(1000, 0, 920, 1080),
        T("Nasze cele", 160, 200, 760, 90, "Montserrat", 800, "#141E30", align="left"),
        T("Więcej klientów z polecenia, szybsza obsługa i nowy sklep internetowy do wiosny.", 160, 360, 760, 50, "Poppins", 400, "#2A3446", align="left", lineHeight=1.5),
    ]),
    (grad("#141E30", "#243B55", 135), [
        T("Dziękuję!", 160, 380, 1600, 200, "Playfair Display", 700, "#FFFFFF", italic=True),
        T("Pytania?", 160, 640, 1600, 70, "Poppins", 400, "#AFC3DD"),
    ]),
])

# ——— YouTube i Facebook ———
save("37-yt-reakcja.json", "Miniaturka — reakcja", "YouTube", 1280, 720, solid("#FFD400"), [
    P(700, 0, 580, 720, mask="blob"),
    T("NIE\nWIERZYŁEM!", 50, 150, 720, 150, "Anton", 400, "#FFFFFF", align="left", lineHeight=1.0, rotation=-4, outline=0.08, outlineColor="#16181D"),
    S("arrow", 560, 520, 260, 60, "", stroke="#E53935", strokeWidth=26, rotation=-20),
])
save("38-okladka-firma.json", "Okładka — pracownia", "Facebook", 1640, 624, grad("#FDF3E7", "#F3D9C1", 90), [
    T("Pracownia Ceramiki", 100, 170, 900, 120, "Playfair Display", 700, "#5A3E2B", align="left", lineHeight=1.05),
    T("warsztaty dla dorosłych i dzieci · Gdańsk", 100, 440, 900, 40, "Poppins", 400, "#8A6A52", align="left"),
    P(1060, 60, 230, 504, radius=115),
    P(1320, 60, 230, 504, radius=115),
])

# ——— Podziękowanie, plan tygodnia ———
save("39-podziekowanie.json", "Podziękowanie", "Dyplom", 3508, 2480, solid("#FBF7EF"), [
    R(140, 140, 3228, 2200, "", 40, stroke="#2F5D50", strokeWidth=14),
    T("Podziękowanie", 300, 380, 2908, 460, "Great Vibes", 400, "#2F5D50"),
    T("dla Pani Marii Kowalskiej", 300, 1020, 2908, 150, "Playfair Display", 700, "#2B2B2B"),
    T("za serce i czas poświęcony naszej świetlicy przez cały rok szkolny", 500, 1300, 2508, 100, "Lora", 400, "#4A4A4A", italic=True, lineHeight=1.4),
    LINE(1354, 1950, 800, "#2F5D50", 5),
    T("Dyrekcja i dzieci", 1154, 1990, 1200, 70, "Lora", 400, "#4A4A4A", italic=True),
], (297, 210))
days = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek", "Sobota", "Niedziela"]
save("40-plan-tygodnia.json", "Plan tygodnia", "Plan", 2480, 3508, solid("#F7F8FB"), [
    T("Plan tygodnia", 160, 150, 2160, 200, "Poppins", 800, "#1F2633", align="left"),
    T("Notuj, odhaczaj, odpoczywaj.", 160, 380, 2160, 110, "Caveat", 400, "#7B61FF", align="left"),
    *[e for i, d in enumerate(days) for e in (
        R(160, 600 + i * 390, 2160, 350, "#FFFFFF", 30, **shadow(30, 8, 180, 0.08)),
        T(d, 220, 640 + i * 390, 900, 80, "Poppins", 800, "#7B61FF" if i < 5 else "#FF5A5F", align="left"),
    )],
], (210, 297))

print("templates:", len([f for f in os.listdir(OUT) if f.endswith('.json')]))

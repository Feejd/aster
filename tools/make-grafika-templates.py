#!/usr/bin/env python3
# Generuje szablony Grafiki — zwykłe pliki projektu bez zdjęć: python3 tools/make-grafika-templates.py apps/grafika/templates
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

def save(fname, name, category, w, h, bg, elements, print_=None):
    doc = {"format": "aster-grafika", "version": 1, "name": name, "category": category, "width": w, "height": h,
           "background": bg, "elements": []}
    if print_:
        doc["print"] = {"width": print_[0], "height": print_[1]}
    for i, e in enumerate(elements, 1):
        e = dict(e)
        e["id"] = "e%d" % i
        doc["elements"].append(e)
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
    T("zespoły z okolicy · strefa dla dzieci · food trucki", 300, 4400, 2908, 88, "Geist", 500, "#FFB300", caps=True, spacing=0.06),
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

print("templates:", len([f for f in os.listdir(OUT) if f.endswith('.json')]))

#!/usr/bin/env python3
"""Kursor Aster: grafitowe kształty z białą obwódką i miękkim cieniem, akcent Aster (#7C8CFF) w kółku ładowania.

Rysuje każdy kursor jako SVG (płótno 32×32, rozmiar nominalny 24) i buduje z nich motyw:
  cursors_scalable/  SVG z metadata.json — ostre w każdej skali (KWin 6)
  cursors/           Xcursor w rozmiarach 24–96 (programy X11, GTK, starsze biblioteki)
plus dowiązania dla wszystkich nazw, pod którymi programy proszą o kursory (CSS, X11, skróty Qt).

Wymaga rsvg-convert (librsvg2-tools) i xcursorgen. Uruchamiane w kontenerze budującym:
  python3 tools/make-cursors.py data/cursors/Aster [podglad.png]
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

CANVAS = 32          # jednostki SVG
NOMINAL = 24         # rozmiar nominalny (jak w Breeze): kursor 24 = obraz 32 px
SIZES = [24, 32, 36, 48, 64, 72, 96]

INK_TOP, INK_BOTTOM = "#2B2E39", "#101117"   # grafit z delikatnym przejściem
RIM = "#FFFFFF"
OUTLINE = 1.25                              # szerokość białej obwódki (po każdej stronie)
ACCENT = "#7C8CFF"                          # akcent Aster (jak w os-release)
GREEN, RED, BLUE = "#22C55E", "#E5484D", "#3B82F6"


# ——— Geometria ———
# Kształt to lista elementów: ("fill", d) — wypełniony kontur, ("line", d, szerokość) — kreska,
# ("detail", d) — cienka jaśniejsza linia na wnętrzu (bez obwódki).
# Rysujemy trzy warstwy: cień, biała obwódka (powiększony kształt), grafitowe wnętrze.

def rect(x, y, w, h, r=0):
    r = min(r, w / 2, h / 2)
    if r <= 0:
        return f"M{x} {y}h{w}v{h}h{-w}z"
    return (f"M{x + r} {y}h{w - 2 * r}a{r} {r} 0 0 1 {r} {r}v{h - 2 * r}a{r} {r} 0 0 1 {-r} {r}"
            f"h{-(w - 2 * r)}a{r} {r} 0 0 1 {-r} {-r}v{-(h - 2 * r)}a{r} {r} 0 0 1 {r} {-r}z")


def circle(cx, cy, r):
    return f"M{cx - r} {cy}a{r} {r} 0 1 0 {2 * r} 0a{r} {r} 0 1 0 {-2 * r} 0z"


def poly(points):
    return "M" + "L".join(f"{x:.3f} {y:.3f}" for x, y in points) + "Z"


def transform_points(points, angle=0, cx=16, cy=16, scale=1.0):
    a = math.radians(angle)
    out = []
    for x, y in points:
        x, y = (x - cx) * scale, (y - cy) * scale
        out.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
    return out


def double_arrow(angle=0, length=21.0, head=5.2, half_w=4.6, shaft=1.35):
    """Strzałka w obie strony (zmiana rozmiaru) wokół środka płótna."""
    l = length / 2
    pts = [(16 - l, 16), (16 - l + head, 16 - half_w), (16 - l + head, 16 - shaft), (16 + l - head, 16 - shaft),
           (16 + l - head, 16 - half_w), (16 + l, 16), (16 + l - head, 16 + half_w), (16 + l - head, 16 + shaft),
           (16 - l + head, 16 + shaft), (16 - l + head, 16 + half_w)]
    return ("fill", poly(transform_points(pts, angle)))


ARROW = [(8, 5), (8, 21.8), (11.9, 18.2), (14.6, 24.4), (17.4, 23.2), (14.8, 17.1), (20.2, 17.1)]
ARROW_HOT = (8, 5)


def arrow(mirror=False):
    pts = [(32 - x, y) for x, y in ARROW] if mirror else ARROW
    return [("fill", poly(pts))]


def hand_pointer():
    return [
        ("fill", rect(11.6, 4.0, 4.0, 14.0, 2.0)),            # palec wskazujący
        ("fill", rect(15.0, 11.2, 3.5, 7.5, 1.75)),           # zgięte palce
        ("fill", rect(18.0, 12.0, 3.4, 7.0, 1.7)),
        ("fill", rect(20.8, 13.2, 3.2, 6.5, 1.6)),
        ("fill", "M7.2 17.0c1.1-1.1 2.8-1.0 3.8 0.2l1.6 2.0V15h11.4v6.6c0 3.6-2.6 6.4-6.2 6.4h-3.0c-2.2 0-3.7-0.9-5.0-2.6"
                 "l-3.0-4.2c-0.7-1.0-0.6-2.3 0.4-3.2z"),        # dłoń z kciukiem
        ("detail", "M15.6 12.6V17.6M18.4 13.4V18.2M21.1 14.6V18.6"),
    ]


def open_hand():
    return [
        ("fill", rect(10.6, 6.0, 3.3, 11.0, 1.65)),
        ("fill", rect(13.9, 4.5, 3.3, 12.0, 1.65)),
        ("fill", rect(17.2, 5.5, 3.3, 11.0, 1.65)),
        ("fill", rect(20.4, 8.0, 3.1, 9.0, 1.55)),
        ("fill", "M6.6 16.2c1.0-1.0 2.6-0.9 3.5 0.2l0.6 0.8V14h12.8v7.0c0 3.9-2.8 7.0-6.6 7.0h-2.6c-2.3 0-3.9-1.0-5.2-2.8"
                 "l-2.9-4.0c-0.7-1.0-0.6-2.3 0.4-3.0z"),
        ("detail", "M13.9 7.5V17.5M17.2 7.5V17.5M20.45 9.5V17.5"),
    ]


def closed_hand():
    return [
        ("fill", rect(10.6, 11.5, 3.3, 6.0, 1.65)),
        ("fill", rect(13.9, 10.8, 3.3, 6.5, 1.65)),
        ("fill", rect(17.2, 11.2, 3.3, 6.2, 1.65)),
        ("fill", rect(20.4, 12.2, 3.1, 5.5, 1.55)),
        ("fill", "M8.4 17.6c0.9-0.8 2.2-0.7 3.0 0.2V14.5h12.1v6.8c0 3.7-2.6 6.7-6.3 6.7h-2.5c-2.2 0-3.7-0.9-4.9-2.6"
                 "l-1.7-2.5c-0.6-0.9-0.5-2.1 0.3-2.8z"),
        ("detail", "M13.9 12.6V17.2M17.2 12.4V17.2M20.45 13.2V17.2"),
    ]


IBEAM = "M12.4 5.6c1.8 0 3 .6 3.6 1.9c.6-1.3 1.8-1.9 3.6-1.9M16 7.5V24.5M12.4 26.4c1.8 0 3-.6 3.6-1.9c.6 1.3 1.8 1.9 3.6 1.9"


def ibeam(vertical=False):
    d = IBEAM
    if vertical:
        return [("line", d, 1.5, "rotate(90 16 16)")]
    return [("line", d, 1.5)]


def crosshair():
    return [("line", "M16 4.5V12.5M16 19.5V27.5M4.5 16H12.5M19.5 16H27.5", 1.6), ("fill", circle(16, 16, 1.3))]


def cell():
    return [("fill", poly([(13.6, 6), (18.4, 6), (18.4, 13.6), (26, 13.6), (26, 18.4), (18.4, 18.4), (18.4, 26),
                           (13.6, 26), (13.6, 18.4), (6, 18.4), (6, 13.6), (13.6, 13.6)]))]


def move():
    return [double_arrow(0, 23, 5.0, 4.4, 1.3), double_arrow(90, 23, 5.0, 4.4, 1.3)]


def split(angle):
    """Podział kolumn/wierszy: dwie kreski i strzałki na boki."""
    pts_l = [(4.5, 16), (9.5, 11.2), (9.5, 14.6), (13.2, 14.6), (13.2, 17.4), (9.5, 17.4), (9.5, 20.8)]
    pts_r = [(32 - x, y) for x, y in pts_l]
    return [("fill", poly(transform_points(pts_l, angle))), ("fill", poly(transform_points(pts_r, angle))),
            ("fill", poly(transform_points([(14.4, 6.5), (15.4, 6.5), (15.4, 25.5), (14.4, 25.5)], angle))),
            ("fill", poly(transform_points([(16.6, 6.5), (17.6, 6.5), (17.6, 25.5), (16.6, 25.5)], angle)))]


def up_arrow():
    return [("fill", poly([(16, 4.5), (23.5, 13), (18.2, 13), (18.2, 26), (13.8, 26), (13.8, 13), (8.5, 13)]))]


def pencil():
    pts = [(6, 26), (7.2, 20.4), (20.6, 7), (25, 11.4), (11.6, 24.8)]
    return [("fill", poly(pts))]


def dropper():
    return [("fill", "M21.2 6.4c1.2-1.2 3.1-1.2 4.3 0s1.2 3.1 0 4.3l-2.2 2.2.9.9-2 2-.9-.9-7.6 7.6c-.6.6-1.4 1-2.3 1.1"
                     "l-2.2.3-1.6 1.6-1.6-1.6 1.6-1.6.3-2.2c.1-.9.5-1.7 1.1-2.3l7.6-7.6-.9-.9 2-2 .9.9z")]


def magnifier(sign):
    items = [("line", circle(13.5, 13.5, 6.6), 2.2), ("line", "M18.4 18.4L25.5 25.5", 3.2)]
    if sign:
        items.append(("line", "M10.6 13.5H16.4" + ("M13.5 10.6V16.4" if sign == "+" else ""), 1.8))
    return items


# ——— Odznaki (kopiuj, skrót, zakaz…) przy strzałce ———

def badge(kind, cx=22.2, cy=23.0, r=5.4):
    fill = {"copy": GREEN, "link": BLUE, "help": BLUE, "no": RED, "menu": "#3F4452"}[kind]
    out = [f'<circle cx="{cx}" cy="{cy}" r="{r + 1.1}" fill="{RIM}"/>', f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"/>']
    s = 'stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"'
    if kind == "copy":
        out.append(f'<path d="M{cx - 2.6} {cy}H{cx + 2.6}M{cx} {cy - 2.6}V{cy + 2.6}" {s}/>')
    elif kind == "link":
        out.append(f'<path d="M{cx - 2.4} {cy + 2.4}L{cx + 2.4} {cy - 2.4}M{cx - 0.4} {cy - 2.4}H{cx + 2.4}V{cy + 0.4}" {s}/>')
    elif kind == "help":
        out.append(f'<path d="M{cx - 1.8} {cy - 1.6}a1.9 1.9 0 1 1 2.7 1.7c-.6.3-.9.7-.9 1.3v.3" {s}/>')
        out.append(f'<circle cx="{cx}" cy="{cy + 2.9}" r=".95" fill="#FFFFFF"/>')
    elif kind == "no":
        out.append(f'<path d="M{cx - 2.5} {cy - 2.5}L{cx + 2.5} {cy + 2.5}" {s}/>')
        out.append(f'<circle cx="{cx}" cy="{cy}" r="3.2" {s}/>')
    elif kind == "menu":
        out.append(f'<path d="M{cx - 2.5} {cy - 1.8}H{cx + 2.5}M{cx - 2.5} {cy}H{cx + 2.5}M{cx - 2.5} {cy + 1.8}H{cx + 2.5}" '
                   f'stroke="#FFFFFF" stroke-width="1.1" stroke-linecap="round" fill="none"/>')
    return "".join(out)


def not_allowed():
    s = 'fill="none" stroke-linecap="round"'
    return (f'<g filter="url(#sh)" opacity=".35"><circle cx="16" cy="17" r="9" fill="none" stroke="#000" stroke-width="5.5"/></g>'
            f'<circle cx="16" cy="16" r="9" {s} stroke="{RIM}" stroke-width="6"/>'
            f'<path d="M9.8 9.8L22.2 22.2" {s} stroke="{RIM}" stroke-width="6"/>'
            f'<circle cx="16" cy="16" r="9" {s} stroke="{RED}" stroke-width="3.2"/>'
            f'<path d="M9.8 9.8L22.2 22.2" {s} stroke="{RED}" stroke-width="3.2"/>')


def spinner(cx, cy, r, w, phase, frames):
    """Kółko ładowania: grafitowy tor i obracający się łuk w kolorze akcentu Aster."""
    start = 360 * phase / frames - 90
    sweep = 110
    a0, a1 = math.radians(start), math.radians(start + sweep)
    x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
    x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
    arc = f"M{x0:.3f} {y0:.3f}A{r} {r} 0 0 1 {x1:.3f} {y1:.3f}"
    return (f'<g filter="url(#sh)" opacity=".35"><circle cx="{cx}" cy="{cy + 0.8}" r="{r}" fill="none" stroke="#000" stroke-width="{w + 2.6}"/></g>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{RIM}" stroke-width="{w + 2 * OUTLINE + 0.4}"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="url(#ink)" stroke-width="{w}"/>'
            f'<path d="{arc}" fill="none" stroke="{ACCENT}" stroke-width="{w}" stroke-linecap="round"/>')


# ——— Składanie SVG ———

DEFS = (f'<defs><linearGradient id="ink" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{INK_TOP}"/><stop offset="1" stop-color="{INK_BOTTOM}"/></linearGradient>'
        f'<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="0.9"/></filter></defs>')


def shape_layers(items):
    def element(it, paint):
        tr = f' transform="{it[3]}"' if len(it) > 3 else ""
        if it[0] == "fill":
            if paint == "shadow":
                return f'<path d="{it[1]}" fill="#000" stroke="#000" stroke-width="{2 * OUTLINE}" stroke-linejoin="round"{tr}/>'
            if paint == "rim":
                return f'<path d="{it[1]}" fill="{RIM}" stroke="{RIM}" stroke-width="{2 * OUTLINE}" stroke-linejoin="round"{tr}/>'
            return f'<path d="{it[1]}" fill="url(#ink)"{tr}/>'
        w = it[2]
        if paint == "shadow":
            return f'<path d="{it[1]}" fill="none" stroke="#000" stroke-width="{w + 2 * OUTLINE}" stroke-linecap="round" stroke-linejoin="round"{tr}/>'
        if paint == "rim":
            return f'<path d="{it[1]}" fill="none" stroke="{RIM}" stroke-width="{w + 2 * OUTLINE}" stroke-linecap="round" stroke-linejoin="round"{tr}/>'
        return f'<path d="{it[1]}" fill="none" stroke="url(#ink)" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"{tr}/>'

    shapes = [i for i in items if i[0] != "detail"]
    shadow = "".join(element(i, "shadow") for i in shapes)
    rim = "".join(element(i, "rim") for i in shapes)
    ink = "".join(element(i, "ink") for i in shapes)
    # Szczegóły (przerwy między palcami) — jaśniejsze kreski na grafitowym wnętrzu
    detail = "".join(f'<path d="{i[1]}" fill="none" stroke="#5A5F70" stroke-width=".7" stroke-linecap="round"/>'
                     for i in items if i[0] == "detail")
    return (f'<g filter="url(#sh)" opacity=".38" transform="translate(0 1)">{shadow}</g>{rim}{ink}{detail}')


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">'
            f'{DEFS}{body}</svg>')


# ——— Kursory: nazwa → (klatki SVG, gorący punkt, opóźnienie ms, aliasy) ———

def cursors():
    c = {}

    def add(name, bodies, hot, aliases=(), delay=0):
        c[name] = ([svg(b) for b in bodies], hot, delay, list(aliases))

    add("default", [shape_layers(arrow())], ARROW_HOT,
        ["left_ptr", "arrow", "top_left_arrow", "X_cursor", "x-cursor", "dnd-none", "dnd-move", "move-arrow", "openhand-arrow"])
    add("right_ptr", [shape_layers(arrow(mirror=True))], (32 - ARROW_HOT[0], ARROW_HOT[1]), ["right-arrow", "draft_large", "draft_small"])
    add("pointer", [shape_layers(hand_pointer())], (13.6, 4.2),
        ["hand2", "hand1", "hand", "pointing_hand", "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822"])
    add("grab", [shape_layers(open_hand())], (15.5, 15.5), ["openhand", "fleur-hand", "5aca4d189052212118709018842178c0"])
    add("grabbing", [shape_layers(closed_hand())], (15.5, 16), ["closedhand", "dnd-grab", "fcf21c00b30f7e3f83fe0dfd12e71cff"])
    add("text", [shape_layers(ibeam())], (16, 16), ["xterm", "ibeam"])
    add("vertical-text", [shape_layers(ibeam(vertical=True))], (16, 16), ["048008013003cff3c00c801001200000"])
    add("crosshair", [shape_layers(crosshair())], (16, 16), ["cross", "tcross", "cross_reverse", "diamond_cross", "target"])
    add("cell", [shape_layers(cell())], (16, 16), ["plus"])
    add("move", [shape_layers(move())], (16, 16), ["all-scroll", "fleur", "size_all", "4498f0e0c1937ffe01fd06f973665830", "9081237383d90e509aa00f00170e968f"])
    add("ew-resize", [shape_layers([double_arrow(0)])], (16, 16),
        ["e-resize", "w-resize", "sb_h_double_arrow", "h_double_arrow", "size_hor", "left_side", "right_side",
         "028006030e0e7ebffc7f7070c0600140", "14fef782d02440884392942c11205230-h"])
    add("ns-resize", [shape_layers([double_arrow(90)])], (16, 16),
        ["n-resize", "s-resize", "sb_v_double_arrow", "v_double_arrow", "size_ver", "top_side", "bottom_side",
         "00008160000006810000408080010102", "double_arrow"])
    add("nwse-resize", [shape_layers([double_arrow(45, 22)])], (16, 16),
        ["nw-resize", "se-resize", "bd_double_arrow", "size_fdiag", "top_left_corner", "bottom_right_corner",
         "c7088f0f3e6c8088236ef8e1e3e70000"])
    add("nesw-resize", [shape_layers([double_arrow(-45, 22)])], (16, 16),
        ["ne-resize", "sw-resize", "fd_double_arrow", "size_bdiag", "top_right_corner", "bottom_left_corner",
         "fcf1c3c7cd4491d801f1e1c78f100000"])
    add("col-resize", [shape_layers(split(0))], (16, 16), ["split_h", "14fef782d02440884392942c11205230", "sb_h_double_arrow-split"])
    add("row-resize", [shape_layers(split(90))], (16, 16), ["split_v", "2870a09082c103050810ffdffffe0204"])
    add("up-arrow", [shape_layers(up_arrow())], (16, 4.5), ["center_ptr", "up_arrow", "sb_up_arrow"])
    add("pencil", [shape_layers(pencil())], (6, 26), ["draft", "pen"])
    add("color-picker", [shape_layers(dropper())], (6.6, 25.4), ["dropper"])
    add("zoom-in", [shape_layers(magnifier("+"))], (13.5, 13.5), ["zoom_in"])
    add("zoom-out", [shape_layers(magnifier("-"))], (13.5, 13.5), ["zoom_out"])
    add("not-allowed", [not_allowed()], (16, 16),
        ["forbidden", "crossed_circle", "circle", "no_drop", "03b6e0fcb3499374a867c041f52298f0", "pirate"])
    add("no-drop", [shape_layers(arrow()) + badge("no")], ARROW_HOT, ["dnd-no-drop"])
    add("copy", [shape_layers(arrow()) + badge("copy")], ARROW_HOT,
        ["dnd-copy", "1081e37283d90000800003c07f3ef6bf", "6407b0e94181790501fd1e167b474872", "08ffe1cb5fe6fc01f906f1c063814ccf"])
    add("alias", [shape_layers(arrow()) + badge("link")], ARROW_HOT,
        ["link", "dnd-link", "dnd-ask", "3085a0e285430894940527032f8b26df", "640fb0e74195791501fd1ed57b41487f", "a2a266d0498c3104214a47bd64ab0fc8"])
    add("help", [shape_layers(arrow()) + badge("help")], ARROW_HOT,
        ["question_arrow", "whats_this", "left_ptr_help", "d9ce0ab605698f320427677b458ad60b", "5c6cd98b3f3ebcb1f9c7f1c204630408"])
    add("context-menu", [shape_layers(arrow()) + badge("menu")], ARROW_HOT, ["08ffe1e65f80fcfdf9fff11263e74c48"])

    frames = 12
    add("wait", [spinner(16, 16, 8.2, 3.2, i, frames) for i in range(frames)], (16, 16), ["watch"], delay=55)
    add("progress", [shape_layers(arrow()) + spinner(22.4, 22.8, 4.3, 2.4, i, frames) for i in range(frames)], ARROW_HOT,
        ["left_ptr_watch", "half-busy", "3ecb610c1bf2410f44200f48c40d3599", "00000000000000020006000e7e9ffc3f",
         "08e8e1c95fe2fc01f976f1e063a24ccd"], delay=55)
    return c


# ——— Budowanie motywu ———

def build(out, preview=None):
    data = cursors()
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "cursors"))
    os.makedirs(os.path.join(out, "cursors_scalable"))
    with open(os.path.join(out, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=Aster\nComment=Kursor systemu Aster\nInherits=breeze_cursors\n")

    with tempfile.TemporaryDirectory() as tmp:
        for name, (frames, hot, delay, aliases) in data.items():
            # Skalowalne (KWin): SVG + metadata.json
            sdir = os.path.join(out, "cursors_scalable", name)
            os.makedirs(sdir)
            meta = []
            for i, body in enumerate(frames):
                fn = f"{name}.svg" if len(frames) == 1 else f"{name}-{i + 1:02d}.svg"
                with open(os.path.join(sdir, fn), "w") as f:
                    f.write(body)
                entry = {"filename": fn, "hotspot_x": hot[0], "hotspot_y": hot[1], "nominal_size": NOMINAL}
                if delay:
                    entry["delay"] = delay
                meta.append(entry)
            with open(os.path.join(sdir, "metadata.json"), "w") as f:
                json.dump(meta, f, indent=1)

            # Xcursor: każdy rozmiar z SVG (rsvg-convert), potem xcursorgen
            config = []
            for size in SIZES:
                px = round(size * CANVAS / NOMINAL)
                for i, body in enumerate(frames):
                    src = os.path.join(tmp, f"{name}-{i}.svg")
                    with open(src, "w") as f:
                        f.write(body)
                    png = os.path.join(tmp, f"{name}-{size}-{i}.png")
                    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-o", png, src], check=True)
                    hx, hy = round(hot[0] * px / CANVAS), round(hot[1] * px / CANVAS)
                    config.append(f"{size} {hx} {hy} {png}" + (f" {delay}" if delay else ""))
            cfg = os.path.join(tmp, f"{name}.cfg")
            with open(cfg, "w") as f:
                f.write("\n".join(config) + "\n")
            subprocess.run(["xcursorgen", cfg, os.path.join(out, "cursors", name)], check=True)

            for alias in aliases:
                if alias in data:
                    continue
                for sub in ("cursors", "cursors_scalable"):
                    link = os.path.join(out, sub, alias)
                    if not os.path.lexists(link):
                        os.symlink(name, link)

    if preview:
        make_preview(data, preview)


def make_preview(data, path):
    """Arkusz podglądu: każdy kursor powiększony 3×, na jasnym i ciemnym tle."""
    names = list(data)
    cols, cell_size, scale = 7, 120, 3
    rows = math.ceil(len(names) / cols)
    w, h = cols * cell_size, rows * cell_size
    parts = []
    for bg_i, (bg, fg) in enumerate((("#EEF0F5", "#5B6270"), ("#1B1D24", "#A2A9B6"))):
        oy = bg_i * h
        parts.append(f'<rect x="0" y="{oy}" width="{w}" height="{h}" fill="{bg}"/>')
        for i, name in enumerate(names):
            x, y = (i % cols) * cell_size, oy + (i // cols) * cell_size
            body = data[name][0][len(data[name][0]) // 3]
            inner = body[body.index(">") + 1:body.rindex("</svg>")].replace('id="ink"', f'id="ink{bg_i}{i}"') \
                .replace("url(#ink)", f"url(#ink{bg_i}{i})").replace('id="sh"', f'id="sh{bg_i}{i}"').replace("url(#sh)", f"url(#sh{bg_i}{i})")
            parts.append(f'<g transform="translate({x + 12} {y + 4}) scale({scale})">{inner}</g>')
            parts.append(f'<text x="{x + cell_size / 2}" y="{y + cell_size - 8}" font-family="sans-serif" font-size="11" '
                         f'text-anchor="middle" fill="{fg}">{name}</text>')
    doc = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{2 * h}">{"".join(parts)}</svg>'
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(doc)
    subprocess.run(["rsvg-convert", "-o", path, f.name], check=True)
    os.unlink(f.name)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)

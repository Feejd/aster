"""Tapeta „Aster Bloom” — płynne, świecące wstęgi koloru (jasna i ciemna).

Każda wstęga to „rurka” ze światłem: cieniowanie w poprzek, połysk przy górnej krawędzi,
jasny rant, poświata za nią i miękki cień na wstędze pod spodem. Na koniec delikatne ziarno.

Uruchom:  python tools/make_bloom.py   (numpy + pillow)
Wynik:    data/wallpapers/bloom-light.jpg, data/wallpapers/bloom-dark.jpg (+ miniatury)
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 2560, 1600
OUT = Path(__file__).resolve().parent.parent / "data" / "wallpapers"


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, radius):
    """Szybkie rozmycie (zmniejsz → powiększ) tablicy 2D 0..1."""
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    small = img.resize((max(1, W // radius), max(1, H // radius)), Image.BILINEAR).filter(ImageFilter.GaussianBlur(2))
    return np.asarray(small.resize((W, H), Image.BICUBIC), np.float32) / 255


ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
nx, ny = xs / W, ys / H

# Wstęgi: (podstawa, amplituda, częstotliwość, faza, grubość, kolor od, kolor do)
RIBBONS = {
    "light": [
        (0.50, 0.10, 1.4, 0.4, 0.13, "#8FA8FF", "#C29BFF"),
        (0.64, 0.12, 1.1, 2.2, 0.12, "#FFA3CA", "#FFBE7A"),
        (0.76, 0.10, 1.6, 4.0, 0.11, "#6EDCCD", "#6B9BFF"),
        (0.92, 0.08, 1.2, 1.1, 0.13, "#AE8FFF", "#FF8DC2"),
    ],
    "dark": [
        (0.50, 0.10, 1.4, 0.4, 0.13, "#3B5BFF", "#8B5CF6"),
        (0.64, 0.12, 1.1, 2.2, 0.12, "#FF3D8B", "#FF8A3D"),
        (0.76, 0.10, 1.6, 4.0, 0.11, "#14C8B4", "#3B82F6"),
        (0.92, 0.08, 1.2, 1.1, 0.13, "#A855F7", "#EC4899"),
    ],
}
BACKGROUND = {
    "light": ("#C9D6FF", "#E6DCFF", "#FFD9E8"),
    "dark": ("#05060F", "#0D0B24", "#1A0B22"),
}


def render(mode):
    dark = mode == "dark"
    a, b, c = (hexc(x) for x in BACKGROUND[mode])
    t = np.clip(0.6 * nx + 0.4 * ny, 0, 1)[..., None]
    img = a * (1 - t) + b * t
    corner = np.exp(-(((nx - 1.0) ** 2) + ((ny - 1.0) ** 2)) / 0.35)[..., None]
    img = img * (1 - corner * 0.6) + c * corner * 0.6
    # Miękkie poświaty koloru u góry (niebieska z lewej, różowa z prawej)
    for cx, cy, rad, col, strength in ((0.12, 0.05, 0.22, "#7C9BFF", 0.55), (0.88, 0.12, 0.26, "#FF9CC7", 0.45)):
        g = np.exp(-(((nx - cx) * 1.6) ** 2 + (ny - cy) ** 2) / rad)[..., None] * (strength * (0.5 if dark else 1.0))
        img = img * (1 - g) + hexc(col) * g

    # Układ współrzędnych obrócony o -16° — wstęgi płyną ukośnie
    ang = np.deg2rad(-12)
    u = (nx - 0.5) * np.cos(ang) - (ny - 0.5) * (H / W) * np.sin(ang) + 0.5
    v = (nx - 0.5) * (W / H) * np.sin(ang) * (H / W) + (ny - 0.5) * np.cos(ang) + 0.5

    for i, (base, amp, freq, phase, thick, c1, c2) in enumerate(RIBBONS[mode]):
        center = base + amp * np.sin(freq * np.pi * u + phase) + 0.035 * np.sin(3.1 * np.pi * u + phase * 1.7)
        th = thick * (0.72 + 0.28 * np.sin(1.3 * np.pi * u + phase * 0.6))
        d = (v - center) / th                                    # -1 … 1 w poprzek wstęgi
        inside = smooth(1.02, 0.94, np.abs(d))

        # Cień rzucony na to, co pod spodem, i poświata wokół
        shadow = blur(np.clip(inside, 0, 1), 18)
        shadow = np.concatenate([np.zeros((26, W), np.float32), shadow[:-26]], axis=0)   # przesunięcie w dół bez zawijania
        img = img * (1 - (shadow * (0.30 if dark else 0.14))[..., None])
        glow = blur(inside, 26)

        k = np.clip(u, 0, 1)[..., None]
        col = hexc(c1) * (1 - k) + hexc(c2) * k
        img = img + col * (glow * (0.38 if dark else 0.22))[..., None]

        # Cieniowanie „rurki”, połysk przy górnej krawędzi i jasny rant
        tube = np.sqrt(np.clip(1 - d * d, 0, 1))
        shade = (0.62 + 0.38 * tube)[..., None]
        spec = np.exp(-((d + 0.52) / 0.16) ** 2) * (0.42 if dark else 0.55)
        rim = np.exp(-((np.abs(d) - 0.94) / 0.035) ** 2) * (0.30 if dark else 0.38)
        ribbon = col * shade + (spec + rim)[..., None]
        if dark:
            ribbon = ribbon * 1.08
        alpha = (inside * 0.94)[..., None]
        img = img * (1 - alpha) + ribbon * alpha

    # Winieta i ziarno
    vig = 1 - (0.20 if dark else 0.07) * ((nx - 0.5) ** 2 + (ny - 0.45) ** 2) * 2.2
    img = img * vig[..., None]
    rng = np.random.default_rng(3)
    img = img + rng.normal(0, 0.010, (H, W, 1)).astype(np.float32)
    return np.clip(img, 0, 1)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for mode in ("light", "dark"):
        im = Image.fromarray((render(mode) * 255 + 0.5).astype(np.uint8))
        im.save(OUT / f"bloom-{mode}.jpg", quality=92, optimize=True, progressive=True)
        im.resize((320, 200), Image.LANCZOS).save(OUT / f"bloom-{mode}-thumb.jpg", quality=88)
        print("ok", mode)


if __name__ == "__main__":
    main()

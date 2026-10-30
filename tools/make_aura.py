"""Tapeta „Aura” — tło z projektu UI Aster (makiety Main / MainDark), w pełnej rozdzielczości.

Gradient pod kątem 170° i cztery duże, mocno rozmyte plamy koloru (CSS: blur 110 px, krycie 0,85),
przeskalowane z makiety 1440×900 do 2560×1600. Delikatne ziarno usuwa pasy w gradientach.

Uruchom:  python tools/make_aura.py   (numpy + pillow)
Wynik:    data/wallpapers/aura-light.jpg, data/wallpapers/aura-dark.jpg (+ miniatury)
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1600
K = W / 1440                     # skala z makiety
OUT = Path(__file__).resolve().parent.parent / "data" / "wallpapers"

DESIGN = {
    "light": {
        "gradient": [(0.0, "#D4E2FF"), (0.5, "#E9E2F7"), (1.0, "#FFE4D4")],
        "blobs": [(900, -200, -320, "#6F97FF"), (820, 980, -300, "#B497FF"), (900, 820, 420, "#FFAE85"), (640, -80, 560, "#7DDCCB")],
    },
    "dark": {
        "gradient": [(0.0, "#090D1C"), (0.55, "#120F28"), (1.0, "#170F2E")],
        "blobs": [(900, -200, -320, "#2847D9"), (820, 980, -300, "#7B3BD8"), (900, 820, 420, "#C23E6E"), (640, -80, 560, "#0E8C8F")],
    },
}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def css_gradient(stops, angle_deg):
    """linear-gradient(angle) jak w CSS: kierunek 0° = do góry, rośnie zgodnie z ruchem wskazówek."""
    a = math.radians(angle_deg)
    dx, dy = math.sin(a), -math.cos(a)
    half = abs(W / 2 * dx) + abs(H / 2 * dy)               # długość linii gradientu / 2
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    t = ((xs - W / 2) * dx + (ys - H / 2) * dy) / (2 * half) + 0.5
    t = np.clip(t, 0, 1)
    out = np.zeros((H, W, 3), np.float32)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / (p1 - p0))[..., None]
        out = np.where(m[..., None], hexc(c0) * (1 - k) + hexc(c1) * k, out)
    return out


def render(mode):
    d = DESIGN[mode]
    img = css_gradient(d["gradient"], 170)
    for size, left, top, color in d["blobs"]:
        layer = Image.new("L", (W, H), 0)
        x0, y0, s = left * K, top * K, size * K
        ImageDraw.Draw(layer).ellipse([x0, y0, x0 + s, y0 + s], fill=255)
        # CSS blur(110px) = rozmycie Gaussa o odchyleniu 110 px
        layer = layer.filter(ImageFilter.GaussianBlur(110 * K))
        a = (np.asarray(layer, np.float32) / 255 * 0.85)[..., None]
        img = img * (1 - a) + hexc(color) * a
    rng = np.random.default_rng(7)
    img = img + rng.normal(0, 0.006, (H, W, 1)).astype(np.float32)
    return np.clip(img, 0, 1)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for mode in ("light", "dark"):
        im = Image.fromarray((render(mode) * 255 + 0.5).astype(np.uint8))
        im.save(OUT / f"aura-{mode}.jpg", quality=93, optimize=True, progressive=True)
        im.resize((320, 200), Image.LANCZOS).save(OUT / f"aura-{mode}-thumb.jpg", quality=88)
        print("ok", mode)


if __name__ == "__main__":
    main()

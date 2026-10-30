"""Renderuje tapety-krajobrazy Aster (własne, bez licencji stron trzecich).

Szczyty  — pasma gór we mgle o świcie / pod księżycem.
Jezioro — te same góry o złotej godzinie / o zmierzchu, odbite w tafli wody.

Uruchom:  python tools/make_wallpapers.py   (potrzebuje numpy i pillow)
Wynik:    data/wallpapers/<nazwa>-light.jpg, wallpapers/<nazwa>-dark.jpg
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 2560, 1600
OUT = Path(__file__).resolve().parent.parent / "data" / "wallpapers"

ys = (np.arange(H, dtype=np.float32) + 0.5)[:, None] / H     # 0 = góra
xs = (np.arange(W, dtype=np.float32) + 0.5)[None, :] / W


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def mix(a, b, t):
    t = np.asarray(t, np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def gradient(stops, t):
    """Gradient wielu kolorów: stops = [(pozycja, '#hex'), ...]."""
    t = np.asarray(t, np.float32)
    out = np.zeros(t.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = smooth(p0, p1, t)[..., None]
        out = np.where(m[..., None], mix(hexc(c0), hexc(c1), k), out)
    out = np.where((t < stops[0][0])[..., None], hexc(stops[0][1]), out)
    out = np.where((t > stops[-1][0])[..., None], hexc(stops[-1][1]), out)
    return out


def noise1(x, freq, seed):
    rng = np.random.default_rng(seed)
    n = int(freq * 4) + 3
    v = rng.random(n).astype(np.float32)
    p = x * freq
    i = np.floor(p).astype(int)
    f = p - i
    f = f * f * (3 - 2 * f)
    return v[i % n] * (1 - f) + v[(i + 1) % n] * f


def ridge1(x, freq, octaves, seed, sharp=1.0):
    """Grzbiet górski: suma oktaw „pofałdowanego” szumu."""
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        n = noise1(x, freq * 2 ** o, seed + o * 17)
        r = 1 - np.abs(2 * n - 1)
        total = total + amp * r ** (1 + sharp * (o == 0))
        norm += amp
        amp *= 0.48
    return total / norm


def noise2(fx, fy, seed, shape=(H, W)):
    rng = np.random.default_rng(seed)
    gy, gx = int(fy) + 3, int(fx) + 3
    v = rng.random((gy, gx)).astype(np.float32)
    py = ys * fy
    px = xs * fx
    iy = np.floor(py).astype(int)
    ix = np.floor(px).astype(int)
    ty = py - iy
    tx = px - ix
    ty = ty * ty * (3 - 2 * ty)
    tx = tx * tx * (3 - 2 * tx)
    iy = np.broadcast_to(iy, shape)
    ix = np.broadcast_to(ix, shape)
    a = v[iy, ix]
    b = v[iy, ix + 1]
    c = v[iy + 1, ix]
    d = v[iy + 1, ix + 1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm2(fx, fy, octaves, seed):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * noise2(fx * 2 ** o, fy * 2 ** o, seed + o * 31)
        norm += amp
        amp *= 0.5
    return total / norm


# Pasma od najdalszego do najbliższego: (średnia wysokość, amplituda, częstotliwość, mgła)
LAYERS = [
    (0.555, 0.15, 2.2, 0.82),
    (0.600, 0.20, 1.6, 0.66),
    (0.680, 0.15, 2.4, 0.50),
    (0.760, 0.12, 1.8, 0.33),
    (0.850, 0.11, 1.4, 0.17),
    (0.940, 0.08, 1.2, 0.04),
]


def ridgeline(i, seed):
    base, amp, freq, _ = LAYERS[i]
    x = xs[0]
    r = ridge1(x + i * 0.37, freq, 6, seed + i * 101, sharp=1.2)
    h = base - amp * (r - 0.35)
    if i == 1:   # główny szczyt pasma po lewej, słońce/księżyc świeci zza niego z prawej
        h = h - 0.17 * np.exp(-((x - 0.30) / 0.11) ** 2)
    if i == 2:
        h = h - 0.08 * np.exp(-((x - 0.86) / 0.08) ** 2)
    return h.astype(np.float32)


def render(p, lake=False, seed=7):
    sky_t = ys / 0.66
    img = gradient(p["sky"], sky_t) * np.ones((1, W, 1), np.float32)

    # Słońce / księżyc i jego poświata
    sx, sy = p["sun"]
    dist = np.sqrt(((xs - sx) * W / H) ** 2 + (ys - sy) ** 2)
    glow = np.exp(-dist / p["glow_r"]) * p["glow_a"]
    img = mix(img, hexc(p["glow"]), np.clip(glow, 0, 1))
    disc = smooth(p["sun_r"] + 0.004, p["sun_r"], dist)
    img = mix(img, hexc(p["disc"]), disc)

    # Chmury: rozciągnięte poziome smugi, podświetlone od strony światła
    cl = fbm2(2.4, 14, 5, seed + 900)
    cl = smooth(0.52, 0.78, cl) * smooth(0.10, 0.30, ys) * (1 - smooth(0.44, 0.56, ys))
    lit = np.exp(-dist / 0.35)
    cloud_col = mix(hexc(p["cloud"]), hexc(p["glow"]), np.clip(lit * 1.2, 0, 1))
    img = mix(img, cloud_col, cl * p["cloud_a"])

    if p.get("stars"):
        rng = np.random.default_rng(seed + 5)
        n = 1500
        sxs = rng.integers(0, W, n)
        sys_ = (rng.random(n) ** 1.6 * H * 0.62).astype(int)
        br = rng.random(n) ** 3
        star = np.zeros((H, W), np.float32)
        star[sys_, sxs] = br
        star_img = Image.fromarray((star * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.9))
        star = np.asarray(star_img, np.float32) / 255 * 3.2
        star *= (1 - smooth(0.35, 0.62, ys)) * (1 - np.clip(glow * 2, 0, 1))
        img = img + star[..., None] * hexc("#DCE4FF")

    haze = hexc(p["haze"])
    tex = fbm2(18, 9, 4, seed + 300)                    # nieregularna linia śniegu
    soft = fbm2(7, 5, 4, seed + 400)                    # łagodne zróżnicowanie zboczy

    for i in range(len(LAYERS)):
        base, amp, freq, atm = LAYERS[i]
        h = ridgeline(i, seed)
        depth = ys - h[None, :]                        # >0 pod grzbietem
        inside = depth > 0
        depth = np.maximum(depth, 0)
        aa = np.clip(depth * H + 0.5, 0, 1)            # wygładzona krawędź grzbietu

        # Zbocza: nachylenie z wygładzonego grzbietu, żeby ściany miały szerokie płaszczyzny
        k = np.exp(-np.linspace(-3, 3, 121) ** 2)
        hs = np.convolve(np.pad(h, 60, mode="edge"), k / k.sum(), mode="valid")
        slope = np.tanh(np.gradient(hs) * W * 1.4)[None, :]
        fall = np.exp(-depth / 0.20)
        # Ściana schodzi od grzbietu ukośnie w dół — przesunięcie zależne od głębokości
        # i rozmycie zamieniają pionowe pasy w szerokie, miękkie płaszczyzny
        shear = np.clip((np.arange(W)[None, :] + (depth * H * 0.9 * np.sign(slope)).astype(int)), 0, W - 1)
        slope2 = slope[0][shear]
        light = 0.5 + 0.34 * slope2 * fall + (soft - 0.5) * 0.22
        light_img = Image.fromarray((np.clip(light, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(26))
        light = np.asarray(light_img, np.float32) / 255

        col = mix(hexc(p["shadow"]), hexc(p["lit"]), light)
        col = mix(col, hexc(p["deep"]), smooth(0.0, 0.28, depth) * 0.45)

        # Śnieg na wysokich szczytach
        peak = smooth(base - amp * 0.2, base - amp - 0.12, h)[None, :]
        snowline = 0.03 + 0.05 * tex
        snow = peak * (1 - smooth(snowline * 0.6, snowline, depth)) * p["snow_a"]
        snow_col = mix(hexc(p["snow_shadow"]), hexc(p["snow_lit"]), np.clip(light * 1.3 - 0.15, 0, 1))
        col = mix(col, snow_col, np.clip(snow, 0, 1))

        # Poświata na krawędzi grzbietu (światło zza gór)
        near_light = np.exp(-np.abs(xs - sx) / 0.30)
        rim = np.exp(-depth * H / 3.0) * near_light * p["rim_a"]
        col = mix(col, hexc(p["glow"]), np.clip(rim, 0, 1))

        # Perspektywa powietrzna i mgła u podnóża
        col = mix(col, haze, atm)
        col = mix(col, mix(haze, hexc(p["glow"]), 0.25 * near_light), np.clip(glow * 0.6 * atm, 0, 1))
        fog = smooth(base - amp * 0.1, base + 0.10, ys) * p["fog_a"] * (0.55 + 0.45 * fbm2(3, 9, 3, seed + i))
        col = mix(col, mix(haze, hexc("#FFFFFF"), p["fog_white"]), np.clip(fog, 0, 1))

        img = np.where(inside[..., None], mix(img, col, aa), img)

    if lake:
        water_y = 0.80
        wy = int(water_y * H)
        rows = H - wy
        src = img[wy - rows:wy][::-1].copy()            # lustro
        ripple = (fbm2(5, 90, 3, seed + 77)[wy:] - 0.5)
        rr = np.arange(rows, dtype=np.float32)[:, None] / rows
        shift = (ripple * (6 + 40 * rr)).astype(int)
        cols = np.clip(np.arange(W)[None, :] + shift, 0, W - 1)
        refl = src[np.arange(rows)[:, None], cols]
        refl = np.asarray(Image.fromarray(np.clip(refl * 255, 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur((0.6, 3.0))), np.float32) / 255
        water = mix(refl, hexc(p["water"]), 0.28 + 0.45 * rr)
        sparkle = smooth(0.62, 0.72, fbm2(40, 260, 2, seed + 88)[wy:]) * np.exp(-np.abs(xs - sx) / 0.10) * (1 - rr) * p["sparkle"]
        water = water + sparkle[..., None] * hexc(p["glow"])
        shore = np.exp(-(rr * rows) / 2.0)[..., None] * 0.35
        water = mix(water, hexc(p["deep"]), shore[..., 0])
        img[wy:] = water

    # Winieta i ziarno (bez pasm w gradientach)
    vig = 1 - 0.18 * (((xs - 0.5) * 1.3) ** 2 + ((ys - 0.48) * 1.2) ** 2)
    img = img * vig[..., None]
    rng = np.random.default_rng(seed + 1)
    img = img + (rng.random((H, W, 1), np.float32) - 0.5) * (2.2 / 255)
    return np.clip(img, 0, 1)


PALETTES = {
    "szczyty-light": dict(
        sky=[(0.0, "#2F55D8"), (0.32, "#7F92F0"), (0.62, "#E6B4D2"), (0.86, "#FFD3BE"), (1.0, "#FFE6D2")],
        sun=(0.70, 0.43), sun_r=0.020, disc="#FFF6E8", glow="#FFD7B0", glow_r=0.20, glow_a=0.85,
        cloud="#F4D6EC", cloud_a=0.45,
        haze="#F2C6D2", shadow="#2B2C7E", lit="#8E7FE0", deep="#2A2770",
        snow_shadow="#A5B2EE", snow_lit="#FFF2EA", snow_a=0.95, rim_a=0.85, fog_a=0.42, fog_white=0.35),
    "szczyty-dark": dict(
        sky=[(0.0, "#03061A"), (0.35, "#0B1544"), (0.70, "#2A2470"), (1.0, "#4A3184")],
        sun=(0.72, 0.21), sun_r=0.016, disc="#F4F6FF", glow="#9FB2FF", glow_r=0.12, glow_a=0.55,
        cloud="#2C2E6E", cloud_a=0.35, stars=True,
        haze="#3A3486", shadow="#080B2E", lit="#3A4FA8", deep="#060824",
        snow_shadow="#3B4A8E", snow_lit="#C9D6FF", snow_a=0.85, rim_a=0.55, fog_a=0.35, fog_white=0.08),
    "jezioro-light": dict(
        sky=[(0.0, "#3E6FE0"), (0.30, "#86A7F2"), (0.58, "#F7C3B0"), (0.82, "#FFC892"), (1.0, "#FFE0B6")],
        sun=(0.64, 0.52), sun_r=0.024, disc="#FFF7E0", glow="#FFC98A", glow_r=0.24, glow_a=0.95,
        cloud="#FFE2D2", cloud_a=0.50,
        haze="#F6C4A8", shadow="#33306E", lit="#C07FA8", deep="#2C2558",
        snow_shadow="#C7B4E2", snow_lit="#FFF0DC", snow_a=0.90, rim_a=0.95, fog_a=0.40, fog_white=0.30,
        water="#3A4C9C", sparkle=1.4),
    "jezioro-dark": dict(
        sky=[(0.0, "#0A0B26"), (0.30, "#1E1C58"), (0.60, "#6A3478"), (0.85, "#C2566A"), (1.0, "#E58460")],
        sun=(0.64, 0.60), sun_r=0.0, disc="#FFB070", glow="#FF8E62", glow_r=0.20, glow_a=0.75,
        cloud="#5A2A6A", cloud_a=0.45,
        haze="#7A3A7A", shadow="#120E36", lit="#4A3E8A", deep="#0C0A28",
        snow_shadow="#4A3E86", snow_lit="#FFC6B0", snow_a=0.75, rim_a=0.9, fog_a=0.30, fog_white=0.05,
        water="#14123E", sparkle=1.0),
}


def main():
    OUT.mkdir(exist_ok=True)
    for name, p in PALETTES.items():
        lake = name.startswith("jezioro")
        img = render(p, lake=lake, seed=11 if lake else 7)
        im = Image.fromarray((img * 255 + 0.5).astype(np.uint8))
        im.save(OUT / f"{name}.jpg", quality=90, optimize=True, progressive=True)
        im.resize((320, 200), Image.LANCZOS).save(OUT / f"{name}-thumb.jpg", quality=88)
        print("ok", name)


if __name__ == "__main__":
    main()

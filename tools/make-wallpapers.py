#!/usr/bin/env python3
"""Tapety Aster: matowe, spokojne plansze bez efektów szkła, w wersji jasnej i ciemnej.
Uruchomienie: python3 tools/make-wallpapers.py data/wallpapers (wymaga numpy i Pillow)."""
import sys
import numpy as np
from PIL import Image

W, H = 3840, 2400
OUT = sys.argv[1] if len(sys.argv) > 1 else "data/wallpapers"


def mix(a, b, t):
    return a + (b - a) * t


def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], dtype=float)


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def wave(x, rng, base, amp):
    """Łagodna krzywa z kilku sinusów, bez powtarzalnego rytmu."""
    y = np.full_like(x, base, dtype=float)
    for k in range(5):
        f = rng.uniform(0.6, 2.6) * (1 + k * 0.7)
        y += amp / (1 + k * 1.1) * np.sin(x * f * 2 * np.pi + rng.uniform(0, 6.3))
    return y


def layers(top, bottom, count, seed, amp):
    """Warstwy jak wydmy: każda ma własny kolor, jasną grań i miękki cień przy dolnej krawędzi sąsiada."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    x, y = xx / W, yy / H
    img = np.zeros((H, W, 3), np.float32)
    sky = smooth(y / 0.75)[..., None]
    img[:] = mix(top, mix(top, bottom, 0.35), sky)
    for i in range(count):
        p = (i + 1) / count
        base = 0.28 + 0.74 * p ** 1.25
        edge = wave(x[0], rng, base, amp * (1.2 - 0.4 * p))
        d = (y - edge[None, :])
        mask = np.clip(d * H / 2.5 + 0.5, 0, 1)[..., None]
        color = mix(mix(top, bottom, 0.3), bottom, p)
        shade = np.exp(-np.clip(d, 0, None) / 0.09)[..., None]           # grań jaśnieje
        slope = (0.5 + 0.5 * np.sin((x * 1.5 + y * 2.0 + i) * np.pi))[..., None]
        tone = color * (0.97 + 0.03 * slope) + (top - color) * 0.16 * shade
        img = img * (1 - mask) + tone * mask
    return img


def bands(colors, seed):
    """Szerokie, ukośne pasma koloru o miękkich przejściach."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    x, y = xx / W, yy / H
    t = (x * 0.62 + y * 0.78) / 1.4
    t = t + 0.035 * np.sin(x * 5 + rng.uniform(0, 6)) + 0.02 * np.sin(y * 7 + rng.uniform(0, 6))
    stops = np.linspace(0, 1, len(colors))
    img = np.stack([np.interp(t, stops, [c[k] for c in colors]) for k in range(3)], -1)
    return img.astype(np.float32)


def paper(base, line, seed):
    """Papier z cienkimi poziomicami."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    x, y = xx / W, yy / H
    f = np.zeros_like(x)
    for k in range(6):
        a, b = rng.uniform(1, 4, 2) * (1 + k * 0.5)
        f += np.sin(x * a * 3 + rng.uniform(0, 6)) * np.cos(y * b * 2 + rng.uniform(0, 6)) / (1 + k)
    v = np.abs(((f * 7) % 1) - 0.5)
    g = np.hypot(*np.gradient(f * 7)) + 1e-5
    ink = np.clip(1.25 - v / (g * 2.2), 0, 1)[..., None] * 0.55
    return (base * (1 - ink) + line * ink).astype(np.float32)


def silk(blobs, base, seed, folds=2.6, depth=0.20, sheen=0.10):
    """Jedwab: miękkie plamy koloru i szerokie, płynne fałdy z delikatnym światłem na grzbietach."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    x, y = xx / W, yy / H
    img = np.zeros((H, W, 3), np.float32) + base
    for (cx, cy, r, color) in blobs:
        w = np.exp(-(((x - cx) * 1.6) ** 2 + (y - cy) ** 2) / (2 * r * r))[..., None]
        img = img * (1 - w) + color * w
    f = (y * 0.9 + x * 0.55
         + 0.10 * np.sin(x * 3.1 + rng.uniform(0, 6))
         + 0.05 * np.sin(x * 6.3 + y * 2.2 + rng.uniform(0, 6))
         + 0.03 * np.sin(y * 9.0 + rng.uniform(0, 6)))
    wave = np.sin(f * folds * 2 * np.pi)
    shade = (wave * 0.5 + 0.5)[..., None]
    crest = np.clip((wave - 0.55) / 0.45, 0, 1)[..., None] ** 3
    img = img * (1 - depth / 2 + depth * shade) + (255 - img) * sheen * crest
    return img


def save(img, name, seed):
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, 1.1, (H, W, 1)).astype(np.float32)        # drobne ziarno: mat zamiast połysku i bez pasków
    out = np.clip(img + grain, 0, 255).astype(np.uint8)
    pic = Image.fromarray(out)
    pic.save(f"{OUT}/{name}.jpg", quality=88, optimize=True, progressive=True)
    pic.resize((480, 300), Image.LANCZOS).save(f"{OUT}/{name}-thumb.jpg", quality=85)


save(silk([(0.15, 0.2, 0.32, rgb("#F7C9B6")), (0.8, 0.25, 0.30, rgb("#C7D3FF")), (0.55, 0.85, 0.36, rgb("#E6C8F2")), (0.95, 0.9, 0.25, rgb("#B9E2F2"))], rgb("#F4EEF3"), 51), "swit-light", 9)
save(silk([(0.15, 0.25, 0.30, rgb("#5B2E8C")), (0.85, 0.2, 0.28, rgb("#1F3A8F")), (0.55, 0.85, 0.36, rgb("#7A2C6B")), (0.95, 0.9, 0.25, rgb("#0F5A73"))], rgb("#0E0F1F"), 51, depth=0.42, sheen=0.025), "swit-dark", 10)
save(layers(rgb("#E9E6DF"), rgb("#7C8496"), 6, 11, 0.05), "grzbiety-light", 1)
save(layers(rgb("#3A3E4C"), rgb("#101217"), 6, 11, 0.05), "grzbiety-dark", 2)
save(layers(rgb("#E6ECF1"), rgb("#5F7F92"), 5, 23, 0.035), "mgla-light", 3)
save(layers(rgb("#2B3A44"), rgb("#0D1216"), 5, 23, 0.035), "mgla-dark", 4)
save(bands([rgb("#EFEBE3"), rgb("#D9D3C8"), rgb("#BFC3CC"), rgb("#9AA5B8")], 31), "pasma-light", 5)
save(bands([rgb("#2C2F38"), rgb("#1F2228"), rgb("#17191E"), rgb("#101115")], 31), "pasma-dark", 6)
save(paper(rgb("#F0EEE8"), rgb("#CFCBC1"), 41), "papier-light", 7)
save(paper(rgb("#191A1E"), rgb("#34363E"), 41), "papier-dark", 8)

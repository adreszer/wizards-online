"""Draws the castle's woven carpets (set dressing 2.0): corridor runners and large hall
rugs, as tileable albedo textures in assets/textures/carpets/. A runner tile is one
repeat of the pattern (it tiles along the runner's length); a hall rug is one whole
carpet. Everything is drawn from vector shapes and seeded noise, so it can be remade
after a palette change. Needs numpy and Pillow (macOS: /usr/bin/python3).

  /usr/bin/python3 tools/make_carpets.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "carpets")

# field, border band, gold, dark outline
PALETTES = {
    "crimson": ("6e1a17", "2a1d3a", "c9a14a", "1c1010"),
    "blue": ("1f2f5c", "5a1a1a", "c9a14a", "0f1424"),
    "green": ("1f4a2e", "3a2416", "c9a14a", "0e1a12"),
}


def hexc(s):
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def weave(h, w, seed):
    """Fine woven texture: warp and weft ridges plus soft mottling, around 1.0."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    ridges = 0.04 * np.sin(xs * np.pi / 2.0) * np.sin(ys * np.pi / 2.0)
    mottle = rng.normal(0, 1, (h // 16 + 2, w // 16 + 2)).astype(np.float32)
    mottle = np.asarray(Image.fromarray(mottle).resize((w, h), Image.BICUBIC))
    # Wrap the mottling so the tile repeats without a seam.
    mottle = (mottle + np.roll(mottle, h // 2, axis=0)) * 0.5
    grain = rng.normal(0, 0.025, (h, w)).astype(np.float32)
    return 1.0 + ridges + 0.05 * mottle + grain


def lozenge(u, v, cu, cv, ru, rv):
    return np.abs(u - cu) / ru + np.abs(v - cv) / rv


def runner(name, pal, w=512, h=512):
    """One repeat of a runner: u across (0..1), v along; the border runs down both sides."""
    field, band, gold, dark = (hexc(c) for c in pal)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xs + 0.5) / w
    v = (ys + 0.5) / h
    rgb = np.zeros((h, w, 3), np.float32) + field
    edge = np.minimum(u, 1 - u)
    # Outer band, gold rule, border band with a running chevron, gold rule.
    rgb[edge < 0.16] = band
    chevron = np.abs(((v * 8.0) % 1.0) - 0.5) * 0.12 + 0.045
    rgb[(edge > chevron) & (edge < chevron + 0.02)] = gold
    rgb[(edge > 0.16) & (edge < 0.175)] = gold
    rgb[edge < 0.012] = dark
    # A medallion in the field: a gold lozenge, a dark one inside, a gold heart.
    d = lozenge(u, v, 0.5, 0.5, 0.26, 0.42)
    rgb[(d > 0.92) & (d < 1.0)] = gold
    rgb[(d < 0.92) & (d > 0.62)] = band * 0.9
    rgb[(d < 0.62) & (d > 0.55)] = gold
    rgb[d < 0.2] = gold
    # Corner sprigs between medallions.
    for cv in (0.0, 1.0):
        dd = lozenge(u, v, 0.5, cv, 0.08, 0.06)
        rgb[dd < 1.0] = gold
    rgb *= weave(h, w, sum(name.encode()) % 1000)[..., None]
    save(name, rgb)


def hall_rug(name, pal, w=1024, h=1536):
    """A whole hall carpet (2:3): border, a field of small motifs, a central medallion."""
    field, band, gold, dark = (hexc(c) for c in pal)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xs + 0.5) / w
    v = (ys + 0.5) / h
    rgb = np.zeros((h, w, 3), np.float32) + field
    eu = np.minimum(u, 1 - u)
    ev = np.minimum(v, 1 - v) * (h / w)
    edge = np.minimum(eu, ev)
    rgb[edge < 0.11] = band
    rgb[(edge > 0.095) & (edge < 0.105)] = gold
    rgb[(edge > 0.03) & (edge < 0.038)] = gold
    rgb[edge < 0.008] = dark
    inner = edge > 0.11
    # Field motifs on a lattice.
    fu = (u * 8.0) % 1.0
    fv = (v * 12.0) % 1.0
    small = lozenge(fu, fv, 0.5, 0.5, 0.22, 0.22)
    rgb[inner & (small < 0.35)] = gold * 0.85
    rgb[inner & (small > 0.85) & (small < 1.0)] = band * 0.8
    d = lozenge(u, v, 0.5, 0.5, 0.3, 0.28)
    rgb[(d < 1.0) & (d > 0.94)] = gold
    rgb[(d < 0.94)] = band * 0.95
    rgb[(d < 0.7) & (d > 0.64)] = gold
    rgb[d < 0.25] = gold
    rgb *= weave(h, w, sum(name.encode()) % 1000 + 7)[..., None]
    save(name, rgb)


def save(name, rgb):
    img = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(img, "RGB").save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name)


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, pal in PALETTES.items():
        runner("runner_" + key, pal)
        hall_rug("hall_rug_" + key, pal)


if __name__ == "__main__":
    main()

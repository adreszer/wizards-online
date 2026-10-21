"""Makes the UI art kit (docs/ui.md, Milestone 66): the nine-slice frames, buttons,
fields, tabs, ribbons, slot rings, separators and the wax-seal close control of both
material families, drawn from CC0 textures and vector shapes so every edge sits on an
exact pixel and the art can be remade after a palette change.

  python3 tools/make_ui_frames.py --fetch      # first time: download the textures
  python3 tools/make_ui_frames.py              # writes assets/ui/frames/

Sources (CC0, downloaded into .godot/ui_src/, not committed): ambientCG Paper001 (fibre)
and Paper003 (mottling) for the parchment, Poly Haven black_oak_veneer for the oak
grain. Colours come from the palette below, which mirrors ui/theme/ui_tokens.gd.

Every piece is drawn at 4x and saved at 1x (name.png) and 2x (name@2x.png); UiFrames
swaps in the 2x copies when the interface is drawn larger than 1:1. frames.json lists
each piece's nine-slice margins (1x px), the shadow drawn outside the control (its
expand margin) and whether the middle tiles; tools/build_ui_theme.gd reads it.

The middle and edges of a tiling piece repeat with the piece's period: every texture
and noise used is periodic over it, sampled from the start of the middle, so a frame
of any size shows no seam.
"""
import argparse
import io
import json
import math
import os
import urllib.request
import zipfile

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "frames")
SRC = os.path.join(ROOT, ".godot", "ui_src")
R = 4   # supersampling: pixels per 1x pixel while drawing

SOURCES = {
    "paper_fibre": ("https://ambientcg.com/get?file=Paper001_1K-JPG.zip", "Paper001_1K-JPG_Color.jpg"),
    "paper_mottle": ("https://ambientcg.com/get?file=Paper003_1K-JPG.zip", "Paper003_1K-JPG_Color.jpg"),
    "oak": ("polyhaven:black_oak_veneer", None),
}


def hexc(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


# Palette (ui_tokens.gd).
OAK = hexc("1e1712")
OAK_RAISED = hexc("2c221a")
OAK_HOVER = hexc("3a2c20")
OAK_PRESSED = hexc("140f0b")
OAK_INSET = hexc("120d0a")
OAK_LINE = hexc("4a3a2a")
BRASS = hexc("c8a35a")
BRASS_BRIGHT = hexc("e8c77a")
BRASS_DIM = hexc("7a6240")
CANDLE = hexc("f2e6cc")
PARCHMENT = hexc("e9ddbf")
PARCHMENT_DEEP = hexc("d8c7a0")
PARCHMENT_EDGE = hexc("73502b")
INK = hexc("2b1d10")
INK_SOFT = hexc("5c4630")
RUBRIC = hexc("8a2e1c")
BURNT = hexc("9a7444")
WAX = hexc("9c2a1a")
WAX_DARK = hexc("4a120a")
BLACK = np.zeros(3, dtype=np.float32)

MANIFEST = {}


# --- Sources ---

def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "arcane-academy-tools/1.0"})
    with urllib.request.urlopen(req) as r:
        return r.read()


def fetch():
    os.makedirs(SRC, exist_ok=True)
    for name, (url, member) in SOURCES.items():
        dest = os.path.join(SRC, name + ".jpg")
        if os.path.exists(dest):
            continue
        if url.startswith("polyhaven:"):
            asset = url.split(":", 1)[1]
            files = json.loads(_get("https://api.polyhaven.com/files/" + asset))
            with open(dest, "wb") as f:
                f.write(_get(files["Diffuse"]["1k"]["jpg"]["url"]))
        else:
            with zipfile.ZipFile(io.BytesIO(_get(url))) as z, open(dest, "wb") as f:
                f.write(z.read(member))
        print("fetched", dest)


_detail_cache = {}


def detail(name, period, axis_scale=(1.0, 1.0)):
    """A source texture's luminance as a zero-mean, unit-spread array that tiles with
    `period` 1x px (period * R pixels), wrapping at the borders while resizing."""
    key = (name, period, axis_scale)
    if key in _detail_cache:
        return _detail_cache[key]
    im = Image.open(os.path.join(SRC, name + ".jpg")).convert("L")
    a = np.asarray(im, dtype=np.float32) / 255.0
    pad = 32
    a = np.pad(a, pad, mode="wrap")
    size = period * R
    big = (int(round(size * axis_scale[0] * a.shape[1] / (a.shape[1] - 2 * pad))),
           int(round(size * axis_scale[1] * a.shape[0] / (a.shape[0] - 2 * pad))))
    b = np.asarray(Image.fromarray(a).resize(big, Image.LANCZOS), dtype=np.float32)
    px = (big[0] - int(size * axis_scale[0])) // 2
    py = (big[1] - int(size * axis_scale[1])) // 2
    b = b[py:py + int(size * axis_scale[1]), px:px + int(size * axis_scale[0])]
    # Scaled tiles are cropped back to one period, so they still wrap.
    b = np.asarray(Image.fromarray(b).resize((size, size), Image.LANCZOS), dtype=np.float32)
    b = (b - b.mean()) / (b.std() + 1e-6)
    _detail_cache[key] = b
    return b


# --- Drawing ---

class Canvas:
    """A piece being drawn: w x h at 1x (shapes are given in 1x px), m the nine-slice
    margin, c the tiling period of the middle."""

    def __init__(self, w, h, m=(0, 0, 0, 0), c=(1, 1)):
        self.w, self.h, self.m, self.c = w, h, m, c
        ys, xs = np.mgrid[0:h * R, 0:w * R].astype(np.float32)
        self.X = (xs + 0.5) / R
        self.Y = (ys + 0.5) / R
        self.rgb = np.zeros((h * R, w * R, 3), dtype=np.float32)
        self.a = np.zeros((h * R, w * R), dtype=np.float32)

    def tile(self, arr):
        """Samples a periodic array (period self.c, starting at the middle's corner)."""
        ph, pw = arr.shape
        ix = (np.floor((self.X - self.m[0]) * R).astype(np.int64)) % pw
        iy = (np.floor((self.Y - self.m[1]) * R).astype(np.int64)) % ph
        return arr[iy, ix]

    def along(self, fn_x, fn_y):
        """Per-pixel values of two periodic 1D functions: along x (top/bottom edges)
        and along y (left/right edges)."""
        return fn_x((self.X - self.m[0]) % self.c[0]), fn_y((self.Y - self.m[1]) % self.c[1])

    def over(self, rgb, alpha):
        alpha = np.clip(alpha, 0, 1)[..., None]
        out_a = alpha[..., 0] + self.a * (1 - alpha[..., 0])
        num = rgb * alpha + self.rgb * self.a[..., None] * (1 - alpha)
        self.rgb = np.where(out_a[..., None] > 1e-6, num / np.maximum(out_a[..., None], 1e-6), self.rgb)
        self.a = out_a

    def save(self, name, tile=True, shadow=(0, 0, 0, 0), content=None):
        img = np.dstack([np.clip(self.rgb, 0, 1), np.clip(self.a, 0, 1)])
        img = (img * 255 + 0.5).astype(np.uint8)
        big = Image.fromarray(img, "RGBA")
        # Downsample in premultiplied alpha so edges do not darken.
        pre = big.convert("RGBa")
        for scale, suffix in ((2, "@2x"), (1, "")):
            small = pre.resize((self.w * scale, self.h * scale), Image.BOX).convert("RGBA")
            small.save(os.path.join(OUT, name + suffix + ".png"), optimize=True)
        MANIFEST[name] = {"size": [self.w, self.h], "margin": list(self.m), "shadow": list(shadow), "tile": tile}
        if content is not None:
            MANIFEST[name]["content"] = list(content)


def cov(sd):
    """Coverage from a signed distance in 1x px (negative inside), antialiased at 4x."""
    return np.clip(0.5 - sd * R, 0, 1)


def sd_rrect(X, Y, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(X - cx) - hx, np.abs(Y - cy) - hy
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def sd_circle(X, Y, cx, cy, r):
    return np.hypot(X - cx, Y - cy) - r


def sd_segment(X, Y, ax, ay, bx, by, r):
    px, py = X - ax, Y - ay
    dx, dy = bx - ax, by - ay
    h = np.clip((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(px - dx * h, py - dy * h) - r


def edge_dist(cv, inset=0.0):
    """Distance from each pixel to the nearest outer edge of the canvas, less `inset`."""
    return np.minimum(np.minimum(cv.X, cv.w - cv.X), np.minimum(cv.Y, cv.h - cv.Y)) - inset


def lerp(a, b, t):
    t = np.asarray(t, dtype=np.float32)
    if t.ndim:
        t = t[..., None]
    return a + (b - a) * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def noise1d(period, cells, seed, octaves=3):
    """A smooth periodic function over [0, period) with values in about [-1, 1]."""
    rng = np.random.default_rng(seed)
    layers = [(rng.uniform(-1, 1, cells * 2 ** o), 0.5 ** o) for o in range(octaves)]

    def fn(t):
        total = np.zeros_like(t)
        for vals, amp in layers:
            n = len(vals)
            u = t / period * n
            i0 = np.floor(u).astype(np.int64)
            f = u - i0
            f = f * f * (3 - 2 * f)
            total += amp * (vals[i0 % n] * (1 - f) + vals[(i0 + 1) % n] * f)
        return total / sum(a for _, a in layers)
    return fn


def blur_alpha(cv, alpha, radius, dy):
    """A soft shadow from `alpha`: blurred by `radius` 1x px and moved down `dy`."""
    im = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L")
    im = im.filter(ImageFilter.GaussianBlur(radius * R))
    s = np.asarray(im, dtype=np.float32) / 255.0
    shift = int(round(dy * R))
    if shift:
        s = np.concatenate([np.zeros((shift, s.shape[1]), np.float32), s[:-shift]], axis=0)
    return s


def bevel(sd_fn, X, Y, width):
    """Light from the top left on a shape's rim: +1 lit, -1 shaded, 0 in the flat."""
    e = 0.35
    gx = (sd_fn(X + e, Y) - sd_fn(X - e, Y)) / (2 * e)
    gy = (sd_fn(X, Y + e) - sd_fn(X, Y - e)) / (2 * e)
    lit = -(gx * 0.7071 + gy * 0.7071)
    weight = np.clip(1 + sd_fn(X, Y) / width, 0, 1)
    return lit * weight


def brass(cv, sd_fn, base=BRASS, width=1.6, grain=0.05):
    """A brass fill for a shape: bevelled rim, faint brushed grain."""
    b = bevel(sd_fn, cv.X, cv.Y, width)
    g = cv.tile(detail("oak", 32, (2.0, 0.25))) * grain
    rgb = lerp(base, BRASS_BRIGHT, np.clip(b, 0, 1) * 0.9)
    rgb = lerp(rgb, BRASS_DIM * 0.55, np.clip(-b, 0, 1) * 0.8)
    return np.clip(rgb * (1 + g)[..., None], 0, 1)


# --- Parchment ---

def paper_rgb(cv, period, mottle=1.0):
    fibre = cv.tile(detail("paper_fibre", period))
    blot = cv.tile(detail("paper_mottle", period))
    t = np.clip(0.45 + 0.15 * blot * mottle, 0, 1)
    rgb = lerp(PARCHMENT, PARCHMENT_DEEP, t)
    return np.clip(rgb * (1 + 0.025 * fibre)[..., None], 0, 1)


def parchment_window():
    P, M, C = 12, 40, 256   # shadow pad, nine-slice margin, period
    cv = Canvas(2 * M + C, 2 * M + C, (M, M, M, M), (C, C))
    nx, ny = cv.along(noise1d(C, 24, 11), noise1d(C, 24, 12))
    nx2, ny2 = cv.along(noise1d(C, 24, 13), noise1d(C, 24, 14))
    # Deckled edge: each side's cut wanders by a pixel and a half.
    sides = [cv.Y - (P + 1.5 + 1.4 * nx), (cv.h - cv.Y) - (P + 1.5 + 1.4 * nx2),
             cv.X - (P + 1.5 + 1.4 * ny), (cv.w - cv.X) - (P + 1.5 + 1.4 * ny2)]
    d = np.minimum.reduce(sides)
    paper_a = np.clip(d * R * 0.5 + 0.5, 0, 1)
    shadow = blur_alpha(cv, paper_a, 5, 3) * 0.55
    cv.over(BLACK, shadow)
    rgb = paper_rgb(cv, C)
    # Aged rim: browner and darker toward the edge, unevenly.
    blot = cv.tile(detail("paper_mottle", C // 2))
    age = np.exp(-np.maximum(d, 0) / 9.0) * (0.75 + 0.25 * blot) + np.exp(-np.maximum(d, 0) / 2.2) * 0.5
    rgb = lerp(rgb, BURNT, np.clip(age * 0.55, 0, 1))
    rgb = lerp(rgb, PARCHMENT_EDGE * 0.8, np.clip(np.exp(-np.maximum(d, 0) / 1.2) * 0.7, 0, 1))
    cv.over(rgb, paper_a)
    # Hand-ruled double frame in faded ink, with a small diamond at each corner.
    inner = edge_dist(cv, P + 10)
    wob = 0.25 * (nx + ny)
    rule = cov(np.abs(inner - wob) - 0.45) * 0.42 + cov(np.abs(inner - 3.2 - wob) - 0.3) * 0.22
    corner_band = np.zeros_like(rule)
    for cx in (P + 10 + 1.6, cv.w - P - 10 - 1.6):
        for cy in (P + 10 + 1.6, cv.h - P - 10 - 1.6):
            dia = (np.abs(cv.X - cx) + np.abs(cv.Y - cy)) - 4.2
            corner_band = np.maximum(corner_band, cov(dia))
    cv.over(lerp(INK_SOFT, RUBRIC, corner_band), np.maximum(rule, corner_band * 0.75) * paper_a)
    cv.save("parchment_window", shadow=(P, P, P, P))


def parchment_panel():
    """A plain paper sheet for popups and small paper boxes."""
    P, M, C = 8, 16, 64
    cv = Canvas(2 * M + C, 2 * M + C, (M, M, M, M), (C, C))
    sd = lambda X, Y: sd_rrect(X, Y, P, P, cv.w - P, cv.h - P, 2)
    a = cov(sd(cv.X, cv.Y))
    cv.over(BLACK, blur_alpha(cv, a, 3, 2) * 0.45)
    d = -sd(cv.X, cv.Y)
    rgb = paper_rgb(cv, C, 0.6)
    rgb = lerp(rgb, BURNT, np.clip(np.exp(-np.maximum(d, 0) / 3.0) * 0.45, 0, 1))
    cv.over(rgb, a)
    cv.over(INK_SOFT, cov(np.abs(d - 0.5) - 0.5) * 0.45)
    cv.save("parchment_panel", shadow=(P, P, P, P))


def parchment_button(state):
    P, M, C = 2, 8, 48
    cv = Canvas(2 * M + C, 2 * M + 24, (M, M, M, M), (C, 24))
    nx, ny = cv.along(noise1d(C, 6, 21), noise1d(24, 3, 22))
    sd = lambda X, Y: sd_rrect(X, Y, P, P, cv.w - P, cv.h - P, 2.5)
    s = sd(cv.X, cv.Y)
    a = cov(s)
    if state != "pressed":
        cv.over(BLACK, cov(sd(cv.X, cv.Y - 1.0)) * (0.18 if state != "disabled" else 0.06))
    rgb = paper_rgb(cv, C, 0.5)
    tint = {"normal": 0.35, "hover": 0.55, "pressed": 0.85, "disabled": 0.15}[state]
    rgb = lerp(rgb, PARCHMENT_DEEP * 0.92, tint)
    if state == "pressed":
        rgb = lerp(rgb, INK, np.clip(1 - (cv.Y - P) / 4, 0, 1) * 0.18)
    elif state != "disabled":
        rgb = lerp(rgb, PARCHMENT * 1.04, np.clip(1 - (cv.Y - P) / 3, 0, 1) * 0.35)
    alpha = 0.55 if state == "disabled" else 1.0
    cv.over(np.clip(rgb, 0, 1), a * alpha)
    line = {"normal": INK_SOFT, "hover": RUBRIC, "pressed": INK, "disabled": INK_SOFT}[state]
    la = {"normal": 0.7, "hover": 0.9, "pressed": 0.95, "disabled": 0.3}[state]
    cv.over(line, cov(np.abs(s + 0.6 + 0.15 * (nx + ny)) - 0.55) * la)
    cv.save("parchment_button_" + state, shadow=(0, 0, 0, 0))


def parchment_field(state):
    M, C = 6, 32
    cv = Canvas(2 * M + C, 2 * M + 16, (M, M, M, M), (C, 16))
    s = sd_rrect(cv.X, cv.Y, 0.5, 0.5, cv.w - 0.5, cv.h - 0.5, 2)
    cv.over(PARCHMENT_EDGE, cov(s) * (0.07 if state != "focus" else 0.1))
    nx, _ = cv.along(noise1d(C, 4, 31), noise1d(16, 2, 32))
    y = cv.h - 1.5 + 0.2 * nx
    width = 0.55 if state != "focus" else 0.95
    col = RUBRIC if state == "focus" else INK_SOFT
    cv.over(col, cov(np.abs(cv.Y - y) - width) * (0.85 if state != "read_only" else 0.35))
    cv.save("parchment_field_" + state, shadow=(0, 0, 0, 0))


def parchment_tab(state):
    M, C = 10, 32
    cv = Canvas(2 * M + C, 30, (M, 8, M, 4), (C, 18))
    top = 2.0 if state == "selected" else 5.0
    # An index tab: slanted sides, rounded top corners, open at the bottom.
    slant = 3.0
    hx = cv.w / 2 - slant * (cv.h - cv.Y) / cv.h - 1
    sd = np.maximum(np.maximum(np.abs(cv.X - cv.w / 2) - hx, top - cv.Y), cv.Y - (cv.h + 2))
    a = cov(sd)
    rgb = paper_rgb(cv, C, 0.5)
    if state == "unselected":
        rgb = lerp(rgb, PARCHMENT_DEEP * 0.88, 0.75)
    elif state == "hovered":
        rgb = lerp(rgb, PARCHMENT_DEEP, 0.4)
    cv.over(rgb, a)
    edge = cov(np.abs(sd + 0.6) - 0.5) * np.clip(cv.h - 0.5 - cv.Y, 0, 1)
    cv.over(RUBRIC if state == "selected" else INK_SOFT, edge * (0.85 if state == "selected" else 0.55))
    cv.save("parchment_tab_" + state, shadow=(0, 0, 0, 0))


def ink_separator():
    M, C = 48, 32
    cv = Canvas(2 * M + C, 9, (M, 0, M, 0), (C, 9))
    x = cv.X
    taper = np.minimum(smooth(2, M, x), smooth(2, M, cv.w - x))
    width = 0.15 + 0.6 * taper
    cv.over(INK_SOFT, cov(np.abs(cv.Y - 4.5) - width) * (0.35 + 0.45 * taper))
    for cx in (2.5, cv.w - 2.5):
        cv.over(INK_SOFT, cov(sd_circle(cv.X, cv.Y, cx, 4.5, 1.3)) * 0.7)
    cv.save("ink_separator", shadow=(0, 0, 0, 0))


def ribbon():
    """A rubric cloth ribbon with notched ends and gilt stitching (window titles,
    area banners)."""
    M, C, H = 30, 64, 48
    cv = Canvas(2 * M + C, H, (M, 0, M, 0), (C, H))
    top, bot = 5.0, H - 7.0
    mid = (top + bot) / 2
    notch = 9.0
    # Body with a V notch cut into each end.
    vx = np.minimum(cv.X, cv.w - cv.X)
    cut = notch * (1 - np.abs(cv.Y - mid) / ((bot - top) / 2))
    sd = np.maximum.reduce([top - cv.Y, cv.Y - bot, 1.0 + cut - vx])
    a = cov(sd)
    cv.over(BLACK, blur_alpha(cv, a, 2.5, 2.5) * 0.5)
    weave = cv.tile(detail("paper_fibre", C, (1.0, 1.0))) * 0.05
    rows = np.sin((cv.Y - top) / (bot - top) * math.pi)
    rgb = lerp(RUBRIC * 0.62, RUBRIC * 1.12, rows * 0.8 + 0.1)
    rgb = np.clip(rgb * (1 + weave)[..., None], 0, 1)
    cv.over(rgb, a)
    for y in (top + 3.2, bot - 3.2):
        stitch = (np.floor((cv.X - M) / 3.0) % 2 == 0)
        st = cov(np.abs(cv.Y - y) - 0.42) * stitch * np.clip(vx - notch - 5, 0, 1)
        cv.over(BRASS, st * 0.85)
    cv.save("ribbon", shadow=(0, 0, 0, 0), content=(M + 6, 6, M + 6, 9))


def wax_seal(state):
    S = 48
    cv = Canvas(S, S)
    c = S / 2
    rad = 16.5 if state != "pressed" else 15.8
    ang = np.arctan2(cv.Y - c, cv.X - c)
    t = (ang + math.pi) / (2 * math.pi) * 64
    blob = noise1d(64, 7, 41)(t) * 1.3 + noise1d(64, 18, 42)(t) * 0.5
    sd_fn = lambda X, Y: np.hypot(X - c, Y - c) - (rad + blob)
    s = sd_fn(cv.X, cv.Y)
    a = cov(s)
    cv.over(BLACK, blur_alpha(cv, a, 2.2, 1.8 if state != "pressed" else 0.8) * 0.6)
    r = np.hypot(cv.X - c, cv.Y - c)
    light = np.clip(1 - np.hypot(cv.X - (c - 5), cv.Y - (c - 6)) / (rad * 1.6), 0, 1)
    base = WAX * (1.12 if state == "hover" else 0.92 if state == "pressed" else 1.0)
    rgb = lerp(WAX_DARK, base, 0.35 + 0.65 * light)
    b = bevel(sd_fn, cv.X, cv.Y, 3.0)
    rgb = lerp(rgb, base * 1.35, np.clip(b, 0, 1) * 0.5)
    rgb = lerp(rgb, WAX_DARK * 0.7, np.clip(-b, 0, 1) * 0.6)
    # The impressed disc: a groove ring, then a cross pressed into the wax.
    ring = r - 11.0
    rgb = lerp(rgb, WAX_DARK * 0.8, cov(np.abs(ring) - 0.7) * 0.75)
    rgb = lerp(rgb, base * 1.4, cov(np.abs(ring - 1.3) - 0.45) * 0.35 * np.clip(-(cv.X + cv.Y - 2 * c) / 8, 0, 1))
    k = 5.0
    cross = np.minimum(sd_segment(cv.X, cv.Y, c - k, c - k, c + k, c + k, 1.35),
                       sd_segment(cv.X, cv.Y, c - k, c + k, c + k, c - k, 1.35))
    cross_hi = np.minimum(sd_segment(cv.X, cv.Y, c - k + 0.7, c - k + 0.7, c + k + 0.7, c + k + 0.7, 1.35),
                          sd_segment(cv.X, cv.Y, c - k + 0.7, c + k + 0.7, c + k + 0.7, c - k + 0.7, 1.35))
    rgb = lerp(rgb, base * 1.45, cov(cross_hi) * 0.4)
    rgb = lerp(rgb, WAX_DARK * 0.65, cov(cross) * 0.85)
    gloss = cov(sd_circle(cv.X, cv.Y, c - 6, c - 7, 3.0)) * 0.22 * (1 if state != "pressed" else 0.4)
    rgb = lerp(rgb, CANDLE, gloss)
    cv.over(np.clip(rgb, 0, 1), a)
    cv.save("wax_seal_" + state, tile=False)


# --- Oak & brass ---

def oak_rgb(cv, period, base=OAK, lit=OAK_RAISED, strength=1.0):
    g = cv.tile(detail("oak", period, (1.0, 0.5)))
    t = np.clip(0.5 + 0.28 * g * strength, 0, 1)
    return lerp(base * 0.85, lit * 1.05, t)


def oak_window():
    P, M, C = 14, 34, 128
    cv = Canvas(2 * M + C, 2 * M + C, (M, M, M, M), (C, C))
    x0, y0, x1, y1 = P, P, cv.w - P, cv.h - P
    outer = lambda X, Y: sd_rrect(X, Y, x0, y0, x1, y1, 4)
    so = outer(cv.X, cv.Y)
    a = cov(so)
    cv.over(BLACK, blur_alpha(cv, a, 6, 4) * 0.65)
    d = -so
    rgb = oak_rgb(cv, C)
    # The wood darkens into the frame (inner shadow), lit faintly along the top.
    rgb = lerp(rgb, OAK_PRESSED * 0.6, np.clip(np.exp(-np.maximum(d - 5, 0) / 4.0), 0, 1) * 0.55)
    cv.over(rgb, a)
    # Frame: dark lip, a brass band, a dark inner line.
    cv.over(OAK_PRESSED * 0.5, cov(np.abs(d - 0.5) - 0.6))
    band = lambda X, Y: np.abs(-outer(X, Y) - 2.8) - 1.6
    cv.over(brass(cv, band, BRASS * 0.92, 1.2), cov(band(cv.X, cv.Y)))
    cv.over(OAK_PRESSED * 0.4, cov(np.abs(d - 5.0) - 0.5) * 0.9)
    # Corner brackets with two rivets each.
    for sx in (0, 1):
        for sy in (0, 1):
            def to_local(X, Y, sx=sx, sy=sy):
                return (X if not sx else cv.w - X), (Y if not sy else cv.h - Y)

            def bracket(X, Y, to_local=to_local):
                lx, ly = to_local(X, Y)
                arm_a = sd_rrect(lx, ly, P - 1.0, P - 1.0, P + 18.0, P + 7.0, 1.5)
                arm_b = sd_rrect(lx, ly, P - 1.0, P - 1.0, P + 7.0, P + 18.0, 1.5)
                return np.minimum(arm_a, arm_b)
            sb = bracket(cv.X, cv.Y)
            cv.over(BLACK, cov(bracket(cv.X - 0.8, cv.Y - 1.0) - 0.4) * 0.55)
            cv.over(brass(cv, bracket, BRASS, 1.6), cov(sb))
            lx, ly = to_local(cv.X, cv.Y)
            for rx, ry in ((P + 13.5, P + 3.0), (P + 3.0, P + 13.5), (P + 3.0, P + 3.0)):
                rv = lambda X, Y, rx=rx, ry=ry, tl=to_local: sd_circle(*tl(X, Y), rx, ry, 1.6)
                cv.over(brass(cv, rv, BRASS_BRIGHT, 1.2), cov(rv(cv.X, cv.Y)))
    cv.save("oak_window", shadow=(P, P, P, P))


def oak_panel(name="oak_panel", P=8, border=BRASS_DIM, alpha=0.96):
    M, C = P + 10, 64
    cv = Canvas(2 * M + C, 2 * M + C, (M, M, M, M), (C, C))
    sd = lambda X, Y: sd_rrect(X, Y, P, P, cv.w - P, cv.h - P, 4)
    s = sd(cv.X, cv.Y)
    a = cov(s)
    if P:
        cv.over(BLACK, blur_alpha(cv, a, P * 0.5, P * 0.3) * 0.55)
    d = -s
    rgb = oak_rgb(cv, C)
    rgb = lerp(rgb, OAK_PRESSED * 0.6, np.clip(np.exp(-np.maximum(d - 1, 0) / 3.0), 0, 1) * 0.4)
    cv.over(rgb, a * alpha)
    cv.over(border, cov(np.abs(d - 0.5) - 0.5) * 0.9)
    cv.save(name, shadow=(P, P, P, P))


def oak_button(state):
    P, M, C = 2, 8, 48
    cv = Canvas(2 * M + C, 2 * M + 24, (M, M, M, M), (C, 24))
    sd = lambda X, Y: sd_rrect(X, Y, P, P, cv.w - P, cv.h - P, 3)
    s = sd(cv.X, cv.Y)
    a = cov(s)
    if state != "pressed":
        cv.over(BLACK, cov(sd(cv.X, cv.Y - 1.2)) * 0.5)
    base, lit = {"normal": (OAK_RAISED, OAK_HOVER), "hover": (OAK_HOVER, OAK_HOVER * 1.25),
                 "pressed": (OAK_PRESSED, OAK_RAISED), "disabled": (OAK_RAISED, OAK_RAISED)}[state]
    rgb = oak_rgb(cv, C, base, lit, 0.8)
    d = -s
    if state == "pressed":
        rgb = lerp(rgb, BLACK, np.clip(1 - (cv.Y - P) / 5, 0, 1) * 0.5)
    else:
        rgb = lerp(rgb, CANDLE, np.clip(1 - np.abs(cv.Y - P - 1.5) / 0.9, 0, 1) * (0.12 if state == "hover" else 0.06))
    if state == "hover":
        # Candle glow from the bottom edge.
        rgb = lerp(rgb, BRASS, np.clip(1 - (cv.h - P - cv.Y) / 10, 0, 1) * 0.12)
    cv.over(rgb, a * (0.5 if state == "disabled" else 1.0))
    border = {"normal": OAK_LINE, "hover": BRASS_DIM * 1.2, "pressed": BRASS, "disabled": OAK_LINE}[state]
    cv.over(border, cov(np.abs(d - 0.5) - 0.5) * (0.45 if state == "disabled" else 1.0))
    cv.save("oak_button_" + state, shadow=(0, 0, 0, 0))


def oak_field(state):
    M, C = 6, 32
    cv = Canvas(2 * M + C, 2 * M + 16, (M, M, M, M), (C, 16))
    sd = lambda X, Y: sd_rrect(X, Y, 0.5, 0.5, cv.w - 0.5, cv.h - 0.5, 3)
    s = sd(cv.X, cv.Y)
    a = cov(s)
    rgb = oak_rgb(cv, C, OAK_INSET, OAK_PRESSED, 0.6)
    # Recessed: shadow along the top and left inside.
    rgb = lerp(rgb, BLACK, np.clip(1 - np.minimum(cv.Y, cv.X * 2) / 4, 0, 1) * 0.6)
    cv.over(rgb, a * (0.92 if state != "read_only" else 0.5))
    d = -s
    border = BRASS if state == "focus" else OAK_LINE
    cv.over(border, cov(np.abs(d - 0.5) - 0.5) * (0.5 if state == "read_only" else 1.0))
    cv.over(CANDLE, cov(np.abs(cv.Y - (cv.h - 0.6)) - 0.4) * 0.05)
    cv.save("oak_field_" + state, shadow=(0, 0, 0, 0))


def oak_tab(state):
    M, C = 8, 32
    cv = Canvas(2 * M + C, 30, (M, 8, M, 4), (C, 18))
    top = 1.0 if state == "selected" else 4.0
    sd = lambda X, Y: sd_rrect(X, Y, 0.5, top, cv.w - 0.5, cv.h + 6, 3)
    s = sd(cv.X, cv.Y)
    base = {"selected": OAK_RAISED, "unselected": OAK_PRESSED, "hovered": OAK_HOVER}[state]
    rgb = oak_rgb(cv, C, base, base * 1.2, 0.7)
    if state != "selected":
        rgb = lerp(rgb, BLACK, np.clip(1 - (cv.h - cv.Y) / 6, 0, 1) * 0.4)
    cv.over(rgb, cov(s) * (1.0 if state != "unselected" else 0.85))
    d = -s
    cv.over(OAK_LINE, cov(np.abs(d - 0.5) - 0.5) * np.clip(cv.h - 1 - cv.Y, 0, 1) * 0.9)
    if state != "unselected":
        top_line = cov(np.abs(cv.Y - top - 1.2) - (0.9 if state == "selected" else 0.5)) * cov(s + 1.5)
        cv.over(BRASS if state == "selected" else BRASS_DIM, top_line)
    cv.save("oak_tab_" + state, shadow=(0, 0, 0, 0))


def key_chip():
    M, C = 7, 16
    cv = Canvas(2 * M + C, 2 * M + 10, (M, 5, M, 8), (C, 10 + 2 * M - 13))
    face = lambda X, Y: sd_rrect(X, Y, 1, 1, cv.w - 1, cv.h - 3.5, 3)
    side = lambda X, Y: sd_rrect(X, Y, 1, 2.5, cv.w - 1, cv.h - 1, 3)
    cv.over(BLACK, cov(side(cv.X, cv.Y - 0.8)) * 0.5)
    cv.over(OAK_PRESSED * 0.8, cov(side(cv.X, cv.Y)))
    rgb = lerp(OAK_HOVER * 1.15, OAK_RAISED, np.clip((cv.Y - 1) / (cv.h - 4), 0, 1))
    cv.over(rgb, cov(face(cv.X, cv.Y)))
    cv.over(BRASS_DIM, cov(np.abs(face(cv.X, cv.Y) + 0.5) - 0.5))
    cv.over(CANDLE, cov(np.abs(cv.Y - 2.2) - 0.45) * cov(face(cv.X, cv.Y) + 2.5) * 0.1)
    cv.save("key_chip", shadow=(0, 0, 0, 0), content=(M, 3, M, 6))


def toast():
    P, M, C = 10, 22, 64
    cv = Canvas(2 * M + C, 2 * M + 24, (M, M, M, M), (C, 24))
    sd = lambda X, Y: sd_rrect(X, Y, P, P, cv.w - P, cv.h - P, 4)
    s = sd(cv.X, cv.Y)
    a = cov(s)
    cv.over(BLACK, blur_alpha(cv, a, 5, 3) * 0.6)
    d = -s
    rgb = oak_rgb(cv, C)
    rgb = lerp(rgb, OAK_PRESSED * 0.6, np.clip(np.exp(-np.maximum(d - 1, 0) / 3.0), 0, 1) * 0.4)
    cv.over(rgb, a * 0.95)
    cv.over(BRASS_DIM, cov(np.abs(d - 0.5) - 0.5))
    cv.over(BRASS, cov(np.abs(d - 2.5) - 0.35) * 0.35)
    cv.save("toast", shadow=(P, P, P, P))


def slot_ring(state):
    S = 72
    cv = Canvas(S, S)
    c = S / 2
    ro, ri = 30.0, 25.5
    r = np.hypot(cv.X - c, cv.Y - c)
    if state == "selected":
        glow = np.clip(1 - (r - ro) / 6, 0, 1) * (r > ro - 1)
        cv.over(BRASS_BRIGHT, glow ** 2 * 0.55)
    disc = lambda X, Y: sd_circle(X, Y, c, c, ri + 0.5)
    rgb = oak_rgb(cv, 72, OAK_INSET, OAK_PRESSED, 0.5)
    rgb = lerp(rgb, BLACK, np.clip(1 - (ri - r) / 6, 0, 1) * 0.65)
    cv.over(rgb, cov(disc(cv.X, cv.Y)) * 0.92)
    ring = lambda X, Y: np.abs(np.hypot(X - c, Y - c) - (ro + ri) / 2) - (ro - ri) / 2
    base = BRASS if state == "normal" else BRASS_BRIGHT if state == "selected" else BRASS_DIM
    cv.over(BLACK, cov(ring(cv.X - 0.6, cv.Y - 1.2) - 0.3) * 0.5)
    cv.over(brass(cv, ring, base, 1.8), cov(ring(cv.X, cv.Y)))
    # Four studs on the ring.
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        sx, sy = c + math.cos(ang) * (ro + ri) / 2, c + math.sin(ang) * (ro + ri) / 2
        stud = lambda X, Y, sx=sx, sy=sy: sd_circle(X, Y, sx, sy, 1.7)
        cv.over(brass(cv, stud, BRASS_BRIGHT, 1.3), cov(stud(cv.X, cv.Y)))
    cv.save("slot_ring_" + state, tile=False)


def item_slot(state):
    M, C = 12, 24
    cv = Canvas(2 * M + C, 2 * M + C, (M, M, M, M), (C, C))
    sd = lambda X, Y: sd_rrect(X, Y, 1, 1, cv.w - 1, cv.h - 1, 3)
    s = sd(cv.X, cv.Y)
    rgb = oak_rgb(cv, C, OAK_INSET, OAK_PRESSED, 0.5)
    rgb = lerp(rgb, BLACK, np.clip(1 - np.minimum(cv.Y, cv.X) / 5, 0, 1) * 0.55)
    cv.over(rgb, cov(s) * 0.9)
    d = -s
    border = BRASS if state == "selected" else OAK_LINE
    cv.over(border, cov(np.abs(d - 0.5) - 0.5))
    # Brass corner ticks.
    for sx in (0, 1):
        for sy in (0, 1):
            lx = cv.X if not sx else cv.w - cv.X
            ly = cv.Y if not sy else cv.h - cv.Y
            tick = lambda X, Y, sx=sx, sy=sy: np.minimum(
                sd_rrect(X if not sx else cv.w - X, Y if not sy else cv.h - Y, 0.5, 0.5, 9, 3, 1),
                sd_rrect(X if not sx else cv.w - X, Y if not sy else cv.h - Y, 0.5, 0.5, 3, 9, 1))
            cv.over(brass(cv, tick, BRASS_BRIGHT if state == "selected" else BRASS, 1.0), cov(tick(cv.X, cv.Y)))
    cv.save("item_slot_" + state, shadow=(0, 0, 0, 0))


def brass_separator():
    M, C = 48, 32
    cv = Canvas(2 * M + C, 9, (M, 0, M, 0), (C, 9))
    taper = np.minimum(smooth(3, M, cv.X), smooth(3, M, cv.w - cv.X))
    cv.over(BLACK, cov(np.abs(cv.Y - 5.4) - 0.6) * taper * 0.6)
    cv.over(BRASS, cov(np.abs(cv.Y - 4.3) - (0.2 + 0.4 * taper)) * (0.4 + 0.6 * taper))
    for cx in (3.0, cv.w - 3.0):
        dia = lambda X, Y, cx=cx: (np.abs(X - cx) + np.abs(Y - 4.5)) - 2.2
        cv.over(brass(cv, dia, BRASS, 1.0), cov(dia(cv.X, cv.Y)))
    cv.save("brass_separator", shadow=(0, 0, 0, 0))


def tooltip():
    oak_panel("oak_tooltip", P=6, border=BRASS_DIM, alpha=0.97)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true", help="download the CC0 source textures first")
    args = ap.parse_args()
    if args.fetch:
        fetch()
    os.makedirs(OUT, exist_ok=True)
    parchment_window()
    parchment_panel()
    for s in ("normal", "hover", "pressed", "disabled"):
        parchment_button(s)
        oak_button(s)
    for s in ("normal", "focus", "read_only"):
        parchment_field(s)
        oak_field(s)
    for s in ("selected", "unselected", "hovered"):
        parchment_tab(s)
        oak_tab(s)
    ink_separator()
    ribbon()
    for s in ("normal", "hover", "pressed"):
        wax_seal(s)
    oak_window()
    oak_panel()
    tooltip()
    key_chip()
    toast()
    for s in ("normal", "selected", "disabled"):
        slot_ring(s)
    for s in ("normal", "selected"):
        item_slot(s)
    brass_separator()
    with open(os.path.join(OUT, "frames.json"), "w") as f:
        json.dump(MANIFEST, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote %d pieces to %s" % (len(MANIFEST), OUT))


if __name__ == "__main__":
    main()

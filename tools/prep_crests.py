"""Turn the generated house crests and the school emblem into game-ready PNGs
with transparency, and the emblem's small mark into the app icon.

Sources live in assets/ui/brand/source/ (as generated, square, 1254 px):
  crest_N_<house>.png       colour crest on dark ink
  crest_N_<house>_mono.png  single-colour crest, dark ink on white

Outputs in assets/ui/brand/ (1024 px, plus pre-shrunk copies for 2D, where
Godot draws without mipmaps and a 1024 px crest shown at 24 px would shimmer):
  crest_N_<house>.png          colour crest, background outside the seal removed
  crest_N_<house>_256.png      the same at 256 px (sorting reveal, cards)
  crest_N_<house>_mono.png     white glyph on alpha, tinted in the engine (modulate)
  crest_N_<house>_mono_48.png  the same at 48 px (HUD and list icons)

  emblem.png / emblem_512.png  the school emblem (four houses around the book), 1024 / 512 px
  wordmark.png / wordmark_640.png  the game name lettering (owner's), 2048 / 640 px wide
  splash.png                   the emblem over the wordmark, for the boot splash
  icon.png                     the mark (book and star in a ring), 1024 px: window and app icon
  icon.ico                     Windows icon; 16 and 24 px use the book and star alone, as the
                               ring's thin lines vanish at that size

Run: python3 tools/prep_crests.py   (needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/ui/brand/source"
OUT = ROOT / "assets/ui/brand"
SIZE = 1024
HOUSES = ["1_drakoryn", "2_grypheon", "3_phoenara", "4_hipporys"]
# Inside this share of the half-width everything is seal; outside it only the
# notches and the ring edge sit on the plain background, which is keyed out.
SEAL_RADIUS = 0.86


def save(im: Image.Image, dst: Path, small: int) -> None:
    im.resize((SIZE, SIZE), Image.LANCZOS).save(dst, optimize=True)
    small_dst = dst.with_name(f"{dst.stem}_{small}.png")
    im.resize((small, small), Image.LANCZOS).save(small_dst, optimize=True)


def colour(src: Path, dst: Path, small: int = 256, seal_radius: float = SEAL_RADIUS) -> None:
    out = keyed(Image.open(src).convert("RGB"), seal_radius)
    save(out, dst, small)


def keyed(im: Image.Image, seal_radius: float) -> Image.Image:
    """`im` with its plain background removed outside the seal."""
    w, h = im.size
    bg = Image.new("RGB", im.size, im.getpixel((4, 4)))
    # Distance from the background colour, ramped to an alpha.
    diff = ImageChops.difference(im, bg).convert("L")
    key = diff.point(lambda v: max(0, min(255, (v - 10) * 6)))
    seal = Image.new("L", im.size, 0)
    r = seal_radius * w / 2
    ImageDraw.Draw(seal).ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), fill=255)
    seal = seal.filter(ImageFilter.GaussianBlur(2))
    alpha = ImageChops.lighter(key, seal)
    out = im.copy()
    out.putalpha(alpha)
    return out


def mono(src: Path, dst: Path) -> None:
    lum = Image.open(src).convert("L")
    # White paper -> clear, dark ink -> solid.
    alpha = ImageOps.invert(lum).point(lambda v: max(0, min(255, (v - 6) * 255 // 190)))
    out = Image.new("RGBA", lum.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    save(out, dst, 48)


# The mark's ring (in the 1254 px original): centre and the radius just inside it.
MARK_CENTRE = (625, 600)
MARK_INNER = 432
# How far the ring's stars reach inside MARK_INNER.
MARK_STAR_TIP = 100


def icon() -> None:
    mark = Image.open(SRC / "emblem_mark.png").convert("RGB")
    big = keyed(mark, MARK_INNER / (mark.width / 2))
    big = big.crop(big.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
    side = max(big.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(big, ((side - big.width) // 2, (side - big.height) // 2))
    square = square.resize((SIZE, SIZE), Image.LANCZOS)
    square.save(OUT / "icon.png", optimize=True)
    # Small sizes: the book and star alone on a dark disc.
    bg = mark.getpixel((4, 4))
    inner = Image.new("L", mark.size, 0)
    cx, cy = MARK_CENTRE
    draw = ImageDraw.Draw(inner)
    draw.ellipse((cx - MARK_INNER, cy - MARK_INNER, cx + MARK_INNER, cy + MARK_INNER), fill=255)
    # The ring's four stars reach inward past the ring: leave their tips out.
    t = MARK_STAR_TIP
    for box in [(cx - 40, 0, cx + 40, cy - MARK_INNER + t), (cx - 40, cy + MARK_INNER - t, cx + 40, mark.height),
                (0, cy - 40, cx - MARK_INNER + t, cy + 40), (cx + MARK_INNER - t, cy - 40, mark.width, cy + 40)]:
        draw.rectangle(box, fill=0)
    plain = Image.new("RGB", mark.size, bg)
    clean = Image.composite(mark, plain, inner)
    book = clean.crop(ImageChops.difference(clean, plain).convert("L").point(lambda v: 255 if v > 40 else 0).getbbox())
    side = int(max(book.size) * 1.12)
    disc = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse((0, 0, side - 1, side - 1), fill=bg + (255,))
    disc.paste(book, ((side - book.width) // 2, (side - book.height) // 2 + side // 40))
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, side - 1, side - 1), fill=255)
    disc.putalpha(mask)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = [(disc if px < 32 else square).resize((px, px), Image.LANCZOS) for px in sizes]
    images[-1].save(OUT / "icon.ico", sizes=[(px, px) for px in sizes], append_images=images[:-1])
    disc.resize((256, 256), Image.LANCZOS).save(OUT / "icon_small.png", optimize=True)


def unpremultiplied(im: Image.Image, bg: tuple, alpha: Image.Image) -> Image.Image:
    """The colour each pixel would have had without the background showing through."""
    out = Image.new("RGBA", im.size)
    px, a_px, o = im.load(), alpha.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            a = a_px[x, y]
            if a == 0:
                o[x, y] = (0, 0, 0, 0)
                continue
            f = a / 255
            o[x, y] = tuple(max(0, min(255, int((px[x, y][i] - bg[i] * (1 - f)) / f))) for i in range(3)) + (a,)
    return out


def wordmark() -> Image.Image:
    """The lettering on transparency, cropped to the art with a small margin."""
    im = Image.open(SRC / "wordmark.png").convert("RGB")
    bg = im.getpixel((4, 4))
    diff = ImageChops.difference(im, Image.new("RGB", im.size, bg)).convert("L")
    alpha = diff.point(lambda v: max(0, min(255, (v - 8) * 3)))
    out = unpremultiplied(im, bg, alpha)
    box = alpha.point(lambda v: 255 if v > 30 else 0).getbbox()
    pad = 24
    out = out.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(im.width, box[2] + pad), min(im.height, box[3] + pad)))
    for width, name in [(2048, "wordmark.png"), (640, "wordmark_640.png")]:
        out.resize((width, round(out.height * width / out.width)), Image.LANCZOS).save(OUT / name, optimize=True)
    return out


def splash(mark: Image.Image) -> None:
    emblem = Image.open(OUT / "emblem.png").resize((560, 560), Image.LANCZOS)
    word = mark.resize((900, round(mark.height * 900 / mark.width)), Image.LANCZOS)
    canvas = Image.new("RGBA", (960, 560 + 20 + word.height), (0, 0, 0, 0))
    canvas.alpha_composite(emblem, ((960 - 560) // 2, 0))
    canvas.alpha_composite(word, ((960 - 900) // 2, 580))
    canvas.save(OUT / "splash.png", optimize=True)


def main() -> None:
    for house in HOUSES:
        colour(SRC / f"crest_{house}.png", OUT / f"crest_{house}.png")
        mono(SRC / f"crest_{house}_mono.png", OUT / f"crest_{house}_mono.png")
        print("crest", house)
    colour(SRC / "emblem.png", OUT / "emblem.png", 512, 0.85)
    icon()
    splash(wordmark())
    print("emblem, wordmark, splash and icon")


if __name__ == "__main__":
    main()

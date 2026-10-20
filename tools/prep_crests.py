"""Turn the generated house crests into game-ready PNGs with transparency.

Sources live in assets/ui/brand/source/ (as generated, square, 1254 px):
  crest_N_<house>.png       colour crest on dark ink
  crest_N_<house>_mono.png  single-colour crest, dark ink on white

Outputs in assets/ui/brand/ (1024 px, plus pre-shrunk copies for 2D, where
Godot draws without mipmaps and a 1024 px crest shown at 24 px would shimmer):
  crest_N_<house>.png          colour crest, background outside the seal removed
  crest_N_<house>_256.png      the same at 256 px (sorting reveal, cards)
  crest_N_<house>_mono.png     white glyph on alpha, tinted in the engine (modulate)
  crest_N_<house>_mono_48.png  the same at 48 px (HUD and list icons)

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


def colour(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    bg = Image.new("RGB", im.size, im.getpixel((4, 4)))
    # Distance from the background colour, ramped to an alpha.
    diff = ImageChops.difference(im, bg).convert("L")
    keyed = diff.point(lambda v: max(0, min(255, (v - 10) * 6)))
    seal = Image.new("L", im.size, 0)
    r = SEAL_RADIUS * w / 2
    ImageDraw.Draw(seal).ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), fill=255)
    seal = seal.filter(ImageFilter.GaussianBlur(2))
    alpha = ImageChops.lighter(keyed, seal)
    out = im.copy()
    out.putalpha(alpha)
    save(out, dst, 256)


def mono(src: Path, dst: Path) -> None:
    lum = Image.open(src).convert("L")
    # White paper -> clear, dark ink -> solid.
    alpha = ImageOps.invert(lum).point(lambda v: max(0, min(255, (v - 6) * 255 // 190)))
    out = Image.new("RGBA", lum.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    save(out, dst, 48)


def main() -> None:
    for house in HOUSES:
        colour(SRC / f"crest_{house}.png", OUT / f"crest_{house}.png")
        mono(SRC / f"crest_{house}_mono.png", OUT / f"crest_{house}_mono.png")
        print("crest", house)


if __name__ == "__main__":
    main()

"""Paint the four house banners: damask cloth in the house colour, a brass border
and the house crest as an embroidered roundel, written into the banner models.

The damask weave is lifted from the first banner batch (a clean stretch of
assets/ui/brand/source/banner_damask.jpg, which has no emblem), turned into a
grey pattern and tinted per house; the crest is the colour crest from
assets/ui/brand/ (tools/prep_crests.py). Each texture replaces the image inside
assets/models/environment/modular/banner_hN.glb and the copy Godot extracted
next to it (banner_hN_banner_hN.jpg), so the models keep their mesh, UVs and
brass rod.

Run: python3 tools/make_banners.py   (needs Pillow)
"""
import io
import json
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets/ui/brand"
MODELS = ROOT / "assets/models/environment/modular"
W, H = 1024, 2048
# Same as CharacterProfile.HOUSE_COLORS / docs/brand-prompts.md.
HOUSES = {1: ("1_drakoryn", (0x33, 0xAD, 0x61)), 2: ("2_grypheon", (0xEB, 0xB8, 0x40)),
          3: ("3_phoenara", (0xF2, 0x6B, 0x2E)), 4: ("4_hipporys", (0x47, 0x8C, 0xEB))}
BRASS = (0xC8, 0xA3, 0x5A)
BRASS_BRIGHT = (0xE8, 0xC7, 0x7A)
INK = (0x2B, 0x1D, 0x10)
# Cloth is the house colour taken down toward ink so the crest's brass reads on it.
CLOTH_DEPTH = 0.62
BAND = 46          # outer brass band, px
LINE = (70, 82)    # inner brass rule, px from the edge
CREST_WIDTH = 780
CREST_CENTRE_Y = 900


def damask() -> Image.Image:
    """A grey weave (mean 1.0 as 128) covering the whole banner."""
    src = Image.open(BRAND / "source/banner_damask.jpg").convert("L")
    tile = ImageOps.autocontrast(src.crop((100, 1450, 920, 2040)), cutoff=1)
    out = Image.new("L", (W, H))
    flip = False
    for y in range(0, H, tile.height):
        row = ImageOps.flip(tile) if flip else tile
        for x in range(0, W, tile.width):
            out.paste(row, (x, y))
        flip = not flip
    return out


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def paint(house: int, weave: Image.Image) -> Image.Image:
    slug, colour = HOUSES[house]
    cloth = lerp(INK, colour, CLOTH_DEPTH)
    base = Image.new("RGB", (W, H), cloth)
    # Weave: lighten and darken the cloth by up to ~18% around its colour.
    light = Image.new("RGB", (W, H), lerp(cloth, (255, 255, 255), 0.18))
    dark = Image.new("RGB", (W, H), lerp(cloth, (0, 0, 0), 0.25))
    img = Image.composite(light, dark, weave)
    img = Image.blend(base, img, 0.55)
    # Brass band on the sides and top (the bottom hem stays cloth, like the first batch).
    band = Image.new("RGB", (W, H), BRASS)
    band_woven = Image.blend(band, Image.composite(Image.new("RGB", (W, H), BRASS_BRIGHT), Image.new("RGB", (W, H), lerp(BRASS, INK, 0.3)), weave), 0.5)
    mask = Image.new("L", (W, H), 0)
    mask.paste(255, (0, 0, BAND, H))
    mask.paste(255, (W - BAND, 0, W, H))
    mask.paste(255, (0, 0, W, BAND))
    mask.paste(255, (LINE[0], LINE[0], LINE[1], H))
    mask.paste(255, (W - LINE[1], LINE[0], W - LINE[0], H))
    mask.paste(255, (LINE[0], LINE[0], W - LINE[0], LINE[1]))
    img = Image.composite(band_woven, img, mask)
    # Crest, sewn on: a soft shadow under it, then the crest.
    crest = Image.open(BRAND / f"crest_{slug}.png").convert("RGBA").resize((CREST_WIDTH, CREST_WIDTH), Image.LANCZOS)
    pos = ((W - CREST_WIDTH) // 2, CREST_CENTRE_Y - CREST_WIDTH // 2)
    shadow = crest.getchannel("A").filter(ImageFilter.GaussianBlur(14))
    shadow_layer = Image.new("RGB", (W, H), (0, 0, 0))
    shadow_mask = Image.new("L", (W, H), 0)
    shadow_mask.paste(shadow.point(lambda v: v * 0.55), (pos[0] + 6, pos[1] + 12))
    img = Image.composite(shadow_layer, img, shadow_mask)
    img.paste(crest, pos, crest)
    return img


def replace_glb_image(glb: Path, jpeg: bytes) -> None:
    """Swaps the GLB's only image for `jpeg`, repacking the binary chunk."""
    data = glb.read_bytes()
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    bin_len = struct.unpack("<I", data[20 + json_len:24 + json_len])[0]
    blob = data[bin_start:bin_start + bin_len]
    image_view = doc["images"][0]["bufferView"]
    out = bytearray()
    for i, view in enumerate(doc["bufferViews"]):
        start = view.get("byteOffset", 0)
        chunk = jpeg if i == image_view else blob[start:start + view["byteLength"]]
        while len(out) % 4:
            out.append(0)
        view["byteOffset"] = len(out)
        view["byteLength"] = len(chunk)
        out += chunk
    while len(out) % 4:
        out.append(0)
    doc["buffers"][0]["byteLength"] = len(out)
    doc["images"][0]["mimeType"] = "image/jpeg"
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    glb.write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
                    + struct.pack("<I4s", len(out), b"BIN\x00") + bytes(out))


def main() -> None:
    weave = damask()
    for house in HOUSES:
        img = paint(house, weave)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=90)
        replace_glb_image(MODELS / f"banner_h{house}.glb", buf.getvalue())
        (MODELS / f"banner_h{house}_banner_h{house}.jpg").write_bytes(buf.getvalue())
        print("banner", house)


if __name__ == "__main__":
    main()

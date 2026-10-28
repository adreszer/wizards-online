"""Caps the textures embedded in GLB files, in place: colour and normal maps to
--max (2048 by default), metallic-roughness and occlusion maps to --max-mr (1024).
Meshy exports 4K maps; a 4K map costs ~21 MB of VRAM-compressed texture in the
exported pack, three per prop, for detail nobody sees at prop distance.
Geometry, UVs and materials are untouched. Needs Pillow (macOS: /usr/bin/python3).

Godot extracts a GLB's images into sidecar files next to it (<model>_<image>.png)
on the first import and never overwrites them, and those sidecars are what the
game loads and ships. So loose .png/.jpg/.webp files under the given folders are
capped too, by name: "metal", "rough" or "occlusion" in the name is a 1K map.

  /usr/bin/python3 tools/shrink_glb_textures.py assets/models            # every GLB under it
  /usr/bin/python3 tools/shrink_glb_textures.py a.glb b.glb --dry-run    # report only
"""
import argparse
import io
import json
import os
import struct
import sys

from PIL import Image

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC or version != 2:
        raise ValueError(f"{path}: not a glTF 2 binary")
    json_len, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == CHUNK_JSON
    gltf = json.loads(data[20:20 + json_len])
    at = 20 + json_len
    binary = b""
    if at < len(data):
        bin_len, bin_type = struct.unpack_from("<II", data, at)
        assert bin_type == CHUNK_BIN
        binary = data[at + 8:at + 8 + bin_len]
    return gltf, binary


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + (8 + len(binary) if binary else 0)
    with open(path + ".tmp", "wb") as out:
        out.write(struct.pack("<III", GLB_MAGIC, 2, total))
        out.write(struct.pack("<II", len(text), CHUNK_JSON) + text)
        if binary:
            out.write(struct.pack("<II", len(binary), CHUNK_BIN) + binary)
    os.replace(path + ".tmp", path)


def image_limits(gltf, max_colour, max_mr):
    """Image index → the largest edge it may keep, from how materials use it."""
    textures = gltf.get("textures", [])
    limits = {}

    def mark(info, limit):
        if not info or info.get("index") is None or info["index"] >= len(textures):
            return
        source = textures[info["index"]].get("source")
        if source is not None:
            limits[source] = max(limits.get(source, 0), limit)

    for material in gltf.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        mark(pbr.get("baseColorTexture"), max_colour)
        mark(material.get("normalTexture"), max_colour)
        mark(material.get("emissiveTexture"), max_colour)
        mark(pbr.get("metallicRoughnessTexture"), max_mr)
        mark(material.get("occlusionTexture"), max_mr)
    return limits


def shrink(path, max_colour, max_mr, dry_run):
    gltf, binary = read_glb(path)
    images = gltf.get("images", [])
    views = gltf.get("bufferViews", [])
    limits = image_limits(gltf, max_colour, max_mr)
    replaced = {}
    report = []
    for index, image in enumerate(images):
        view_index = image.get("bufferView")
        if view_index is None:
            continue
        view = views[view_index]
        start = view.get("byteOffset", 0)
        raw = binary[start:start + view["byteLength"]]
        with Image.open(io.BytesIO(raw)) as picture:
            size = picture.size
            limit = limits.get(index, max_colour)
            if max(size) <= limit:
                continue
            scale = limit / max(size)
            new_size = (max(1, round(size[0] * scale)), max(1, round(size[1] * scale)))
            report.append(f"{image.get('name', index)} {size[0]}x{size[1]} -> {new_size[0]}x{new_size[1]}")
            if dry_run:
                continue
            picture.load()
            small = picture.resize(new_size, Image.LANCZOS)
            buffer = io.BytesIO()
            if image.get("mimeType") == "image/jpeg":
                small.convert("RGB").save(buffer, "JPEG", quality=92)
            else:
                small.save(buffer, "PNG", optimize=True)
            replaced[view_index] = buffer.getvalue()
    if replaced:
        # Rebuild the binary chunk in view order, each view 4-byte aligned.
        out = bytearray()
        for view_index, view in enumerate(views):
            start = view.get("byteOffset", 0)
            chunk = replaced.get(view_index, binary[start:start + view["byteLength"]])
            out += b"\0" * (-len(out) % 4)
            view["byteOffset"] = len(out)
            view["byteLength"] = len(chunk)
            out += chunk
        gltf["buffers"][0]["byteLength"] = len(out)
        before = os.path.getsize(path)
        write_glb(path, gltf, bytes(out))
        report.append(f"{before / 1e6:.1f} MB -> {os.path.getsize(path) / 1e6:.1f} MB")
    return report


MR_WORDS = ("metal", "rough", "occlusion")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


def shrink_image(path, max_colour, max_mr, dry_run):
    with Image.open(path) as picture:
        size = picture.size
        limit = max_mr if any(w in os.path.basename(path).lower() for w in MR_WORDS) else max_colour
        if max(size) <= limit:
            return []
        scale = limit / max(size)
        new_size = (max(1, round(size[0] * scale)), max(1, round(size[1] * scale)))
        line = f"{size[0]}x{size[1]} -> {new_size[0]}x{new_size[1]}"
        if dry_run:
            return [line]
        picture.load()
        small = picture.resize(new_size, Image.LANCZOS)
        fmt = picture.format
    before = os.path.getsize(path)
    if fmt == "JPEG":
        small.convert("RGB").save(path, "JPEG", quality=92)
    elif fmt == "WEBP":
        small.save(path, "WEBP", quality=92)
    else:
        small.save(path, "PNG", optimize=True)
    return [line, f"{before / 1e6:.1f} MB -> {os.path.getsize(path) / 1e6:.1f} MB"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("paths", nargs="+")
    p.add_argument("--max", type=int, default=2048)
    p.add_argument("--max-mr", type=int, default=1024)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    files = []
    for path in a.paths:
        if os.path.isdir(path):
            for root, _dirs, names in os.walk(path):
                files += [os.path.join(root, n) for n in names if n.lower().endswith(IMAGE_EXTS + (".glb",))]
        else:
            files.append(path)
    for path in sorted(files):
        if path.endswith(".glb"):
            lines = shrink(path, a.max, a.max_mr, a.dry_run)
        else:
            lines = shrink_image(path, a.max, a.max_mr, a.dry_run)
        if lines:
            print(path + ": " + "; ".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())

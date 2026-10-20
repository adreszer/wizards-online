"""Weaves the castle tapestry: the four house creatures (the banner emblems, rendered
from their sculptures into .godot/meshy_src/emblems/) on a deep green millefleurs
field inside a red and gold border, quantised to a wool palette with weft ribs, then
hung as softly folded cloth from a wooden rod. Runs inside Blender, headless:

  blender -b --factory-startup --python tools/make_tapestry.py -- \
      --emblems .godot/meshy_src/emblems --out assets/models/environment/modular/tapestry.glb

The hanging is 2.4 m wide and 3.2 m tall, its bottom 1.0 m above the floor; origin at
the floor, centred, the cloth just in front of the wall (front -Y in Blender).
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np

W, H = 1536, 2048
BORDER = 96
# Each creature: (image, dark wool, light wool, quadrant, mirror so it faces the middle).
CREATURES = [
    ("emblem_phoenix.png", (0.55, 0.22, 0.05), (1.0, 0.78, 0.42), (0, 0), False),
    ("emblem_dragon.png", (0.50, 0.08, 0.06), (0.98, 0.62, 0.32), (1, 0), False),
    ("emblem_hippocampus.png", (0.10, 0.20, 0.48), (0.80, 0.88, 1.0), (0, 1), True),
    ("emblem_griffin.png", (0.42, 0.28, 0.04), (0.98, 0.86, 0.42), (1, 1), False),
]
FIELD = np.array([0.07, 0.15, 0.12])
FLOWERS = [(0.92, 0.86, 0.68), (0.78, 0.18, 0.14), (0.30, 0.42, 0.75), (0.88, 0.66, 0.20), (0.62, 0.32, 0.55)]


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--emblems", required=True)
    p.add_argument("--out", required=True)
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def load_rgba(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(im)
    return a


def resize(a, w, h):
    ys = (np.arange(h) * a.shape[0] / h).astype(int)
    xs = (np.arange(w) * a.shape[1] / w).astype(int)
    return a[ys[:, None], xs[None, :]]


def disc(img, cx, cy, r, color):
    y0, y1 = max(0, int(cy - r)), min(H, int(cy + r) + 1)
    x0, x1 = max(0, int(cx - r)), min(W, int(cx + r) + 1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    m = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    img[y0:y1, x0:x1][m] = color


def weave(emblems):
    rng = np.random.default_rng(7)
    img = np.empty((H, W, 3), np.float32)
    img[:] = FIELD
    # Millefleurs: small five-petal flowers scattered over the field.
    for _ in range(900):
        cx, cy = rng.uniform(BORDER, W - BORDER), rng.uniform(BORDER, H - BORDER)
        col = np.array(FLOWERS[rng.integers(len(FLOWERS))])
        r = rng.uniform(5, 9)
        for k in range(5):
            ang = k * 2 * math.pi / 5 + rng.uniform(0, 1)
            disc(img, cx + math.cos(ang) * r, cy + math.sin(ang) * r, r * 0.6, col)
        disc(img, cx, cy, r * 0.45, (0.95, 0.80, 0.30))
    # The creatures, each in its quarter, woven in its house colours.
    qw, qh = (W - 2 * BORDER) // 2, (H - 2 * BORDER) // 2
    for name, dark, light, (qx, qy), mirror in CREATURES:
        a = load_rgba(os.path.join(emblems, name))
        ys, xs = np.nonzero(a[..., 3] > 0.05)
        a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        if mirror:
            a = a[:, ::-1]
        s = min(qw * 0.86 / a.shape[1], qh * 0.80 / a.shape[0])
        a = resize(a, int(a.shape[1] * s), int(a.shape[0] * s))
        h, w = a.shape[:2]
        x0 = BORDER + qx * qw + (qw - w) // 2
        y0 = BORDER + qy * qh + (qh - h) // 2
        lum = a[..., :3].mean(axis=2, keepdims=True)
        lum = np.clip((lum - lum[a[..., 3] > 0.5].min()) / (np.ptp(lum[a[..., 3] > 0.5]) + 1e-6), 0, 1)
        col = np.array(dark) + (np.array(light) - np.array(dark)) * lum
        alpha = a[..., 3:4]
        img[y0:y0 + h, x0:x0 + w] = img[y0:y0 + h, x0:x0 + w] * (1 - alpha) + col * alpha
    # Border: madder red with a gold lozenge chain between cream rules.
    yy, xx = np.mgrid[0:H, 0:W]
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy))
    band = edge < BORDER
    img[band] = (0.45, 0.08, 0.07)
    along = np.where(np.minimum(xx, W - 1 - xx) < np.minimum(yy, H - 1 - yy), yy, xx)
    loz = (np.abs((along % 64) - 32) + np.abs(edge - BORDER / 2)) < 26
    img[band & loz] = (0.86, 0.64, 0.22)
    for r0 in (10, BORDER - 14):
        img[(edge >= r0) & (edge < r0 + 5)] = (0.90, 0.84, 0.66)
    # Wool: a limited palette (quantised) and weft ribs with a little thread jitter.
    # Age: colours faded toward grey and a little darker, as old wool is.
    grey = img.mean(axis=2, keepdims=True)
    img = (img * 0.78 + grey * 0.22) * 0.9
    img = np.round(img * 7) / 7
    row = (yy // 3) % 2
    jitter = rng.normal(0, 0.035, (H // 3 + 1, 1))[yy // 3, 0][..., None]
    ribs = (0.86 + 0.14 * np.abs(np.sin((yy % 3) / 3 * math.pi)))[..., None]
    img = np.clip(img * (ribs + jitter) * (0.97 + 0.03 * row[..., None]), 0, 1)
    height = (ribs[..., 0] - 0.86) / 0.14
    return img, height


def save_image(name, rgb, path):
    h, w = rgb.shape[:2]
    out = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = rgb[::-1]
    out.pixels.foreach_set(px.ravel())
    out.filepath_raw = path
    out.file_format = "JPEG"
    out.save()
    return out


def main():
    a = args()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    color, height = weave(a.emblems)
    tmp = bpy.app.tempdir
    albedo = save_image("tapestry_albedo", color, os.path.join(tmp, "tapestry_albedo.jpg"))
    gy, gx = np.gradient(height)
    normal = np.stack([0.5 - gx * 0.6, 0.5 + gy * 0.6, np.ones_like(height)], axis=-1)
    normal_img = save_image("tapestry_normal", np.clip(normal, 0, 1), os.path.join(tmp, "tapestry_normal.jpg"))
    normal_img.colorspace_settings.name = "Non-Color"

    # The cloth: a plane with soft vertical folds, hanging from 4.2 m down to 1.0 m.
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=48, y_subdivisions=8, size=1)
    cloth = bpy.context.active_object
    cloth.name = "tapestry"
    for v in cloth.data.vertices:
        u, t = v.co.x + 0.5, v.co.y + 0.5
        v.co = (v.co.x * 2.4, -0.05 - 0.025 * (0.5 + 0.5 * math.sin(u * math.pi * 7)) * (1 - 0.6 * t), 1.0 + t * 3.2)
    mat = bpy.data.materials.new("tapestry")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.95
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = albedo
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    ntex = nt.nodes.new("ShaderNodeTexImage")
    ntex.image = normal_img
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    cloth.data.materials.append(mat)
    # UVs straight from the plane.
    uv = cloth.data.uv_layers.new()
    for loop in cloth.data.loops:
        co = cloth.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / 2.4 + 0.5, (co.z - 1.0) / 3.2)
    # The rod with turned finials.
    wood = bpy.data.materials.new("rod")
    wood.use_nodes = True
    wb = next(n for n in wood.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    wb.inputs["Base Color"].default_value = (0.12, 0.06, 0.03, 1)
    wb.inputs["Roughness"].default_value = 0.55
    parts = [cloth]
    bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=2.7, location=(0, -0.06, 4.24), rotation=(0, math.pi / 2, 0))
    parts.append(bpy.context.active_object)
    for x in (-1.4, 1.4):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(x, -0.06, 4.24))
        parts.append(bpy.context.active_object)
    for p in parts[1:]:
        p.data.materials.append(wood)
        bpy.ops.object.select_all(action="DESELECT")
        p.select_set(True)
        bpy.context.view_layer.objects.active = p
        bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.ops.export_scene.gltf(filepath=a.out, use_selection=True, export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=92)
    print(f"WOVEN {a.out}")


main()

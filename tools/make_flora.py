"""Builds the grounds' flora (trees, bushes, rocks) at game weight from Poly Haven's
photoreal models (CC0). The grounds scatter tens of thousands of these as MultiMesh
instances, so each must stay at a few hundred triangles:

  * trees: the real tree's foliage is split into clusters, each cluster rendered from
    the side onto a tile of a leaf atlas; the game tree is a tapered bark trunk (and, for
    the broadleaf, limbs reaching into the biggest clusters) plus three crossed cards
    per cluster carrying those renders (the conifer instead lays them out as whorls of
    drooping branches in a cone, as the source fir is lanky), with normals bent outward
    from the crown so the cards light like a volume;
  * the bush: a low dome of cards from the broadleaf atlas;
  * the rock: the boulder decimated, keeping its texture.

The sources are saved .blend files of the Poly Haven downloads (git-ignored, in
.godot/meshy_src/flora/: conifer_src.blend = fir_tree_01 a, broadleaf_src.blend =
tree_small_02, rock_src.blend = boulder_01). Runs inside Blender, headless:

  blender -b --factory-startup --python tools/make_flora.py -- \
      --src .godot/meshy_src/flora --out assets/models/environment/flora

Each kind is exported as <kind>.glb: origin at the base, +Z up (glTF +Y), wood
surface first, leaves second (Seasons tints the leaves by surface index).
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

TILE = 256
ATLAS = 8  # tiles per side: 2048 px
## Cards are drawn this much bigger than their cluster, so the crown closes up.
CARD_GROW = 1.3
# kind: (source file, leaf material substring, bark material substring, clusters, height (m),
# seed, trunk (top as a share of the height, base radius, top radius), limbs)
TREES = {
    "conifer": ("conifer_src.blend", "twig", "bark", 48, 11.5, 3, (0.94, 0.3, 0.03), 0),
    "broadleaf": ("broadleaf_src.blend", "leaves", "trunk", 48, 8.5, 5, (0.5, 0.34, 0.2), 5),
}


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--only", default="")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


def append(path):
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = list(src.objects)
    objs = []
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
        objs.append(o)
    return objs


def apply_all(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def to_ground(o, height):
    """Base of the trunk at the origin, scaled to `height`."""
    apply_all(o)
    co = np.empty(len(o.data.vertices) * 3, np.float32)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    zmin, zmax = co[:, 2].min(), co[:, 2].max()
    base = co[co[:, 2] < zmin + 0.3]
    s = height / (zmax - zmin)
    o.location = (-base[:, 0].mean() * s, -base[:, 1].mean() * s, -zmin * s)
    o.scale = (s, s, s)
    apply_all(o)


def image_of(mat, word):
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and word in n.image.name:
            return n.image
    return None


def split(o, keep):
    """A new object holding only the faces whose material index is in `keep`."""
    c = o.copy()
    c.data = o.data.copy()
    bpy.context.scene.collection.objects.link(c)
    bm = bmesh.new()
    bm.from_mesh(c.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in keep], context="FACES")
    bm.to_mesh(c.data)
    bm.free()
    return c


def kmeans(pts, k, seed):
    rng = np.random.default_rng(seed)
    sample = pts[rng.choice(len(pts), min(len(pts), 40000), replace=False)]
    cen = sample[rng.choice(len(sample), k, replace=False)]
    for _ in range(25):
        lab = np.argmin(((sample[:, None, :] - cen[None]) ** 2).sum(-1), axis=1)
        for i in range(k):
            if (lab == i).any():
                cen[i] = sample[lab == i].mean(0)
    lab = np.concatenate([np.argmin(((pts[j:j + 200000, None, :] - cen[None]) ** 2).sum(-1), axis=1)
                          for j in range(0, len(pts), 200000)])
    return cen, lab


def render_setup():
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = TILE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.world = sc.world or bpy.data.worlds.new("w")
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def flat_material(name, diff, alpha):
    """Emission of the leaf colour, cut out by its alpha: the albedo as a flat render."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = diff
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    if alpha is not None:
        at = nt.nodes.new("ShaderNodeTexImage")
        at.image = alpha
        at.image.colorspace_settings.name = "Non-Color"
        nt.links.new(at.outputs["Color"], mix.inputs[0])
    else:
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


def hide_material():
    m = bpy.data.materials.new("hide")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(tr.outputs[0], out.inputs["Surface"])
    return m


def dilate(rgba, passes=12):
    """Spread colour into the transparent pixels so mipmaps don't fringe dark."""
    rgb, a = rgba[..., :3].copy(), rgba[..., 3] > 0.3
    filled = a.copy()
    for _ in range(passes):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * sh[..., None]
            cnt += sh
        grow = (~filled) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    rgb[~filled] = rgb[filled].mean(0)
    return np.concatenate([rgb, rgba[..., 3:4]], -1)


def bake_cards(leaves, k, seed, cam, tmp):
    """Clusters the leaf faces and renders each cluster onto a tile. Returns the atlas
    (H, W, 4) and one card per cluster: (centre, view direction, half size)."""
    me = leaves.data
    n = len(me.polygons)
    cen_f = np.empty(n * 3, np.float32)
    me.polygons.foreach_get("center", cen_f)
    cen_f = cen_f.reshape(-1, 3)
    centres, lab = kmeans(cen_f, k, seed)
    src = me.materials[0]
    diff = image_of(src, "diff")
    alpha = image_of(src, "alpha")
    flat, hide = flat_material("flat", diff, alpha), hide_material()
    me.materials.clear()
    for i in range(k):
        me.materials.append(hide)
    me.polygons.foreach_set("material_index", lab.astype(np.int32))
    me.update()
    axis = np.array([0.0, 0.0])
    atlas = np.zeros((TILE * ATLAS, TILE * ATLAS, 4), np.float32)
    cards = []
    vco = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", vco)
    vco = vco.reshape(-1, 3)
    loop_v = np.empty(sum(len(p.vertices) for p in me.polygons), np.int32)
    me.polygons.foreach_get("vertices", loop_v)
    starts = np.empty(n, np.int32)
    me.polygons.foreach_get("loop_start", starts)
    for i in range(k):
        c = centres[i]
        out = c[:2] - axis
        d = np.array([out[0], out[1], 0.0])
        if np.linalg.norm(d) < 0.2:
            ang = i * 2.399
            d = np.array([math.cos(ang), math.sin(ang), 0.0])
        d /= np.linalg.norm(d)
        right = np.cross([0, 0, 1], d)
        right /= np.linalg.norm(right)
        pts = vco[loop_v[starts[lab == i]]]
        u = (pts - c) @ right
        v = pts[:, 2] - c[2]
        lo_u, hi_u = np.percentile(u, [1, 99])
        lo_v, hi_v = np.percentile(v, [1, 99])
        mid = c + right * (lo_u + hi_u) / 2 + np.array([0, 0, (lo_v + hi_v) / 2])
        half = max(hi_u - lo_u, hi_v - lo_v) / 2 * 1.04
        me.materials[i] = flat
        cam.data.ortho_scale = half * 2
        cam.location = Vector(mid + d * 30)
        cam.rotation_euler = Vector(-d).to_track_quat("-Z", "Y").to_euler()
        cam.data.clip_end = 80
        path = os.path.join(tmp, "tile_%02d.png" % i)
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        me.materials[i] = hide
        im = bpy.data.images.load(path)
        px = np.array(im.pixels[:], np.float32).reshape(TILE, TILE, 4)
        bpy.data.images.remove(im)
        ty, tx = divmod(i, ATLAS)
        atlas[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE] = dilate(px)
        cards.append((mid, d, half, (tx, ty)))
    return atlas, cards


def tube(verts, faces, uvs, a, b, r0, r1, sides=8, rings=6, bend=0.0, seed=0):
    """A tapered bark tube from `a` to `b` (UVs: bark around twice, 1.6 m per repeat)."""
    rng = np.random.default_rng(seed)
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    length = np.linalg.norm(axis)
    w = axis / length
    u = np.cross(w, [0, 0, 1] if abs(w[2]) < 0.9 else [1, 0, 0])
    u /= np.linalg.norm(u)
    v = np.cross(w, u)
    sway = rng.normal(0, bend, (rings + 1, 2))
    sway[0] = 0
    base = len(verts)
    for i in range(rings + 1):
        t = i / rings
        c = a + axis * t + (u * sway[i, 0] + v * sway[i, 1]) * math.sin(t * math.pi)
        r = r0 + (r1 - r0) * t
        for j in range(sides + 1):
            ang = 2 * math.pi * j / sides
            verts.append(c + (u * math.cos(ang) + v * math.sin(ang)) * r)
            uvs.append((2 * j / sides, length * t / 1.6))
    for i in range(rings):
        for j in range(sides):
            p = base + i * (sides + 1) + j
            faces.append((p, p + 1, p + sides + 2, p + sides + 1))


def wood_mesh(height, trunk, limbs, cards, seed):
    top, r0, r1 = trunk
    verts, faces, uvs = [], [], []
    tube(verts, faces, uvs, (0, 0, -0.3), (0, 0, height * top), r0, r1, rings=8, bend=0.06, seed=seed)
    # Limbs from the top of the trunk into the biggest clusters, spread around it.
    order = sorted(cards, key=lambda c: -c[2])
    picked = []
    for c in order:
        d = c[0][:2] / (np.linalg.norm(c[0][:2]) + 1e-6)
        if all(np.dot(d, q) < 0.5 for q in picked) and c[0][2] > height * top:
            picked.append(d)
            start = np.array([0, 0, height * top * (0.85 + 0.1 * len(picked) / max(limbs, 1))])
            tube(verts, faces, uvs, start, c[0] - (c[0] - start) * 0.25, r1 * 0.85, 0.04, sides=6, rings=4,
                 bend=0.15, seed=seed + len(picked))
        if len(picked) >= limbs:
            break
    me = bpy.data.meshes.new("wood")
    me.from_pydata([tuple(p) for p in verts], [], faces)
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[me.loops[li].vertex_index]
    me.shade_smooth()
    return me


def cluster_quads(cards, grow=CARD_GROW):
    """Three quads per cluster crossed at 60 degrees, each (corners, tile)."""
    quads = []
    for mid, d, half, tile in cards:
        half = half * grow
        right = np.cross([0, 0, 1], d)
        for ang in (0.0, math.pi / 3, -math.pi / 3):
            axis = right * math.cos(ang) + d * math.sin(ang)
            quads.append(([mid + axis * su * half + np.array([0, 0, sv * half])
                           for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))], tile))
    return quads


def cone_quads(tiles, height, seed):
    """A fir's cone: whorls of drooping branch cards around the trunk, wide at the
    bottom and narrowing to the tip, each branch a flat card and an upright one along
    it; the tip a few upright crossed cards."""
    rng = np.random.default_rng(seed)
    quads = []
    whorls = 11
    bottom, top = height * 0.16, height * 0.97
    for w in range(whorls):
        t = w / (whorls - 1)
        z = bottom + (top - bottom) * t ** 0.9
        reach = 0.35 + 2.5 * (1 - t) ** 1.1
        n = max(3, int(round(4 + 3 * (1 - t))))
        spin = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            ang = spin + 2 * math.pi * i / n + rng.uniform(-0.25, 0.25)
            d = np.array([math.cos(ang), math.sin(ang), 0.0])
            side = np.cross([0, 0, 1], d)
            droop = 0.25 + 0.2 * (1 - t)
            out = (d * math.cos(droop) - np.array([0, 0, math.sin(droop)])) * reach
            root = np.array([0, 0, z])
            wid = 0.45 * reach + 0.35
            tile = tiles[rng.integers(len(tiles))]
            # Flat card along the branch (tile bottom at the trunk) and an upright one.
            flat = [root - side * wid, root + side * wid, root + out + side * wid * 0.5, root + out - side * wid * 0.5]
            up = np.array([0, 0, wid * 0.7])
            tall = [root - up * 0.6, root + out - up * 0.8, root + out + up * 0.6, root + up]
            quads.append((flat, tile))
            quads.append((tall, tiles[rng.integers(len(tiles))]))
    tip = np.array([0, 0, top])
    for ang in (0.0, math.pi / 3, 2 * math.pi / 3):
        a = np.array([math.cos(ang), math.sin(ang), 0.0]) * 0.55
        quads.append(([tip - a - [0, 0, 1.2], tip + a - [0, 0, 1.2], tip + a * 0.2 + [0, 0, 0.5], tip - a * 0.2 + [0, 0, 0.5]],
                      tiles[rng.integers(len(tiles))]))
    return quads


def card_mesh(quads, crown):
    """The cards as one mesh: UVs on each quad's atlas tile, normals bent out of the
    crown so the cards light like a volume."""
    verts, faces, uvs, normals = [], [], [], []
    for corners, (tx, ty) in quads:
        base = len(verts)
        for p, (su, sv) in zip(corners, ((-1, -1), (1, -1), (1, 1), (-1, 1))):
            p = np.asarray(p, float)
            verts.append(p)
            out = p - crown
            out[2] *= 0.6
            normals.append(out / (np.linalg.norm(out) + 1e-6))
            # The atlas is in Blender's pixel order (row 0 at the bottom), as UV v.
            uvs.append(((tx + (su + 1) / 2) / ATLAS, (ty + (sv + 1) / 2) / ATLAS))
        faces.append((base, base + 1, base + 2, base + 3))
    me = bpy.data.meshes.new("cards")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[me.loops[li].vertex_index]
    me.normals_split_custom_set_from_vertices([tuple(n) for n in normals])
    return me


def save_image(name, px, path, fmt):
    h, w = px.shape[:2]
    im = bpy.data.images.new(name, w, h, alpha=True)
    im.pixels.foreach_set(px.ravel())
    im.filepath_raw = path
    im.file_format = fmt
    im.save()
    return im


def clean_material(src, name):
    """Just the colour and normal maps of a Poly Haven material (it also carries
    displacement, roughness and mask maps the game doesn't use)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Roughness"].default_value = 0.9
    diff, nor = image_of(src, "diff"), image_of(src, "nor_gl")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = diff
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if nor is not None:
        nt_ = nt.nodes.new("ShaderNodeTexImage")
        nt_.image = nor
        nor.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nt_.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


def leaf_material(atlas_img):
    m = bpy.data.materials.new("leaves")
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = atlas_img
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.85
    return m


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_image_format="WEBP", export_image_quality=85, export_yup=True)
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def build_tree(kind, a, tmp):
    src, leaf_word, bark_word, k, height, seed, trunk, limbs = TREES[kind]
    reset()
    o = [x for x in append(os.path.join(a.src, src)) if x.type == "MESH"][0]
    to_ground(o, height)
    mats = [m.name if m else "" for m in o.data.materials]
    leaf_idx = {i for i, m in enumerate(mats) if leaf_word in m}
    bark = [m for m in o.data.materials if m and bark_word in m.name][0]
    leaves = split(o, leaf_idx)
    bpy.data.objects.remove(o)
    # The leaf object keeps all slots; put its leaf material first for bake_cards.
    lm = [m for m in leaves.data.materials if m and leaf_word in m.name][0]
    leaves.data.materials.clear()
    leaves.data.materials.append(lm)
    leaves.data.polygons.foreach_set("material_index", np.zeros(len(leaves.data.polygons), np.int32))
    cam = render_setup()
    atlas, cards = bake_cards(leaves, k, seed, cam, tmp)
    bpy.data.objects.remove(leaves)
    co = np.array([c[0] for c in cards])
    crown = co.mean(0)
    if kind == "conifer":
        # The source fir is lanky: lay its foliage out as a proper cone instead, a cooler green.
        atlas[..., :3] *= np.array([0.62, 0.8, 0.7])
        crown = np.array([0, 0, height * 0.4])
        quads = cone_quads([c[3] for c in cards], height, seed)
    else:
        quads = cluster_quads(cards)
    cards_obj = bpy.data.objects.new("leaves", card_mesh(quads, crown))
    bpy.context.scene.collection.objects.link(cards_obj)
    img = save_image(kind + "_leaves", atlas, os.path.join(tmp, kind + "_leaves.png"), "PNG")
    cards_obj.data.materials.append(leaf_material(img))
    wood = bpy.data.objects.new("wood", wood_mesh(height, trunk, limbs, cards, seed))
    bpy.context.scene.collection.objects.link(wood)
    wood.data.materials.append(clean_material(bark, "bark"))
    wood_tris = len(wood.data.polygons) * 2
    tris = export([wood, cards_obj], os.path.join(a.out, kind + ".glb"))
    print("FLORA %s: %d tris (wood %d, %d cards), crown at %s" % (kind, tris, wood_tris, len(quads), np.round(crown, 2)))
    return atlas, cards


def build_bush(a, atlas, cards, tmp):
    """A low dome of crossed cards cut from the broadleaf atlas, 1.3 m tall."""
    reset()
    rng = np.random.default_rng(11)
    pick = rng.choice(len(cards), 9, replace=False)
    out = []
    for j, i in enumerate(pick):
        ang = j * 2 * math.pi / 9 + rng.uniform(-0.2, 0.2)
        r = 0.45 if j < 6 else 0.1
        d = np.array([math.cos(ang), math.sin(ang), 0.0])
        half = 0.5 if j < 6 else 0.6
        mid = d * r + np.array([0, 0, half * 0.9 + (0.15 if j >= 6 else 0)])
        out.append((mid, d, half, cards[i][3]))
    o = bpy.data.objects.new("bush", card_mesh(cluster_quads(out, grow=1.0), np.array([0, 0, 0.35])))
    bpy.context.scene.collection.objects.link(o)
    img = save_image("bush_leaves", atlas, os.path.join(tmp, "bush_leaves.png"), "PNG")
    o.data.materials.append(leaf_material(img))
    tris = export([o], os.path.join(a.out, "bush.glb"))
    print("FLORA bush: %d tris" % tris)


def build_rock(a):
    reset()
    o = [x for x in append(os.path.join(a.src, "rock_src.blend")) if x.type == "MESH"][0]
    apply_all(o)
    co = np.empty(len(o.data.vertices) * 3, np.float32)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    # About 1.9 m across like the placeholder, sunk 10 cm so it sits in the ground.
    s = 1.9 / np.ptp(co[:, :2], axis=0).max()
    o.location = (-co[:, 0].mean() * s, -co[:, 1].mean() * s, -co[:, 2].min() * s - 0.1)
    o.scale = (s, s, s)
    apply_all(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.001)
    bpy.ops.object.mode_set(mode="OBJECT")
    n = sum(len(p.vertices) - 2 for p in o.data.polygons)
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = 700 / n
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    src = o.data.materials[0]
    o.data.materials.clear()
    o.data.materials.append(clean_material(src, "rock"))
    tris = export([o], os.path.join(a.out, "rock.glb"))
    print("FLORA rock: %d tris" % tris)


def main():
    a = args()
    os.makedirs(a.out, exist_ok=True)
    tmp = bpy.app.tempdir
    only = set(a.only.split(",")) if a.only else {"conifer", "broadleaf", "bush", "rock"}
    for kind in ("conifer", "broadleaf"):
        if kind in only or (kind == "broadleaf" and "bush" in only):
            atlas, cards = build_tree(kind, a, tmp)
    if "bush" in only:
        build_bush(a, atlas, cards, tmp)
    if "rock" in only:
        build_rock(a)


main()

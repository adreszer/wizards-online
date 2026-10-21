"""Builds the castle's small puzzle and grounds pieces as real models, shaped in Blender
with Poly Haven's PBR textures (CC0; saved in .godot/meshy_src/textures/): carved
granite for stonework, iron, dark wood, bronze and gold, mossy rock, glowing crystal.
Each piece keeps the size and origin of the primitive it replaces (origin at the base,
front +Y in Blender = -Z in the game). Runs inside Blender, headless:

  blender -b --factory-startup --python tools/make_props5.py -- \
      --tex .godot/meshy_src/textures --out assets/models [--only lever_base,plaque]

Pieces: pressure_plate, pushable_block, statue_plinth, door_jamb, waystone, fragment,
lever_base, lever_handle, plaque, wall_medallion, goal_ring, broom_stand.
"""
import argparse
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

GRANITE_TILE = (0.02, 0.52, 0.31, 0.98)  # one paving tile of granite_tile_03 (u0, v0, u1, v1)


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--tex", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--only", default="")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


A = None


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)


# --- materials ---------------------------------------------------------------------


def _tex(nt, path, non_color=False):
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        t.image.colorspace_settings.name = "Non-Color"
    return t


def material(name, tex=None, tint=None, metallic=0.0, roughness=0.8, emission=None):
    """A Principled material: the texture's colour (times `tint`), its normal map and
    roughness, or flat values; `emission` makes it glow."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    if tex:
        d = _tex(nt, os.path.join(A.tex, tex + "_diff.jpg"))
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(d.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = (*tint, 1)
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        else:
            nt.links.new(d.outputs["Color"], b.inputs["Base Color"])
        n = _tex(nt, os.path.join(A.tex, tex + "_nor.jpg"), True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    elif tint:
        b.inputs["Base Color"].default_value = (*tint, 1)
    if emission:
        b.inputs["Emission Color"].default_value = (*emission, 1)
        b.inputs["Emission Strength"].default_value = 2.0
    return m


def mats():
    return {
        "granite": material("granite", "granite_tile_03", (0.92, 0.9, 0.86)),
        "granite_dark": material("granite_dark", "granite_tile_03", (0.45, 0.43, 0.42)),
        "iron": material("iron", "metal_plate_02", (0.32, 0.3, 0.29), metallic=0.85, roughness=0.55),
        "wood": material("wood", "dark_wooden_planks", (1.0, 0.92, 0.85), roughness=0.75),
        "bronze": material("bronze", None, (0.74, 0.52, 0.27), metallic=0.65, roughness=0.42),
        "gold": material("gold", None, (0.95, 0.72, 0.32), metallic=1.0, roughness=0.3),
        "moss": material("moss", "mossy_rock", (0.95, 0.95, 0.95)),
        "crystal_blue": material("crystal_blue", None, (0.55, 0.8, 1.0), roughness=0.1, emission=(0.35, 0.7, 1.0)),
        "crystal_gold": material("crystal_gold", None, (1.0, 0.82, 0.45), roughness=0.1, emission=(1.0, 0.72, 0.35)),
        "crystal_violet": material("crystal_violet", None, (0.75, 0.55, 1.0), roughness=0.1, emission=(0.62, 0.42, 1.0)),
    }


# --- geometry helpers --------------------------------------------------------------


def link(me, name, mat):
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def box(name, size, at, mat, bevel=0.0, segments=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(me, name, mat)


def lathe(name, profile, mat, sides=32, at=(0, 0, 0)):
    """Turns a (radius, height) profile about Z."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            ring.append(bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if profile[0][0] > 0:
        bm.faces.new(list(reversed(rings[0])))
    if profile[-1][0] > 0:
        bm.faces.new(rings[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(me, name, mat)
    smooth(o)
    return o


def torus(name, major, minor, mat, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), seg=48, minor_seg=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=minor_seg)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.rotation_euler = rot
    o.location = at
    o.data.materials.clear()
    o.data.materials.append(mat)
    smooth(o)
    return o


def crystal(name, radius, height, mat, at, tilt=(0, 0), sides=6):
    """A hexagonal crystal: a prism with a pointed tip and a shorter point below."""
    prof = [(0.0, -height * 0.18), (radius, 0.0), (radius, height * 0.62), (0.0, height)]
    o = lathe(name, prof, mat, sides=sides)
    for p in o.data.polygons:
        p.use_smooth = False
    o.rotation_euler = (tilt[0], tilt[1], 0)
    o.location = at
    return o


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def box_uv(o, tile=None, world=1.0):
    """Box-projected UVs: each face takes the two axes across its normal. With `tile`,
    the object's extent maps into that rectangle of the texture (one granite paving
    tile, so no grout lines); otherwise `world` metres per texture repeat."""
    me = o.data
    uv = me.uv_layers.new() if not me.uv_layers else me.uv_layers[0]
    co = [o.matrix_world @ v.co for v in me.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    span = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))) - lo
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for li in p.loop_indices:
            c = co[me.loops[li].vertex_index]
            if tile:
                s = max(span[a], span[b], 1e-4)
                u = (c[a] - lo[a]) / s
                v = (c[b] - lo[b]) / s
                uv.data[li].uv = (tile[0] + u * (tile[2] - tile[0]), tile[1] + v * (tile[3] - tile[1]))
            else:
                uv.data[li].uv = (c[a] / world, c[b] / world)


def text_lines(lines, size, depth, mat, at, width):
    """Raised lettering (an invented script) across a plaque: one text object per line."""
    objs = []
    for i, line in enumerate(lines):
        bpy.ops.object.text_add(location=(0, 0, 0))
        t = bpy.context.active_object
        t.data.body = line
        t.data.size = size
        t.data.extrude = depth
        t.data.align_x = "CENTER"
        bpy.ops.object.convert(target="MESH")
        t = bpy.context.active_object
        w = t.dimensions.x
        if w > width:
            t.scale.x = width / w
        t.rotation_euler = (math.pi / 2, 0, 0)
        t.location = (at[0], at[1], at[2] - i * size * 1.45)
        t.data.materials.clear()
        t.data.materials.append(mat)
        objs.append(t)
    return objs


def finish(name, objs, sub="environment/props5"):
    """Joins the parts, applies transforms and exports <out>/<sub>/<name>.glb."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    out = os.path.join(A.out, sub)
    os.makedirs(out, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    path = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_image_format="WEBP", export_image_quality=85)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("PROP %s: %d tris, %s m" % (name, tris, [round(d, 2) for d in o.dimensions]))


# --- pieces ------------------------------------------------------------------------


def pressure_plate(m):
    """A 1.8 m granite slab, 0.12 thick, with a darker rune ring set into its top."""
    slab = box("slab", (1.8, 1.8, 0.12), (0, 0, 0.06), m["granite"], bevel=0.03)
    box_uv(slab, GRANITE_TILE)
    ring = torus("ring", 0.58, 0.035, m["granite_dark"], at=(0, 0, 0.118), scale=(1, 1, 0.35))
    inner = torus("inner", 0.32, 0.025, m["granite_dark"], at=(0, 0, 0.118), scale=(1, 1, 0.35))
    marks = []
    for i in range(8):
        a = i * math.pi / 4
        marks.append(box("mark%d" % i, (0.05, 0.16, 0.012), (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.124), m["granite_dark"]))
        marks[-1].rotation_euler = (0, 0, a + math.pi / 2)
    for o in [ring, inner] + marks:
        box_uv(o, GRANITE_TILE)
    finish("pressure_plate", [slab, ring, inner] + marks)


def pushable_block(m):
    """A 1.4 m granite cube, its edges worn round, a raised square border on every face
    and a ring rune in the middle of each side."""
    cube = box("cube", (1.4, 1.4, 1.4), (0, 0, 0.7), m["granite"], bevel=0.05, segments=3)
    box_uv(cube, GRANITE_TILE)
    parts = [cube]
    for axis in range(3):
        for sign in (-1, 1):
            n = Vector((0, 0, 0))
            n[axis] = sign
            centre = Vector((0, 0, 0.7)) + n * 0.705
            u = Vector((0, 0, 0))
            u[(axis + 1) % 3] = 1
            v = n.cross(u)
            for k, (du, dv, lu, lv) in enumerate(((0, 0.5, 1.1, 0.06), (0, -0.5, 1.1, 0.06), (0.5, 0, 0.06, 1.1), (-0.5, 0, 0.06, 1.1))):
                size = Vector((0, 0, 0))
                size += Vector([abs(x) for x in u]) * lu + Vector([abs(x) for x in v]) * lv + Vector([abs(x) for x in n]) * 0.03
                b = box("bd", tuple(size), tuple(centre + u * du + v * dv), m["granite_dark"])
                parts.append(b)
            if axis != 2:
                r = torus("rune", 0.22, 0.025, m["granite_dark"], at=tuple(centre), scale=(1, 1, 0.4))
                r.rotation_euler = Vector((0, 0, 1)).rotation_difference(n).to_euler()
                parts.append(r)
    for o in parts[1:]:
        box_uv(o, GRANITE_TILE)
    finish("pushable_block", parts)


def statue_plinth(m):
    """A round plinth for the rotating statue: 1.6 m across, 0.6 m tall, moulded, with a
    darker rune band."""
    prof = [(0.0, 0.0), (0.8, 0.0), (0.8, 0.08), (0.76, 0.12), (0.72, 0.14), (0.7, 0.2), (0.7, 0.46),
            (0.73, 0.5), (0.76, 0.54), (0.76, 0.58), (0.72, 0.6), (0.0, 0.6)]
    p = lathe("plinth", prof, m["granite"], sides=40)
    box_uv(p, GRANITE_TILE)
    band = torus("band", 0.705, 0.03, m["granite_dark"], at=(0, 0, 0.33), scale=(1, 1, 1.6))
    box_uv(band, GRANITE_TILE)
    finish("statue_plinth", [p, band])


def door_jamb(m):
    """One side post of a magic doorway: 0.5 x 0.6, 3.6 m, chamfered, with a base and a
    capital (origin at the centre of its foot)."""
    shaft = box("shaft", (0.42, 0.52, 3.1), (0, 0, 0.25 + 1.55), m["granite"], bevel=0.04)
    base = box("base", (0.5, 0.6, 0.25), (0, 0, 0.125), m["granite"], bevel=0.03)
    neck = box("neck", (0.46, 0.56, 0.06), (0, 0, 3.32), m["granite"], bevel=0.015)
    cap = box("cap", (0.5, 0.6, 0.25), (0, 0, 3.475), m["granite"], bevel=0.03)
    for o in (shaft, base, neck, cap):
        box_uv(o, GRANITE_TILE)
    finish("door_jamb", [shaft, base, neck, cap])


def waystone(m):
    """A checkpoint waystone: a rough mossy standing stone, knee high, with a glowing
    blue crystal set on top."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    rnd = random.Random(4)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.32, v.co.y * 0.26, v.co.z * 0.45)) * (1 + rnd.uniform(-0.06, 0.06))
        if v.co.z < -0.3:
            v.co.z = -0.3
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.3)), verts=bm.verts)
    me = bpy.data.meshes.new("stone")
    bm.to_mesh(me)
    bm.free()
    stone = link(me, "stone", m["moss"])
    box_uv(stone, world=1.2)
    smooth(stone)
    c1 = crystal("c1", 0.08, 0.42, m["crystal_blue"], (0, 0, 0.68))
    c2 = crystal("c2", 0.05, 0.26, m["crystal_blue"], (0.06, 0.02, 0.66), tilt=(0.0, 0.5))
    c3 = crystal("c3", 0.045, 0.22, m["crystal_blue"], (-0.05, -0.03, 0.66), tilt=(0.4, -0.4))
    finish("waystone", [stone, c1, c2, c3])


def fragment(m):
    """A collectible fragment: a cluster of gold and violet crystal shards, 0.5 m tall,
    centred on its middle (it floats and spins)."""
    a = crystal("a", 0.1, 0.5, m["crystal_gold"], (0, 0, -0.25))
    b = crystal("b", 0.06, 0.3, m["crystal_violet"], (0.07, 0.0, -0.2), tilt=(0.0, 0.6))
    c = crystal("c", 0.055, 0.26, m["crystal_violet"], (-0.06, 0.03, -0.2), tilt=(0.5, -0.5))
    finish("fragment", [a, b, c])


def lever_base(m):
    """The lever's granite block (0.6 x 0.6, 1.0 tall) with an iron slot plate and bands."""
    block = box("block", (0.6, 0.6, 0.98), (0, 0, 0.49), m["granite"], bevel=0.03)
    box_uv(block, GRANITE_TILE)
    plate = box("plate", (0.3, 0.46, 0.04), (0, 0, 1.0), m["iron"], bevel=0.008)
    slot = box("slot", (0.08, 0.36, 0.045), (0, 0, 1.005), m["granite_dark"])
    bands = [box("band%d" % i, (0.62, 0.62, 0.05), (0, 0, z), m["iron"], bevel=0.01) for i, z in enumerate((0.12, 0.86))]
    pivot = lathe("pivot", [(0.0, -0.33), (0.05, -0.33), (0.05, 0.33), (0.0, 0.33)], m["iron"], sides=12)
    pivot.rotation_euler = (0, math.pi / 2, 0)
    pivot.location = (0, 0, 1.0)
    rivets = []
    for i, (x, y) in enumerate(((0.12, 0.2), (-0.12, 0.2), (0.12, -0.2), (-0.12, -0.2))):
        rivets.append(lathe("rivet%d" % i, [(0.0, 0.0), (0.018, 0.0), (0.014, 0.012), (0.0, 0.016)], m["iron"], sides=8, at=(x, y, 1.02)))
    for o in [plate, slot, pivot] + bands + rivets:
        box_uv(o, world=0.6)
    finish("lever_base", [block, plate, slot, pivot] + bands + rivets)


def lever_handle(m):
    """The lever arm: an iron rod from the pivot (origin) 0.9 m up to a wooden grip."""
    rod = lathe("rod", [(0.0, 0.0), (0.035, 0.0), (0.03, 0.66), (0.0, 0.66)], m["iron"], sides=12)
    collar = lathe("collar", [(0.0, 0.0), (0.06, 0.0), (0.06, 0.05), (0.0, 0.05)], m["iron"], sides=12)
    grip = lathe("grip", [(0.0, 0.64), (0.045, 0.64), (0.055, 0.7), (0.055, 0.84), (0.045, 0.88), (0.03, 0.9), (0.0, 0.9)], m["wood"], sides=12)
    for o in (rod, collar, grip):
        box_uv(o, world=0.4)
    finish("lever_handle", [rod, collar, grip])


SCRIPT = ["IN MEMORIAM", "MAGISTRORVM", "ET DISCIPVLORVM", "* * *"]


def plaque(m):
    """A bronze wall plaque, 1.2 x 0.8, 0.06 deep, with a raised frame and four lines of
    raised Latin lettering (the readable text is the game's own, shown on interact)."""
    back = box("back", (1.2, 0.06, 0.8), (0, 0.03, 0.4), m["bronze"], bevel=0.012)
    parts = [back]
    for size, at in (((1.2, 0.02, 0.06), (0, -0.005, 0.77)), ((1.2, 0.02, 0.06), (0, -0.005, 0.03)),
                     ((0.06, 0.02, 0.8), (0.57, -0.005, 0.4)), ((0.06, 0.02, 0.8), (-0.57, -0.005, 0.4))):
        parts.append(box("frame", size, at, m["bronze"], bevel=0.006))
    parts += text_lines(SCRIPT, 0.085, 0.006, m["bronze"], (0, 0.0, 0.58), 0.94)
    for o in parts:
        box_uv(o, world=0.8)
    # Face the room: the plaque's front is -Y here; the game's front is +Z (Blender -Y).
    finish("plaque", parts)


def wall_medallion(m):
    """The secret wall's ornament: a bronze ring (0.42 m) with an eye rune in its middle,
    centred on its back face, facing out (+Z in the game)."""
    ring = torus("ring", 0.3, 0.1, m["bronze"], rot=(math.pi / 2, 0, 0), scale=(1, 1, 0.7))
    disc = lathe("disc", [(0.0, 0.0), (0.2, 0.0), (0.2, 0.03), (0.0, 0.05)], m["bronze"], sides=32)
    disc.rotation_euler = (-math.pi / 2, 0, 0)
    eye = torus("eye", 0.11, 0.018, m["bronze"], rot=(math.pi / 2, 0, 0), scale=(1, 0.55, 1))
    eye.location = (0, -0.05, 0)
    pupil = lathe("pupil", [(0.0, 0.0), (0.035, 0.0), (0.03, 0.02), (0.0, 0.03)], m["bronze"], sides=16)
    pupil.rotation_euler = (-math.pi / 2, 0, 0)
    pupil.location = (0, -0.05, 0)
    parts = [ring, disc, eye, pupil]
    for o in parts:
        box_uv(o, world=0.5)
    finish("wall_medallion", parts)


def goal_ring(m):
    """A Lantern Chase hoop: a gilded ring (1.825 m radius, as the torus it replaces)
    standing in the XZ plane, with raised bands every 30 degrees."""
    ring = torus("ring", 1.825, 0.16, m["gold"], rot=(math.pi / 2, 0, 0), seg=72, minor_seg=14)
    bands = []
    for i in range(12):
        a = i * math.pi / 6
        b = torus("b%d" % i, 0.19, 0.035, m["gold"], seg=20, minor_seg=8)
        b.rotation_euler = (0, -a, 0)
        b.rotation_mode = "XYZ"
        b.location = (math.cos(a) * 1.825, 0, math.sin(a) * 1.825)
        b.rotation_euler = (math.pi / 2, a + math.pi / 2, 0)
        bands.append(b)
    finish("goal_ring", [ring] + bands)


def broom_stand(m):
    """The broom rack's stand: two posts, a top rail and a base board in dark wood, at the
    sizes BroomRack placed its boxes (2 m wide, posts 2 m tall)."""
    parts = [box("post_l", (0.1, 0.1, 2.0), (-0.95, 0.15, 1.0), m["wood"], bevel=0.015),
             box("post_r", (0.1, 0.1, 2.0), (0.95, 0.15, 1.0), m["wood"], bevel=0.015),
             box("rail", (2.0, 0.1, 0.08), (0, 0.15, 1.5), m["wood"], bevel=0.012),
             box("base", (2.0, 0.5, 0.08), (0, 0, 0.04), m["wood"], bevel=0.012)]
    for i in range(5):
        x = -0.8 + i * 0.4
        parts.append(lathe("peg%d" % i, [(0.0, 0.0), (0.018, 0.0), (0.018, 0.12), (0.0, 0.13)], m["wood"], sides=8))
        parts[-1].rotation_euler = (-math.pi / 2, 0, 0)
        parts[-1].location = (x, 0.1, 1.5)
    for o in parts:
        box_uv(o, world=1.0)
    finish("broom_stand", parts)


PIECES = [pressure_plate, pushable_block, statue_plinth, door_jamb, waystone, fragment,
          lever_base, lever_handle, plaque, wall_medallion, goal_ring, broom_stand]


def main():
    global A
    A = args()
    only = set(A.only.split(",")) if A.only else None
    for piece in PIECES:
        if only and piece.__name__ not in only:
            continue
        reset()
        piece(mats())


main()

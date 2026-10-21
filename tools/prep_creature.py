"""Turns a raw Meshy creature into the game's paddock creature / familiar: welds it,
sizes it and decimates it (keeping Meshy's UVs and texture); it keeps Meshy's facing
(-Y here, +Z in the game, so the game turns it to look along -Z). With --wings it also cuts the wings
off the body at `--wings` metres either side of the centre (after sizing) into their
own meshes, `wing_l` and `wing_r`, each with its origin on the hinge, so the game can
flap them. Runs inside Blender, headless:

  blender -b --factory-startup --python tools/prep_creature.py -- \
      --src .godot/meshy_src/batch5/glimmerwing_raw.glb \
      --out assets/models/creatures/glimmerwing.glb --height 0.3 --tris 6000 [--wings 0.04] [--weld 0.002]

--height is the creature's height in metres (origin at its feet, centred).
"""
import argparse
import sys

import bmesh
import bpy
import numpy as np


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--height", type=float, required=True)
    p.add_argument("--tris", type=int, default=6000)
    p.add_argument("--wings", type=float, default=0.0)
    p.add_argument("--weld", type=float, default=0.0001, help="weld distance as a share of the height")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def select(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def main():
    a = args()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=a.src)
    o = [x for x in bpy.data.objects if x.type == "MESH"][0]
    o.parent = None
    select(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.empty(len(o.data.vertices) * 3, np.float32)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    s = a.height / np.ptp(co[:, 2])
    o.location = (co[:, 0].mean() * s, co[:, 1].mean() * s, -co[:, 2].min() * s)
    o.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=a.weld * a.height)
    bpy.ops.object.mode_set(mode="OBJECT")
    o.name = "body"
    parts = [o]
    if a.wings > 0:
        for side, name in ((1, "wing_l"), (-1, "wing_r")):
            w = o.copy()
            w.data = o.data.copy()
            bpy.context.scene.collection.objects.link(w)
            w.name = name
            bm = bmesh.new()
            bm.from_mesh(w.data)
            # Facing -Y, the creature's left is +X.
            keep = lambda f: side * f.calc_center_median().x > a.wings
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(f)], context="FACES")
            bm.to_mesh(w.data)
            bm.free()
            vs = np.array([v.co[:] for v in w.data.vertices])
            hinge = (side * a.wings, float(np.median(vs[:, 1])), float(np.median(vs[:, 2])))
            w.data.transform(__import__("mathutils").Matrix.Translation([-c for c in hinge]))
            w.location = hinge
            parts.append(w)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.calc_center_median().x) > a.wings], context="FACES")
        bm.to_mesh(o.data)
        bm.free()
    # Decimate each part to its share (wings a fifth each) in steps of at most 5x: one
    # big collapse smears fine texture detail (the mossling's eyes); gradual ones keep it.
    for p in parts:
        select(p)
        share = a.tris * (0.2 if p.name.startswith("wing") else (0.6 if a.wings > 0 else 1.0))
        for _ in range(8):
            n = sum(len(f.vertices) - 2 for f in p.data.polygons)
            if n <= share * 1.1:
                break
            m = p.modifiers.new("dec", "DECIMATE")
            m.ratio = max(share / n, 0.2)
            bpy.ops.object.modifier_apply(modifier="dec")
        bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.ops.export_scene.gltf(filepath=a.out, use_selection=True, export_format="GLB",
                              export_image_format="WEBP", export_image_quality=88)
    print("CREATURE %s: %s" % (a.out, ", ".join("%s %d tris" % (p.name, sum(len(f.vertices) - 2 for f in p.data.polygons)) for p in parts)))


main()

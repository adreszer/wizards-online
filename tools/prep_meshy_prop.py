"""Turns a raw Meshy export (hundreds of thousands of triangles) into a game-ready prop:
welds it, scales it and decimates it, keeping Meshy's own UVs and textures. Runs inside
Blender, headless:

  blender -b --factory-startup --python tools/prep_meshy_prop.py -- \
      --src /abs/raw.glb --out assets/models/environment/modular/sofa.glb \
      --tris 12000 [--scale 1.4,1,1.4]

The weld matters: glTF arrives split along every seam of Meshy's texture atlas, and
decimating those loose fragments leaves bright, stretched slivers all over the texture.
--scale is applied in Blender axes (Z up, the model's front facing -Y) before decimating.
"""
import argparse
import os
import sys

import bpy


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--tris", type=int, default=10000)
    p.add_argument("--scale", default="1,1,1")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return p.parse_args(argv)


def main():
    a = args()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=a.src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise SystemExit(f"expected one mesh in {a.src}, found {len(meshes)}")
    o = meshes[0]
    o.parent = None
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode="OBJECT")
    o.location = (0, 0, 0)
    o.scale = [float(v) for v in a.scale.split(",")]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    dec = o.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = min(1.0, a.tris / tris)
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    o.name = os.path.splitext(os.path.basename(a.out))[0]
    bpy.ops.export_scene.gltf(filepath=a.out, use_selection=True, export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=90)
    print(f"PREPPED {a.out}: {tris} -> {sum(len(p.vertices) - 2 for p in o.data.polygons)} tris, "
          f"size {[round(v, 3) for v in o.dimensions]}")


main()

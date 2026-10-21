"""Re-exports a glb with its textures scaled down (longest side at most --size) and
stored as WebP: Meshy hands out 2048 px maps even for a hand-sized prop. Runs inside
Blender, headless:

  blender -b --factory-startup --python tools/shrink_textures.py -- --size 1024 a.glb b.glb …
"""
import argparse
import sys

import bpy


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("files", nargs="+")
    a = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    for path in a.files:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        for im in list(bpy.data.images):
            bpy.data.images.remove(im)
        bpy.ops.import_scene.gltf(filepath=path)
        for im in bpy.data.images:
            w, h = im.size
            if max(w, h) > a.size:
                f = a.size / max(w, h)
                im.scale(max(1, int(w * f)), max(1, int(h * f)))
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                                  export_image_format="WEBP", export_image_quality=85)
        print("SHRUNK", path)


main()

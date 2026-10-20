"""Paints a portrait: renders a sitter in the portrait studio (85 mm lens, dark warm
backdrop, warm key, cool fill and a rim light, Eevee + AgX) and gives it an oil
varnish (softened, warmed, gentle contrast, vignette). Runs inside Blender, headless:

  blender -b --factory-startup --python tools/render_portrait.py -- \
      --src assets/models/portraits/sitter_03.glb \
      --out assets/textures/portraits/portrait_03.jpg [--pose relaxed] [--bust]

--pose relaxed lowers a rigged sitter's arms from a T-pose and folds the hands in
front (sitters are generated in a T-pose so they rig cleanly). --bust frames the
whole model instead of the head and upper body.
"""
import argparse
import math
import sys

import bpy
import numpy as np
from mathutils import Vector

# Pose directions in world space (Blender: Z up, the sitter faces -Y; its right is -X).
RELAXED = {
    "RightArm": (-0.14, -0.22, -1.0), "RightForeArm": (0.6, -0.72, -0.3), "RightHand": (0.7, -0.6, -0.35),
    "LeftArm": (0.14, -0.22, -1.0), "LeftForeArm": (-0.6, -0.72, -0.3), "LeftHand": (-0.7, -0.6, -0.35),
}


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--pose", default="")
    p.add_argument("--bust", action="store_true")
    p.add_argument("--size", default="768,980")
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def look_at(ob, target):
    ob.rotation_euler = (target - ob.location).to_track_quat("-Z", "Y").to_euler()


def pose(rig, dirs):
    to_rig = rig.matrix_world.inverted().to_3x3()
    for suffix, d in dirs.items():
        pb = next(b for b in rig.pose.bones if b.name.endswith(":" + suffix) or b.name == suffix)
        bpy.context.view_layer.update()
        cur = (pb.tail - pb.head).normalized()
        turn = cur.rotation_difference((to_rig @ Vector(d)).normalized())
        m = turn.to_matrix().to_4x4() @ pb.matrix
        m.translation = pb.matrix.translation
        pb.matrix = m
    bpy.context.view_layer.update()


def light(name, energy, size, color, at, target):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.size, data.color = energy, size, color
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = at
    look_at(ob, target)


def varnish(path_in, path_out):
    im = bpy.data.images.load(path_in)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = a[..., :3]
    # Soften a little (3x3 box) to lose the CG crispness.
    pad = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), mode="edge")
    soft = sum(pad[y:y + h, x:x + w] for y in range(3) for x in range(3)) / 9
    rgb = rgb * 0.55 + soft * 0.45
    # Varnish: warmer, lower blues, a gentle contrast curve, then a vignette.
    rgb = np.clip(rgb * np.array([1.02, 0.95, 0.80]), 0, 1)
    rgb = rgb * rgb * (3 - 2 * rgb) * 0.35 + rgb * 0.65
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h * 0.55) / (h / 2)) ** 2)
    rgb = rgb * np.clip(1.0 - 0.45 * np.clip(d - 0.45, 0, 1) ** 1.4, 0, 1)[..., None]
    a[..., :3] = np.clip(rgb, 0, 1)
    a[..., 3] = 1
    out = bpy.data.images.new("varnished", w, h, alpha=False)
    out.pixels.foreach_set(a.ravel())
    out.filepath_raw = path_out
    out.file_format = "JPEG"
    bpy.context.scene.render.image_settings.quality = 90
    out.save()


def main():
    a = args()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=a.src)
    rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if a.pose == "relaxed" and rig is not None:
        pose(rig, RELAXED)
    bpy.context.view_layer.update()
    pts = []
    for o in bpy.data.objects:
        if o.type == "MESH":
            ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
            pts += [ev.matrix_world @ v.co for v in ev.to_mesh().vertices]
    top, bot = max(p.z for p in pts), min(p.z for p in pts)
    cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2
    cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2
    h = top - bot
    span = h * 1.08 if a.bust else h * 0.42
    tgt = Vector((cx, cy, (top + bot) / 2 if a.bust else top - span * 0.47))
    s = span

    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens, cam_data.sensor_fit, cam_data.sensor_height = 85, "VERTICAL", 24
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = tgt + Vector((0, -span * 3.53, span * 0.05))
    look_at(cam, tgt)
    sc.camera = cam
    light("key", 390 * s * s, 1.2, (1.0, 0.86, 0.68), tgt + Vector((-1.3 * s, -1.6 * s, 1.0 * s)), tgt)
    light("fill", 14 * s * s, 2.0, (0.75, 0.82, 1.0), tgt + Vector((1.6 * s, -1.4 * s, 0.2 * s)), tgt)
    light("rim", 192 * s * s, 0.8, (1.0, 0.8, 0.6), tgt + Vector((1.0 * s, 1.4 * s, 0.9 * s)), tgt)
    bpy.ops.mesh.primitive_plane_add(size=1, location=tgt + Vector((0, 1.2 * s + 0.5, 0)), rotation=(math.radians(90), 0, 0))
    backdrop = bpy.context.active_object
    backdrop.scale = (6 * s, 6 * s, 1)
    mat = bpy.data.materials.new("backdrop")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (0.045, 0.03, 0.018, 1)
    nt.links.new(em.outputs[0], next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL").inputs[0])
    backdrop.data.materials.append(mat)
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.012, 0.009, 0.007, 1)

    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    try:
        sc.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    sc.render.resolution_x, sc.render.resolution_y = (int(v) for v in a.size.split(","))
    sc.render.image_settings.file_format = "PNG"
    raw = bpy.app.tempdir + "portrait_raw.png"
    sc.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    varnish(raw, a.out)
    print(f"PAINTED {a.out}")


main()

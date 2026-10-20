"""Rigs a portrait sitter with a Mixamo-named skeleton in Blender, for figures that
Mixamo's auto-rigger rejects (arms hanging against a robe). Runs headless:

  blender -b --factory-startup --python tools/rig_sitter.py -- \
      --src sitter_01.fbx --out assets/models/portraits/sitter_01.glb --joints '{...}'

--src is a sitter already scaled to 1.8 m, feet on the ground, front facing -Y.
--joints are landmarks read off a front orthographic render (512 px, 2 m wide,
centred at height 0.95 m): "top" (head top, under any hat), "chin", "hip" (heights,
in px rows), "shoulder"/"elbow"/"wrist" ([[x, y] right, [x, y] left], character
right on screen left), "feet" ([x right, x left]) and optionally "arm_radius"
([near, far] metres, default 0.09, 0.15: how far cloth beside the arm still follows it). Depth comes from the mesh
itself (the middle of the slice at each joint). Bones are the standard Mixamo set
without fingers, so SocialPose and Mixamo clips drive them like the player rigs.
Skinning is Blender's automatic (heat) weights; vertices it misses go to the
nearest bone, and arm weight is faded off cloth hanging away from the arm.
"""
import argparse
import json
import sys

import bpy
from mathutils import Vector
from mathutils.geometry import intersect_point_line


def seg_dist(co, bone):
    """Distance from a point to a bone (name, head, tail) segment."""
    p, t = intersect_point_line(co, bone[1], bone[2])
    p = bone[1] if t < 0 else bone[2] if t > 1 else p
    return (co - p).length


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--joints", required=True)
    return p.parse_args(sys.argv[sys.argv.index("--") + 1:])


def main():
    a = args()
    j = json.loads(a.joints)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    if a.src.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=a.src)
    else:
        bpy.ops.import_scene.gltf(filepath=a.src)
    mesh = [o for o in bpy.data.objects if o.type == "MESH"][0]
    for o in list(bpy.data.objects):
        if o is not mesh:
            bpy.data.objects.remove(o)
    verts = [mesh.matrix_world @ v.co for v in mesh.data.vertices]

    def x_of(px):
        return (px - 256) / 256

    def z_of(py):
        return 0.95 + (256 - py) / 256

    def depth(x, z, r=0.05):
        ys = [v.y for v in verts if abs(v.x - x) < r and abs(v.z - z) < r]
        while not ys and r < 0.3:
            r *= 1.6
            ys = [v.y for v in verts if abs(v.x - x) < r and abs(v.z - z) < r]
        return (min(ys) + max(ys)) / 2 if ys else 0.0

    def at(x, z):
        return Vector((x, depth(x, z), z))

    top, chin, hip = z_of(j["top"]), z_of(j["chin"]), z_of(j["hip"])
    sh = [Vector((x_of(p[0]), 0, z_of(p[1]))) for p in j["shoulder"]]
    el = [Vector((x_of(p[0]), 0, z_of(p[1]))) for p in j["elbow"]]
    wr = [Vector((x_of(p[0]), 0, z_of(p[1]))) for p in j["wrist"]]
    feet = [x_of(f) for f in j["feet"]]
    neck_z = (sh[0].z + sh[1].z) / 2 + 0.04
    pts = {
        "Hips": at(0, hip),
        "Spine": at(0, hip + (neck_z - hip) * 0.22),
        "Spine1": at(0, hip + (neck_z - hip) * 0.46),
        "Spine2": at(0, hip + (neck_z - hip) * 0.7),
        "Neck": at(0, neck_z),
        "Head": at(0, chin + 0.03),
        "HeadTop_End": at(0, top),
    }
    ground = min(v.z for v in verts)
    for i, side in enumerate(("Right", "Left")):
        sx = sh[i].x
        pts[side + "Shoulder"] = at(sx * 0.35, neck_z - 0.02)
        pts[side + "Arm"] = at(sh[i].x, sh[i].z)
        pts[side + "ForeArm"] = at(el[i].x, el[i].z)
        pts[side + "Hand"] = at(wr[i].x, wr[i].z)
        hand_dir = (pts[side + "Hand"] - pts[side + "ForeArm"]).normalized()
        pts[side + "Hand_End"] = pts[side + "Hand"] + hand_dir * 0.14
        fx = feet[i]
        hip_x = fx * 0.8
        pts[side + "UpLeg"] = at(hip_x, hip - 0.05)
        pts[side + "Leg"] = at((hip_x + fx) / 2, ground + (hip - ground) * 0.48)
        ankle = at(fx, ground + 0.08)
        pts[side + "Foot"] = ankle
        front = min((v.y for v in verts if abs(v.x - fx) < 0.06 and v.z < ground + 0.12), default=ankle.y - 0.12)
        pts[side + "ToeBase"] = Vector((fx, (ankle.y + front) / 2, ground + 0.03))
        pts[side + "Toe_End"] = Vector((fx, front, ground + 0.03))

    chains = [
        ("Hips", "Spine", None), ("Spine", "Spine1", "Hips"), ("Spine1", "Spine2", "Spine"),
        ("Spine2", "Neck", "Spine1"), ("Neck", "Head", "Spine2"), ("Head", "HeadTop_End", "Neck"),
    ]
    for side in ("Right", "Left"):
        chains += [
            (side + "Shoulder", side + "Arm", "Spine2"), (side + "Arm", side + "ForeArm", side + "Shoulder"),
            (side + "ForeArm", side + "Hand", side + "Arm"), (side + "Hand", side + "Hand_End", side + "ForeArm"),
            (side + "UpLeg", side + "Leg", "Hips"), (side + "Leg", side + "Foot", side + "UpLeg"),
            (side + "Foot", side + "ToeBase", side + "Leg"), (side + "ToeBase", side + "Toe_End", side + "Foot"),
        ]
    arm = bpy.data.armatures.new("Armature")
    rig = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, child, parent in chains:
        b = arm.edit_bones.new("mixamorig:" + name)
        b.head, b.tail = pts[name], pts[child]
        if (b.tail - b.head).length < 0.01:
            b.tail = b.head + Vector((0, 0, 0.05))
        if parent:
            b.parent = arm.edit_bones["mixamorig:" + parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    bones = [(b.name, b.head_local, b.tail_local) for b in arm.bones]
    missed = 0
    for v in mesh.data.vertices:
        if any(g.weight > 0.001 for g in v.groups):
            continue
        missed += 1
        co = mesh.matrix_world @ v.co
        name = min(bones, key=lambda b: seg_dist(co, b))[0]
        group = mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
        group.add([v.index], 1.0, "REPLACE")
    # Heat weights tie robe panels and aprons that hang by the hands to the arm bones,
    # so a raised arm drags them up. Arm influence fades out between NEAR and FAR from
    # the arm itself; what it loses goes to the nearest torso bone.
    near, far = j.get("arm_radius", (0.09, 0.15))
    limb = {b[0]: b for b in bones if any(k in b[0] for k in ("Arm", "Hand"))}
    torso = [b for b in bones if b[0].split(":")[-1] in ("Hips", "Spine", "Spine1", "Spine2")]
    index = {g.index: g.name for g in mesh.vertex_groups}
    trimmed = 0
    for v in mesh.data.vertices:
        co = mesh.matrix_world @ v.co
        moved = 0.0
        for g in v.groups:
            name = index[g.group]
            if name not in limb or g.weight <= 0.0:
                continue
            side = "Right" if "Right" in name else "Left"
            reach = min(seg_dist(co, b) for n, b in limb.items() if side in n)
            keep = max(0.0, min(1.0, (far - reach) / (far - near)))
            if keep < 1.0:
                moved += g.weight * (1.0 - keep)
                g.weight *= keep
        if moved > 0.0:
            trimmed += 1
            name = min(torso, key=lambda b: seg_dist(co, b))[0]
            mesh.vertex_groups[name].add([v.index], moved, "ADD")
    print(f"RIGGED {a.out}: {len(arm.bones)} bones, {missed} of {len(mesh.data.vertices)} vertices "
          f"nearest-bone, {trimmed} pulled off the arms")
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=a.out, use_selection=True, export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=90, export_animations=False)


main()

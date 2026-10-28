"""Writes a prop's wrapper scene from its GLB's bounds, the kit's convention: origin at
the back-bottom-centre, front toward +Z, a box collider round it (unless --no-collide:
clutter that lies on tables), optionally lifted (--lift, wall-hung shelves).

  python3 tools/wrap_prop.py assets/models/environment/dress/bench.glb \\
      objects/environment/props/dress/bench.tscn [--no-collide] [--lift 1.2] [--turn]

--turn faces the model the other way (for models that come out looking along -Z).
"""
import argparse
import json
import os
import struct


def bounds(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    lo, hi = [1e9] * 3, [-1e9] * 3

    def visit(index, scale, offset):
        node = gltf["nodes"][index]
        s = node.get("scale", [1, 1, 1])
        t = node.get("translation", [0, 0, 0])
        scale = [scale[i] * s[i] for i in range(3)]
        offset = [offset[i] + t[i] for i in range(3)]
        if "mesh" in node:
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                acc = gltf["accessors"][prim["attributes"]["POSITION"]]
                for i in range(3):
                    lo[i] = min(lo[i], acc["min"][i] * scale[i] + offset[i])
                    hi[i] = max(hi[i], acc["max"][i] * scale[i] + offset[i])
        for child in node.get("children", []):
            visit(child, scale, offset)

    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        visit(root, [1, 1, 1], [0, 0, 0])
    return lo, hi


def main():
    p = argparse.ArgumentParser()
    p.add_argument("glb")
    p.add_argument("out")
    p.add_argument("--no-collide", action="store_true")
    p.add_argument("--lift", type=float, default=0.0)
    p.add_argument("--turn", action="store_true")
    a = p.parse_args()
    lo, hi = bounds(a.glb)
    size = [hi[i] - lo[i] for i in range(3)]
    cx = (lo[0] + hi[0]) / 2
    cz = (lo[2] + hi[2]) / 2
    name = "".join(w.title() for w in os.path.splitext(os.path.basename(a.out))[0].split("_"))
    res = "res://" + os.path.relpath(a.glb).replace(os.sep, "/")
    half = size[2] / 2
    if a.turn:
        basis = "-1, 0, 0, 0, 1, 0, 0, 0, -1"
        model = (cx, a.lift - lo[1], half + cz)
    else:
        basis = "1, 0, 0, 0, 1, 0, 0, 0, 1"
        model = (-cx, a.lift - lo[1], half - cz)
    f = lambda v: ", ".join("%.4g" % x for x in v)
    root_type = "Node3D" if a.no_collide else "StaticBody3D"
    out = ["[gd_scene load_steps=%d format=3]" % (2 if a.no_collide else 3), "",
           '[ext_resource type="PackedScene" path="%s" id="1"]' % res, ""]
    if not a.no_collide:
        out += ['[sub_resource type="BoxShape3D" id="Shape"]', "size = Vector3(%s)" % f(size), ""]
    out += ['[node name="%s" type="%s"]' % (name, root_type)]
    if not a.no_collide:
        out += ["collision_layer = 1", "collision_mask = 0"]
    out += ["", '[node name="Model" parent="." instance=ExtResource("1")]',
            "transform = Transform3D(%s, %s)" % (basis, f(model))]
    if not a.no_collide:
        out += ["", '[node name="Shape" type="CollisionShape3D" parent="."]',
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s)" % f((0, a.lift + size[1] / 2, half)),
                'shape = SubResource("Shape")']
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out, "w").write("\n".join(out) + "\n")
    print("%s: %.2f x %.2f x %.2f m" % (a.out, size[0], size[1], size[2]))


if __name__ == "__main__":
    main()

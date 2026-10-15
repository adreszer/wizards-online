"""Placeholder props for the dressing pass, written as plain scenes (no script) so
StaticBatch draws them as MultiMeshes. Each is a kit role (content/castle/kit.json,
"props"): replace the path with a real model's wrapper and every instance restyles.

A recipe is a list of parts (shape, size, centre, colour); shapes: box, cyl (size = radius,
height, radius), sphere (size = radius). The prop's origin is its back-bottom-centre: +Z
faces into the room, like the castle's other wall props. Collision: one box around the
solid parts (rugs, banners, portraits and tapestries have none).
"""
import os

OUT = "objects/environment/placeholders"
WOOD = (0.42, 0.29, 0.18); DARK_WOOD = (0.28, 0.19, 0.12); IRON = (0.2, 0.2, 0.22); STONE = (0.55, 0.53, 0.5)
CLOTH = (0.55, 0.12, 0.12); BRASS = (0.72, 0.56, 0.25); GLASS = (0.55, 0.7, 0.8); GREEN = (0.2, 0.45, 0.18)
LINEN = (0.85, 0.82, 0.74); PARCH = (0.82, 0.74, 0.55); ASH = (0.18, 0.16, 0.15)
HOUSE = {1: (0.62, 0.16, 0.12), 2: (0.78, 0.62, 0.18), 3: (0.82, 0.4, 0.14), 4: (0.16, 0.36, 0.66)}

RECIPES = {
    "bed": [("box", (1.2, 0.45, 2.2), (0, 0.35, 1.1), WOOD), ("box", (1.15, 0.2, 2.1), (0, 0.65, 1.1), LINEN),
            ("box", (1.2, 1.1, 0.1), (0, 0.55, 0.05), DARK_WOOD), ("box", (0.6, 0.12, 0.35), (0, 0.8, 0.35), LINEN)],
    "trunk": [("box", (0.9, 0.5, 0.5), (0, 0.25, 0.25), DARK_WOOD), ("box", (0.92, 0.06, 0.52), (0, 0.5, 0.25), IRON)],
    "wardrobe": [("box", (1.4, 2.2, 0.6), (0, 1.1, 0.3), DARK_WOOD), ("box", (0.05, 1.6, 0.02), (0, 1.1, 0.61), BRASS)],
    "armchair": [("box", (0.9, 0.45, 0.85), (0, 0.22, 0.45), CLOTH), ("box", (0.9, 0.8, 0.2), (0, 0.65, 0.1), CLOTH),
                 ("box", (0.15, 0.3, 0.85), (-0.38, 0.55, 0.45), CLOTH), ("box", (0.15, 0.3, 0.85), (0.38, 0.55, 0.45), CLOTH)],
    "sofa": [("box", (2.0, 0.45, 0.9), (0, 0.22, 0.45), CLOTH), ("box", (2.0, 0.8, 0.2), (0, 0.65, 0.1), CLOTH)],
    "hearth": [("box", (2.8, 2.4, 0.8), (0, 1.2, 0.4), STONE), ("box", (1.6, 1.2, 0.6), (0, 0.6, 0.62), ASH),
               ("box", (3.0, 0.25, 1.0), (0, 2.4, 0.5), STONE)],
    "rug": [("box", (3.0, 0.03, 2.0), (0, 0.015, 1.0), CLOTH)],
    "table": [("box", (2.0, 0.08, 1.0), (0, 0.78, 0.5), WOOD), ("box", (0.1, 0.75, 0.1), (-0.9, 0.37, 0.1), WOOD),
              ("box", (0.1, 0.75, 0.1), (0.9, 0.37, 0.1), WOOD), ("box", (0.1, 0.75, 0.1), (-0.9, 0.37, 0.9), WOOD),
              ("box", (0.1, 0.75, 0.1), (0.9, 0.37, 0.9), WOOD)],
    "chair": [("box", (0.5, 0.06, 0.5), (0, 0.45, 0.25), WOOD), ("box", (0.5, 0.6, 0.06), (0, 0.75, 0.03), WOOD),
              ("box", (0.06, 0.45, 0.06), (-0.2, 0.22, 0.45), WOOD), ("box", (0.06, 0.45, 0.06), (0.2, 0.22, 0.45), WOOD)],
    "cabinet": [("box", (1.6, 2.0, 0.5), (0, 1.0, 0.25), DARK_WOOD), ("box", (1.4, 1.4, 0.02), (0, 1.2, 0.51), GLASS),
                ("box", (0.3, 0.35, 0.2), (-0.4, 1.0, 0.3), BRASS), ("box", (0.25, 0.3, 0.2), (0.35, 1.45, 0.3), BRASS)],
    "barrel": [("cyl", (0.4, 0.95, 0.4), (0, 0.48, 0.45), WOOD)],
    "crate": [("box", (0.8, 0.8, 0.8), (0, 0.4, 0.45), WOOD)],
    "cauldron": [("cyl", (0.45, 0.6, 0.35), (0, 0.4, 0.5), IRON), ("cyl", (0.4, 0.05, 0.4), (0, 0.68, 0.5), GREEN)],
    "workbench": [("box", (2.4, 0.1, 0.9), (0, 0.9, 0.45), WOOD), ("box", (2.3, 0.85, 0.8), (0, 0.42, 0.45), DARK_WOOD)],
    "plant_pot": [("cyl", (0.3, 0.4, 0.22), (0, 0.2, 0.35), (0.5, 0.3, 0.2)), ("sphere", (0.35,), (0, 0.65, 0.35), GREEN)],
    "globe": [("cyl", (0.25, 0.8, 0.3), (0, 0.4, 0.4), WOOD), ("sphere", (0.4,), (0, 1.15, 0.4), (0.3, 0.45, 0.6))],
    "telescope": [("cyl", (0.06, 1.2, 0.06), (0, 0.6, 0.5), WOOD), ("cyl", (0.12, 1.6, 0.08), (0, 1.35, 0.6), BRASS)],
    "pedestal": [("box", (0.7, 1.0, 0.7), (0, 0.5, 0.4), STONE), ("sphere", (0.25,), (0, 1.25, 0.4), GLASS)],
    "rune_stone": [("box", (0.7, 1.6, 0.3), (0, 0.8, 0.3), STONE)],
    "dummy": [("cyl", (0.08, 1.2, 0.08), (0, 0.6, 0.4), WOOD), ("box", (0.6, 0.8, 0.3), (0, 1.4, 0.4), PARCH), ("sphere", (0.2,), (0, 2.0, 0.4), PARCH)],
    "staff_rack": [("box", (1.6, 0.1, 0.3), (0, 1.4, 0.15), WOOD), ("cyl", (0.03, 1.8, 0.03), (-0.5, 0.9, 0.2), WOOD),
                   ("cyl", (0.03, 1.8, 0.03), (0.0, 0.9, 0.2), WOOD), ("cyl", (0.03, 1.8, 0.03), (0.5, 0.9, 0.2), WOOD)],
    "cage": [("box", (1.2, 1.2, 1.2), (0, 0.6, 0.65), (0.3, 0.28, 0.25))],
    "crystal_table": [("cyl", (0.45, 0.8, 0.45), (0, 0.4, 0.5), DARK_WOOD), ("sphere", (0.22,), (0, 1.0, 0.5), GLASS)],
    "abacus": [("box", (1.0, 0.8, 0.1), (0, 1.0, 0.1), WOOD), ("box", (0.9, 0.05, 0.08), (0, 1.1, 0.16), BRASS)],
    "candelabra": [("cyl", (0.05, 1.4, 0.05), (0, 0.7, 0.3), BRASS), ("box", (0.6, 0.05, 0.05), (0, 1.4, 0.3), BRASS)],
    "statue": [("box", (1.0, 0.6, 1.0), (0, 0.3, 0.6), STONE), ("cyl", (0.35, 1.8, 0.3), (0, 1.5, 0.6), STONE), ("sphere", (0.28,), (0, 2.6, 0.6), STONE)],
    "armour": [("box", (0.7, 0.2, 0.5), (0, 0.1, 0.4), STONE), ("cyl", (0.3, 1.2, 0.25), (0, 1.0, 0.4), IRON), ("sphere", (0.2,), (0, 1.8, 0.4), IRON)],
    "portrait": [("box", (1.2, 1.5, 0.08), (0, 2.2, 0.04), BRASS), ("box", (1.0, 1.3, 0.02), (0, 2.2, 0.09), (0.35, 0.28, 0.22))],
    "tapestry": [("box", (2.4, 3.2, 0.04), (0, 2.6, 0.03), (0.42, 0.18, 0.2))],
    "chest": [("box", (1.0, 0.6, 0.6), (0, 0.3, 0.32), DARK_WOOD), ("box", (1.02, 0.08, 0.62), (0, 0.6, 0.32), BRASS)],
    "high_table": [("box", (6.0, 0.1, 1.2), (0, 0.85, 0.6), DARK_WOOD), ("box", (5.8, 0.8, 1.0), (0, 0.4, 0.6), DARK_WOOD)],
}
for h, colour in HOUSE.items():
    RECIPES[f"banner_h{h}"] = [("box", (1.4, 3.0, 0.04), (0, 3.4, 0.03), colour), ("box", (1.6, 0.08, 0.08), (0, 4.95, 0.06), BRASS)]
NO_COLLISION = ("rug", "portrait", "tapestry") + tuple(f"banner_h{h}" for h in HOUSE)


def scene_text(kind, parts):
    subs, nodes, n = [], [], 0
    mats = {}
    lo = [1e9, 1e9, 1e9]; hi = [-1e9, -1e9, -1e9]
    for shape, size, centre, colour in parts:
        n += 1
        if colour not in mats:
            mats[colour] = f"M{len(mats) + 1}"
            subs.append(f'[sub_resource type="StandardMaterial3D" id="{mats[colour]}"]\nalbedo_color = Color({colour[0]}, {colour[1]}, {colour[2]}, 1)\nroughness = 0.85\n')
        if shape == "box":
            subs.append(f'[sub_resource type="BoxMesh" id="P{n}"]\nsize = Vector3({size[0]}, {size[1]}, {size[2]})\n')
            ext = (size[0] / 2, size[1] / 2, size[2] / 2)
        elif shape == "cyl":
            subs.append(f'[sub_resource type="CylinderMesh" id="P{n}"]\ntop_radius = {size[2]}\nbottom_radius = {size[0]}\nheight = {size[1]}\nradial_segments = 12\n')
            ext = (max(size[0], size[2]), size[1] / 2, max(size[0], size[2]))
        else:
            subs.append(f'[sub_resource type="SphereMesh" id="P{n}"]\nradius = {size[0]}\nheight = {size[0] * 2}\nradial_segments = 12\nrings = 6\n')
            ext = (size[0], size[0], size[0])
        for i in range(3):
            lo[i] = min(lo[i], centre[i] - ext[i]); hi[i] = max(hi[i], centre[i] + ext[i])
        nodes.append(f'[node name="Part{n}" type="MeshInstance3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {centre[0]}, {centre[1]}, {centre[2]})\n'
                     f'mesh = SubResource("P{n}")\nsurface_material_override/0 = SubResource("{mats[colour]}")\n')
    if kind not in NO_COLLISION:
        subs.append(f'[sub_resource type="BoxShape3D" id="Shape"]\nsize = Vector3({hi[0] - lo[0]:.3f}, {hi[1] - lo[1]:.3f}, {hi[2] - lo[2]:.3f})\n')
        nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, '
                     f'{(lo[0] + hi[0]) / 2:.3f}, {(lo[1] + hi[1]) / 2:.3f}, {(lo[2] + hi[2]) / 2:.3f})\nshape = SubResource("Shape")\n')
    head = f'[gd_scene load_steps={len(subs) + 1} format=3 uid="uid://ph{kind.replace("_", "")[:16]}"]\n\n'
    root = f'[node name="{kind.title().replace("_", "")}" type="StaticBody3D"]\ncollision_layer = 1\ncollision_mask = 0\n\n'
    return head + "\n".join(subs) + "\n" + root + "\n".join(nodes)


def write_all():
    os.makedirs(OUT, exist_ok=True)
    for kind, parts in RECIPES.items():
        with open(os.path.join(OUT, f"{kind}.tscn"), "w") as f:
            f.write(scene_text(kind, parts))
    return {k: f"res://{OUT}/{k}.tscn" for k in RECIPES}

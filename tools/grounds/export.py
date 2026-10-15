"""Writes the grounds for Godot: levels/grounds/{terrain.json, height.bin, splat.png,
scatter.bin} and levels/grounds/grounds.tscn (terrain, water, flora, greybox landmarks).

height.bin: gzip of int32 little-endian, row-major [z][x], h = min + q * (max - min) / 65535.
scatter.bin: float32 rows (x, y, z, yaw, scale), kinds back to back; offsets in terrain.json.
"""
import gzip
import json
import math
import os
import struct
import zlib

import numpy as np

OUT_DIR = "levels/grounds"
RES = "res://levels/grounds/"


def write_png(path, rgba):
    h, w, c = rgba.shape
    color_type = {3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + rgba[i].tobytes() for i in range(h))
    def chunk(t, d):
        out = struct.pack(">I", len(d)) + t + d
        return out + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_data(g, out_dir=OUT_DIR):
    os.makedirs(out_dir, exist_ok=True)
    T = g.terrain
    hmin, hmax = float(np.floor(T.H.min())), float(np.ceil(T.H.max()))
    q = np.round((T.H - hmin) / (hmax - hmin) * 65535).astype("<i4")
    raw = q.tobytes()
    with open(os.path.join(out_dir, "height.bin"), "wb") as f:
        f.write(gzip.compress(raw, compresslevel=9, mtime=0))
    write_png(os.path.join(out_dir, "splat.png"), g.splat[::2, ::2].copy())
    # Terrain holes: quads whose four corners lie inside a castle room that has its own
    # floor at or below the ground floor (the castle's floors replace the ground there).
    holes = np.zeros((T.nz - 1, T.nx - 1), np.uint8)
    for (x0, x1, z0, z1) in g.floor_rects:
        inside = (T.X >= x0 - 1e-6) & (T.X <= x1 + 1e-6) & (T.Z >= z0 - 1e-6) & (T.Z <= z1 + 1e-6)
        quad = inside[:-1, :-1] & inside[1:, :-1] & inside[:-1, 1:] & inside[1:, 1:]
        holes |= quad.astype(np.uint8)
    # Underground rooms (dungeons, the boat tunnel): where the terrain dips into the room,
    # cut it away so it never blocks the inside (the exterior shell dresses the opening).
    for (x0, x1, z0, z1), top in g.underground:
        inside = (T.X >= x0 - 1e-6) & (T.X <= x1 + 1e-6) & (T.Z >= z0 - 1e-6) & (T.Z <= z1 + 1e-6)
        low = inside & (T.H < top + 0.6)
        quad = (low[:-1, :-1] | low[1:, :-1] | low[:-1, 1:] | low[1:, 1:]) & \
               inside[:-1, :-1] & inside[1:, :-1] & inside[:-1, 1:] & inside[1:, 1:]
        holes |= quad.astype(np.uint8)
    hraw = holes.tobytes()
    with open(os.path.join(out_dir, "holes.bin"), "wb") as f:
        f.write(gzip.compress(hraw, compresslevel=9, mtime=0))
    offsets = {}
    blob = b""
    for kind in sorted(g.scatter):
        arr = g.scatter[kind]
        offsets[kind] = [len(blob) // 4, int(arr.shape[0])]
        blob += arr.astype("<f4").tobytes()
    with open(os.path.join(out_dir, "scatter.bin"), "wb") as f:
        f.write(blob)
    meta = {
        "origin": [T.x0, T.z0], "spacing": T.sp, "size": [T.nx, T.nz],
        "height_range": [hmin, hmax], "water_level": T.water,
        "height": RES + "height.bin", "height_bytes": len(raw), "holes": RES + "holes.bin", "holes_bytes": len(hraw), "splat": RES + "splat.png", "splat_spacing": T.sp * 2,
        "scatter": RES + "scatter.bin", "scatter_kinds": offsets,
        "paths": {p["id"]: [[round(x, 2), round(float(h), 3), round(z, 2)] for (x, z), h in list(zip(p["route"], p["profile"]))[::4] + [(p["route"][-1], p["profile"][-1])]]
                  for p in g.paths},
        "probes": [[x, round(float(T.height_at(x, z)), 3), z] for x, z in ((0.0, 120.0), (-224.0, -62.0), (430.0, -430.0), (560.0, 80.0), (-92.0, -60.0), (300.0, 600.0))],
        "rivers": [{"id": r["id"], "width": r["width"], "points": [[round(x, 2), round(l, 3), round(z, 2)] for x, z, l in r["points"]]}
                   for r in T.rivers],
    }
    with open(os.path.join(out_dir, "terrain.json"), "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")


# --------------------------------------------------------------------------- scene
class Scene:
    def __init__(self):
        self.ext = {}
        self.subs = []
        self.nodes = []
        self.names = {}

    def ext_id(self, kind, path):
        if (kind, path) not in self.ext:
            self.ext[(kind, path)] = len(self.ext) + 1
        return self.ext[(kind, path)]

    def uname(self, base):
        self.names[base] = self.names.get(base, 0) + 1
        n = self.names[base]
        return base if n == 1 else f"{base}_{n}"

    @staticmethod
    def xf(pos, yaw=0.0, pitch=0.0):
        """Basis rows of Ry(yaw) * Rz(pitch) (the tscn convention, as in the castle builder)."""
        c, s = math.cos(yaw), math.sin(yaw)
        cp, sp = math.cos(pitch), math.sin(pitch)
        rows = (c * cp, -c * sp, s, sp, cp, 0.0, -s * cp, s * sp, c)
        return "Transform3D(" + ", ".join(f"{v:.6f}" for v in rows) + f", {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})"

    def inst(self, name, path, pos, parent="Landmarks", yaw=0.0, props=None, groups=None):
        i = self.ext_id("PackedScene", path)
        g = f' groups=[{", ".join(json.dumps(x) for x in groups)}]' if groups else ""
        body = f'[node name="{self.uname(name)}" parent="{parent}"{g} instance=ExtResource("{i}")]\ntransform = {self.xf(pos, yaw)}\n'
        for k, v in (props or {}).items():
            body += f"{k} = {v}\n"
        self.nodes.append(body)

    def node(self, name, type_, parent=".", pos=None, yaw=0.0, props=None, pitch=0.0, groups=None):
        g = f' groups=[{", ".join(json.dumps(x) for x in groups)}]' if groups else ""
        body = f'[node name="{self.uname(name)}" type="{type_}" parent="{parent}"{g}]\n'
        if pos is not None:
            body += f"transform = {self.xf(pos, yaw, pitch)}\n"
        for k, v in (props or {}).items():
            body += f"{k} = {v}\n"
        self.nodes.append(body)

    def block(self, name, centre, size, parent="Landmarks", yaw=0.0, color=None):
        props = {"size": f"Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})"}
        if color:
            props["color"] = f"Color({color[0]:.3f}, {color[1]:.3f}, {color[2]:.3f}, 1)"
        self.inst(name, KIT["block"], centre, parent, yaw, props)

    def text(self, root_props):
        exts = "".join(f'[ext_resource type="{k}" path="{p}" id="{i}"]\n'
                       for (k, p), i in sorted(self.ext.items(), key=lambda kv: kv[1]))
        header = f'[gd_scene load_steps={len(self.ext) + len(self.subs) + 1} format=3 uid="uid://grounds000001"]\n\n'
        return header + exts + "".join(self.subs) + root_props + "\n".join(self.nodes) + "\n"


KIT = {}
HOUSE_COLOURS = [(0.72, 0.29, 0.23), (0.79, 0.65, 0.25), (0.85, 0.45, 0.23), (0.23, 0.48, 0.72)]
WOOD = (0.45, 0.32, 0.2)
STONE = (0.62, 0.6, 0.56)
ROOF = (0.32, 0.22, 0.2)


def write_scene(g, kit, out_dir=OUT_DIR):
    KIT.clear(); KIT.update(kit["roles"])
    sc = Scene()
    T = g.terrain
    terrain_script = sc.ext_id("Script", "res://gameplay/world/terrain.gd")
    root = (f'\n[node name="Grounds" type="Node3D"]\n\n'
            f'[node name="Terrain" type="Node3D" parent="."]\nscript = ExtResource("{terrain_script}")\n'
            f'data_path = "{RES}terrain.json"\n\n'
            f'[node name="Landmarks" type="Node3D" parent="."]\n\n')
    for lm in g.cfg["landmarks"]:
        emit_landmark(sc, g, lm)
    for br in g.bridges:
        emit_bridge(sc, g, br)
    from . import village
    village.emit(sc, g, KIT)
    with open(os.path.join(out_dir, "grounds.tscn"), "w") as f:
        f.write(sc.text(root))


def ground(g, x, z):
    return float(g.terrain.height_at(x, z))


def emit_landmark(sc, g, lm):
    kind = lm["kind"]
    if kind in ("covered_bridge", "viaduct", "village", "station"):
        return   # built from the path's bridge span (emit_bridge) or by village.py
    x, z = lm["at"]
    yaw = math.radians(lm.get("yaw", 0.0))
    y = ground(g, x, z)
    w, d = lm["size"]
    name = lm["id"].title().replace("_", "")
    if kind == "jetty":
        top = g.terrain.water + 0.9
        # Deck from the shore out over the water, on piles.
        sc.block(name + "Deck", (x - w / 2 + 6, top - 0.2, z), (w + 12, 0.4, d), color=WOOD)
        for i in range(7):
            px = x - w / 2 + 2 + i * (w / 6)
            for pz in (z - d / 2 + 0.4, z + d / 2 - 0.4):
                sc.block(name + "Pile", (px, top - 3.2, pz), (0.5, 6, 0.5), color=WOOD)
        for i in range(4):
            sc.block(name + "Boat", (x - w / 2 + 4 + i * 5.5, g.terrain.water + 0.25, z + d / 2 + 2.2), (4.2, 0.6, 1.6),
                     color=(0.35, 0.25, 0.18))
        sc.inst(name + "Lantern", KIT["lantern_post"], (x - w / 2 - 2, top, z - d / 2 + 0.5))
        sc.inst(name + "Lantern", KIT["lantern_post"], (x + w / 2 + 4, top, z - d / 2 + 0.5))
    elif kind in ("boathouse", "cottage"):
        h = 7 if kind == "boathouse" else 5
        sc.block(name + "Walls", (x, y + h / 2 - 0.5, z), (w, h + 1, d), color=WOOD if kind == "boathouse" else STONE)
        sc.block(name + "Roof", (x, y + h + 0.8, z), (w + 1.6, 1.6, d + 1.6), color=ROOF)
        sc.block(name + "Ridge", (x, y + h + 2.1, z), (w + 1.2, 1.2, d * 0.5), color=ROOF)
        if kind == "cottage":
            sc.block(name + "Chimney", (x + w / 2 - 2, y + h + 2.5, z), (1.4, 4, 1.4), color=STONE)
            sc.block(name + "Garden", (x, y + 0.4, z + d / 2 + 5), (w, 0.8, 6), color=(0.35, 0.28, 0.18))
        sc.inst(name + "Lantern", KIT["lantern_post"], (x - w / 2 - 1.5, y, z + d / 2 + 1.5))
    elif kind == "stone_circle":
        r = w / 2 - 4
        for i in range(12):
            a = i * math.pi / 6
            sx, sz = x + r * math.cos(a), z + r * math.sin(a)
            sy = ground(g, sx, sz)
            sc.block(name + "Stone", (sx, sy + 1.6, sz), (1.3, 4.4 + (i % 3) * 0.6, 0.8), yaw=-a, color=STONE)
        sc.block(name + "Altar", (x, y + 0.5, z), (3, 1, 1.6), color=STONE)
    elif kind == "pitch":
        top = y
        sc.block(name + "Field", (x, top - 0.45, z), (w, 1.0, d), color=(0.3, 0.45, 0.22))
        for end in (-1, 1):
            gx = x + end * (w / 2 - 12)
            for k, (dz, hgt) in enumerate(((-9, 14), (0, 18), (9, 14))):
                sc.block(name + "GoalPole", (gx, top + hgt / 2, z + dz), (0.5, hgt, 0.5), color=(0.8, 0.7, 0.35))
                sc.inst(name + "GoalRing", KIT["goal_ring"], (gx, top + hgt + 2.2, z + dz), yaw=math.pi / 2)
        for side, colours in ((-1, HOUSE_COLOURS[:2]), (1, HOUSE_COLOURS[2:])):
            for k, col in enumerate(colours):
                sx = x + (k - 0.5) * (w / 2)
                sz = z + side * (d / 2 + 8)
                for step in range(4):
                    sc.block(name + "Stand", (sx, top + 1 + step * 2, sz + side * step * 2.2), (w / 2 - 8, 2 + step * 4, 2.4),
                             color=col)
                sc.block(name + "Banner", (sx, top + 13, sz + side * 10), (w / 2 - 12, 4, 0.3), color=col)
    elif kind == "gatehouse":
        for side in (-1, 1):
            sc.block(name + "Tower", (x + side * (w / 2 - 4), y + 7, z), (8, 14, d), color=STONE)
            sc.block(name + "Cap", (x + side * (w / 2 - 4), y + 15, z), (9, 2, d + 1), color=ROOF)
        sc.block(name + "Arch", (x, y + 11, z), (w - 16, 6, d), color=STONE)
        # The gate stands open: the road runs on through it to the village.
        leaf = (w - 16) / 2
        for side in (-1, 1):
            sc.block(name + "Gate", (x + side * (leaf - 0.4), y + 4, z + d / 2 + leaf / 2 - 0.2), (0.6, 8, leaf),
                     color=(0.3, 0.22, 0.15))


def emit_bridge(sc, g, br):
    """A deck between the span's ends, parapets both sides; a covered bridge gets posts and
    a roof, a viaduct stone piers down to the ground."""
    (ax, ay, az), (bx, by, bz) = br["from"], br["to"]
    L = math.hypot(bx - ax, bz - az)
    yaw = math.atan2(-(bz - az), bx - ax)
    rise = by - ay
    w = br["width"]
    covered = br["path"] == "pitch_road"
    name = "CoveredBridge" if covered else "Viaduct"
    deck_t = 1.2
    # Deck: a Railing prism used as a slab (length along +X, rising by `rise`).
    sc.inst(name + "Deck", KIT["railing"], (ax, ay - deck_t, az), yaw=yaw,
            props={"length": f"{L:.3f}", "rise": f"{rise:.3f}", "height": f"{deck_t:.3f}", "thickness": f"{w:.3f}"})
    ux, uz = (bx - ax) / L, (bz - az) / L
    nx, nz = -uz, ux
    for side in (-1, 1):
        px, pz = ax + nx * side * (w / 2 - 0.2), az + nz * side * (w / 2 - 0.2)
        sc.inst(name + "Parapet", KIT["railing"], (px, ay, pz), yaw=yaw,
                props={"length": f"{L:.3f}", "rise": f"{rise:.3f}", "height": "1.2" if not covered else "1.4"})
    n = max(2, int(L // (8 if covered else 16)))
    for i in range(n + 1):
        t = i / n
        cx, cz, cy = ax + (bx - ax) * t, az + (bz - az) * t, ay + rise * t
        if covered:
            for side in (-1, 1):
                sc.block(name + "Post", (cx + nx * side * (w / 2 - 0.2), cy + 2.6, cz + nz * side * (w / 2 - 0.2)), (0.4, 5.2, 0.4),
                         yaw=yaw, color=WOOD)
        elif 0 < i < n:
            gy = ground(g, cx, cz)
            hgt = cy - deck_t - gy + 2
            if hgt > 1.5:
                sc.block(name + "Pier", (cx, gy - 2 + hgt / 2, cz), (5, hgt, w * 0.8), yaw=yaw, color=STONE)
    if covered:
        sc.inst(name + "RoofSlab", KIT["railing"], (ax, ay + 5.2, az), yaw=yaw,
                props={"length": f"{L:.3f}", "rise": f"{rise:.3f}", "height": "0.5", "thickness": f"{w + 1.6:.3f}"})

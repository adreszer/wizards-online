"""The castle's exterior shell, derived from the plan, the wall units and the terrain.

Writes levels/castle/exterior.json; gameplay/world/castle_exterior.gd builds the meshes
at runtime (merged per material, so the shell costs a handful of draw calls):

  roofs        hipped roofs over every roofed room's uncovered top (wings, halls)
  spires       broach spires on towers and stair turrets
  merlons      battlement lines along roof edges that face the open air, platforms, the forecourt
  buttresses   on the outer walls of tall halls and the library, between the windows
  chimneys     over hearth rooms (common rooms, the kitchens, feast halls)
  bartizans    corner turrets on the outer corners of tall halls' roofs
  corbels      stepped brackets under corbelled rooms
  foundations  a plinth under every ground-floor room, from below the ground to just under the floor
  covers       slabs over underground rooms where the terrain was cut back (the lake gate)
  facade       an outward-facing stone skin on every blank exterior wall module (lit by the
               moon on the outdoor layer, never seen from inside)
  hlod         far-view boxes per room plus window glows, shown beyond the detail range
"""
import json
import math

import numpy as np

from .geometry import STOREY, MODULE_H, T, overlaps, rect_minus_all

ROOF_PITCH = 1.15          # ridge height per metre of half-span
SPIRE_RATIO = 1.7          # spire height per metre of base width
PARAPET_INSET = 0.6        # roofs start this far inside a battlemented edge
OPEN_AIR = ("outdoor", "grounds")


def built(r):
    return not r.get("terrain")


def open_air(r):
    return r.kind in OPEN_AIR or not r.ceiling


def wall_top(r):
    """Height of the top of a room's walls (band filler included for full-height rooms)."""
    return r.top_storey * STOREY + (STOREY if r.rows >= 2 else r.rows * MODULE_H)


def room_at(plan, x, z, storey, exclude=None):
    for r in plan.rooms.values():
        if not built(r) or r.id == exclude:
            continue
        if r.storey <= storey <= r.top_storey and r.x0 < x < r.x1 and r.z0 < z < r.z1:
            if r.inside is not None and any(c.inside == r.id for c in plan.rooms.values()):
                pass
            return r
    return None


def solid_at(plan, x, z, storey):
    """A roofed (not open-air) built room covering (x, z) on that storey, preferring nested rooms."""
    best = None
    for r in plan.rooms.values():
        if not built(r) or open_air(r):
            continue
        if r.storey <= storey <= r.top_storey and r.x0 < x < r.x1 and r.z0 < z < r.z1:
            best = r
    return best


def generate(plan, units, terrain):
    data = {k: [] for k in ("roofs", "spires", "merlons", "buttresses", "chimneys", "bartizans",
                            "corbels", "foundations", "covers", "facade", "hlod", "windows")}
    roofs_and_edges(plan, data)
    platforms(plan, data)
    buttresses(plan, units, data)
    corbels(plan, data)
    foundations(plan, terrain, data)
    covers(plan, terrain, data)
    facade(plan, units, data)
    hlod(plan, units, data)
    return data


def roofs_and_edges(plan, data):
    for r in plan.rooms.values():
        if not built(r) or open_air(r):
            continue
        top = r.top_storey
        above = [o.rect for o in plan.rooms.values() if built(o) and o.storey == top + 1 and overlaps(o, r) and o.inside is None]
        base = wall_top(r)
        for piece in rect_minus_all(r.rect, above):
            x0, x1, z0, z1 = piece
            w, d = x1 - x0, z1 - z0
            if w < 4 or d < 4:
                continue
            edges = exterior_edges(plan, r, piece, top)
            tower = bool(r.get("tower")) or r.kind == "stair_turret"
            for side, a, b in edges:
                data["merlons"].append(edge_line(piece, side, a, b, base))
            inset = {s: (PARAPET_INSET if any(e[0] == s for e in edges) else -0.3) for s in "wens"}
            rx0, rx1 = x0 + inset["w"], x1 - inset["e"]
            rz0, rz1 = z0 + inset["n"], z1 - inset["s"]
            if tower and piece == r.rect:
                half = min(rx1 - rx0, rz1 - rz0) / 2
                data["spires"].append({"centre": [(x0 + x1) / 2, (z0 + z1) / 2], "base": base, "half": round(half, 3),
                                       "height": round(2 * half * SPIRE_RATIO, 3)})
                continue
            span = min(rx1 - rx0, rz1 - rz0)
            data["roofs"].append({"rect": [round(v, 3) for v in (rx0, rx1, rz0, rz1)], "base": base,
                                  "height": round(span / 2 * ROOF_PITCH, 3), "room": r.id})
            if r.kind == "common_room" or r.id == "kitchens" or r.get("dressing") == "feast":
                cx = x0 + w * 0.7; cz = z0 + d * 0.3
                data["chimneys"].append([cx, base, cz, round(span / 2 * ROOF_PITCH + 3.5, 2)])
            if r.bands >= 2 and r.kind in ("hall", "library") and piece == r.rect:
                ext = {e[0] for e in edges}
                for cs, (cx, cz) in (("nw", (x0, z0)), ("ne", (x1, z0)), ("sw", (x0, z1)), ("se", (x1, z1))):
                    if cs[0] in ext and cs[1] in ext:
                        data["bartizans"].append([cx, base, cz])


def exterior_edges(plan, r, piece, top):
    """Edges of a roof piece (in 4 m steps, merged) that look out over open air or a lower roof."""
    x0, x1, z0, z1 = piece
    out = []
    for side in "wens":
        if side in "we":
            c = x0 if side == "w" else x1
            lo, hi = z0, z1
        else:
            c = z0 if side == "n" else z1
            lo, hi = x0, x1
        run = None
        for a in np.arange(lo, hi, 4.0):
            m = a + 2
            px, pz = ((c - 2 if side == "w" else c + 2), m) if side in "we" else (m, (c - 2 if side == "n" else c + 2))
            n = solid_at(plan, px, pz, top)
            higher = solid_at(plan, px, pz, top + 1)
            exposed = n is None and higher is None
            if exposed and run is None:
                run = a
            if not exposed and run is not None:
                out.append((side, run, a)); run = None
        if run is not None:
            out.append((side, run, hi))
    return out


def edge_line(piece, side, a, b, y):
    x0, x1, z0, z1 = piece
    if side in "we":
        c = x0 if side == "w" else x1
        return [c, a, c, b, y, side]
    c = z0 if side == "n" else z1
    return [a, c, b, c, y, side]


def platforms(plan, data):
    """Battlements on open-air rooms marked "battlements" (the forecourt wall, tower platforms)."""
    for r in plan.rooms.values():
        if not built(r) or not open_air(r) or not r.get("battlements"):
            continue
        y = wall_top(r)
        for side in "wens":
            axis, coord, lo, hi = r.wall_line(side)
            if axis == "z":
                data["merlons"].append([coord, lo, coord, hi, y, side])
            else:
                data["merlons"].append([lo, coord, hi, coord, y, side])


def exposed_sides(plan, key):
    """Which sides (-1 / +1 along the wall's normal) of a wall unit face the open air."""
    axis, coord, off, s = key
    m = off + 2
    out = []
    for sign in (-1, 1):
        if axis == "z":
            px, pz = coord + sign * 1.0, m
        else:
            px, pz = m, coord + sign * 1.0
        if solid_at(plan, px, pz, s) is None:
            out.append(sign)
    return out


def buttresses(plan, units, data):
    for r in plan.rooms.values():
        if not built(r) or r.bands < 2 or r.kind not in ("hall", "library"):
            continue
        for side in "wens":
            axis, coord, lo, hi = r.wall_line(side)
            sign = -1 if side in "wn" else 1
            doors = [k[2] + 2 for k, u in units.items() if k[0] == axis and k[1] == coord and k[3] == r.storey and (u["door"] or u["secret"])]
            for p in range(int(lo) + 8, int(hi) - 3, 8):
                if any(abs(p - c) < 3.0 for c in doors):
                    continue
                key = (axis, coord, p - 4 if p - 4 >= lo else p, r.storey)
                if key not in units or sign not in exposed_sides(plan, key):
                    continue
                pos = [coord + sign * T / 2, r.y, p] if axis == "z" else [p, r.y, coord + sign * T / 2]
                normal = [sign, 0] if axis == "z" else [0, sign]
                data["buttresses"].append({"pos": pos, "normal": normal, "height": round(wall_top(r) - r.y - 1.5, 2)})


def corbels(plan, data):
    for r in plan.rooms.values():
        if not built(r) or r.get("support") != "corbel":
            continue
        for side in "wens":
            axis, coord, lo, hi = r.wall_line(side)
            px, pz = ((coord + (1 if side == "e" else -1), (lo + hi) / 2) if axis == "z"
                      else ((lo + hi) / 2, coord + (1 if side == "s" else -1)))
            if solid_at(plan, px, pz, r.storey) is not None:
                continue
            for a in np.arange(lo + 1, hi, 2.0):
                pos = [coord, r.y, a] if axis == "z" else [a, r.y, coord]
                data["corbels"].append({"pos": pos, "normal": [1 if side == "e" else -1, 0] if axis == "z" else [0, 1 if side == "s" else -1]})


def terrain_min(terrain, rect):
    x0, x1, z0, z1 = rect
    xs = np.arange(x0, x1 + 0.01, 2.0); zs = np.arange(z0, z1 + 0.01, 2.0)
    X, Z = np.meshgrid(xs, zs)
    return float(terrain.height_at(X, Z).min())


def foundations(plan, terrain, data):
    """Plinths under ground-floor rooms where the terrain drops below the floor slab."""
    for r in plan.rooms.values():
        if not built(r) or r.inside is not None or r.storey != 0:
            continue
        # Always: the terrain is cut away under the castle's floors, so a plinth must close the
        # ground line under every wall (a few centimetres of gap show the world behind it).
        low = terrain_min(terrain, (r.x0 - 1, r.x1 + 1, r.z0 - 1, r.z1 + 1))
        bottom = round(min(low, r.y - 1.0) - 1.5, 2)
        if any(built(u) and u.top_storey < 0 and u.x0 < r.x1 + 0.4 and r.x0 - 0.4 < u.x1 and u.z0 < r.z1 + 0.4 and r.z0 - 0.4 < u.z1
               for u in plan.rooms.values()):
            bottom = r.y - 0.98     # a dungeon below: stay within the floor slab
        data["foundations"].append([r.x0 - 0.4, r.x1 + 0.4, r.z0 - 0.4, r.z1 + 0.4, bottom, r.y - 0.03])


def covers(plan, terrain, data):
    """Underground rooms whose roof the terrain no longer covers get a stone slab."""
    for r in plan.rooms.values():
        if not built(r) or r.top_storey >= 0 or r.inside is not None:
            continue
        top = r.ceiling_y
        xs = np.arange(r.x0, r.x1 + 0.01, 2.0); zs = np.arange(r.z0, r.z1 + 0.01, 2.0)
        X, Z = np.meshgrid(xs, zs)
        low = terrain.height_at(X, Z) < top + 0.6
        if not low.any():
            continue
        cx0, cx1 = float(X[low].min()), float(X[low].max())
        cz0, cz1 = float(Z[low].min()), float(Z[low].max())
        cx0, cx1 = max(r.x0 - 0.3, cx0 - 2), min(r.x1 + 0.3, cx1 + 2)
        cz0, cz1 = max(r.z0 - 0.3, cz0 - 2), min(r.z1 + 0.3, cz1 + 2)
        data["covers"].append([cx0, cx1, cz0, cz1, top + 1.0, top + 2.2])


def facade(plan, units, data):
    """Outward stone skin on exposed wall units, merged along each wall line."""
    runs = {}
    for key, u in units.items():
        axis, coord, off, s = key
        for sign in exposed_sides(plan, key):
            rows = []
            for row in range(u["rows"]):
                if row == 0 and (u["door"] or u["secret"] or u["window"]):
                    continue
                rows.append((s * STOREY + row * MODULE_H, s * STOREY + (row + 1) * MODULE_H))
            if u["rows"] >= 2:
                rows.append((s * STOREY + 2 * MODULE_H, (s + 1) * STOREY))
            for y0, y1 in rows:
                runs.setdefault((axis, coord, sign, y0, y1), []).append(off)
    for (axis, coord, sign, y0, y1), offs in sorted(runs.items()):
        offs.sort()
        start = prev = offs[0]
        for o in offs[1:] + [None]:
            if o is not None and o == prev + 4:
                prev = o
                continue
            data["facade"].append([axis, coord + sign * (T / 2 + 0.03), start, prev + 4, y0, y1, sign])
            if o is not None:
                start = prev = o


def hlod(plan, units, data):
    for r in plan.rooms.values():
        if not built(r) or open_air(r):
            continue
        data["hlod"].append([r.x0, r.x1, r.z0, r.z1, r.y, wall_top(r)])
    for key, u in units.items():
        if not u["window"]:
            continue
        axis, coord, off, s = key
        for sign in exposed_sides(plan, key):
            lit = (hash_unit(axis, coord, off, s) % 10) < 7     # about seven in ten windows lit
            data["windows"].append([axis, coord + sign * (T / 2 + 0.06), off + 2, s * STOREY + 2.1, sign, lit])


def hash_unit(axis, coord, off, s):
    """Stable small hash of a wall unit (Python's hash() is salted per process)."""
    h = 2166136261
    for v in (ord(axis), int(coord) + 1000, int(off) + 1000, s + 10):
        h = ((h ^ v) * 16777619) & 0xFFFFFFFF
    return h


def write(data, path="levels/castle/exterior.json"):
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
    return {k: len(v) for k, v in data.items()}

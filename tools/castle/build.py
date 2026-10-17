"""Builds the castle scene (levels/castle/castle.tscn) from a validated Plan.

Everything is derived from the plan and the modular wrappers named in
content/castle/kit.json: shared walls are emitted once, door segments become
doorway modules, stairs cut holes in the floor above, every room gets pillars,
torches, a ceiling and an AreaZone. Gameplay objects come from
content/placements.json. Re-running overwrites the scene, so hand edits belong
in objects/, in the program or in this package.

The builder is a single pass over one plan: its working state lives in module
globals that build() resets, which keeps the emit functions short.
"""
import json
import math
import os
from collections import defaultdict

from .geometry import (STOREY, BAND_H, MODULE, MODULE_H, T, PILLAR_SPACING, TORCH_HEIGHT,
                       STAIR_HOLE_FROM_HEIGHT, local_to_world, snap_rect, rect_minus_all)

PLACEMENTS = "content/placements.json"

KIT = {}
def K(role):
    """Scene path for a kit role (content/castle/kit.json)."""
    return KIT["roles"][role]

# Plan data, bound by build().
rooms = {}
doors = []
house_gates = []
secrets = []
stairs = []
door_rooms = {}
CLASSROOM_FRONT = {}
RAILINGS = []
KEEPOUT = []

# --------------------------------------------------------------------------- scene writer
ext = {}
def ext_id(kind, path):
    key = (kind, path)
    if key not in ext:
        ext[key] = len(ext) + 1
    return ext[key]

nodes = []
placed_nodes = []   # (parent container, (x, y, z), scene path): for the budget rules (budgets.py)
def xf(pos, rot_y=0.0):
    c = math.cos(rot_y); s = math.sin(rot_y)
    return f'Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})'

def block(name, center, size, parent="Geometry"):
    i = ext_id("PackedScene", K("block"))
    nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{i}")]\n'
                 f'transform = {xf(center)}\n'
                 f'size = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')

def inst(name, path, pos, parent=".", rot_y=0.0, props=None, groups=None):
    i = ext_id("PackedScene", path)
    placed_nodes.append((parent, pos, path))
    g = f' groups=[{", ".join(chr(34) + x + chr(34) for x in groups)}]' if groups else ""
    body = f'[node name="{name}" parent="{parent}"{g} instance=ExtResource("{i}")]\ntransform = {xf(pos, rot_y)}\n'
    for k, v in (props or {}).items():
        body += f'{k} = {v}\n'
    nodes.append(body)

object_ids = set()
def oid_props(oid, extra=None):
    """Props for a world object: its stable id ("<area>/<name>"), checked for uniqueness."""
    area, _, name = oid.partition("/")
    assert area in rooms and name, f"object id {oid!r}: needs <known area>/<name>"
    assert oid not in object_ids, f"duplicate object id {oid!r}"
    object_ids.add(oid)
    props = {"object_id": f'"{oid}"'}
    props.update(extra or {})
    return props

def node_name(oid):
    return "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in oid)

_names = defaultdict(int)
def uname(base):
    _names[base] += 1
    return base if _names[base] == 1 else f"{base}_{_names[base]}"

# --------------------------------------------------------------------------- walls
units = {}   # (axis, coord, off, storey) -> {"rows": n, "door": bool, "secret": bool}
def register_edge(axis, coord, lo, hi, storey, rows, room_id):
    for off in range(lo, hi, 4):
        key = (axis, coord, off, storey)
        u = units.setdefault(key, {"rows": 0, "door": False, "secret": False, "window": None, "rooms": set()})
        u["rows"] = max(u["rows"], rows)
        u["rooms"].add(room_id)

def built(r):
    """Rooms that get geometry (terrain rooms are only areas)."""
    return not r.get("terrain")

def register_units():
    for r in rooms.values():
        if not built(r):
            continue
        for s in r.storeys():
            register_edge("z", r.x0, r.z0, r.z1, s, r.rows, r.id)
            register_edge("z", r.x1, r.z0, r.z1, s, r.rows, r.id)
            register_edge("x", r.z0, r.x0, r.x1, s, r.rows, r.id)
            register_edge("x", r.z1, r.x0, r.x1, s, r.rows, r.id)
    for axis, coord, off, storey in doors:
        assert (axis, coord, off, storey) in units, ("door on no wall", axis, coord, off, storey)
        units[(axis, coord, off, storey)]["door"] = True
    for a, b, axis, coord, off, storey, _name in secrets:
        units[(axis, coord, off, storey)]["secret"] = True

# Windows: the wall_window module (a window set into the stone) on walls that face the
# outside or an open-air area, in the lower row of every storey a room spans (tall halls
# get a second, high tier). Every module of such a wall can hold one, except its end
# modules, modules beside a doorway or secret wall, and walls that carry furniture
# (bookshelf walls), stairs or a placed object. A classroom's front wall is the exception
# the other way round: its middle holds the boards, so its windows are the two end
# modules, flanking them. The *_EVERY_OTHER switches thin the rows to every second module.
WINDOW_KINDS = {"hall", "classroom", "library", "common_room", "dormitory", "room", "tower", "corridor"}
# Window type per room ("window" in the program), then per room kind (kit.json window_by_kind);
# anything else gets the module's default single lancet. Walls listed in a room's
# "no_window_sides" (bookshelf walls) stay blind.
def window_scene_for(r):
    role = r.get("window") and "window_" + r.get("window") or KIT["window_by_kind"].get(r.kind)
    return K(role) if role else None

def wall_line(r, side):
    """(axis, coord, lo, hi) of one of room r's walls."""
    return r.wall_line(side)

def placed_wall_points(path):
    """(x, z, storey) of every content/placements.json object, to keep windows clear of them."""
    pts = []
    for area, entries in load_placements(path).items():
        r = rooms[area]
        for e in entries:
            (x, _y, z), _ = placement_point(r, e)
            pts.append((x, z, r.storey))
    return pts

WINDOW_EVERY_OTHER = False
WINDOW_UPPER_EVERY_OTHER = False
WINDOW_AVOID_DOORS = True

def choose_windows():
    occupied = placed_wall_points(PLACEMENTS)
    n = 0
    for r in rooms.values():
        if r.kind not in WINDOW_KINDS or r.storey < 0:
            continue
        for side in "wens":
            if side in r.no_torch_sides or side in r.get("no_window_sides", ""):
                continue
            front = CLASSROOM_FRONT.get(r.id) == side
            axis, coord, lo, hi = wall_line(r, side)
            offs = list(range(lo, hi, 4))
            for storey in r.storeys():
                upper = storey != r.storey
                for i, off in enumerate(offs):
                    end = i == 0 or i == len(offs) - 1
                    if front and not upper:
                        if not end:
                            continue
                    elif end or (upper and WINDOW_UPPER_EVERY_OTHER and i % 2 == 0) or (not upper and WINDOW_EVERY_OTHER and i % 2 == 0):
                        continue
                    key = (axis, coord, off, storey)
                    u = units[key]
                    outside = all(o == r.id or rooms[o].kind == "outdoor" for o in u["rooms"])
                    if not outside or u["door"] or u["secret"] or u["window"]:
                        continue
                    if WINDOW_AVOID_DOORS and any(units.get((axis, coord, o, storey), {}).get(f) for o in (off - 4, off + 4) for f in ("door", "secret")):
                        continue
                    centre = off + 2
                    if any(st == storey and abs((px if axis == "z" else pz) - coord) < 1.0
                           and abs((pz if axis == "z" else px) - centre) < 1.5 for px, pz, st in occupied):
                        continue
                    u["window"] = r.id
                    n += 1
    return n

def windowed_rooms():
    """Rooms that got at least one window (choose_windows ran): daylight reaches them, so
    their torches and chandeliers are put out by day (Lamplighter)."""
    return {u["window"] for u in units.values() if u["window"]}

def run_start(axis, coord, lo, hi, y):
    if axis == "x":
        return (lo, y, coord), 0.0
    return (coord, y, hi), math.radians(90)

def emit_walls():
    by_line = defaultdict(list)
    for (axis, coord, off, storey), u in units.items():
        by_line[(axis, coord, storey)].append((off, u))
    for (axis, coord, storey), items in sorted(by_line.items()):
        items.sort()
        y = storey * STOREY
        max_rows = max(u["rows"] for _, u in items)
        for row in range(max_rows):
            run_lo = None
            def flush(run_hi):
                nonlocal run_lo
                if run_lo is not None:
                    pos, rot = run_start(axis, coord, run_lo, run_hi, y + row * MODULE_H)
                    inst(uname(f"Wall_{axis}{coord:+d}_s{storey}_r{row}"), K("wall_run"),
                         pos, parent="Walls", rot_y=rot, props={"length": f"{run_hi - run_lo:.3f}"})
                run_lo = None
            prev = None
            for off, u in items:
                gap = prev is not None and off != prev + 4
                if gap:
                    flush(prev + 4)
                solid = u["rows"] > row and not (row == 0 and (u["door"] or u["secret"] or u["window"]))
                if solid:
                    if run_lo is None:
                        run_lo = off
                else:
                    flush(off)
                prev = off
            flush(prev + 4)
        for off, u in items:
            centre = off + 2
            pos = (centre, y, coord) if axis == "x" else (coord, y, centre)
            rot = 0.0 if axis == "x" else math.radians(90)
            if u["door"]:
                inst(uname(f"Doorway_{axis}{coord:+d}_s{storey}"), K("doorway"), pos, parent="Walls", rot_y=rot)
            if u["window"]:
                # The module's +Z side (the window's inner face) turns toward the room.
                r = rooms[u["window"]]
                inward = (r.z0 == coord) if axis == "x" else (r.x0 == coord)
                kind_scene = window_scene_for(r)
                props = {"window_scene": f'ExtResource("{ext_id("PackedScene", kind_scene)}")'} if kind_scene else None
                inst(uname(f"Window_{axis}{coord:+d}_s{storey}"), K("window_module"), pos, parent="Walls",
                     rot_y=rot + (0.0 if inward else math.pi), props=props)
            if u["secret"]:
                # SecretWall is 4 × 3.4 m; fill the strip above it up to the next row.
                size = (4, MODULE_H - 3.4, T) if axis == "x" else (T, MODULE_H - 3.4, 4)
                block(uname(f"SecretFill_{axis}{coord:+d}_s{storey}"), (pos[0], y + 3.4 + (MODULE_H - 3.4) / 2, pos[2]), size)

def emit_secret_walls():
    for a, b, axis, coord, off, storey, name in secrets:
        A = rooms[a]
        y = storey * STOREY
        centre = off + 2
        if axis == "z":
            pos = (coord, y, centre); rot = -90.0 if coord == A.x1 else 90.0
        else:
            pos = (centre, y, coord); rot = 180.0 if coord == A.z1 else 0.0
        oid = f"{b}/{name}"
        inst(f"Secret_{node_name(oid)}", K("secret_wall"), pos, rot_y=math.radians(rot),
             props=oid_props(oid, {"approach_area": f'"{a}"'}), groups=["secret_walls", "world_objects"])

def emit_band_fillers():
    """Close the 1 m band between a storey's wall top (8 m) and the next floor (9 m) on every
    full-height wall. Tall rooms would show it from inside; everywhere else the outer face
    would show the ceiling tiles' openwork edges, lit by the room behind."""
    fill = {key for key, u in units.items() if u["rows"] >= 2}
    by_line = defaultdict(list)
    for axis, coord, off, s in fill:
        by_line[(axis, coord, s)].append(off)
    for (axis, coord, s), offs in sorted(by_line.items()):
        offs.sort()
        lo = offs[0]; prev = lo
        def emit(lo, hi):
            y = s * STOREY + BAND_H + (STOREY - BAND_H) / 2
            if axis == "x":
                block(uname(f"BandFill_{axis}{coord:+d}_s{s}"), ((lo + hi) / 2, y, coord), (hi - lo, STOREY - BAND_H, T))
            else:
                block(uname(f"BandFill_{axis}{coord:+d}_s{s}"), (coord, y, (lo + hi) / 2), (T, STOREY - BAND_H, hi - lo))
        for off in offs[1:]:
            if off != prev + 4:
                emit(lo, prev + 4); lo = off
            prev = off
        emit(lo, prev + 4)

# --------------------------------------------------------------------------- floors, ceilings, stairs
def floor_piece(name, rect, top, thick=1.0, tile="plain"):
    x0, x1, z0, z1 = rect
    role, tile_thick = KIT["floor_tiles"][tile]
    scene = K(role)
    props = {"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}", "occluder_y": f"{-tile_thick / 2:.3f}"}
    if tile != "plain":
        props["module_scene"] = f'ExtResource("{ext_id("PackedScene", scene)}")'
    inst(name, K("floor"), (x0, top, z0), parent="Floors", props=props)
    sub_thick = max(0.2, thick - tile_thick)
    block(name + "_Sub", ((x0 + x1) / 2, top - tile_thick - sub_thick / 2, (z0 + z1) / 2), (x1 - x0, sub_thick, z1 - z0))

def ceiling_piece(name, rect, y):
    x0, x1, z0, z1 = rect
    inst(name, K("floor"), (x0, y, z0), parent="Ceilings",
         props={"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}", "occluder_y": "0.245",
                "module_scene": f'ExtResource("{ext_id("PackedScene", K("ceiling_tile"))}")'})

def emit_stairs():
    """Flights and spirals as derived by circulation.py; pads carry the player from a top
    step to the far edge of its hole."""
    for st in stairs:
        if st.get("kind") == "spiral":
            inst(uname(f"Spiral_{st['lo']}"), K("spiral_staircase"), (st["x"], st["y0"], st["z"]), parent="Stairs",
                 props={"turns": f"{st['turns']:.3f}", "rise_per_turn": f"{st['rise_per_turn']:.3f}",
                        "steps_per_turn": str(st["steps_per_turn"]), "landing_steps": str(st["landing_steps"]),
                        "half_size": f"{st['half']:.3f}",
                        "start_angle_degrees": f"{st['start_angle']:.3f}"})
            continue
        inst(uname(f"Stairs_{st['lo']}"), K("staircase"), (st["x"], st["y0"], st["z"]),
             parent="Stairs", rot_y=math.radians(st["rot"]),
             props={"rise": f"{st['rise']:.3f}", "run": f"{st['run']:.3f}", "width": f"{st['width']:.3f}"})
        if st.get("pad"):
            x0, x1, z0, z1 = st["pad"]
            block(uname(f"StairPad_{st['lo']}"), ((x0 + x1) / 2, st["y0"] + st["rise"] - 0.5, (z0 + z1) / 2), (x1 - x0, 1.0, z1 - z0))

def emit_movers(plan):
    """Shifting stairs with their rail gates, clockwork gears and the clock ledge, trick steps."""
    n = 0
    for m in plan.movers:
        if m["kind"] == "shifting_stair":
            name = uname(f"ShiftingStair_{m['room']}_s{m['storey']}")
            inst(name, K("shifting_stair"), m["pivot"], parent="Movers",
                 props={"stops": "PackedFloat32Array(" + ", ".join(f"{a:.3f}" for a in m["stops"]) + ")",
                        "hold": f"{m['hold']:.3f}", "move": f"{m['move']:.3f}", "phase": f"{m['phase']:.3f}",
                        "rise": f"{m['rise']:.3f}", "run": f"{m['run']:.3f}", "width": f"{m['width']:.3f}"})
            for g in m["gates"]:
                inst(uname(f"RailGate_{m['room']}_s{m['storey']}"), K("rail_gate"), g["pos"], parent="Movers",
                     rot_y=math.radians(g["rot"]), props={"stair": f'NodePath("../{name}")', "open_stop": str(g["stop"]),
                                                          "length": f"{g['length']:.3f}"})
            n += 1
        elif m["kind"] == "gear":
            inst(uname(f"Gear_{m['room']}"), K("gear"), m["pos"], parent="Movers",
                 props={"mode": "1", "speed": f"{m['speed']:.3f}", "phase": f"{m['phase']:.3f}", "radius": f"{m['radius']:.3f}"})
            n += 1
    for r in rooms.values():
        ledge = r.get("clock_ledge")
        if ledge:
            lx, ly, lz = ledge
            block(uname(f"ClockLedge_{r.id}"), (lx, ly - 0.25, lz), (3.0, 0.5, 3.0))
            oid = f"{r.id}/fragment_clock"
            inst(f"Fragment_{node_name(oid)}", "res://gameplay/collectibles/collectible.tscn", (lx, ly + 0.8, lz),
                 parent="Collectibles", props=oid_props(oid), groups=["world_objects"])
    for (x, y, z, rot) in plan.trick_steps:
        inst(uname("TrickStep"), K("trick_step"), (x, y + 0.2, z), parent="Movers", rot_y=math.radians(rot))
    return n

def emit_railings():
    for rl in RAILINGS:
        inst(uname("Railing"), K("railing"), rl["pos"], parent="Stairs", rot_y=math.radians(rl["rot"]),
             props={"length": f"{rl['length']:.3f}", "rise": f"{rl['rise']:.3f}"})
    return len(RAILINGS)

def emit_floors_and_ceilings():
    for r in rooms.values():
        if not built(r):
            continue
        holes = list(r.holes) + [rooms[i].rect for i in rooms if rooms[i].inside == r.id and built(rooms[i])]
        for k, piece in enumerate(rect_minus_all(r.rect, holes)):
            floor_piece(uname(f"Floor_{r.id}"), piece, r.y, thick=1.0 if r.storey <= 0 else 0.5, tile=r.tile)
        for rect, y in r.extra_floors:
            floor_piece(uname(f"Landing_{r.id}"), rect, y, thick=1.0, tile=r.tile)
        if r.ceiling:
            for piece in rect_minus_all(r.rect, r.ceiling_holes):
                ceiling_piece(uname(f"Ceiling_{r.id}"), piece, r.ceiling_y)

# --------------------------------------------------------------------------- pillars, torches, zones
def door_centres(axis, coord, storey):
    return [off + 2 for (a, c, off, s) in units if a == axis and c == coord and s == storey and (units[(a, c, off, s)]["door"] or units[(a, c, off, s)]["secret"])]

pillar_points = set()   # (x, z, storey) of every placed pillar
torch_points = []       # (x, z, storey) of every placed torch

def kept_out(x, z, y, margin=0.6):
    """Is (x, z) at height y inside a stair's treads or landings (circulation keepout)?"""
    for (x0, x1, z0, z1), ylo, yhi in KEEPOUT:
        if ylo - 0.1 <= y <= yhi + 0.1 and x0 - margin <= x <= x1 + margin and z0 - margin <= z <= z1 + margin:
            return True
    return False

def emit_pillars():
    placed = pillar_points
    for r in rooms.values():
        if not r.pillars:
            continue
        for s in r.storeys():
            y = s * STOREY
            pts = set()
            for x in (r.x0, r.x1):
                for z in (r.z0, r.z1):
                    pts.add((x, z))
                for z in range(r.z0, r.z1 + 1, 4):
                    if z % PILLAR_SPACING == 0 and all(abs(z - c) > 2.4 for c in door_centres("z", x, s)):
                        pts.add((x, z))
            for z in (r.z0, r.z1):
                for x in range(r.x0, r.x1 + 1, 4):
                    if x % PILLAR_SPACING == 0 and all(abs(x - c) > 2.4 for c in door_centres("x", z, s)):
                        pts.add((x, z))
            for x, z in pts:
                if (x, z, s) in placed or kept_out(x, z, y):
                    continue
                placed.add((x, z, s))
                inst(uname(f"Pillar_{r.id}"), K("pillar"), (x, y, z), parent="Pillars")

CHANDELIER_PITCH = 12.0   # one chandelier per ~12 m of room along each axis

CHANDELIER_CANDLE_HEIGHT = 4.3   # candles this high above the floor, whatever the ceiling
CHANDELIER_RADIUS = 1.3          # the hanging model's reach; a landing this close overhead is in the way
LANDING_THICK = 1.0              # landing slab depth (floor_piece thick for extra floors)

def has_chandeliers(r):
    """Roofed rooms are lit from above; corridors and outdoor areas keep wall torches."""
    return r.ceiling and r.kind not in ("corridor", "outdoor", "stair_turret")

def chandelier_bands(r, x, z):
    """(top, floor) of the open bands over (x, z) that get a chandelier, highest first.
    Landings inside a tall room split it: a chandelier hangs from the underside of the first surface above it
    and never runs its rod through a landing floor."""
    over = sorted({y for (x0, x1, z0, z1), y in r.extra_floors
                   if r.y < y < r.ceiling_y
                   and x0 - CHANDELIER_RADIUS <= x <= x1 + CHANDELIER_RADIUS
                   and z0 - CHANDELIER_RADIUS <= z <= z1 + CHANDELIER_RADIUS}, reverse=True)
    tops = [r.ceiling_y] + [y - LANDING_THICK for y in over]
    floors = over + [r.y]
    bands = list(zip(tops, floors))
    # The top band and the ground band; the walkways between are lit from these and by
    # wall torches (a multi-storey shaft would otherwise blow the room's light budget).
    return bands if len(bands) <= 2 else [bands[0], bands[-1]]

def emit_chandeliers():
    n = 0
    for r in rooms.values():
        if not has_chandeliers(r):
            continue
        w, d = r.x1 - r.x0, r.z1 - r.z0
        nx, nz = max(1, round(w / CHANDELIER_PITCH)), max(1, round(d / CHANDELIER_PITCH))
        for i in range(nx):
            for j in range(nz):
                x = r.x0 + w * (i + 0.5) / nx
                z = r.z0 + d * (j + 0.5) / nz
                for top, floor in chandelier_bands(r, x, z):
                    drop = top - floor - CHANDELIER_CANDLE_HEIGHT - 1.7
                    if drop < 0.3:
                        continue    # too low a band to hang candles in
                    props = {"drop": f"{drop:.3f}"}
                    if r.id in windowed_rooms():
                        props["daylit"] = "true"
                    inst(uname(f"Chandelier_{r.id}"), K("chandelier"),
                         (x, top, z), parent="Lights", props=props)
                    n += 1
    return n

def emit_torches():
    n = 0
    for r in rooms.values():
        if not r.torches:
            continue
        sp = int(r.torch_spacing)
        if has_chandeliers(r):
            if r.bands == 1:
                continue            # candlelight is enough in an ordinary room
            sp = 16                 # tall halls: a few wall accents under the chandeliers
        # Torches light the ground band only: with a 7 m radius, a torch on the upper
        # band of a tall hall lights nothing anyone walks on.
        for s in (r.storey,):
            y = s * STOREY + TORCH_HEIGHT
            for side in "wens":
                if side in r.no_torch_sides:
                    continue
                if side in "we":
                    x = r.x0 + T / 2 if side == "w" else r.x1 - T / 2
                    rot = 90.0 if side == "w" else -90.0
                    coord = r.x0 if side == "w" else r.x1
                    dc = door_centres("z", coord, s)
                    for z in range(r.z0 + 4, r.z1, 4):
                        if (z - 4) % sp != 0 or any(abs(z - c) < 2.5 for c in dc):
                            continue
                        wall_torch(r, (x, y, z), rot); n += 1
                        torch_points.append((x, z, s))
                else:
                    z = r.z0 + T / 2 if side == "n" else r.z1 - T / 2
                    rot = 0.0 if side == "n" else 180.0
                    coord = r.z0 if side == "n" else r.z1
                    dc = door_centres("x", coord, s)
                    for x in range(r.x0 + 4, r.x1, 4):
                        if (x - 4) % sp != 0 or any(abs(x - c) < 2.5 for c in dc):
                            continue
                        wall_torch(r, (x, y, z), rot); n += 1
                        torch_points.append((x, z, s))
    return n

def wall_torch(r, pos, rot):
    """Rule-placed torch. Its id counts per room in emit order, so it shifts when a room's
    layout changes: mysteries should only reference objects placed in content/placements.json."""
    oid = f"{r.id}/torch_{_names['torch:' + r.id] + 1}"
    _names['torch:' + r.id] += 1
    extra = {"daylit": "true"} if r.id in windowed_rooms() else None
    inst(f"Torch_{node_name(oid)}", K("wall_torch"), pos, parent="Torches",
         rot_y=math.radians(rot), props=oid_props(oid, extra), groups=["world_objects"])

def emit_zones():
    for r in rooms.values():
        cx, cz = r.centre()
        h = r.bands * STOREY
        y = r.y + h / 2
        if r.get("zone_y"):
            lo, hi = r.get("zone_y")
            h, y = hi - lo, (lo + hi) / 2
        inst(f"Zone_{r.id}", K("area_zone"), (cx, y, cz), parent="Zones",
             props={"area_id": f'&"{r.id}"', "display_key": f'"{r.name_key}"', "kind": f'"{r.kind}"',
                    "house": str(r.house), "size": f"Vector3({r.x1 - r.x0:.1f}, {h:.1f}, {r.z1 - r.z0:.1f})"})

# --------------------------------------------------------------------------- props and secrets' rewards
# Classrooms get rows of student desks + benches facing the professor's end of the
# room ("front" = the wall opposite the entrance door); wall id -> (desks per row, rows).
# Desk rows (m from the front wall) keep the room's centre clear: the area test drops the
# player there, and it is where players naturally cross a room.
DESK_ROWS_DEEP = (5.0, 7.5, 10.0)         # 24 m deep rooms (wing classrooms, Potions)
DESK_ROWS_TOWER = (4.0, 6.4)              # 16 m tower rooms
DESK_PITCH = 3.0                          # m between desk centres along a row (desk is 1.9 wide)
BENCH_BEHIND_DESK = 0.85                  # bench centre this far behind the desk centre
LECTERN_BEFORE_FIRST_ROW = 2.0            # lectern (and the practice tomes beside it) ahead of the first row
LECTERN_BEFORE_FIRST_ROW_TOWER = 1.4      # tighter in the 16 m tower rooms so the professor fits behind it
SLATE_BOARD_FROM_FRONT = 1.1              # easel board on the centre line, clear of the corner/mid-wall pillar
WALL_BOARD_ACROSS = -2.0                  # wall-mounted board beside the mid-wall pillar (and clear of the torch at ±4)
WALL_BOARD_CENTRE_HEIGHT = 2.0            # centre of the 1.55 m tall board above the floor
PROFESSOR_DESK_FROM_FRONT = 1.6           # professor's desk, off to one side of the lectern
PROFESSOR_DESK_ACROSS = 3.5
PRACTICE_TARGET = "res://objects/school/practice_target.tscn"
PRACTICE_TARGET_FROM_FRONT = 1.8          # practice target (practicals) this far in from the front wall
PRACTICE_TARGET_FROM_SIDE = 2.0           # and this far in from the side wall opposite the professor's desk
TOME_ACROSS = -2.2                        # practice tomes on the other side of the lectern (pitch 2.2 per dx unit)

def classroom_frame(r):
    """(origin on the front wall's centre line, unit vector into the room, unit vector along the
    front wall, prop yaw). Furniture models have their "professor" side on +Z (student
    desk's carved apron, professor desk's drawers, lectern's slanted top); the yaw turns
    +Z toward the front wall (xf() writes basis rows, so +Z maps to (sin, 0, cos))."""
    front = CLASSROOM_FRONT[r.id]
    cx, cz = r.centre()
    if front == "w":   return (r.x0, cz), (1, 0), (0, 1), math.radians(-90)
    if front == "e":   return (r.x1, cz), (-1, 0), (0, 1), math.radians(90)
    if front == "n":   return (cx, r.z0), (0, 1), (1, 0), 0.0
    return (cx, r.z1), (0, -1), (1, 0), math.radians(180)

def classroom_point(r, along, across, height=0.0):
    (ox, oz), (ix, iz), (sx, sz), _ = classroom_frame(r)
    return (ox + ix * along + sx * across, r.y + height, oz + iz * along + sz * across)

def lectern_gap(rid):
    return LECTERN_BEFORE_FIRST_ROW_TOWER if rid.startswith("tower") else LECTERN_BEFORE_FIRST_ROW

def emit_furniture():
    n = 0
    for rid in CLASSROOM_FRONT:
        r = rooms[rid]
        _, (ix, iz), _, yaw = classroom_frame(r)
        cross = (r.z1 - r.z0) if ix else (r.x1 - r.x0)
        per_row = 4 if cross >= 20 else 3
        rows = DESK_ROWS_TOWER if rid.startswith("tower") else DESK_ROWS_DEEP
        offsets = [(i - (per_row - 1) / 2) * DESK_PITCH for i in range(per_row)]
        # The professor's end: lectern on the centre line, desk to one side (both face the class
        # with their +Z side toward the professor, like the student desks).
        tower = rid.startswith("tower")
        inst(uname(f"Lectern_{rid}"), K("lectern"),
             classroom_point(r, rows[0] - lectern_gap(rid), 0.0), parent="Furniture", rot_y=yaw)
        # Slate board on an easel by the front wall; its writing face (+Z) turns toward the class.
        inst(uname(f"SlateBoard_{rid}"), K("slate_board"),
             classroom_point(r, SLATE_BOARD_FROM_FRONT, 0.0), parent="Furniture", rot_y=yaw + math.pi)
        inst(uname(f"ProfessorDesk_{rid}"), K("professor_desk"),
             classroom_point(r, PROFESSOR_DESK_FROM_FRONT - (0.2 if tower else 0.0), PROFESSOR_DESK_ACROSS - (0.5 if tower else 0.0)),
             parent="Furniture", rot_y=yaw)
        # Wall board: origin on its back face, writing face on -Z, so the furniture yaw hangs it
        # on the front wall's inner face looking into the room.
        inst(uname(f"WallBoard_{rid}"), K("wall_board"),
             classroom_point(r, T / 2, WALL_BOARD_ACROSS, WALL_BOARD_CENTRE_HEIGHT), parent="Furniture", rot_y=yaw)
        n += 4
        for a in rows:
            for b in offsets:
                inst(uname(f"Desk_{rid}"), K("student_desk"),
                     classroom_point(r, a, b), parent="Furniture", rot_y=yaw)
                inst(uname(f"Bench_{rid}"), K("student_bench"),
                     classroom_point(r, a + BENCH_BEHIND_DESK, b), parent="Furniture", rot_y=yaw)
                n += 2
        # The practice target for practicals: at the front on the far side from the professor's
        # desk, its rune disc (+Z) turned toward the class.
        oid = f"{rid}/practice_target"
        inst(f"PracticeTarget_{node_name(oid)}", PRACTICE_TARGET,
             classroom_point(r, PRACTICE_TARGET_FROM_FRONT, -(cross / 2 - PRACTICE_TARGET_FROM_SIDE)),
             parent="Puzzles", rot_y=yaw + math.pi, props=oid_props(oid), groups=["world_objects"])
        n += 1
    return n

# Wall furniture: props lined along a room's wall (back against it), skipping doors,
# pillars and torches. Wrapper convention: origin at the back face's bottom centre,
# +Z into the room.
SHELF_W, SHELF_D = 2.85, 0.52

def wall_free_intervals(r, side, width, storey=None):
    """Free spans along a wall (as coordinates along its axis) between doors, secret walls,
    pillars and torches, each shrunk so a prop of `width` centred inside clears them."""
    storey = r.storey if storey is None else storey
    if side in "we":
        axis, coord, lo, hi = "z", (r.x0 if side == "w" else r.x1), r.z0, r.z1
        along = lambda x, z: z; other = lambda x, z: x
    else:
        axis, coord, lo, hi = "x", (r.z0 if side == "n" else r.z1), r.x0, r.x1
        along = lambda x, z: x; other = lambda x, z: z
    blocked = []
    for (a, c, off, st), u in units.items():
        if a == axis and c == coord and st == storey and lo <= off < hi and (u["door"] or u["secret"] or u["window"]):
            blocked.append((off - 0.3, off + 4.3))
    for x, z, st in pillar_points:
        if st == storey and abs(other(x, z) - coord) < 0.01 and lo - 1 <= along(x, z) <= hi + 1:
            blocked.append((along(x, z) - 0.6, along(x, z) + 0.6))
    for x, z, st in torch_points:
        if st == storey and abs(other(x, z) - coord) < 0.5 and lo <= along(x, z) <= hi:
            blocked.append((along(x, z) - 0.4, along(x, z) + 0.4))
    for x, z, st, half in wall_spans:
        if st == storey and abs(other(x, z) - coord) < 0.6 and lo - half <= along(x, z) <= hi + half:
            blocked.append((along(x, z) - half, along(x, z) + half))
    blocked.sort()
    free, cursor = [], lo + T / 2
    for b0, b1 in blocked:
        if b0 > cursor:
            free.append((cursor, b0))
        cursor = max(cursor, b1)
    if cursor < hi - T / 2:
        free.append((cursor, hi - T / 2))
    return axis, coord, [(a, b) for a, b in free if b - a >= width]

def line_wall(r, side, scene, width, name):
    """Fill a wall with `scene` instances of `width`, evenly spread within each free span."""
    axis, coord, free = wall_free_intervals(r, side, width)
    inner = coord + (T / 2 if side in "wn" else -T / 2)
    yaw = {"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[side]
    n = 0
    for a, b in free:
        k = int((b - a) // width)
        gap = (b - a - k * width) / (k + 1)
        for i in range(k):
            c = a + gap * (i + 1) + width * (i + 0.5)
            pos = (inner, r.y, c) if axis == "z" else (c, r.y, inner)
            inst(uname(f"{name}_{r.id}"), scene, pos, parent="Furniture", rot_y=math.radians(yaw))
            n += 1
    return n

def shelf_at(r, side, along, scene=None, name="Shelf"):
    """One wall prop with its back on wall `side` at coordinate `along` the wall."""
    if side in "we":
        pos = ((r.x0 + T / 2) if side == "w" else (r.x1 - T / 2), r.y, along)
    else:
        pos = (along, r.y, (r.z0 + T / 2) if side == "n" else (r.z1 - T / 2))
    yaw = {"w": 90.0, "e": -90.0, "n": 0.0, "s": 180.0}[side]
    inst(uname(f"{name}_{r.id}"), scene or K("bookshelf"), pos, parent="Furniture", rot_y=math.radians(yaw))

def shelf_stack(r, x, z0, count, name="Stack"):
    """Freestanding double-sided run of shelves along Z starting at z0 (backs meeting on x)."""
    for i in range(count):
        z = z0 + SHELF_W * (i + 0.5)
        inst(uname(f"{name}_{r.id}"), K("bookshelf"), (x, r.y, z), parent="Furniture", rot_y=math.radians(90))
        inst(uname(f"{name}_{r.id}"), K("bookshelf"), (x, r.y, z), parent="Furniture", rot_y=math.radians(-90))
    return 2 * count

FEAST_TABLE_L = 5.7       # one feast_table.tscn segment (×3 of the Meshy export)
FEAST_BENCH_PITCH = 2.85   # student benches along each side (1.9 m bench + gap)

def emit_feast(gh):
    """Four long house tables run the length of the hall, benches down both sides; the head
    of the hall (north: sorting stone, plaques) stays clear. Dressing "feast"."""
    n = 0
    segments = 4
    length = segments * FEAST_TABLE_L
    z0 = gh.z1 - 3.7 - length          # tables end 3.7 m short of the south wall
    for i in range(4):
        x = gh.x0 + (gh.x1 - gh.x0) * (i + 0.5) / 4
        for k in range(segments):
            inst(uname(f"FeastTable_{gh.id}"), K("feast_table"),
                 (x, gh.y, z0 + FEAST_TABLE_L * (k + 0.5)), parent="Furniture", rot_y=math.radians(90))
            n += 1
        benches = int(length // FEAST_BENCH_PITCH)
        gap = (length - benches * 1.9) / benches
        for b in range(benches):
            z = z0 + gap / 2 + 1.9 / 2 + b * (1.9 + gap)
            for side, yaw in ((-0.82, -90.0), (0.82, 90.0)):   # bench backs away from the table
                inst(uname(f"FeastBench_{gh.id}"), K("student_bench"),
                     (x + side, gh.y, z), parent="Furniture", rot_y=math.radians(yaw))
                n += 1
    return n

def emit_great_hall():
    return sum(emit_feast(r) for r in rooms.values() if r.get("dressing") == "feast")

def emit_shelves():
    """Bookshelves where a room reads as a library (dressing "library": the north wall is a
    solid wall of books and three double-sided stacks make reading aisles in the back half,
    leaving the entrance half open), an archive (dressing "archive_<side>": one wall of
    shelves) or a study (dressing "study": two shelves on the west wall)."""
    n = 0
    for r in rooms.values():
        d = r.get("dressing") or ""
        cx, cz = r.centre()
        if d == "library":
            n += line_wall(r, "n", K("bookshelf"), SHELF_W, "Shelf")
            for dx in (-10.0, 0.0, 10.0):
                n += shelf_stack(r, cx + dx, r.z0 + 4.0, 2)   # a walkway between the back wall of books and the stacks
        elif d.startswith("archive_"):
            n += line_wall(r, d[-1], K("bookshelf"), SHELF_W, "Shelf")
        elif d == "study":
            for dz in (-2.2, 2.2):   # between the mid-wall pillar and the torches
                shelf_at(r, "w", cz + dz); n += 1
    return n

# Doors: a pair of oak leaves (CastleDoor) in the doorways of rooms people use as rooms
# (classrooms, offices, dormitories, common rooms, the library, tower rooms). The castle's
# main routes get the ceremonial leaves instead, standing open: both arches of every wide
# double opening (the entrance, the courtyard, the library) and the doorways into
# rooms with door_style "grand". House gates (HouseDoor) and passages between halls and corridors stay
# open. Leaves swing into the room (a main route: away from the open air); when a placed
# object stands where a leaf would swing, toward the other side; when both are blocked
# the doorway stays empty. Doors into rooms with door_style "locked" start locked: an unlock spell
# (Unbolt) opens them.
DOOR_KINDS = ("classroom", "room", "dormitory", "common_room", "library", "tower")
DOOR_SWING = 1.85   # a leaf sweeps this far into the room and along the wall from the doorway's centre ± 1.78

def emit_castle_doors():
    occupied = placed_wall_points(PLACEMENTS)
    gates = {(ax, c, off, st) for ax, c, off, st, _h, _a in house_gates}
    n = 0
    for key, (a, b, count) in sorted(door_rooms.items()):
        axis, coord, off, storey = key
        if key in gates:
            continue
        A, B = rooms[a], rooms[b]
        grand = count > 1 or A.get("door_style") == "grand" or B.get("door_style") == "grand"
        if grand:
            inside = sorted([r for r in (A, B) if r.kind not in ("outdoor", "grounds")],
                            key=lambda r: (r.get("door_style") != "grand", r.kind not in DOOR_KINDS))
        else:
            inside = [r for r in (A, B) if r.kind in DOOR_KINDS]
        if not inside:
            continue
        centre = off + 2
        def swing_clear(r):
            # Is the strip the leaves sweep on r's side free of placed objects?
            sign = 1 if (r.z0 == coord if axis == "x" else r.x0 == coord) else -1
            for px, pz, st in occupied:
                along, across = (px, pz - coord) if axis == "x" else (pz, px - coord)
                if st == storey and 0 < across * sign < DOOR_SWING + 0.5 and abs(along - centre) < 2 * DOOR_SWING:
                    return False
            return True
        order = inside + [r for r in (A, B) if r not in inside]
        side = next((r for r in order if swing_clear(r)), None)
        if side is None:
            continue
        other = B if side is A else A
        owner = inside[0]
        y = storey * STOREY
        pos = (centre, y, coord) if axis == "x" else (coord, y, centre)
        rot = 0.0 if axis == "x" else math.radians(90)
        # The leaves open toward the door's +Z side, which must face `side`.
        toward = (side.z0 == coord) if axis == "x" else (side.x0 == coord)
        oid = f"{owner.id}/door_{_names['door:' + owner.id] + 1}"
        _names['door:' + owner.id] += 1
        props = {"approach_area": f'"{(other if owner is side else side).id}"'}
        if owner.get("door_style") == "locked" or other.get("door_style") == "locked":
            props["locked"] = "true"
        elif grand:
            props["start_open"] = "true"
        inst(f"Door_{node_name(oid)}", K("door_grand") if grand else K("door"), pos, parent="Doors", rot_y=rot + (0.0 if toward else math.pi),
             props=oid_props(oid, props), groups=["world_objects"])
        n += 1
    return n

def emit_house_gates():
    for axis, coord, off, storey, house, area in house_gates:
        y = storey * STOREY
        centre = off + 2
        pos = (centre, y, coord) if axis == "x" else (coord, y, centre)
        rot = 0.0 if axis == "x" else math.radians(90)
        # The leaves swing toward the door's +Z side: into the house area.
        H = rooms[area]
        if not ((H.z0 == coord) if axis == "x" else (H.x0 == coord)):
            rot += math.pi
        oid = f"{area}/house_door"
        inst(f"HouseDoor_{node_name(oid)}", K("house_door"), pos, parent="Doors", rot_y=rot,
             props=oid_props(oid, {"house": str(house)}), groups=["world_objects"])

# --------------------------------------------------------------------------- placed gameplay objects
# content/placements.json: area id -> list of entries {id, kind, <position>, <kind fields>}.
# Position (relative to the area's room; every position must land inside it):
#   "slot": "centre"                  the room centre (+ "dy", "yaw")
#   "door": <room id>                 beside the doorway to that room: "along" m from its centre
#                                     along the wall (default 2.6), "inset" m into the room
#   "at": [dx, dz]                    offset from the room centre (+ "dy"), "yaw" in degrees
#   "wall": n|s|e|w, "along": 0..1    on that wall, facing into the room; "inset" m from the
#                                     wall (default: flush), "height" above the floor
#   "corner": nw|ne|sw|se, "inset": [x, z]   m in from that corner (+ "dy")
#   "beside_lectern": dx              classrooms: next to the lectern, dx × 1.1 m across
# Kind fields: spell_tome "spell" (resources/spells/<id>.tres), plaque "text" (translation key).
# "set": {property: bool | number | string} overrides exported properties of the instance.
# Each entry gets the object id "<area>/<id>".
KINDS = {
    # kind: (scene, parent container, world object: gets object_id + the world_objects group)
    "spell_tome": ("res://objects/interactables/spell_tome.tscn", "Tomes", True),
    "plaque": ("res://objects/interactables/plaque.tscn", "Props", True),
    "fragment": ("res://gameplay/collectibles/collectible.tscn", "Collectibles", True),
    "checkpoint": ("res://gameplay/checkpoints/checkpoint.tscn", "Checkpoints", False),
    "crystal_guardian": ("res://characters/enemies/crystal_guardian.tscn", "Enemies", False),
    "magic_switch": ("res://objects/puzzles/magic_switch.tscn", "Puzzles", True),
    "pushable_block": ("res://objects/puzzles/pushable_block.tscn", "Puzzles", True),
    "rotating_statue": ("res://objects/puzzles/rotating_statue.tscn", "Puzzles", True),
    "lever": ("res://objects/interactables/lever.tscn", "Puzzles", True),
    "sorting_stone": ("res://objects/school/sorting_stone.tscn", ".", True),
    "house_tally": ("res://objects/school/house_tally.tscn", "Props", False),
    "item_rack": ("res://objects/interactables/broom_rack.tscn", "Props", True),
    "notice_board": ("res://objects/school/notice_board.tscn", "Props", False),
    "lore_book": ("res://objects/interactables/lore_book.tscn", "Props", True),
}
PLAQUE_HEIGHT = 1.6
NOTICE_BOARD_HEIGHT = 1.9   # centre of the 1.55 m board (its origin) above the floor
# Placed kinds that take wall space from the dressing (half their width along the wall, m).
WALL_SPAN_KINDS = {"notice_board": 1.5}
wall_spans = []   # (x, z, storey, half width) of placed wall items, filled by emit_placements
WALL_HEIGHTS = {"plaque": PLAQUE_HEIGHT, "notice_board": NOTICE_BOARD_HEIGHT}
WALL_FLUSH = T / 2 + 0.05

def placement_point(r, e):
    """(position, yaw radians) of a placement entry in room r."""
    cx, cz = r.centre()
    if "at" in e:
        dx, dz = e["at"]
        return (cx + dx, r.y + e.get("dy", 0.0), cz + dz), math.radians(e.get("yaw", 0.0))
    if e.get("wall") == "auto":
        e = dict(e, **auto_wall(r))
    if "wall" in e:
        side, along = e["wall"], e.get("along", 0.5)
        d = e.get("inset", WALL_FLUSH)
        y = r.y + e.get("height", WALL_HEIGHTS.get(e["kind"], 0.0))
        if side == "n": return (r.x0 + (r.x1 - r.x0) * along, y, r.z0 + d), 0.0
        if side == "s": return (r.x0 + (r.x1 - r.x0) * along, y, r.z1 - d), math.radians(180)
        if side == "w": return (r.x0 + d, y, r.z0 + (r.z1 - r.z0) * along), math.radians(90)
        if side == "e": return (r.x1 - d, y, r.z0 + (r.z1 - r.z0) * along), math.radians(-90)
        raise AssertionError(f"{r.id}/{e['id']}: unknown wall {side!r}")
    if "corner" in e:
        corner, (ix, iz) = e["corner"], e["inset"]
        assert corner in ("nw", "ne", "sw", "se"), f"{r.id}/{e['id']}: unknown corner {corner!r}"
        x = r.x0 + ix if corner[1] == "w" else r.x1 - ix
        z = r.z0 + iz if corner[0] == "n" else r.z1 - iz
        return (x, r.y + e.get("dy", 0.0), z), math.radians(e.get("yaw", 0.0))
    if e.get("slot") == "centre":
        return (cx, r.y + e.get("dy", 0.0), cz), math.radians(e.get("yaw", 0.0))
    if "door" in e:
        # Beside the doorway into room e["door"]: "along" m from the doorway's centre along
        # the wall, "inset" m into the room; faces into the room.
        other = e["door"]
        for (axis, coord, off, storey), (a, b, _c) in door_rooms.items():
            if {a, b} == {r.id, other} and storey in r.storeys():
                side = r.side_of(axis, coord)
                along = off + 2 + e.get("along", 2.6)
                d = e.get("inset", 1.0)
                y = r.y + e.get("dy", 0.0)
                if side == "n": return (along, y, r.z0 + d), 0.0
                if side == "s": return (along, y, r.z1 - d), math.radians(180)
                if side == "w": return (r.x0 + d, y, along), math.radians(90)
                if side == "e": return (r.x1 - d, y, along), math.radians(-90)
        raise AssertionError(f"{r.id}/{e['id']}: no doorway to {other!r}")
    if "beside_lectern" in e:
        assert r.id in CLASSROOM_FRONT, f"{r.id}/{e['id']}: beside_lectern needs a furnished classroom"
        first_row = (DESK_ROWS_TOWER if r.id.startswith("tower") else DESK_ROWS_DEEP)[0]
        return classroom_point(r, first_row - lectern_gap(r.id), TOME_ACROSS + 1.1 * e["beside_lectern"]), 0.0
    raise AssertionError(f"{r.id}/{e['id']}: no position (slot, at, wall, corner, door or beside_lectern)")

def check_inside(r, e, pos):
    """A placement must land inside its room (walls: on the inner face)."""
    x, _y, z = pos
    m = 0.0 if "wall" in e else 0.2
    assert r.x0 + m <= x <= r.x1 - m and r.z0 + m <= z <= r.z1 - m, \
        f"{r.id}/{e['id']}: position ({x:.1f}, {z:.1f}) is outside the room {r.rect}"

def auto_wall(r):
    """A wall spot clear of doorways and secret walls for a plaque ("wall": "auto")."""
    best = None
    for side in "nswe":
        axis, coord, lo, hi = r.wall_line(side)
        busy = [k[2] for k, u in units.items() if k[0] == axis and k[1] == coord and k[3] == r.storey and (u["door"] or u["secret"])]
        for off in range(int(lo) + 4, int(hi) - 4, 4):
            if any(abs(off - b) < 8 for b in busy):
                continue
            along = (off + 2 - lo) / (hi - lo)
            return {"wall": side, "along": round(along, 4)}
    return {"wall": "n", "along": 0.5} if best is None else best

def godot_literal(value):
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, (int, float)): return repr(value)
    if isinstance(value, str): return json.dumps(value)
    raise AssertionError(f"unsupported property value {value!r}")

GENERATED_PLACEMENTS = {}

def load_placements(path):
    with open(path) as f:
        data = json.load(f)
    for area, entries in GENERATED_PLACEMENTS.items():
        data.setdefault(area, []).extend(entries)
    for area, entries in data.items():
        assert area in rooms, f"{path}: unknown area {area!r}"
        for e in entries:
            assert isinstance(e.get("id"), str) and e["id"] and "/" not in e["id"], f"{path}: {area}: entry without a plain id: {e}"
            assert e.get("kind") in KINDS, f"{path}: {area}/{e['id']}: unknown kind {e.get('kind')!r}"
            if e["kind"] == "spell_tome":
                assert os.path.exists(f"resources/spells/{e.get('spell')}.tres"), f"{area}/{e['id']}: unknown spell {e.get('spell')!r}"
            if e["kind"] == "plaque":
                assert isinstance(e.get("text"), str), f"{area}/{e['id']}: plaque without text"
    return data

def emit_placements(path):
    counts = defaultdict(int)
    for area, entries in load_placements(path).items():
        r = rooms[area]
        for e in entries:
            scene, parent, world = KINDS[e["kind"]]
            oid = f"{area}/{e['id']}"
            pos, yaw = placement_point(r, e)
            check_inside(r, e, pos)
            if e["kind"] in WALL_SPAN_KINDS:
                wall_spans.append((pos[0], pos[2], r.storey, WALL_SPAN_KINDS[e["kind"]]))
            props = {}
            if e["kind"] == "spell_tome":
                spell_ext = ext_id("Resource", "res://resources/spells/" + e["spell"] + ".tres")
                props["spell"] = f'ExtResource("{spell_ext}")'
            if e["kind"] == "plaque":
                props["text"] = f'"{e["text"]}"'
            if e["kind"] == "lore_book":
                props["book"] = f'"{e["book"]}"'
            for prop, value in e.get("set", {}).items():
                props[prop] = godot_literal(value)
            if world:
                props = oid_props(oid, props)
            else:
                assert oid not in object_ids, f"duplicate object id {oid!r}"
                object_ids.add(oid)
            inst(f"{e['kind'].title().replace('_', '')}_{node_name(oid)}", scene, pos, parent=parent, rot_y=yaw,
                 props=props, groups=["world_objects"] if world else None)
            counts[e["kind"]] += 1
    return counts

# --------------------------------------------------------------------------- build
SCENE_ENV = '''
[sub_resource type="ProceduralSkyMaterial" id="NightSkyMat"]
sky_top_color = Color(0.015, 0.02, 0.045, 1)
sky_horizon_color = Color(0.07, 0.08, 0.12, 1)
sky_curve = 0.12
ground_bottom_color = Color(0.02, 0.02, 0.025, 1)
ground_horizon_color = Color(0.07, 0.08, 0.11, 1)
sun_angle_max = 4.0
sun_curve = 0.08
energy_multiplier = 1.0

[sub_resource type="Sky" id="NightSky"]
sky_material = SubResource("NightSkyMat")

[sub_resource type="Environment" id="Env"]
background_mode = 2
sky = SubResource("NightSky")
ambient_light_source = 2
ambient_light_color = Color(0.5, 0.5, 0.56, 1)
ambient_light_energy = 0.22
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.09, 0.1, 0.13, 1)
fog_density = 0.0016
fog_sky_affect = 0.35
'''
# Render layer 11 ("outdoor"): terrain, water, flora and exteriors. Only the moon lights it,
# so moonlight never reaches the castle's interiors.
OUTDOOR_LAYER = 11
OUTDOOR_LAYER_MASK = 1 << (OUTDOOR_LAYER - 1)
CONTAINERS = ["Movers", "Geometry", "Floors", "Walls", "Pillars", "Ceilings", "Stairs", "Torches", "Lights", "Zones",
              "Collectibles", "Checkpoints", "Tomes", "Doors", "Furniture", "Enemies", "Props", "Puzzles"]


def reset(plan, kit):
    """Bind the plan and clear every piece of working state."""
    global rooms, doors, house_gates, secrets, stairs, door_rooms, CLASSROOM_FRONT, KIT, RAILINGS, KEEPOUT, GENERATED_PLACEMENTS
    rooms = plan.rooms; doors = plan.doors; house_gates = plan.house_gates
    secrets = plan.secrets; stairs = plan.stairs; door_rooms = plan.door_rooms
    RAILINGS = plan.railings; KEEPOUT = plan.keepout
    GENERATED_PLACEMENTS = getattr(plan, "generated_placements", {})
    CLASSROOM_FRONT = {r.id: r.get("front") for r in rooms.values() if r.get("front")}
    KIT = kit
    for state in (ext, object_ids, _names, units, pillar_points):
        state.clear()
    del nodes[:]
    del torch_points[:]
    del placed_nodes[:]
    del wall_spans[:]


def build(plan, kit, placements=PLACEMENTS):
    """Emit every node for `plan`. Returns (stats, scene text)."""
    reset(plan, kit)
    register_units()
    window_count = choose_windows()
    emit_walls()
    emit_secret_walls()
    emit_band_fillers()
    emit_stairs()
    railing_count = emit_railings()
    mover_count = emit_movers(plan)
    for centre, size in plan.parapets:
        block(uname("Parapet"), centre, size)
    emit_floors_and_ceilings()
    emit_pillars()
    torch_count = emit_torches()
    chandelier_count = emit_chandeliers()
    emit_zones()
    emit_house_gates()
    placed = emit_placements(placements)
    door_count = emit_castle_doors()
    furniture_count = emit_furniture() + emit_shelves() + emit_great_hall()
    from . import dressing
    furniture_count += dressing.dress(plan, getattr(plan, "names_by_key", {}))
    stats = dict(rooms=len(rooms), wall_units=len(units), doors=len(doors), secrets=len(secrets), stairs=len(stairs), railings=railing_count, movers=mover_count,
                 torches=torch_count, windows=window_count, castle_doors=door_count, chandeliers=chandelier_count,
                 furniture=furniture_count, enemies=placed["crystal_guardian"], nodes=len(nodes))
    return stats, scene_text(plan)


def scene_text(plan):
    level_script = ext_id("Script", "res://levels/castle/castle.gd")
    grounds = ext_id("PackedScene", "res://levels/grounds/grounds.tscn")
    exterior = ext_id("Script", "res://gameplay/world/castle_exterior.gd")
    static_batch = ext_id("Script", "res://gameplay/world/static_batch.gd")
    sectors = ext_id("Script", "res://gameplay/world/sector_streamer.gd")
    exts = ""
    for (kind, path), i in sorted(ext.items(), key=lambda kv: kv[1]):
        exts += f'[ext_resource type="{kind}" path="{path}" id="{i}"]\n'
    sx, sy, sz = plan.start
    root = f'''
[node name="Castle" type="Node3D"]
script = ExtResource("{level_script}")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 20, 0)
light_color = Color(0.85, 0.86, 0.95, 1)
light_energy = 0.06
shadow_enabled = false

[node name="StaticBatch" type="Node3D" parent="."]
script = ExtResource("{static_batch}")

[node name="StartPoint" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, {sx}, {sy + 0.05}, {sz})
'''
    for c in CONTAINERS:
        root += f'\n[node name="{c}" type="Node3D" parent="."]\n'
    root += f'\n[node name="Grounds" parent="." instance=ExtResource("{grounds}")]\n'
    root += f'\n[node name="Exterior" type="Node3D" parent="."]\nscript = ExtResource("{exterior}")\n'
    root += f'\n[node name="Sectors" type="Node" parent="."]\nscript = ExtResource("{sectors}")\n'
    root += f'''
[node name="Moon" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.707107, -0.5, 0.5, 0, 0.707107, 0.707107, -0.707107, -0.5, 0.5, 0, 60, 0)
light_color = Color(0.55, 0.64, 0.95, 1)
light_energy = 0.38
light_cull_mask = {OUTDOOR_LAYER_MASK}
shadow_enabled = false
'''
    root += "\n"
    header = f'[gd_scene load_steps={len(ext) + 4} format=3 uid="uid://castle0000001"]\n\n'
    return header + exts + SCENE_ENV + root + "\n".join(nodes) + "\n"

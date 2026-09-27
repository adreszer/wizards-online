#!/usr/bin/env python3
"""Generates levels/castle/castle.tscn — the open-world castle.
Run from the project root:  python3 tools/generate_castle.py

Everything is declared as data (rooms on a 4 m grid, doors between rooms,
stairs between storeys, secrets) and the script derives the geometry from the
modular wrappers in objects/environment/: shared walls are emitted once, door
segments become doorway modules, stairs cut holes in the floor above, every
room gets pillars, torches, a ceiling and an AreaZone. Re-running overwrites
the scene, so hand edits belong in objects/ or in this file.

Conventions (see docs/plan.md, "Production environment asset pipeline"):
  - grid 4 m, walls 0.35 m thick centred on room boundaries, 4 m modules
  - storey pitch 9 m: walls 0..8 m (two rows), ceiling tile at 8 m, next floor top at 9 m
  - a room spanning `bands` storeys is that many bands tall (great hall: 17 m)
  - stairs: 25 steps of 0.36 m (PlayerMovement.step_height is 0.42)
"""
import math
import os
import sys
from collections import defaultdict

STOREY = 9.0        # floor-to-floor pitch
BAND_H = 8.0        # wall height within a storey (two 4 m rows)
MODULE = 4.0        # wall / floor module size
MODULE_H = 4.0
T = 0.35            # wall thickness
PILLAR_SPACING = 8.0
TORCH_HEIGHT = 2.6
STAIR_RUN = 14.0
STAIR_WIDTH = 3.6
STAIR_HOLE_FROM_HEIGHT = 5.6   # part of a flight above this needs the ceiling/floor above cut open

OUT = "levels/castle/castle.tscn"

# --------------------------------------------------------------------------- scene writer
ext = {}
def ext_id(kind, path):
    key = (kind, path)
    if key not in ext:
        ext[key] = len(ext) + 1
    return ext[key]

nodes = []
def xf(pos, rot_y=0.0):
    c = math.cos(rot_y); s = math.sin(rot_y)
    return f'Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})'

def block(name, center, size, parent="Geometry"):
    i = ext_id("PackedScene", "res://objects/greybox/greybox_block.tscn")
    nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{i}")]\n'
                 f'transform = {xf(center)}\n'
                 f'size = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')

def inst(name, path, pos, parent=".", rot_y=0.0, props=None, groups=None):
    i = ext_id("PackedScene", path)
    g = f' groups=[{", ".join(chr(34) + x + chr(34) for x in groups)}]' if groups else ""
    body = f'[node name="{name}" parent="{parent}"{g} instance=ExtResource("{i}")]\ntransform = {xf(pos, rot_y)}\n'
    for k, v in (props or {}).items():
        body += f'{k} = {v}\n'
    nodes.append(body)

_names = defaultdict(int)
def uname(base):
    _names[base] += 1
    return base if _names[base] == 1 else f"{base}_{_names[base]}"

# --------------------------------------------------------------------------- model
class Room:
    def __init__(self, id, x0, x1, z0, z1, storey=0, bands=1, kind="room", ceiling=True,
                 rows=2, pillars=True, torches=True, tile="plain", house=0, inside=None,
                 torch_spacing=8.0, name_key=None):
        for v in (x0, x1, z0, z1):
            assert v % 4 == 0, f"{id}: coordinates must be on the 4 m grid ({v})"
        assert x1 > x0 and z1 > z0, id
        self.id = id; self.x0 = x0; self.x1 = x1; self.z0 = z0; self.z1 = z1
        self.storey = storey; self.bands = bands; self.kind = kind; self.ceiling = ceiling
        self.rows = rows; self.pillars = pillars; self.torches = torches; self.tile = tile
        self.house = house; self.inside = inside; self.torch_spacing = torch_spacing
        self.name_key = name_key or ("AREA_" + id.upper())
        self.holes = []          # floor cut-outs (stair arrivals from below)
        self.ceiling_holes = []  # ceiling cut-outs (stairs leaving upward)
        self.no_torch_sides = set()
        self.extra_floors = []   # (rect, y) landings inside tall rooms

    @property
    def y(self): return self.storey * STOREY
    @property
    def top_storey(self): return self.storey + self.bands - 1
    @property
    def ceiling_y(self): return self.top_storey * STOREY + BAND_H
    @property
    def rect(self): return (self.x0, self.x1, self.z0, self.z1)
    def storeys(self): return range(self.storey, self.storey + self.bands)
    def centre(self): return ((self.x0 + self.x1) / 2, (self.z0 + self.z1) / 2)

rooms = {}
def room(id, x0, x1, z0, z1, storey=0, **kw):
    assert id not in rooms, id
    r = Room(id, x0, x1, z0, z1, storey, **kw)
    rooms[id] = r
    return r

doors = []      # (axis, coord, off, storey, count)
house_gates = []  # (axis, coord, off, storey, house): doorways that get a HouseDoor
secrets = []    # (a, b, axis, coord, off, storey)
stairs = []     # dicts
edges = []      # (a, b) connectivity for the reachability check
door_units = set()

def shared_edge(A, B):
    """Wall line shared by two rooms: (axis, coord, lo, hi). axis 'z' = wall along Z at x=coord."""
    if A.x1 == B.x0 or B.x1 == A.x0:
        coord = A.x1 if A.x1 == B.x0 else A.x0
        lo, hi = max(A.z0, B.z0), min(A.z1, B.z1)
        assert hi - lo >= 4, f"{A.id}/{B.id} do not share a wall"
        return "z", coord, lo, hi
    if A.z1 == B.z0 or B.z1 == A.z0:
        coord = A.z1 if A.z1 == B.z0 else A.z0
        lo, hi = max(A.x0, B.x0), min(A.x1, B.x1)
        assert hi - lo >= 4, f"{A.id}/{B.id} do not share a wall"
        return "x", coord, lo, hi
    raise AssertionError(f"{A.id} and {B.id} are not adjacent")

def _door_offs(lo, hi, at, count):
    """`at` is the start of the 4 m door segment (count=1) or the centre line of a
    double opening (count=2); None picks the middle of the shared wall."""
    n = (hi - lo) // 4
    if at is None:
        at = lo + 4 * ((n - count) // 2) + 2 * count
    start = math.floor((at - 2 * count) / 4 + 0.5) * 4
    offs = [start + 4 * i for i in range(count)]
    for off in offs:
        assert lo <= off and off + 4 <= hi, f"door at {at} outside {lo}..{hi}"
    return offs

def door(a, b, at=None, storey=None, count=1):
    A, B = rooms[a], rooms[b]
    axis, coord, lo, hi = shared_edge(A, B)
    if storey is None:
        storey = max(A.storey, B.storey)
    assert storey in A.storeys() and storey in B.storeys(), f"door {a}/{b}: storey {storey}"
    for off in _door_offs(lo, hi, at, count):
        doors.append((axis, coord, off, storey))
        # A doorway into a house area (common room, dormitory, house landing) gets a gate.
        if A.house != B.house:
            house_gates.append((axis, coord, off, storey, A.house or B.house))
    edges.append((a, b))

def door_on(a, side, at, storey=None, count=1, to=None):
    """Doorway on a room's own wall (rooms nested inside a bigger outdoor area)."""
    A = rooms[a]
    storey = A.storey if storey is None else storey
    if side in "ew":
        axis, coord, lo, hi = "z", (A.x1 if side == "e" else A.x0), A.z0, A.z1
    else:
        axis, coord, lo, hi = "x", (A.z1 if side == "s" else A.z0), A.x0, A.x1
    for off in _door_offs(lo, hi, at, count):
        doors.append((axis, coord, off, storey))
    edges.append((a, to or A.inside))

def secret(a, b, at=None, storey=None):
    """A SecretWall in the wall between a (where the ornament is seen) and b (hidden room)."""
    A, B = rooms[a], rooms[b]
    axis, coord, lo, hi = shared_edge(A, B)
    if storey is None:
        storey = max(A.storey, B.storey)
    off = _door_offs(lo, hi, at, 1)[0]
    secrets.append((a, b, axis, coord, off, storey))
    edges.append((a, b))

def stair(lo, hi, side, direction, start, run=STAIR_RUN, width=STAIR_WIDTH, rise=STOREY, hole=True):
    """Straight flight inside room `lo` hugging wall `side` ('e','w','n','s'), climbing
    toward `direction` ('n','s','e','w') from coordinate `start` along that wall.
    Cuts the arrival hole in `hi`'s floor and `lo`'s ceiling (hole=True)."""
    L = rooms[lo]
    inset = T / 2 + 0.05 + width / 2
    if side == "e": x, z = L.x1 - inset, start
    elif side == "w": x, z = L.x0 + inset, start
    elif side == "n": x, z = start, L.z0 + inset
    else: x, z = start, L.z1 - inset
    rot = {"n": 90.0, "s": -90.0, "e": 0.0, "w": 180.0}[direction]
    L.no_torch_sides.add(side)
    stairs.append(dict(lo=lo, hi=hi, x=x, z=z, rot=rot, run=run, width=width, rise=rise, hole=hole, side=side))
    if hi is not None:
        edges.append((lo, hi))

def local_to_world(x, z, rot_deg, local):
    r = math.radians(rot_deg)
    lx, lz = local
    return (x + lx * math.cos(r) + lz * math.sin(r), z - lx * math.sin(r) + lz * math.cos(r))

def snap_rect(x0, x1, z0, z1):
    return (math.floor(x0 / 4 + 1e-6) * 4, math.ceil(x1 / 4 - 1e-6) * 4,
            math.floor(z0 / 4 + 1e-6) * 4, math.ceil(z1 / 4 - 1e-6) * 4)

def rect_minus(rect, hole):
    x0, x1, z0, z1 = rect; hx0, hx1, hz0, hz1 = hole
    if hx1 <= x0 or hx0 >= x1 or hz1 <= z0 or hz0 >= z1:
        return [rect]
    out = []
    if hz0 > z0: out.append((x0, x1, z0, hz0))
    if hz1 < z1: out.append((x0, x1, hz1, z1))
    mz0, mz1 = max(z0, hz0), min(z1, hz1)
    if hx0 > x0: out.append((x0, hx0, mz0, mz1))
    if hx1 < x1: out.append((hx1, x1, mz0, mz1))
    return out

def rect_minus_all(rect, holes):
    pieces = [rect]
    for h in holes:
        pieces = [p for piece in pieces for p in rect_minus(piece, h)]
    return pieces

# --------------------------------------------------------------------------- the castle
# Plan view: +X east, +Z south. Players arrive from the grounds in the south and walk north.
# Storeys: -1 dungeons (y -9), 0 ground, 1 first, 2 second, 3/4 tower tops.

# Grounds (outdoors) and what stands on them
room("grounds", -64, 64, 48, 96, kind="outdoor", ceiling=False, rows=1, pillars=False, torches=False, tile="plain")
room("greenhouse", 40, 64, 52, 68, kind="classroom", inside="grounds", rows=1)
room("paddock", -64, -40, 52, 68, kind="outdoor", ceiling=False, rows=1, pillars=False, torches=False, inside="grounds")
door_on("greenhouse", "w", 60)
door_on("paddock", "e", 60)

# Ground floor core
room("entrance_hall", -12, 12, 24, 48, bands=2, kind="hall")
room("great_hall", 12, 44, 8, 48, bands=2, kind="hall", tile="ornate")
room("stair_hall", -36, -12, 24, 48, bands=3, kind="hall")
room("courtyard", -12, 12, -16, 24, bands=3, kind="outdoor", ceiling=False)
room("north_hall", -12, 12, -40, -16, kind="hall")
room("library", -20, 20, -64, -40, bands=2, kind="library", tile="ornate")
room("kitchens", 44, 60, 24, 48, kind="room")
room("house4_common", 44, 60, 8, 24, kind="common_room", house=4, tile="ornate")
room("house4_dorm", 60, 76, 8, 24, kind="dormitory", house=4)

door("grounds", "entrance_hall", at=0, count=2)
door("entrance_hall", "courtyard", at=0, count=2)
door("entrance_hall", "great_hall", at=36)
door("entrance_hall", "stair_hall", at=36)
door("great_hall", "kitchens", at=36)
door("kitchens", "house4_common", at=52)
door("house4_common", "house4_dorm", at=16)
door("courtyard", "north_hall", at=0, count=2)
door("north_hall", "library", at=0, count=2)

# West wing: corridor + classrooms, ground and first floor
for s in (0, 1):
    room(f"corridor_w_{s}", -20, -12, -40, 24, storey=s, kind="corridor", torch_spacing=16.0)
    room(f"corridor_e_{s}", 12, 20, -40, 8, storey=s, kind="corridor", torch_spacing=16.0)
west = {0: ["class_shapeshaping", "class_sigilcraft", "class_chronicles", "class_glyphs"],
        1: ["class_numeromancy", "class_warding", "staff_room", "hospital_wing"]}
east = {0: ["class_herblore", "class_skyriding", "class_beastlore"],
        1: ["class_stargazing", "song_room", "records_room"]}
for s in (0, 1):
    for i, rid in enumerate(west[s]):
        z1 = 24 - 16 * i
        room(rid, -44, -20, z1 - 16, z1, storey=s, kind="classroom" if rid.startswith("class") else "room")
        door(f"corridor_w_{s}", rid, at=z1 - 8 if rid != "class_sigilcraft" else 0)
    for i, rid in enumerate(east[s]):
        z1 = 8 - 16 * i
        room(rid, 20, 44, z1 - 16, z1, storey=s, kind="classroom" if rid.startswith("class") else "room")
        door(f"corridor_e_{s}", rid, at=z1 - 8)
door("stair_hall", "corridor_w_0", at=-16)
door("stair_hall", "class_shapeshaping", at=-28)
door("corridor_w_0", "courtyard", at=4)
door("corridor_w_0", "north_hall", at=-28)
door("corridor_e_0", "courtyard", at=4)
door("corridor_e_0", "north_hall", at=-28)
door("corridor_e_0", "great_hall", at=16)
door("corridor_e_0", "library", at=16)
door("corridor_w_0", "library", at=-16)

# First floor: landing of the grand staircase (north strip of the stair hall, y 9) opens north
room("north_hall_1", -12, 12, -40, -16, storey=1, kind="hall")
door("stair_hall", "corridor_w_1", at=-16, storey=1)
door("stair_hall", "class_numeromancy", at=-28, storey=1)
door("corridor_w_1", "north_hall_1", at=-28)
door("corridor_e_1", "north_hall_1", at=-28)

# Second floor: top landing (south strip of the stair hall, y 18) opens east and west
room("gallery", -12, 12, 24, 48, storey=2, kind="hall", tile="ornate")
room("roost", -52, -36, 40, 48, storey=2, kind="room")
door("stair_hall", "gallery", at=44, storey=2)
door("stair_hall", "roost", at=44, storey=2)

# Towers (16 × 16, one straight flight per storey along the east wall, arriving in the NE corner)
def tower(prefix, x0, z0, storeys, kinds, no_stair=()):
    """`no_stair` lists storeys with no flight up from them (a gated landing above)."""
    ids = []
    for s in storeys:
        rid = f"{prefix}_{s}"
        kind, house = kinds.get(s, ("tower", 0))
        r = room(rid, x0, x0 + 16, z0, z0 + 16, storey=s, kind=kind, house=house,
                 tile="ornate" if kind in ("common_room", "classroom") else "plain")
        if s == storeys[-1] and kind == "outdoor":
            r.ceiling = False; r.rows = 1; r.torches = False; r.pillars = False
        ids.append(rid)
    for s, a, b in zip(storeys, ids, ids[1:]):
        if s not in no_stair:
            stair(a, b, "e", "n", z0 + 16 - 0.2)
    return ids

# House towers: the ground room is public; the first-floor landing already belongs to the house
# (its door from the records room / hospital wing is the gate) and the stairs to the common room
# and dormitory start there.
tower("tower_ne", 20, -56, [0, 1, 2, 3], {1: ("tower", 1), 2: ("common_room", 1), 3: ("dormitory", 1)}, no_stair=(0,))
tower("tower_nw", -36, -56, [0, 1, 2, 3], {1: ("tower", 2), 2: ("common_room", 2), 3: ("dormitory", 2)}, no_stair=(0,))
tower("tower_sw", -52, 24, [0, 1, 2, 3, 4], {2: ("classroom", 0), 3: ("classroom", 0), 4: ("outdoor", 0)})
rooms["tower_sw_3"].name_key = "AREA_CLASS_FARSIGHT"
rooms["tower_sw_4"].name_key = "AREA_STARGAZING_PLATFORM"
door("library", "tower_ne_0", at=-48)
door("library", "tower_nw_0", at=-48)
door("class_beastlore", "tower_ne_0", at=28)
door("records_room", "tower_ne_1", at=28)
door("class_glyphs", "tower_nw_0", at=-28)
door("hospital_wing", "tower_nw_1", at=-28)
door("stair_hall", "tower_sw_0", at=28)
door("stair_hall", "tower_sw_1", at=28, storey=1)

# Side stairs in the corridors (west strip of the east corridor / east strip of the west corridor,
# so the classroom doors stay clear) and the grand staircase in the stair hall
stair("corridor_e_0", "corridor_e_1", "w", "n", -8)
stair("corridor_w_0", "corridor_w_1", "e", "n", -8)
SH = rooms["stair_hall"]
stair("stair_hall", None, "w", "n", SH.z1 - 0.2, run=15.8, hole=False)                 # ground → landing 1 (north strip)
SH.extra_floors.append(((SH.x0, SH.x1, SH.z0, SH.z0 + 8), STOREY))
stair("stair_hall", None, "e", "s", SH.z0 + 8, run=15.8, rise=STOREY, hole=False)     # landing 1 → landing 2 (south strip)
stairs[-1]["y"] = STOREY
SH.extra_floors.append(((SH.x0, SH.x1 - 4, SH.z1 - 8, SH.z1), 2 * STOREY))
SH.no_torch_sides.update({"w", "e"})
# Railings on the open edges of the two landings (flights arrive at their ends).
landing_parapets = [((-24, STOREY + 0.5, 32), (16, 1, 0.25)),
                    ((-16, 2 * STOREY + 0.5, 43), (0.25, 1, 6)),
                    ((-26, 2 * STOREY + 0.5, 40), (20, 1, 0.25))]

# Dungeons (storey -1) under the west wing
room("dungeon_corridor", -20, -12, -40, 24, storey=-1, kind="corridor", torch_spacing=16.0)
room("class_elixirs", -44, -20, 0, 24, storey=-1, kind="classroom", tile="ornate")
room("cellars", -44, -20, -16, 0, storey=-1, kind="room")
room("house3_common", -44, -20, -40, -16, storey=-1, kind="common_room", house=3, tile="ornate")
room("house3_dorm", -60, -44, -40, -16, storey=-1, kind="dormitory", house=3)
room("undercroft", -12, 12, -40, -16, storey=-1, kind="secret", tile="ornate")
door("dungeon_corridor", "class_elixirs", at=0)
door("dungeon_corridor", "cellars", at=-8)
door("dungeon_corridor", "house3_common", at=-28)
door("house3_common", "house3_dorm", at=-28)
stair("dungeon_corridor", "corridor_w_0", "w", "n", 20)
secret("dungeon_corridor", "undercroft", at=-28)

# More secrets: a hidden study off the Chronicles classroom, a loft above the great hall
room("hidden_study", -52, -44, -24, -8, kind="secret", tile="ornate")
secret("class_chronicles", "hidden_study", at=-16)
room("loft", 12, 28, 24, 48, storey=2, kind="secret", tile="ornate")
secret("gallery", "loft", at=36)

START = (0.0, 0.0, 84.0)

# --------------------------------------------------------------------------- consistency checks
def overlaps(a, b):
    return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1

ids = list(rooms)
for i, a in enumerate(ids):
    for b in ids[i + 1:]:
        A, B = rooms[a], rooms[b]
        if A.inside == b or B.inside == a:
            continue
        if set(A.storeys()) & set(B.storeys()) and overlaps(A, B):
            sys.exit(f"rooms overlap: {a} and {b}")

adj = defaultdict(set)
for a, b in edges:
    adj[a].add(b); adj[b].add(a)
seen = {"grounds"}; stack = ["grounds"]
while stack:
    n = stack.pop()
    for m in adj[n]:
        if m not in seen:
            seen.add(m); stack.append(m)
unreachable = [r for r in rooms if r not in seen]
if unreachable:
    sys.exit(f"unreachable rooms: {unreachable}")

# --------------------------------------------------------------------------- walls
units = {}   # (axis, coord, off, storey) -> {"rows": n, "door": bool, "secret": bool}
def register_edge(axis, coord, lo, hi, storey, rows):
    for off in range(lo, hi, 4):
        key = (axis, coord, off, storey)
        u = units.setdefault(key, {"rows": 0, "door": False, "secret": False})
        u["rows"] = max(u["rows"], rows)

for r in rooms.values():
    for s in r.storeys():
        register_edge("z", r.x0, r.z0, r.z1, s, r.rows)
        register_edge("z", r.x1, r.z0, r.z1, s, r.rows)
        register_edge("x", r.z0, r.x0, r.x1, s, r.rows)
        register_edge("x", r.z1, r.x0, r.x1, s, r.rows)
for axis, coord, off, storey in doors:
    assert (axis, coord, off, storey) in units, ("door on no wall", axis, coord, off, storey)
    units[(axis, coord, off, storey)]["door"] = True
    door_units.add((axis, coord, off, storey))
for a, b, axis, coord, off, storey in secrets:
    units[(axis, coord, off, storey)]["secret"] = True

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
                    inst(uname(f"Wall_{axis}{coord:+d}_s{storey}_r{row}"), "res://objects/environment/modular/modular_wall_run.tscn",
                         pos, parent="Walls", rot_y=rot, props={"length": f"{run_hi - run_lo:.3f}"})
                run_lo = None
            prev = None
            for off, u in items:
                gap = prev is not None and off != prev + 4
                if gap:
                    flush(prev + 4)
                solid = u["rows"] > row and not (row == 0 and (u["door"] or u["secret"]))
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
                inst(uname(f"Doorway_{axis}{coord:+d}_s{storey}"), "res://objects/environment/modular/doorway.tscn", pos, parent="Walls", rot_y=rot)
            if u["secret"]:
                # SecretWall is 4 × 3.4 m; fill the strip above it up to the next row.
                size = (4, MODULE_H - 3.4, T) if axis == "x" else (T, MODULE_H - 3.4, 4)
                block(uname(f"SecretFill_{axis}{coord:+d}_s{storey}"), (pos[0], y + 3.4 + (MODULE_H - 3.4) / 2, pos[2]), size)

def emit_secret_walls():
    for a, b, axis, coord, off, storey in secrets:
        A = rooms[a]
        y = storey * STOREY
        centre = off + 2
        if axis == "z":
            pos = (coord, y, centre); rot = -90.0 if coord == A.x1 else 90.0
        else:
            pos = (centre, y, coord); rot = 180.0 if coord == A.z1 else 0.0
        inst(uname(f"Secret_{a}_{b}"), "res://objects/puzzles/secret_wall.tscn", pos, rot_y=math.radians(rot), groups=["secret_walls"])

def emit_band_fillers():
    """Tall rooms show the 1 m gap between a storey's wall top (8 m) and the next floor (9 m)."""
    fill = set()
    for r in rooms.values():
        if r.bands < 2:
            continue
        for s in list(r.storeys())[:-1]:
            for off in range(r.z0, r.z1, 4):
                fill.add(("z", r.x0, off, s)); fill.add(("z", r.x1, off, s))
            for off in range(r.x0, r.x1, 4):
                fill.add(("x", r.z0, off, s)); fill.add(("x", r.z1, off, s))
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
FLOOR_TILES = {
    "plain": ("res://objects/environment/modular/floor_tile.tscn", 0.46),
    "ornate": ("res://objects/environment/modular/floor_tile_2.tscn", 0.22),
}
def floor_piece(name, rect, top, thick=1.0, tile="plain"):
    x0, x1, z0, z1 = rect
    scene, tile_thick = FLOOR_TILES[tile]
    props = {"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}", "occluder_y": f"{-tile_thick / 2:.3f}"}
    if tile != "plain":
        props["module_scene"] = f'ExtResource("{ext_id("PackedScene", scene)}")'
    inst(name, "res://objects/environment/modular/modular_floor.tscn", (x0, top, z0), parent="Floors", props=props)
    sub_thick = max(0.2, thick - tile_thick)
    block(name + "_Sub", ((x0 + x1) / 2, top - tile_thick - sub_thick / 2, (z0 + z1) / 2), (x1 - x0, sub_thick, z1 - z0))

def ceiling_piece(name, rect, y):
    x0, x1, z0, z1 = rect
    inst(name, "res://objects/environment/modular/modular_floor.tscn", (x0, y, z0), parent="Ceilings",
         props={"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}", "occluder_y": "0.245",
                "module_scene": f'ExtResource("{ext_id("PackedScene", "res://objects/environment/modular/ceiling_tile.tscn")}")'})

def emit_stairs():
    for st in stairs:
        L = rooms[st["lo"]]
        y = st.get("y", L.y)
        run, width, rise, rot = st["run"], st["width"], st["rise"], st["rot"]
        inst(uname(f"Stairs_{st['lo']}"), "res://objects/environment/modular/staircase.tscn", (st["x"], y, st["z"]),
             parent="Stairs", rot_y=math.radians(rot),
             props={"rise": f"{rise:.3f}", "run": f"{run:.3f}", "width": f"{width:.3f}"})
        if not st["hole"] or st["hi"] is None:
            continue
        H = rooms[st["hi"]]
        # Part of the flight that needs headroom through the ceiling / floor above.
        lx0 = run * STAIR_HOLE_FROM_HEIGHT / rise
        corners = [local_to_world(st["x"], st["z"], rot, (lx, lz)) for lx in (lx0, run + 1.5) for lz in (-width / 2, width / 2)]
        xs = [c[0] for c in corners]; zs = [c[1] for c in corners]
        hole = snap_rect(min(xs), max(xs), min(zs), max(zs))
        hole = (max(hole[0], H.x0), min(hole[1], H.x1), max(hole[2], H.z0), min(hole[3], H.z1))
        H.holes.append(hole)
        L.ceiling_holes.append(hole)
        # Landing pad from the top step to the far wall of the hole (player keeps walking straight).
        end = local_to_world(st["x"], st["z"], rot, (run, 0))
        far = {90.0: hole[2] + T / 2, -90.0: hole[3] - T / 2, 0.0: hole[1] - T / 2, 180.0: hole[0] + T / 2}[rot]
        along = abs((far - end[1]) if rot in (90.0, -90.0) else (far - end[0]))
        if along > 0.15:
            pc = local_to_world(st["x"], st["z"], rot, (run + along / 2, 0))
            size = (width, 1.0, along) if rot in (90.0, -90.0) else (along, 1.0, width)
            block(uname(f"StairPad_{st['lo']}"), (pc[0], y + rise - 0.5, pc[1]), size)
        # Parapets around the hole on the upper floor, except where the flight lets out.
        yp = y + rise
        for side, (ax0, ax1, az0, az1) in (("w", (hole[0], hole[0], hole[2], hole[3])), ("e", (hole[1], hole[1], hole[2], hole[3])),
                                            ("n", (hole[0], hole[1], hole[2], hole[2])), ("s", (hole[0], hole[1], hole[3], hole[3]))):
            on_wall = (side == "w" and ax0 == H.x0) or (side == "e" and ax1 == H.x1) or (side == "n" and az0 == H.z0) or (side == "s" and az1 == H.z1)
            if on_wall:
                continue
            if side in "we":
                dist = abs(end[0] - ax0); lo, hi = az0, az1; proj = end[1]
            else:
                dist = abs(end[1] - az0); lo, hi = ax0, ax1; proj = end[0]
            segs = [(lo, hi)]
            if dist <= width / 2 + 0.6:
                segs = [(lo, proj - 2.2), (proj + 2.2, hi)]
            for a, b in segs:
                a, b = max(a, lo), min(b, hi)
                if b - a < 0.3:
                    continue
                if side in "we":
                    block(uname(f"Parapet_{st['hi']}"), (ax0, yp + 0.5, (a + b) / 2), (0.25, 1.0, b - a))
                else:
                    block(uname(f"Parapet_{st['hi']}"), ((a + b) / 2, yp + 0.5, az0), (b - a, 1.0, 0.25))

def emit_floors_and_ceilings():
    for r in rooms.values():
        holes = list(r.holes) + [rooms[i].rect for i in rooms if rooms[i].inside == r.id]
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

def emit_pillars():
    placed = set()
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
                if (x, z, s) in placed:
                    continue
                placed.add((x, z, s))
                inst(uname(f"Pillar_{r.id}"), "res://objects/environment/modular/pillar.tscn", (x, y, z), parent="Pillars")

def emit_torches():
    n = 0
    for r in rooms.values():
        if not r.torches:
            continue
        sp = int(r.torch_spacing)
        for s in r.storeys():
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
                        inst(uname(f"Torch_{r.id}"), "res://objects/environment/props/wall_torch.tscn", (x, y, z), parent="Torches", rot_y=math.radians(rot)); n += 1
                else:
                    z = r.z0 + T / 2 if side == "n" else r.z1 - T / 2
                    rot = 0.0 if side == "n" else 180.0
                    coord = r.z0 if side == "n" else r.z1
                    dc = door_centres("x", coord, s)
                    for x in range(r.x0 + 4, r.x1, 4):
                        if (x - 4) % sp != 0 or any(abs(x - c) < 2.5 for c in dc):
                            continue
                        inst(uname(f"Torch_{r.id}"), "res://objects/environment/props/wall_torch.tscn", (x, y, z), parent="Torches", rot_y=math.radians(rot)); n += 1
    return n

def emit_area_map(path):
    """Server-side copy of the area metadata (nakama/modules/world_areas.lua) so the
    match handler can validate classroom-only actions without trusting the client."""
    lines = ["-- GENERATED by tools/generate_castle.py; do not edit. area id -> { kind, house }",
             "return {"]
    for r in sorted(rooms.values(), key=lambda r: r.id):
        lines.append(f'  ["{r.id}"] = {{ kind = "{r.kind}", house = {r.house} }},')
    lines.append("}")
    open(path, "w").write("\n".join(lines) + "\n")

def emit_zones():
    for r in rooms.values():
        cx, cz = r.centre()
        h = r.bands * STOREY
        inst(f"Zone_{r.id}", "res://gameplay/world/area_zone.tscn", (cx, r.y + h / 2, cz), parent="Zones",
             props={"area_id": f'&"{r.id}"', "display_key": f'"{r.name_key}"', "kind": f'"{r.kind}"',
                    "house": str(r.house), "size": f"Vector3({r.x1 - r.x0:.1f}, {h:.1f}, {r.z1 - r.z0:.1f})"})

# --------------------------------------------------------------------------- props and secrets' rewards
def plaque(rid, text_key, side="n", along=0.5):
    r = rooms[rid]
    y = r.y + 1.6
    if side == "n": pos, rot = (r.x0 + (r.x1 - r.x0) * along, y, r.z0 + T / 2 + 0.05), 0.0
    elif side == "s": pos, rot = (r.x0 + (r.x1 - r.x0) * along, y, r.z1 - T / 2 - 0.05), 180.0
    elif side == "w": pos, rot = (r.x0 + T / 2 + 0.05, y, r.z0 + (r.z1 - r.z0) * along), 90.0
    else: pos, rot = (r.x1 - T / 2 - 0.05, y, r.z0 + (r.z1 - r.z0) * along), -90.0
    inst(uname(f"Plaque_{rid}"), "res://objects/interactables/plaque.tscn", pos, rot_y=math.radians(rot), props={"text": f'"{text_key}"'})

def fragment(rid, dx, dz, dy=0.0):
    r = rooms[rid]
    cx, cz = r.centre()
    inst(uname(f"Fragment_{rid}"), "res://gameplay/collectibles/collectible.tscn", (cx + dx, r.y + dy, cz + dz), parent="Collectibles")

# Classrooms get rows of student desks + benches facing the professor's end of the
# room ("front" = the wall opposite the entrance door); wall id -> (desks per row, rows).
CLASSROOM_FRONT = {
    "class_shapeshaping": "w", "class_sigilcraft": "w", "class_chronicles": "w", "class_glyphs": "w",
    "class_numeromancy": "w", "class_warding": "w", "class_elixirs": "w",
    "class_herblore": "e", "class_skyriding": "e", "class_beastlore": "e", "class_stargazing": "e",
    "tower_sw_2": "w", "tower_sw_3": "w",
}
# Desk rows (m from the front wall) keep the room's centre clear: the area test drops the
# player there, and it is where players naturally cross a room.
DESK_ROWS_DEEP = (5.0, 7.5, 10.0)         # 24 m deep rooms (wing classrooms, Elixirs)
DESK_ROWS_TOWER = (4.0, 6.4)              # 16 m tower rooms
DESK_PITCH = 3.0                          # m between desk centres along a row (desk is 1.9 wide)
BENCH_BEHIND_DESK = 0.85                  # bench centre this far behind the desk centre
LECTERN_BEFORE_FIRST_ROW = 2.0            # practice tomes / professor's spot, ahead of the first row

def classroom_frame(r):
    """(origin on the front wall's centre line, unit vector into the room, unit vector along the
    front wall, desk yaw). Desk model: carved apron on +Z faces the professor."""
    front = CLASSROOM_FRONT[r.id]
    cx, cz = r.centre()
    if front == "w":   return (r.x0, cz), (1, 0), (0, 1), math.radians(90)
    if front == "e":   return (r.x1, cz), (-1, 0), (0, 1), math.radians(-90)
    if front == "n":   return (cx, r.z0), (0, 1), (1, 0), math.radians(180)
    return (cx, r.z1), (0, -1), (1, 0), 0.0

def classroom_point(r, along, across):
    (ox, oz), (ix, iz), (sx, sz), _ = classroom_frame(r)
    return (ox + ix * along + sx * across, r.y, oz + iz * along + sz * across)

def emit_furniture():
    n = 0
    for rid in CLASSROOM_FRONT:
        r = rooms[rid]
        _, (ix, iz), _, yaw = classroom_frame(r)
        cross = (r.z1 - r.z0) if ix else (r.x1 - r.x0)
        per_row = 4 if cross >= 20 else 3
        rows = DESK_ROWS_TOWER if rid.startswith("tower") else DESK_ROWS_DEEP
        offsets = [(i - (per_row - 1) / 2) * DESK_PITCH for i in range(per_row)]
        for a in rows:
            for b in offsets:
                inst(uname(f"Desk_{rid}"), "res://objects/environment/props/student_desk.tscn",
                     classroom_point(r, a, b), parent="Furniture", rot_y=yaw)
                inst(uname(f"Bench_{rid}"), "res://objects/environment/props/student_bench.tscn",
                     classroom_point(r, a + BENCH_BEHIND_DESK, b), parent="Furniture", rot_y=yaw)
                n += 2
    return n

# (room, spell id, offset: across the lectern for furnished classrooms, else from the room centre)
PRACTICE_TOMES = [
    ("class_sigilcraft", "arcane_pulse", -2.0, 0.0),
    ("class_sigilcraft", "uplift", 2.0, 0.0),
    ("class_skyriding", "galewind", 0.0, 0.0),
    ("kitchens", "emberkindle", 0.0, 0.0),
    ("class_elixirs", "wellspring", 0.0, 0.0),
    ("class_warding", "frostbind", 0.0, 0.0),
    ("library", "glowmote", 0.0, 0.0),
    ("class_stargazing", "duskveil", 0.0, 0.0),
    ("class_glyphs", "unbolt", 0.0, 0.0),
    ("class_shapeshaping", "mendweave", 0.0, 0.0),
    ("class_herblore", "quicksprout", 0.0, 0.0),
]

# (room, offset from the room centre, yaw in degrees) — dungeon enemies; see characters/enemies/.
ENEMIES = [
    ("cellars", 4.0, -4.0, 90.0),
    ("cellars", -6.0, 4.0, -45.0),
    ("dungeon_corridor", 0.0, -22.0, 0.0),
]

def emit_enemies():
    for rid, dx, dz, yaw in ENEMIES:
        r = rooms[rid]
        cx, cz = r.centre()
        inst(uname(f"Guardian_{rid}"), "res://characters/enemies/crystal_guardian.tscn",
             (cx + dx, r.y, cz + dz), parent="Enemies", rot_y=math.radians(yaw))
    return len(ENEMIES)

def emit_house_gates():
    for axis, coord, off, storey, house in house_gates:
        y = storey * STOREY
        centre = off + 2
        pos = (centre, y, coord) if axis == "x" else (coord, y, centre)
        rot = 0.0 if axis == "x" else math.radians(90)
        inst(uname(f"HouseDoor_{house}"), "res://objects/school/house_door.tscn", pos, parent="Doors", rot_y=rot, props={"house": str(house)})

def emit_props():
    # The sorting ceremony: a stone at the head of the great hall.
    gh = rooms["great_hall"]
    inst("SortingStone", "res://objects/school/sorting_stone.tscn", (gh.centre()[0], gh.y, gh.z0 + 5))
    plaque("great_hall", "PLAQUE_SORTING_STONE", "n", 0.3)
    plaque("entrance_hall", "PLAQUE_CASTLE_ENTRANCE", "w", 0.75)
    plaque("great_hall", "PLAQUE_GREAT_HALL", "n", 0.5)
    plaque("library", "PLAQUE_LIBRARY", "s", 0.25)
    plaque("class_sigilcraft", "PLAQUE_SIGILCRAFT", "n", 0.5)
    plaque("stair_hall", "PLAQUE_STAIR_HALL", "s", 0.5)
    plaque("undercroft", "PLAQUE_UNDERCROFT", "n", 0.5)
    plaque("cellars", "PLAQUE_CELLARS", "e", 0.5)
    plaque("hidden_study", "PLAQUE_HIDDEN_STUDY", "n", 0.5)
    plaque("loft", "PLAQUE_LOFT", "n", 0.5)
    plaque("tower_sw_4", "PLAQUE_STARGAZING", "n", 0.5)
    plaque("grounds", "PLAQUE_GROUNDS", "n", 0.3)
    # Until lessons grant spells, each subject keeps a practice tome for the
    # spell closest to it (ids from resources/spells/, see SpellRegistry).
    for rid, spell_id, dx, dz in PRACTICE_TOMES:
        r = rooms[rid]
        cx, cz = r.centre()
        spell_ext = ext_id("Resource", f"res://resources/spells/{spell_id}.tres")
        if rid in CLASSROOM_FRONT:
            first_row = (DESK_ROWS_TOWER if rid.startswith("tower") else DESK_ROWS_DEEP)[0]
            pos = classroom_point(r, first_row - LECTERN_BEFORE_FIRST_ROW, dx)
        else:
            pos = (cx + dx, r.y, cz + dz)
        inst(uname(f"Tome_{spell_id}"), "res://objects/interactables/spell_tome.tscn", pos,
             parent="Tomes", props={"spell": f'ExtResource("{spell_ext}")'})
    r = rooms["class_sigilcraft"]
    inst("SigilcraftSwitch", "res://objects/puzzles/magic_switch.tscn", (r.x0 + 3, r.y, r.z0 + 3))
    inst("SigilcraftBlock", "res://objects/puzzles/pushable_block.tscn", (r.x1 - 4, r.y + 0.6, r.z0 + 4))
    for rid, pts in {"undercroft": [(-6, -6), (6, -6), (0, 6)], "hidden_study": [(0, -4), (0, 4)],
                     "loft": [(-4, 0), (4, 0)], "tower_sw_4": [(-4, 4)], "tower_ne_3": [(-5, 5)],
                     "tower_nw_3": [(-5, 5)], "cellars": [(-8, 4)], "roost": [(0, 0)]}.items():
        for dx, dz in pts:
            fragment(rid, dx, dz)
    for rid in ("entrance_hall", "north_hall", "library", "stair_hall", "dungeon_corridor", "gallery"):
        cx, cz = rooms[rid].centre()
        inst(uname(f"Checkpoint_{rid}"), "res://gameplay/checkpoints/checkpoint.tscn", (cx, rooms[rid].y, cz + 4), parent="Checkpoints")

# --------------------------------------------------------------------------- build
emit_walls()
emit_secret_walls()
emit_band_fillers()
emit_stairs()
for centre, size in landing_parapets:
    block(uname("Parapet_stair_hall"), centre, size)
emit_floors_and_ceilings()
emit_pillars()
torch_count = emit_torches()
emit_zones()
emit_house_gates()
emit_props()
furniture_count = emit_furniture()
enemy_count = emit_enemies()
emit_area_map("nakama/modules/world_areas.lua")

level_script = ext_id("Script", "res://levels/castle/castle.gd")
exts = ""
for (kind, path), i in sorted(ext.items(), key=lambda kv: kv[1]):
    exts += f'[ext_resource type="{kind}" path="{path}" id="{i}"]\n'
subs = '''
[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.05, 0.045, 0.045, 1)
ambient_light_source = 2
ambient_light_color = Color(0.56, 0.53, 0.5, 1)
ambient_light_energy = 0.7
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.2, 0.18, 0.17, 1)
fog_density = 0.004
'''
sx, sy, sz = START
root = f'''
[node name="Castle" type="Node3D"]
script = ExtResource("{level_script}")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 20, 0)
light_color = Color(0.9, 0.88, 0.85, 1)
light_energy = 0.15
shadow_enabled = false

[node name="StartPoint" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, {sx}, {sy + 0.05}, {sz})

[node name="Geometry" type="Node3D" parent="."]

[node name="Floors" type="Node3D" parent="."]

[node name="Walls" type="Node3D" parent="."]

[node name="Pillars" type="Node3D" parent="."]

[node name="Ceilings" type="Node3D" parent="."]

[node name="Stairs" type="Node3D" parent="."]

[node name="Torches" type="Node3D" parent="."]

[node name="Zones" type="Node3D" parent="."]

[node name="Collectibles" type="Node3D" parent="."]

[node name="Checkpoints" type="Node3D" parent="."]

[node name="Tomes" type="Node3D" parent="."]

[node name="Doors" type="Node3D" parent="."]

[node name="Furniture" type="Node3D" parent="."]

[node name="Enemies" type="Node3D" parent="."]

'''
header = f'[gd_scene load_steps={len(ext) + 2} format=3 uid="uid://castle0000001"]\n\n'
open(OUT, "w").write(header + exts + subs + root + "\n".join(nodes) + "\n")
print("name keys:", " ".join(sorted({r.name_key for r in rooms.values()})))
print(f"rooms: {len(rooms)}  wall units: {len(units)}  doors: {len(doors)}  secrets: {len(secrets)}  stairs: {len(stairs)}  torches: {torch_count}  furniture: {furniture_count}  enemies: {enemy_count}  nodes: {len(nodes)}")

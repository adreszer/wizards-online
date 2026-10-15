"""The castle model: rooms on a 4 m grid and the connections between them.

A Plan is pure data (rooms, doorways, secret walls, stair flights, landings).
It is produced by the program loader (content/castle/program.json) or by the
layout generator, checked by rules.py and turned into a scene by build.py.

Conventions:
  - plan view +X east, +Z south; grid 4 m; walls 0.35 m thick centred on room boundaries
  - storey pitch 9 m: walls 0..8 m (two rows), ceiling tile at 8 m, next floor top at 9 m
  - a room spanning `bands` storeys is that many bands tall (great hall: 17 m)
"""
import math

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

SIDES = "wens"
OPPOSITE = {"w": "e", "e": "w", "n": "s", "s": "n"}


class PlanError(Exception):
    """A declaration that cannot be built (bad coordinates, rooms that do not touch…)."""


def check(cond, msg):
    if not cond:
        raise PlanError(msg)


class Room:
    def __init__(self, id, x0, x1, z0, z1, storey=0, bands=1, kind="room", ceiling=True,
                 rows=2, pillars=True, torches=True, tile="plain", house=0, inside=None,
                 torch_spacing=8.0, name_key=None, **extra):
        for v in (x0, x1, z0, z1):
            check(v % 4 == 0, f"{id}: coordinates must be on the 4 m grid ({v})")
        check(x1 > x0 and z1 > z0, f"{id}: empty rectangle")
        self.id = id; self.x0 = x0; self.x1 = x1; self.z0 = z0; self.z1 = z1
        self.storey = storey; self.bands = bands; self.kind = kind; self.ceiling = ceiling
        self.rows = rows; self.pillars = pillars; self.torches = torches; self.tile = tile
        self.house = house; self.inside = inside; self.torch_spacing = torch_spacing
        self.name_key = name_key or ("AREA_" + id.upper())
        # Program attributes that only some rooms carry: front (classroom teaching wall),
        # no_window_sides, door_style ("grand" | "locked"), dressing, sector, wing, public…
        self.extra = dict(extra)
        self.holes = []          # floor cut-outs (stair arrivals from below)
        self.ceiling_holes = []  # ceiling cut-outs (stairs leaving upward)
        self.no_torch_sides = set()
        self.extra_floors = []   # (rect, y) landings inside tall rooms

    def get(self, key, default=None):
        return self.extra.get(key, default)

    @property
    def y(self): return self.storey * STOREY
    @property
    def top_storey(self): return self.storey + self.bands - 1
    @property
    def ceiling_y(self): return self.top_storey * STOREY + BAND_H
    @property
    def rect(self): return (self.x0, self.x1, self.z0, self.z1)
    @property
    def width(self): return self.x1 - self.x0
    @property
    def depth(self): return self.z1 - self.z0
    def storeys(self): return range(self.storey, self.storey + self.bands)
    def centre(self): return ((self.x0 + self.x1) / 2, (self.z0 + self.z1) / 2)

    def wall_line(self, side):
        """(axis, coord, lo, hi) of one of the room's walls. axis 'z' = wall along Z at x=coord."""
        if side in "we":
            return "z", (self.x0 if side == "w" else self.x1), self.z0, self.z1
        return "x", (self.z0 if side == "n" else self.z1), self.x0, self.x1

    def side_of(self, axis, coord):
        """Which of the room's walls lies on (axis, coord), or None."""
        if axis == "z":
            return "w" if coord == self.x0 else "e" if coord == self.x1 else None
        return "n" if coord == self.z0 else "s" if coord == self.z1 else None


def overlaps(a, b):
    return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1


def shared_edge(A, B):
    """Wall line shared by two rooms: (axis, coord, lo, hi). axis 'z' = wall along Z at x=coord."""
    if A.x1 == B.x0 or B.x1 == A.x0:
        coord = A.x1 if A.x1 == B.x0 else A.x0
        lo, hi = max(A.z0, B.z0), min(A.z1, B.z1)
        check(hi - lo >= 4, f"{A.id}/{B.id} do not share a wall")
        return "z", coord, lo, hi
    if A.z1 == B.z0 or B.z1 == A.z0:
        coord = A.z1 if A.z1 == B.z0 else A.z0
        lo, hi = max(A.x0, B.x0), min(A.x1, B.x1)
        check(hi - lo >= 4, f"{A.id}/{B.id} do not share a wall")
        return "x", coord, lo, hi
    raise PlanError(f"{A.id} and {B.id} are not adjacent")


def door_offsets(lo, hi, at, count):
    """`at` is the start of the 4 m door segment (count=1) or the centre line of a
    double opening (count=2); None picks the middle of the shared wall."""
    n = (hi - lo) // 4
    if at is None:
        at = lo + 4 * ((n - count) // 2) + 2 * count
    start = math.floor((at - 2 * count) / 4 + 0.5) * 4
    offs = [start + 4 * i for i in range(count)]
    for off in offs:
        check(lo <= off and off + 4 <= hi, f"door at {at} outside {lo}..{hi}")
    return offs


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


def rect_overlap(a, b, eps=1e-6):
    return a[0] < b[1] - eps and b[0] < a[1] - eps and a[2] < b[3] - eps and b[2] < a[3] - eps


class Plan:
    """Everything the builder needs, as data."""

    def __init__(self):
        self.rooms = {}
        self.doors = []         # (axis, coord, off, storey)
        self.house_gates = []   # (axis, coord, off, storey, house, area): doorways that get a HouseDoor
        self.secrets = []       # (a, b, axis, coord, off, storey, name)
        self.stairs = []        # dicts (see stair())
        self.edges = []         # (a, b, how) connectivity: how in door | secret | stair
        self.door_rooms = {}    # (axis, coord, off, storey) -> (room a, room b, openings in that doorway)
        self.parapets = []      # (centre, size) railings placed by the program
        self.start = (0.0, 0.0, 84.0)
        self.meta = {}

    # -- declarations ---------------------------------------------------------------------
    def room(self, id, x0, x1, z0, z1, storey=0, **kw):
        check(id not in self.rooms, f"duplicate room {id}")
        r = Room(id, x0, x1, z0, z1, storey, **kw)
        self.rooms[id] = r
        return r

    def door(self, a, b, at=None, storey=None, count=1):
        A, B = self.rooms[a], self.rooms[b]
        axis, coord, lo, hi = shared_edge(A, B)
        if storey is None:
            storey = max(A.storey, B.storey)
        check(storey in A.storeys() and storey in B.storeys(), f"door {a}/{b}: storey {storey}")
        for off in door_offsets(lo, hi, at, count):
            self.doors.append((axis, coord, off, storey))
            self.door_rooms[(axis, coord, off, storey)] = (a, b, count)
            # A doorway into a house area (common room, dormitory, house landing) gets a gate.
            if A.house != B.house:
                self.house_gates.append((axis, coord, off, storey, A.house or B.house, a if A.house else b))
        self.edges.append((a, b, "door"))

    def door_on(self, a, side, at, storey=None, count=1, to=None):
        """Doorway on a room's own wall (rooms nested inside a bigger outdoor area)."""
        A = self.rooms[a]
        storey = A.storey if storey is None else storey
        axis, coord, lo, hi = A.wall_line(side)
        for off in door_offsets(lo, hi, at, count):
            self.doors.append((axis, coord, off, storey))
            self.door_rooms[(axis, coord, off, storey)] = (a, to or A.inside, count)
        self.edges.append((a, to or A.inside, "door"))

    def secret(self, a, b, at=None, storey=None, name="secret_wall"):
        """A SecretWall in the wall between a (where the ornament is seen) and b (hidden room).
        Its object id is "<b>/<name>"."""
        A, B = self.rooms[a], self.rooms[b]
        axis, coord, lo, hi = shared_edge(A, B)
        if storey is None:
            storey = max(A.storey, B.storey)
        off = door_offsets(lo, hi, at, 1)[0]
        self.secrets.append((a, b, axis, coord, off, storey, name))
        self.edges.append((a, b, "secret"))

    def stair(self, lo, hi, side, direction, start, run=STAIR_RUN, width=STAIR_WIDTH, rise=STOREY,
              hole=True, y=None, kind="straight", **extra):
        """Straight flight inside room `lo` hugging wall `side` ('e','w','n','s'), climbing
        toward `direction` ('n','s','e','w') from coordinate `start` along that wall.
        Cuts the arrival hole in `hi`'s floor and `lo`'s ceiling (hole=True)."""
        L = self.rooms[lo]
        inset = T / 2 + 0.05 + width / 2
        if side == "e": x, z = L.x1 - inset, start
        elif side == "w": x, z = L.x0 + inset, start
        elif side == "n": x, z = start, L.z0 + inset
        else: x, z = start, L.z1 - inset
        rot = {"n": 90.0, "s": -90.0, "e": 0.0, "w": 180.0}[direction]
        L.no_torch_sides.add(side)
        st = dict(lo=lo, hi=hi, x=x, z=z, rot=rot, run=run, width=width, rise=rise, hole=hole, side=side,
                  direction=direction, kind=kind)
        st.update(extra)
        if y is not None:
            st["y"] = y
        self.stairs.append(st)
        if hi is not None:
            self.edges.append((lo, hi, "stair"))
        return st

    # -- queries --------------------------------------------------------------------------
    def stair_y(self, st):
        return st.get("y", self.rooms[st["lo"]].y)

    def stair_footprint(self, st):
        """(x0, x1, z0, z1) of a flight's treads in plan."""
        corners = [local_to_world(st["x"], st["z"], st["rot"], (lx, lz))
                   for lx in (0.0, st["run"]) for lz in (-st["width"] / 2, st["width"] / 2)]
        xs = [c[0] for c in corners]; zs = [c[1] for c in corners]
        return (min(xs), max(xs), min(zs), max(zs))

    def adjacency(self, allow=("door", "secret", "stair")):
        adj = {}
        for a, b, how in self.edges:
            if how in allow:
                adj.setdefault(a, set()).add(b); adj.setdefault(b, set()).add(a)
        return adj

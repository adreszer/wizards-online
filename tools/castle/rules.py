"""Castle rules as validators (ids from docs/castle-generation.md, section 3).

Each rule is a function plan -> list of messages. validate() runs them all and
returns Violations; the generator refuses to write anything while one remains.
"""
from collections import deque

from .geometry import overlaps

RULES = []


class Violation:
    def __init__(self, rule, where, message):
        self.rule = rule; self.where = where; self.message = message

    def __str__(self):
        return f"[{self.rule}] {self.where}: {self.message}"


def rule(rule_id, title):
    def deco(fn):
        RULES.append((rule_id, title, fn))
        return fn
    return deco


def validate(plan, only=None):
    out = []
    for rule_id, _title, fn in RULES:
        if only and rule_id not in only:
            continue
        for where, message in fn(plan):
            out.append(Violation(rule_id, where, message))
    return out


def reachable(plan, root, allow=("door", "secret", "stair"), blocked=()):
    adj = plan.adjacency(allow)
    seen = {root}; queue = deque([root])
    while queue:
        n = queue.popleft()
        for m in adj.get(n, ()):
            if m not in seen and m not in blocked:
                seen.add(m); queue.append(m)
    return seen


DOOR_KINDS = ("classroom", "room", "dormitory", "common_room", "library", "tower")


def has_leaves(plan, key):
    """Does this doorway get door leaves (mirrors build.emit_castle_doors / house gates)?"""
    a, b, count = plan.door_rooms[key]
    A, B = plan.rooms[a], plan.rooms[b]
    if A.house != B.house:
        return True
    if count > 1 or "grand" in (A.get("door_style"), B.get("door_style")):
        return True
    return A.kind in DOOR_KINDS or B.kind in DOOR_KINDS


def room_levels(plan, r):
    """Storeys where room r has something to stand on: its floor, landings, a spiral's turns."""
    levels = {r.storey}
    for _rect, y in r.extra_floors:
        levels.add(int(round(y / 9.0)))
    if r.kind == "stair_turret":
        levels.update(r.storeys())
    return levels


def level_edges(plan):
    """(node, node, how) with nodes (room id, storey)."""
    out = []
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        out.append(((a, s), (b, s), "door"))
    for a, b, _ax, _c, _off, s, _n in plan.secrets:
        out.append(((a, s), (b, s), "secret"))
    for a, b in getattr(plan, "terrain_links", []):
        out.append(((a, plan.rooms[a].storey), (b, plan.rooms[b].storey), "door"))
    for st in plan.stairs:
        if st.get("kind") == "spiral":
            R = plan.rooms[st["lo"]]
            ss = sorted(R.storeys())
            for s0, s1 in zip(ss, ss[1:]):
                out.append(((R.id, s0), (R.id, s1), "stair"))
            continue
        y0 = plan.stair_y(st)
        lo = (st["lo"], int(round(y0 / 9.0)))
        hi = (st["hi"] or st["lo"], int(round((y0 + st["rise"]) / 9.0)))
        out.append((lo, hi, "stair"))
    return out


def reachable_levels(plan, allow=("door", "secret", "stair"), blocked=(), skip=None):
    edges = [e for i, e in enumerate(level_edges(plan)) if e[2] in allow and i != skip]
    adj = {}
    for a, b, _h in edges:
        adj.setdefault(a, set()).add(b); adj.setdefault(b, set()).add(a)
    # Inside a room, one level leads to no other (tall rooms are crossed by their flights).
    start = ("grounds", 0)
    seen = {start}; queue = deque([start])
    while queue:
        n = queue.popleft()
        for m in adj.get(n, ()):
            if m not in seen and m[0] not in blocked:
                seen.add(m); queue.append(m)
    return {rid for rid, _s in seen}


@rule("C11", "every doorway opens onto something to stand on at its storey")
def doorway_levels(plan):
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        for rid in (a, b):
            if s not in room_levels(plan, plan.rooms[rid]):
                yield rid, f"doorway {a}/{b} on storey {s} opens into the air"


@rule("C0", "rooms on the same storey never overlap")
def no_overlap(plan):
    ids = list(plan.rooms)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            A, B = plan.rooms[a], plan.rooms[b]
            if A.inside == b or B.inside == a or A.get("terrain") or B.get("terrain"):
                continue
            if set(A.storeys()) & set(B.storeys()) and overlaps(A, B):
                yield a, f"overlaps {b}"


@rule("C1", "every room is reachable from the grounds")
def all_reachable(plan):
    seen = reachable_levels(plan)
    for r in plan.rooms:
        if r not in seen:
            yield r, "unreachable"


# --------------------------------------------------------------------------- helpers
import math as _math

from . import circulation as _c
from .geometry import STOREY as _STOREY, T as _T, rect_overlap as _rect_overlap

PUBLIC_KINDS = {"hall", "corridor", "classroom", "library", "room", "outdoor", "tower", "stair_turret", "shaft", "common_room", "dormitory"}
STAIR_ROOM_KINDS = {"hall", "corridor", "stair_turret", "shaft", "landing"}
MIN_SIZE = {"classroom": (16, 16), "common_room": (16, 16), "dormitory": (16, 16), "library": (24, 40)}
GREAT_HALL_MIN = (32, 40)
DOOR_SWING = 2.0
GATE = {"x": 0, "z": 48, "facing": "s"}
ENTRANCE_RECT = (-12, 12, 24, 48)
START = (0.0, 0.0, 84.0)


def waived(plan, rule_id, where):
    return any(w.get("rule") == rule_id and w.get("where") == where for w in plan.waivers)


def interior(r, margin=_T / 2):
    return (r.x0 + margin, r.x1 - margin, r.z0 + margin, r.z1 - margin)


def rect_inside(inner, outer, eps=0.02):
    return inner[0] >= outer[0] - eps and inner[1] <= outer[1] + eps and inner[2] >= outer[2] - eps and inner[3] <= outer[3] + eps


def flights(plan):
    return [st for st in plan.stairs if st.get("kind") != "spiral"]


def stair_name(st):
    return f"{st['lo']}->{st['hi'] or 'landing'}@{st['x']:.1f},{st['z']:.1f}"


def door_swing_rects(plan, storey):
    """Rects a door leaf sweeps (both sides of each doorway) on a storey."""
    out = []
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        if s != storey or not has_leaves(plan, (axis, coord, off, s)):
            continue
        if axis == "x":
            out.append(((off, off + 4, coord - DOOR_SWING, coord + DOOR_SWING), a, b))
        else:
            out.append(((coord - DOOR_SWING, coord + DOOR_SWING, off, off + 4), a, b))
    return out


def surface_at(plan, x, z, y):
    """Is (x, z, y) on a landing / room floor that a flight can start or end on?"""
    return _c.walkable(plan, x, z, y)


# --------------------------------------------------------------------------- anchors
@rule("A1", "the main gate, entrance hall and start point never move")
def fixed_entrance(plan):
    gate = plan.meta.get("gate")
    if gate != GATE:
        yield "gate", f"program gate is {gate}, must be {GATE}"
    e = plan.rooms.get("entrance_hall")
    if e is None or e.rect != ENTRANCE_RECT or e.storey != 0:
        yield "entrance_hall", f"must be {ENTRANCE_RECT} on storey 0"
    if tuple(plan.start) != START:
        yield "start", f"start point {plan.start} must be {START}"
    gate_doors = [k for k, v in plan.door_rooms.items() if set(v[:2]) == {"grounds", "entrance_hall"}]
    if sorted(k[2] for k in gate_doors) != [-4, 0] or any(k[:2] != ("x", 48) or k[3] != 0 for k in gate_doors):
        yield "gate", f"the gate must be a double doorway centred on x 0 in the wall z 48 ({gate_doors})"


@rule("A3", "the entrance hall opens onto the great hall, the stair hall and the courtyard")
def hub(plan):
    linked = {b for a, b, how in plan.edges if a == "entrance_hall" and how == "door"} | \
             {a for a, b, how in plan.edges if b == "entrance_hall" and how == "door"}
    for need in ("great_hall", "stair_hall", "courtyard", "grounds"):
        if need not in linked:
            yield "entrance_hall", f"no doorway to {need}"


# --------------------------------------------------------------------------- stairs
@rule("S1", "a clear 4 m approach landing before every flight")
def approach_landing(plan):
    for st in flights(plan):
        a = st["approach"]
        for msg in _clear_landing(plan, st, a, st["y0"], "approach"):
            yield stair_name(st), msg


@rule("S2", "a clear 4 m arrival landing past every flight")
def arrival_landing(plan):
    for st in flights(plan):
        a = st["arrival"]
        for msg in _clear_landing(plan, st, a, st["y0"] + st["rise"], "arrival"):
            yield stair_name(st), msg


def _clear_landing(plan, st, rect, y, what):
    host = None
    for r in plan.rooms.values():
        if r.y <= y + 0.05 and y <= r.ceiling_y and rect_inside(rect, interior(r, _T / 2 - 0.01)):
            host = r
            break
    if host is None:
        yield f"{what} {_fmt(rect)} at y {y:.1f} is not inside one room (it meets a wall)"
        return
    x0, x1, z0, z1 = rect
    for i in range(5):
        for j in range(5):
            px, pz = x0 + (x1 - x0) * (i + 0.5) / 5, z0 + (z1 - z0) * (j + 0.5) / 5
            if not surface_at(plan, px, pz, y):
                yield f"{what} at ({px:.1f}, {pz:.1f}) y {y:.1f} has no floor"
                return
    for other in flights(plan):
        if other is st:
            continue
        if _rect_overlap(rect, other["footprint"]) and other["y0"] - 0.05 <= y + _c.HEADROOM and y - 0.05 <= other["y0"] + other["rise"]:
            # The other flight passes over this landing: only allowed with full headroom.
            low = _lowest_tread_over(other, rect)
            if low - 1.0 < y + _c.HEADROOM:
                yield f"{what} runs into the flight {stair_name(other)}"
    storey = int(round(y / _STOREY))
    if abs(storey * _STOREY - y) < 0.05:
        for swing, a, b in door_swing_rects(plan, storey):
            if host.id in (a, b) and _rect_overlap(rect, swing):
                yield f"{what} lies in the swing of the doorway {a}/{b}"


def _lowest_tread_over(st, rect):
    lo = None
    for k in range(41):
        lx = st["run"] * k / 40
        px, pz = _c.local_to_world(st["x"], st["z"], st["rot"], (lx, 0))
        fr = _c.flight_rect(st, max(0, lx - 0.2), min(st["run"], lx + 0.2))
        if _rect_overlap(fr, rect):
            h = st["y0"] + _c.tread_height(st, lx)
            lo = h if lo is None else min(lo, h)
    return lo if lo is not None else 1e9


def _fmt(rect):
    return "(" + ", ".join(f"{v:.1f}" for v in rect) + ")"


@rule("S3", "2.6 m of headroom over every tread")
def headroom(plan):
    for st in flights(plan):
        L = plan.rooms[st["lo"]]
        worst = None
        for k in range(1, 60):
            lx = st["run"] * k / 60
            h = st["y0"] + _c.tread_height(st, lx)
            for lz in (-st["width"] / 2 + 0.2, 0.0, st["width"] / 2 - 0.2):
                px, pz = _c.local_to_world(st["x"], st["z"], st["rot"], (lx, lz))
                over = _overhead(plan, st, px, pz, h)
                if over is not None and over - h < _c.HEADROOM - 1e-3:
                    if worst is None or over - h < worst[0]:
                        worst = (over - h, px, pz, h)
        if worst:
            yield stair_name(st), f"only {worst[0]:.2f} m of headroom at ({worst[1]:.1f}, {worst[2]:.1f}) tread y {worst[3]:.1f}"


def _overhead(plan, st, x, z, h):
    best = None
    def take(v):
        nonlocal best
        if v > h + 0.01 and (best is None or v < best):
            best = v
    for r in plan.rooms.values():
        if r.get("terrain") or not _c.inside(r.rect, x, z, 0.01):
            continue
        if r.ceiling and not any(_c.inside(c, x, z, -0.01) for c in r.ceiling_holes) and r.ceiling_y > h:
            take(r.ceiling_y)
        if r.y > h and not any(_c.inside(hl, x, z, -0.01) for hl in r.holes):
            take(r.y - _c.FLOOR_THICK)
        for rect, y in r.extra_floors:
            if y > h and _c.inside(rect, x, z, 0.01):
                take(y - _c.LANDING_THICK)
    return best


@rule("S4", "risers at most 0.36 m, treads at least 0.45 m")
def tread_comfort(plan):
    for st in flights(plan):
        n = _c.steps_for(st["rise"])
        if st["rise"] / n > _c.MAX_RISER + 1e-6:
            yield stair_name(st), f"riser {st['rise'] / n:.2f} m"
        if st["run"] / n < _c.MIN_TREAD - 1e-6:
            yield stair_name(st), f"tread {st['run'] / n:.2f} m (run {st['run']} m for {n} steps; use a switchback or a spiral)"


@rule("S5", "towers and small rooms climb by spiral stairs in a stair turret")
def spirals_in_turrets(plan):
    for st in plan.stairs:
        r = plan.rooms[st["lo"]]
        if st.get("kind") == "spiral":
            if r.kind != "stair_turret":
                yield r.id, "a spiral stair needs a stair turret room"
        elif r.kind in ("tower", "stair_turret") or (r.width < 20 and r.depth < 20 and r.kind != "corridor"):
            yield stair_name(st), f"straight flight in {r.kind} {r.id} ({r.width}x{r.depth}); use a stair turret"
    for r in plan.rooms.values():
        if r.kind == "stair_turret":
            if not any(s.get("kind") == "spiral" and s["lo"] == r.id for s in plan.stairs):
                yield r.id, "stair turret without a spiral"
            if r.width not in (8, 12) or r.depth != r.width:
                yield r.id, "stair turrets are 8 x 8 or 12 x 12"


@rule("S6", "no doorway or secret wall on the wall behind a flight")
def wall_behind_flight(plan):
    for st in flights(plan):
        L = plan.rooms[st["lo"]]
        axis, coord, _lo, _hi = L.wall_line(st["side"])
        fx0, fx1, fz0, fz1 = st["footprint"]
        lo, hi = (fz0, fz1) if axis == "z" else (fx0, fx1)
        openings = [(ax, c, off, s, f"doorway {a}/{b}") for (ax, c, off, s), (a, b, _n) in plan.door_rooms.items()]
        openings += [(ax, c, off, s, f"secret wall {a}/{b}") for a, b, ax, c, off, s, _n in plan.secrets]
        for ax, c, off, s, what in openings:
            if ax != axis or c != coord or not (off < hi - 0.01 and off + 4 > lo + 0.01):
                continue
            # Blocked when the flight's underside comes down into the opening (3.5 m tall).
            strip = (max(fx0, off), min(fx1, off + 4), fz0, fz1) if axis == "x" else (fx0, fx1, max(fz0, off), min(fz1, off + 4))
            underside = _lowest_tread_over(st, strip) - 1.0
            floor = s * _STOREY
            if underside < floor + 3.5 and underside + 1.0 > floor + 0.05:
                yield stair_name(st), f"{what} at {off}..{off + 4} (storey {s}) on the wall behind the flight"


@rule("S7", "railings on every open flight side and every landing edge that drops away")
def fall_protection(plan):
    for st in flights(plan):
        for sign in st["open_sides"]:
            lz = sign * (st["width"] / 2 + _c.RAIL_T / 2)
            sx, sz = _c.local_to_world(st["x"], st["z"], st["rot"], (0.0, lz))
            if not any(abs(rl["pos"][0] - sx) < 0.01 and abs(rl["pos"][2] - sz) < 0.01 and rl["rise"] > 0 for rl in plan.railings):
                yield stair_name(st), "open side without a balustrade"
    ends = _c.flight_end_lines(plan)
    for r in plan.rooms.values():
        for rect, y in r.extra_floors:
            x0, x1, z0, z1 = rect
            for side, coord, lo, hi in (("n", z0, x0, x1), ("s", z1, x0, x1), ("w", x0, z0, z1), ("e", x1, z0, z1)):
                if r.side_of("x" if side in "ns" else "z", coord) == side:
                    continue
                for a, b in _c.open_segments(plan, side, coord, lo, hi, y, ends):
                    if not _railed(plan, side, coord, a, b, y):
                        yield r.id, f"landing edge {side} {coord} ({a:.1f}..{b:.1f}) at y {y:.0f} has no parapet"


def _railed(plan, side, coord, a, b, y):
    for rl in plan.railings:
        if abs(rl["pos"][1] - y) > 0.05 or rl["rise"]:
            continue
        if side in "we" and abs(rl["rot"] - 90.0) < 0.1 and abs(abs(rl["pos"][0] - coord) - _c.RAIL_T / 2) < 0.02:
            r0, r1 = rl["pos"][2] - rl["length"], rl["pos"][2]
        elif side in "ns" and abs(rl["rot"]) < 0.1 and abs(abs(rl["pos"][2] - coord) - _c.RAIL_T / 2) < 0.02:
            r0, r1 = rl["pos"][0], rl["pos"][0] + rl["length"]
        else:
            continue
        if r0 <= a + 0.05 and r1 >= b - 0.05:
            return True
    return False


@rule("S8", "flights only in halls, corridors, landings, shafts and stair turrets")
def stair_rooms(plan):
    for st in flights(plan):
        r = plan.rooms[st["lo"]]
        if r.kind not in STAIR_ROOM_KINDS:
            yield stair_name(st), f"flight in a {r.kind}"


def _main_rooms(plan):
    return [r for r in plan.rooms.values()
            if r.house == 0 and r.kind not in ("secret", "tower", "stair_turret", "outdoor", "grounds") and r.get("door_style") != "locked"
            and not r.get("tower")]


@rule("S9", "every upper or lower floor is reached by two independent stair routes")
def two_routes(plan):
    edges = level_edges(plan)
    blocked = {r.id for r in plan.rooms.values() if r.house or r.get("door_style") == "locked"}
    for i, (a, b, how) in enumerate(edges):
        if how != "stair" or a[0] == b[0] and plan.rooms[a[0]].kind == "stair_turret":
            continue
        seen = reachable_levels(plan, allow=("door", "stair"), blocked=blocked, skip=i)
        for r in _main_rooms(plan):
            if r.storey != 0 and r.id not in seen and not waived(plan, "S9", r.id):
                yield r.id, f"cut off when the flight {a[0]}@{a[1]}->{b[0]}@{b[1]} is closed"


# --------------------------------------------------------------------------- circulation and rooms
@rule("C1b", "every public room is reachable without secrets, house gates or locked doors")
def public_reachable(plan):
    blocked = {r.id for r in plan.rooms.values() if r.house or r.get("door_style") == "locked" or r.kind == "secret"}
    seen = reachable_levels(plan, allow=("door", "stair"), blocked=blocked)
    for r in plan.rooms.values():
        if r.id not in blocked and r.id not in seen:
            yield r.id, "only reachable through a secret, a house gate or a locked door"


WALK_BUDGET = {"classroom": 180.0, "common_room": 220.0}


def walking_distances(plan, origin):
    """Shortest walking distance (m) from the origin room's centre to every room, through
    doorway centres and along flights."""
    import heapq
    pts = {}
    links = {}
    def node_for(key, xyz):
        pts[key] = xyz
        return key
    room_nodes = {}
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        p = (off + 2, s * _STOREY, coord) if axis == "x" else (coord, s * _STOREY, off + 2)
        k = node_for(("d", axis, coord, off, s), p)
        room_nodes.setdefault(a, []).append(k); room_nodes.setdefault(b, []).append(k)
    for st in flights(plan):
        if st["hi"] is None:
            continue
        f = _c.local_to_world(st["x"], st["z"], st["rot"], (0, 0))
        t = _c.local_to_world(st["x"], st["z"], st["rot"], (st["run"], 0))
        kf = node_for(("sf", id(st)), (f[0], st["y0"], f[1])); kt = node_for(("st", id(st)), (t[0], st["y0"] + st["rise"], t[1]))
        room_nodes.setdefault(st["lo"], []).append(kf); room_nodes.setdefault(st["hi"], []).append(kt)
        links.setdefault(kf, []).append((kt, _math.hypot(st["run"], st["rise"])))
        links.setdefault(kt, []).append((kf, _math.hypot(st["run"], st["rise"])))
    for rid, r in plan.rooms.items():
        cx, cz = r.centre()
        c = node_for(("c", rid), (cx, r.y, cz))
        ns = room_nodes.get(rid, []) + [c]
        for i, a in enumerate(ns):
            for b in ns[i + 1:]:
                pa, pb = pts[a], pts[b]
                d = abs(pa[0] - pb[0]) + abs(pa[2] - pb[2]) + abs(pa[1] - pb[1]) * 2   # Manhattan inside rooms
                links.setdefault(a, []).append((b, d)); links.setdefault(b, []).append((a, d))
    dist = {("c", origin): 0.0}
    heap = [(0.0, ("c", origin))]
    while heap:
        d, n = heapq.heappop(heap)
        if d > dist.get(n, 1e18):
            continue
        for m, w in links.get(n, ()):
            nd = d + w
            if nd < dist.get(m, 1e18):
                dist[m] = nd; heapq.heappush(heap, (nd, m))
    return {rid: dist.get(("c", rid)) for rid in plan.rooms}


@rule("C2", "classrooms within 180 m and common rooms within 220 m of the great hall")
def walking_budget(plan):
    if "great_hall" not in plan.rooms:
        return
    dist = walking_distances(plan, "great_hall")
    for r in plan.rooms.values():
        limit = WALK_BUDGET.get(r.kind)
        if limit and (dist[r.id] is None or dist[r.id] > limit) and not waived(plan, "C2", r.id):
            yield r.id, f"{dist[r.id] or 0:.0f} m from the great hall (limit {limit:.0f})"


@rule("C3", "corridors at least 8 m wide and never dead ends")
def corridors(plan):
    for r in plan.rooms.values():
        if r.kind == "corridor":
            if min(r.width, r.depth) < 8:
                yield r.id, f"{min(r.width, r.depth)} m wide"
            links = sum(1 for a, b, how in plan.edges if r.id in (a, b))
            if links < 2:
                yield r.id, "dead end"
        if r.kind == "passage" and min(r.width, r.depth) < 4:
            yield r.id, "passages are at least 4 m wide"


@rule("C4", "room proportions and minimum sizes")
def proportions(plan):
    for r in plan.rooms.values():
        if r.kind not in ("corridor", "passage", "outdoor", "grounds", "hall", "gallery", "shaft") and max(r.width, r.depth) > 3 * min(r.width, r.depth):
            yield r.id, f"{r.width} x {r.depth} is longer than 3:1"
        need = MIN_SIZE.get(r.kind)
        if r.id == "great_hall":
            need = GREAT_HALL_MIN
        if need and (min(r.width, r.depth) < need[0] or max(r.width, r.depth) < need[1]) and not waived(plan, "C4", r.id):
            yield r.id, f"{r.width} x {r.depth} below the minimum {need[0]} x {need[1]} for a {r.kind}"


@rule("C5", "classrooms are entered from the back or the side, never the teaching wall")
def classroom_doors(plan):
    for r in plan.rooms.values():
        if r.kind != "classroom" or r.inside is not None:
            continue
        front = r.get("front")
        if not front:
            if r.get("furnish", True):
                yield r.id, "classroom without a teaching wall ('front')"
            continue
        axis, coord, _lo, _hi = r.wall_line(front)
        for (ax, c, off, s), (a, b, _n) in plan.door_rooms.items():
            if ax == axis and c == coord and s in r.storeys() and r.id in (a, b):
                yield r.id, f"doorway {a}/{b} in the teaching wall"


@rule("C6", "each house territory has exactly one gate from public space")
def house_gates(plan):
    gates = {}
    for axis, coord, off, s, house, area in plan.house_gates:
        a, b, _n = plan.door_rooms[(axis, coord, off, s)]
        other = b if a == area else a
        if plan.rooms[other].house == 0:
            gates.setdefault(house, set()).add((a, b))
    houses = {r.house for r in plan.rooms.values() if r.house}
    for h in sorted(houses):
        n = len(gates.get(h, ()))
        if n != 1:
            yield f"house {h}", f"{n} gates from public space ({sorted(gates.get(h, ()))})"


@rule("C7", "doorways keep a module from corners and 4 m from each other")
def door_spacing(plan):
    for r in plan.rooms.values():
        if r.kind in ("outdoor", "grounds", "stair_turret"):
            continue
        for side in "wens":
            axis, coord, lo, hi = r.wall_line(side)
            if hi - lo < 12:
                continue
            for s in r.storeys():
                keys = [k for k, v in plan.door_rooms.items() if k[0] == axis and k[1] == coord and k[3] == s and r.id in v[:2]]
                leaves = {k[2] for k in keys if has_leaves(plan, k)}
                offs = sorted({k[2] for k in keys}
                              | {sc[4] for sc in plan.secrets if sc[2] == axis and sc[3] == coord and sc[5] == s and r.id in sc[:2]})
                for off in offs:
                    if off in leaves and (off == lo or off + 4 == hi) and not waived(plan, "C7", f"{r.id}/{side}/{off}/{s}"):
                        yield r.id, f"doorway at {off} on its {side} wall (storey {s}) is in a corner module"
                for a, b in zip(offs, offs[1:]):
                    if 4 < b - a < 8 and not waived(plan, "C7", f"{r.id}/{side}/{a}/{s}"):
                        yield r.id, f"doorways at {a} and {b} on its {side} wall are closer than 4 m"


@rule("C9", "upper rooms stand on rooms below (or are corbelled turrets)")
def structure(plan):
    for r in plan.rooms.values():
        if r.storey <= 0 or r.inside is not None:
            continue
        if r.get("support") == "bridge":
            ends = [n for n in plan.rooms.values() if n.id != r.id and not n.get("terrain") and n.storey <= r.storey <= n.top_storey and _touches(n, r)]
            if len(ends) < 2 or min(r.width, r.depth) > 12:
                yield r.id, "a bridge spans at most 12 m wide between two rooms on its storey"
            continue
        if r.get("support") == "corbel":
            if min(r.width, r.depth) > 8:
                yield r.id, "a corbelled room reaches out at most 8 m"
            elif not any(n.storey <= r.storey <= n.top_storey and n.id != r.id and _touches(n, r) for n in plan.rooms.values()):
                yield r.id, "a corbelled room hangs off a neighbour on the same storey"
            continue
        below = [b for b in plan.rooms.values() if b.top_storey == r.storey - 1 and b.inside is None]
        x0, x1, z0, z1 = r.rect
        missing = 0
        for i in range(int((x1 - x0) // 4)):
            for j in range(int((z1 - z0) // 4)):
                px, pz = x0 + 4 * i + 2, z0 + 4 * j + 2
                if not any(_c.inside(b.rect, px, pz) for b in below):
                    missing += 1
        if missing:
            yield r.id, f"{missing * 16} m2 of its floor stands on nothing"


def _touches(a, b):
    return ((a.x1 == b.x0 or b.x1 == a.x0) and min(a.z1, b.z1) - max(a.z0, b.z0) >= 4) or \
           ((a.z1 == b.z0 or b.z1 == a.z0) and min(a.x1, b.x1) - max(a.x0, b.x0) >= 4)


@rule("C10", "room ids are lowercase words")
def room_ids(plan):
    import re
    for rid in plan.rooms:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", rid):
            yield rid, "id must match [a-z][a-z0-9_]*"


@rule("W", "waivers name a rule, a place, the milestone that lifts them and why")
def waiver_shape(plan):
    for w in plan.waivers:
        if not all(w.get(k) for k in ("rule", "where", "until", "why")):
            yield str(w), "incomplete waiver"


@rule("C12", "doorways never open onto a stair hole")
def doors_clear_of_holes(plan):
    holes = [(h, r.storey) for r in plan.rooms.values() for h in r.holes]
    for (axis, coord, off, s), (a, b, _n) in plan.door_rooms.items():
        for sign in (-1, 1):
            if axis == "x":
                thr = (off, off + 4, min(coord, coord + sign * 1.6), max(coord, coord + sign * 1.6))
            else:
                thr = (min(coord, coord + sign * 1.6), max(coord, coord + sign * 1.6), off, off + 4)
            for h, hs in holes:
                if hs == s and _rect_overlap(thr, h):
                    yield f"{a}/{b}", f"doorway on storey {s} opens onto the stair hole {_fmt(h)}"

"""Derived circulation geometry: everything about stairs that rules and builder share.

derive(plan) fills, for every straight flight:
  footprint   plan rect of the treads
  approach    4 m clear rect before the foot, at the foot's level (rule S1)
  arrival     4 m clear rect past the top step, at the top's level (rule S2)
  hole / pad  the cut in the floor above (and the room's ceiling) and the slab that
              carries the player from the top step to the hole's far edge
  open_sides  local z signs (+1 / -1) of the flight's sides that are not against a wall
and for every spiral (stair turret): its centre, half size, turns and start angle.

It also collects plan.railings (balustrades on open flight sides, parapets on landing
and hole edges: rule S7), plan.pads (extra walkable slabs) and plan.keepout (rects where
pillars may not stand).
"""
import math

from .geometry import (STOREY, T, MODULE, local_to_world, snap_rect, rect_overlap, PlanError, check)

APPROACH = 4.0          # S1 / S2 landing length
HEADROOM = 2.6          # S3
MAX_RISER = 0.36        # S4 (PlayerMovement.step_height is 0.42)
MIN_TREAD = 0.45
HOLE_FROM_HEIGHT = 5.4  # treads above this need the ceiling / floor above cut open (8 m ceiling - headroom)
FLOOR_THICK = 0.5       # bottom of a floor slab below its top (upper storeys)
LANDING_THICK = 1.0
RAIL_HEIGHT = 1.0
RAIL_T = 0.25
SPIRAL_STEPS = 25       # per storey
SPIRAL_COLUMN = 0.5


def steps_for(rise):
    return max(1, math.ceil(rise / MAX_RISER - 1e-4))


def flight_rect(st, lx0, lx1, lz0=None, lz1=None):
    w = st["width"] / 2
    lz0 = -w if lz0 is None else lz0
    lz1 = w if lz1 is None else lz1
    pts = [local_to_world(st["x"], st["z"], st["rot"], (lx, lz)) for lx in (lx0, lx1) for lz in (lz0, lz1)]
    xs = [p[0] for p in pts]; zs = [p[1] for p in pts]
    return (min(xs), max(xs), min(zs), max(zs))


def tread_height(st, lx):
    """Top of the tread at local distance lx along the flight (0 before the first step)."""
    if lx <= 0:
        return 0.0
    n = steps_for(st["rise"])
    i = min(n - 1, int(lx / (st["run"] / n)))
    return (i + 1) * st["rise"] / n


def inside(rect, x, z, margin=0.0):
    return rect[0] + margin <= x <= rect[1] - margin and rect[2] + margin <= z <= rect[3] - margin


def derive(plan):
    plan.railings = []
    plan.pads = []
    plan.keepout = []
    for st in plan.stairs:
        if st.get("kind") == "spiral":
            derive_spiral(plan, st)
        else:
            derive_flight(plan, st)
    for st in plan.stairs:
        if st.get("kind") != "spiral":
            flight_railings(plan, st)
    landing_railings(plan)
    return plan


# --------------------------------------------------------------------------- straight flights
def derive_flight(plan, st):
    L = plan.rooms[st["lo"]]
    y = plan.stair_y(st)
    run, w = st["run"], st["width"]
    st["y0"] = y
    st["footprint"] = flight_rect(st, 0.0, run)
    st["approach"] = flight_rect(st, -APPROACH, 0.0)
    st["arrival"] = flight_rect(st, run, run + APPROACH)
    st["steps"] = steps_for(st["rise"])
    # Which lateral side hugs the wall: the side whose edge is nearest the wall line.
    axis, coord, _lo, _hi = L.wall_line(st["side"])
    st["open_sides"] = []
    for sign in (-1, 1):
        px, pz = local_to_world(st["x"], st["z"], st["rot"], (run / 2, sign * w / 2))
        d = abs((px if axis == "z" else pz) - coord)
        if d > T / 2 + 0.3:
            st["open_sides"].append(sign)
    # Pillars keep clear of the treads and both landings.
    for rect, ylo, yhi in ((st["footprint"], y, y + st["rise"]), (st["approach"], y, y), (st["arrival"], y + st["rise"], y + st["rise"])):
        plan.keepout.append((rect, ylo, yhi))
    if not st["hole"] or st["hi"] is None:
        st["hole_rect"] = None
        return
    H = plan.rooms[st["hi"]]
    lx0 = run * HOLE_FROM_HEIGHT / st["rise"]
    hx0, hx1, hz0, hz1 = flight_rect(st, lx0, run)
    hole = snap_rect(hx0, hx1, hz0, hz1)
    hole = (max(hole[0], H.x0), min(hole[1], H.x1), max(hole[2], H.z0), min(hole[3], H.z1))
    st["hole_rect"] = hole
    H.holes.append(hole)
    L.ceiling_holes.append(hole)
    # Landing pad from the top step to the far edge of the hole (the player keeps walking straight).
    end = local_to_world(st["x"], st["z"], st["rot"], (run, 0))
    rot = st["rot"]
    far = {90.0: hole[2], -90.0: hole[3], 0.0: hole[1], 180.0: hole[0]}[rot]
    along = abs((far - end[1]) if rot in (90.0, -90.0) else (far - end[0]))
    st["pad"] = None
    if along > 0.15:
        st["pad"] = flight_rect(st, run, run + along)
        plan.pads.append((st["pad"], y + st["rise"]))


def flight_railings(plan, st):
    """Balustrade on every open side of the flight, parapets round its hole."""
    y = st["y0"]
    for sign in st["open_sides"]:
        lz = sign * (st["width"] / 2 + RAIL_T / 2)
        sx, sz = local_to_world(st["x"], st["z"], st["rot"], (0.0, lz))
        plan.railings.append(dict(pos=(sx, y, sz), rot=st["rot"], length=st["run"], rise=st["rise"], why=f"flight {st['lo']}"))
    hole = st.get("hole_rect")
    if not hole:
        return
    H = plan.rooms[st["hi"]]
    yp = y + st["rise"]
    end = local_to_world(st["x"], st["z"], st["rot"], (st["run"], 0))
    for side in "wens":
        on_wall = (side == "w" and hole[0] == H.x0) or (side == "e" and hole[1] == H.x1) or \
                  (side == "n" and hole[2] == H.z0) or (side == "s" and hole[3] == H.z1)
        if on_wall:
            continue
        if side in "we":
            c = hole[0] if side == "w" else hole[1]
            lo, hi, proj, dist = hole[2], hole[3], end[1], abs(end[0] - c)
        else:
            c = hole[2] if side == "n" else hole[3]
            lo, hi, proj, dist = hole[0], hole[1], end[0], abs(end[1] - c)
        segs = [(lo, hi)]
        if dist <= st["width"] / 2 + 0.6:   # the edge the flight lets out over (the pad)
            segs = [(lo, proj - st["width"] / 2 - 0.1), (proj + st["width"] / 2 + 0.1, hi)]
        for a, b in segs:
            a, b = max(a, lo), min(b, hi)
            if b - a < 0.3:
                continue
            add_edge_railing(plan, side, c, a, b, yp, f"hole {st['hi']}")


def add_edge_railing(plan, side, coord, a, b, y, why):
    """A level parapet on the edge line `coord` (x for w/e, z for n/s) from a to b,
    standing on the walkable side (inside the edge)."""
    inset = RAIL_T / 2
    if side in "we":
        x = coord - inset if side == "w" else coord + inset
        plan.railings.append(dict(pos=(x, y, b), rot=90.0, length=b - a, rise=0.0, why=why))
    else:
        z = coord - inset if side == "n" else coord + inset
        plan.railings.append(dict(pos=(a, y, z), rot=0.0, length=b - a, rise=0.0, why=why))


# --------------------------------------------------------------------------- walkable surfaces
def walkable(plan, x, z, y, eps=0.05):
    """Is there a floor, landing or pad with its top at height y under (x, z)?"""
    for r in plan.rooms.values():
        if abs(r.y - y) < eps and inside(r.rect, x, z) and not any(inside(h, x, z, 0.01) for h in r.holes):
            if r.inside is None and any(c.inside == r.id and inside(c.rect, x, z) for c in plan.rooms.values()):
                continue
            return True
        for rect, ly in r.extra_floors:
            if abs(ly - y) < eps and inside(rect, x, z):
                return True
    for rect, py in plan.pads:
        if abs(py - y) < eps and inside(rect, x, z):
            return True
    return False


def flight_end_lines(plan):
    """(rect, y) of every flight's foot and top edge, where a landing may stay open."""
    out = []
    for st in plan.stairs:
        if st.get("kind") == "spiral":
            continue
        out.append((flight_rect(st, -0.6, 0.6), st["y0"]))
        out.append((flight_rect(st, st["run"] - 0.6, st["run"] + 0.6), st["y0"] + st["rise"]))
    return out


def landing_railings(plan):
    """Parapets on every landing edge that drops away (not against a wall, another walkable
    surface at the same height, or a flight's end)."""
    ends = flight_end_lines(plan)
    for r in plan.rooms.values():
        for rect, y in r.extra_floors:
            x0, x1, z0, z1 = rect
            for side, coord, lo, hi in (("n", z0, x0, x1), ("s", z1, x0, x1), ("w", x0, z0, z1), ("e", x1, z0, z1)):
                if (side == "n" and coord == r.z0) or (side == "s" and coord == r.z1) or \
                   (side == "w" and coord == r.x0) or (side == "e" and coord == r.x1):
                    continue
                for a, b in open_segments(plan, side, coord, lo, hi, y, ends):
                    add_edge_railing(plan, side, coord, a, b, y, f"landing {r.id}")


def open_segments(plan, side, coord, lo, hi, y, ends, step=0.5):
    out = []
    start = None
    n = max(1, int(round((hi - lo) / step)))
    seg = (hi - lo) / n
    for i in range(n):
        m = lo + seg * (i + 0.5)
        out_d = 0.25
        if side in "we":
            px, pz = (coord - out_d if side == "w" else coord + out_d), m
        else:
            px, pz = m, (coord - out_d if side == "n" else coord + out_d)
        at_end = any(abs(ey - y) < 0.05 and inside(rect, px, pz, -0.05) for rect, ey in ends)
        dropping = not walkable(plan, px, pz, y) and not at_end
        if dropping and start is None:
            start = lo + seg * i
        if not dropping and start is not None:
            out.append((start, lo + seg * i)); start = None
    if start is not None:
        out.append((start, hi))
    return out


# --------------------------------------------------------------------------- spiral turrets
def derive_spiral(plan, st):
    """A stair turret: one tall square room whose spiral climbs from its bottom floor to its
    top storey; every doorway into it sits where a turn ends level with that storey."""
    R = plan.rooms[st["lo"]]
    check(R.width == R.depth, f"{R.id}: a stair turret must be square")
    cx, cz = R.centre()
    st["x"], st["z"] = cx, cz
    st["half"] = R.width / 2 - T / 2 - 0.02
    st["turns"] = R.bands - 1 if st.get("turns") is None else st["turns"]
    st["rise_per_turn"] = STOREY
    st["steps_per_turn"] = SPIRAL_STEPS
    st["y0"] = R.y
    st["rise"] = st["turns"] * STOREY
    # The doorway angle: all of the turret's doorways must line up (same wall, same module).
    doors = [(k, v) for k, v in plan.door_rooms.items() if R.id in v[:2]]
    check(doors, f"{R.id}: a stair turret needs a doorway")
    segs = {(k[0], k[1], k[2]) for k, _v in doors}
    check(len(segs) == 1, f"{R.id}: every doorway of a stair turret must use the same wall module ({sorted(segs)})")
    axis, coord, off = next(iter(segs))
    dx, dz = (off + 2 - cx, coord - cz) if axis == "x" else (coord - cx, off + 2 - cz)
    door_angle = math.atan2(dz, dx)
    da = 2 * math.pi / SPIRAL_STEPS
    st["start_angle"] = math.degrees(door_angle + da / 2)
    st["door_angle"] = math.degrees(door_angle)
    st["door_storeys"] = sorted(k[3] for k, _v in doors)
    st["footprint"] = R.rect
    st["approach"] = None
    st["arrival"] = None
    st["open_sides"] = []
    plan.keepout.append((R.rect, R.y, R.ceiling_y))


def spiral_tread(st, angle_deg, turn_floor):
    """Tread top under the angle on the turn that starts at storey offset turn_floor."""
    rel = (math.radians(angle_deg) - math.radians(st["start_angle"])) % (2 * math.pi)
    i = int(rel / (2 * math.pi / st["steps_per_turn"]))
    return st["y0"] + turn_floor * STOREY + (i + 1) * STOREY / st["steps_per_turn"]

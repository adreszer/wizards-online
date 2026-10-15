"""Set pieces that move (docs/castle-generation.md, section 4): derived after the layout,
before circulation.derive (which cuts the parapet gaps they need).

plan.movers: dicts the builder turns into nodes
  shifting_stair  {pivot (x, y, z), stops [yaw deg], rise, run, width, hold, move, phase, room, storey,
                   gates: [{pos, rot, length, stop}]}
  gear            {pos, radius, speed, phase, room}           (ScheduledMover SPIN)
plan.trick_steps: [(x, y, z, yaw)]
plan.mover_ends: [(rect, y)] landing edges a mover meets (left open by the parapets)

Hall of Turning Stairs (rooms of kind "shaft"): per storey one flight hinged on the ring
at the doorway side, swinging between two landing tongues on the ring above (one each
side). Clockwork loft (rooms with "clockwork": true): spinning gear platforms climbing in a
spiral to a clock-face ledge.
"""
import math

from .geometry import STOREY, T

SHIFT_RUN = 12.0
SHIFT_RISE = STOREY
SHIFT_WIDTH = 3.2
TONGUE_DEPTH = 4.0
TONGUE_LEN = 6.0
HOLD = 24.0
MOVE = 7.0


def yaw_to(dx, dz):
    """Yaw (deg) that turns local +X toward (dx, dz) (ScheduledMover rotates basis about Y)."""
    return math.degrees(math.atan2(-dz, dx))


def prepare(plan):
    plan.movers = []
    plan.trick_steps = []
    plan.mover_ends = []
    for r in list(plan.rooms.values()):
        if r.kind == "shaft":
            turning_stairs(plan, r)
        if r.get("clockwork"):
            clockwork(plan, r)
    for st in plan.stairs:
        if st.get("shaft"):
            # The ninth tread of every fixed flight in the shaft is a trick step.
            n = 25
            lx = SHIFT_RUN * 8.5 / n
            from .geometry import local_to_world
            x, z = local_to_world(st["x"], st["z"], st["rot"], (lx, 0))
            plan.trick_steps.append((x, st["y"] + SHIFT_RISE * 9 / n, z, st["rot"]))
    return plan


def turning_stairs(plan, R):
    ring = R.get("ring", 8)
    ix0, ix1, iz0, iz1 = R.x0 + ring, R.x1 - ring, R.z0 + ring, R.z1 - ring
    cx, cz = (ix0 + ix1) / 2, (iz0 + iz1) / 2
    # The doorway side: the wall the corridors come in through.
    door_sides = {R.side_of(k[0], k[1]) for k, v in plan.door_rooms.items() if R.id in v[:2]}
    side = sorted(door_sides)[0] if door_sides else "s"
    # Pivot on the ring's inner edge, middle of the doorway side; tongues on the two
    # neighbouring sides where the flight's top (run 12) reaches the ring above. The flight
    # reaches 8.5 m sideways at most; the tongues stretch out of the side rings to meet it.
    half = ((ix1 - ix0) if side in "ns" else (iz1 - iz0)) / 2
    along = min(half - TONGUE_DEPTH, 8.5)
    reach_in = half - along                      # the tongue's free edge is this far into the void
    fwd = math.sqrt(max(0.0, SHIFT_RUN ** 2 - along ** 2))
    if side == "s":
        pivot, inward, lateral = (cx, iz1), (0, -1), (1, 0)
    elif side == "n":
        pivot, inward, lateral = (cx, iz0), (0, 1), (-1, 0)
    elif side == "e":
        pivot, inward, lateral = (ix1, cz), (-1, 0), (0, -1)
    else:
        pivot, inward, lateral = (ix0, cz), (1, 0), (0, 1)
    for k, s in enumerate(range(R.storey, R.top_storey)):
        y = s * STOREY
        stops, gates = [], []
        for i, sign in enumerate((1, -1)):
            tx = pivot[0] + lateral[0] * sign * along + inward[0] * fwd
            tz = pivot[1] + lateral[1] * sign * along + inward[1] * fwd
            stops.append(round(yaw_to(tx - pivot[0], tz - pivot[1]), 3))
            # The tongue: TONGUE_LEN along the side ring's inner edge, TONGUE_DEPTH into the void.
            ex = pivot[0] + lateral[0] * sign * half + inward[0] * fwd    # point on the side ring's inner edge
            ez = pivot[1] + lateral[1] * sign * half + inward[1] * fwd
            if lateral[0]:   # side rings are e/w: tongue spans z, protrudes in x
                x_edge = ex - sign * lateral[0] * reach_in
                xa, xb = sorted((ex, x_edge))
                rect = (xa, xb, ez - TONGUE_LEN / 2, ez + TONGUE_LEN / 2)
                gate = dict(pos=(x_edge, y + STOREY, ez + TONGUE_LEN / 2), rot=90.0, length=TONGUE_LEN, stop=i)
                end_rect = (x_edge - 0.6, x_edge + 0.6, rect[2], rect[3])
            else:
                z_edge = ez - sign * lateral[1] * reach_in
                za, zb = sorted((ez, z_edge))
                rect = (ex - TONGUE_LEN / 2, ex + TONGUE_LEN / 2, za, zb)
                gate = dict(pos=(ex - TONGUE_LEN / 2, y + STOREY, z_edge), rot=0.0, length=TONGUE_LEN, stop=i)
                end_rect = (rect[0], rect[1], z_edge - 0.6, z_edge + 0.6)
            R.extra_floors.append((tuple(round(v, 3) for v in rect), y + STOREY))
            plan.mover_ends.append((end_rect, y + STOREY))
            gates.append(gate)
        # Swing the short way round: keep the second heading within 180 degrees of the first.
        stops[1] = round(stops[0] + ((stops[1] - stops[0] + 180.0) % 360.0 - 180.0), 3)
        # The pivot's landing: the ring at the doorway side; the flight's foot stays there.
        foot = (pivot[0] - inward[0] * 0.6, pivot[1] - inward[1] * 0.6)
        plan.mover_ends.append(((foot[0] - 2.2, foot[0] + 2.2, foot[1] - 2.2, foot[1] + 2.2), y))
        plan.movers.append(dict(kind="shifting_stair", room=R.id, storey=s, pivot=(pivot[0], y, pivot[1]), stops=stops,
                                rise=SHIFT_RISE, run=SHIFT_RUN, width=SHIFT_WIDTH, hold=HOLD, move=MOVE,
                                phase=round(k * 11.0, 3), gates=gates))


def clockwork(plan, R):
    """Gears spiralling up the room to a ledge on its far wall (a jump route)."""
    cx, cz = R.centre()
    y = R.y
    n = 5
    for i in range(n):
        a = math.radians(i * 78 + 20)
        plan.movers.append(dict(kind="gear", room=R.id, pos=(cx + 4.0 * math.cos(a), y + 1.0 + 1.2 * i, cz + 4.0 * math.sin(a)),
                                radius=1.8, speed=(18.0 + 6 * i) * (1 if i % 2 == 0 else -1), phase=round(i * 3.7, 3)))
    a = math.radians(n * 78 + 20)
    lx, lz = cx + 5.6 * math.cos(a), cz + 5.6 * math.sin(a)
    R.extra["clock_ledge"] = (lx, y + 1.0 + 1.2 * n, lz)


def mover_top(m, stop):
    """Plan position and height of a shifting stair's top step centre at a stop."""
    a = math.radians(m["stops"][stop])
    px, py, pz = m["pivot"]
    return px + m["run"] * math.cos(a), py + m["rise"], pz - m["run"] * math.sin(a)

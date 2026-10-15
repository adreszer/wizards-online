"""Budgets B1 and B2 (docs/castle-generation.md, 3.6), checked on what the builder placed.

B1  per 24 m cell per storey: at most CELL_MODULES batched modules (wall stones, floor and
    ceiling tiles, pillars, furniture) and CELL_LIGHTS lights (torches, chandeliers).
B2  per room: at most max(ROOM_LIGHTS_MIN, floor area / M2_PER_LIGHT) lights.
Caps were set in Milestone 28 from the measured castle with headroom (perf_castle.tscn:
the 5x stress fixture runs at 2.5-7.5 ms a frame with these densities).
"""
from collections import defaultdict

from .geometry import STOREY, MODULE

CELL = 24.0
CELL_MODULES = 420
CELL_LIGHTS = 14
ROOM_LIGHTS_MIN = 6
M2_PER_LIGHT = 36.0
LIGHT_SCENES = ("wall_torch.tscn", "chandelier.tscn")
MODULE_PARENTS = ("Pillars", "Furniture")


def cell_of(x, y, z):
    return (int(x // CELL), int((y + 0.5) // STOREY), int(z // CELL))


def measure(plan, units, placed):
    modules = defaultdict(int)
    lights = defaultdict(int)
    room_lights = defaultdict(int)
    for (axis, coord, off, s), u in units.items():
        x, z = (off + 2, coord) if axis == "x" else (coord, off + 2)
        modules[cell_of(x, s * STOREY, z)] += u["rows"]
    for r in plan.rooms.values():
        if r.get("terrain"):
            continue
        tiles = int(r.width // MODULE) * int(r.depth // MODULE)
        cx, cz = r.centre()
        modules[cell_of(cx, r.y, cz)] += tiles * (2 if r.ceiling else 1)
    for parent, pos, path in placed:
        if parent in MODULE_PARENTS:
            modules[cell_of(*pos)] += 1
        if path.endswith(LIGHT_SCENES):
            y = pos[1] - (STOREY - 1 if path.endswith("chandelier.tscn") else 0)
            lights[cell_of(pos[0], y, pos[2])] += 1
            for r in plan.rooms.values():
                if not r.get("terrain") and r.x0 <= pos[0] <= r.x1 and r.z0 <= pos[2] <= r.z1 and r.y - 0.5 <= y <= r.ceiling_y:
                    room_lights[r.id] += 1
                    break
    return modules, lights, room_lights


def check(plan, units, placed):
    from .rules import Violation
    modules, lights, room_lights = measure(plan, units, placed)
    out = []
    for c, n in modules.items():
        if n > CELL_MODULES:
            out.append(Violation("B1", f"cell {c}", f"{n} modules (cap {CELL_MODULES})"))
    for c, n in lights.items():
        if n > CELL_LIGHTS:
            out.append(Violation("B1", f"cell {c}", f"{n} lights (cap {CELL_LIGHTS})"))
    for rid in empty_rooms(plan, placed):
        out.append(Violation("D1", rid, "nothing placed in it"))
    for rid, n in room_lights.items():
        r = plan.rooms[rid]
        cap = max(ROOM_LIGHTS_MIN, int(r.width * r.depth / M2_PER_LIGHT))
        if n > cap:
            out.append(Violation("B2", rid, f"{n} lights (cap {cap})"))
    return out


def empty_rooms(plan, placed):
    """D1: rooms (not open air, turrets or the terrain) with nothing placed in them."""
    out = []
    for r in plan.rooms.values():
        if r.get("terrain") or r.kind in ("outdoor", "grounds", "stair_turret"):
            continue
        has = any(parent in ("Furniture", "Collectibles", "Tomes", "Props", "Puzzles") and r.x0 <= pos[0] <= r.x1 and r.z0 <= pos[2] <= r.z1
                  and r.y - 0.5 <= pos[1] <= r.ceiling_y for parent, pos, _p in placed)
        if not has:
            out.append(r.id)
    return out


def report(plan, units, placed):
    modules, lights, room_lights = measure(plan, units, placed)
    return {"max_cell_modules": max(modules.values() or [0]), "max_cell_lights": max(lights.values() or [0]),
            "max_room_lights": max(room_lights.values() or [0])}

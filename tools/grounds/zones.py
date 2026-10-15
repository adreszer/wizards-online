"""Outdoor areas as terrain rooms of the castle plan.

Every zone in grounds.json and every landmark's zone becomes a Room with kind "grounds"
and terrain=True: no geometry is built for it, but it gets an AreaZone, an entry in the
server's area map and a place in the reachability graph (linked to the estate, which
the forecourt's gates and the lake gate open onto).
"""
import numpy as np


def add_terrain_rooms(plan, cfg):
    specs = [dict(z) for z in cfg["zones"]]
    for lm in cfg["landmarks"]:
        specs.append({"id": lm["id"], "rect": lm["zone"], "name_key": "AREA_" + lm["id"].upper()})
    plan.terrain_links = []
    for z in specs:
        x0, x1, z0, z1 = z["rect"]
        plan.room(z["id"], x0, x1, z0, z1, storey=z.get("storey", 0), kind="grounds", ceiling=False, rows=1,
                  pillars=False, torches=False, name_key=z.get("name_key"), terrain=True,
                  inside=None if z["id"] == "estate" else "estate")
        if z["id"] != "estate":
            plan.terrain_links.append((z["id"], "estate"))
    return plan


def set_zone_heights(plan, g):
    """Each terrain room's AreaZone spans the terrain under it, from 4 m below its lowest
    point to 24 m above its highest (the estate: everything)."""
    T = g.terrain
    for r in plan.rooms.values():
        if not r.get("terrain"):
            continue
        x0, x1, z0, z1 = r.rect
        m = (T.X >= x0) & (T.X <= x1) & (T.Z >= z0) & (T.Z <= z1)
        lo, hi = float(T.H[m].min()), float(T.H[m].max())
        if r.id == "estate":
            lo, hi = lo - 20, hi + 120
        r.extra["zone_y"] = (round(lo - 4, 1), round(hi + 24, 1))

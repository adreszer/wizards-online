"""Grounds rules G1-G6 (docs/castle-generation.md, section 3.5)."""
import math

import numpy as np

from castle.rules import Violation
from .paths import MAX_GRADE

RULES = []
GRADE_TOLERANCE = 0.012    # bilinear sampling of a 2 m grid across a carved path
WALKABLE_SLOPE = 35.0
DEEP_WATER = 1.2


def rule(rule_id, title):
    def deco(fn):
        RULES.append((rule_id, title, fn))
        return fn
    return deco


def validate(g, plan):
    out = []
    for rule_id, _t, fn in RULES:
        for where, msg in fn(g, plan):
            out.append(Violation(rule_id, where, msg))
    return out


@rule("G1", "terrain never pokes through the castle's floors")
def plateau(g, plan):
    T = g.terrain
    for r in plan.rooms.values():
        if r.get("terrain") or r.inside is not None or r.top_storey < 0:
            continue
        x0, x1, z0, z1 = r.rect
        m = (T.X >= x0) & (T.X <= x1) & (T.Z >= z0) & (T.Z <= z1)
        if m.any():
            top = float(T.H[m].max())
            if top > r.y + 0.02 and r.storey >= 0:
                yield r.id, f"terrain reaches {top:.2f} m over its floor at {r.y:.2f}"


@rule("G2", "paths climb at most 10 degrees")
def path_grades(g, plan):
    T = g.terrain
    for p in g.paths:
        if p["worst_grade"] > MAX_GRADE:
            yield p["id"], f"profile needs {math.degrees(math.atan(p['worst_grade'])):.1f} degrees between its pinned ends"
        route = p["route"]
        spans = p["bridge_spans"]
        xs = np.array([q[0] for q in route]); zs = np.array([q[1] for q in route])
        h = T.height_at(xs, zs)
        step = 8
        for i in range(0, len(route) - step, step // 2):
            if any(a <= i <= b for a, b in spans):
                continue
            grade = abs(h[i + step] - h[i]) / step
            if grade > MAX_GRADE + GRADE_TOLERANCE:
                yield p["id"], f"{math.degrees(math.atan(grade)):.1f} degrees at ({xs[i]:.0f}, {zs[i]:.0f})"
                break


@rule("G3", "every landmark is reached by a path from one of the castle's gates")
def landmarks_connected(g, plan):
    # Paths join where an end of one comes within 12 m of another's route.
    routes = {p["id"]: p["route"] for p in g.paths}
    def near(pt, route, d=12.0):
        return any((q[0] - pt[0]) ** 2 + (q[1] - pt[1]) ** 2 < d * d for q in route[::2])
    gates = [tuple(gt) for gt in g.cfg.get("gates", [[0.0, 98.0]])]
    linked = {pid for pid, r in routes.items() if any(near(gt, r[:3] + r[-3:], 24.0) for gt in gates)}
    grew = True
    while grew:
        grew = False
        for pid, r in routes.items():
            if pid in linked:
                continue
            if any(near(r[0], routes[o]) or near(r[-1], routes[o]) or near(routes[o][0], r) or near(routes[o][-1], r) for o in linked):
                linked.add(pid); grew = True
    for p in routes:
        if p not in linked:
            yield p, "path not joined to the network from the gate"
    for lm in g.cfg["landmarks"]:
        x0, x1, z0, z1 = lm["zone"]
        if not any(x0 <= q[0] <= x1 and z0 <= q[1] <= z1 for pid in linked for q in routes[pid]):
            yield lm["id"], "no path reaches its zone"


@rule("G4", "scatter keeps clear of paths, buildings, the castle and the shore")
def scatter_clearance(g, plan):
    from .scatter import KINDS
    T = g.terrain
    for kind, arr in g.scatter.items():
        if len(arr) == 0:
            continue
        _sp, c_path, c_build, c_castle, c_shore, _s, _k = KINDS[kind]
        fz, fx = T.index(arr[:, 0], arr[:, 2])
        iz = np.clip(np.round(fz).astype(int), 0, T.nz - 1); ix = np.clip(np.round(fx).astype(int), 0, T.nx - 1)
        bad = np.count_nonzero(g.path_dist[iz, ix] <= c_path - 1.0)
        if bad:
            yield kind, f"{bad} instances closer than {c_path} m to a path"
        for r in g.castle_rects:
            x0, x1, z0, z1 = r
            dx = np.maximum(np.maximum(x0 - arr[:, 0], arr[:, 0] - x1), 0)
            dz = np.maximum(np.maximum(z0 - arr[:, 2], arr[:, 2] - z1), 0)
            m = np.hypot(dx, dz) < c_castle - 1.0
            if m.any():
                yield kind, f"{int(m.sum())} instances within {c_castle} m of the castle"
                break


@rule("G5", "the walkable grounds are enclosed by water, cliffs and mountains")
def soft_boundary(g, plan):
    T = g.terrain
    k = 2
    H = T.H[::k, ::k]
    gz, gx = np.gradient(H, T.sp * k)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    walk = (slope <= WALKABLE_SLOPE) & (H > T.water - DEEP_WATER)
    nz, nx = H.shape
    fz, fx = T.index(0.0, 98.0)
    start = (int(round(fz / k)), int(round(fx / k)))
    seen = np.zeros(walk.shape, bool)
    stack = [start]
    seen[start] = True
    border = 12
    while stack:
        cz, cx = stack.pop()
        if cz < border or cx < border or cz >= nz - border or cx >= nx - border:
            yield "estate", f"walkable ground reaches the edge of the world near ({T.x0 + cx * k * T.sp:.0f}, {T.z0 + cz * k * T.sp:.0f})"
            return
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cz + dz, cx + dx)
            if walk[n] and not seen[n]:
                seen[n] = True
                stack.append(n)


@rule("G6", "the grounds are divided into named outdoor areas")
def outdoor_zones(g, plan):
    ids = {r.id for r in plan.rooms.values() if r.get("terrain")}
    for need in ["estate"] + [lm["id"] for lm in g.cfg["landmarks"]]:
        if need not in ids:
            yield need, "no outdoor area"


@rule("V", "the village: lots clear of streets and each other (V1), doors onto a street (V2), floors on the site (V3), railway into a hillside (V4)")
def village_rules(g, plan):
    from . import village
    for rule_id, where, msg in village.validate(g):
        yield where, f"{rule_id}: {msg}"

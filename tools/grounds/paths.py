"""Roads and paths: routed between pinned waypoints, then carved into the terrain.

Each path in grounds.json lists waypoints; between consecutive waypoints the route is
found with A* on an 8 m grid (cost grows with grade, water and the castle are out of
bounds) unless the path is "straight". The route is smoothed, its height profile is
the terrain smoothed and clamped to MAX_GRADE (rule G2) between the fixed waypoint
heights, and the terrain is cut and filled along it. Waypoint pairs listed in
"bridges" are spanned by a deck instead (viaduct, covered bridge): no carving there.
"""
import heapq
import math

import numpy as np

MAX_GRADE = math.tan(math.radians(10.0))     # rule G2
CARVE_GRADE = math.tan(math.radians(9.0))    # carved a little gentler so sampling never tips over G2
COARSE = 8.0
BLEND = 5.0


def chaikin(pts, rounds=2):
    for _ in range(rounds):
        out = [pts[0]]
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            out.append((0.75 * ax + 0.25 * bx, 0.75 * az + 0.25 * bz))
            out.append((0.25 * ax + 0.75 * bx, 0.25 * az + 0.75 * bz))
        out.append(pts[-1])
        pts = out
    return pts


def astar(terrain, a, b, blocked):
    """Route on the coarse grid from world point a to b."""
    step = int(round(COARSE / terrain.sp))
    Hc = terrain.H[::step, ::step]
    Bc = blocked[::step, ::step]
    nz, nx = Hc.shape
    def cell(p):
        fz, fx = terrain.index(p[0], p[1])
        return (int(round(fz / step)), int(round(fx / step)))
    start, goal = cell(a), cell(b)
    dist = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]
    nbrs = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    while heap:
        _f, c = heapq.heappop(heap)
        if c == goal:
            break
        g = dist[c]
        for dz, dx in nbrs:
            n = (c[0] + dz, c[1] + dx)
            if not (0 <= n[0] < nz and 0 <= n[1] < nx):
                continue
            if Bc[n] and n != goal:
                continue
            run = COARSE * math.hypot(dz, dx)
            grade = abs(Hc[n] - Hc[c]) / run
            cost = run * (1 + 30 * max(0.0, grade - 0.06) ** 1.5 * 10) + (400 if grade > 0.45 else 0)
            ng = g + cost
            if ng < dist.get(n, 1e18):
                dist[n] = ng
                prev[n] = c
                h = COARSE * math.hypot(goal[0] - n[0], goal[1] - n[1])
                heapq.heappush(heap, (ng + h, n))
    if goal not in dist:
        raise ValueError(f"no route from {a} to {b}")
    route = [goal]
    while route[-1] != start:
        route.append(prev[route[-1]])
    route.reverse()
    pts = [(terrain.x0 + c[1] * step * terrain.sp, terrain.z0 + c[0] * step * terrain.sp) for c in route]
    pts[0] = tuple(a); pts[-1] = tuple(b)
    return pts


def densify(pts, step=1.0):
    out = []
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(bx - ax, bz - az) / step))
        for k in range(n):
            t = k / n
            out.append((ax + (bx - ax) * t, az + (bz - az) * t))
    out.append(pts[-1])
    return out


def profile(heights, anchors, length_step=1.0):
    """Smooth the terrain heights along the path and clamp the grade, keeping the anchor
    samples (waypoints) at their heights. Returns (profile, worst grade)."""
    h = np.array(heights, dtype=float)
    k = 15
    if len(h) > 2 * k:
        kernel = np.ones(2 * k + 1) / (2 * k + 1)
        padded = np.pad(h, k, mode="edge")
        h = np.convolve(padded, kernel, mode="valid")
    for i, v in anchors.items():
        h[i] = v
    g = CARVE_GRADE * length_step
    fixed = set(anchors)
    for _ in range(200):
        changed = False
        for i in range(1, len(h)):
            if i in fixed:
                continue
            lo, hi = h[i - 1] - g, h[i - 1] + g
            if h[i] < lo: h[i] = lo; changed = True
            elif h[i] > hi: h[i] = hi; changed = True
        for i in range(len(h) - 2, -1, -1):
            if i in fixed:
                continue
            lo, hi = h[i + 1] - g, h[i + 1] + g
            if h[i] < lo: h[i] = lo; changed = True
            elif h[i] > hi: h[i] = hi; changed = True
        if not changed:
            break
    worst = float(np.max(np.abs(np.diff(h))) / length_step) if len(h) > 1 else 0.0
    return h, worst


def build_paths(terrain, cfg, blocked):
    """Route, profile and carve every path. Returns (paths, path_dist, path_mask, bridges)."""
    T = terrain
    path_dist = np.full(T.H.shape, 1e9)
    target = np.zeros(T.H.shape)
    half_at = np.zeros(T.H.shape)
    paths = []
    bridges = []
    for P in cfg["paths"]:
        way = [tuple(p) for p in P["points"]]
        bridge_pairs = {tuple(b) for b in P.get("bridges", [])}
        route = []          # (x, z) dense samples
        anchors = {}        # sample index -> fixed height
        bridge_spans = []   # (i0, i1) sample index ranges
        for i in range(len(way) - 1):
            a, b = way[i], way[i + 1]
            if P.get("straight") or (i, i + 1) in bridge_pairs:
                leg = [a, b]
            else:
                leg = chaikin(astar(T, a, b, blocked))
            dense = densify(leg)
            if route:
                dense = dense[1:]
            i0 = len(route)
            route.extend(dense)
            if (i, i + 1) in bridge_pairs:
                bridge_spans.append((max(0, i0 - 1), len(route) - 1))
        # Anchors: the path's ends keep the terrain height there (gates, terraces, landmark
        # flats), and so do bridge ends; waypoints in between only steer the route.
        pinned = {0, len(way) - 1} | {i for pair in bridge_pairs for i in pair} | set(P.get("anchors", []))
        for i in sorted(pinned):
            w = way[i]
            j = min(range(len(route)), key=lambda k: (route[k][0] - w[0]) ** 2 + (route[k][1] - w[1]) ** 2)
            anchors[j] = float(T.height_at(w[0], w[1]))
        heights = [float(h) for h in T.height_at(np.array([p[0] for p in route]), np.array([p[1] for p in route]))]
        prof, worst = profile(heights, anchors)
        for i0, i1 in bridge_spans:
            a, b = prof[i0], prof[i1]
            for k in range(i0, i1 + 1):
                prof[k] = a + (b - a) * (k - i0) / max(1, i1 - i0)
            bridges.append({"path": P["id"], "from": (route[i0][0], float(a), route[i0][1]),
                            "to": (route[i1][0], float(b), route[i1][1]), "width": P["width"] + 2})
        in_bridge = np.zeros(len(route), bool)
        for i0, i1 in bridge_spans:
            in_bridge[i0 + 1:i1] = True
        half = P["width"] / 2
        R = half + BLEND
        r = int(math.ceil(R / T.sp)) + 1
        for k, (x, z) in enumerate(route):
            if in_bridge[k]:
                continue
            fz, fx = T.index(x, z)
            iz0, ix0 = int(fz) - r, int(fx) - r
            iz1, ix1 = int(fz) + r + 2, int(fx) + r + 2
            iz0, ix0 = max(0, iz0), max(0, ix0)
            iz1, ix1 = min(T.nz, iz1), min(T.nx, ix1)
            if iz0 >= iz1 or ix0 >= ix1:
                continue
            dx = T.X[iz0:iz1, ix0:ix1] - x
            dz = T.Z[iz0:iz1, ix0:ix1] - z
            d = np.hypot(dx, dz) - half
            win = d < path_dist[iz0:iz1, ix0:ix1]
            path_dist[iz0:iz1, ix0:ix1] = np.where(win, d, path_dist[iz0:iz1, ix0:ix1])
            target[iz0:iz1, ix0:ix1] = np.where(win, prof[k], target[iz0:iz1, ix0:ix1])
            half_at[iz0:iz1, ix0:ix1] = np.where(win, half, half_at[iz0:iz1, ix0:ix1])
        paths.append({"id": P["id"], "kind": P["kind"], "width": P["width"], "route": route,
                      "profile": [float(v) for v in prof], "worst_grade": worst, "bridge_spans": bridge_spans})
    w = np.clip(1 - path_dist / BLEND, 0, 1)
    w = w * w * (3 - 2 * w)
    T.H = T.H * (1 - w) + target * w
    return paths, path_dist, bridges

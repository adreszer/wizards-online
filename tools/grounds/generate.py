"""Grounds pipeline: terrain -> paths -> scatter -> masks, from grounds.json and the castle plan.

generate(cfg, plan) returns a Grounds object; export.write() turns it into
levels/grounds/* files and the grounds scene; rules.validate() checks G1-G6.
"""
import numpy as np

from .terrain import Terrain
from .paths import build_paths
from .scatter import scatter
from .noise import smoothstep


class Grounds:
    pass


def castle_rects(plan, min_storey=0):
    """Plan rects of the built castle at or above a storey (terrain rooms excluded)."""
    return [r.rect for r in plan.rooms.values()
            if not r.get("terrain") and r.top_storey >= min_storey and r.inside is None]


def generate(cfg, plan):
    g = Grounds()
    g.cfg = cfg
    rects = castle_rects(plan)
    T = Terrain(cfg).build(rects)
    # Paths may not cross the castle or the water.
    blocked = np.zeros(T.H.shape, bool)
    for r in rects:
        blocked |= T.rect_distance(r) < 6
    blocked |= T.H < T.water + 0.4
    g.paths, g.path_dist, g.bridges = build_paths(T, cfg, blocked)
    # Re-flatten pinned areas the carving may have nicked, then the castle plateau stays exact.
    for t in cfg.get("terraces", []):
        T.flat(t["rect"], t["height"], 2)
    for r in rects:
        x0, x1, z0, z1 = r
        inside = (T.X >= x0 - 4) & (T.X <= x1 + 4) & (T.Z >= z0 - 4) & (T.Z <= z1 + 4)
        T.H = np.where(inside, np.minimum(T.H, cfg["plateau"]["height"]), T.H)
    keepout = [lm["zone"] for lm in cfg["landmarks"]] + [f["rect"] for f in cfg.get("flats", [])]
    g.scatter = scatter(T, cfg, g.path_dist, keepout, rects)
    g.terrain = T
    g.castle_rects = rects
    g.floor_rects = [r.rect for r in plan.rooms.values()
                     if not r.get("terrain") and r.inside is None and r.storey <= 0 <= r.top_storey]
    g.underground = [(r.rect, r.ceiling_y) for r in plan.rooms.values()
                     if not r.get("terrain") and r.inside is None and r.top_storey < 0]
    g.splat = splat(T, g.path_dist)
    return g


def splat(T, path_dist):
    """RGBA weights per cell: R grass, G rock, B path / dirt, A sand."""
    slope = T.slope_deg()
    rock = smoothstep(28, 40, slope)
    rock = np.maximum(rock, smoothstep(60, 110, T.H) * 0.8)
    path = np.clip(1 - path_dist / 1.5, 0, 1)
    sand = smoothstep(T.water + 1.4, T.water + 0.2, T.H) * (1 - rock)
    grass = np.clip(1 - rock - path - sand, 0, 1)
    w = np.stack([grass, rock * (1 - path), path, sand * (1 - path)], axis=-1)
    w /= np.maximum(w.sum(axis=-1, keepdims=True), 1e-6)
    return (w * 255 + 0.5).astype(np.uint8)

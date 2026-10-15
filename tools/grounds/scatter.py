"""Trees, rocks and bushes on the grounds: jittered-grid sampling filtered by masks.

Clearance (rule G4): no tree within 4 m of a path edge, 8 m of a landmark or 15 m of
the castle; no rock on a path; a 3 m clear rim along the water. Instances are
(x, y, z, yaw, scale) per kind.
"""
import numpy as np

from .noise import Perlin, fbm, smoothstep

KINDS = {
    #            spacing  path  build  castle  shore  slope range   scale range
    "conifer":   (6.5,    4.0,  8.0,   15.0,   3.0,   (0, 32),      (0.8, 1.35)),
    "broadleaf": (8.0,    4.0,  8.0,   15.0,   3.0,   (0, 26),      (0.8, 1.3)),
    "bush":      (4.5,    1.5,  3.0,   6.0,    3.0,   (0, 30),      (0.6, 1.3)),
    "rock":      (9.0,    0.5,  2.0,   4.0,    0.0,   (12, 60),     (0.6, 2.2)),
}


def forest_mask(terrain, cfg, noise):
    X, Z = terrain.X, terrain.Z
    m = np.zeros(X.shape)
    for f in cfg.get("forest", []):
        x0, x1, z0, z1 = f["rect"]
        d = terrain.rect_distance(f["rect"])
        m = np.maximum(m, f["density"] * (1 - smoothstep(0, 60, d)))
    patch = fbm(noise, X, Z, 140, 3)
    return np.clip(m * (0.75 + 0.6 * patch), 0, 1)


def scatter(terrain, cfg, path_dist, keepout_rects, castle_rects):
    """Returns {kind: np.array of rows (x, y, z, yaw, scale)}."""
    T = terrain
    rng = np.random.Generator(np.random.PCG64(cfg["seed"] + 77))
    noise = Perlin(cfg["seed"] + 5)
    forest = forest_mask(T, cfg, noise)
    slope = T.slope_deg()
    castle_d = np.full(T.H.shape, 1e9)
    for r in castle_rects:
        castle_d = np.minimum(castle_d, T.rect_distance(r))
    build_d = np.full(T.H.shape, 1e9)
    for r in keepout_rects:
        build_d = np.minimum(build_d, T.rect_distance(r))
    above_water = T.H - T.water
    out = {}
    x0, x1, z0, z1 = cfg["extent"]
    for kind, (sp, c_path, c_build, c_castle, c_shore, (s0, s1), (k0, k1)) in KINDS.items():
        gx = np.arange(x0 + sp / 2, x1, sp)
        gz = np.arange(z0 + sp / 2, z1, sp)
        PX, PZ = np.meshgrid(gx, gz)
        PX = PX + rng.uniform(-0.45, 0.45, PX.shape) * sp
        PZ = PZ + rng.uniform(-0.45, 0.45, PZ.shape) * sp
        PX = PX.ravel(); PZ = PZ.ravel()
        fz, fx = T.index(PX, PZ)
        iz = np.clip(np.round(fz).astype(int), 0, T.nz - 1)
        ix = np.clip(np.round(fx).astype(int), 0, T.nx - 1)
        f = forest[iz, ix]; sl = slope[iz, ix]
        if kind == "conifer":
            prob = f * np.where(T.H[iz, ix] > 25, 1.0, 0.55)
            prob = np.maximum(prob, 0.012)
        elif kind == "broadleaf":
            prob = f * np.where(T.H[iz, ix] > 25, 0.15, 0.45)
            prob = np.maximum(prob, 0.02)
        elif kind == "bush":
            edge = f * (1 - f) * 4
            prob = np.maximum(edge * 0.5, 0.03)
        else:
            prob = np.where(sl > 30, 0.35, 0.04) + 0.25 * smoothstep(20, 60, T.H[iz, ix])
        ok = rng.uniform(0, 1, PX.shape) < prob
        ok &= (sl >= s0) & (sl <= s1)
        ok &= path_dist[iz, ix] > c_path
        ok &= build_d[iz, ix] > c_build
        ok &= castle_d[iz, ix] > c_castle
        ok &= above_water[iz, ix] > c_shore + 0.5
        # Nothing on the outermost strip (the world edge is mountains anyway).
        ok &= (np.abs(PX) < 1000) & (np.abs(PZ) < 1000)
        PX, PZ = PX[ok], PZ[ok]
        Y = T.height_at(PX, PZ)
        yaw = rng.uniform(0, 2 * np.pi, PX.shape)
        scale = rng.uniform(k0, k1, PX.shape)
        out[kind] = np.stack([PX, Y, PZ, yaw, scale], axis=1).astype(np.float32)
    return out

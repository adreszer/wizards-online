"""Heightmap of the grounds from content/grounds/grounds.json and the castle plan.

Layers, in order (each one a numpy operation over the whole grid):
  base hills -> lake basin -> island -> plateau under the castle -> cliffs -> hills ->
  valleys (rivers) -> mountains at the border -> flats under landmarks -> terraces.
Paths are carved afterwards (paths.py). Heights are metres, y up; the castle's ground
floor is y 0, the dungeons y -9.
"""
import numpy as np

from .noise import Perlin, fbm, ridged, smoothstep


class Terrain:
    def __init__(self, cfg):
        self.cfg = cfg
        x0, x1, z0, z1 = cfg["extent"]
        self.sp = cfg["spacing"]
        self.x0, self.z0 = x0, z0
        self.nx = int(round((x1 - x0) / self.sp)) + 1
        self.nz = int(round((z1 - z0) / self.sp)) + 1
        xs = x0 + np.arange(self.nx) * self.sp
        zs = z0 + np.arange(self.nz) * self.sp
        self.X, self.Z = np.meshgrid(xs, zs)          # [iz, ix]
        self.H = np.zeros_like(self.X)
        self.water = cfg["water_level"]
        self.rivers = []        # (points [(x, z, level)], width)
        self.noise = Perlin(cfg["seed"])
        self.noise2 = Perlin(cfg["seed"] + 1)

    # -- sampling ------------------------------------------------------------------------
    def index(self, x, z):
        return (z - self.z0) / self.sp, (x - self.x0) / self.sp

    def height_at(self, x, z):
        """Bilinear height at world (x, z); arrays allowed."""
        fz, fx = self.index(np.asarray(x, float), np.asarray(z, float))
        fx = np.clip(fx, 0, self.nx - 1.001); fz = np.clip(fz, 0, self.nz - 1.001)
        ix = np.floor(fx).astype(int); iz = np.floor(fz).astype(int)
        tx = fx - ix; tz = fz - iz
        H = self.H
        a = H[iz, ix] * (1 - tx) + H[iz, ix + 1] * tx
        b = H[iz + 1, ix] * (1 - tx) + H[iz + 1, ix + 1] * tx
        return a * (1 - tz) + b * tz

    def slope_deg(self):
        gz, gx = np.gradient(self.H, self.sp)
        return np.degrees(np.arctan(np.hypot(gx, gz)))

    # -- layers --------------------------------------------------------------------------
    def build(self, castle_rects):
        c = self.cfg
        X, Z = self.X, self.Z
        b = c["base"]
        # The castle stands on high ground: hills grow and the land falls away with distance.
        cx, cz = b.get("summit", [0, -80])
        d = np.hypot(X - cx, Z - cz)
        far = smoothstep(b.get("near", 160), b.get("far", 650), d)
        self.H = b["height"] + b["hills"] * fbm(self.noise, X, Z, b["hill_wavelength"], 4) * (0.25 + 0.75 * far) \
            + b["detail"] * fbm(self.noise2, X, Z, b["detail_wavelength"], 4) - b.get("fall", 0.0) * far
        self.lake(c["lake"])
        self.island(c["island"])
        self.plateau(c["plateau"], castle_rects)
        for cl in c.get("cliffs", []):
            self.cliff(cl)
        for h in c.get("hills", []):
            self.hill(h)
        for v in c.get("valleys", []):
            self.valley(v)
        self.mountains(c["mountains"])
        for f in c.get("flats", []):
            self.flat(f["rect"], None, f.get("blend", 16))
        for t in c.get("terraces", []):
            self.flat(t["rect"], t["height"], t.get("blend", 10))
        return self

    def lake(self, L):
        cx, cz = L["centre"]; rx, rz = L["radii"]
        r = np.sqrt(((self.X - cx) / rx) ** 2 + ((self.Z - cz) / rz) ** 2)
        R = (rx + rz) / 2
        wobble = 0.08 * fbm(self.noise2, self.X, self.Z, 160, 3)
        r = r + wobble
        inner = L["floor"] + (self.water - 0.5 - L["floor"]) * np.clip(r, 0, 1) ** 2
        outer = self.water - 0.5 + (r - 1) * R * 0.12
        target = np.where(r < 1, inner, outer)
        self.H = np.minimum(self.H, target)

    def island(self, I):
        cx, cz = I["centre"]
        d = np.hypot(self.X - cx, self.Z - cz)
        bump = (self.water - 8) + (I["height"] - (self.water - 8)) * (1 - smoothstep(0, I["radius"], d))
        self.H = np.maximum(self.H, np.where(d < I["radius"] * 1.2, bump, -1e9))

    def rect_distance(self, rect):
        x0, x1, z0, z1 = rect
        dx = np.maximum(np.maximum(x0 - self.X, self.X - x1), 0)
        dz = np.maximum(np.maximum(z0 - self.Z, self.Z - z1), 0)
        return np.hypot(dx, dz)

    def plateau(self, P, castle_rects):
        d = self.rect_distance(P["reserve"])
        for (x0, x1, z0, z1) in castle_rects:
            m = P["margin"]
            d = np.minimum(d, self.rect_distance((x0 - m, x1 + m, z0 - m, z1 + m)))
        t = 1 - smoothstep(0, P["blend"], d)
        self.H = self.H * (1 - t) + P["height"] * t

    def cliff(self, C):
        (ax, az), (bx, bz) = C["from"], C["to"]
        ux, uz = bx - ax, bz - az
        L = np.hypot(ux, uz); ux /= L; uz /= L
        # Outward normal toward the low side.
        nx, nz = (-uz, ux)
        if (C["side"] == "w" and nx > 0) or (C["side"] == "e" and nx < 0) or (C["side"] == "n" and nz > 0) or (C["side"] == "s" and nz < 0):
            nx, nz = -nx, -nz
        rx, rz = self.X - ax, self.Z - az
        along = rx * ux + rz * uz
        across = rx * nx + rz * nz
        ends = smoothstep(-60, 0, along) * (1 - smoothstep(L, L + 60, along))
        low = C["drop_to"] + 0.6 * fbm(self.noise, self.X, self.Z, 40, 2)
        t = smoothstep(0, C["width"], across) * ends
        self.H = np.where(across > 0, self.H * (1 - t) + np.minimum(self.H, low) * t, self.H)

    def hill(self, Hh):
        cx, cz = Hh["centre"]
        d = np.hypot(self.X - cx, self.Z - cz)
        self.H = self.H + Hh["height"] * (1 - smoothstep(0, Hh["radius"], d)) ** 1.5

    def polyline_distance(self, pts):
        """Distance to a polyline and the parameter (0..1 per segment index) of the nearest point."""
        best = np.full(self.X.shape, 1e9); seg_t = np.zeros(self.X.shape)
        for i in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[i], pts[i + 1]
            vx, vz = bx - ax, bz - az
            L2 = vx * vx + vz * vz
            t = np.clip(((self.X - ax) * vx + (self.Z - az) * vz) / L2, 0, 1)
            d = np.hypot(self.X - (ax + t * vx), self.Z - (az + t * vz))
            closer = d < best
            best = np.where(closer, d, best)
            seg_t = np.where(closer, i + t, seg_t)
        return best, seg_t

    def valley(self, V):
        pts = V["points"]
        d, s = self.polyline_distance(pts)
        w = V["width"] / 2
        carve = V["depth"] * (1 - smoothstep(w * 0.25, w * 1.6, d))
        self.H = self.H - carve
        if V.get("river"):
            # Water a metre above the bed, sampled along the polyline and kept falling downstream.
            samples = []
            for i in range(len(pts) - 1):
                (ax, az), (bx, bz) = pts[i], pts[i + 1]
                n = max(2, int(np.hypot(bx - ax, bz - az) // 8))
                for k in range(n):
                    t = k / n
                    samples.append((ax + (bx - ax) * t, az + (bz - az) * t))
            samples.append(tuple(pts[-1]))
            levels = []
            last = 1e9
            for (x, z) in samples:
                bed = float(self.height_at(x, z))
                level = min(last, max(bed + 0.9, self.water))
                levels.append((x, z, level)); last = level
            self.rivers.append({"id": V["id"], "points": levels, "width": V["width"] * 0.32})

    def mountains(self, M):
        e = np.maximum(np.abs(self.X), np.abs(self.Z))
        t = smoothstep(M["start"], max(abs(v) for v in self.cfg["extent"]), e)
        ridge = ridged(self.noise2, self.X, self.Z, M["ridge_wavelength"], 4)
        self.H = self.H + M["height"] * t * (0.45 + 0.55 * ridge)

    def flat(self, rect, height, blend):
        x0, x1, z0, z1 = rect
        inside = (self.X >= x0) & (self.X <= x1) & (self.Z >= z0) & (self.Z <= z1)
        if height is None:
            height = float(np.median(self.H[inside])) if inside.any() else 0.0
        d = self.rect_distance(rect)
        t = 1 - smoothstep(0, blend, d)
        self.H = self.H * (1 - t) + height * t
        return height

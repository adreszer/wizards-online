"""Seeded 2D gradient noise (Perlin) and fractal sums, vectorised with numpy.

Deterministic for a seed: the permutation comes from numpy's PCG64 generator.
"""
import numpy as np


class Perlin:
    def __init__(self, seed):
        rng = np.random.Generator(np.random.PCG64(seed))
        p = rng.permutation(256)
        self.perm = np.concatenate([p, p]).astype(np.int64)
        angles = rng.uniform(0, 2 * np.pi, 256)
        self.grad = np.stack([np.cos(angles), np.sin(angles)], axis=1)

    def __call__(self, x, z):
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        xi = np.floor(x).astype(np.int64)
        zi = np.floor(z).astype(np.int64)
        xf = x - xi
        zf = z - zi
        xi &= 255
        zi &= 255
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
        perm, grad = self.perm, self.grad

        def corner(dx, dz):
            h = perm[perm[xi + dx] + zi + dz] & 255
            g = grad[h]
            return g[..., 0] * (xf - dx) + g[..., 1] * (zf - dz)

        n00 = corner(0, 0); n10 = corner(1, 0); n01 = corner(0, 1); n11 = corner(1, 1)
        nx0 = n00 + u * (n10 - n00)
        nx1 = n01 + u * (n11 - n01)
        return (nx0 + v * (nx1 - nx0)) * 1.41421356


def fbm(noise, x, z, wavelength, octaves=5, gain=0.5, lacunarity=2.0):
    """Fractal sum in roughly [-1, 1]; `wavelength` is the largest feature size in metres."""
    total = np.zeros(np.broadcast(x, z).shape)
    amp, freq, norm = 1.0, 1.0 / wavelength, 0.0
    for i in range(octaves):
        total += amp * noise(x * freq + 17.3 * i, z * freq - 9.1 * i)
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / norm


def ridged(noise, x, z, wavelength, octaves=5):
    """Ridged multifractal in [0, 1]: sharp crests for mountains."""
    total = np.zeros(np.broadcast(x, z).shape)
    amp, freq, norm = 1.0, 1.0 / wavelength, 0.0
    for i in range(octaves):
        n = 1.0 - np.abs(noise(x * freq + 31.7 * i, z * freq + 5.3 * i))
        total += amp * n * n
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

"""Texture generation for the MakeHuman characters (numpy + Pillow).

Skin: MakeHuman's 512 px diffuse maps upscaled to 2048, with a tileable pore
and fine-wrinkle normal map and a roughness map (oilier T-zone is not
attempted: the atlas has no face mask). Fabric: tileable weave albedo
variation, normal and roughness per weave kind.
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageFilter


def _rng(seed):
    return np.random.default_rng(seed)


def tile_noise(n: int, scale: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Tileable value noise in [0, 1] (bilinear lattice, `scale` cells per side)."""
    rng = _rng(seed)
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = scale * (2 ** o)
        g = rng.random((s, s))
        x = np.arange(n) * s / n
        i0 = np.floor(x).astype(int) % s
        i1 = (i0 + 1) % s
        f = x - np.floor(x)
        f = f * f * (3 - 2 * f)
        a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
        b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
        out += amp * (a * (1 - f)[:, None] + b * f[:, None])
        tot += amp
        amp *= 0.5
    return out / tot


def height_to_normal(h: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(arr: np.ndarray, path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a).save(path, optimize=True)


# ------------------------------------------------------------------------ skin
def skin_maps(src: str, out_prefix: str, size: int = 2048, tint=(1.0, 1.0, 1.0), seed: int = 1):
    """Writes <prefix>_albedo.png, _normal.png, _roughness.png."""
    im = Image.open(src).convert("RGB").resize((size, size), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    a = np.asarray(im).astype(np.float64) / 255.0
    # subtle blotchy variation (freckling, redness) so the upscale isn't flat
    blot = tile_noise(size, 24, seed, 4)
    a *= (0.94 + 0.12 * blot)[..., None]
    a *= np.array(tint)[None, None, :]
    save(np.clip(a, 0, 1), out_prefix + "_albedo.png")
    # pores: dense small dimples + fine wrinkles
    rng = _rng(seed + 7)
    pores = rng.random((size, size))
    pores = np.asarray(Image.fromarray((pores * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)),
                       dtype=np.float64) / 255.0
    wr = tile_noise(size, 96, seed + 3, 3)
    h = pores * 0.6 + wr * 0.4
    save(height_to_normal(h, 3.0), out_prefix + "_normal.png")
    rough = 0.52 + 0.12 * tile_noise(size, 16, seed + 11, 3) + 0.06 * (pores - 0.5)
    save(np.clip(rough, 0, 1), out_prefix + "_roughness.png")


# ---------------------------------------------------------------------- fabric
def fabric_maps(kind: str, color, out_prefix: str, size: int = 1024, seed: int = 3):
    """kind: 'linen' | 'wool' | 'leather' | 'cloak'. Tileable; the materials
    tile them with uv1_scale. Writes _albedo/_normal/_roughness."""
    n = size
    y, x = np.mgrid[0:n, 0:n] / n
    base = np.array(color, dtype=np.float64)
    if kind in ("linen", "wool", "cloak"):
        threads = {"linen": 96, "wool": 64, "cloak": 128}[kind]
        wx = np.sin(2 * np.pi * x * threads)
        wy = np.sin(2 * np.pi * y * threads)
        # plain weave: warp over/under alternates
        cell = (np.floor(x * threads) + np.floor(y * threads)) % 2
        h = np.where(cell > 0, 0.5 + 0.5 * np.abs(wx), 0.5 + 0.5 * np.abs(wy))
        slub = tile_noise(n, 8, seed, 4)
        fuzz = tile_noise(n, 64, seed + 1, 2)
        h = h * 0.7 + fuzz * 0.3
        var = 0.86 + 0.18 * slub + 0.08 * (h - 0.5)
        if kind == "cloak":
            # long lengthwise streaks of the mistcloak's ribbons
            streak = tile_noise(n, 4, seed + 5, 3)
            var *= 0.9 + 0.2 * np.roll(streak, 0, 0)
        alb = base[None, None, :] * var[..., None]
        nrm = height_to_normal(h, 2.5 if kind == "wool" else 1.8)
        rough = 0.86 + 0.1 * fuzz - 0.04 * (h - 0.5)
    else:  # leather
        cells = tile_noise(n, 48, seed, 3)
        crease = tile_noise(n, 6, seed + 2, 5)
        h = cells * 0.5 + crease * 0.5
        alb = base[None, None, :] * (0.8 + 0.35 * crease)[..., None]
        nrm = height_to_normal(h, 4.0)
        rough = 0.45 + 0.25 * crease
    save(np.clip(alb, 0, 1), out_prefix + "_albedo.png")
    save(nrm, out_prefix + "_normal.png")
    save(np.clip(rough, 0, 1), out_prefix + "_roughness.png")


def alpha_card(src: str, dst: str, tint=None, size: int | None = None):
    """Copies a hair/brow/lash texture (RGBA), optionally tinted and resized."""
    im = Image.open(src).convert("RGBA")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    if tint is not None:
        a = np.asarray(im).astype(np.float64) / 255.0
        lum = a[..., :3].mean(-1, keepdims=True)
        # keep the strand-to-strand variation: scale luminance around its mean
        m = float(np.average(lum[..., 0], weights=a[..., 3] + 1e-6))
        rel = np.clip(lum / max(m, 1e-3), 0.0, 3.0) ** 1.4
        a[..., :3] = np.clip(rel * np.array(tint)[None, None, :], 0, 1)
        im = Image.fromarray((a * 255).astype(np.uint8))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, optimize=True)

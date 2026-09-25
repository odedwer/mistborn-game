#!/usr/bin/env python3
"""Procedural PBR texture generator for Mistborn: Ashes of Luthadel.

Generates seamless, tileable 1024x1024 albedo/normal/roughness (+ao) sets
for the game's building materials, plus a handful of small effect sprites.
Everything here is original, procedurally generated and deterministic
(fixed seeds) -- safe to redistribute as CC0 / project-original content.

Usage:
    python3 tools/gen_textures.py [--size 1024] [--out assets/textures]

No external network access is used or required.
"""
from __future__ import annotations

import argparse
import os
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, maximum_filter

# --------------------------------------------------------------------------
# Core tileable noise primitives
# --------------------------------------------------------------------------

def spectral_noise(size: int, seed: int, beta: float = 2.2) -> np.ndarray:
    """Band-limited fractal noise that is perfectly periodic (tileable) by
    construction, since it is synthesized directly in the Fourier domain.
    Returns values normalized to [0, 1]."""
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(size, size))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(size).reshape(-1, 1)
    fx = np.fft.fftfreq(size).reshape(1, -1)
    freq = np.sqrt(fx ** 2 + fy ** 2)
    freq[0, 0] = freq[0, 1] if size > 1 else 1e-6
    amp = 1.0 / np.power(freq, beta / 2.0)
    amp[0, 0] = 0.0  # remove DC offset randomness; we normalize anyway
    f *= amp
    img = np.fft.ifft2(f).real
    img -= img.min()
    rng_span = img.max() - img.min() if img.max() != img.min() else 1.0
    img /= (img.max() + 1e-12)
    return img


def fbm(size: int, seed: int, octaves=(2.6, 2.2, 1.8, 1.4), weights=(0.5, 0.25, 0.15, 0.1)) -> np.ndarray:
    """Combine several spectral-noise bands (different beta = different
    'roughness' of the spectrum) into a layered fractal look. Still exactly
    tileable since every layer is tileable."""
    out = np.zeros((size, size))
    for i, (beta, w) in enumerate(zip(octaves, weights)):
        out += w * spectral_noise(size, seed * 1000 + i, beta=beta)
    out -= out.min()
    out /= (out.max() + 1e-12)
    return out


def periodic_coords(size: int):
    """Pixel centers mapped into [0, 1)."""
    c = (np.arange(size) + 0.5) / size
    return np.meshgrid(c, c)  # xs, ys


def tileable_worley(size: int, n_points: int, seed: int, metric_order=2):
    """Cellular (Worley) noise on the unit torus: replicate the point set on
    a 3x3 tiling so nearest-neighbour queries wrap seamlessly at the edges.
    Returns (f1, f2, cell_id) each shaped (size, size)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((n_points, 2))
    offsets = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
    tiled = np.concatenate([pts + np.array(o) for o in offsets], axis=0)
    ids = np.tile(np.arange(n_points), len(offsets))
    tree = cKDTree(tiled)
    xs, ys = periodic_coords(size)
    query = np.stack([xs.ravel(), ys.ravel()], axis=1)
    dists, idxs = tree.query(query, k=2)
    f1 = dists[:, 0].reshape(size, size)
    f2 = dists[:, 1].reshape(size, size)
    cell_id = ids[idxs[:, 0]].reshape(size, size)
    return f1, f2, cell_id, pts


def normalize01(a: np.ndarray) -> np.ndarray:
    lo, hi = a.min(), a.max()
    if hi - lo < 1e-12:
        return np.zeros_like(a)
    return (a - lo) / (hi - lo)


def height_to_normal(height: np.ndarray, strength: float = 6.0) -> np.ndarray:
    """OpenGL-convention tangent-space normal map from a height field, using
    periodic (wrap-around) central differences so the result tiles exactly."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nx = -dx
    ny = -dy  # OpenGL: +Y is up the texture toward increasing green
    nz = np.ones_like(height)
    length = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    nx, ny, nz = nx / length, ny / length, nz / length
    normal = np.stack([
        (nx * 0.5 + 0.5),
        (ny * 0.5 + 0.5),
        (nz * 0.5 + 0.5),
    ], axis=-1)
    return np.clip(normal, 0.0, 1.0)


def periodic_vertical_envelope(size: int, sharpness: float = 3.0) -> np.ndarray:
    """A perfectly periodic vertical gradient, dark near row 0 (and wrapping
    back to dark at row size), used for ash/soot streak accumulation without
    breaking tiling. Row index 0 = top of texture."""
    ys = (np.arange(size) + 0.5) / size
    # cos: 1.0 at y=0, -1 at y=0.5, back to 1.0 at y=1 -> periodic
    env = (np.cos(2 * np.pi * ys) * 0.5 + 0.5) ** sharpness
    return np.tile(env.reshape(-1, 1), (1, size))


def ao_from_height(height: np.ndarray, radius: float) -> np.ndarray:
    """Cheap ambient-occlusion approximation: blur the height field and
    darken pixels that sit below their local (blurred, wrapped) neighbourhood."""
    blurred = gaussian_filter(height, sigma=radius, mode="wrap")
    cavity = blurred - height
    cavity = normalize01(np.clip(cavity, 0, None))
    ao = 1.0 - cavity * 0.6
    return np.clip(ao, 0.15, 1.0)


def save_png(arr: np.ndarray, path: str, mode: str = "RGB") -> None:
    arr8 = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr8, mode=mode)
    img.save(path, optimize=True)


def lerp(a, b, t):
    return a * (1 - t) + b * t


def tint(mask2d: np.ndarray, color_a, color_b) -> np.ndarray:
    """mask2d in [0,1] -> RGB image blending color_a (0) to color_b (1)."""
    color_a = np.array(color_a).reshape(1, 1, 3)
    color_b = np.array(color_b).reshape(1, 1, 3)
    m = mask2d[..., None]
    return color_a * (1 - m) + color_b * m


# --------------------------------------------------------------------------
# Material recipes
# --------------------------------------------------------------------------

def add_soot(albedo: np.ndarray, size: int, seed: int, strength: float = 0.35) -> np.ndarray:
    """Darken toward the (periodic) top of the tile with streaky noise, to
    suggest ash/soot accumulation in Luthadel's ash-fall climate."""
    streaks = fbm(size, seed + 777, octaves=(2.0, 1.4), weights=(0.7, 0.3))
    # stretch streak noise vertically by resampling narrower horizontally
    env = periodic_vertical_envelope(size, sharpness=2.2)
    soot_mask = normalize01(streaks * 0.6 + env * 0.4) * env
    soot_color = np.array([0.05, 0.045, 0.045])
    out = albedo * (1 - soot_mask[..., None] * strength) + soot_color * (soot_mask[..., None] * strength)
    return np.clip(out, 0, 1)


def add_color_variation(albedo: np.ndarray, size: int, seed: int, amount: float = 0.06) -> np.ndarray:
    var = fbm(size, seed + 42, octaves=(2.4, 1.6), weights=(0.6, 0.4)) - 0.5
    return np.clip(albedo + var[..., None] * amount, 0, 1)


def gen_stone_wall(size, seed):
    f1, f2, cell_id, _ = tileable_worley(size, 46, seed)
    mortar = normalize01(f2 - f1)
    mortar_mask = np.clip(mortar * 9.0, 0, 1)  # 1 = stone interior, 0 = thin mortar line
    stone_noise = fbm(size, seed + 1, octaves=(2.6, 2.0, 1.5), weights=(0.5, 0.3, 0.2))
    per_cell = (np.sin(cell_id * 12.9898) * 43758.5453) % 1.0
    base = 0.42 + per_cell * 0.12 + (stone_noise - 0.5) * 0.14
    base = np.clip(base, 0.15, 0.85)
    stone_color = tint(base, (0.28, 0.27, 0.26), (0.55, 0.52, 0.48))
    albedo = lerp(np.array([0.10, 0.09, 0.09]), stone_color, mortar_mask[..., None])
    albedo = add_color_variation(albedo, size, seed)
    albedo = add_soot(albedo, size, seed, 0.4)
    height = 0.5 * mortar_mask + 0.5 * (1 - normalize01(stone_noise)) * mortar_mask
    height = normalize01(height + (per_cell[..., None].squeeze() * 0.05))
    normal = height_to_normal(height, strength=5.0)
    rough = 0.75 + (1 - mortar_mask) * 0.15 + (stone_noise - 0.5) * 0.08
    ao = ao_from_height(height, 6)
    return albedo, normal, np.clip(rough, 0.3, 1.0), ao


def gen_brick_soot(size, seed):
    rows, cols = 16, 8
    xs, ys = periodic_coords(size)
    row = np.floor(ys * rows)
    offset = (row % 2) * (0.5 / cols)
    col = np.floor((xs + offset) * cols) % cols
    # distance to nearest brick edge (in normalized brick-local coords)
    local_x = ((xs + offset) * cols) % 1.0
    local_y = (ys * rows) % 1.0
    edge_x = np.minimum(local_x, 1 - local_x)
    edge_y = np.minimum(local_y, 1 - local_y)
    mortar_w = 0.045
    mortar = np.clip(1 - np.minimum(edge_x, edge_y) / mortar_w, 0, 1)
    brick_id = row * 97 + col
    per_brick = (np.sin(brick_id * 12.9898) * 43758.5453) % 1.0
    noise = fbm(size, seed + 3, octaves=(2.4, 1.8), weights=(0.6, 0.4))
    brick_shade = 0.5 + per_brick * 0.25 + (noise - 0.5) * 0.12
    brick_color = tint(np.clip(brick_shade, 0.1, 0.95), (0.32, 0.13, 0.10), (0.62, 0.30, 0.20))
    mortar_color = np.array([0.55, 0.53, 0.5])
    albedo = lerp(brick_color, mortar_color, mortar[..., None])
    albedo = add_color_variation(albedo, size, seed, 0.05)
    albedo = add_soot(albedo, size, seed, 0.5)
    height = normalize01((1 - mortar) * 0.7 + per_brick * 0.3)
    normal = height_to_normal(height, strength=4.5)
    rough = 0.7 + mortar * 0.15 + (noise - 0.5) * 0.1
    ao = ao_from_height(height, 5)
    return albedo, normal, np.clip(rough, 0.3, 1.0), ao


def gen_cobblestone(size, seed):
    f1, f2, cell_id, _ = tileable_worley(size, 260, seed)
    mortar = normalize01(f2 - f1)
    mortar_mask = np.clip(mortar * 6.0, 0, 1)  # 1 = stone interior, 0 = thin gap
    per_cell = (np.sin(cell_id * 78.233) * 43758.5453) % 1.0
    dome = np.clip(1.0 - f1 / (f2 + 1e-6), 0, 1)  # rounded stone bump per cell
    noise = fbm(size, seed + 5, octaves=(2.2, 1.6), weights=(0.6, 0.4))
    shade = 0.35 + per_cell * 0.25 + (noise - 0.5) * 0.1
    stone_color = tint(np.clip(shade, 0.1, 0.9), (0.22, 0.21, 0.2), (0.5, 0.48, 0.45))
    dirt_color = np.array([0.12, 0.1, 0.09])
    albedo = lerp(dirt_color, stone_color, mortar_mask[..., None])
    albedo = add_color_variation(albedo, size, seed, 0.05)
    albedo = add_soot(albedo, size, seed, 0.3)
    height = normalize01(dome * mortar_mask)
    normal = height_to_normal(height, strength=7.0)
    rough = 0.8 - dome * 0.15 + (1 - mortar_mask) * 0.1
    ao = ao_from_height(height, 4)
    return albedo, normal, np.clip(rough, 0.35, 1.0), ao


def gen_slate_roof(size, seed):
    rows = 20
    xs, ys = periodic_coords(size)
    row = np.floor(ys * rows)
    row_frac = (ys * rows) % 1.0
    stagger = (row % 2) * 0.5
    cols = 6
    col_frac = ((xs + stagger) * cols) % 1.0
    slate_id = row * 53 + np.floor((xs + stagger) * cols)
    per_slate = (np.sin(slate_id * 12.9898) * 43758.5453) % 1.0
    edge = np.minimum(row_frac, 1 - row_frac)
    seam = np.clip(1 - edge / 0.06, 0, 1)  # overlap seam near row edges
    noise = fbm(size, seed + 7, octaves=(2.6, 1.8), weights=(0.55, 0.45))
    shade = 0.28 + per_slate * 0.16 + (noise - 0.5) * 0.08
    slate_color = tint(np.clip(shade, 0.05, 0.7), (0.14, 0.16, 0.18), (0.34, 0.36, 0.38))
    albedo = slate_color * (1 - seam[..., None] * 0.35)
    albedo = add_color_variation(albedo, size, seed, 0.04)
    albedo = add_soot(albedo, size, seed, 0.35)
    height = normalize01((1 - row_frac) * 0.6 + per_slate * 0.2 + seam * 0.4)
    normal = height_to_normal(height, strength=4.0)
    rough = 0.55 + seam * 0.1 + (noise - 0.5) * 0.08
    ao = ao_from_height(height, 5)
    return albedo, normal, np.clip(rough, 0.25, 0.85), ao


def gen_wood_planks(size, seed):
    planks = 8
    xs, ys = periodic_coords(size)
    col_f = (xs * planks) % 1.0
    plank_id = np.floor(xs * planks)
    per_plank = (np.sin(plank_id * 91.345) * 43758.5453) % 1.0
    seam = np.clip(1 - np.minimum(col_f, 1 - col_f) / 0.02, 0, 1)
    grain = fbm(size, seed + 9, octaves=(3.0, 2.0, 1.2), weights=(0.5, 0.3, 0.2))
    # stretch grain along plank length (x) by combining with a 1D-ish stripe pattern
    stripes = 0.5 + 0.5 * np.sin((ys * 260 + grain * 18 + per_plank * 30))
    shade = 0.25 + per_plank * 0.2 + stripes * 0.15 + (grain - 0.5) * 0.1
    wood_color = tint(np.clip(shade, 0.05, 0.85), (0.10, 0.06, 0.04), (0.42, 0.28, 0.16))
    albedo = wood_color * (1 - seam[..., None] * 0.5)
    albedo = add_color_variation(albedo, size, seed, 0.04)
    albedo = add_soot(albedo, size, seed, 0.2)
    height = normalize01(stripes * 0.5 + (1 - seam) * 0.5)
    normal = height_to_normal(height, strength=2.5)
    rough = 0.6 + seam * 0.15 + (grain - 0.5) * 0.1
    ao = ao_from_height(height, 4)
    return albedo, normal, np.clip(rough, 0.3, 0.9), ao


def gen_iron_rusty(size, seed):
    base_noise = fbm(size, seed + 11, octaves=(2.8, 2.0, 1.3), weights=(0.5, 0.3, 0.2))
    rust_noise = fbm(size, seed + 13, octaves=(3.0, 1.8), weights=(0.65, 0.35))
    rust_mask = np.clip(normalize01(rust_noise) ** 1.6, 0, 1)
    metal_color = tint(base_noise, (0.18, 0.18, 0.19), (0.42, 0.42, 0.44))
    rust_color = tint(base_noise, (0.28, 0.13, 0.06), (0.55, 0.28, 0.12))
    albedo = lerp(metal_color, rust_color, rust_mask[..., None])
    albedo = add_soot(albedo, size, seed, 0.15)
    height = normalize01(base_noise * 0.4 + rust_mask * 0.6)
    normal = height_to_normal(height, strength=4.0)
    rough = 0.35 + rust_mask * 0.5 + (base_noise - 0.5) * 0.05
    ao = ao_from_height(height, 5)
    return albedo, normal, np.clip(rough, 0.2, 0.95), ao


def gen_plaster_dirty(size, seed):
    noise = fbm(size, seed + 15, octaves=(2.2, 1.6, 1.1), weights=(0.5, 0.3, 0.2))
    f1, f2, cell_id, _ = tileable_worley(size, 12, seed + 16)
    cracks = 1.0 - np.clip(normalize01(f2 - f1) * 25.0, 0, 1)
    dirt = fbm(size, seed + 17, octaves=(2.0, 1.3), weights=(0.6, 0.4))
    shade = 0.55 + (noise - 0.5) * 0.1 - dirt * 0.15
    plaster_color = tint(np.clip(shade, 0.2, 0.9), (0.45, 0.42, 0.38), (0.75, 0.72, 0.66))
    albedo = plaster_color * (1 - cracks[..., None] * 0.5)
    albedo = add_color_variation(albedo, size, seed, 0.03)
    albedo = add_soot(albedo, size, seed, 0.45)
    height = normalize01(cracks * 0.7 + (noise - 0.5) * 0.2)
    normal = height_to_normal(height, strength=3.0)
    rough = 0.7 + cracks * 0.1 + dirt * 0.1
    ao = ao_from_height(height, 6)
    return albedo, normal, np.clip(rough, 0.4, 0.95), ao


def gen_cloth_mistcloak(size, seed):
    xs, ys = periodic_coords(size)
    weave = 0.5 + 0.5 * np.sin((xs + ys) * 2 * np.pi * 90)
    weave2 = 0.5 + 0.5 * np.sin((xs - ys) * 2 * np.pi * 90)
    twill = (weave * 0.6 + weave2 * 0.4)
    noise = fbm(size, seed + 19, octaves=(2.6, 1.6), weights=(0.5, 0.5))
    tassel_dir = fbm(size, seed + 20, octaves=(1.3,), weights=(1.0,))
    shade = 0.16 + twill * 0.06 + (noise - 0.5) * 0.05 + (tassel_dir - 0.5) * 0.04
    cloth_color = tint(np.clip(shade, 0.05, 0.5), (0.05, 0.05, 0.06), (0.22, 0.21, 0.23))
    albedo = cloth_color
    albedo = add_color_variation(albedo, size, seed, 0.02)
    height = normalize01(twill * 0.6 + noise * 0.4)
    normal = height_to_normal(height, strength=1.6)
    rough = 0.82 + (noise - 0.5) * 0.08
    ao = ao_from_height(height, 3)
    return albedo, normal, np.clip(rough, 0.55, 0.98), ao


def gen_leather(size, seed):
    f1, f2, cell_id, _ = tileable_worley(size, 900, seed)
    pores = normalize01(f1)
    noise = fbm(size, seed + 22, octaves=(2.4, 1.6, 1.0), weights=(0.5, 0.3, 0.2))
    wrinkles = fbm(size, seed + 23, octaves=(1.4,), weights=(1.0,))
    shade = 0.32 + pores * 0.12 + (noise - 0.5) * 0.1 + (wrinkles - 0.5) * 0.12
    leather_color = tint(np.clip(shade, 0.1, 0.7), (0.15, 0.08, 0.05), (0.42, 0.24, 0.14))
    albedo = leather_color
    albedo = add_color_variation(albedo, size, seed, 0.03)
    height = normalize01(pores * 0.4 + wrinkles * 0.6)
    normal = height_to_normal(height, strength=2.2)
    rough = 0.55 + pores * 0.1 + (noise - 0.5) * 0.08
    ao = ao_from_height(height, 4)
    return albedo, normal, np.clip(rough, 0.35, 0.85), ao


def gen_obsidian(size, seed):
    noise = fbm(size, seed + 25, octaves=(3.2, 2.2, 1.4), weights=(0.5, 0.3, 0.2))
    f1, f2, cell_id, _ = tileable_worley(size, 30, seed + 26)
    fracture = 1.0 - np.clip(normalize01(f2 - f1) * 30.0, 0, 1)
    shade = 0.04 + (noise - 0.5) * 0.03 + fracture * 0.05
    obsidian_color = tint(np.clip(shade, 0.0, 0.2), (0.01, 0.01, 0.015), (0.08, 0.07, 0.09))
    albedo = obsidian_color
    height = normalize01(fracture * 0.8 + (noise - 0.5) * 0.2)
    normal = height_to_normal(height, strength=2.0)
    rough = 0.08 + fracture * 0.1 + (noise - 0.5) * 0.03
    ao = ao_from_height(height, 3)
    return albedo, normal, np.clip(rough, 0.03, 0.35), ao


MATERIALS = {
    "stone_wall": gen_stone_wall,
    "brick_soot": gen_brick_soot,
    "cobblestone": gen_cobblestone,
    "slate_roof": gen_slate_roof,
    "wood_planks": gen_wood_planks,
    "iron_rusty": gen_iron_rusty,
    "plaster_dirty": gen_plaster_dirty,
    "cloth_mistcloak": gen_cloth_mistcloak,
    "leather": gen_leather,
    "obsidian": gen_obsidian,
}

BASE_SEED = 20260925  # today's date -> deterministic, memorable seed


# --------------------------------------------------------------------------
# Effect / misc textures
# --------------------------------------------------------------------------

def gen_ash_flake_atlas(size, seed, out_dir):
    """4x4 atlas of small alpha ash-flake sprites."""
    cell = size // 4
    atlas = np.zeros((size, size, 4), dtype=np.float64)
    rng = np.random.default_rng(seed)
    for iy in range(4):
        for ix in range(4):
            sub = cell
            xs, ys = np.meshgrid(np.linspace(-1, 1, sub), np.linspace(-1, 1, sub))
            n = spectral_noise(sub, seed + iy * 4 + ix + 1, beta=2.0)
            r = np.sqrt(xs ** 2 + ys ** 2) + (n - 0.5) * 0.5
            rot = rng.uniform(0, np.pi)
            xr = xs * np.cos(rot) - ys * np.sin(rot)
            yr = xs * np.sin(rot) + ys * np.cos(rot)
            flake = np.clip(1.0 - np.abs(xr) * 2.2, 0, 1) * np.clip(1.0 - np.abs(yr) * 3.2, 0, 1)
            flake *= np.clip(1.0 - r, 0, 1)
            alpha = np.clip(flake * 1.4, 0, 1)
            grey = 0.55 + n * 0.2
            y0, x0 = iy * cell, ix * cell
            atlas[y0:y0 + sub, x0:x0 + sub, 0] = grey
            atlas[y0:y0 + sub, x0:x0 + sub, 1] = grey
            atlas[y0:y0 + sub, x0:x0 + sub, 2] = grey
            atlas[y0:y0 + sub, x0:x0 + sub, 3] = alpha
    save_png(atlas, os.path.join(out_dir, "ash_flake.png"), mode="RGBA")


def gen_coin_face(size, seed, out_dir):
    xs, ys = periodic_coords(size)
    xs = xs * 2 - 1
    ys = ys * 2 - 1
    r = np.sqrt(xs ** 2 + ys ** 2)
    disc = np.clip(1.0 - (r - 0.85) * 40, 0, 1)
    rim = np.clip(1.0 - np.abs(r - 0.9) * 60, 0, 1)
    ridges = 0.5 + 0.5 * np.sin(np.arctan2(ys, xs) * 90)
    noise = fbm(size, seed + 31, octaves=(2.4, 1.6), weights=(0.6, 0.4))
    shade = 0.55 + rim * 0.25 + (noise - 0.5) * 0.08 + (ridges - 0.5) * 0.03 * (r > 0.8)
    metal = tint(np.clip(shade, 0.2, 1.0), (0.35, 0.28, 0.12), (0.85, 0.72, 0.35))
    albedo = metal * disc[..., None] + np.array([0.02, 0.02, 0.02]) * (1 - disc[..., None])
    height = normalize01(disc * 0.6 + rim * 0.4 + noise * 0.1)
    normal = height_to_normal(height, strength=5.0)
    save_png(albedo, os.path.join(out_dir, "coin_face_albedo.png"))
    save_png(normal, os.path.join(out_dir, "coin_face_normal.png"))


def gen_vial_label(size, seed, out_dir):
    xs, ys = periodic_coords(size)
    paper = fbm(size, seed + 33, octaves=(2.0, 1.4), weights=(0.6, 0.4))
    shade = 0.75 + (paper - 0.5) * 0.12
    color = tint(np.clip(shade, 0.4, 1.0), (0.55, 0.48, 0.32), (0.88, 0.82, 0.65))
    border = np.clip(1 - np.minimum(np.minimum(xs, 1 - xs), np.minimum(ys, 1 - ys)) / 0.05, 0, 1)
    color = color * (1 - border[..., None] * 0.6)
    save_png(color, os.path.join(out_dir, "vial_label_albedo.png"))


def gen_spark(size, seed, out_dir):
    xs, ys = periodic_coords(size)
    xs = xs * 2 - 1
    ys = ys * 2 - 1
    r = np.sqrt(xs ** 2 + ys ** 2)
    core = np.clip(1.0 - r * 4, 0, 1) ** 2
    ang = np.arctan2(ys, xs)
    rays = (0.5 + 0.5 * np.cos(ang * 6)) ** 8
    glow = np.clip(1.0 - r * 1.6, 0, 1) ** 3
    alpha = np.clip(core + rays * glow * 0.8, 0, 1)
    rgb = tint(np.ones_like(alpha), (0.7, 0.85, 1.0), (1.0, 1.0, 0.9))
    out = np.dstack([rgb, alpha])
    save_png(out, os.path.join(out_dir, "spark.png"), mode="RGBA")


def gen_soft_particle(size, seed, out_dir):
    xs, ys = periodic_coords(size)
    xs = xs * 2 - 1
    ys = ys * 2 - 1
    r = np.sqrt(xs ** 2 + ys ** 2)
    alpha = np.clip(1.0 - r, 0, 1) ** 2.2
    rgb = np.ones((size, size, 3))
    out = np.dstack([rgb, alpha])
    save_png(out, os.path.join(out_dir, "soft_particle.png"), mode="RGBA")


def stable_seed(name: str) -> int:
    import zlib
    return zlib.crc32(name.encode("utf-8"))


def build_material(name, gen_fn, size, out_dir):
    seed = BASE_SEED + stable_seed(name) % 100000
    albedo, normal, rough, ao = gen_fn(size, seed)
    save_png(albedo, os.path.join(out_dir, f"{name}_albedo.png"))
    save_png(normal, os.path.join(out_dir, f"{name}_normal.png"))
    save_png(np.repeat(rough[..., None], 3, axis=-1), os.path.join(out_dir, f"{name}_roughness.png"))
    save_png(np.repeat(ao[..., None], 3, axis=-1), os.path.join(out_dir, f"{name}_ao.png"))
    print(f"  {name}: albedo/normal/roughness/ao ({size}x{size})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--out", type=str, default="assets/textures")
    ap.add_argument("--only", type=str, default="", help="comma-separated subset of material names")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    names = list(MATERIALS.keys())
    if args.only:
        wanted = set(args.only.split(","))
        names = [n for n in names if n in wanted]

    print(f"Generating {len(names)} PBR material sets at {args.size}x{args.size} ...")
    for name in names:
        build_material(name, MATERIALS[name], args.size, args.out)

    print("Generating effect textures ...")
    gen_ash_flake_atlas(512, BASE_SEED + 500, args.out)
    gen_coin_face(512, BASE_SEED + 600, args.out)
    gen_vial_label(256, BASE_SEED + 700, args.out)
    gen_spark(256, BASE_SEED + 800, args.out)
    gen_soft_particle(256, BASE_SEED + 900, args.out)

    print("Done.")


if __name__ == "__main__":
    main()

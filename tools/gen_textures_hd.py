#!/usr/bin/env python3
"""High-fidelity procedural PBR sets for the city (tileable, 2048 px).

Each set writes <name>_albedo.png, _normal.png, _roughness.png, _ao.png and
_height.png (16-bit, for parallax in world_surface.gdshader), replacing the
gen_textures.py version of the same name. Built from explicit layouts (setts,
courses, shingles, planks) with per-element variation, wear, grime and ash,
rather than one noise field, so they read closer to photographed surfaces.

Usage: python3 tools/gen_textures_hd.py [--size 2048] [--only cobblestone,...]
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_textures import (ao_from_height, fbm, height_to_normal, normalize01,  # noqa: E402
                          save_png, spectral_noise, tileable_worley)


def save_height(h: np.ndarray, path: str) -> None:
    a = np.clip(h, 0, 1)
    Image.fromarray((a * 65535.0 + 0.5).astype(np.uint16)).save(path)


def srgb(c):
    return np.array(c, dtype=np.float64) / 255.0


# --------------------------------------------------------------- layout helper
def running_layout(n: int, rows: int, width_range, seed: int, stagger=True):
    """A running-bond layout on the unit torus: `rows` rows of elements with
    random widths (fractions of the tile) that wrap seamlessly. Returns per
    pixel: element id, local u, v in [0, 1], element width and row height
    (tile fractions)."""
    rng = np.random.default_rng(seed)
    ys = (np.arange(n) + 0.5) / n
    xs = (np.arange(n) + 0.5) / n
    rh = 1.0 / rows
    eid = np.zeros((n, n), np.int64)
    u = np.zeros((n, n))
    w = np.zeros((n, n))
    row_of = np.minimum((ys * rows).astype(int), rows - 1)
    v = (ys * rows) - row_of
    next_id = 0
    for r in range(rows):
        widths = []
        while sum(widths) < 1.0:
            widths.append(rng.uniform(*width_range))
        widths = np.array(widths) / sum(widths)
        edges = np.concatenate([[0.0], np.cumsum(widths)])
        off = (0.5 * widths.mean() * (r % 2) if stagger else 0.0) + rng.uniform(-0.15, 0.15) * widths.mean()
        px = (xs - off) % 1.0
        k = np.clip(np.searchsorted(edges, px, side="right") - 1, 0, len(widths) - 1)
        mask = row_of == r
        uu = (px - edges[k]) / widths[k]
        eid[mask] = (next_id + k)[None, :].repeat(mask.sum(), 0)
        u[mask] = uu[None, :].repeat(mask.sum(), 0)
        w[mask] = widths[k][None, :].repeat(mask.sum(), 0)
        next_id += len(widths)
    return eid, u, v[:, None].repeat(n, 1), w, rh, next_id


def element_rand(eid: np.ndarray, count: int, seed: int, k: int = 1):
    rng = np.random.default_rng(seed)
    table = rng.random((count, k))
    return table[eid]


# ----------------------------------------------------------------- cobblestone
def gen_cobblestone(n: int, seed: int, tile_m: float = 1.6):
    """Granite setts in running courses, domed and worn, with dirt and ash in
    the joints."""
    rows = 10
    eid, u, v, w, rh, count = running_layout(n, rows, (0.11, 0.19), seed)
    rnd = element_rand(eid, count, seed + 2, 8)
    # distances to the sett's edges in metres, each sett inset by its own
    # amount so the joints vary (6-16 mm)
    inset = 0.003 + rnd[..., 4] * 0.005
    dx = np.minimum(u, 1 - u) * w * tile_m - inset
    dy = np.minimum(v, 1 - v) * rh * tile_m - inset
    edge_noise = (spectral_noise(n, seed + 1, beta=1.7) - 0.5) * 0.012 + (fbm(n, seed + 11) - 0.5) * 0.01
    k = 0.007
    e = -k * np.log(np.exp(-dx / k) + np.exp(-dy / k)) + edge_noise   # soft-min: slightly rounded corners
    t = np.clip(e / 0.022, 0.0, 1.0)
    dome = t ** 0.35
    # per-sett tilt and sink, split-face relief, chipped edges
    tilt = (rnd[..., 0] - 0.5) * 0.3 * (u - 0.5) + (rnd[..., 1] - 0.5) * 0.3 * (v - 0.5)
    sink = rnd[..., 2] * 0.14
    relief = spectral_noise(n, seed + 3, beta=2.0)
    grain = spectral_noise(n, seed + 12, beta=0.9)
    f1, f2, _, _ = tileable_worley(n, 1400, seed + 4)
    pits = np.clip(1 - (f2 - f1) * 70, 0, 1) * (1 - t) ** 1.5
    h_stone = 0.4 + 0.45 * dome - sink + tilt + 0.16 * (relief - 0.5) + 0.03 * (grain - 0.5) - 0.12 * pits
    stone_mask = np.clip(e / 0.0025, 0, 1)
    joint = 0.18 + 0.1 * fbm(n, seed + 5)          # sand and dirt fill the joints
    h = joint * (1 - stone_mask) + np.maximum(h_stone, joint) * stone_mask
    h = gaussian_filter(h, 0.6, mode="wrap")
    # colour: grey granite, a few warm or blue-grey setts, black/white grain
    pal = np.array([srgb((96, 94, 91)), srgb((108, 103, 96)), srgb((84, 84, 88)),
                    srgb((118, 111, 101)), srgb((92, 87, 80)), srgb((76, 77, 82)), srgb((101, 98, 95))])
    pick = (rnd[..., 3] * len(pal)).astype(int)
    base = pal[pick] * (0.88 + 0.24 * rnd[..., 5])[..., None]
    mott = fbm(n, seed + 7)
    dark_grain = (grain > 0.68).astype(float) * 0.45
    light_grain = (grain < 0.28).astype(float) * 0.25
    stone = base * (0.85 + 0.25 * mott[..., None])
    stone = stone * (1 - dark_grain[..., None]) + srgb((165, 160, 152)) * light_grain[..., None] + stone * 0
    stone *= (0.86 + 0.22 * dome[..., None])             # worn tops catch more light
    dirt = srgb((48, 42, 36)) * (0.75 + 0.5 * fbm(n, seed + 8)[..., None])
    edge_dirt = np.clip(1 - t * 2.5, 0, 1)[..., None] * 0.55
    alb = stone * (1 - edge_dirt) + dirt * edge_dirt
    alb = alb * stone_mask[..., None] + dirt * (1 - stone_mask[..., None])
    ash = srgb((128, 125, 120))
    ash_amt = np.clip((fbm(n, seed + 9) - 0.5) * 2.5, 0, 1) * (1 - t) * 0.5
    alb = alb * (1 - ash_amt[..., None]) + ash * ash_amt[..., None]
    rough = 0.66 - 0.16 * dome * rnd[..., 6] + 0.12 * mott
    rough = rough * stone_mask + 0.96 * (1 - stone_mask)
    ao = ao_from_height(h, 5) * (0.7 + 0.3 * stone_mask)
    return alb, height_to_normal(h, 10.0), rough, ao, h


# ------------------------------------------------------------- shared pieces
def streaks(n: int, seed: int, length: float = 8.0) -> np.ndarray:
    """Tileable vertical run-off streaks (soot, rain, ash) in [0, 1]."""
    base = spectral_noise(n, seed, beta=1.2)
    # stretch vertically: blur strongly along y only (wrap keeps it tileable)
    st = gaussian_filter(base, sigma=(n / length * 0.35, 1.2), mode="wrap")
    return normalize01(st)


def masonry(n, seed, *, rows, widths, tile_m, joint, bevel, relief, pillow, palette, mortar_col,
            mortar_depth=0.25, chip=0.6, stagger=True, edge_jitter=0.01, var=0.2):
    """Shared block masonry: running courses of blocks with jittered edges,
    pillowed faces, chipped arrises, recessed mortar. Returns (albedo,
    height, mask, t (0 at the joint .. 1 a bevel inside), rnd, u, v)."""
    eid, u, v, w, rh, count = running_layout(n, rows, widths, seed, stagger=stagger)
    rnd = element_rand(eid, count, seed + 2, 8)
    inset = joint * (0.6 + 0.8 * rnd[..., 4])
    dx = np.minimum(u, 1 - u) * w * tile_m - inset
    dy = np.minimum(v, 1 - v) * rh * tile_m - inset
    en = (spectral_noise(n, seed + 1, beta=1.6) - 0.5) * edge_jitter * 2
    k = max(bevel * 0.4, 0.002)
    e = -k * np.log(np.exp(-dx / k) + np.exp(-dy / k)) + en
    t = np.clip(e / bevel, 0, 1)
    mask = np.clip(e / 0.002, 0, 1)
    rel = spectral_noise(n, seed + 3, beta=2.1)
    f1, f2, _, _ = tileable_worley(n, 1200, seed + 4)
    chips = np.clip(1 - (f2 - f1) * 50, 0, 1) * (1 - t) ** 2 * chip
    pil = np.sin(np.clip(u, 0, 1) * np.pi) ** 0.5 * np.sin(np.clip(v, 0, 1) * np.pi) ** 0.5
    h_block = 0.55 + 0.25 * t ** 0.5 + pillow * pil + relief * (rel - 0.5) - 0.25 * chips \
        + (rnd[..., 0] - 0.5) * 0.08
    mortar_h = mortar_depth * (0.8 + 0.4 * fbm(n, seed + 5))
    h = mortar_h * (1 - mask) + np.maximum(h_block, mortar_h) * mask
    h = gaussian_filter(h, 0.6, mode="wrap")
    pal = np.array([srgb(c) for c in palette])
    base = pal[(rnd[..., 3] * len(pal)).astype(int)] * (1 - var / 2 + var * rnd[..., 5])[..., None]
    mott = fbm(n, seed + 7)
    grain = spectral_noise(n, seed + 12, beta=0.9)
    blk = base * (0.85 + 0.25 * mott[..., None]) * (0.93 + 0.12 * grain[..., None])
    blk *= (1 - 0.35 * chips[..., None])
    mortar = srgb(mortar_col) * (0.85 + 0.3 * fbm(n, seed + 8)[..., None])
    alb = blk * mask[..., None] + mortar * (1 - mask[..., None])
    return alb, h, mask, t, rnd, u, v


def weather(alb, h, n, seed, soot=0.35, ash=0.25):
    """Soot run-off streaks and ash caught on the upper edges of relief."""
    st = streaks(n, seed + 20)
    runs = np.clip((st - 0.58) * 3.0, 0, 1) * np.clip(fbm(n, seed + 22) * 1.6 - 0.3, 0, 1)
    alb = alb * (1 - soot * runs[..., None])
    up = np.clip((h - np.roll(h, 3, axis=0)) * 12, 0, 1)    # faces looking up the texture catch ash
    a = ash * up * np.clip(fbm(n, seed + 21) * 1.5 - 0.3, 0, 1)
    return alb * (1 - a[..., None]) + srgb((140, 136, 130)) * a[..., None]


def finish(alb, h, rough, n, strength, ao_r=5):
    return alb, height_to_normal(h, strength), rough, ao_from_height(h, ao_r), h


# ------------------------------------------------------------------ stone wall
def gen_stone_wall(n, seed):
    """Coursed rubble: roughly squared limestone blocks of mixed size in
    rough courses, lime mortar, soot run-off."""
    alb, h, mask, t, rnd, u, v = masonry(
        n, seed, rows=10, widths=(0.08, 0.2), tile_m=2.6, joint=0.008, bevel=0.03, relief=0.22, pillow=0.12,
        palette=[(132, 126, 115), (120, 115, 106), (142, 135, 122), (110, 106, 99), (126, 118, 104),
                 (100, 97, 92)],
        mortar_col=(118, 114, 106), edge_jitter=0.02, chip=0.8, var=0.25)
    alb = weather(alb, h, n, seed, soot=0.4, ash=0.3)
    rough = (0.82 + 0.1 * fbm(n, seed + 30)) * mask + 0.95 * (1 - mask)
    return finish(alb, h, rough, n, 9.0)


def gen_ashlar(n, seed):
    """Dressed sandstone/limestone blocks, fine joints, crisp bevels."""
    alb, h, mask, t, rnd, u, v = masonry(
        n, seed, rows=12, widths=(0.09, 0.19), tile_m=2.4, joint=0.004, bevel=0.012, relief=0.06, pillow=0.03,
        palette=[(150, 142, 128), (160, 151, 135), (142, 134, 121), (156, 145, 126), (138, 131, 120)],
        mortar_col=(120, 114, 104), edge_jitter=0.003, chip=0.4, var=0.12)
    alb = weather(alb, h, n, seed, soot=0.3, ash=0.2)
    rough = (0.78 + 0.1 * fbm(n, seed + 30)) * mask + 0.92 * (1 - mask)
    return finish(alb, h, rough, n, 7.0)


def gen_brick_soot(n, seed):
    """Sooty fired brick, stretcher bond, recessed mortar."""
    alb, h, mask, t, rnd, u, v = masonry(
        n, seed, rows=30, widths=(0.105, 0.115), tile_m=2.0, joint=0.005, bevel=0.006, relief=0.08, pillow=0.02,
        palette=[(112, 58, 44), (98, 52, 40), (124, 68, 50), (104, 56, 42), (106, 62, 48), (90, 50, 40)],
        mortar_col=(104, 98, 90), edge_jitter=0.002, chip=0.7, var=0.3, mortar_depth=0.3)
    # a few overburnt dark headers and pale salt-bloomed bricks
    over = (rnd[..., 6] > 0.93)[..., None]
    alb = np.where(over, alb * 0.55, alb)
    alb = weather(alb, h, n, seed, soot=0.55, ash=0.25)
    rough = (0.85 + 0.08 * fbm(n, seed + 30)) * mask + 0.95 * (1 - mask)
    return finish(alb, h, rough, n, 8.0, ao_r=3)


def gen_plaster_dirty(n, seed):
    """Lime render over brick: hairline cracks, damp and soot staining, and
    patches where the render has fallen away to the brick beneath."""
    pl = fbm(n, seed + 1)
    fine = spectral_noise(n, seed + 2, beta=1.4)
    f1, f2, _, _ = tileable_worley(n, 40, seed + 3)
    crack_on = np.clip((fbm(n, seed + 4) - 0.6) * 6, 0, 1)
    cracks = np.clip(1 - (f2 - f1) * 260, 0, 1) * crack_on
    big = gaussian_filter(spectral_noise(n, seed + 5, beta=2.8), 6, mode="wrap")
    loss = np.clip((normalize01(big) - 0.74) * 12, 0, 1)
    b_alb, b_h, b_mask, _, _, _, _ = masonry(
        n, seed + 50, rows=30, widths=(0.105, 0.115), tile_m=3.0, joint=0.005, bevel=0.006, relief=0.06,
        pillow=0.02, palette=[(104, 58, 44), (92, 52, 42), (116, 66, 50)], mortar_col=(110, 104, 96),
        edge_jitter=0.002, var=0.25)
    plaster = srgb((150, 143, 131)) * (0.86 + 0.18 * pl[..., None]) * (0.95 + 0.08 * fine[..., None])
    plaster *= (1 - 0.5 * cracks[..., None])
    h_pl = 0.75 + 0.06 * pl + 0.02 * fine - 0.12 * cracks
    alb = plaster * (1 - loss[..., None]) + b_alb * loss[..., None]
    h = h_pl * (1 - loss) + (b_h * 0.45) * loss
    # rim of broken render around the losses
    rim = np.clip(loss * (1 - loss) * 4, 0, 1)
    alb *= (1 - 0.25 * rim[..., None])
    alb = weather(alb, h, n, seed, soot=0.45, ash=0.2)
    rough = 0.9 + 0.06 * pl
    return finish(alb, gaussian_filter(h, 0.6, mode="wrap"), rough, n, 6.0)


def gen_slate_roof(n, seed):
    """Overlapping slates in staggered rows: each slate's lower edge stands
    proud of the next row, so the roof has real stepped relief."""
    rows = 14
    eid, u, v, w, rh, count = running_layout(n, rows, (0.08, 0.12), seed)
    rnd = element_rand(eid, count, seed + 2, 8)
    gap = 0.004 / (w * 2.2)
    side = np.clip((np.minimum(u, 1 - u) - gap) / 0.02, 0, 1)
    # v = 0 at the top of the row (texture y down = down the roof): the slate
    # rises towards its lower edge
    rise = 0.25 + 0.7 * v ** 1.2
    rel = spectral_noise(n, seed + 3, beta=2.0)
    cut = np.clip((1 - v) / 0.04, 0, 1)                  # chipped lower edge
    jag = (spectral_noise(n, seed + 9, beta=1.3) - 0.5) * 0.06
    edge = np.clip((1 - v + jag) / 0.03, 0, 1)
    h = (rise + 0.06 * (rel - 0.5) + (rnd[..., 0] - 0.5) * 0.1) * side * edge
    h = gaussian_filter(h, 0.7, mode="wrap")
    pal = np.array([srgb(c) for c in [(58, 62, 70), (66, 68, 74), (52, 55, 62), (72, 72, 76), (60, 58, 62)]])
    base = pal[(rnd[..., 3] * len(pal)).astype(int)] * (0.85 + 0.3 * rnd[..., 5])[..., None]
    mott = fbm(n, seed + 7)
    alb = base * (0.85 + 0.25 * mott[..., None])
    alb *= (0.55 + 0.45 * side * edge)[..., None]
    lich = np.clip((fbm(n, seed + 8) - 0.62) * 5, 0, 1) * 0.5
    alb = alb * (1 - lich[..., None]) + srgb((112, 108, 96)) * lich[..., None]
    alb = weather(alb, h, n, seed, soot=0.25, ash=0.45)
    rough = 0.55 + 0.25 * mott + 0.2 * lich
    return finish(alb, h, rough, n, 10.0, ao_r=4)


def gen_wood_planks(n, seed):
    """Weathered vertical boards: grain, knots, gaps and nail heads."""
    cols = 8
    xs = (np.arange(n) + 0.5) / n
    board = np.floor(xs * cols).astype(int)
    bu = xs * cols - board
    rng = np.random.default_rng(seed)
    br = rng.random((cols, 4))
    grain_src = spectral_noise(n, seed + 1, beta=1.6)
    grain = normalize01(gaussian_filter(grain_src, sigma=(n * 0.03, 0.8), mode="wrap"))
    rings = np.sin((grain * 40 + bu[None, :] * 6) * np.pi) * 0.5 + 0.5
    gap = np.clip((np.minimum(bu, 1 - bu) - 0.02) / 0.02, 0, 1)[None, :].repeat(n, 0)
    cup = np.sin(np.clip(bu, 0, 1) * np.pi)[None, :] ** 0.4
    h = (0.5 + 0.2 * cup + 0.08 * rings + 0.05 * (grain - 0.5)) * gap
    base = np.array([srgb((92, 70, 52)), srgb((80, 62, 48)), srgb((100, 78, 58)), srgb((72, 58, 46))])
    bc = base[(br[:, 0] * 4).astype(int)][board][None, :, :].repeat(n, 0)
    alb = bc * (0.8 + 0.3 * rings[..., None]) * (0.85 + 0.2 * fbm(n, seed + 2)[..., None])
    alb *= (0.4 + 0.6 * gap[..., None])
    # weathering to silver-grey
    grey = np.clip(fbm(n, seed + 3) * 1.4 - 0.35, 0, 1)[..., None] * 0.5
    lum = alb.mean(-1, keepdims=True)
    alb = alb * (1 - grey) + lum * np.array([1.05, 1.0, 0.95]) * grey
    alb = weather(alb, h, n, seed, soot=0.35, ash=0.2)
    rough = 0.8 + 0.12 * rings
    return finish(alb, gaussian_filter(h, 0.5, mode="wrap"), rough, n, 6.0, ao_r=3)


MATERIALS = {
    "cobblestone": gen_cobblestone,
    "stone_wall": gen_stone_wall,
    "ashlar": gen_ashlar,
    "brick_soot": gen_brick_soot,
    "plaster_dirty": gen_plaster_dirty,
    "slate_roof": gen_slate_roof,
    "wood_planks": gen_wood_planks,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--out", default="assets/textures")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    names = [x for x in MATERIALS if not a.only or x in a.only.split(",")]
    for name in names:
        seed = 9000 + sum(map(ord, name))
        alb, nrm, rough, ao, h = MATERIALS[name](a.size, seed)
        p = os.path.join(a.out, name)
        save_png(np.clip(alb, 0, 1), p + "_albedo.png")
        save_png(nrm, p + "_normal.png")
        save_png(np.repeat(np.clip(rough, 0, 1)[..., None], 3, -1), p + "_roughness.png")
        save_png(np.repeat(np.clip(ao, 0, 1)[..., None], 3, -1), p + "_ao.png")
        save_height(normalize01(h), p + "_height.png")
        print(f"  {name}: {a.size}px")


if __name__ == "__main__":
    main()

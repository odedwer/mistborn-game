#!/usr/bin/env python3
"""Fits the death-settle skirt bone poses of a long robe or gown
(`anim.SETTLE[style]["lie"]`, see SKIRT_CLASS): how far the lying cloth is
flattened front to back (`fb`), spread sideways (`lat`) and shifted (`lift`)
over the hips, thighs and shins.

The objective, over the lying part of `die` (0.95 s and 1.3 s by default) and
every character of the style:
  - the lower half of the cloth lies as low as it can (its mean height), and
    the hem too (its highest point, weighted by --hem-weight);
  - every leg and hip vertex the cloth covers in the rest pose (from
    --margin above the hem up, m for a 1.75 m character) stays at least 1 cm
    inside it (or as deep as it already was, if less); a steep penalty;
  - no cloth sinks more than 2 cm under the floor; a steep penalty.
It is minimised with differential evolution, then polished with Powell. It
needs numpy and scipy, not Blender, and takes a few minutes per style.

Usage:
  tools/characters/fit_robe_settle.py inquisitor          # fit; prints a _lie(...) line for anim.SETTLE
  tools/characters/fit_robe_settle.py gown --free-lat --margin=0.0   (what "gown" uses by default)
  tools/characters/fit_robe_settle.py --check             # every style: refit, compare with anim.SETTLE

The robes (inquisitor, sazed, marsh, obligator, obligator_b) fit the six fb
and lift values with the sideways spread fixed at 1.1 / 1.15 / 1.15. The
hoop skirts ("gown": vin_gown and noble_woman) also fit the spread (--free-lat).
After fitting, run clearance.py --settle and --cloth --anim=die.
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import anim  # noqa: E402
import clearance as C  # noqa: E402

PARTS = ("hips", "thigh", "shin")
FIT_KEYS = [f"sk_{p}_{k}" for p in PARTS for k in ("fb", "lift")]
LAT_KEYS = [f"sk_{p}_lat" for p in PARTS]
FIXED_LAT = {"sk_hips_lat": 1.1, "sk_thigh_lat": 1.15, "sk_shin_lat": 1.15}
BOUNDS = {"fb": (0.1, 1.1), "lat": (0.9, 1.6), "lift": (-0.1, 0.15)}
COVER = 0.01  # (m) how deep the covered legs must stay inside the cloth
FLOOR = -0.02  # (m) how far the cloth may sink under the floor
# How each style was fitted (art pass 16): the gowns' hems reach the floor
# and the toes poked through, so their feet count as covered too.
STYLE_OPTS = {"gown": dict(free_lat=True, margin=0.0)}


def style_chars(style):
    return [n for n in C.settling() if C._built(n)[1]["style"] == style]


class Fit:
    def __init__(self, style, names=None, times=(0.95, 1.3), margin=C.CLOTH_HEM_MARGIN, hem_weight=1.0):
        self.style, self.times, self.hem_weight = style, times, hem_weight
        saved = (C.CLOTH_HEM_MARGIN, C.LEG_BONES)
        C.CLOTH_HEM_MARGIN = margin
        C.LEG_BONES = C.LEG_BONES | {"Hips"}  # (the buttocks stay under the cloth too)
        try:
            self.chars = []
            for n in names or style_chars(style):
                ch = C.Cloth(n)
                V, Wm, bones = C._skin_matrix(ch.b)
                grid = np.unique(np.concatenate([g.reshape(-1) for g in ch.grid_idx]))
                low = np.unique(np.concatenate([g[len(g) // 2:].reshape(-1) for g in ch.grid_idx]))
                hem = np.unique(np.concatenate([g[-1].reshape(-1) for g in ch.grid_idx]))
                self.chars.append((ch, Wm[grid], V[grid], np.isin(grid, low), np.isin(grid, hem), bones))
        finally:
            C.CLOTH_HEM_MARGIN, C.LEG_BONES = saved
        self.target = {}

    def cost(self, lie, verbose=False):
        saved = anim.SETTLE[self.style]
        anim.SETTLE[self.style] = dict(saved, lie=lie)
        try:
            f = 0.0
            for ch, Wg, Vg, low, hem, bones in self.chars:
                A = anim.make_anims(self.style, ch.S)
                for t in self.times:
                    p = A["die"][1](t)
                    cover = ch.measure(p)
                    # (a leg already shallower than COVER needn't get deeper)
                    tgt = self.target.setdefault((ch.name, t), min(COVER, cover - 0.001))
                    Q, off = ch.rig.solve(p)
                    D, Hd = C._pose(ch.S, Q, off, ch.rig.loc)
                    z = C._skin(ch.S, D, Hd, bones, Vg, Wg)[:, 2]
                    under = np.maximum(FLOOR - z, 0.0)
                    f += (z[low].mean() + self.hem_weight * z[hem].max()
                          + 1e5 * max(tgt - cover, 0.0) ** 2 + 1e3 * float((under ** 2).sum()))
                    if verbose:
                        print(f"  {ch.name} t={t}: legs {cover:+.3f} inside, lowest cloth {z.min():+.3f}, "
                              f"lower half mean {z[low].mean():.3f}, hem {z[hem].max():.3f}")
            return f
        finally:
            anim.SETTLE[self.style] = saved


def fit(style, free_lat=False, margin=C.CLOTH_HEM_MARGIN, hem_weight=1.0, gens=60, seed=1, verbose=True):
    """Returns the fitted `lie` dict."""
    from scipy.optimize import differential_evolution, minimize
    F = Fit(style, margin=margin, hem_weight=hem_weight)
    keys = FIT_KEYS + (LAT_KEYS if free_lat else [])
    fixed = {} if free_lat else dict(FIXED_LAT)
    bounds = [BOUNDS[k.rsplit("_", 1)[1]] for k in keys]
    x0 = np.array([1.0 if k.endswith(("fb", "lat")) else 0.0 for k in keys])

    def f(x):
        return F.cost(dict(fixed, **dict(zip(keys, map(float, x)))))

    if verbose:
        print(f"{style}: {', '.join(c[0].name for c in F.chars)}, unflattened")
        F.cost(dict(fixed, **dict(zip(keys, x0))), verbose=True)
    r = differential_evolution(f, bounds, seed=seed, maxiter=gens, popsize=12, tol=1e-6, polish=False, x0=x0)
    r = minimize(f, r.x, method="Powell", bounds=bounds, options=dict(maxiter=3000, xtol=1e-3, ftol=1e-7))
    lie = dict(fixed, **{k: round(float(v), 3) for k, v in zip(keys, r.x)})
    if verbose:
        print(f"{style}: fitted")
        F.cost(lie, verbose=True)
    return lie


def lie_line(style, lie):
    a = ", ".join(f"{lie[f'sk_{p}_{k}']:g}" for p in PARTS for k in ("fb", "lift"))
    lat = tuple(lie[k] for k in LAT_KEYS)
    tail = "" if lat == tuple(FIXED_LAT[k] for k in LAT_KEYS) else f", lat={lat}"
    return f'    "{style}": {{"fall": {{}}, "lie": _lie({a}{tail})}},'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("styles", nargs="*", help=f"styles (default: all of {', '.join(anim.SETTLE)})")
    ap.add_argument("--free-lat", action="store_true", default=None, help="also fit the sideways spread")
    ap.add_argument("--margin", type=float, default=None,
                    help=f"covered legs start this far above the hem (m, default {C.CLOTH_HEM_MARGIN})")
    ap.add_argument("--hem-weight", type=float, default=None, help="weight of the hem height (default 1)")
    ap.add_argument("--gens", type=int, default=60, help="differential evolution generations (default 60)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--check", action="store_true",
                    help="compare each refit with anim.SETTLE: fb/lat within 0.06, lift within 1.5 cm")
    a = ap.parse_args(argv)
    bad = 0
    for style in a.styles or list(anim.SETTLE):
        o = dict(dict(free_lat=False, margin=C.CLOTH_HEM_MARGIN, hem_weight=1.0), **STYLE_OPTS.get(style, {}))
        for k in o:
            if getattr(a, k) is not None:
                o[k] = getattr(a, k)
        lie = fit(style, gens=a.gens, seed=a.seed, verbose=not a.check, **o)
        print(lie_line(style, lie))
        if a.check:
            cur = anim.SETTLE[style]["lie"]
            off = {k: (cur[k], lie[k]) for k in lie
                   if abs(cur[k] - lie[k]) > (0.015 if k.endswith("lift") else 0.06)}
            print(f"  {'differs: ' + str(off) if off else 'matches anim.SETTLE'}")
            bad += bool(off)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

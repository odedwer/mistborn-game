#!/usr/bin/env python3
"""Weapon clearance check: how close each armed character's weapon comes to
its own body, frame by frame, in every animation.

Needs only numpy (no Blender): it builds the character with chars.py, poses
the skeleton with anim.py exactly as build_characters.py bakes it, and skins
the mesh with linear blend skinning. The weapon is measured through the
capsules its builder registers (`Body.weapon_caps`), and a shield through its
disc (`Body.shields`). The body is sampled at its vertices plus the centroid
and edge midpoints of every face.

Regions (the gripping hand and forearm are never checked):
  head   Head-weighted surface (hair, helmet, hood, eye spikes)
  neck   Neck
  torso  Hips, Spine, Chest, UpperChest, shoulders (minus skirts)
  arms   the free arm, hand and the weapon arm's upper arm
  legs   thighs, shins and feet, where no skirt covers them (in the rest pose)
  skirt  robe / tunic / coat skirts (`Body.skirt`)
  shield the character's own shield (the hazekiller's round shield and its boss)

Distances are in metres, surface to surface (negative = interpenetrating).
A region fails when its minimum falls below its threshold.

Usage:
  tools/characters/clearance.py                     # every armed character, every clip: summary
  tools/characters/clearance.py inquisitor --anim=pull --frames   # per-frame table
  tools/characters/clearance.py guard thug --anim=run,sprint --step=2
  tools/characters/clearance.py --threshold=head=0.02 --threshold=skirt=0
Exit status: 0 when every region clears its threshold, 1 otherwise.
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import chars  # noqa: E402
from anim import ANIM_NAMES, FPS, LOOPING, Rig, make_anims  # noqa: E402

ARMED = ["guard", "hazekiller", "thug", "inquisitor"]
REGIONS = ["head", "neck", "torso", "arms", "legs", "skirt", "shield"]
# Default failure thresholds (m). Head, neck and torso keep a 1 cm gap. The
# arms, legs and skirts are soft and move with the weapon arm, so only real
# interpenetration fails; the shield only must not be passed through.
THRESHOLDS = {"head": 0.01, "neck": 0.01, "torso": 0.01, "arms": 0.0, "legs": 0.0, "skirt": 0.0, "shield": 0.0}

BONE_REGION = {
    "Head": "head", "Neck": "neck",
    "Hips": "torso", "Spine": "torso", "Chest": "torso", "UpperChest": "torso",
    "LeftShoulder": "torso", "RightShoulder": "torso",
    "LeftUpperLeg": "legs", "RightUpperLeg": "legs", "LeftLowerLeg": "legs", "RightLowerLeg": "legs",
    "LeftFoot": "legs", "RightFoot": "legs", "LeftToes": "legs", "RightToes": "legs",
}


def _covered(p, skirts):
    """True when rest-pose point p lies above the hem of a skirt that wraps
    round to it (`Body.skirts`: hem z, centre y at the hem, arc or None)."""
    for z_hem, yc, arc in skirts:
        if p[2] < z_hem:
            continue
        if arc is None:
            return True
        # tube() angle for a skirt lofted downwards: 0 = -X, 90 = forward (+Y)
        th = np.degrees(np.arctan2(p[1] - yc, -p[0])) % 360.0
        a0, a1 = arc
        if any(a0 <= th + k <= a1 for k in (-360.0, 0.0, 360.0)):
            return True
    return False


def _arm_bones(hand_bone):
    """Arm bones checked against a weapon held by `hand_bone` (its own hand
    and forearm grip the weapon and are left out)."""
    side, free = ("Right", "Left") if hand_bone.startswith("Right") else ("Left", "Right")
    return {free + "UpperArm", free + "LowerArm", free + "Hand", side + "UpperArm"}


def _pose(S, Q, off):
    """World rotation and head position of every bone (as bake_actions keys them)."""
    D, Hd = {}, {}
    for b in S.order:
        par = S.bones[b][0]
        if par is None:
            D[b] = Q[b]
            Hd[b] = S.head(b) + off
        else:
            D[b] = D[par] @ Q[b]
            Hd[b] = Hd[par] + D[par] @ (S.head(b) - S.head(par))
    return D, Hd


def _seg_dist(P, a, c):
    """Distances from points P (N,3) to segment a-c."""
    ab = c - a
    u = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + u[:, None] * ab), axis=1)


def _caps_dist(P, A, C, R, bound=None):
    """Minimum surface distance from points P (N,3) to capsules A-C (K,3) of
    radii R (K,). `bound` = (a, c, r), one capsule enclosing them all, culls
    points that cannot beat the best of the closest few (the result is exact)."""
    if bound is not None and len(P) > 64:
        lb = _seg_dist(P, bound[0], bound[1]) - bound[2]
        near = np.argpartition(lb, 32)[:32]
        best = _caps_dist(P[near], A, C, R)
        P = P[lb < best]
        if len(P) == 0:
            return best
        return min(best, _caps_dist(P, A, C, R))
    AB = C - A
    den = np.maximum(np.einsum("kj,kj->k", AB, AB), 1e-12)
    PA = P[:, None, :] - A[None, :, :]
    u = np.clip(np.einsum("nkj,kj->nk", PA, AB) / den, 0.0, 1.0)
    D = PA - u[:, :, None] * AB[None, :, :]
    return float((np.sqrt(np.einsum("nkj,nkj->nk", D, D)) - R).min())


def _disc_dist(P, c, n, R, ht):
    """Distances from points P to a solid disc (centre c, normal n, radius R, half thickness ht)."""
    rel = P - c
    h = rel @ n
    radial = np.linalg.norm(rel - h[:, None] * n, axis=1)
    dr = np.maximum(radial - R, 0.0)
    dh = np.maximum(np.abs(h) - ht, 0.0)
    return np.sqrt(dr * dr + dh * dh)


class Character:
    """One character's mesh, regions and weapon proxies, ready to pose."""

    def __init__(self, name):
        self.name = name
        b, info = chars.BUILDERS[name]()
        self.b, self.S, self.style = b, b.S, info["style"]
        if not b.weapon_caps:
            raise ValueError(f"{name} carries no weapon with clearance capsules")
        m = b.m
        V = np.array(m.verts)
        bones = list(self.S.order)
        bi = {n: i for i, n in enumerate(bones)}
        Wm = np.zeros((len(V), len(bones)))
        for i, w in enumerate(m.weights):
            for bn, x in w.items():
                Wm[i, bi[bn]] = x
        Wm /= Wm.sum(axis=1, keepdims=True)
        dom = [bones[j] for j in Wm.argmax(axis=1)]
        tag = [None] * len(V)
        for part, ranges in b.parts.items():
            for s0, s1 in ranges:
                for i in range(s0, s1):
                    tag[i] = part
        hands = {cap[0] for cap in b.weapon_caps}
        arm_bones = set().union(*(_arm_bones(h) for h in hands))
        grip = set().union(*({h, h.replace("Hand", "LowerArm")} for h in hands))

        def region(i):
            if tag[i] in ("weapon", "shield"):
                return None
            if tag[i] == "skirt":
                return "skirt"
            if dom[i] in grip:
                return None
            if dom[i] in arm_bones:
                return "arms"
            r = BONE_REGION.get(dom[i])
            if r == "legs" and _covered(V[i], b.skirts):
                return None
            return r

        vreg = [region(i) for i in range(len(V))]
        # sample points: vertices, face centroids, edge midpoints (each a set of
        # vertex indices averaged after skinning); a face/edge belongs to a
        # region when all its vertices do
        samples = {r: [] for r in REGIONS}
        for i, r in enumerate(vreg):
            if r:
                samples[r].append((i,))
        edges = set()
        for f in m.faces:
            rs = {vreg[i] for i in f}
            if len(rs) == 1 and None not in rs:
                r = rs.pop()
                samples[r].append(tuple(f))
                for k in range(len(f)):
                    e = tuple(sorted((f[k], f[(k + 1) % len(f)])))
                    if e not in edges:
                        edges.add(e)
                        samples[r].append(e)
        self.samples = {}
        used = sorted({i for r in samples for s in samples[r] for i in s})
        self.used = np.array(used, dtype=int)
        pos = {v: k for k, v in enumerate(used)}
        for r, lst in samples.items():
            if not lst:
                continue
            # group by arity for vectorised averaging
            groups = {}
            for s in lst:
                groups.setdefault(len(s), []).append([pos[i] for i in s])
            self.samples[r] = [np.array(g, dtype=int) for g in groups.values()]
        self.V = V[self.used]
        self.Wm = Wm[self.used]
        self.bones = bones
        self.anims = make_anims(self.style, self.S)
        self.rig = Rig(self.S)
        # one capsule around the whole weapon (rest pose) for culling
        self.bound = None
        if len(hands) == 1:
            E = np.array([p for cap in b.weapon_caps for p in cap[1:3]])
            rr = np.array([cap[3] for cap in b.weapon_caps for _ in range(2)])
            mu = E.mean(axis=0)
            ax = np.linalg.svd(E - mu)[2][0]
            pr = (E - mu) @ ax
            a, c = mu + ax * pr.min(), mu + ax * pr.max()
            self.bound = (next(iter(hands)), a, c, float((_seg_dist(E, a, c) + rr).max()) + 1e-6)

    def regions(self):
        rs = [r for r in REGIONS if r in self.samples and r != "shield"]
        if self.b.shields:
            rs.append("shield")
        return rs

    def frame(self, anim, t):
        """{region: min clearance (m)} for `anim` at time t."""
        return self.measure(self.anims[anim][1](t))

    def measure(self, params):
        """{region: min clearance (m)} for one anim.py pose parameter dict."""
        S = self.S
        Q, off = self.rig.solve(params)
        D, Hd = _pose(S, Q, off)
        # linear blend skinning of the sampled vertices
        P = np.zeros_like(self.V)
        for j, bn in enumerate(self.bones):
            w = self.Wm[:, j]
            nz = w > 0
            if nz.any():
                P[nz] += w[nz, None] * (Hd[bn] + (self.V[nz] - S.head(bn)) @ D[bn].T)

        def xf(bn, p):
            return Hd[bn] + D[bn] @ (p - S.head(bn))

        caps = [(xf(bn, a), xf(bn, c), r) for bn, a, c, r in self.b.weapon_caps]
        A = np.array([c[0] for c in caps])
        C = np.array([c[1] for c in caps])
        R = np.array([c[2] for c in caps])
        bnd = None
        if self.bound:
            bn, a, c, rb = self.bound
            bnd = (xf(bn, a), xf(bn, c), rb)
        out = {}
        for r, groups in self.samples.items():
            pts = np.concatenate([P[g].mean(axis=1) for g in groups])
            out[r] = _caps_dist(pts, A, C, R, bnd)
        for bn, c, n, R, ht in self.b.shields:
            cw, nw = xf(bn, c), D[bn] @ n
            best = 9.0
            for a, c2, rad in caps:
                k = max(2, int(np.linalg.norm(c2 - a) / 0.005) + 1)
                pts = a + np.linspace(0.0, 1.0, k)[:, None] * (c2 - a)
                best = min(best, float((_disc_dist(pts, cw, nw, R, ht) - rad).min()))
            out["shield"] = min(out.get("shield", 9.0), best)
        return out

    def scan(self, anim, step=1):
        """[(t, {region: clearance})] for every `step`-th frame of `anim`."""
        n = self.anims[anim][0]
        last = n - 1 if anim in LOOPING else n  # a loop's last frame repeats frame 0
        return [(f / FPS, self.frame(anim, f / FPS)) for f in list(range(0, last + 1, step))]


def check(names=None, anims=None, step=1, thresholds=None, report=None):
    """Scans the characters; returns a list of failures
    (name, anim, region, clearance, t, threshold). `report(name, anim, rows)`
    is called with each scan."""
    th = dict(THRESHOLDS, **(thresholds or {}))
    fails = []
    for name in names or ARMED:
        ch = Character(name)
        for anim in anims or ANIM_NAMES:
            rows = ch.scan(anim, step)
            if report:
                report(ch, anim, rows)
            for r in ch.regions():
                t, v = min(((t, res[r]) for t, res in rows), key=lambda x: x[1])
                if v < th[r]:
                    fails.append((name, anim, r, v, t, th[r]))
    return fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="Regions: " + ", ".join(REGIONS))
    ap.add_argument("chars", nargs="*", help=f"characters (default: {' '.join(ARMED)}; vin's dagger works too)")
    ap.add_argument("--anim", default="", help="comma-separated clips (default: all)")
    ap.add_argument("--step", type=int, default=1, help="check every Nth frame (default 1)")
    ap.add_argument("--frames", action="store_true", help="print every frame, not just each clip's minimum")
    ap.add_argument("--threshold", action="append", default=[], metavar="REGION=M",
                    help="override a failure threshold in metres (repeatable)")
    a = ap.parse_args(argv)
    th = {}
    for kv in a.threshold:
        k, v = kv.split("=", 1)
        if k not in THRESHOLDS:
            ap.error(f"unknown region {k}")
        th[k] = float(v)
    th = dict(THRESHOLDS, **th)
    anims = [x for x in a.anim.split(",") if x] or None
    for x in anims or []:
        if x not in ANIM_NAMES:
            ap.error(f"unknown animation {x}")

    def report(ch, anim, rows):
        regs = ch.regions()
        if a.frames:
            print(f"== {ch.name} {anim}  (clearance in m: " + " / ".join(regs) + ")")
            for t, res in rows:
                flag = " <<" if any(res[r] < th[r] for r in regs) else ""
                print(f"  t={t:4.2f}  " + "  ".join(f"{r} {res[r]:6.3f}" for r in regs) + flag)
        else:
            cells = []
            for r in regs:
                t, v = min(((t, res[r]) for t, res in rows), key=lambda x: x[1])
                cells.append(f"{r} {v:6.3f}@{t:4.2f}{'!' if v < th[r] else ' '}")
            print(f"{ch.name:<11}{anim:<12}" + "  ".join(cells))

    fails = check(a.chars or None, anims, a.step, th, report)
    if fails:
        print(f"\n{len(fails)} clip(s) below threshold:")
        for name, anim, r, v, t, lim in fails:
            print(f"  {name} {anim} {r}: {v:.3f} m at t={t:.2f} (threshold {lim:.3f})")
        return 1
    print("\nall clear")
    return 0


if __name__ == "__main__":
    sys.exit(main())

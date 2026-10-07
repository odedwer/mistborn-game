#!/usr/bin/env python3
"""Clearance checks of the generated characters, frame by frame, in every
animation: how close each armed character's weapon comes to its own body
(the weapon check), and whether any skirted character's legs show through
its robe, gown, tunic or coat (the cloth check, `--cloth`).

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
  legs   thighs, shins and feet, where no skirt covers them in that frame (a
         thigh that swings out past the hem mid-stride counts)
  skirt  robe / tunic / coat skirts (`Body.skirt`)
  shield the character's own shield (the hazekiller's round shield and its boss)

Distances are in metres, surface to surface (negative = interpenetrating).
A region fails when its minimum falls below its threshold.

Cloth check (`--cloth`, every character with a skirt): the leg vertices a
skirt covers in the rest pose (from 8 cm above its hem up) must stay inside
its cloth. Each frame reports the deepest a leg shows through (negative, m);
a clip fails below -1.5 cm (CLOTH_THRESHOLD). A leg that leaves the cloth
past the hem or through a front slit is uncovered there, not clipping.

Usage:
  tools/characters/clearance.py                     # every armed character, every clip: summary
  tools/characters/clearance.py inquisitor --anim=pull --frames   # per-frame table
  tools/characters/clearance.py guard thug --anim=run,sprint --step=2
  tools/characters/clearance.py --threshold=head=0.02 --threshold=skirt=0
  tools/characters/clearance.py --cloth                       # every skirted character
  tools/characters/clearance.py --cloth sazed --anim=crouch_walk --frames
  tools/characters/clearance.py --cloth noble_man:longcoat     # a garment's skirt
  tools/characters/clearance.py --settle                      # robes lying down in `die`
  tools/characters/clearance.py --dead                        # everyone lying on the floor at the end of `die`
Exit status: 0 when every region clears its threshold, 1 otherwise.
"""
from __future__ import annotations

import argparse
import functools
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import chars  # noqa: E402
import chars_npc  # noqa: E402
from body import MAT_NAMES  # noqa: E402
from anim import ANIM_NAMES, FPS, LOOPING, Rig, make_anims  # noqa: E402

BUILDERS = {**chars.BUILDERS, **chars_npc.BUILDERS}
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


def _arm_bones(hand_bone):
    """Arm bones checked against a weapon held by `hand_bone` (its own hand
    and forearm grip the weapon and are left out)."""
    side, free = ("Right", "Left") if hand_bone.startswith("Right") else ("Left", "Right")
    return {free + "UpperArm", free + "LowerArm", free + "Hand", side + "UpperArm"}


def _pose(S, Q, off, loc=None):
    """World rotation (with the skirt bones' scale) and head position of every
    bone (as bake_actions keys them). `loc`: Rig.loc, the skirt bones' shifts."""
    D, Hd = {}, {}
    loc = loc or {}
    for b in S.order:
        par = S.bones[b][0]
        if par is None:
            D[b] = Q[b]
            Hd[b] = S.head(b) + off
        else:
            D[b] = D[par] @ Q[b]
            Hd[b] = Hd[par] + D[par] @ (S.head(b) - S.head(par) + loc.get(b, 0.0))
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


def _caps_dists(P, A, C, R):
    """Surface distance from each of points P (N,3) to the nearest of capsules A-C (K,3), radii R (K,)."""
    AB = C - A
    den = np.maximum(np.einsum("kj,kj->k", AB, AB), 1e-12)
    PA = P[:, None, :] - A[None, :, :]
    u = np.clip(np.einsum("nkj,kj->nk", PA, AB) / den, 0.0, 1.0)
    D = PA - u[:, :, None] * AB[None, :, :]
    return (np.sqrt(np.einsum("nkj,nkj->nk", D, D)) - R).min(axis=1)


def _disc_dist(P, c, n, R, ht):
    """Distances from points P to a solid disc (centre c, normal n, radius R, half thickness ht)."""
    rel = P - c
    h = rel @ n
    radial = np.linalg.norm(rel - h[:, None] * n, axis=1)
    dr = np.maximum(radial - R, 0.0)
    dh = np.maximum(np.abs(h) - ht, 0.0)
    return np.sqrt(dr * dr + dh * dh)


def _skin_matrix(b, m=None):
    """(rest vertices, normalised skin weight matrix, bone names) of b's main
    mesh (or of mesh `m`, a garment)."""
    m = b.m if m is None else m
    V = np.array(m.verts)
    bones = list(b.S.order)
    bi = {n: i for i, n in enumerate(bones)}
    Wm = np.zeros((len(V), len(bones)))
    for i, w in enumerate(m.weights):
        for bn, x in w.items():
            Wm[i, bi[bn]] = x
    Wm /= Wm.sum(axis=1, keepdims=True)
    return V, Wm, bones


def _skin(S, D, Hd, bones, V, Wm):
    """Linear blend skinning of rest points V (N,3) with weights Wm (N,bones)."""
    P = np.zeros_like(V)
    for j, bn in enumerate(bones):
        w = Wm[:, j]
        nz = w > 0
        if nz.any():
            P[nz] += w[nz, None] * (Hd[bn] + (V[nz] - S.head(bn)) @ D[bn].T)
    return P


def _unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


class SkirtSurface:
    """A skirt's posed cloth surface (`Body.skirt_grids`: a grid of rings x
    columns, hem last), sampled at its vertices, quad centres and boundary
    edge midpoints. Each sample has an outward normal, and boundary samples
    (hem, waist and the edges of an open arc) a tangent pointing off the cloth.

    `classify(P)` -> (d, beyond): d is the distance of each point outside the
    cloth along the nearest sample's normal (negative = inside), and `beyond`
    says the point has passed off the edge of the cloth (below the hem, out
    of a front slit): it is uncovered there, not poking through."""

    def __init__(self, grid, closed, yc):
        self.grid, self.closed, self.yc = grid, closed, yc
        self.sign = 1.0

    def _quads(self, G):
        Gn = np.concatenate([G, G[:, :1]], axis=1) if self.closed else G
        a, b, c, d = Gn[:-1, :-1], Gn[:-1, 1:], Gn[1:, 1:], Gn[1:, :-1]
        return Gn, (a + b + c + d) / 4.0, np.cross(c - a, d - b)

    def orient(self, G):
        """Fixes the normal sign from the rest pose: normals point away from
        the skirt's axis (x = 0, y = centre at the hem)."""
        _, qc, qn = self._quads(G)
        out = qc - np.stack([np.zeros_like(qc[..., 0]), np.full_like(qc[..., 0], self.yc), qc[..., 2]], axis=-1)
        self.sign = 1.0 if float((qn * out).sum()) >= 0.0 else -1.0

    def samples(self, G):
        """(points, normals, tangents) for the posed grid G (rows, cols, 3)."""
        R, C = G.shape[:2]
        Gn, qc, qn = self._quads(G)
        qn = _unit(qn * self.sign)
        vn = np.zeros(Gn.shape)
        vn[:-1, :-1] += qn
        vn[:-1, 1:] += qn
        vn[1:, 1:] += qn
        vn[1:, :-1] += qn
        if self.closed:
            vn[:, 0] += vn[:, -1]
            vn = vn[:, :-1]
        vn = _unit(vn)
        vt = np.zeros(G.shape)
        vt[-1] += _unit(G[-1] - G[-2])  # hem: down the cloth
        vt[0] += _unit(G[0] - G[1])  # waist
        if not self.closed:
            vt[:, 0] += _unit(G[:, 0] - G[:, 1])
            vt[:, -1] += _unit(G[:, -1] - G[:, -2])
        vt = _unit(vt) * (np.linalg.norm(vt, axis=-1, keepdims=True) > 0)
        pts, nrm, tan = [G.reshape(-1, 3), qc.reshape(-1, 3)], [vn.reshape(-1, 3), qn.reshape(-1, 3)], \
            [vt.reshape(-1, 3), np.zeros((qc.shape[0] * qc.shape[1], 3))]
        # boundary edge midpoints
        edges = []
        cols = list(range(C)) if self.closed else list(range(C - 1))
        for r in (0, R - 1):
            edges += [((r, j), (r, (j + 1) % C)) for j in cols]
        if not self.closed:
            edges += [((i, c), (i + 1, c)) for c in (0, C - 1) for i in range(R - 1)]
        if edges:
            e0 = np.array([e[0] for e in edges])
            e1 = np.array([e[1] for e in edges])
            pts.append((G[e0[:, 0], e0[:, 1]] + G[e1[:, 0], e1[:, 1]]) / 2.0)
            nrm.append(_unit(vn[e0[:, 0], e0[:, 1]] + vn[e1[:, 0], e1[:, 1]]))
            tan.append(_unit(vt[e0[:, 0], e0[:, 1]] + vt[e1[:, 0], e1[:, 1]]))
        return np.concatenate(pts), np.concatenate(nrm), np.concatenate(tan)

    def classify(self, P, G):
        S, N, T = self.samples(G)
        d2 = (P * P).sum(1)[:, None] - 2.0 * P @ S.T + (S * S).sum(1)[None, :]
        k = d2.argmin(axis=1)
        rel = P - S[k]
        d = (rel * N[k]).sum(1)
        if self.closed:
            # Where the cloth folds over itself (a knee-length fold behind a
            # bent knee), the nearest sample can lie on the far side of the
            # fold. A closed tube's winding number settles it: about 1 inside,
            # about 0 outside, whatever the folds.
            out = np.where(d > 0.0)[0]
            if len(out):
                inside = np.abs(self.winding(P[out], G)) > 0.5
                d[out[inside]] = np.minimum(d[out[inside]], 0.0)
        return d, (rel * T[k]).sum(1) > 0.0

    def winding(self, P, G):
        """Generalised winding number of the cloth tube around points P (the
        signed solid angle of its triangles over 4 pi; the open waist and hem
        let it fall short of 1 inside)."""
        Gn = np.concatenate([G, G[:, :1]], axis=1)
        a, b, c, d = Gn[:-1, :-1], Gn[:-1, 1:], Gn[1:, 1:], Gn[1:, :-1]
        T = np.concatenate([np.stack([a, b, c], -2).reshape(-1, 3, 3), np.stack([a, c, d], -2).reshape(-1, 3, 3)])
        R = T[None, :, :, :] - P[:, None, None, :]
        L = np.linalg.norm(R, axis=-1)
        A, B, C = R[:, :, 0], R[:, :, 1], R[:, :, 2]
        la, lb, lc = L[:, :, 0], L[:, :, 1], L[:, :, 2]
        num = np.einsum("ntj,ntj->nt", A, np.cross(B, C))
        den = (la * lb * lc + np.einsum("ntj,ntj->nt", A, B) * lc + np.einsum("ntj,ntj->nt", A, C) * lb
               + np.einsum("ntj,ntj->nt", B, C) * la)
        return (2.0 * np.arctan2(num, den)).sum(axis=1) / (4.0 * np.pi)


def _skirt_surfaces(b):
    return [SkirtSurface(g, closed, yc) for (g, closed), (_, yc, _) in zip(b.skirt_grids, b.skirts)]


def _coverage(surfs, Pg, P):
    """(depth, beyond), each (points, skirts): how deep each point of P lies
    inside each skirt's cloth (m, negative = outside it), and whether it has
    left that cloth past its hem or edge. `Pg` holds the posed skirt grids."""
    depth = np.zeros((len(P), len(surfs)))
    beyond = np.zeros((len(P), len(surfs)), dtype=bool)
    for k, (sf, G) in enumerate(zip(surfs, Pg)):
        d, beyond[:, k] = sf.classify(P, G)
        depth[:, k] = -d
    return depth, beyond


def covered(surfs, Pg, P):
    """True for the points of P inside some skirt's cloth (posed grids Pg)."""
    depth, beyond = _coverage(surfs, Pg, P)
    return ((depth >= 0.0) & ~beyond).any(axis=1)


LEG_BONES = {bn for bn, r in BONE_REGION.items() if r == "legs"}
CLOTH_THRESHOLD = -0.015  # (m) see Cloth
# Feet step out from under a long robe's hem as they would under real cloth:
# only leg vertices at least this far above the hem in the rest pose (m, for
# a 1.75 m character) must stay inside the cloth.
CLOTH_HEM_MARGIN = 0.08


class Cloth:
    """Cloth-against-legs check: a character's skirts (robe, gown, tunic,
    coat tails, tabard) against its own legs, posed frame by frame. A name
    "<character>:<garment>" checks the skirts of that optional garment mesh
    (noble_man:tails, noble_woman:bustle) instead of the main mesh's.

    A leg vertex (thigh, knee, shin, foot) that the cloth covers in the rest
    pose must stay inside it: its clearance is how far inside the cloth it
    lies (negative = showing through). A leg that leaves the cloth past its
    hem or through a front slit is uncovered there, not clipping, and doesn't
    count."""

    def __init__(self, name):
        self.name = name
        base, _, garment = name.partition(":")
        b, info = BUILDERS[base]()
        self.b, self.S, self.style = b, b.S, info["style"]
        if garment:
            gs = b.garment_skirts.get(garment, [])
            infos, grids = [e[0] for e in gs], [e[1] for e in gs]
        else:
            infos, grids = b.skirts, b.skirt_grids
        if not grids:
            raise ValueError(f"{name} has no skirt")
        V, Wm, bones = _skin_matrix(b)
        # the cloth's own vertices (the garment mesh's, or the main mesh's)
        Vc, Wc, _ = _skin_matrix(b, b.garments[garment]) if garment else (V, Wm, bones)
        tag = np.zeros(len(V), dtype=bool)
        for ranges in b.parts.values():
            for s0, s1 in ranges:
                tag[s0:s1] = True
        dom = Wm.argmax(axis=1)
        legs = np.array([i for i in range(len(V)) if bones[dom[i]] in LEG_BONES and not tag[i]], dtype=int)
        self.surfs = [SkirtSurface(g, closed, yc) for (g, closed), (_, yc, _) in zip(grids, infos)]
        for sf in self.surfs:
            sf.orient(Vc[sf.grid])
        depth, beyond = _coverage(self.surfs, [Vc[sf.grid] for sf in self.surfs], V[legs])
        margin = CLOTH_HEM_MARGIN * b.H / 1.75
        hems = np.array([z for z, _, _ in infos])
        # (legs, skirts): covered in the rest pose, well above that skirt's hem
        self.cover = (depth >= 0.0) & ~beyond & (V[legs][:, 2:3] > hems[None, :] + margin)
        keep = self.cover.any(axis=1)
        self.legs, self.cover = legs[keep], self.cover[keep]
        self.grid_idx = [sf.grid for sf in self.surfs]
        self.Wl, self.Vl = Wm[self.legs], V[self.legs]
        self.Wg = [Wc[g.reshape(-1)] for g in self.grid_idx]
        self.Vg = [Vc[g.reshape(-1)] for g in self.grid_idx]
        self.bones = bones
        self.anims = make_anims(self.style, self.S)
        self.rig = Rig(self.S)

    def measure(self, params, detail=False):
        """Minimum depth (m) of the rest-covered leg vertices inside the cloth
        (negative = a leg shows through); with `detail`, also the per-vertex
        depths and posed leg positions."""
        Q, off = self.rig.solve(params)
        D, Hd = _pose(self.S, Q, off, self.rig.loc)
        P = _skin(self.S, D, Hd, self.bones, self.Vl, self.Wl)
        Pg = [_skin(self.S, D, Hd, self.bones, V, W).reshape(g.shape + (3,))
              for V, W, g in zip(self.Vg, self.Wg, self.grid_idx)]
        depth, beyond = _coverage(self.surfs, Pg, P)
        # a point that left a skirt past its hem or edge is uncovered, not poking through
        depth = np.where(self.cover, np.where(beyond, np.inf, depth), -np.inf).max(axis=1)
        v = float(depth.min()) if len(depth) else 9.0
        return (v, depth, P) if detail else v

    def scan(self, anim, step=1):
        n = self.anims[anim][0]
        last = n - 1 if anim in LOOPING else n
        return [(f / FPS, self.measure(self.anims[anim][1](f / FPS))) for f in range(0, last + 1, step)]


@functools.lru_cache(maxsize=None)
def _built(name):
    """BUILDERS[name]() built once, for read-only use (the listings below)."""
    return BUILDERS[name]()


def skirted():
    """Every character whose main mesh has a skirt."""
    return [n for n in BUILDERS if _built(n)[0].skirt_grids]


def garment_skirted():
    """Every optional garment with a skirt, as "<character>:<garment>"."""
    return [f"{n}:{g}" for n in BUILDERS for g in _built(n)[0].garment_skirts]


def check_cloth(names=None, anims=None, step=1, threshold=CLOTH_THRESHOLD, report=None):
    """Scans the skirted characters; returns failures (name, anim, depth, t)."""
    fails = []
    for name in names or skirted() + garment_skirted():
        ch = Cloth(name)
        for anim in anims or ANIM_NAMES:
            rows = ch.scan(anim, step)
            if report:
                report(ch, anim, rows)
            t, v = min(rows, key=lambda x: x[1])
            if v < threshold:
                fails.append((name, anim, v, t))
    return fails


class Character:
    """One character's mesh, regions and weapon proxies, ready to pose."""

    def __init__(self, name):
        self.name = name
        b, info = BUILDERS[name]()
        self.b, self.S, self.style = b, b.S, info["style"]
        if not b.weapon_caps:
            raise ValueError(f"{name} carries no weapon with clearance capsules")
        m = b.m
        V, Wm, bones = _skin_matrix(b)
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
            return BONE_REGION.get(dom[i])

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
        # the skirts' own grids are skinned too: a leg counts as covered in
        # the frames where it is inside its skirt (see SkirtSurface)
        self.surfs = _skirt_surfaces(b)
        for sf in self.surfs:
            sf.orient(V[sf.grid])
        grid_v = {int(i) for sf in self.surfs for i in sf.grid.reshape(-1)}
        used = sorted({i for r in samples for s in samples[r] for i in s} | grid_v)
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
        self.grids = [np.vectorize(pos.get)(sf.grid) for sf in self.surfs]
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
        D, Hd = _pose(S, Q, off, self.rig.loc)
        P = _skin(S, D, Hd, self.bones, self.V, self.Wm)

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
            if r == "legs" and self.surfs:
                out[r] = self._uncovered_dist(pts, [P[g] for g in self.grids], A, C, R)
            else:
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

    def _uncovered_dist(self, pts, grids, A, C, R, chunk=48):
        """Closest weapon distance over the leg points no skirt covers in
        this pose: a thigh that swings out past the hem mid-stride counts.
        Points are tried nearest first, a chunk at a time."""
        dist = _caps_dists(pts, A, C, R)
        order = np.argsort(dist)
        for k in range(0, len(order), chunk):
            idx = order[k:k + chunk]
            cov = covered(self.surfs, grids, pts[idx])
            if not cov.all():
                return float(dist[idx[~cov][0]])
        return 9.0

    def scan(self, anim, step=1):
        """[(t, {region: clearance})] for every `step`-th frame of `anim`."""
        n = self.anims[anim][0]
        last = n - 1 if anim in LOOPING else n  # a loop's last frame repeats frame 0
        return [(f / FPS, self.frame(anim, f / FPS)) for f in list(range(0, last + 1, step))]


# Death settle (`--settle`): once a long robe or gown lies down (from
# SETTLE_FROM s into `die`), its hem may rise at most SETTLE_HEM (m, for a
# 1.75 m character) off the floor, and no cloth may sink more than
# SETTLE_FLOOR under it (a little is hidden by the floor).
SETTLE_FROM = 0.95
SETTLE_HEM = 0.32
SETTLE_FLOOR = -0.03


def settling():
    """Every character whose skirt has skirt bones (Body.settle_bones)."""
    return [n for n in BUILDERS if "SkirtHips" in _built(n)[0].S.bones]


def settle_scan(name, step=1, settle=None):
    """[(t, hem height, lowest cloth z)] of `name`'s main-mesh skirts in the
    lying part of `die`. `settle` overrides anim.SETTLE[style] (a test)."""
    import anim
    b, info = _built(name)
    style = info["style"]
    saved = anim.SETTLE.get(style)
    if settle is not None:
        anim.SETTLE[style] = settle
    try:
        A = make_anims(style, b.S)
    finally:
        if settle is not None:
            anim.SETTLE[style] = saved
    V, Wm, bones = _skin_matrix(b)
    grids = [g for g, _ in b.skirt_grids]
    idx = np.unique(np.concatenate([g.reshape(-1) for g in grids]))
    hem = np.isin(idx, np.concatenate([g[-1] for g in grids]))
    rig = Rig(b.S)
    n = A["die"][0]
    rows = []
    for f in range(int(round(SETTLE_FROM * FPS)), n + 1, step):
        Q, off = rig.solve(A["die"][1](f / FPS))
        D, Hd = _pose(b.S, Q, off, rig.loc)
        z = _skin(b.S, D, Hd, bones, V[idx], Wm[idx])[:, 2]
        rows.append((f / FPS, float(z[hem].max()), float(z.min())))
    return rows


def check_settle(names=None, step=1, report=None):
    """Returns failures (name, what, value, t, limit)."""
    fails = []
    for name in names or settling():
        rows = settle_scan(name, step)
        if report:
            report(name, rows)
        k = _built(name)[0].H / 1.75
        t, h, _ = max(rows, key=lambda r: r[1])
        if h > SETTLE_HEM * k:
            fails.append((name, "hem", h, t, SETTLE_HEM * k))
        t, _, z = min(rows, key=lambda r: r[2])
        if z < SETTLE_FLOOR:
            fails.append((name, "floor", z, t, SETTLE_FLOOR))
    return fails


# Lying dead (`--dead`, every character): from DEAD_FROM s into `die`, no part
# of the body may sink more than DEAD_FLOOR under the floor (m; the skin gives
# a little), and in the final pose the lowest point of each thigh, shin and
# foot must rest within DEAD_LIFT of it (m, for a 1.75 m character), so the
# legs lie on the floor rather than above it (except under a long robe, whose
# lying cloth --settle checks). The body is the main mesh minus
# the parts in DEAD_SOFT: props (`weapon`, `shield`, and `prop`, Ham's slung
# staff), skirts (the long robes' cloth is checked by --settle) and tied hair
# tails, and minus the mistcloak (its spring-simulated tassels, and its back
# panel, which the body would squash flat).
DEAD_FROM = 0.95
DEAD_SOFT = ("weapon", "shield", "skirt", "hair", "prop")  # Body.parts left out
DEAD_FLOOR = -0.01
DEAD_LIFT = 0.05
DEAD_SEGMENTS = {f"{s} {part}": [side + b for b in bones] for s, side in (("left", "Left"), ("right", "Right"))
                 for part, bones in (("thigh", ["UpperLeg"]), ("shin", ["LowerLeg"]), ("foot", ["Foot", "Toes"]))}


def dead_scan(name, step=1, params=None):
    """[(t, lowest body z, where, {leg segment: lowest z})] of `name` in the
    lying part of `die`. `params` overrides pose parameters in every frame (a
    test)."""
    b, info = _built(name)
    A = make_anims(info["style"], b.S)
    V, Wm, bones = _skin_matrix(b)
    keep = np.ones(len(V), dtype=bool)
    for part in DEAD_SOFT:
        for s0, s1 in b.parts.get(part, []):
            keep[s0:s1] = False
    dom = np.array([bones[j] for j in Wm.argmax(axis=1)])
    keep &= ~np.char.startswith(dom.astype(str), "Tassel")
    # (the mistcloak, tassels and back panel, is cloth that the body squashes flat)
    cloak = MAT_NAMES.index("Cloak")
    solid = np.zeros(len(V), dtype=bool)
    for face, mat in zip(b.m.faces, b.m.face_mat):
        if mat != cloak:
            solid[list(face)] = True
    keep &= solid
    V, Wm, dom = V[keep], Wm[keep], dom[keep]
    segs = {k: np.isin(dom, bs) for k, bs in DEAD_SEGMENTS.items()}
    rig = Rig(b.S)
    n = A["die"][0]
    rows = []
    frames = list(range(int(round(DEAD_FROM * FPS)), n + 1, step))
    if frames[-1] != n:  # (the final pose is always measured)
        frames.append(n)
    for f in frames:
        p = A["die"][1](f / FPS)
        p.update(params or {})
        Q, off = rig.solve(p)
        D, Hd = _pose(b.S, Q, off, rig.loc)
        z = _skin(b.S, D, Hd, bones, V, Wm)[:, 2]
        i = int(np.argmin(z))
        rows.append((f / FPS, float(z[i]), str(dom[i]), {k: float(z[m].min()) for k, m in segs.items()}))
    return rows


def check_dead(names=None, step=1, report=None):
    """Returns failures (name, what, value, t, limit)."""
    fails = []
    for name in names or list(BUILDERS):
        rows = dead_scan(name, step)
        if report:
            report(name, rows)
        t, z, where, _ = min(rows, key=lambda r: r[1])
        if z < DEAD_FLOOR:
            fails.append((name, f"floor ({where})", z, t, DEAD_FLOOR))
        b = _built(name)[0]
        if "SkirtHips" in b.S.bones:
            continue  # (the long robes lie over the legs: see --settle)
        lift = DEAD_LIFT * b.H / 1.75
        t, _, _, legs = rows[-1]
        for seg, z in legs.items():
            if z > lift:
                fails.append((name, seg, z, t, lift))
    return fails


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
    ap.add_argument("--cloth", action="store_true",
                    help="cloth check instead: legs against skirts (default: every skirted character)")
    ap.add_argument("--settle", action="store_true",
                    help="death settle check instead: long robes and gowns lying down")
    ap.add_argument("--dead", action="store_true",
                    help="lying dead check instead: the body on the floor at the end of `die` (default: everyone)")
    a = ap.parse_args(argv)
    if a.dead:
        return _main_dead(a)
    if a.settle:
        return _main_settle(a)
    if a.cloth:
        return _main_cloth(a, ap)
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


def _main_cloth(a, ap):
    lim = CLOTH_THRESHOLD
    for kv in a.threshold:
        k, v = kv.split("=", 1)
        if k != "cloth":
            ap.error("with --cloth, only --threshold=cloth=M")
        lim = float(v)
    anims = [x for x in a.anim.split(",") if x] or None
    for x in anims or []:
        if x not in ANIM_NAMES:
            ap.error(f"unknown animation {x}")

    def report(ch, anim, rows):
        if a.frames:
            print(f"== {ch.name} {anim}  (depth of the legs inside the cloth, m)")
            for t, v in rows:
                print(f"  t={t:4.2f}  cloth {v:6.3f}" + (" <<" if v < lim else ""))
        else:
            t, v = min(rows, key=lambda x: x[1])
            print(f"{ch.name:<19}{anim:<12}cloth {v:6.3f}@{t:4.2f}{'!' if v < lim else ''}")

    fails = check_cloth(a.chars or None, anims, a.step, lim, report)
    if fails:
        print(f"\n{len(fails)} clip(s) where a leg shows through the cloth:")
        for name, anim, v, t in fails:
            print(f"  {name} {anim}: {v:.3f} m at t={t:.2f} (threshold {lim:.3f})")
        return 1
    print("\nall covered")
    return 0


def _main_settle(a):
    def report(name, rows):
        if a.frames:
            print(f"== {name} die (hem height / lowest cloth, m)")
            for t, h, z in rows:
                print(f"  t={t:4.2f}  hem {h:6.3f}  floor {z:+6.3f}")
        else:
            th, h, _ = max(rows, key=lambda r: r[1])
            tz, _, z = min(rows, key=lambda r: r[2])
            print(f"{name:<12}hem {h:6.3f}@{th:4.2f}  floor {z:+6.3f}@{tz:4.2f}")

    fails = check_settle(a.chars or None, a.step, report)
    if fails:
        print(f"\n{len(fails)} failure(s):")
        for name, what, v, t, lim in fails:
            print(f"  {name} {what}: {v:.3f} m at t={t:.2f} (limit {lim:.3f})")
        return 1
    print("\nall settled")
    return 0


def _main_dead(a):
    def report(name, rows):
        if a.frames:
            print(f"== {name} die (lowest body point / each leg segment's lowest, m)")
            for t, z, where, legs in rows:
                print(f"  t={t:4.2f}  low {z:+6.3f} ({where})  " + "  ".join(f"{k} {v:+.3f}" for k, v in legs.items()))
        else:
            t, z, where, _ = min(rows, key=lambda r: r[1])
            legs = rows[-1][3]
            print(f"{name:<12}low {z:+6.3f}@{t:4.2f} {where:<14}legs {min(legs.values()):+.3f}..{max(legs.values()):+.3f}")

    fails = check_dead(a.chars or None, a.step, report)
    if fails:
        print(f"\n{len(fails)} failure(s):")
        for name, what, v, t, lim in fails:
            print(f"  {name} {what}: {v:+.3f} m at t={t:.2f} (limit {lim:+.3f})")
        return 1
    print("\nall lying on the floor")
    return 0


if __name__ == "__main__":
    sys.exit(main())

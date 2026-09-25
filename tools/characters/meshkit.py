"""Procedural mesh construction kit (pure numpy, Blender-independent).

Coordinates are Blender's: +Z up, character faces +Y, character's right is +X.
Every part is built directly in the rest (A-)pose and carries per-vertex bone
weights, per-corner UVs/colours and a per-face material slot.
"""
from __future__ import annotations

import math
from typing import Callable, Iterable, Sequence

import numpy as np

Vec = np.ndarray


def v3(x, y=None, z=None) -> Vec:
    if y is None:
        return np.asarray(x, dtype=float)
    return np.array([x, y, z], dtype=float)


def norm(v: Vec) -> Vec:
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def hexcol(h: str, a: float = 1.0):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0, a)


def rot_axis(axis, deg) -> np.ndarray:
    a = norm(v3(axis))
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    x, y, z = a
    C = 1 - c
    return np.array([
        [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, c + z * z * C],
    ])


def frame_from(fwd, up) -> np.ndarray:
    """Columns: x = right, y = fwd, z = up (orthonormalised)."""
    f = norm(v3(fwd))
    u = norm(v3(up) - f * np.dot(v3(up), f))
    r = np.cross(f, u)
    return np.column_stack([r, f, u])


class Skel:
    """Minimal skeleton description used for weights and prop placement."""

    def __init__(self):
        self.bones: dict[str, tuple[str | None, Vec, Vec]] = {}
        self.order: list[str] = []

    def add(self, name, parent, head, tail):
        self.bones[name] = (parent, v3(head), v3(tail))
        self.order.append(name)

    def head(self, b):
        return self.bones[b][1]

    def tail(self, b):
        return self.bones[b][2]

    def dir(self, b):
        return norm(self.tail(b) - self.head(b))

    def length(self, b):
        return float(np.linalg.norm(self.tail(b) - self.head(b)))


class Mesh:
    def __init__(self):
        self.verts: list[Vec] = []
        self.weights: list[dict[str, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_uv: list[list[tuple[float, float]]] = []
        self.face_col: list[list[tuple[float, float, float, float]]] = []
        self.face_mat: list[int] = []
        self.face_smooth: list[bool] = []

    # ------------------------------------------------------------------ basics
    def add_vert(self, p, w) -> int:
        self.verts.append(v3(p))
        self.weights.append(dict(w))
        return len(self.verts) - 1

    def add_face(self, idx, uvs, cols, mat, smooth=True):
        self.faces.append(tuple(idx))
        self.face_uv.append(list(uvs))
        self.face_col.append(list(cols))
        self.face_mat.append(mat)
        self.face_smooth.append(smooth)

    def tri_count(self) -> int:
        return sum(len(f) - 2 for f in self.faces)

    def merge(self, other: "Mesh"):
        off = len(self.verts)
        self.verts += other.verts
        self.weights += other.weights
        for i, f in enumerate(other.faces):
            self.add_face([j + off for j in f], other.face_uv[i], other.face_col[i],
                          other.face_mat[i], other.face_smooth[i])

    def bounds(self):
        a = np.array(self.verts)
        return a.min(axis=0), a.max(axis=0)


# ---------------------------------------------------------------------- weights
def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0)
    return float(np.linalg.norm(p - (a + ab * t)))


def proximity_weights(skel: Skel, p, bones: Sequence[str], power=5.0,
                      bias: dict[str, float] | None = None, maxinf=3) -> dict[str, float]:
    ws = {}
    for b in bones:
        d = seg_dist(p, skel.head(b), skel.tail(b))
        k = (bias or {}).get(b, 1.0)
        ws[b] = k / (d + 0.01) ** power
    return clean_weights(ws, maxinf)


def clean_weights(ws: dict[str, float], maxinf=4, thresh=0.03) -> dict[str, float]:
    items = sorted(ws.items(), key=lambda kv: -kv[1])[:maxinf]
    tot = sum(w for _, w in items)
    items = [(b, w / tot) for b, w in items if w / tot >= thresh]
    tot = sum(w for _, w in items)
    return {b: w / tot for b, w in items}


# ------------------------------------------------------------------------ tubes
Ring = tuple  # (center, radii(ru+, ru-, rv+, rv-))


def _radii(r):
    if np.isscalar(r):
        return (r, r, r, r)
    if len(r) == 2:
        return (r[0], r[0], r[1], r[1])
    if len(r) == 3:
        return (r[0], r[0], r[1], r[2])
    return tuple(r)


def tube(m: Mesh, centers, radii, *, n=12, hint=(0, 1, 0), ex=2.0, mat=0,
         color=(0.5, 0.5, 0.5, 1.0), weights=None, cap0=None, cap1=None,
         shape: Callable | None = None, arc: tuple[float, float] | None = None,
         frames: list | None = None, smooth=True, flip=False, uv_scale=1.0):
    """Loft rings along a polyline.

    radii[i] = r | (ru, rv) | (ru+, ru-, rv+, rv-) in the ring frame where
    v = `hint` projected perpendicular to the path and u = v x t.
    color(p, i, theta) or constant.  weights(p, i, theta) -> dict  or dict.
    shape(i, theta) -> radius multiplier.  arc=(a0, a1) degrees builds an open
    (partial) tube.  cap0/cap1: None | 'flat' | float (dome length)."""
    C = [v3(c) for c in centers]
    R = [_radii(r) for r in radii]
    nr = len(C)
    closed = arc is None
    a0, a1 = (0.0, 360.0) if closed else arc
    ncols = n if closed else n + 1
    rings = []
    tangents = []
    for i in range(nr):
        if i == 0:
            t = C[1] - C[0]
        elif i == nr - 1:
            t = C[-1] - C[-2]
        else:
            t = C[i + 1] - C[i - 1]
        tangents.append(norm(t))
    for i in range(nr):
        t = tangents[i]
        if frames is not None:
            u, vv = frames[i]
        else:
            h = v3(hint)
            vv = norm(h - t * np.dot(h, t))
            u = np.cross(vv, t)
        ru_p, ru_n, rv_p, rv_n = R[i]
        ring = []
        for j in range(ncols):
            th = math.radians(a0 + (a1 - a0) * j / (n if closed else n))
            cu, sv = math.cos(th), math.sin(th)
            e = 2.0 / ex
            x = math.copysign(abs(cu) ** e, cu) * (ru_p if cu >= 0 else ru_n)
            y = math.copysign(abs(sv) ** e, sv) * (rv_p if sv >= 0 else rv_n)
            k = shape(i, math.degrees(th)) if shape else 1.0
            p = C[i] + (u * x + vv * y) * k
            w = weights(p, i, math.degrees(th)) if callable(weights) else weights
            col = color(p, i, math.degrees(th)) if callable(color) else color
            idx = m.add_vert(p, w)
            ring.append((idx, col, th))
        rings.append(ring)
    # arc-length for v coordinate
    vcoord = [0.0]
    for i in range(1, nr):
        vcoord.append(vcoord[-1] + float(np.linalg.norm(C[i] - C[i - 1])))
    circ = 2 * math.pi * max(np.mean(R[0]), 0.01)

    def uv(i, j):
        return ((j / n) * circ * uv_scale, vcoord[i] * uv_scale)

    # orientation test on first quad
    def quad(i, j):
        j2 = (j + 1) % ncols if closed else j + 1
        return [rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]], j2

    q, _ = quad(0, 0)
    P = [m.verts[a[0]] for a in q]
    nrm = np.cross(P[1] - P[0], P[3] - P[0])
    out = (P[0] + P[1] + P[2] + P[3]) / 4 - (C[0] + C[1]) / 2
    reverse = np.dot(nrm, out) < 0
    if flip:
        reverse = not reverse
    jmax = n if closed else n
    for i in range(nr - 1):
        for j in range(jmax):
            q, j2 = quad(i, j)
            uvs = [uv(i, j), uv(i, j + 1), uv(i + 1, j + 1), uv(i + 1, j)]
            idx = [a[0] for a in q]
            cols = [a[1] for a in q]
            if reverse:
                idx, uvs, cols = idx[::-1], uvs[::-1], cols[::-1]
            m.add_face(idx, uvs, cols, mat, smooth)
    # caps
    for end, cap in ((0, cap0), (nr - 1, cap1)):
        if cap is None or not closed:
            continue
        t = tangents[end] * (-1 if end == 0 else 1)
        length = 0.0 if cap == "flat" else float(cap)
        cp = C[end] + t * length
        ring = rings[end]
        w = weights(cp, end, 0.0) if callable(weights) else weights
        col = ring[0][1]
        ci = m.add_vert(cp, w)
        for j in range(n):
            a, b = ring[j], ring[(j + 1) % n]
            idx = [a[0], b[0], ci]
            P = [m.verts[k] for k in idx]
            nn = np.cross(P[1] - P[0], P[2] - P[0])
            if np.dot(nn, t) < 0:
                idx = idx[::-1]
            if flip:
                idx = idx[::-1]
            m.add_face(idx, [(0, 0), (0.1, 0), (0.05, 0.1)], [a[1], b[1], col], mat, smooth)
    return rings


def ribbon(m: Mesh, left_pts, right_pts, *, mat=0, color=(0.5, 0.5, 0.5, 1),
           weights=None, normal_hint=None, smooth=True):
    """Single-sided strip (use a double-sided material)."""
    n = len(left_pts)
    L = [v3(p) for p in left_pts]
    Rr = [v3(p) for p in right_pts]
    il, ir = [], []
    for i in range(n):
        for pts, out in ((L, il), (Rr, ir)):
            p = pts[i]
            w = weights(p, i) if callable(weights) else weights
            out.append(m.add_vert(p, w))
    vlen = [0.0]
    for i in range(1, n):
        vlen.append(vlen[-1] + float(np.linalg.norm(L[i] - L[i - 1])))
    width = float(np.linalg.norm(L[0] - Rr[0]))
    for i in range(n - 1):
        idx = [il[i], ir[i], ir[i + 1], il[i + 1]]
        uvs = [(0, vlen[i]), (width, vlen[i]), (width, vlen[i + 1]), (0, vlen[i + 1])]
        if normal_hint is not None:
            P = [m.verts[k] for k in idx]
            nn = np.cross(P[1] - P[0], P[3] - P[0])
            if np.dot(nn, v3(normal_hint)) < 0:
                idx, uvs = idx[::-1], uvs[::-1]
        c = color(i) if callable(color) else color
        m.add_face(idx, uvs, [c] * 4, mat, smooth)


def box(m: Mesh, center, size, *, frame=None, mat=0, color=(0.5, 0.5, 0.5, 1), weights=None,
        taper=1.0):
    """Axis box in `frame` (3x3 columns r,f,u).  taper scales the +z face."""
    Fm = np.eye(3) if frame is None else frame
    c = v3(center)
    sx, sy, sz = (s / 2 for s in size)
    corners = []
    for z in (-1, 1):
        k = taper if z > 0 else 1.0
        for y in (-1, 1):
            for x in (-1, 1):
                corners.append(c + Fm @ v3(x * sx * k, y * sy * k, z * sz))
    ids = [m.add_vert(p, weights(p) if callable(weights) else weights) for p in corners]
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    for f in faces:
        idx = [ids[i] for i in f]
        P = [m.verts[k] for k in idx]
        nn = np.cross(P[1] - P[0], P[3] - P[0])
        if np.dot(nn, sum(P) / 4 - c) < 0:
            idx = idx[::-1]
        m.add_face(idx, [(0, 0), (1, 0), (1, 1), (0, 1)], [color] * 4, mat, False)


def local_tube(m: Mesh, M: np.ndarray, o: Vec, pts, radii, **kw):
    """Tube whose centres are given in a local frame (M 3x3, origin o)."""
    centers = [o + M @ v3(p) for p in pts]
    hint = kw.pop("hint", (1, 0, 0))
    kw["hint"] = M @ v3(hint)
    return tube(m, centers, radii, **kw)

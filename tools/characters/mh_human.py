"""Realistic human bodies from the MakeHuman hm08 base mesh (numpy only).

Loads the data fetched by fetch_mh.py, morphs the base mesh with MakeHuman's
macro targets (gender, age, muscle, weight, height, proportions) plus any
detail targets, fits proxies (eyes, eyebrows, eyelashes, hair) to the result,
and maps it onto this project's humanoid skeleton (body.HUMANOID_BONES):
joint positions come from MakeHuman's joint helpers, skin weights from its
default skeleton with each MakeHuman bone folded into one humanoid bone.

Axes: MakeHuman is Y up, facing +Z, decimetres. The character build is Z up,
facing +Y, right hand at +X, metres: (x, y, z) -> (-x, z, y) / 10.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, ".mh-data")


def to_blender(p: np.ndarray) -> np.ndarray:
    p = np.asarray(p, dtype=np.float64)
    return np.stack([-p[..., 0], p[..., 2], p[..., 1]], axis=-1) * 0.1


# ---------------------------------------------------------------- three.js JSON
def _decode_faces(f: list, n_uv_layers: int = 1):
    """three.js JSON v3 faces -> (vertex index tuples, material ids, uv index tuples)."""
    faces, mats, uvs = [], [], []
    i, n = 0, len(f)
    while i < n:
        t = f[i]
        i += 1
        quad = t & 1
        nv = 4 if quad else 3
        vi = f[i:i + nv]
        i += nv
        m = 0
        if t & 2:
            m = f[i]
            i += 1
        if t & 4:
            i += n_uv_layers
        uv = None
        if t & 8:
            uv = f[i:i + nv]
            i += nv * n_uv_layers
        if t & 16:
            i += 1
        if t & 32:
            i += nv
        if t & 64:
            i += 1
        if t & 128:
            i += nv
        faces.append(tuple(vi))
        mats.append(m)
        uvs.append(tuple(uv) if uv is not None else None)
    return faces, mats, uvs


@dataclass
class MHMesh:
    coords: np.ndarray            # (n, 3) MakeHuman space
    faces: list
    face_uv: list                 # per face, per corner (u, v)
    face_mat: list
    weights: list = field(default_factory=list)  # per vertex {mh bone: w}
    mat_names: list = field(default_factory=list)
    texture: str | None = None


def _load_three(path: str) -> tuple[dict, MHMesh]:
    with open(path) as fp:
        d = json.load(fp)
    v = np.array(d["vertices"], dtype=np.float64).reshape(-1, 3)
    faces, mats, uvi = _decode_faces(d["faces"])
    uv = np.array(d["uvs"][0], dtype=np.float64).reshape(-1, 2) if d.get("uvs") and d["uvs"][0] else None
    face_uv = [[tuple(uv[j]) for j in u] if (u is not None and uv is not None) else [(0.0, 0.0)] * len(f)
               for f, u in zip(faces, uvi)]
    names = [m.get("DbgName", "") for m in d.get("materials", [])]
    m = MHMesh(v, faces, face_uv, mats, mat_names=names)
    tex = [mm.get("mapDiffuse") for mm in d.get("materials", []) if mm.get("mapDiffuse")]
    m.texture = tex[0] if tex else None
    bones = [b["name"] for b in d.get("bones", [])]
    if bones and d.get("skinIndices"):
        k = d.get("influencesPerVertex", 4)
        si = np.array(d["skinIndices"]).reshape(-1, k)
        sw = np.array(d["skinWeights"], dtype=np.float64).reshape(-1, k)
        for row_i, row_w in zip(si, sw):
            w = {}
            for b, x in zip(row_i, row_w):
                if x > 0:
                    nm = bones[int(b)].split("____")[0]
                    w[nm] = w.get(nm, 0.0) + float(x)
            m.weights.append(w)
    return d, m


# --------------------------------------------------------------------- targets
_TARGETS = None


def _targets():
    global _TARGETS
    if _TARGETS is None:
        _TARGETS = np.load(os.path.join(DATA, "targets.npz"))
    return _TARGETS


def target_delta(name: str, n: int) -> np.ndarray:
    """The displacement of target `name` (e.g. 'macrodetails/caucasian-male-young')."""
    t = _targets()
    d = np.zeros((n, 3))
    d[t[f"targets/{name}.index"]] = t[f"targets/{name}.vector"].astype(np.float64) * 1e-3
    return d


def _tri(x: float) -> dict[str, float]:
    """MakeHuman min/average/max blend of a 0..1 slider."""
    if x < 0.5:
        return {"min": 1.0 - 2.0 * x, "average": 2.0 * x}
    return {"average": 2.0 - 2.0 * x, "max": 2.0 * x - 1.0}


def _age(a: float) -> dict[str, float]:
    """0 -> 1 year, 0.1875 -> 11, 0.5 -> 25, 1 -> 90 (MakeHuman's age slider)."""
    if a < 0.1875:
        return {"baby": 1 - a / 0.1875, "child": a / 0.1875}
    if a < 0.5:
        t = (a - 0.1875) / (0.5 - 0.1875)
        return {"child": 1 - t, "young": t}
    t = (a - 0.5) / 0.5
    return {"young": 1 - t, "old": t}


def macro_weights(gender=1.0, age=0.5, muscle=0.5, weight=0.5, height=0.5, proportions=0.5,
                  african=0.0, asian=0.0, caucasian=1.0) -> dict[str, float]:
    G = {"female": 1.0 - gender, "male": gender}
    A = _age(age)
    M = {k + "muscle": v for k, v in _tri(muscle).items()}
    W = {k + "weight": v for k, v in _tri(weight).items()}
    out: dict[str, float] = {}

    def add(k, w):
        if abs(w) > 1e-6:
            out[k] = out.get(k, 0.0) + w

    race = {"african": african, "asian": asian, "caucasian": caucasian}
    tot = sum(race.values()) or 1.0
    for g, gw in G.items():
        for a, aw in A.items():
            for r, rw in race.items():
                add(f"macrodetails/{r}-{g}-{a}", gw * aw * rw / tot)
            for m, mw in M.items():
                for w, ww in W.items():
                    base = gw * aw * mw * ww
                    add(f"macrodetails/universal-{g}-{a}-{m}-{w}", base)
                    if height != 0.5:
                        hk = "maxheight" if height > 0.5 else "minheight"
                        add(f"macrodetails/height/{g}-{a}-{m}-{w}-{hk}", base * abs(height - 0.5) * 2)
                    if proportions != 0.5:
                        pk = "idealproportions" if proportions > 0.5 else "uncommonproportions"
                        add(f"macrodetails/proportions/{g}-{a}-{m}-{w}-{pk}", base * abs(proportions - 0.5) * 2)
    return out


# ------------------------------------------------------------------- the human
# MakeHuman default-skeleton bone (prefix) -> humanoid bone. Sides: MakeHuman
# ".L"/".R" are the character's own left/right, as are ours.
def humanoid_of(mh: str) -> str:
    side = ""
    if mh.endswith(".L"):
        side, mh = "Left", mh[:-2]
    elif mh.endswith(".R"):
        side, mh = "Right", mh[:-2]
    if mh in ("root", "spine05", "pelvis"):
        return "Hips"
    if mh == "spine04":
        return "Spine"
    if mh == "spine03":
        return "Chest"
    if mh in ("spine02", "spine01", "breast"):
        return "UpperChest"
    if mh.startswith("neck"):
        return "Neck"
    if mh == "clavicle":
        return side + "Shoulder"
    if mh in ("shoulder01", "upperarm01", "upperarm02"):
        return side + "UpperArm"
    if mh.startswith("lowerarm"):
        return side + "LowerArm"
    if mh in ("wrist",) or mh.startswith(("finger", "metacarpal")):
        return side + "Hand"
    if mh.startswith("upperleg"):
        return side + "UpperLeg"
    if mh.startswith("lowerleg"):
        return side + "LowerLeg"
    if mh == "foot":
        return side + "Foot"
    if mh.startswith("toe"):
        return side + "Toes"
    return "Head"  # head, jaw, eyes, lids, tongue, face muscles


class Human:
    """A morphed MakeHuman body: `coords` in MakeHuman space (all 19158 verts,
    helpers included, so proxies can be fitted)."""

    def __init__(self, targets: dict[str, float]):
        self.raw, self.base = _load_three(os.path.join(DATA, "models", "human_full_size.json"))
        n = len(self.base.coords)
        c = self.base.coords.copy()
        for name, w in targets.items():
            c += target_delta(name, n) * w
        self.coords = c
        self.joint_idx = self.raw["metadata"]["joint_pos_idxs"]

    def _j(self, bone: str, end: str = "head") -> np.ndarray:
        return self.coords[self.joint_idx[f"{bone}____{end}"]].mean(axis=0)

    def _palm(self, s: str):
        """(palm normal, finger direction, thumb-side axis) of hand `s` ('L'/'R').
        From the thumb's side: for the right hand thumb = finger x palm, so
        palm = thumb x finger; mirrored for the left."""
        k2, k5 = self._j(f"finger2-1.{s}"), self._j(f"finger5-1.{s}")
        t = (k2 - k5) / np.linalg.norm(k2 - k5)
        d = self._j(f"finger3-1.{s}") - self._j(f"wrist.{s}")
        d = d - t * np.dot(d, t)
        d /= np.linalg.norm(d)
        # MakeHuman space is Y up, facing +Z, the character's left at +X
        p = np.cross(t, d) if s == "R" else np.cross(d, t)
        return p, d, t

    def _lbs(self, transforms: dict[str, np.ndarray]):
        """Moves the vertices by {MakeHuman bone: 4x4 world transform},
        blended by the skin weights (bones not listed stay put)."""
        W = self.base.weights
        disp = np.zeros_like(self.coords)
        for vi, w in enumerate(W):
            v = self.coords[vi]
            for b, x in w.items():
                T = transforms.get(b)
                if T is not None and x > 0:
                    disp[vi] += x * (T[:3, :3] @ v + T[:3, 3] - v)
        self.coords = self.coords + disp

    def relax_hands(self, curl: float = 1.0, pronate: float = 1.0, grip: str = ""):
        """Turns the palms from MakeHuman's forward-facing rest pose towards
        the thighs (forearm twist spread along the forearm) and curls the
        fingers into a relaxed hand, since the humanoid skeleton has no
        forearm-twist or finger bones to do it at runtime."""
        for s in ("L", "R"):
            p, d, t = self._palm(s)
            mid = -1.0 if s == "L" else 1.0          # towards the midline in x
            target = np.array([mid, 0.0, -0.35])      # inward, a little back
            a0, a1 = self._j(f"lowerarm01.{s}"), self._j(f"wrist.{s}")
            ax = (a1 - a0) / np.linalg.norm(a1 - a0)
            pp = p - ax * np.dot(p, ax)
            tt = target - ax * np.dot(target, ax)
            ang = np.arctan2(np.dot(np.cross(pp, tt), ax), np.dot(pp, tt)) * pronate
            tr = {}
            hand = [f"wrist.{s}"] + [f"metacarpal{i}.{s}" for i in range(1, 5)] + \
                   [f"finger{f}-{k}.{s}" for f in range(1, 6) for k in range(1, 4)]
            for b, k in [(f"lowerarm01.{s}", 0.3), (f"lowerarm02.{s}", 0.75)] + [(b, 1.0) for b in hand]:
                M = np.eye(4)
                R = _rot(ax, ang * k)
                M[:3, :3] = R
                M[:3, 3] = a0 - R @ a0
                tr[b] = M
            self._lbs(tr)
            # straighten the wrist: the hand hangs in line with the forearm
            w0 = self._j(f"wrist.{s}")
            fa = w0 - self._j(f"lowerarm01.{s}")
            fa /= np.linalg.norm(fa)
            _, d, _ = self._palm(s)
            axis = np.cross(d, fa)
            sn = np.linalg.norm(axis)
            if sn > 1e-6:
                ang = np.arcsin(min(sn, 1.0)) * 0.8
                M = np.eye(4)
                R = _rot(axis / sn, ang)
                M[:3, :3] = R
                M[:3, 3] = w0 - R @ w0
                self._lbs({b: M for b in hand})
        # close the splay: MakeHuman's rest hand has its fingers fanned
        # apart, which reads as a claw once they curl; turn the index, ring
        # and little fingers most of the way towards the middle finger
        for s in ("L", "R"):
            p, _, _ = self._palm(s)
            ref = self._j(f"finger3-1.{s}", "tail") - self._j(f"finger3-1.{s}")
            ref -= p * np.dot(ref, p)
            ref /= np.linalg.norm(ref)
            tr = {}
            for f in (2, 4, 5):
                h = self._j(f"finger{f}-1.{s}")
                d = self._j(f"finger{f}-1.{s}", "tail") - h
                d -= p * np.dot(d, p)
                d /= np.linalg.norm(d)
                ang = np.arctan2(np.dot(np.cross(d, ref), p), np.dot(d, ref)) * 0.7
                M = np.eye(4)
                R = _rot(p, ang)
                M[:3, :3] = R
                M[:3, 3] = h - R @ h
                for k in (1, 2, 3):
                    tr[f"finger{f}-{k}.{s}"] = M
            self._lbs(tr)
        # per finger: degrees at its three joints (thumb first)
        angles = {1: (4, 10, 12), 2: (9, 16, 12), 3: (11, 19, 14), 4: (13, 22, 15), 5: (15, 25, 16)}
        for s in ("L", "R"):
            p, _, t = self._palm(s)
            tr = {}
            for f, angs in angles.items():
                T = np.eye(4)
                for k in range(1, 4):
                    b = f"finger{f}-{k}.{s}"
                    h, tl = self._j(b), self._j(b, "tail")
                    d = (tl - h) / max(np.linalg.norm(tl - h), 1e-9)
                    n = p if f > 1 else (p * 0.6 + (-t) * 0.4)  # the thumb folds across the palm
                    r = np.cross(d, n)
                    r /= max(np.linalg.norm(r), 1e-9)
                    hw = T[:3, :3] @ h + T[:3, 3]
                    rw = T[:3, :3] @ r
                    c = curl * (3.2 if s in grip else 1.0)   # a gripping hand closes
                    R = _rot(rw, np.radians(angs[k - 1] * c))
                    M = np.eye(4)
                    M[:3, :3] = R
                    M[:3, 3] = hw - R @ hw
                    T = M @ T
                    tr[b] = T.copy()
            self._lbs(tr)

    def grip_frame(self, s: str):
        """(origin, palm normal, finger dir, thumb axis) of hand `s` in Blender
        space (floor offset applied): the origin sits inside the closed fist."""
        p, d, t = self._palm(s)
        w = self._j(f"wrist.{s}")
        k = self._j(f"finger3-1.{s}")
        o = w * 0.35 + k * 0.65 + p * 0.25  # decimetres: ~2.5 cm into the palm
        off = self.floor_offset()
        tb = lambda x: to_blender(x) * 10.0  # noqa: E731  (directions: no scaling)
        return to_blender(o) + off, tb(p), tb(d), tb(t)

    # joints ----------------------------------------------------------------
    def joint(self, mh_bone: str, end: str = "head") -> np.ndarray:
        """Blender-space position of a MakeHuman bone's head/tail joint."""
        idx = self.joint_idx[f"{mh_bone}____{end}"]
        return to_blender(self.coords[idx].mean(axis=0))

    def floor_offset(self) -> np.ndarray:
        """Lifts the soles to z = 0."""
        body = self.body_vertex_ids()
        z = to_blender(self.coords[body])[:, 2].min()
        return np.array([0.0, 0.0, -z])

    def body_vertex_ids(self) -> np.ndarray:
        used = set()
        for f, m in zip(self.base.faces, self.base.face_mat):
            if m == 0:
                used.update(f)
        return np.array(sorted(used))

    def skeleton(self):
        """The humanoid Skel (meshkit) at this body's joints."""
        from meshkit import Skel
        off = self.floor_offset()
        J = lambda b, e="head": self.joint(b, e) + off  # noqa: E731
        S = Skel()
        hips = J("spine05")
        S.add("Root", None, (0, 0, 0), (0, 0.12, 0))
        S.add("Hips", "Root", hips, J("spine04"))
        S.add("Spine", "Hips", J("spine04"), J("spine03"))
        S.add("Chest", "Spine", J("spine03"), J("spine02"))
        S.add("UpperChest", "Chest", J("spine02"), J("neck01"))
        S.add("Neck", "UpperChest", J("neck01"), J("head"))
        S.add("Head", "Neck", J("head"), J("head", "tail"))
        for side, mh in (("Left", "L"), ("Right", "R")):
            S.add(side + "Shoulder", "UpperChest", J(f"clavicle.{mh}"), J(f"upperarm01.{mh}"))
            S.add(side + "UpperArm", side + "Shoulder", J(f"upperarm01.{mh}"), J(f"lowerarm01.{mh}"))
            S.add(side + "LowerArm", side + "UpperArm", J(f"lowerarm01.{mh}"), J(f"wrist.{mh}"))
            S.add(side + "Hand", side + "LowerArm", J(f"wrist.{mh}"), J(f"finger3-2.{mh}"))
        for side, mh in (("Left", "L"), ("Right", "R")):
            S.add(side + "UpperLeg", "Hips", J(f"upperleg01.{mh}"), J(f"lowerleg01.{mh}"))
            S.add(side + "LowerLeg", side + "UpperLeg", J(f"lowerleg01.{mh}"), J(f"foot.{mh}"))
            S.add(side + "Foot", side + "LowerLeg", J(f"foot.{mh}"), J(f"toe3-1.{mh}"))
            S.add(side + "Toes", side + "Foot", J(f"toe3-1.{mh}"), J(f"toe3-3.{mh}", "tail"))
        return S

    # meshes ----------------------------------------------------------------
    def body_mesh(self):
        """(verts Blender space, faces, face uvs, humanoid weights) of the skin
        surface (material 0), re-indexed."""
        ids = self.body_vertex_ids()
        remap = -np.ones(len(self.coords), dtype=np.int64)
        remap[ids] = np.arange(len(ids))
        faces, fuv = [], []
        for f, m, u in zip(self.base.faces, self.base.face_mat, self.base.face_uv):
            if m == 0:
                faces.append(tuple(int(remap[i]) for i in f))
                fuv.append(u)
        verts = to_blender(self.coords[ids]) + self.floor_offset()
        weights = [_fold(self.base.weights[i]) for i in ids]
        return verts, faces, fuv, weights

    def proxy(self, rel: str):
        """Fits proxy `rel` (e.g. 'hair/short02/short02.json') to this body.
        Returns (verts, faces, face uvs, humanoid weights, texture path)."""
        path = os.path.join(DATA, "proxies", rel)
        d, m = _load_three(path)
        ref = np.array(d["ref_vIdxs"], dtype=np.int64)
        w = np.array(d["weights"], dtype=np.float64)
        off = np.array(d["offsets"], dtype=np.float64)
        # MakeHuman scales the offsets with the body (mhclo x/y/z_scale, which
        # the export dropped); scale them by the morph's local size change
        # around the reference triangle instead.
        base = self.base.coords
        p = (self.coords[ref] * w[..., None]).sum(axis=1) + off * _local_scale(base, self.coords, ref)[:, None]
        verts = to_blender(p) + self.floor_offset()
        # weights: the reference vertices' weights, blended
        weights = []
        for r, ww in zip(ref, w):
            acc: dict[str, float] = {}
            for vi, x in zip(r, ww):
                for b, y in _fold(self.base.weights[vi]).items():
                    acc[b] = acc.get(b, 0.0) + y * max(x, 0.0)
            s = sum(acc.values()) or 1.0
            weights.append({b: y / s for b, y in acc.items()})
        tex = None
        if m.texture:
            tex = os.path.join(os.path.dirname(path), "textures", os.path.basename(m.texture))
        return verts, m.faces, m.face_uv, weights, tex


def _rot(axis: np.ndarray, ang: float) -> np.ndarray:
    x, y, z = axis
    c, s_ = np.cos(ang), np.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s_, x * z * C + y * s_],
                     [y * x * C + z * s_, c + y * y * C, y * z * C - x * s_],
                     [z * x * C - y * s_, z * y * C + x * s_, c + z * z * C]])


def _local_scale(base, morphed, ref) -> np.ndarray:
    a = np.linalg.norm(base[ref[:, 0]] - base[ref[:, 1]], axis=1) + np.linalg.norm(base[ref[:, 1]] - base[ref[:, 2]], axis=1)
    b = np.linalg.norm(morphed[ref[:, 0]] - morphed[ref[:, 1]], axis=1) + np.linalg.norm(morphed[ref[:, 1]] - morphed[ref[:, 2]], axis=1)
    return np.where(a > 1e-9, b / np.maximum(a, 1e-9), 1.0)


def _fold(w: dict[str, float]) -> dict[str, float]:
    out: dict[str, float] = {}
    for b, x in w.items():
        h = humanoid_of(b)
        out[h] = out.get(h, 0.0) + x
    s = sum(out.values()) or 1.0
    out = {b: x / s for b, x in out.items() if x / s > 0.01}
    if len(out) > 4:
        out = dict(sorted(out.items(), key=lambda kv: -kv[1])[:4])
    s = sum(out.values())
    return {b: x / s for b, x in out.items()}


def skin_texture(skin: str = "young_caucasian_male") -> str:
    d = os.path.join(DATA, "skins", skin, "textures")
    return os.path.join(d, sorted(os.listdir(d))[-1] if skin != "young_caucasian_male"
                        else "young_lightskinned_male_diffuse.png")

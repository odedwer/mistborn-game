"""Builds realistic (MakeHuman-based) character GLBs with Blender-as-a-module.

Usage (from the repo root):
    tools/characters/.venv-bpy/bin/python tools/characters/fetch_mh.py   # once
    tools/characters/.venv-bpy/bin/python tools/characters/mh_build.py [name ...]

Per character: a morphed MakeHuman body (subdivided once), eyes, brows,
lashes and hair proxies, garments cut from the body surface and pushed out
along the normals (shirt, trousers, boots), and an optional mistcloak draped
with Blender's cloth solver and split into ribbons below the waist. The
skeleton is the project's humanoid one (body.HUMANOID_BONES) at MakeHuman's
joints, so anim.py's procedural clips play unchanged.

Writes assets/models/characters/<name>.glb + .json, its textures under
textures/<name>/ and StandardMaterial3D files under materials/<name>/.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "characters")
RES = "res://assets/models/characters"

import bpy  # noqa: E402
import bmesh  # noqa: E402
import mathutils  # noqa: E402
import numpy as np  # noqa: E402

import mh_human as mh  # noqa: E402
import mh_textures as tx  # noqa: E402
from anim import ANIM_NAMES, LOOPING, Rig, make_anims  # noqa: E402
from build_characters import bake_actions, build_armature, reset  # noqa: E402

# ------------------------------------------------------------------ characters
# body: MakeHuman macro sliders; skin: MakeHuman skin set; garments: name ->
# (body region, offset m, fabric kind, linear colour); cloak: mistcloak or None
SPECS = {
    "kelsier": dict(
        style="kelsier",
        body=dict(gender=1.0, age=0.56, muscle=0.66, weight=0.42, height=0.58, proportions=0.75),
        skin="young_caucasian_male", skin_tint=(1.0, 0.97, 0.95),
        eyes="grey", brows="eyebrow001", lashes="Eyelashes01",
        hair=("short02", (0.3, 0.21, 0.13)),
        garments={
            "Coat": ("shirt", 0.012, "wool", (0.13, 0.105, 0.085)),
            "Trousers": ("trousers", 0.009, "wool", (0.06, 0.056, 0.052)),
            "Boots": ("boots", 0.01, "leather", (0.05, 0.036, 0.026)),
        },
        belt=dict(color=(0.07, 0.045, 0.03)),
        collar="coat",
        loose={"Coat": {"Spine": 2.4, "Chest": 2.4, "UpperChest": 2.0, "Hips": 2.2, "Shoulder": 1.4}},
        skirt=dict(material="coat", hem_z=0.62, flare=0.08, front_gap=28.0),
        cloak=dict(color=(0.17, 0.18, 0.19), hem_z=0.36, split_z=1.05, strips=22),
    ),
    "guard": dict(
        style="guard",
        body=dict(gender=1.0, age=0.6, muscle=0.7, weight=0.55, height=0.55, proportions=0.6),
        skin="middleage_caucasian_male", skin_tint=(1.0, 0.95, 0.9),
        eyes="brown", brows="eyebrow001", lashes="Eyelashes01",
        hair=("short02", (0.1, 0.075, 0.055)),
        garments={
            "Tunic": ("shirt", 0.009, "wool", (0.2, 0.14, 0.085)),
            "Trousers": ("trousers", 0.008, "wool", (0.09, 0.08, 0.07)),
            "Boots": ("boots", 0.011, "leather", (0.06, 0.04, 0.026)),
            "Cuirass": ("cuirass", 0.032, "metal", (0.4, 0.41, 0.43)),
            "Pauldrons": ("pauldron", 0.04, "metal", (0.36, 0.37, 0.39)),
            "Gloves": ("gloves", 0.004, "leather", (0.07, 0.05, 0.035)),
        },
        loose={"Tunic": {"Spine": 1.6, "Chest": 1.6, "UpperChest": 1.4, "Hips": 1.6}},
        collar="tunic",
        belt=dict(color=(0.05, 0.034, 0.022)),
        skirt=dict(material="tunic", hem_drop=0.32, flare=0.06, front_gap=0.0, folds=6),
        helmet=dict(depth=0.075, brim=0.05, material="helmet"),
        spear="R",
        lantern=True,
    ),
    "vin": dict(
        style="vin",
        body=dict(gender=0.0, age=0.47, muscle=0.55, weight=0.34, height=0.52, proportions=0.8),
        skin="young_caucasian_female", skin_tint=(1.0, 0.96, 0.93),
        eyes="brown", brows="eyebrow002", lashes="Eyelashes01",
        hair=("bob02", (0.1, 0.07, 0.05)),
        garments={
            "Shirt": ("shirt", 0.008, "linen", (0.1, 0.09, 0.105)),
            "Trousers": ("trousers", 0.008, "wool", (0.068, 0.06, 0.075)),
            "Boots": ("boots", 0.009, "leather", (0.045, 0.032, 0.022)),
        },
        loose={"Shirt": {"Spine": 1.8, "Chest": 1.8, "UpperChest": 1.5, "Hips": 1.6}},
        collar="shirt",
        belt=dict(color=(0.06, 0.038, 0.025)),
        dagger="R",
        skirt=dict(material="shirt", hem_drop=0.24, flare=0.03, front_gap=0.0, folds=5),
        cloak=dict(color=(0.2, 0.21, 0.225), hem_z=0.3, split_z=0.86, span=180.0),
    ),
}


# ---------------------------------------------------------------------- regions
def dominant(w: dict) -> str:
    return max(w.items(), key=lambda kv: kv[1])[0] if w else "Hips"


def region_of(kind: str, v: np.ndarray, w: dict, S) -> bool:
    b = dominant(w)
    z = v[2]
    waist = S.head("Spine")[2] - 0.02
    wrist_z = None
    if kind == "shirt":
        if b == "Head" or b.endswith(("Hand", "UpperLeg", "LowerLeg", "Foot", "Toes")):
            return False
        if b.endswith("LowerArm"):
            # stop a hand's width short of the wrist
            side = "Left" if b.startswith("Left") else "Right"
            wr = S.head(side + "Hand")
            return np.linalg.norm(v - wr) > 0.05
        if b == "Hips":
            return z > waist - 0.12
        return z < S.head("Neck")[2] - 0.01
    if kind == "trousers":
        if b == "Hips":
            return z < waist + 0.02
        if b.endswith(("UpperLeg", "LowerLeg")):
            return z > 0.22
        return False
    if kind == "boots":   # the shaft; the foot is a hull (foot_hull)
        if b.endswith(("Foot", "Toes", "LowerLeg")):
            return 0.07 < z < 0.34
        return False
    if kind == "cuirass":   # breast and back plates: the trunk between waist and collarbones
        if b in ("Spine", "Chest", "UpperChest") or (b == "Hips" and z > waist - 0.04):
            return z < S.head("Neck")[2] - 0.05
        return False
    if kind == "pauldron":  # shoulder caps
        if b.endswith(("Shoulder", "UpperArm")):
            sh = S.head(("Left" if b.startswith("Left") else "Right") + "UpperArm")
            return z > sh[2] - 0.13
        return False
    if kind == "gloves":
        if b.endswith("Hand"):
            return True
        if b.endswith("LowerArm"):
            side = "Left" if b.startswith("Left") else "Right"
            return np.linalg.norm(v - S.head(side + "Hand")) < 0.07
        return False
    if kind == "feet":
        return b.endswith(("Foot", "Toes", "LowerLeg")) and z < 0.14
    raise ValueError(kind)
    return wrist_z


# ------------------------------------------------------------------ mesh utils
def vertex_normals(verts: np.ndarray, faces) -> np.ndarray:
    n = np.zeros_like(verts)
    for f in faces:
        p = verts[list(f)]
        fn = np.cross(p[1] - p[0], p[2] - p[0])
        if len(f) == 4:
            fn += np.cross(p[2] - p[0], p[3] - p[0])
        for i in f:
            n[i] += fn
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def taubin(v: np.ndarray, faces, iters: int, lam=0.5, mu=-0.53, pin_rings=2) -> np.ndarray:
    """Taubin smoothing (shrink-free) with the open edges and `pin_rings`
    rings inside them held still, so hems and cuffs keep their place."""
    n = len(v)
    nb = [set() for _ in range(n)]
    edge_count: dict = {}
    for f in faces:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            nb[a].add(b)
            nb[b].add(a)
            e = (min(a, b), max(a, b))
            edge_count[e] = edge_count.get(e, 0) + 1
    pinned = np.zeros(n, bool)
    for (a, b), c in edge_count.items():
        if c == 1:
            pinned[a] = pinned[b] = True
    for _ in range(pin_rings):
        ring = pinned.copy()
        for i in np.nonzero(pinned)[0]:
            for j in nb[i]:
                ring[j] = True
        pinned = ring
    # free vertices move fully; pinned ones not at all
    idx = [np.fromiter(x, int) for x in nb]
    v = v.copy()
    free = ~pinned
    for it in range(iters * 2):
        f = lam if it % 2 == 0 else mu
        avg = np.array([v[j].mean(axis=0) if len(j) else v[i] for i, j in enumerate(idx)])
        v[free] += f * (avg[free] - v[free])
    return v


def make_obj(name, verts, faces, face_uv, weights, mat, arm, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in verts], [], [list(f) for f in faces])
    me.update()
    me.materials.append(mat)
    me.polygons.foreach_set("use_smooth", [smooth] * len(me.polygons))
    uv = me.uv_layers.new(name="UVMap")
    uvs = []
    for fi, poly in enumerate(me.polygons):
        for k in range(poly.loop_total):
            uvs += list(face_uv[fi][k])
    me.uv_layers["UVMap"].data.foreach_set("uv", uvs)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    groups = {b.name: obj.vertex_groups.new(name=b.name) for b in arm.data.bones}
    for vi, w in enumerate(weights):
        for b, x in w.items():
            groups[b].add([vi], float(x), "REPLACE")
    return obj


def bind(obj, arm):
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def apply_mods(obj, *mods):
    bpy.context.view_layer.objects.active = obj
    for m in mods:
        bpy.ops.object.modifier_apply(modifier=m)


def subdivide(obj, levels=1):
    m = obj.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    m.uv_smooth = "PRESERVE_CORNERS"
    apply_mods(obj, "Subsurf")


def solidify(obj, thickness):
    m = obj.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = thickness
    m.offset = -1.0
    m.use_rim = True
    m.use_even_offset = False
    apply_mods(obj, "Solid")


# ------------------------------------------------------------------- materials
def gltf_mat(name):
    """A plain named material: Godot swaps it for materials/<char>/<name>.tres."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


SHARED = os.path.join(OUT, "textures", "shared")
SHARED_RES = f"{RES}/textures/shared"


def shared_fabric(kind: str) -> dict:
    """Neutral (mid-grey) tileable maps of a fabric kind, shared by every
    character: materials tint them with albedo_color (see fabric_tint)."""
    pre = os.path.join(SHARED, kind)
    if not os.path.exists(pre + "_albedo.png"):
        tx.fabric_maps(kind, (0.5, 0.5, 0.5), pre, seed=17 + sum(map(ord, kind)))
    return {"albedo_texture": f"{SHARED_RES}/{kind}_albedo.png", "normal_texture": f"{SHARED_RES}/{kind}_normal.png",
            "roughness_texture": f"{SHARED_RES}/{kind}_roughness.png"}


def fabric_tint(col) -> str:
    """albedo_color that turns the 0.5 grey shared maps into `col` (sRGB
    values; exact under a power-law transfer since (0.5 * 2c) = c)."""
    r, g, b = (min(2.0 * c, 1.0) for c in col)
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, 1)"


def shared_skin(skin: str, tint) -> dict:
    """Per skin-and-tint albedo; the pore normal and roughness detail (the
    same for every skin) is one shared pair."""
    key = skin + "_" + "".join(f"{int(t * 100):03d}" for t in tint)
    pre = os.path.join(SHARED, "skin_" + key)
    if not os.path.exists(pre + "_albedo.png"):
        tx.skin_maps(mh.skin_texture(skin), pre, tint=tint)
        for m in ("normal", "roughness"):
            detail = os.path.join(SHARED, f"skin_detail_{m}.png")
            if os.path.exists(detail):
                os.remove(f"{pre}_{m}.png")
            else:
                os.replace(f"{pre}_{m}.png", detail)
    return {"albedo_texture": f"{SHARED_RES}/skin_{key}_albedo.png",
            "normal_texture": f"{SHARED_RES}/skin_detail_normal.png",
            "roughness_texture": f"{SHARED_RES}/skin_detail_roughness.png"}


def write_tres(path, props: dict, textures: dict):
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(textures) + 1} format=3]', ""]
    ids = {}
    for i, (slot, tex) in enumerate(textures.items(), start=1):
        lines.append(f'[ext_resource type="Texture2D" path="{tex}" id="{i}"]')
        ids[slot] = i
    lines += ["", "[resource]"]
    for k, v in props.items():
        lines.append(f"{k} = {v}")
    for slot, i in ids.items():
        lines.append(f'{slot} = ExtResource("{i}")')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ draping
class Collider:
    """Ray queries against the body without its forearms and hands (they hang
    beside the hips and thighs, where skirts, belts and cloaks pass), pushed
    out by `pad` along the normals."""

    def __init__(self, verts, faces, weights, pad=0.0, shoulder_z=9.0):
        from mathutils.bvhtree import BVHTree
        def arm(i):
            d = dominant(weights[i])
            return d.endswith(("LowerArm", "Hand")) or (d.endswith("UpperArm") and verts[i][2] < shoulder_z)
        keep = [f for f in faces if not any(arm(i) for i in f)]
        n = vertex_normals(verts, faces)
        v = verts + n * pad
        self.bvh = BVHTree.FromPolygons([tuple(x) for x in v], [list(f) for f in keep])

    def outer_radius(self, c, d, default=0.0):
        """Distance from axis point `c` to the outermost surface along the
        horizontal direction `d` (a ray cast inwards from far outside)."""
        o = mathutils.Vector(tuple(c)) + mathutils.Vector(tuple(d)) * 1.2
        hit = self.bvh.ray_cast(o, -mathutils.Vector(tuple(d)))
        if hit[0] is None:
            return default
        return 1.2 - hit[3]

    def top(self, x, y, default):
        hit = self.bvh.ray_cast(mathutils.Vector((x, y, 2.6)), mathutils.Vector((0, 0, -1)))
        return hit[0].z if hit[0] is not None else default


def hang(col: Collider, top_pts, bottom_z, rows, axis_xy, clearance=0.025, flare=0.0,
         folds=0, fold_amp=0.0, seed=0):
    """A cloth sheet hanging straight down from the polyline `top_pts`
    (x, y, z) to `bottom_z`: each column falls vertically, swings out by
    `flare` (m at the hem, proportional to the drop) and is pushed out of the
    collider (with `clearance`) - it rests on what it falls past, like cloth
    on a body - then `folds` vertical folds of `fold_amp` grow with the drop.
    Returns (verts (rows+1)*(cols) x 3, faces, uvs per face corner)."""
    rng = np.random.default_rng(seed)
    cols = len(top_pts)
    ax, ay = axis_xy
    phase = rng.random() * 6.28
    verts = np.zeros((rows + 1, cols, 3))
    for c, (x, y, z0) in enumerate(top_pts):
        d = np.array([x - ax, y - ay, 0.0])
        d /= max(np.linalg.norm(d), 1e-6)
        r_prev = np.hypot(x - ax, y - ay)
        for r in range(rows + 1):
            t = r / rows
            z = z0 + (bottom_z - z0) * t
            rad = np.hypot(x - ax, y - ay) + flare * t
            body = col.outer_radius((ax, ay, z), d, 0.0)
            rad = max(rad, body + clearance, r_prev - 0.02 if r > 0 else 0)
            # a falling sheet keeps the widest radius it has passed, eased
            r_prev = max(rad, r_prev * 0.985)
            rad = max(rad, r_prev)
            fold = fold_amp * min(t * 1.6, 1.0) * np.sin(c / cols * folds * 6.2832 + phase)
            p = np.array([ax, ay, z]) + d * (rad + fold)
            verts[r, c] = p
    faces, fuv = [], []
    for r in range(rows):
        for c in range(cols - 1):
            i = r * cols + c
            faces.append((i, i + 1, i + cols + 1, i + cols))
            u0, u1 = c / (cols - 1), (c + 1) / (cols - 1)
            v0, v1 = 1 - r / rows, 1 - (r + 1) / rows
            fuv.append([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    return verts.reshape(-1, 3), faces, fuv


def build_cloak(S, col: Collider, arm, spec, mat):
    """The mistcloak: over the shoulders and down the back, ribbons below
    `split_z`. Draped by `hang` (deterministic; no solver)."""
    neck = S.head("Neck")
    sh_r = S.tail("RightShoulder")
    cols = 97
    spec["_cols"] = cols
    span = math.radians(spec.get("span", 176.0))
    ax_, ay_ = abs(sh_r[0]) + 0.05, 0.16
    top = []
    for c in range(cols):
        a = -span / 2 + span * c / (cols - 1)  # 0 = straight back (-Y)
        x, y = math.sin(a) * ax_, -math.cos(a) * ay_ + neck[1]
        top.append((x, y, col.top(x, y, neck[2] - 0.1) + 0.022))
    v, f, uv = hang(col, top, spec["hem_z"], 60, (0.0, neck[1]), clearance=0.03, flare=0.1,
                    folds=spec.get("folds", 9), fold_amp=0.022, seed=5)
    # ribbons: below split_z, cut a gap after every third column of faces
    keep_f, keep_uv = [], []
    for k, (face, u) in enumerate(zip(f, uv)):
        r, c = divmod(k, cols - 1)
        zc = np.mean([v[i][2] for i in face])
        if zc < spec["split_z"] and c % 4 == 3:
            continue
        keep_f.append(face)
        keep_uv.append([(a * 4.0, b * 3.0) for a, b in u])
    return v, keep_f, keep_uv


CHAIN = 4


def cloak_chains(S, geo, spec, parent="Chest"):
    """One spring-bone chain (Tassel_kk_0..3, the CharacterModel's cloak
    dynamics) per ribbon, from the split down its centre to the hem. Adds the
    bones to `S`; returns [{bones, cols, z0, z1}]."""
    v, f, uv = geo
    cols = spec["_cols"]
    rows = len(v) // cols - 1
    grid = np.asarray(v).reshape(rows + 1, cols, 3)
    split, hem = spec["split_z"], spec["hem_z"]
    out = []
    k = 0
    for c0 in range(0, cols - 1, 4):
        cs = [c for c in range(c0, min(c0 + 4, cols))]   # vertex columns of this ribbon
        line = grid[:, cs, :].mean(axis=1)               # centre line, top to hem
        zs = line[:, 2]
        pts = []
        for j in range(CHAIN + 1):
            z = split + (hem - split) * j / CHAIN
            i = int(np.clip(np.searchsorted(-zs, -z), 1, rows))
            t = (zs[i - 1] - z) / max(zs[i - 1] - zs[i], 1e-6)
            pts.append(line[i - 1] + (line[i] - line[i - 1]) * np.clip(t, 0, 1))
        names = [f"Tassel_{k:02d}_{j}" for j in range(CHAIN)]
        par = parent
        for j in range(CHAIN):
            S.add(names[j], par, pts[j], pts[j + 1])
            par = names[j]
        out.append(dict(bones=names, cols=(c0, c0 + 4), xy=line[:, :2]))
        k += 1
    return out


def chain_weights(v, base_w, chains, spec):
    """Below the split, each ribbon's vertices follow its chain (blended with
    the cloak's body weights just under the split)."""
    cols = spec["_cols"]
    split, hem = spec["split_z"], spec["hem_z"]
    out = []
    for vi, p in enumerate(v):
        c = vi % cols
        w = base_w[vi]
        if p[2] < split + 0.02:
            ch = next(ch for ch in chains if ch["cols"][0] <= c < ch["cols"][1] or ch is chains[-1])
            f = (split + 0.02 - p[2]) / (split + 0.02 - hem) * CHAIN
            j = int(np.clip(np.floor(f), 0, CHAIN - 1))
            t = f - j
            nw = {ch["bones"][j]: 1.0}
            if j == 0 and t < 0.5:
                k = (0.5 - t) * 2
                nw = {ch["bones"][0]: 1 - k}
                for b, x in w.items():
                    nw[b] = nw.get(b, 0.0) + x * k
            elif t < 0.3 and j > 0:
                nw = {ch["bones"][j - 1]: 0.5 * (0.3 - t) / 0.3, ch["bones"][j]: 1 - 0.5 * (0.3 - t) / 0.3}
            w = nw
        out.append(w)
    return out


def build_skirt(S, col: Collider, spec):
    """A coat's skirt from the waist to `hem_z`, open at the front."""
    hips = S.head("Hips")
    zc = S.head("Spine")[2] - 0.02
    cols = 81
    gap = math.radians(spec.get("front_gap", 24.0))
    top = []
    for c in range(cols):
        a = gap / 2 + (2 * math.pi - gap) * c / (cols - 1)  # 0 = front (+Y), around the back
        d = (math.sin(a), math.cos(a), 0.0)
        r = col.outer_radius((0.0, hips[1], zc), d, 0.16) + 0.012
        top.append((d[0] * r, hips[1] + d[1] * r, zc))
    hem = spec["hem_z"] if "hem_z" in spec else zc - spec["hem_drop"]
    return hang(col, top, hem, 36, (0.0, hips[1]), clearance=0.02, flare=spec.get("flare", 0.06),
                folds=spec.get("folds", 7), fold_amp=0.012, seed=9)


def weights_from_nearest(obj, ref_verts: np.ndarray, ref_weights: list, S, free_below=None):
    """Copies each vertex's skin weights from the nearest reference vertex;
    below `free_below` (hanging cloth) binds to the hips and spine instead."""
    kd = mathutils.kdtree.KDTree(len(ref_verts))
    for i, p in enumerate(ref_verts):
        kd.insert(mathutils.Vector(p.tolist()), i)
    kd.balance()
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {}
    for v in obj.data.vertices:
        co = v.co
        if free_below is not None and co.z < free_below:
            k = min((free_below - co.z) / 0.25, 1.0)
            w = {"Hips": 0.6 + 0.4 * k, "Spine": 0.4 * (1 - k)}
        else:
            _, i, _ = kd.find(co)
            w = ref_weights[i]
        for b, x in w.items():
            if x <= 0:
                continue
            if b not in groups:
                groups[b] = obj.vertex_groups.new(name=b)
            groups[b].add([v.index], float(x), "REPLACE")


# ---------------------------------------------------------------------- weapons
def build_dagger(human, arm, name, side="R", blade=0.2, reverse=True):
    """An obsidian dagger in the closed hand (reverse grip: the blade leaves
    the fist on the little-finger side)."""
    o, p, d, t = human.grip_frame(side)
    g = -t if reverse else t
    hand = ("Right" if side == "R" else "Left") + "Hand"
    parts = []

    def prism(a, b, ra, rb, n, flat=1.0, mat="handle"):
        u = np.cross(b - a, p)
        u /= np.linalg.norm(u)
        w = np.cross(u, (b - a) / np.linalg.norm(b - a))
        vs, fs = [], []
        for ring, (c, r) in enumerate(((a, ra), (b, rb))):
            for i in range(n):
                ang = 2 * math.pi * i / n
                vs.append(c + (u * math.cos(ang) * r) + (w * math.sin(ang) * r * flat))
        for i in range(n):
            j = (i + 1) % n
            fs.append((i, j, n + j, n + i))
        for i in range(1, n - 1):  # end caps as fans (glTF tangents need tris/quads)
            fs.append((0, i + 1, i))
            fs.append((n, n + i, n + i + 1))
        parts.append((np.array(vs), fs, mat))

    grip0 = o - g * 0.05
    prism(grip0, grip0 + g * 0.11, 0.013, 0.012, 12)
    prism(grip0 + g * 0.11, grip0 + g * 0.125, 0.03, 0.03, 4, flat=0.35)
    b0 = grip0 + g * 0.125
    prism(b0, b0 + g * blade * 0.5, 0.017, 0.016, 4, flat=0.25, mat="obsidian")
    prism(b0 + g * blade * 0.5, b0 + g * blade, 0.016, 0.0008, 4, flat=0.25, mat="obsidian")
    for k, (vs, fs, mat) in enumerate(parts):
        uv = [[(0.0, 0.0)] * len(f) for f in fs]
        ob = make_obj(f"Dagger{k}", vs, fs, uv, [{hand: 1.0}] * len(vs), gltf_mat(name + "_" + mat), arm,
                      smooth=(mat == "handle"))


# --------------------------------------------------------------------- helmets
def build_helmet(S, col, arm, name, spec):
    """A helmet turned about the head's vertical axis: a skull cap sized to
    the head (from the collider) and a brim (`brim` m wide) at `brim_z`
    below the crown (kettle hat)."""
    hd, tl = S.head("Head"), S.tail("Head")
    cx, cy = (hd[0] + tl[0]) / 2, (hd[1] + tl[1]) / 2 - 0.01
    top = col.top(cx, cy, tl[2]) + 0.012
    rim_z = top - spec.get("depth", 0.11)
    # head radius at the rim height, around
    rr = [col.outer_radius((cx, cy, rim_z), (math.sin(a), math.cos(a), 0.0), 0.1) for a in np.linspace(0, 6.28, 16)]
    r0 = max(rr) + spec.get("clear", 0.012)
    prof = []                                   # (radius, z) crown -> rim -> brim edge
    for k in range(9):
        t = k / 8
        ang = t * math.pi / 2
        prof.append((r0 * math.sin(ang), rim_z + (top - rim_z) * math.cos(ang)))
    brim = spec.get("brim", 0.0)
    if brim > 0:
        prof += [(r0 + brim * 0.45, rim_z - 0.012), (r0 + brim, rim_z - 0.03)]
    n = 40
    verts, faces, fuv = [], [], []
    for r_, z in prof:
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append((cx + math.sin(a) * r_, cy + math.cos(a) * r_ * 1.08, z))
    for k in range(len(prof) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, (k + 1) * n + i, (k + 1) * n + j, k * n + j))
            fuv.append([(i / n * 4, k / 8), (i / n * 4, (k + 1) / 8), ((i + 1) / n * 4, (k + 1) / 8),
                        ((i + 1) / n * 4, k / 8)])
    o = make_obj("Helmet", np.array(verts), faces, fuv, [{"Head": 1.0}] * len(verts),
                 gltf_mat(name + "_" + spec.get("material", "helmet")), arm)
    subdivide(o, 1)
    solidify(o, 0.004)
    return o


# -------------------------------------------------------------------- lantern
def build_belt_lantern(S, col, arm, name, side=-1):
    """A small iron lantern hanging from the belt at the hip (the guard's:
    CharacterModel lights it from the `lantern` socket). Returns the socket
    position."""
    hips = S.head("Hips")
    zc = S.head("Spine")[2] - 0.035
    d = (side * 0.94, 0.34, 0.0)
    r = col.outer_radius((hips[0], hips[1], zc), d, 0.17)
    hook = np.array([hips[0] + d[0] * (r + 0.03), hips[1] + d[1] * (r + 0.03), zc - 0.02])
    c = hook + np.array([side * 0.015, 0.0, -0.13])
    bm = bmesh.new()
    for (sx, sy, sz, off) in ((0.045, 0.045, 0.09, (0, 0, 0)),          # glass box
                              (0.055, 0.055, 0.012, (0, 0, 0.051)),     # top plate
                              (0.055, 0.055, 0.012, (0, 0, -0.051)),    # base
                              (0.02, 0.02, 0.03, (0, 0, 0.072))):       # chimney
        geom = bmesh.ops.create_cube(bm, size=1.0)
        for v in geom["verts"]:
            v.co = mathutils.Vector((v.co.x * sx * 2, v.co.y * sy * 2, v.co.z * sz * 2)) + \
                mathutils.Vector(tuple(c + np.array(off)))
    me = bpy.data.meshes.new("Lantern")
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name="UVMap")
    me.materials.append(gltf_mat(name + "_iron"))
    me.materials.append(gltf_mat(name + "_lanternglass"))
    for poly in me.polygons:   # the first cube (6 faces) is the glass
        poly.material_index = 1 if poly.index < 6 else 0
    o = bpy.data.objects.new("Lantern", me)
    bpy.context.scene.collection.objects.link(o)
    g = o.vertex_groups.new(name="Hips")
    g.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    return c


# ---------------------------------------------------------------------- spear
def build_spear(human, arm, name, side="R", up=1.25, down=0.55):
    """A spear held upright through the closed fist (along the grip axis)."""
    o, p, d, t = human.grip_frame(side)
    # the old rig's grip axis: forward, square to the fingers; the guard's
    # carry pose (elbow ~80 degrees) stands it upright
    fwd = np.array([0.0, 1.0, 0.0])
    dn = d / np.linalg.norm(d)
    g = fwd - dn * np.dot(dn, fwd)
    g /= np.linalg.norm(g)
    hand = ("Right" if side == "R" else "Left") + "Hand"
    parts = []

    def rod(a, b, ra, rb, n=10, mat="shaft", flat=1.0):
        ax = (b - a) / np.linalg.norm(b - a)
        u = np.cross(ax, p)
        u /= np.linalg.norm(u)
        w = np.cross(ax, u)
        vs, fs = [], []
        for c, r in ((a, ra), (b, rb)):
            for i in range(n):
                an = 2 * math.pi * i / n
                vs.append(c + u * math.cos(an) * r + w * math.sin(an) * r * flat)
        for i in range(n):
            j = (i + 1) % n
            fs.append((i, j, n + j, n + i))
        for i in range(1, n - 1):
            fs.append((0, i + 1, i))
            fs.append((n, n + i, n + i + 1))
        parts.append((np.array(vs), fs, mat))

    rod(o - g * down, o + g * up, 0.016, 0.014)
    tip = o + g * up
    rod(tip - g * 0.02, tip + g * 0.05, 0.02, 0.012, mat="steel")       # socket
    rod(tip + g * 0.05, tip + g * 0.12, 0.028, 0.02, n=4, mat="steel", flat=0.2)
    rod(tip + g * 0.12, tip + g * 0.3, 0.02, 0.0008, n=4, mat="steel", flat=0.2)
    for k, (vs, fs, mat) in enumerate(parts):
        make_obj(f"Spear{k}", vs, fs, [[(0.0, 0.0)] * len(f) for f in fs], [{hand: 1.0}] * len(vs),
                 gltf_mat(name + "_" + mat), arm, smooth=(mat == "shaft"))


# ----------------------------------------------------------------------- boots
def foot_hull(mat_name, verts, norms, weights, S, side, off, arm):
    """A shoe: the convex hull of one foot (toes and all) pushed out by
    `off`, rounded by a subdivision and a light smooth."""
    from scipy.spatial import ConvexHull
    ids = [i for i in range(len(verts)) if region_of("feet", verts[i], weights[i], S) and verts[i][0] * side > 0]
    pts = verts[ids] + norms[ids] * off
    pts[:, 2] = np.maximum(pts[:, 2], 0.0)
    hull = ConvexHull(pts)
    used = sorted(set(hull.simplices.ravel()))
    remap = {o: n for n, o in enumerate(used)}
    hv = pts[used]
    c = hv.mean(axis=0)
    hf = []
    for tri in hull.simplices:
        a, b, d = (remap[i] for i in tri)
        n = np.cross(hv[b] - hv[a], hv[d] - hv[a])
        if np.dot(n, hv[a] - c) < 0:
            b, d = d, b
        hf.append((a, b, d))
    huv = [[(hv[i][0] * 4, hv[i][1] * 4) for i in f] for f in hf]
    foot = ("Right" if side > 0 else "Left")
    hw = [{foot + "Foot": 1.0} if p[1] < S.head(foot + "Toes")[1] - 0.01 else {foot + "Toes": 0.6, foot + "Foot": 0.4}
          for p in hv]
    o = make_obj(f"Shoe{'R' if side > 0 else 'L'}", hv, hf, huv, hw, gltf_mat(mat_name), arm)
    subdivide(o, 2)
    sm = o.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.iterations = 4
    sm.lambda_factor = 1.0
    sm.use_volume_preserve = True
    apply_mods(o, "Smooth")
    return o


# ----------------------------------------------------------------------- belt
def build_belt(S, col, arm, name, spec, tdir, mdir, tres):
    """A leather belt around the waist (over the coat), with a buckle."""
    zc = S.head("Spine")[2] - 0.035
    n = 72
    c = S.head("Hips")
    verts, faces, fuv = [], [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = (math.sin(a), math.cos(a), 0.0)   # i = 0: the front (+Y)
        for z in (zc - 0.022, zc + 0.022):
            r = col.outer_radius((c[0], c[1], z), d, 0.17) + 0.008
            verts.append((c[0] + d[0] * r, c[1] + d[1] * r, z))
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
        fuv.append([(i / n * 8, 0), ((i + 1) / n * 8, 0), ((i + 1) / n * 8, 0.12), (i / n * 8, 0.12)])
    o = make_obj("Belt", np.array(verts), faces, fuv, [{"Hips": 1.0}] * len(verts), gltf_mat(name + "_belt"), arm)
    solidify(o, 0.006)
    # buckle: a squat box at the front
    front = mathutils.Vector(verts[0]) * 0.5 + mathutils.Vector(verts[1]) * 0.5
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = mathutils.Vector((v.co.x * 0.055, v.co.y * 0.012, v.co.z * 0.05)) + front + mathutils.Vector((0, 0.009, 0))
    me = bpy.data.meshes.new("Buckle")
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name="UVMap")
    bo = bpy.data.objects.new("Buckle", me)
    bpy.context.scene.collection.objects.link(bo)
    me.materials.append(gltf_mat(name + "_buckle"))
    g = bo.vertex_groups.new(name="Hips")
    g.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    write_tres(os.path.join(mdir, "belt.tres"),
               {"resource_name": f'"{name}_belt"', "roughness": 1.0, "normal_enabled": "true",
                "albedo_color": fabric_tint(spec["color"]), "uv1_scale": "Vector3(1, 1, 1)", "texture_filter": 5},
               shared_fabric("leather"))
    write_tres(os.path.join(mdir, "buckle.tres"),
               {"resource_name": f'"{name}_buckle"', "albedo_color": "Color(0.55, 0.5, 0.42, 1)",
                "metallic": 0.9, "roughness": 0.35}, {})


# ---------------------------------------------------------------------- build
def build(name):
    t0 = time.time()
    spec = SPECS[name]
    reset()
    tdir = os.path.join(OUT, "textures", name)
    mdir = os.path.join(OUT, "materials", name)
    tres = lambda n: f"{RES}/textures/{name}/{n}"  # noqa: E731

    human = mh.Human(mh.macro_weights(**spec["body"]))
    human.relax_hands(grip="R" if (spec.get("dagger") or spec.get("spear")) else "")
    S = human.skeleton()
    verts, faces, fuv, weights = human.body_mesh()
    col = Collider(verts, faces, weights, pad=0.014, shoulder_z=S.head("LeftUpperArm")[2] - 0.05)
    cloak_geo, chains = None, []
    if spec.get("cloak"):
        cloak_geo = build_cloak(S, col, None, spec["cloak"], None)
        chains = cloak_chains(S, cloak_geo, spec["cloak"])
    arm = build_armature(S)

    # garments cut from the body surface
    norms = vertex_normals(verts, faces)
    covered = np.zeros(len(verts), bool)
    garment_objs = []
    for gname, (region, off, kind, gcol) in spec["garments"].items():
        inside = np.array([region_of(region, verts[i], weights[i], S) for i in range(len(verts))])
        gfaces, guv = [], []
        for f, u in zip(faces, fuv):
            if all(inside[i] for i in f):
                gfaces.append(f)
                guv.append(u)
        ids = sorted({i for f in gfaces for i in f})
        remap = {o: n for n, o in enumerate(ids)}
        loose = spec.get("loose", {}).get(gname, {})
        k = np.array([loose.get(dominant(weights[i]).removeprefix("Left").removeprefix("Right"), 1.0) for i in ids])
        gv = verts[ids] + norms[ids] * (off * k)[:, None]
        gf = [tuple(remap[i] for i in f) for f in gfaces]
        gv = taubin(gv, gf, {"shirt": 60, "trousers": 25, "boots": 6, "cuirass": 120, "pauldron": 60,
                             "gloves": 10}.get(region, 20))
        o = make_obj(gname, gv, gf, guv,
                     [weights[i] for i in ids], gltf_mat(name + "_" + gname.lower()), arm)
        subdivide(o, 1)
        solidify(o, 0.003)
        garment_objs.append(o)
        uvs = {"linen": 22, "wool": 18, "leather": 6, "metal": 3}[kind]
        props = {"resource_name": f'"{name}_{gname.lower()}"', "cull_mode": 2,
                 "albedo_color": fabric_tint(gcol), "roughness": 1.0,
                 "normal_enabled": "true", "normal_scale": 0.8,
                 "uv1_scale": f"Vector3({uvs}, {uvs}, 1)",
                 "roughness_texture_channel": 0, "texture_filter": 5}
        if kind == "metal":
            props["metallic"] = 0.85
        write_tres(os.path.join(mdir, gname.lower() + ".tres"), props, shared_fabric(kind))
        if region == "boots":
            covered |= np.array([region_of("feet", verts[i], weights[i], S) for i in range(len(verts))])
            for side in (-1, 1):
                foot_hull(name + "_" + gname.lower(), verts, norms, weights, S, side, off, arm)
        # hide the skin well inside the garment (keep a ring under its edge)
        core = inside.copy()
        for f in faces:
            if not all(inside[i] for i in f):
                for i in f:
                    core[i] = False
        covered |= core

    # the body, minus faces fully under garments
    keep = [k for k, f in enumerate(faces) if not all(covered[i] for i in f)]
    body = make_obj("Body", verts, [faces[k] for k in keep], [fuv[k] for k in keep], weights,
                    gltf_mat(name + "_skin"), arm)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    # drop the vertices left without faces
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    subdivide(body, 1)
    write_tres(os.path.join(mdir, "skin.tres"),
               {"resource_name": f'"{name}_skin"', "roughness": 1.0,
                "normal_enabled": "true", "normal_scale": 0.35,
                "subsurf_scatter_enabled": "true", "subsurf_scatter_strength": 0.35,
                "subsurf_scatter_skin_mode": "true",
                "rim_enabled": "true", "rim": 0.25, "rim_tint": 0.6,
                "texture_filter": 5},
               shared_skin(spec["skin"], spec["skin_tint"]))

    # proxies: eyes, brows, lashes, hair
    def proxy(rel, mat_name, tex_dst, tint=None, solid=False):
        pv, pf, pu, pw, tex = human.proxy(rel)
        o = make_obj(mat_name, pv, pf, pu, pw, gltf_mat(name + "_" + mat_name.lower()), arm)
        if tex_dst and tex:
            if solid:
                import shutil
                os.makedirs(tdir, exist_ok=True)
                shutil.copy(tex, os.path.join(tdir, tex_dst))
            else:
                tx.alpha_card(tex, os.path.join(tdir, tex_dst), tint=tint)
        return o, tex

    # eyes: MakeHuman maps the cornea shell to a transparent corner of the
    # texture; it gets its own glossy see-through material
    pv, pf, pu, pw, _ = human.proxy("eyes/HighPolyEyes/HighPolyEyes.json")
    is_cornea = [np.mean([c[0] for c in u]) > 0.85 and np.mean([c[1] for c in u]) < 0.15 for u in pu]
    for label, sel in (("Eyes", False), ("Cornea", True)):
        fsel = [k for k, c in enumerate(is_cornea) if c == sel]
        ids = sorted({i for k in fsel for i in pf[k]})
        remap = {o: n for n, o in enumerate(ids)}
        make_obj(label, pv[ids], [tuple(remap[i] for i in pf[k]) for k in fsel], [pu[k] for k in fsel],
                 [pw[i] for i in ids], gltf_mat(name + "_" + label.lower()), arm)
    write_tres(os.path.join(mdir, "cornea.tres"),
               {"resource_name": f'"{name}_cornea"', "transparency": 1, "albedo_color": "Color(1, 1, 1, 0.04)",
                "roughness": 0.02, "metallic_specular": 1.0, "cull_mode": 0},
               {})
    import shutil
    os.makedirs(tdir, exist_ok=True)
    os.makedirs(SHARED, exist_ok=True)
    shutil.copy(os.path.join(mh.DATA, "proxies", "eyes", "HighPolyEyes", "textures", spec["eyes"] + "_eye.png"),
                os.path.join(SHARED, f"eyes_{spec['eyes']}.png"))
    write_tres(os.path.join(mdir, "eyes.tres"),
               {"resource_name": f'"{name}_eyes"', "roughness": 0.08, "metallic_specular": 0.7,
                "clearcoat_enabled": "true", "clearcoat": 1.0, "clearcoat_roughness": 0.02},
               {"albedo_texture": f"{SHARED_RES}/eyes_{spec['eyes']}.png"})
    hair_name, hair_tint = spec["hair"]
    for rel, label, dst, tint in (
            (f"eyebrows/{spec['brows']}/{spec['brows']}.json", "Brows", "brows.png", hair_tint),
            (f"eyelashes/{spec['lashes']}/{spec['lashes']}.json", "Lashes", "lashes.png", (0.09, 0.07, 0.055)),
            (f"hair/{hair_name}/{hair_name}.json", "Hair", "hair.png", hair_tint)):
        proxy(rel, label, dst, tint=tint)
        write_tres(os.path.join(mdir, label.lower() + ".tres"),
                   {"resource_name": f'"{name}_{label.lower()}"', "transparency": 3,  # alpha hash
                    "cull_mode": 2, "roughness": 0.55, "metallic_specular": 0.35,
                    "texture_filter": 5, "alpha_antialiasing_mode": 0},
                   {"albedo_texture": tres(dst)})

    # draped pieces: coat skirt and mistcloak, resting on the dressed body
    if spec.get("belt"):
        build_belt(S, col, arm, name, spec["belt"], tdir, mdir, tres)

    def skirt_weights(points):
        """Hips, with the lower skirt following each thigh on its side."""
        hz = S.head("Hips")[2]
        out = []
        for p in points:
            t = min(max((hz - p[2]) / 0.45, 0.0), 1.0)
            side = "Right" if p[0] > 0 else "Left"
            k = 0.65 * t * min(abs(p[0]) / 0.1, 1.0)
            w = {"Hips": 1.0 - k}
            if k > 0:
                w[side + "UpperLeg"] = k
            out.append(w)
        return out

    def nearest_weights(points, free_below=None):
        ok = np.array([not dominant(w).endswith(("Arm", "Hand")) for w in weights])
        idx = np.nonzero(ok)[0]
        kd = mathutils.kdtree.KDTree(len(idx))
        for k, i in enumerate(idx):
            kd.insert(mathutils.Vector(tuple(verts[i])), k)
        kd.balance()
        out = []
        for p in points:
            if free_below is not None and p[2] < free_below:
                k = min((free_below - p[2]) / 0.3, 1.0)
                out.append({"Hips": 0.7 + 0.3 * k, "Spine": 0.3 * (1 - k)})
                continue
            _, k, _ = kd.find(mathutils.Vector(tuple(p)))
            w = weights[idx[k]]
            # legs drive nothing above the hem: fold them into the hips
            ww = {}
            for bn, x in w.items():
                bn = "Hips" if bn.endswith(("UpperLeg", "LowerLeg", "Foot", "Toes")) else bn
                ww[bn] = ww.get(bn, 0.0) + x
            out.append(ww)
        return out

    if spec.get("collar"):
        # a stand collar hides the coat's neckline edge
        cz = S.head("Neck")[2]
        nk = S.head("Neck")
        n, rows = 64, 4
        cv, cf, cu = [], [], []
        for r in range(rows + 1):
            z = cz - 0.035 + 0.075 * r / rows
            for i in range(n):
                a = 2 * math.pi * i / n
                d = (math.sin(a), math.cos(a), 0.0)
                rad = col.outer_radius((nk[0], nk[1], z), d, 0.07) + 0.004 + 0.012 * (1 - r / rows)
                cv.append((nk[0] + d[0] * rad, nk[1] + d[1] * rad, z))
        for r in range(rows):
            for i in range(n):
                j = (i + 1) % n
                cf.append((r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i))
                cu.append([(i / n * 6, r / rows), ((i + 1) / n * 6, r / rows), ((i + 1) / n * 6, (r + 1) / rows),
                           (i / n * 6, (r + 1) / rows)])
        cw = [{"Neck": 0.5, "UpperChest": 0.5} if p[2] > cz else {"UpperChest": 1.0} for p in cv]
        o = make_obj("Collar", np.array(cv), cf, cu, cw, gltf_mat(name + "_" + spec["collar"]), arm)
        solidify(o, 0.004)

    if spec.get("helmet"):
        hs = spec["helmet"]
        build_helmet(S, col, arm, name, hs)
        write_tres(os.path.join(mdir, hs.get("material", "helmet") + ".tres"),
                   {"resource_name": f'"{name}_{hs.get("material", "helmet")}"',
                    "albedo_color": "Color(0.42, 0.43, 0.45, 1)", "metallic": 0.85, "roughness": 0.38,
                    "cull_mode": 2}, {})

    lantern_at = None
    if spec.get("lantern"):
        lantern_at = build_belt_lantern(S, col, arm, name)
        write_tres(os.path.join(mdir, "iron.tres"),
                   {"resource_name": f'"{name}_iron"', "albedo_color": "Color(0.12, 0.11, 0.1, 1)",
                    "metallic": 0.8, "roughness": 0.55}, {})
        write_tres(os.path.join(mdir, "lanternglass.tres"),
                   {"resource_name": f'"{name}_lanternglass"', "albedo_color": "Color(1, 0.75, 0.45, 1)",
                    "emission_enabled": "true", "emission": "Color(1, 0.6, 0.28, 1)",
                    "emission_energy_multiplier": 3.0, "roughness": 0.3}, {})

    if spec.get("spear"):
        build_spear(human, arm, name)
        write_tres(os.path.join(mdir, "shaft.tres"),
                   {"resource_name": f'"{name}_shaft"', "albedo_color": "Color(0.26, 0.18, 0.11, 1)",
                    "roughness": 0.75}, {})
        write_tres(os.path.join(mdir, "steel.tres"),
                   {"resource_name": f'"{name}_steel"', "albedo_color": "Color(0.55, 0.56, 0.58, 1)",
                    "metallic": 0.9, "roughness": 0.3}, {})

    if spec.get("dagger"):
        build_dagger(human, arm, name)
        write_tres(os.path.join(mdir, "handle.tres"),
                   {"resource_name": f'"{name}_handle"', "albedo_color": "Color(0.09, 0.06, 0.045, 1)",
                    "roughness": 0.7}, {})
        write_tres(os.path.join(mdir, "obsidian.tres"),
                   {"resource_name": f'"{name}_obsidian"', "albedo_color": "Color(0.015, 0.014, 0.018, 1)",
                    "roughness": 0.05, "metallic_specular": 0.9, "clearcoat_enabled": "true", "clearcoat": 1.0,
                    "clearcoat_roughness": 0.02}, {})

    if spec.get("skirt"):
        sk = spec["skirt"]
        v, f, uv = build_skirt(S, col, sk)
        o = make_obj("Skirt", v, f, [[(a * 6, b * 2) for a, b in u] for u in uv],
                     skirt_weights(v), gltf_mat(name + "_" + sk["material"]), arm)
        subdivide(o, 1)
        solidify(o, 0.004)

    if spec.get("cloak"):
        c = spec["cloak"]
        v, f, uv = cloak_geo
        cw = nearest_weights(v, free_below=S.head("Spine")[2])
        cw = chain_weights(v, cw, chains, c)
        o = make_obj("Cloak", v, f, uv, cw,
                     gltf_mat(name + "_cloak"), arm)
        subdivide(o, 1)
        solidify(o, 0.004)
        write_tres(os.path.join(mdir, "cloak.tres"),
                   {"resource_name": f'"{name}_cloak"', "cull_mode": 2, "roughness": 1.0,
                    "albedo_color": fabric_tint(c["color"]),
                    "normal_enabled": "true", "normal_scale": 0.9, "uv1_scale": "Vector3(2, 2, 1)",
                    "texture_filter": 5},
                   shared_fabric("cloak"))

    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        bind(o, arm)

    rig = Rig(S)
    anims = make_anims(spec["style"], S)
    bake_actions(arm, rig, anims)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_skins=True, export_influence_nb=4,
        export_yup=True, export_optimize_animation_size=True, export_reset_pose_bones=True,
        export_def_bones=False, export_leaf_bone=False, export_rest_position_armature=True,
        export_materials="EXPORT", export_image_format="NONE", export_normals=True,
        export_tangents=True, export_texcoords=True, export_extras=False, export_morph=False,
        export_vertex_color="NONE")

    tris = sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == "MESH" for p in o.data.polygons)
    hand = {1: "RightHand", -1: "LeftHand"}
    sockets = {}
    for side, key in ((1, "hand_r"), (-1, "hand_l")):
        b = hand[side]
        sockets[key] = dict(bone=b, pos=[float(x) for x in (S.head(b) * 0.4 + S.tail(b) * 0.6)])
    sockets["chest"] = dict(bone="UpperChest", pos=[0.0, float(S.head("UpperChest")[1] + 0.12),
                                                   float(S.head("UpperChest")[2] + 0.1)])
    sockets["head"] = dict(bone="Head", pos=[float(x) for x in S.head("Head") + np.array([0, 0, 0.1])])
    if lantern_at is not None:
        sockets["lantern"] = dict(bone="Hips", pos=[float(x) for x in lantern_at])
    mats = sorted({m.name for o in bpy.context.scene.objects if o.type == "MESH" for m in o.data.materials})
    meta = dict(name=name, style=spec["style"], tris=tris, height=float(max(v.co.z for v in body.data.vertices)),
                garments={}, tris_max=tris, materials=mats, tassel_chains=[ch["bones"] for ch in chains], sockets=sockets,
                loops=sorted(LOOPING), animations=ANIM_NAMES, realistic=True)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(f"[{name}] tris={tris} mats={mats} ({time.time() - t0:.1f}s)")
    return meta


def write_godot_files(name, meta):
    import godot_files as gf
    path = os.path.join(OUT, name + ".glb.import")
    mats = {m: {"use_external/enabled": True,
                "use_external/path": f"{RES}/materials/{name}/{m.removeprefix(name + '_')}.tres"}
            for m in meta["materials"]}
    sub = "_subresources=" + gf._godot_str({"materials": mats})
    txt = "\n".join([
        "[remap]", "", 'importer="scene"', "importer_version=1", 'type="PackedScene"', "",
        "[deps]", "", f'source_file="{RES}/{name}.glb"', "",
        "[params]", "", "meshes/generate_lods=true", "meshes/create_shadow_meshes=true",
        "meshes/ensure_tangents=true", "skins/use_named_skins=true", "animation/import=true",
        "animation/fps=30", "animation/remove_immutable_tracks=true", sub, ""])
    with open(path, "w") as f:
        f.write(txt)
    gf.write_scene(name, meta)


if __name__ == "__main__":
    for n in [a for a in sys.argv[1:] if a in SPECS] or list(SPECS):
        write_godot_files(n, build(n))

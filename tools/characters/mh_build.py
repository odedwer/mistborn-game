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
    "kelsier_hd": dict(
        style="kelsier",
        body=dict(gender=1.0, age=0.56, muscle=0.66, weight=0.42, height=0.64, proportions=0.75),
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
        skirt=dict(material="coat", hem_z=0.62, flare=0.08, front_gap=28.0),
        cloak=dict(color=(0.17, 0.18, 0.19), hem_z=0.36, split_z=1.05, strips=22),
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
    if kind == "boots":
        if b.endswith(("Foot", "Toes")):
            return True
        if b.endswith("LowerLeg"):
            return z < 0.34
        return False
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
    span = math.radians(spec.get("span", 205.0))
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
    return hang(col, top, spec["hem_z"], 36, (0.0, hips[1]), clearance=0.02, flare=spec.get("flare", 0.06),
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
    tx.fabric_maps("leather", spec["color"], os.path.join(tdir, "belt"), size=512, seed=41)
    write_tres(os.path.join(mdir, "belt.tres"),
               {"resource_name": f'"{name}_belt"', "roughness": 1.0, "normal_enabled": "true",
                "uv1_scale": "Vector3(1, 1, 1)", "texture_filter": 5},
               {"albedo_texture": tres("belt_albedo.png"), "normal_texture": tres("belt_normal.png"),
                "roughness_texture": tres("belt_roughness.png")})
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
    human.relax_hands()
    S = human.skeleton()
    arm = build_armature(S)
    verts, faces, fuv, weights = human.body_mesh()

    # garments cut from the body surface
    norms = vertex_normals(verts, faces)
    covered = np.zeros(len(verts), bool)
    garment_objs = []
    for gname, (region, off, kind, col) in spec["garments"].items():
        inside = np.array([region_of(region, verts[i], weights[i], S) for i in range(len(verts))])
        gfaces, guv = [], []
        for f, u in zip(faces, fuv):
            if all(inside[i] for i in f):
                gfaces.append(f)
                guv.append(u)
        ids = sorted({i for f in gfaces for i in f})
        remap = {o: n for n, o in enumerate(ids)}
        gv = verts[ids] + norms[ids] * off
        o = make_obj(gname, gv, [tuple(remap[i] for i in f) for f in gfaces], guv,
                     [weights[i] for i in ids], gltf_mat(name + "_" + gname.lower()), arm)
        sm = o.modifiers.new("Smooth", "LAPLACIANSMOOTH")
        sm.iterations = {"boots": 24}.get(region, 12)
        sm.lambda_factor = 1.5 if region != "boots" else 0.8
        sm.use_volume_preserve = region != "boots"
        sm.use_normalized = True
        apply_mods(o, "Smooth")
        subdivide(o, 1)
        solidify(o, 0.003)
        garment_objs.append(o)
        tx.fabric_maps(kind, col, os.path.join(tdir, gname.lower()), seed=hash(gname) % 1000)
        uvs = {"linen": 22, "wool": 18, "leather": 6}[kind]
        write_tres(os.path.join(mdir, gname.lower() + ".tres"),
                   {"resource_name": f'"{name}_{gname.lower()}"', "cull_mode": 2,
                    "albedo_color": "Color(1, 1, 1, 1)", "roughness": 1.0,
                    "normal_enabled": "true", "normal_scale": 0.8,
                    "uv1_scale": f"Vector3({uvs}, {uvs}, 1)",
                    "roughness_texture_channel": 0, "texture_filter": 5},
                   {"albedo_texture": tres(gname.lower() + "_albedo.png"),
                    "normal_texture": tres(gname.lower() + "_normal.png"),
                    "roughness_texture": tres(gname.lower() + "_roughness.png")})
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
    tx.skin_maps(mh.skin_texture(spec["skin"]), os.path.join(tdir, "skin"), tint=spec["skin_tint"])
    write_tres(os.path.join(mdir, "skin.tres"),
               {"resource_name": f'"{name}_skin"', "roughness": 1.0,
                "normal_enabled": "true", "normal_scale": 0.35,
                "subsurf_scatter_enabled": "true", "subsurf_scatter_strength": 0.35,
                "subsurf_scatter_skin_mode": "true",
                "rim_enabled": "true", "rim": 0.25, "rim_tint": 0.6,
                "texture_filter": 5},
               {"albedo_texture": tres("skin_albedo.png"), "normal_texture": tres("skin_normal.png"),
                "roughness_texture": tres("skin_roughness.png")})

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
    shutil.copy(os.path.join(mh.DATA, "proxies", "eyes", "HighPolyEyes", "textures", spec["eyes"] + "_eye.png"),
                os.path.join(tdir, "eyes.png"))
    write_tres(os.path.join(mdir, "eyes.tres"),
               {"resource_name": f'"{name}_eyes"', "roughness": 0.08, "metallic_specular": 0.7,
                "clearcoat_enabled": "true", "clearcoat": 1.0, "clearcoat_roughness": 0.02},
               {"albedo_texture": tres("eyes.png")})
    hair_name, hair_tint = spec["hair"]
    for rel, label, dst, tint in (
            (f"eyebrows/{spec['brows']}/{spec['brows']}.json", "Brows", "brows.png", hair_tint),
            (f"eyelashes/{spec['lashes']}/{spec['lashes']}.json", "Lashes", "lashes.png", (0.09, 0.07, 0.055)),
            (f"hair/{hair_name}/{hair_name}.json", "Hair", "hair.png", hair_tint)):
        proxy(rel, label, dst, tint=tint)
        write_tres(os.path.join(mdir, label.lower() + ".tres"),
                   {"resource_name": f'"{name}_{label.lower()}"', "transparency": 3,  # alpha hash
                    "cull_mode": 2, "roughness": 0.75, "metallic_specular": 0.25,
                    "texture_filter": 5, "alpha_antialiasing_mode": 0},
                   {"albedo_texture": tres(dst)})

    # draped pieces: coat skirt and mistcloak, resting on the dressed body
    col = Collider(verts, faces, weights, pad=0.014, shoulder_z=S.head("LeftUpperArm")[2] - 0.05)
    if spec.get("belt"):
        build_belt(S, col, arm, name, spec["belt"], tdir, mdir, tres)

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

    if spec.get("skirt"):
        sk = spec["skirt"]
        v, f, uv = build_skirt(S, col, sk)
        o = make_obj("Skirt", v, f, [[(a * 6, b * 2) for a, b in u] for u in uv],
                     nearest_weights(v, free_below=S.head("Hips")[2] - 0.05), gltf_mat(name + "_" + sk["material"]), arm)
        subdivide(o, 1)
        solidify(o, 0.004)

    if spec.get("cloak"):
        c = spec["cloak"]
        v, f, uv = build_cloak(S, col, arm, c, None)
        o = make_obj("Cloak", v, f, uv, nearest_weights(v, free_below=S.head("Spine")[2]),
                     gltf_mat(name + "_cloak"), arm)
        subdivide(o, 1)
        solidify(o, 0.004)
        tx.fabric_maps("cloak", c["color"], os.path.join(tdir, "cloak"), seed=17)
        write_tres(os.path.join(mdir, "cloak.tres"),
                   {"resource_name": f'"{name}_cloak"', "cull_mode": 2, "roughness": 1.0,
                    "normal_enabled": "true", "normal_scale": 0.9, "uv1_scale": "Vector3(2, 2, 1)",
                    "texture_filter": 5},
                   {"albedo_texture": tres("cloak_albedo.png"), "normal_texture": tres("cloak_normal.png"),
                    "roughness_texture": tres("cloak_roughness.png")})

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
    mats = sorted({m.name for o in bpy.context.scene.objects if o.type == "MESH" for m in o.data.materials})
    meta = dict(name=name, style=spec["style"], tris=tris, height=float(max(v.co.z for v in body.data.vertices)),
                garments={}, tris_max=tris, materials=mats, tassel_chains=[], sockets=sockets,
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

"""Builds all character GLBs with Blender-as-a-module (bpy 4.5).

Usage (from the repo root):
    tools/characters/build.sh [name ...]      # wrapper: venv setup + build + import
    tools/characters/.venv-bpy/bin/python tools/characters/build_characters.py [name ...]

Outputs assets/models/characters/<name>.glb (+ <name>.tscn wrapper scenes).
"""
from __future__ import annotations

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "characters")

import bpy  # noqa: E402
import mathutils  # noqa: E402
import numpy as np  # noqa: E402

from anim import ANIM_NAMES, FPS, LOOPING, Rig, make_anims  # noqa: E402
from body import MAT_NAMES  # noqa: E402
import chars  # noqa: E402
import chars_npc  # noqa: E402

BUILDERS = {**chars.BUILDERS, **chars_npc.BUILDERS}

MAT_PBR = {  # name: (base rgba, metallic, roughness, emission)
    "Cloth": ((0.5, 0.5, 0.5, 1), 0.0, 0.85, None),
    "Cloak": ((0.35, 0.36, 0.38, 1), 0.0, 0.9, None),
    "Metal": ((0.7, 0.72, 0.75, 1), 0.9, 0.32, None),
    "Obsidian": ((0.02, 0.02, 0.03, 1), 0.0, 0.08, None),
    "Glow": ((1.0, 0.75, 0.4, 1), 0.0, 0.5, (1.0, 0.7, 0.35)),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.render.fps_base = 1.0


def make_material(name):
    base, metal, rough, emit = MAT_PBR[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    # The vertex colour is deliberately NOT linked in the node tree: with export_vertex_color
    # ="ACTIVE" the exporter then writes the active attribute as RGBA COLOR_0, keeping the
    # alpha dye-slot tags (body.dyed). Godot replaces these materials with the external
    # .tres ones, which read COLOR directly.
    if name == "Cloak":
        mat.use_backface_culling = False
    return mat


def build_armature(S):
    arm = bpy.data.armatures.new("Armature")
    obj = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name in S.order:
        parent, head, tail = S.bones[name]
        b = arm.edit_bones.new(name)
        b.head = mathutils.Vector(head)
        b.tail = mathutils.Vector(tail)
        d = (tail - head)
        d = d / np.linalg.norm(d)
        ref = (0, 0, 1) if abs(d[2]) < 0.7 else (0, 1, 0)
        b.align_roll(mathutils.Vector(ref))
        b.use_deform = True
        if parent:
            b.parent = eb[parent]
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def build_mesh(name, m, arm_obj, matmap):
    me = bpy.data.meshes.new(name)
    verts = [tuple(v) for v in m.verts]
    me.from_pydata(verts, [], [list(f) for f in m.faces])
    me.update()
    # materials
    used = sorted(set(m.face_mat))
    slot_of = {}
    for mi in used:
        mname = matmap[mi]
        if mname not in [x.name for x in me.materials]:
            me.materials.append(bpy.data.materials.get(mname) or make_material(mname))
        slot_of[mi] = [x.name for x in me.materials].index(mname)
    me.polygons.foreach_set("material_index", [slot_of[i] for i in m.face_mat])
    me.polygons.foreach_set("use_smooth", m.face_smooth)
    uv = me.uv_layers.new(name="UVMap")
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    uvs, cols = [], []
    for fi, poly in enumerate(me.polygons):
        for k in range(poly.loop_total):
            uvs += list(m.face_uv[fi][k])
            cols += list(m.face_col[fi][k])
    uv.data.foreach_set("uv", uvs)
    col.data.foreach_set("color", cols)
    me.color_attributes.active_color = col
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    groups = {}
    for b in arm_obj.data.bones:
        groups[b.name] = obj.vertex_groups.new(name=b.name)
    for vi, w in enumerate(m.weights):
        for b, x in w.items():
            groups[b].add([vi], float(x), "REPLACE")
    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    return obj


def bake_actions(arm_obj, rig: Rig, anims):
    bones = arm_obj.data.bones
    rest = {b.name: np.array(b.matrix_local.to_3x3()) for b in bones}
    body_bones = [b for b in rig.order if not b.startswith("Tassel")]
    ad = arm_obj.animation_data_create()
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for name in ANIM_NAMES:
        n, fn, loop = anims[name]
        act = bpy.data.actions.new(name + ("-loop" if loop else ""))
        ad.action = act
        dur = n / FPS
        for f in range(n + 1):
            t = min(f / FPS, dur)
            if loop and f == n:
                t = 0.0 + dur  # periodic functions: identical to t=0
            Q, off = rig.solve(fn(t))
            for b in body_bones:
                R = rest[b]
                L = R.T @ Q[b] @ R
                q = mathutils.Matrix(L.tolist()).to_quaternion()
                pb = arm_obj.pose.bones[b]
                # keep quaternion continuity
                if pb.rotation_quaternion.dot(q) < 0:
                    q.negate()
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            loc = rest["Hips"].T @ off
            ph = arm_obj.pose.bones["Hips"]
            ph.location = mathutils.Vector(loc.tolist())
            ph.keyframe_insert("location", frame=f, group="Hips")
        track = ad.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, 0, act)
        ad.action = None
        for pb in arm_obj.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)


def build(name):
    t0 = time.time()
    reset()
    body, info = BUILDERS[name]()
    matmap = {k: v for k, v in info["mats"].items()}
    m = body.m
    lo, hi = m.bounds()
    arm = build_armature(body.S)
    build_mesh(name.capitalize(), m, arm, matmap)
    for gname, gm in body.garments.items():
        build_mesh("G_" + gname, gm, arm, matmap)
    rig = Rig(body.S)
    anims = make_anims(info["style"], body.S)
    bake_actions(arm, rig, anims)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_skins=True, export_influence_nb=4,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_yup=True,
        export_optimize_animation_size=True, export_reset_pose_bones=True, export_def_bones=False,
        export_leaf_bone=False, export_rest_position_armature=True, export_materials="EXPORT",
        export_image_format="NONE", export_normals=True, export_tangents=False, export_texcoords=True,
        export_extras=False, export_morph=False)
    for side, key in ((1, "hand_r"), (-1, "hand_l")):
        o, _ = body.hand_frame(side)
        body.sockets[key] = (("Right" if side > 0 else "Left") + "Hand", o)
    if "chest" not in body.sockets:
        z = body.S.head("UpperChest")[2]
        body.sockets["chest"] = ("UpperChest", np.array([0.0, 0.1 * body.s, z]))
    body.sockets["head"] = ("Head", body.S.head("Head") + np.array([0, 0, 0.1 * body.s]))
    gtris = {g: gm.tri_count() for g, gm in body.garments.items()}
    used_mats = set(m.face_mat)
    for gm in body.garments.values():
        used_mats |= set(gm.face_mat)
    meta = dict(
        name=name, style=info["style"], tris=m.tri_count(), height=float(hi[2] - lo[2]),
        garments=gtris, tris_max=m.tri_count() + sum(gtris.values()),
        materials=sorted(set(matmap[i] for i in used_mats)),
        tassel_chains=body.extra_chains,
        sockets={k: dict(bone=b, pos=[float(x) for x in p]) for k, (b, p) in body.sockets.items()},
        loops=sorted(LOOPING), animations=ANIM_NAMES,
    )
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(f"[{name}] tris={m.tri_count()} (+garments {gtris}) height={hi[2]-lo[2]:.3f} bones={len(body.S.order)} "
          f"mats={meta['materials']} ({time.time()-t0:.1f}s)")
    return meta


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if a in BUILDERS] or list(BUILDERS)
    for n in names:
        build(n)
    import godot_files
    godot_files.write_all(names)

"""Writes the Godot-side files for the generated characters (plain Python, no bpy):
shared materials, <name>.tscn wrapper scenes and the .glb.import settings
(external materials, LOD generation)."""
from __future__ import annotations

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "characters")
RES = "res://assets/models/characters"

MATERIALS = {
    # file: (shader, params)
    "cloth": ("character.gdshader", dict(roughness=0.86, metallic=0.0, specular=0.35, detail_strength=0.14,
                                         grime_strength=0.18, rim_strength=0.3)),
    "cloak": ("character_cloak.gdshader", dict(roughness=0.92, metallic=0.0, specular=0.3, detail_strength=0.18,
                                               grime_strength=0.2, rim_strength=0.45)),
    "metal": ("character.gdshader", dict(roughness=0.34, metallic=0.7, specular=0.6, detail_strength=0.04,
                                         grime_strength=0.3, rim_strength=0.15)),
    "obsidian": ("character.gdshader", dict(roughness=0.07, metallic=0.0, specular=0.9, detail_strength=0.0,
                                            grime_strength=0.0, rim_strength=0.2)),
    "glow": ("character.gdshader", dict(roughness=0.4, metallic=0.0, specular=0.5, detail_strength=0.0,
                                        grime_strength=0.0, rim_strength=0.0, emission_energy=2.2)),
}
GLTF_TO_FILE = {"Cloth": "cloth", "Cloak": "cloak", "Metal": "metal", "Obsidian": "obsidian", "Glow": "glow"}


def write_materials():
    d = os.path.join(OUT, "materials")
    os.makedirs(d, exist_ok=True)
    for name, (sh, params) in MATERIALS.items():
        lines = ['[gd_resource type="ShaderMaterial" load_steps=2 format=3]', "",
                 f'[ext_resource type="Shader" path="{RES}/materials/{sh}" id="1"]', "",
                 "[resource]", f'resource_name = "{name}"', "render_priority = 0", 'shader = ExtResource("1")']
        for k, v in params.items():
            lines.append(f"shader_parameter/{k} = {v}")
        if name == "glow":
            lines.append("shader_parameter/emission_color = Color(1, 0.62, 0.28, 1)")
        with open(os.path.join(d, name + ".tres"), "w") as f:
            f.write("\n".join(lines) + "\n")


def _subresources(meta):
    mats = {}
    for m in meta["materials"]:
        mats[m] = {"use_external/enabled": True,
                   "use_external/path": f"{RES}/materials/{GLTF_TO_FILE[m]}.tres"}
    return {"materials": mats}


def _godot_str(v):
    """Python -> Godot variant text (dict/bool/str/float)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, dict):
        return "{\n" + ",\n".join(f'"{k}": {_godot_str(x)}' for k, x in v.items()) + "\n}"
    if isinstance(v, str):
        return f'"{v}"'
    return str(v)


def write_import(name, meta):
    path = os.path.join(OUT, name + ".glb.import")
    sub = "_subresources=" + _godot_str(_subresources(meta))
    if os.path.exists(path):
        txt = open(path).read()
        # replace the (possibly multi-line) _subresources value
        txt = re.sub(r"_subresources=\{.*?\n\}\n|_subresources=\{\}\n", lambda m: sub + "\n", txt, flags=re.S)
        txt = re.sub(r"meshes/generate_lods=\w+", "meshes/generate_lods=true", txt)
        txt = re.sub(r"animation/fps=[\d.]+", "animation/fps=30", txt)
    else:
        txt = "\n".join([
            "[remap]", "", 'importer="scene"', "importer_version=1", 'type="PackedScene"', "",
            "[deps]", "", f'source_file="{RES}/{name}.glb"', "",
            "[params]", "", "meshes/generate_lods=true", "meshes/create_shadow_meshes=true",
            "skins/use_named_skins=true", "animation/import=true", "animation/fps=30",
            "animation/remove_immutable_tracks=true", sub, ""])
    with open(path, "w") as f:
        f.write(txt)


def to_godot(p):
    x, y, z = p
    return (x, z, -y)


def _color(hexstr):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, 1)"


def _variant_lines(base, variant):
    """CharacterModel variant exports: garments shown, dye colours (sRGB), scale, crowd pool."""
    try:
        import chars_npc
    except ImportError:  # numpy missing: plain python without the venv
        return []
    lines = []
    pool = chars_npc.POOLS.get(base)
    if variant is None:
        variant = chars_npc.DEFAULT_VARIANTS.get(base)
    if variant is not None:
        garments, dyes, scale = variant
        lines.append("garments = PackedStringArray(" + ", ".join(f'"{g}"' for g in garments) + ")")
        lines.append("dye_colors = Array[Color]([" + ", ".join(_color(c) for c in dyes) + "])")
        lines.append(f"body_scale = {float(scale)}")
    if pool is not None:
        groups = "[" + ", ".join("[" + ", ".join(f'"{g}"' for g in grp) + "]" for grp in pool["garment_groups"]) + "]"
        pals = "[" + ", ".join("[" + ", ".join(_color(c) for c in pal) + "]" for pal in pool["palettes"]) + "]"
        lo, hi = pool["scale"]
        lines.append('variant_pool = {\n"garment_groups": ' + groups + ',\n"palettes": ' + pals +
                     f',\n"scale": Vector2({lo}, {hi})\n}}')
    return lines


def write_scene(name, meta, base=None, variant=None):
    # The glTF faces -Z; the Model child is rotated 180 degrees so the CharacterModel root
    # faces +Z (the convention of player.gd / enemy_base.gd: yaw = atan2(dir.x, dir.z)).
    base = base or name
    socks = {}
    for k, s in meta["sockets"].items():
        x, y, z = to_godot(s["pos"])
        x, z = -x, -z  # sockets are in root space (model rotated 180 deg)
        socks[k] = f'["{s["bone"]}", Vector3({x:.4f}, {y:.4f}, {z:.4f})]'
    sock_txt = "{\n" + ",\n".join(f'"{k}": {v}' for k, v in socks.items()) + "\n}"
    node = "".join(p.capitalize() for p in name.split("_"))
    lines = [
        '[gd_scene load_steps=3 format=3]', "",
        f'[ext_resource type="Script" path="{RES}/character_model.gd" id="1"]',
        f'[ext_resource type="PackedScene" path="{RES}/{base}.glb" id="2"]', "",
        f'[node name="{node}" type="Node3D"]',
        'script = ExtResource("1")',
        f'character_id = &"{name}"',
        f"sockets = {sock_txt}",
        f"lantern_light = {'true' if 'lantern' in meta['sockets'] else 'false'}",
    ] + _variant_lines(base, variant) + [
        "",
        '[node name="Model" parent="." instance=ExtResource("2")]',
        "transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)", "",
    ]
    with open(os.path.join(OUT, name + ".tscn"), "w") as f:
        f.write("\n".join(lines))


def write_all(names=None):
    write_materials()
    try:
        from chars_npc import PRESETS
    except ImportError:
        PRESETS = {}
    for fn in sorted(os.listdir(OUT)):
        if not fn.endswith(".json"):
            continue
        name = fn[:-5]
        if names and name not in names:
            continue
        meta = json.load(open(os.path.join(OUT, fn)))
        write_import(name, meta)
        write_scene(name, meta)
        for pid, (base, garments, dyes, scale) in PRESETS.items():
            if base == name:
                write_scene(pid, meta, base=base, variant=(garments, dyes, scale))


if __name__ == "__main__":
    import sys
    write_all(sys.argv[1:] or None)

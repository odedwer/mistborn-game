#!/usr/bin/env python3
"""Optional helper to download extra CC0 reference/production assets from
Poly Haven, for a developer running this on a machine with normal internet
access (this repo's build/dev sandbox blocks polyhaven.com and friends).

This is entirely optional: the game ships fully playable with the procedural
assets from gen_textures.py / gen_audio.py. Use this script if you want
higher-fidelity real-world PBR textures or an HDRI for lighting reference.

Everything it downloads is CC0 (public domain) per Poly Haven's license, and
is written to `assets/external/`, which is gitignored -- nothing downloaded
here is committed to the repo.

Usage:
    pip install -r tools/requirements.txt requests
    python3 tools/fetch_assets.py --list
    python3 tools/fetch_assets.py --textures cobblestone_02,brick_wall_001 --res 2k
    python3 tools/fetch_assets.py --hdri qwantani_dusk_2 --res 2k

Writes assets/external/manifest.json recording what was fetched, its Poly
Haven id, resolution and license, so provenance stays clear.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

API_ROOT = "https://api.polyhaven.com"
FILES_ROOT = "https://api.polyhaven.com/files"


def _require_requests():
    try:
        import requests  # noqa: F401
        return requests
    except ImportError:
        print("This script needs the 'requests' package: pip install requests", file=sys.stderr)
        sys.exit(1)


def list_assets(asset_type: str):
    requests = _require_requests()
    resp = requests.get(f"{API_ROOT}/assets", params={"type": asset_type}, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    for slug, info in sorted(data.items()):
        print(f"{slug}\t{info.get('name', '')}\t{','.join(info.get('categories', []))}")


def fetch_texture(slug: str, res: str, out_dir: str, manifest: dict):
    requests = _require_requests()
    files_resp = requests.get(f"{FILES_ROOT}/{slug}", timeout=30)
    files_resp.raise_for_status()
    files = files_resp.json()
    dest_dir = os.path.join(out_dir, "textures", slug)
    os.makedirs(dest_dir, exist_ok=True)
    maps_written = []
    for map_name, resolutions in files.items():
        if map_name in ("blend", "gltf", "usd"):
            continue  # skip full scene/material bundles, we just want maps
        if not isinstance(resolutions, dict) or res not in resolutions:
            continue
        variant = resolutions[res]
        # Prefer a plain PNG/JPG entry over exr where available.
        fmt_key = "png" if "png" in variant else next(iter(variant), None)
        if fmt_key is None:
            continue
        url = variant[fmt_key]["url"]
        ext = url.split(".")[-1]
        dest = os.path.join(dest_dir, f"{map_name}.{ext}")
        print(f"  downloading {slug}/{map_name} ({res}) ...")
        r = requests.get(url, timeout=120)
        r.raise_for_status()
        with open(dest, "wb") as f:
            f.write(r.content)
        maps_written.append(dest)
    manifest.setdefault("textures", {})[slug] = {
        "resolution": res,
        "files": maps_written,
        "source": f"https://polyhaven.com/a/{slug}",
        "license": "CC0",
    }


def fetch_hdri(slug: str, res: str, out_dir: str, manifest: dict):
    requests = _require_requests()
    files_resp = requests.get(f"{FILES_ROOT}/{slug}", timeout=30)
    files_resp.raise_for_status()
    files = files_resp.json()
    hdri_variants = files.get("hdri", {}).get(res, {})
    if not hdri_variants:
        print(f"  no '{res}' hdri found for {slug}", file=sys.stderr)
        return
    fmt_key = "hdr" if "hdr" in hdri_variants else next(iter(hdri_variants))
    url = hdri_variants[fmt_key]["url"]
    dest_dir = os.path.join(out_dir, "hdri")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, f"{slug}.{fmt_key}")
    print(f"  downloading hdri {slug} ({res}) ...")
    r = requests.get(url, timeout=180)
    r.raise_for_status()
    with open(dest, "wb") as f:
        f.write(r.content)
    manifest.setdefault("hdris", {})[slug] = {
        "resolution": res,
        "file": dest,
        "source": f"https://polyhaven.com/a/{slug}",
        "license": "CC0",
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="assets/external")
    ap.add_argument("--res", default="2k", help="Resolution, e.g. 1k, 2k, 4k")
    ap.add_argument("--list", metavar="TYPE", nargs="?", const="textures",
                     help="List available Poly Haven assets of TYPE (textures|hdris|models) and exit")
    ap.add_argument("--textures", default="", help="Comma-separated Poly Haven texture slugs to fetch")
    ap.add_argument("--hdri", default="", help="Comma-separated Poly Haven HDRI slugs to fetch")
    args = ap.parse_args()

    if args.list:
        type_map = {"textures": "textures", "hdris": "hdris", "models": "models"}
        list_assets(type_map.get(args.list, args.list))
        return

    manifest_path = os.path.join(args.out, "manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = json.load(f)

    os.makedirs(args.out, exist_ok=True)

    for slug in filter(None, args.textures.split(",")):
        fetch_texture(slug.strip(), args.res, args.out, manifest)

    for slug in filter(None, args.hdri.split(",")):
        fetch_hdri(slug.strip(), args.res, args.out, manifest)

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"Manifest written to {manifest_path}")


if __name__ == "__main__":
    main()

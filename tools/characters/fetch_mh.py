"""Fetches the MakeHuman base mesh, morph targets, skins and proxies into
tools/characters/.mh-data (gitignored), for mh_human.py.

Sources (both reachable from the build sandbox, which allows only the package
registries):
  * npm `makehuman-data-v1` 0.0.2: the hm08 base mesh, skeleton weights, skins
    and proxies (hair, eyes, eyebrows, eyelashes) as three.js JSON + PNG.
  * PyPI `makehuman` 1.3.2: data/targets.npz, every morph target.

The MakeHuman base mesh, targets and the system assets used here are CC0
since MakeHuman 1.1 (see LICENSE-ASSETS.md). Only the files the character
build reads are kept.

Usage: tools/characters/.venv-bpy/bin/python tools/characters/fetch_mh.py
"""
from __future__ import annotations

import io
import os
import shutil
import tarfile
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, ".mh-data")
NPM = "https://registry.npmjs.org/makehuman-data-v1/-/makehuman-data-v1-0.0.2.tgz"

# npm paths (under package/public/data/) the build reads
KEEP = ("models/human_full_size.json", "skins/", "proxies/hair/", "proxies/eyes/",
        "proxies/eyebrows/", "proxies/eyelashes/", "proxies/teeth/", "proxies/tongue/")


def _get(url: str) -> bytes:
    print("fetching", url)
    with urllib.request.urlopen(url, timeout=900) as r:
        return r.read()


def _pypi_wheel_url() -> str:
    import json
    meta = json.loads(_get("https://pypi.org/pypi/makehuman/1.3.2/json"))
    return next(u["url"] for u in meta["urls"] if u["filename"].endswith(".whl"))


def main() -> None:
    os.makedirs(DATA, exist_ok=True)
    if not os.path.exists(os.path.join(DATA, "targets.npz")):
        z = zipfile.ZipFile(io.BytesIO(_get(_pypi_wheel_url())))
        with z.open("makehuman/data/targets.npz") as src, \
                open(os.path.join(DATA, "targets.npz"), "wb") as dst:
            shutil.copyfileobj(src, dst)
    if not os.path.exists(os.path.join(DATA, "models", "human_full_size.json")):
        with tarfile.open(fileobj=io.BytesIO(_get(NPM)), mode="r:gz") as t:
            for m in t.getmembers():
                rel = m.name.removeprefix("package/public/data/")
                if not m.isfile() or rel == m.name or not rel.startswith(KEEP):
                    continue
                out = os.path.join(DATA, rel)
                os.makedirs(os.path.dirname(out), exist_ok=True)
                with t.extractfile(m) as src, open(out, "wb") as dst:
                    shutil.copyfileobj(src, dst)
    print("MakeHuman data in", DATA)


if __name__ == "__main__":
    main()

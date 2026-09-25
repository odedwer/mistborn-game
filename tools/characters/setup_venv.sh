#!/usr/bin/env bash
# Creates tools/characters/.venv-bpy with Blender-as-a-module (bpy 4.5.4, needs Python 3.11).
set -euo pipefail
cd "$(dirname "$0")"
python3.11 -m venv .venv-bpy
.venv-bpy/bin/pip install --quiet bpy==4.5.4
.venv-bpy/bin/python -c "import bpy; print('bpy', bpy.app.version_string)"

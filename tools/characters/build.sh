#!/usr/bin/env bash
# Regenerates character GLBs + wrapper scenes, then re-imports the project.
# Usage: tools/characters/build.sh [vin guard hazekiller thug coinshot inquisitor]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -x "$HERE/.venv-bpy/bin/python" ] || "$HERE/setup_venv.sh"
"$HERE/.venv-bpy/bin/python" "$HERE/build_characters.py" "$@"
cd "$HERE/../.."
"${GODOT:-godot}" --headless --import >/dev/null 2>&1 || true

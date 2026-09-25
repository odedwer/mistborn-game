#!/usr/bin/env bash
# Runs the headless test suite. Usage: tools/run_tests.sh [filename-filter]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Import once so class_name globals and resources are registered.
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://tests/run_tests.gd -- "${1:-}"

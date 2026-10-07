#!/usr/bin/env bash
# Runs the headless test suite. Usage: tools/run_tests.sh [filename-filter]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Import once so class_name globals and resources are registered.
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://tests/run_tests.gd -- "${1:-}"
# Weapon and cloth clearance checks of the generated characters (numpy only, ~1 min;
# see tools/characters/clearance.py). Skipped when numpy is missing.
if [ -z "${1:-}" ]; then
	if python3 -c "import numpy" >/dev/null 2>&1; then
		python3 -m unittest discover -s tools/characters -p 'test_*.py'
	else
		echo "skipping tools/characters weapon clearance test (python3 with numpy not found)"
	fi
fi

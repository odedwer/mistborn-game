#!/usr/bin/env bash
# Headless robustness + CPU soak of the full game. Usage: tools/soak.sh [frames] [report.json]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless -s res://tools/soak.gd -- "${1:-3000}" "${2:-}"

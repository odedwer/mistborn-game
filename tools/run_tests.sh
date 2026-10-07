#!/usr/bin/env bash
# Runs the test suite. Usage: tools/run_tests.sh [filename-filter]
#
# - Godot suite (tests/test_*.gd, tests/run_tests.gd): split across TEST_JOBS
#   headless Godot processes ("shards"). They share a claim dir, and each takes
#   the next unclaimed test file (heaviest first), so they balance themselves.
#   Every file still runs all of its tests in order, in one process.
# - Python clearance tests (tools/characters, numpy only; see
#   tools/characters/clearance.py) run at the same time, without a filter
#   only, split over 2 processes by tools/characters/run_parallel.py (about
#   40 s; 70 s in one process). Skipped when numpy is missing.
#
# Each shard's output is printed when the suite finishes (a shard at a time,
# so it stays readable), then the failures again, the totals and the slowest
# files and tests. Any failure, crash or missing summary fails the run.
#
# TEST_JOBS=<n>  Godot processes (default: CPU cores, at most 4; 1 = the old
#                sequential run, its output streamed live).
# TEST_SLOWEST=<n>  rows in the slowest files/tests tables (default 10).
#
# Wall time on a 4-core machine (see docs/PERFORMANCE.md "Test suite"):
# about 2 min with the defaults; about 4.5 min with TEST_JOBS=1.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
FILTER="${1:-}"
if [ -z "${TEST_JOBS:-}" ]; then
	TEST_JOBS=$(nproc 2>/dev/null || echo 2)
	[ "$TEST_JOBS" -gt 4 ] && TEST_JOBS=4
fi
[ "$TEST_JOBS" -lt 1 ] && TEST_JOBS=1
t_start=$(date +%s)

work=$(mktemp -d "${TMPDIR:-/tmp}/mistborn_tests.XXXXXX")
py_pid=""
cleanup() {
	[ -n "$py_pid" ] && kill "$py_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT

# Import once so class_name globals and resources are registered.
"$GODOT" --headless --import >/dev/null 2>&1 || true

# Python clearance tests, in the background.
py_status=0
py_ran=0
if [ -z "$FILTER" ]; then
	if python3 -c "import numpy" >/dev/null 2>&1; then
		python3 tools/characters/run_parallel.py -j 2 >"$work/python.log" 2>&1 &
		py_pid=$!
		py_ran=1
	else
		echo "skipping tools/characters weapon clearance test (python3 with numpy not found)"
	fi
fi

godot_status=0
if [ "$TEST_JOBS" -eq 1 ]; then
	"$GODOT" --headless -s res://tests/run_tests.gd -- "$FILTER" || godot_status=$?
else
	echo "Godot suite: $TEST_JOBS shards${FILTER:+, filter '$FILTER'}..."
	mkdir "$work/claims"
	pids=()
	for i in $(seq 1 "$TEST_JOBS"); do
		"$GODOT" --headless -s res://tests/run_tests.gd -- "$FILTER" --claim-dir="$work/claims" \
			>"$work/shard$i.log" 2>&1 &
		pids+=($!)
	done
	codes=()
	for i in $(seq 1 "$TEST_JOBS"); do
		code=0
		wait "${pids[$((i - 1))]}" || code=$?
		codes+=("$code")
	done
	passed=0
	failed=0
	files_run=0
	for i in $(seq 1 "$TEST_JOBS"); do
		log="$work/shard$i.log"
		echo
		echo "===== Godot shard $i/$TEST_JOBS (exit ${codes[$((i - 1))]}) ====="
		grep -v -E '^TIME[FT] ' "$log" || true
		summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$log" | tail -1 || true)
		if [ -z "$summary" ]; then
			echo "FAIL  shard $i ended without a summary (crashed?)"
			godot_status=1
		else
			passed=$((passed + $(echo "$summary" | cut -d' ' -f1)))
			failed=$((failed + $(echo "$summary" | cut -d' ' -f3)))
			n=$(grep -E '^files run: [0-9]+$' "$log" | tail -1 | cut -d' ' -f3)
			files_run=$((files_run + ${n:-0}))
		fi
		[ "${codes[$((i - 1))]}" -ne 0 ] && godot_status=1
	done
	[ "$failed" -gt 0 ] && godot_status=1
	# Every matching test file must have been run by some shard.
	expected=$( (cd tests && ls test_*.gd | grep -v '^test_case\.gd$' | grep -F -- "$FILTER" | wc -l) || true)
	echo
	echo "===== Godot suite: $passed passed, $failed failed, $files_run files ($TEST_JOBS shards) ====="
	grep -h -E '^FAIL ' "$work"/shard*.log || true
	if [ "$files_run" -ne "$expected" ]; then
		echo "FAIL  the shards ran $files_run test files, expected $expected"
		godot_status=1
	fi
	rows="${TEST_SLOWEST:-10}"
	echo "Slowest files:"
	grep -h '^TIMEF ' "$work"/shard*.log | sort -k2 -g -r | head -n "$rows" | sed 's/^TIMEF /  /' || true
	echo "Slowest tests:"
	grep -h '^TIMET ' "$work"/shard*.log | sort -k2 -g -r | head -n "$rows" | sed 's/^TIMET /  /' || true
fi

if [ "$py_ran" -eq 1 ]; then
	wait "$py_pid" || py_status=$?
	py_pid=""
	echo
	echo "===== Python clearance tests (tools/characters) ====="
	cat "$work/python.log"
fi

echo
echo "Total wall time: $(($(date +%s) - t_start)) s"
if [ "$godot_status" -ne 0 ] || [ "$py_status" -ne 0 ]; then
	echo "TESTS FAILED (godot exit $godot_status, python exit $py_status)"
	exit 1
fi

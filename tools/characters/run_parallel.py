"""Runs the tools/characters unittest suite split across processes.

Usage: python3 tools/characters/run_parallel.py [-j N]   (default 2)

Every test class found by `unittest discover -p 'test_*.py'` goes to one of
N `python3 -m unittest` processes, the heaviest classes first (each class runs
whole, in one process, so its per-module caches still work). A class's weight
is its `WEIGHT` attribute (rough seconds on an idle machine; 1.0 if unset):
the long scans in test_clearance.py are one class per character, or per share
of a character's clips, so they spread over the processes. Outputs are
printed one process at a time; the exit code is non-zero if any process
fails. tools/run_tests.sh runs this alongside the Godot suite.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def classes() -> dict[str, float]:
    """Test class ids ("module.Class") and their weights, in discovery order."""
    out: dict[str, float] = {}

    def walk(s: unittest.TestSuite) -> None:
        for t in s:
            if isinstance(t, unittest.TestSuite):
                walk(t)
            else:
                # A module that fails to import shows up as
                # unittest.loader._FailedTest.<module>: run the module, so
                # unittest reports the error.
                tid = t.id()
                cls = tid.rsplit(".", 1)[-1] if tid.startswith("unittest.loader.") else tid.rsplit(".", 1)[0]
                if cls not in out:
                    out[cls] = float(getattr(type(t), "WEIGHT", 1.0))

    walk(unittest.defaultTestLoader.discover(HERE, pattern="test_*.py", top_level_dir=HERE))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", "--jobs", type=int, default=2)
    args = ap.parse_args()
    weights = classes()
    names = sorted(weights, key=lambda c: (-weights[c], c))
    groups: list[list[str]] = [[] for _ in range(max(1, min(args.jobs, len(names))))]
    load = [0.0] * len(groups)
    for c in names:
        i = load.index(min(load))
        groups[i].append(c)
        load[i] += weights[c]
    t0 = time.time()
    procs = [subprocess.Popen([sys.executable, "-m", "unittest", *g], cwd=HERE, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True) for g in groups]
    status = 0
    for g, p in zip(groups, procs):
        out, _ = p.communicate()
        print(f"--- {', '.join(g)} (exit {p.returncode})")
        print(out, end="")
        status = status or p.returncode
    print(f"--- clearance tests: {len(groups)} processes, {time.time() - t0:.1f} s, {'OK' if status == 0 else 'FAILED'}")
    return status


if __name__ == "__main__":
    sys.exit(main())

"""Weapon clearance regression test for the armed characters (numpy only).

Run: python3 -m unittest discover -s tools/characters -p 'test_*.py'
     (or pytest tools/characters/test_clearance.py). About 15 s.
tools/run_tests.sh runs it after the Godot suite when numpy is installed.
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import clearance  # noqa: E402
from anim import base_params  # noqa: E402


class GeometryTest(unittest.TestCase):
    def test_capsule_distance(self):
        P = np.array([[0.0, 0.1, 0.5], [0.0, 0.0, 1.3], [0.0, 0.005, 0.2]])
        A, C, R = np.array([[0.0, 0.0, 0.0]]), np.array([[0.0, 0.0, 1.0]]), np.array([0.01])
        self.assertAlmostEqual(clearance._caps_dist(P[:1], A, C, R), 0.09)
        self.assertAlmostEqual(clearance._caps_dist(P[1:2], A, C, R), 0.29)
        self.assertAlmostEqual(clearance._caps_dist(P, A, C, R), -0.005)

    def test_disc_distance(self):
        c, n = np.zeros(3), np.array([1.0, 0.0, 0.0])
        P = np.array([[0.05, 0.0, 0.0], [0.0, 0.0, 0.5], [0.0, 0.1, 0.0]])
        d = clearance._disc_dist(P, c, n, 0.3, 0.015)
        np.testing.assert_allclose(d, [0.035, 0.2, 0.0], atol=1e-9)


class ClearanceTest(unittest.TestCase):
    def test_regions_found(self):
        """Every armed character is sampled in the regions it has."""
        expect = {"guard": {"skirt"}, "hazekiller": {"skirt", "shield"}, "thug": set(),
                  "inquisitor": {"skirt"}}
        for name, extra in expect.items():
            regs = set(clearance.Character(name).regions())
            self.assertEqual(regs, {"head", "neck", "torso", "arms"} | extra, name)

    def test_detects_a_clip(self):
        """Negative control: the thug's club driven behind his back goes through
        his torso and arm, and the check must see it."""
        ch = clearance.Character("thug")
        p = base_params("thug")
        p.update({"r_abd": 35, "r_flex": 165, "r_elbow": 140, "r_wrist": 25})
        res = ch.measure(p)
        self.assertLess(res["torso"], 0.0)
        self.assertLess(res["arms"], 0.0)

    def test_all_clips_clear(self):
        """No animation brings a weapon within 1 cm of the head, neck or torso,
        into an arm or a skirt, or through the hazekiller's shield."""
        fails = clearance.check()
        msg = "\n".join(f"{n} {a} {r}: {v:.3f} m at t={t:.2f} (threshold {lim:.3f})"
                        for n, a, r, v, t, lim in fails)
        self.assertEqual(fails, [], "weapon clips:\n" + msg)


if __name__ == "__main__":
    unittest.main()

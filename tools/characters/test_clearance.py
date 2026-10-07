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
import chars  # noqa: E402
from anim import ANIM_NAMES, base_params, make_anims  # noqa: E402


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

    def test_skirt_cover(self):
        """A skirt covers the legs above its hem, inside its arc only."""
        full = [(0.7, 0.0, None)]
        self.assertTrue(clearance._covered(np.array([0.1, 0.0, 0.8]), full))
        self.assertFalse(clearance._covered(np.array([0.1, 0.0, 0.6]), full))
        slit = [(0.7, 0.0, (100.0, 440.0))]  # open over the front, 80-100 degrees
        self.assertFalse(clearance._covered(np.array([0.0, 0.1, 0.8]), slit))
        self.assertTrue(clearance._covered(np.array([0.0, -0.1, 0.8]), slit))
        self.assertTrue(clearance._covered(np.array([0.1, 0.0, 0.8]), slit))

    def test_shield_boss(self):
        """The hazekiller's shield is the board plus its boss: a point at the
        boss's crown is inside the shield, though clear of the board."""
        b, _ = chars.BUILDERS["hazekiller"]()
        (_, c, n, R, ht), boss = b.shields[0], b.shields[1:]
        self.assertGreaterEqual(len(boss), 2)
        p = (c + n * 0.06 * b.s)[None, :]
        self.assertGreater(clearance._disc_dist(p, c, n, R, ht)[0], 0.03 * b.s)
        self.assertEqual(min(clearance._disc_dist(p, *d[1:])[0] for d in boss), 0.0)


class ClearanceTest(unittest.TestCase):
    def test_regions_found(self):
        """Every armed character is sampled in the regions it has."""
        expect = {"guard": {"skirt"}, "hazekiller": {"skirt", "shield"}, "thug": set(),
                  "inquisitor": {"skirt"}}
        for name, extra in expect.items():
            regs = set(clearance.Character(name).regions())
            self.assertEqual(regs, {"head", "neck", "torso", "arms", "legs"} | extra, name)

    def test_legs_under_skirts(self):
        """Legs are checked only where no skirt covers them: the thug's whole
        leg, the guard's below the tunic, and only the Inquisitor's feet."""
        for name, lo, hi in (("thug", 0.0, 0.9), ("guard", 0.0, 0.45), ("inquisitor", 0.0, 0.1)):
            ch = clearance.Character(name)
            pts = np.concatenate([ch.V[g].mean(axis=1) for g in ch.samples["legs"]])
            top = ch.b.skirts[0][0] if ch.b.skirts else 9.0
            self.assertLess(pts[:, 2].max(), min(top, hi * ch.b.H), name)
            self.assertGreater(pts[:, 2].max(), lo, name)

    def test_every_clip_checked(self):
        """The check scans every clip the builder exports."""
        for name in clearance.ARMED:
            b, info = chars.BUILDERS[name]()
            self.assertEqual(set(make_anims(info["style"], b.S)), set(ANIM_NAMES), name)

    def test_detects_a_clip(self):
        """Negative control: the thug's club driven behind his back goes through
        his torso and arm, and the check must see it."""
        ch = clearance.Character("thug")
        p = base_params("thug")
        p.update({"r_abd": 35, "r_flex": 165, "r_elbow": 140, "r_wrist": 25})
        res = ch.measure(p)
        self.assertLess(res["torso"], 0.0)
        self.assertLess(res["arms"], 0.0)

    def test_detects_a_leg_clip(self):
        """Negative control: in the sprint's knee lift, the guard's spear held
        5 degrees closer to his side than his base carry goes into his thigh."""
        ch = clearance.Character("guard")
        p = ch.anims["sprint"][1](0.4)
        p["r_abd"] = base_params("guard")["r_abd"] - 5
        self.assertLess(ch.measure(p)["legs"], 0.0)

    def test_all_clips_clear(self):
        """No animation brings a weapon within 1 cm of the head, neck or torso,
        into an arm, a leg or a skirt, or through the hazekiller's shield."""
        fails = clearance.check()
        msg = "\n".join(f"{n} {a} {r}: {v:.3f} m at t={t:.2f} (threshold {lim:.3f})"
                        for n, a, r, v, t, lim in fails)
        self.assertEqual(fails, [], "weapon clips:\n" + msg)


if __name__ == "__main__":
    unittest.main()

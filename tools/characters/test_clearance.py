"""Clearance regression tests (numpy only): the armed characters' weapons
against their bodies, every skirted character's legs against its cloth, and
everyone lying dead on the floor.

Run: python3 -m unittest discover -s tools/characters -p 'test_*.py'
     (or pytest tools/characters/test_clearance.py). About a minute.
tools/run_tests.sh runs it (split over 2 processes by run_parallel.py) alongside
the Godot suite when numpy is installed.
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import clearance  # noqa: E402
import chars  # noqa: E402
import anim  # noqa: E402
from anim import ANIM_NAMES, SKIRT_CLASS, base_params, make_anims  # noqa: E402


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

    @staticmethod
    def _cylinder(arc=None, r=0.2, z=(1.0, 0.5), rows=6, n=24):
        """A skirt-like cloth grid: rings from the waist down to the hem, laid
        out as tube() does (0 degrees = -X, 90 = forward)."""
        a0, a1 = (0.0, 360.0) if arc is None else arc
        cols = n if arc is None else n + 1
        th = np.radians(a0 + (a1 - a0) * np.arange(cols) / n)
        zs = np.linspace(z[0], z[1], rows)
        G = np.stack([np.broadcast_to(-r * np.cos(th), (rows, cols)), np.broadcast_to(r * np.sin(th), (rows, cols)),
                      np.broadcast_to(zs[:, None], (rows, cols))], axis=-1)
        sf = clearance.SkirtSurface(None, arc is None, 0.0)
        sf.orient(G)
        return sf, G

    def test_skirt_cover(self):
        """A skirt covers the points inside its cloth: not those outside it,
        below its hem or in front of a front slit."""
        sf, G = self._cylinder()
        P = np.array([[0.1, 0.0, 0.8], [0.25, 0.0, 0.8], [0.1, 0.0, 0.4], [0.0, 0.0, 0.52]])
        np.testing.assert_array_equal(clearance.covered([sf], [G], P), [True, False, False, True])
        d, beyond = sf.classify(P, G)
        self.assertAlmostEqual(d[1], 0.05, delta=0.005)  # 5 cm outside the cloth
        np.testing.assert_array_equal(beyond, [False, False, True, False])
        sf, G = self._cylinder(arc=(100.0, 440.0))  # open over the front, 80-100 degrees
        P = np.array([[0.0, 0.1, 0.8], [0.0, -0.1, 0.8], [0.1, 0.0, 0.8], [0.0, 0.25, 0.8]])
        np.testing.assert_array_equal(clearance.covered([sf], [G], P), [False, True, True, False])
        self.assertTrue(sf.classify(P, G)[1][3])  # out through the slit, not through the cloth

    def test_winding(self):
        """The cloth tube's winding number tells inside from outside (it is
        what overrides the nearest-sample test where the cloth folds)."""
        sf, G = self._cylinder(z=(1.0, 0.0), rows=11)
        w = np.abs(sf.winding(np.array([[0.0, 0.0, 0.5], [0.15, 0.0, 0.6], [0.3, 0.0, 0.5], [0.0, 0.0, 1.4]]), G))
        self.assertGreater(w[0], 0.7)
        self.assertGreater(w[1], 0.5)
        self.assertLess(w[2], 0.2)
        self.assertLess(w[3], 0.2)

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
        """In the rest pose the legs are uncovered only where no skirt hides
        them: the thug's whole leg, the guard's below the tunic, and only the
        Inquisitor's feet below his robe."""
        for name, hi in (("thug", 0.9), ("guard", 0.45), ("inquisitor", 0.1)):
            ch = clearance.Character(name)
            pts = np.concatenate([ch.V[g].mean(axis=1) for g in ch.samples["legs"]])
            if ch.surfs:
                pts = pts[~clearance.covered(ch.surfs, [ch.V[g] for g in ch.grids], pts)]
            top = ch.b.skirts[0][0] if ch.b.skirts else 9.0
            self.assertLess(pts[:, 2].max(), min(top, hi * ch.b.H), name)
            self.assertGreater(len(pts), 100, name)

    def test_posed_cover(self):
        """Skirt coverage follows the pose: a guard's knee raised high past
        his tunic's hem is exposed to the weapon check, though the tunic hides
        it standing."""
        ch = clearance.Character("guard")
        dom = ch.Wm.argmax(axis=1)
        knee = np.where(np.array(ch.bones)[dom] == "RightUpperLeg")[0]
        knee = knee[ch.V[knee, 2] > ch.b.skirts[0][0]]
        grids = [ch.V[g] for g in ch.grids]
        self.assertTrue(clearance.covered(ch.surfs, grids, ch.V[knee]).all())
        p = base_params("guard")
        p.update({"leg_fk": 1.0, "r_lflex": 100, "r_knee": 90})
        Q, off = ch.rig.solve(p)
        D, Hd = clearance._pose(ch.S, Q, off)
        P = clearance._skin(ch.S, D, Hd, ch.bones, ch.V, ch.Wm)
        self.assertFalse(clearance.covered(ch.surfs, [P[g] for g in ch.grids], P[knee]).all())

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


class ClothTest(unittest.TestCase):
    def test_skirted_characters(self):
        """Every robed or skirted character is checked."""
        self.assertEqual(set(clearance.skirted()),
                         {"guard", "hazekiller", "coinshot", "inquisitor", "dockson", "breeze", "clubs", "sazed",
                          "marsh", "elend", "vin_gown", "noble_woman", "obligator", "obligator_2", "skaa_man",
                          "skaa_woman"})

    def test_garment_skirts(self):
        """The skirts of the optional garment meshes are checked too."""
        self.assertEqual(set(clearance.garment_skirted()),
                         {"noble_man:tails", "noble_man:longcoat", "noble_woman:bustle"})

    def test_detects_legs_through_a_garment(self):
        """Negative control: the noble's long coat (a garment mesh) skinned to
        the hips alone shows his crouching knees."""
        ch = clearance.Cloth("noble_man:longcoat")
        p = ch.anims["crouch_idle"][1](0.5)
        self.assertGreater(ch.measure(p), clearance.CLOTH_THRESHOLD)
        hips = ch.bones.index("Hips")
        for W in ch.Wg:
            W[:] = 0.0
            W[:, hips] = 1.0
        self.assertLess(ch.measure(p), -0.05)

    def test_detects_legs_through_a_robe(self):
        """Negative control: a robe that only follows the hips (as the
        Inquisitor's did, mostly) shows his crouching knees by over 10 cm."""
        ch = clearance.Cloth("inquisitor")
        hips = ch.bones.index("Hips")
        p = ch.anims["crouch_idle"][1](0.5)
        self.assertGreater(ch.measure(p), clearance.CLOTH_THRESHOLD)
        for W in ch.Wg:
            W[:] = 0.0
            W[:, hips] = 1.0
        self.assertLess(ch.measure(p), -0.1)

    def test_no_legs_through_cloth(self):
        """No animation shows a leg through a robe, gown, tunic or coat (by
        more than CLOTH_THRESHOLD)."""
        fails = clearance.check_cloth(step=2)
        msg = "\n".join(f"{n} {a}: {v:.3f} m at t={t:.2f}" for n, a, v, t in fails)
        self.assertEqual(fails, [], "legs through cloth:\n" + msg)


class SettleTest(unittest.TestCase):
    def test_settling_characters(self):
        """The long robes and gowns have skirt bones."""
        self.assertEqual(set(clearance.settling()),
                         {"inquisitor", "sazed", "marsh", "vin_gown", "noble_woman", "obligator", "obligator_2"})

    def test_skirt_bones_rest_outside_die(self):
        """The skirt bones stay at rest in every clip but `die`, so the cloth
        moves exactly as it did before they were added."""
        for name in clearance.settling():
            b, info = clearance.BUILDERS[name]()
            A, rig = make_anims(info["style"], b.S), clearance.Rig(b.S)
            for anim, (n, fn, _) in A.items():
                if anim == "die":
                    continue
                for f in range(0, n + 1, 8):
                    Q, _ = rig.solve(fn(f / 30.0))
                    for bone in SKIRT_CLASS:
                        np.testing.assert_allclose(Q[bone], np.eye(3), atol=1e-9, err_msg=f"{name} {anim}")
                        np.testing.assert_allclose(rig.loc[bone], 0.0, atol=1e-9, err_msg=f"{name} {anim}")

    def test_robes_settle(self):
        """Lying in `die`, no robe or gown stands open over the feet or sinks
        through the floor."""
        fails = clearance.check_settle(step=3)
        self.assertEqual(fails, [], "\n".join(f"{n} {w}: {v:.3f} at t={t:.2f} (limit {lim:.3f})"
                                              for n, w, v, t, lim in fails))

    def test_detects_an_unsettled_robe(self):
        """Negative control: without its skirt bone poses the Inquisitor's
        robe lies as a stiff tube, its back 20 cm under the floor."""
        rows = clearance.settle_scan("inquisitor", step=4, settle={"fall": {}, "lie": {}})
        self.assertLess(min(z for _, _, z in rows), -0.15)


class DeadTest(unittest.TestCase):
    def test_everyone_lies_on_the_floor(self):
        """At the end of `die` every character's legs rest on the floor (the
        robed ones under their robes aside), and no part of anyone's body
        sinks through it."""
        fails = clearance.check_dead(step=3)
        self.assertEqual(fails, [], "\n".join(f"{n} {w}: {v:+.3f} at t={t:.2f} (limit {lim:+.3f})"
                                              for n, w, v, t, lim in fails))

    def test_detects_raised_legs(self):
        """Negative control: the old lying legs (left knee raised, feet
        pointed up off the floor) leave Vin's shins and feet 7-12 cm up."""
        old = dict(r_lflex=8, l_lflex=24, r_knee=12, l_knee=40, r_labd=12, l_labd=9, r_ltwist=0, l_ltwist=0,
                   r_ankle=25, l_ankle=25)
        legs = clearance.dead_scan("vin", step=99, params=old)[-1][3]
        self.assertGreater(legs["left shin"], 0.07)
        self.assertGreater(legs["right foot"], 0.05)

    def test_detects_a_head_through_the_floor(self):
        """Negative control: without his DIE_LIE correction the guard's
        helmet brim sinks 8 cm into the floor."""
        saved = anim.DIE_LIE.pop("guard")
        try:
            rows = clearance.dead_scan("guard", step=3)
        finally:
            anim.DIE_LIE["guard"] = saved
        t, z, where, _ = min(rows, key=lambda r: r[1])
        self.assertLess(z, -0.06)
        self.assertEqual(where, "Head")

    def test_thighs_turn_out(self):
        """ltwist turns each thigh out about its own axis: the bent leg's foot
        swings away from the body's midline."""
        b, info = clearance.BUILDERS["vin"]()
        rig = clearance.Rig(b.S)
        p = base_params(info["style"])
        p.update(leg_fk=1.0, l_knee=40, r_knee=40)
        feet = []
        for tw in (0.0, 30.0):
            p.update(l_ltwist=tw, r_ltwist=tw)
            Q, off = rig.solve(p)
            _, Hd = clearance._pose(b.S, Q, off)
            feet.append((Hd["LeftFoot"][0], Hd["RightFoot"][0]))
        self.assertLess(feet[1][0], feet[0][0] - 0.05)
        self.assertGreater(feet[1][1], feet[0][1] + 0.05)


if __name__ == "__main__":
    unittest.main()

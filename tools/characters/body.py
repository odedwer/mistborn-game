"""Shared humanoid skeleton + body-part builders (numpy only)."""
from __future__ import annotations

import math

import numpy as np

from meshkit import (Mesh, Skel, box, clean_weights, frame_from, hexcol, lerp, norm,
                     proximity_weights, ribbon, rot_axis, smoothstep, tube, v3)

# material slots (mapped to <=3 real materials per character)
CLOTH, CLOAK, METAL, GLOSS, GLOW = range(5)
MAT_NAMES = ["Cloth", "Cloak", "Metal", "Gloss", "Glow"]

HUMANOID_BONES = [
    "Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
    "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
    "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]

TORSO_BONES = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "RightShoulder",
               "LeftUpperLeg", "RightUpperLeg"]


def side_name(side: int, base: str) -> str:
    return ("Right" if side > 0 else "Left") + base


class Body:
    """Holds the skeleton, mesh and proportions of one character."""

    def __init__(self, H=1.75, sh_w=0.18, hip_w=0.095, apose=40.0, arm=1.0, leg=1.0,
                 head=1.0, neck=1.0, width=1.0, limb=1.0, female=False):
        self.H, self.s = H, H / 1.75
        self.P = dict(sh_w=sh_w, hip_w=hip_w, apose=apose, arm=arm, leg=leg, head=head,
                      neck=neck, width=width, limb=limb, female=female)
        self.S = Skel()
        self.m = Mesh()
        self.extra_chains: list[list[str]] = []  # tassel bone chains
        self.sockets: dict[str, tuple[str, np.ndarray]] = {}
        self._make_skel()

    # ---------------------------------------------------------------- skeleton
    def _make_skel(self):
        H, s, P = self.H, self.s, self.P
        S = self.S
        z = lambda f: f * H
        hip_z = z(0.555)
        S.add("Root", None, (0, 0, 0), (0, 0.12 * s, 0))
        S.add("Hips", "Root", (0, 0, hip_z), (0, 0, z(0.615)))
        S.add("Spine", "Hips", (0, 0, z(0.615)), (0, 0.004 * s, z(0.685)))
        S.add("Chest", "Spine", (0, 0.004 * s, z(0.685)), (0, 0.0, z(0.755)))
        S.add("UpperChest", "Chest", (0, 0.0, z(0.755)), (0, -0.012 * s, z(0.835)))
        S.add("Neck", "UpperChest", (0, -0.012 * s, z(0.835)), (0, -0.002 * s, z(0.893)))
        S.add("Head", "Neck", (0, -0.002 * s, z(0.893)), (0, -0.002 * s, H))
        a = math.radians(P["apose"])
        for side in (1, -1):
            sx = side
            shj = v3(sx * P["sh_w"] * s, -0.012 * s, z(0.815))
            S.add(side_name(side, "Shoulder"), "UpperChest", (sx * 0.028 * s, -0.004 * s, z(0.80)), shj)
            d = v3(sx * math.sin(a), 0.0, -math.cos(a))
            ua = 0.165 * H * P["arm"]
            fa = 0.148 * H * P["arm"]
            hl = 0.10 * H * P["arm"]
            elb = shj + d * ua + v3(0, -0.012 * s, 0)
            d2 = norm(d + v3(0, 0.07, 0))
            wr = elb + d2 * fa
            S.add(side_name(side, "UpperArm"), side_name(side, "Shoulder"), shj, elb)
            S.add(side_name(side, "LowerArm"), side_name(side, "UpperArm"), elb, wr)
            S.add(side_name(side, "Hand"), side_name(side, "LowerArm"), wr, wr + d2 * hl)
            hw = P["hip_w"] * s
            hipj = v3(sx * hw, 0.0, z(0.525))
            knee = v3(sx * (hw + 0.004 * s), 0.012 * s, z(0.285))
            ank = v3(sx * (hw + 0.008 * s), -0.012 * s, z(0.048))
            ball = v3(sx * (hw + 0.014 * s), 0.118 * s, z(0.012))
            tip = v3(sx * (hw + 0.016 * s), 0.19 * s, z(0.012))
            S.add(side_name(side, "UpperLeg"), "Hips", hipj, knee)
            S.add(side_name(side, "LowerLeg"), side_name(side, "UpperLeg"), knee, ank)
            S.add(side_name(side, "Foot"), side_name(side, "LowerLeg"), ank, ball)
            S.add(side_name(side, "Toes"), side_name(side, "Foot"), ball, tip)

    # ------------------------------------------------------------------ helpers
    def W(self, bones, bias=None, power=5.0, maxinf=3):
        S = self.S
        return lambda p, *a: proximity_weights(S, p, bones, power, bias, maxinf)

    def rigid(self, bone):
        return {bone: 1.0}

    def hand_frame(self, side):
        """Returns (grip_origin, M) with M columns (x: palm normal (out of palm),
        y: fingers, z: grip axis / thumb direction)."""
        S = self.S
        hb = side_name(side, "Hand")
        d = S.dir(hb)
        g = norm(v3(0, 1, 0) - d * d[1])            # thumb / grip axis ~ forward
        pn = norm(np.cross(g, d)) * side             # palm normal (towards body)
        pn = pn if np.dot(pn, v3(-side, 0, 0)) > 0 else -pn
        o = S.head(hb) + d * (S.length(hb) * 0.42) + pn * 0.012 * self.s
        return o, np.column_stack([pn, d, g])

    # --------------------------------------------------------------- body parts
    def torso(self, table, color, mat=CLOTH, n=20, ex=2.2, zmin=None, zmax=None, extra_w=None):
        """table rows: (zf, rx, rf, rb, yc) in metres for H=1.75."""
        s, H, P = self.s, self.H, self.P
        rows = [r for r in table if (zmin is None or r[0] >= zmin) and (zmax is None or r[0] <= zmax)]
        centers = [v3(0, r[4] * s, r[0] * H) for r in rows]
        radii = [(r[1] * s * P["width"], r[1] * s * P["width"], r[2] * s * P["width"], r[3] * s * P["width"])
                 for r in rows]
        bones = TORSO_BONES + (extra_w or [])
        bias = {"LeftUpperLeg": 0.25, "RightUpperLeg": 0.25, "LeftShoulder": 0.5, "RightShoulder": 0.5,
                "Neck": 0.7}
        return tube(self.m, centers, radii, n=n, ex=ex, mat=mat, color=color,
                    weights=self.W(bones, bias), cap0=0.02 * s if zmin is None else None,
                    cap1=None)

    def neck(self, color, r=0.052, top=0.905, bot=0.815):
        s, H = self.s, self.H
        r *= s * self.P["neck"]
        cs = [v3(0, -0.01 * s, bot * H), v3(0, -0.006 * s, 0.86 * H), v3(0, 0.0, top * H)]
        tube(self.m, cs, [(r * 1.15, r * 1.05), (r, r * 0.95), (r * 0.95, r * 0.95)], n=10,
             color=color, weights=self.W(["UpperChest", "Neck", "Head"], {"UpperChest": 0.5}))

    def head(self, skin, *, hair=None, brow=None, lips=None, eye=(0.12, 0.09, 0.08, 1),
             ears=True, jaw=1.0, n=20, gaunt=0.0):
        """Builds head; returns dict of landmark positions."""
        s = self.s * self.P["head"]
        H = self.H
        chin_z = H - 0.232 * s
        # (dz from chin, rx, rf, rb, yc)
        tab = [
            (0.000, 0.020, 0.016, 0.016, 0.066),
            (0.012, 0.038 * jaw, 0.030, 0.036, 0.054),
            (0.035, 0.053 * jaw, 0.052, 0.056, 0.034),
            (0.062, 0.061 - gaunt * 0.008, 0.073, 0.074, 0.017),
            (0.090, 0.067 - gaunt * 0.01, 0.088, 0.090, 0.004),
            (0.118, 0.073, 0.091, 0.094, -0.004),
            (0.142, 0.076, 0.099, 0.100, -0.002),
            (0.168, 0.076, 0.097, 0.099, -0.005),
            (0.192, 0.069, 0.088, 0.090, -0.009),
            (0.212, 0.054, 0.068, 0.070, -0.011),
            (0.226, 0.030, 0.040, 0.040, -0.010),
        ]
        eye_z = chin_z + 0.118 * s
        brow_z = chin_z + 0.138 * s
        mouth_z = chin_z + 0.04 * s
        centers = [v3(0, t[4] * s, chin_z + t[0] * s) for t in tab]
        radii = [(t[1] * s, t[1] * s, t[2] * s, t[3] * s) for t in tab]

        def shape(i, th):
            k = 1.0
            z = centers[i][2]
            for ex_ in (62.0, 118.0):
                dth = (th - ex_) / 13.0
                dz = (z - eye_z) / (0.016 * s)
                k -= 0.075 * math.exp(-(dth * dth + dz * dz))
            # brow ridge
            if 55 < th < 125:
                k += 0.025 * math.exp(-((z - brow_z) / (0.012 * s)) ** 2)
            # cheek hollow for gaunt faces
            if gaunt > 0:
                for cx in (40.0, 140.0):
                    k -= gaunt * 0.07 * math.exp(-(((th - cx) / 15) ** 2 + ((z - (mouth_z + 0.03 * s)) / (0.02 * s)) ** 2))
            return k

        def color(p, i, th):
            z = p[2]
            c = np.array(skin, dtype=float)
            for ex_ in (62.0, 118.0):
                de = ((th - ex_) / 7.0) ** 2 + ((z - eye_z) / (0.007 * s)) ** 2
                c = lerp(c, np.array(eye), 0.85 * math.exp(-de))
            if brow is not None and (48 < th < 80 or 100 < th < 132):
                c = lerp(c, np.array(brow), 0.85 * math.exp(-((z - brow_z - 0.004 * s) / (0.006 * s)) ** 2))
            if lips is not None and 70 < th < 110:
                c = lerp(c, np.array(lips), 0.7 * math.exp(-((z - mouth_z) / (0.007 * s)) ** 2))
            return tuple(c)

        hw = self.W(["Head", "Neck"], {"Neck": 0.05})
        tube(self.m, centers, radii, n=n, ex=2.1, color=color, shape=shape, weights=hw, cap1=0.006 * s,
             cap0=0.004 * s)
        face_y = lambda zz: np.interp(zz, [c[2] for c in centers], [c[1] + r[2] for c, r in zip(centers, radii)])
        # nose
        ny = face_y(eye_z) - 0.006 * s
        nz_tip = chin_z + 0.078 * s
        tube(self.m, [v3(0, ny, eye_z + 0.004 * s), v3(0, ny + 0.01 * s, chin_z + 0.095 * s),
                      v3(0, ny + 0.017 * s, nz_tip)],
             [(0.005 * s, 0.004 * s), (0.007 * s, 0.006 * s), (0.009 * s, 0.008 * s)], n=6,
             hint=(0, 0, -1), color=skin, weights={"Head": 1.0}, cap1=0.006 * s)
        if ears:
            for side in (1, -1):
                ex_x = side * 0.074 * s
                tube(self.m, [v3(ex_x * 0.92, -0.012 * s, eye_z - 0.005 * s), v3(ex_x * 1.12, -0.02 * s, eye_z - 0.005 * s)],
                     [(0.018 * s, 0.009 * s), (0.02 * s, 0.01 * s)], n=6, hint=(0, 0, 1), color=skin,
                     weights={"Head": 1.0}, cap1=0.004 * s)
        lm = dict(chin_z=chin_z, eye_z=eye_z, brow_z=brow_z, top=H, s=s, centers=centers, radii=radii,
                  eye_l=v3(-0.03 * s, face_y(eye_z) - 0.012 * s, eye_z),
                  eye_r=v3(0.03 * s, face_y(eye_z) - 0.012 * s, eye_z))
        self.head_lm = lm
        return lm

    def hair_shell(self, color, *, fringe_z=None, back_z=None, puff=1.12, jag=0.012, n=20, spikes=7):
        """Hair cap built from the head profile, hidden in front below the fringe."""
        lm = self.head_lm
        s = lm["s"]
        fz = fringe_z if fringe_z is not None else lm["brow_z"] + 0.012 * s
        bz = back_z if back_z is not None else lm["chin_z"] + 0.03 * s
        cs, rs = lm["centers"], lm["radii"]
        zs = [c[2] for c in cs]
        rings_z = list(np.linspace(bz, lm["top"] - 0.006 * s, 9))
        centers, radii = [], []
        for z in rings_z:
            yc = np.interp(z, zs, [c[1] for c in cs])
            r = [np.interp(z, zs, [rr[k] for rr in rs]) for k in range(4)]
            centers.append(v3(0, yc - 0.004 * s, z))
            radii.append(tuple(max(x, 0.03 * s) * puff + 0.004 * s for x in r))

        def shape(i, th):
            z = rings_z[i]
            front = math.exp(-((th - 90) / 55.0) ** 2)
            side_ = math.exp(-((th - 90) / 95.0) ** 2)
            k = 1.0
            if z < fz:
                # hide inside the face below the fringe line (front), keep sides/back
                k -= 0.35 * front * smoothstep(fz, fz - 0.03 * s, z)
                k -= 0.12 * side_ * smoothstep(lm["eye_z"], lm["eye_z"] - 0.04 * s, z)
            if i == 0 or (z < fz + 0.01 * s and front > 0.3):
                k += jag / 0.1 * 0.25 * math.sin(math.radians(th) * spikes)
            return k

        tube(self.m, centers, radii, n=n, ex=2.1, color=color, shape=shape,
             weights={"Head": 1.0}, cap1=0.01 * s)

    def arm(self, side, radii_scale=1.0, color=None, sleeve=None, bare_from=None, n=12,
            cuff=None, flare=0.0, skin=None):
        """Arm tube along UpperArm/LowerArm. color(p,i,th) or const."""
        S, s = self.S, self.s * self.P["limb"] * radii_scale
        ua, la = side_name(side, "UpperArm"), side_name(side, "LowerArm")
        sh, el, wr = S.head(ua), S.head(la), S.tail(la)
        d1, d2 = S.dir(ua), S.dir(la)
        pts = [sh - d1 * 0.035 * s, sh + (el - sh) * 0.12, sh + (el - sh) * 0.4, sh + (el - sh) * 0.75,
               el, el + (wr - el) * 0.25, el + (wr - el) * 0.6, wr - d2 * 0.005]
        base = [0.056, 0.058, 0.048, 0.043, 0.039, 0.042, 0.035, 0.027]
        rr = []
        for i, r in enumerate(base):
            r *= s
            if i >= 5:
                r += flare * (i - 4) / 3.0 * self.s
            rr.append((r, r * 0.92))
        bones = [side_name(side, "Shoulder"), ua, la, side_name(side, "Hand"), "UpperChest"]
        bias = {"UpperChest": 0.3, side_name(side, "Shoulder"): 0.6, side_name(side, "Hand"): 0.5}
        tube(self.m, pts, rr, n=n, color=color, hint=(0, 1, 0), weights=self.W(bones, bias), cap1="flat")

    def hand(self, side, color, n=8, scale=1.0, curl=1.0):
        S = self.S
        s = self.s * self.P["limb"] * scale
        hb = side_name(side, "Hand")
        o = S.head(hb)
        d = S.dir(hb)
        L = S.length(hb) * scale
        _, M = self.hand_frame(side)
        pn, g = M[:, 0], M[:, 2]
        # palm + curled fingers (mitten), centreline curling toward the palm side
        ts = [0.0, 0.25, 0.5, 0.72, 0.9, 1.0]
        curlo = [0.0, 0.0, 0.004, 0.018, 0.04, 0.052]
        back = [0.0, 0.0, 0.0, 0.03, 0.08, 0.14]
        pts = [o + d * (t * L - back[i] * L * curl) + pn * curlo[i] * s * curl for i, t in enumerate(ts)]
        rad = [(0.018, 0.026), (0.02, 0.041), (0.019, 0.043), (0.017, 0.041), (0.015, 0.037), (0.012, 0.03)]
        rr = [(a * s, b * s) for a, b in rad]
        fr = [(np.cross(g, norm(d)), g)] * len(pts)
        W = {hb: 1.0}
        tube(self.m, pts, [(r[0], r[1]) for r in rr], n=n, color=color, hint=g, weights=W,
             cap1=0.01 * s, cap0=None, ex=2.4)
        # thumb
        tb = o + d * 0.2 * L + g * 0.03 * s
        tube(self.m, [tb, tb + d * 0.25 * L + g * 0.02 * s + pn * 0.012 * s, tb + d * 0.45 * L + pn * 0.03 * s * curl],
             [0.012 * s, 0.011 * s, 0.0095 * s], n=6, color=color, weights=W, cap1=0.007 * s)

    def leg(self, side, color, n=14, scale=1.0, top_extra=0.0, boot_z=None, boot_col=None, boot_add=0.006,
            thigh=1.0):
        S, s = self.S, self.s * self.P["limb"] * scale
        ul, ll = side_name(side, "UpperLeg"), side_name(side, "LowerLeg")
        hp, kn, an = S.head(ul), S.head(ll), S.tail(ll)
        top = hp + v3(-side * 0.02 * self.s, 0, 0.05 * self.s + top_extra)
        fr = [0.0, 0.2, 0.5, 0.82, 1.0]
        pts = [top] + [hp + (kn - hp) * f for f in fr[1:]] + [kn + (an - kn) * f for f in (0.2, 0.42, 0.7, 0.9)] + [an + v3(0, 0, 0.015 * self.s)]
        # (r_side, r_front, r_back)
        R = [(0.088 * thigh, 0.085 * thigh, 0.09 * thigh), (0.082 * thigh, 0.08 * thigh, 0.084 * thigh),
             (0.07 * thigh, 0.072, 0.07), (0.056, 0.06, 0.054), (0.05, 0.052, 0.05),
             (0.052, 0.05, 0.062), (0.05, 0.046, 0.064), (0.04, 0.04, 0.045), (0.034, 0.035, 0.036),
             (0.034, 0.036, 0.034)]
        radii = []
        for i, (a, f, b) in enumerate(R):
            add = 0.0
            if boot_z is not None and pts[i][2] < boot_z:
                add = boot_add * self.s
            radii.append((a * s + add, a * s + add, f * s + add, b * s + add))

        def col(p, i, th):
            if boot_z is not None and p[2] < boot_z:
                return boot_col
            return color(p, i, th) if callable(color) else color

        bones = ["Hips", ul, ll, side_name(side, "Foot")]
        bias = {"Hips": 0.35, side_name(side, "Foot"): 0.3}
        tube(self.m, pts, radii, n=n, color=col, hint=(0, 1, 0), weights=self.W(bones, bias), cap1="flat")

    def foot(self, side, color, n=10, scale=1.0, sole=None):
        S, s = self.S, self.s * scale * 0.93
        fb, tb = side_name(side, "Foot"), side_name(side, "Toes")
        an, ball, tip = S.head(fb), S.head(tb), S.tail(tb)
        x = an[0]
        pts = [v3(x, an[1] - 0.06 * s, 0.045 * s), v3(x, an[1] - 0.03 * s, 0.055 * s), v3(x, an[1] + 0.02 * s, 0.06 * s),
               v3(ball[0], ball[1] - 0.04 * s, 0.045 * s), v3(ball[0], ball[1], 0.037 * s), v3(tip[0], tip[1] - 0.03 * s, 0.03 * s),
               v3(tip[0], tip[1] + 0.012 * s, 0.026 * s)]
        # (ru, rv+ up, rv- down) -> tube along +Y with hint up: v = up
        rad = [(0.03, 0.03, 0.043), (0.038, 0.035, 0.053), (0.042, 0.036, 0.058), (0.047, 0.026, 0.043),
               (0.049, 0.02, 0.035), (0.046, 0.016, 0.028), (0.034, 0.012, 0.024)]
        radii = [(a * s, a * s, b * s, c * s) for a, b, c in rad]
        bones = [side_name(side, "LowerLeg"), fb, tb]

        def col(p, i, th):
            if sole is not None and p[2] < 0.012 * s:
                return sole
            return color

        tube(self.m, pts, radii, n=n, color=col, hint=(0, 0, 1), weights=self.W(bones, {side_name(side, "LowerLeg"): 0.4}),
             cap0=0.012 * s, cap1=0.012 * s, ex=2.4)

    def skirt(self, z_top, z_bot, r_top, r_bot, color, *, mat=CLOTH, arc=None, n=18, rows=6,
              yc_top=0.0, yc_bot=0.0, leg_share=0.85, ex=2.2, front_scale=1.0):
        """Flared skirt / robe / coat tails with leg-following weights."""
        s = self.s
        zs = np.linspace(z_top, z_bot, rows)
        centers, radii = [], []
        for i, z in enumerate(zs):
            f = i / (rows - 1)
            rx = lerp(r_top[0], r_bot[0], f ** 0.9)
            rf = lerp(r_top[1], r_bot[1], f ** 0.9) * front_scale
            rb = lerp(r_top[2], r_bot[2], f ** 0.9)
            centers.append(v3(0, lerp(yc_top, yc_bot, f), z))
            radii.append((rx, rx, rf, rb))

        def weights(p, i, th):
            f = i / (rows - 1)
            a = (f ** 0.85) * leg_share
            rxz = radii[i][0]
            R = smoothstep(-0.55, 0.55, p[0] / rxz)
            w = {"Hips": 1 - a, "RightUpperLeg": a * R, "LeftUpperLeg": a * (1 - R)}
            if i == 0:
                w = {"Hips": 0.6, "Spine": 0.4}
            return clean_weights(w)

        tube(self.m, centers, radii, n=n, ex=ex, mat=mat, color=color, weights=weights, arc=arc)
        return centers, radii

    def mistcloak(self, *, z_hem, z_collar, n_strips, len_range, color, color_dark, arc=(128, 412),
                  cape_scale=1.0, tassel_w=0.9, seed=1, flare=0.14, segs=8, chain=4, cloak_rows=None,
                  parent="Chest", hood=True):
        """Upper cloak (partial tube over shoulders/back) + independent tassel strips
        each with its own bone chain Tassel_i_k (for spring-bone dynamics)."""
        s, H, S = self.s, self.H, self.S
        sw = self.P["sh_w"] / 0.18 * cape_scale
        W = self.P["width"] * cape_scale
        rows = cloak_rows or [
            (z_collar, 0.078, 0.07, 0.074, -0.01),
            (z_collar - 0.012, 0.14 * sw, 0.085, 0.10, -0.015),
            (0.812, 0.215 * sw, 0.105, 0.118, -0.02),
            (0.775, 0.228 * sw, 0.118, 0.122, -0.02),
            (0.72, 0.215 * sw, 0.125, 0.125, -0.02),
            (0.66, 0.205 * sw, 0.13, 0.13, -0.02),
        ]
        rows = [r for r in rows if r[0] > z_hem + 0.01] + [(z_hem, rows[-1][1] * 1.02, rows[-1][2] * 1.02, rows[-1][3] * 1.04, -0.02)]
        centers = [v3(0, r[4] * s, r[0] * H) for r in rows]
        radii = [(r[1] * s * W, r[1] * s * W, r[2] * s * W, r[3] * s * W) for r in rows]
        bones = ["Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm"]
        bias = {"LeftUpperArm": 0.35, "RightUpperArm": 0.35, "Neck": 0.5}

        def ccol(p, i, th):
            k = (p[2] - z_hem * H) / ((z_collar - z_hem) * H)
            return tuple(lerp(np.array(color_dark), np.array(color), 0.55 + 0.45 * k))

        tube(self.m, centers, radii, n=24, ex=2.0, mat=CLOAK, color=ccol, weights=self.W(bones, bias), arc=arc)
        if hood:
            hz = (z_collar - 0.035) * H
            hy = -(rows[1][3] * s * W) + 0.005 * s
            pts = [v3(x * s, hy - 0.01 * s * (1 - abs(x) / 0.12), hz - 0.02 * s * abs(x) / 0.12) for x in (-0.12, -0.06, 0.0, 0.06, 0.12)]
            tube(self.m, pts, [(0.03 * s, 0.045 * s), (0.04 * s, 0.06 * s), (0.045 * s, 0.065 * s), (0.04 * s, 0.06 * s), (0.03 * s, 0.045 * s)],
                 n=8, hint=(0, -1, -0.6), mat=CLOAK, color=color_dark, weights=self.W(["UpperChest", "Neck"]), cap0=0.01 * s, cap1=0.01 * s)
        # tassels
        rng = np.random.default_rng(seed)
        hem_c, hem_r = centers[-1], radii[-1]
        a0, a1 = arc[0] + 10, arc[1] - 10
        span = (a1 - a0) / n_strips
        chains = []
        for k in range(n_strips):
            thc = math.radians(a0 + span * (k + 0.5))
            half = math.radians(span * tassel_w * 0.5)
            L = rng.uniform(*len_range) * H
            # length taper: sides slightly shorter than the back
            back = math.exp(-((math.degrees(thc) - 270) / 110.0) ** 2)
            L *= 0.8 + 0.2 * back
            names = [f"Tassel_{k:02d}_{j}" for j in range(chain)]

            def ring_pt(th, f):
                z = hem_c[2] - L * f
                fl = 1.0 + flare * f
                x = math.cos(th) * hem_r[0] * fl
                y = math.sin(th) * (hem_r[2] if math.sin(th) > 0 else hem_r[3]) * fl
                return v3(x, hem_c[1] + y, z + 0.004 * s)  # slight overlap with hem

            centre = [ring_pt(thc, j / chain) for j in range(chain + 1)]
            par = parent
            for j in range(chain):
                S.add(names[j], par, centre[j], centre[j + 1])
                par = names[j]
            chains.append(names)
            left = [ring_pt(thc - half * (1 - 0.15 * (i / segs)), i / segs) for i in range(segs + 1)]
            right = [ring_pt(thc + half * (1 - 0.15 * (i / segs)), i / segs) for i in range(segs + 1)]
            # pointed/uneven tip
            left[-1] = left[-1] + v3(0, 0, rng.uniform(0.0, 0.03) * s)
            right[-1] = right[-1] + v3(0, 0, rng.uniform(0.0, 0.03) * s)

            def tw(p, i, names=names, segs=segs):
                f = i / segs * chain
                j = min(int(f), chain - 1)
                t = f - j
                if i == 0:
                    return {"Spine": 0.5, "Chest": 0.5} if parent == "Chest" else {parent: 1.0}
                if t < 0.001 and j > 0:
                    return {names[j - 1]: 0.5, names[j]: 0.5}
                w = {names[j]: 1.0 - 0.5 * max(0, 0.5 - t)}
                if j > 0 and t < 0.5:
                    w[names[j - 1]] = 0.5 * (0.5 - t)
                return clean_weights(w)

            def tcol(i, segs=segs):
                return tuple(lerp(np.array(color), np.array(color_dark), (i / segs) ** 0.8))

            ribbon(self.m, left, right, mat=CLOAK, color=tcol, weights=tw,
                   normal_hint=v3(math.cos(thc), math.sin(thc), 0))
        self.extra_chains += chains
        return chains

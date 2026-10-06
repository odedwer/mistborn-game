"""Shared humanoid skeleton + body-part builders (numpy only)."""
from __future__ import annotations

import math
from contextlib import contextmanager

import numpy as np

from meshkit import (Mesh, Skel, box, clean_weights, frame_from, hexcol, lerp, norm,
                     proximity_weights, ribbon, rot_axis, smoothstep, tube, v3)

# material slots (mapped to <=3 real materials per character)
CLOTH, CLOAK, METAL, GLOSS, GLOW = range(5)
MAT_NAMES = ["Cloth", "Cloak", "Metal", "Gloss", "Glow"]

# Dye slots: the vertex-colour alpha marks regions the shader can recolour per
# instance (CharacterModel.dye_colors -> instance uniforms dye_1..dye_3).
# Author dyed regions near mid luminance; darker trim stays proportionally darker.
DYE_ALPHA = {0: 1.0, 1: 0.75, 2: 0.5, 3: 0.25}


# UV scale for skin surfaces (head, neck). The shared character shader adds a
# ~1 cm cloth weave; on skin at a third of the scale it reads as soft
# mottling rather than a fabric grid.
SKIN_UV = 0.3


def dyed(col, slot):
    """Returns `col` tagged with dye slot 1..3 (0 = not dyeable)."""
    return (col[0], col[1], col[2], DYE_ALPHA[slot])

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
        # optional garments: exported as separate meshes G_<name> on the same skeleton
        self.garments: dict[str, Mesh] = {}
        self._make_skel()

    @contextmanager
    def garment(self, name):
        """Everything built inside `with b.garment("hat"):` goes to the G_hat mesh."""
        prev = self.m
        self.m = self.garments.setdefault(name, Mesh())
        try:
            yield self.m
        finally:
            self.m = prev

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
             color=color, weights=self.W(["UpperChest", "Neck", "Head"], {"UpperChest": 0.5}), uv_scale=SKIN_UV)

    def head(self, skin, *, hair=None, brow=None, lips=None, eye=(0.12, 0.09, 0.08, 1),
             ears=True, jaw=1.0, n=20, gaunt=0.0, eyes=True, tattoo=None, tattoo_rank=1, bald_top=None,
             earrings=None):
        """Builds head; returns dict of landmark positions."""
        s = self.s * self.P["head"] * 1.06
        H = self.H
        chin_z = H - 0.232 * s
        # (dz from chin, rx, rf, rb, yc)
        tab = [
            (0.000, 0.024, 0.018, 0.018, 0.066),
            (0.012, 0.042 * jaw, 0.032, 0.036, 0.054),
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
        # Mouth sits about a third of the way from the nose base to the chin
        # (it used to be lower, which read as a long, mouthless jaw).
        mouth_z = chin_z + 0.05 * s
        tab = np.array(tab)
        # Rows are denser through the eye/brow band (0.1-0.16): with ~13 mm
        # spacing the brow ridge and socket landed on single rings and read as
        # a hard horizontal crease running across the forehead to the temples.
        dzs = np.concatenate([np.linspace(0.0, 0.035, 4), np.linspace(0.045, 0.095, 5), np.linspace(0.103, 0.163, 11),
                              [0.176, 0.19, 0.2, 0.212, 0.222, 0.228]])
        rows = [[np.interp(dz, tab[:, 0], tab[:, k]) for k in range(5)] for dz in dzs]
        centers = [v3(0, t[4] * s, chin_z + t[0] * s) for t in rows]
        radii = [(t[1] * s, t[1] * s, t[2] * s, t[3] * s) for t in rows]
        nose_z = chin_z + 0.08 * s

        def shape(i, th):
            k = 1.0
            z = centers[i][2]
            # Eye sockets: recessed deeper than before so the brow ridge above
            # them (and the cheekbone below) actually reads as a ridge/socket
            # pair instead of a smooth cylindrical face.
            for ex_ in (62.0, 118.0):
                dth = (th - ex_) / 12.0
                dz = (z - eye_z) / (0.015 * s)
                k -= 0.095 * math.exp(-(dth * dth + dz * dz))
            # Brow ridge: stronger and a touch narrower, so it overhangs the
            # (now deeper) socket rather than blending into it.
            # Windowed smoothly across the face (a super-gaussian in theta):
            # the old hard 52..128 degree cut left a step at each temple that
            # read as a seam running from the brow back to the ear.
            # Deeper than before (0.045 / 9 mm) so it reads in profile, with a
            # little extra at the glabella over the nose root.
            k += 0.07 * math.exp(-((th - 90) / 34.0) ** 4) * math.exp(-((z - brow_z) / (0.011 * s)) ** 2)
            k += 0.02 * math.exp(-((th - 90) / 12.0) ** 2) * math.exp(-((z - brow_z + 0.004 * s) / (0.008 * s)) ** 2)
            # Cheekbones: sharper falloff (tighter sigma) and more prominent,
            # sitting just below and outside the eye sockets.
            for cx in (46.0, 134.0):
                k += 0.05 * math.exp(-(((th - cx) / 14) ** 2 + ((z - (eye_z - 0.02 * s)) / (0.013 * s)) ** 2))
            # Jaw angle: a subtle corner where the jawline turns up toward the
            # ear, instead of a uniform taper from chin to cheek.
            for cx in (38.0, 142.0):
                k += 0.022 * math.exp(-(((th - cx) / 16) ** 2 + ((z - (chin_z + 0.05 * s)) / (0.02 * s)) ** 2))
            # Nose bridge: a faint ridge running up from the nose wedge toward
            # the brow, giving the profile more than a flat cylindrical front.
            # It fades out again above the brow, so it no longer pushes a
            # ridge up the forehead and through the crown of the hair cap.
            k += (0.018 * math.exp(-(((th - 90) / 10) ** 2)) * smoothstep(mouth_z, brow_z, z)
                  * (1.0 - smoothstep(brow_z, brow_z + 0.03 * s, z)))
            # lips and chin
            # (a fuller muzzle under the lips, so they sit proud in profile)
            k += 0.045 * math.exp(-(((th - 90) / 18) ** 2 + ((z - mouth_z) / (0.01 * s)) ** 2))
            k += 0.03 * math.exp(-(((th - 90) / 22) ** 2 + ((z - (chin_z + 0.012 * s)) / (0.01 * s)) ** 2))
            # flatten the sides of the face a little (less cylindrical)
            k -= 0.03 * math.exp(-(((th - 90) / 60) ** 2)) * math.exp(-((z - eye_z) / (0.04 * s)) ** 2) * (1 - math.exp(-((th - 90) / 25) ** 2))
            # cheek hollow for gaunt faces
            if gaunt > 0:
                for cx in (40.0, 140.0):
                    k -= gaunt * 0.07 * math.exp(-(((th - cx) / 15) ** 2 + ((z - (mouth_z + 0.03 * s)) / (0.02 * s)) ** 2))
            return k

        def ink(th, z):
            """Obligator eye tattoos: a dark ring around each eye plus rank spikes."""
            best = 0.0
            for ex_, sgn in ((62.0, 1.0), (118.0, -1.0)):
                dx = math.radians(ex_ - th) * 0.078 * s * sgn  # >0 towards the temple
                dz = z - eye_z
                r = math.hypot(dx, dz)
                a = math.degrees(math.atan2(dz, dx))
                k = 1.0 if 0.012 * s < r < 0.02 * s else 0.0
                for sa in [0.0, 40.0, -40.0, 75.0, -75.0, 110.0][:1 + tattoo_rank]:
                    da = abs((a - sa + 180) % 360 - 180)
                    if da < 12 and 0.016 * s < r < (0.042 + 0.005 * tattoo_rank) * s:
                        k = 1.0
                best = max(best, k)
            return best

        def color(p, i, th):
            z = p[2]
            c = np.array(skin, dtype=float)
            if bald_top is not None:
                c = lerp(c, np.array(bald_top, dtype=float), smoothstep(brow_z + 0.03 * s, H - 0.02 * s, z) * 0.6)
            if tattoo is not None:
                c = lerp(c, np.array(tattoo, dtype=float), 0.92 * ink(th, z))
            for ex_ in (62.0, 118.0):
                de = ((th - ex_) / 7.0) ** 2 + ((z - eye_z) / (0.007 * s)) ** 2
                c = lerp(c, np.array(eye), 0.85 * math.exp(-de))
            if brow is not None and (48 < th < 80 or 100 < th < 132):
                c = lerp(c, np.array(brow), 0.85 * math.exp(-((z - brow_z - 0.004 * s) / (0.006 * s)) ** 2))
            if lips is not None and 70 < th < 110:
                c = lerp(c, np.array(lips), 0.7 * math.exp(-((z - mouth_z) / (0.007 * s)) ** 2))
            return tuple(c)

        hw = self.W(["Head", "Neck"], {"Neck": 0.05})
        # Level (horizontal) rings. The centre line wobbles forward/back by a few
        # mm around the eyes; rings set perpendicular to it tilted ~10 degrees
        # either way, and with 0.1 m radii that moved the front of neighbouring
        # rings past each other. The folded surface read as a hard crease
        # across the face just above the eyes, running back to the temples.
        level = [(v3(1, 0, 0), v3(0, 1, 0))] * len(centers)
        head_rings = tube(self.m, centers, radii, n=n, ex=2.1, color=color, shape=shape, weights=hw, cap1=0.004 * s,
                          cap0=0.004 * s, frames=level, uv_scale=SKIN_UV)
        # the skin's actual vertex columns (front/back/sides), for shells that must clear it
        cols = {}
        for key, want in (("x+", 0.0), ("y+", 90.0), ("x-", 180.0), ("y-", 270.0)):
            j = min(range(n), key=lambda j_: abs((360.0 * j_ / n - want + 180.0) % 360.0 - 180.0))
            cols[key] = np.array([self.m.verts[ring[j][0]] for ring in head_rings])
        face_y = lambda zz: np.interp(zz, [c[2] for c in centers], [c[1] + r[2] for c, r in zip(centers, radii)])
        # nose: diamond-section wedge whose back half sits inside the face
        fy = face_y(eye_z)
        # Projects further than before (tip ~1 cm more), so the profile has a
        # real nose rather than a bump on a flat face.
        pts = [v3(0, fy - 0.006 * s, eye_z + 0.006 * s), v3(0, fy + 0.007 * s, eye_z - 0.012 * s),
               v3(0, fy + 0.019 * s, nose_z + 0.012 * s), v3(0, fy + 0.025 * s, nose_z + 0.002 * s)]
        tube(self.m, pts, [(0.005 * s, 0.007 * s), (0.007 * s, 0.009 * s), (0.01 * s, 0.011 * s), (0.013 * s, 0.01 * s)],
             n=6, hint=(0, 1, 0.2), color=skin, weights={"Head": 1.0}, cap1=0.008 * s, cap0=0.002 * s)
        # nostril wings: two small lobes either side of the tip, so the nose has
        # a base from the front instead of reading as a thin blade
        skin_dk = tuple(np.array(skin[:3]) * 0.9) + (skin[3] if len(skin) > 3 else 1.0,)
        for side in (1, -1):
            c = v3(side * 0.009 * s, fy + 0.011 * s, nose_z + 0.003 * s)
            tube(self.m, [c - v3(0, 0.004 * s, 0), c + v3(0, 0.002 * s, 0)], [(0.0065 * s, 0.0055 * s)] * 2, n=6,
                 hint=(0, 0, 1), color=skin_dk, weights={"Head": 1.0}, cap0=0.002 * s, cap1=0.003 * s)
        # mouth: a dark lip line plus a fuller lower lip, laid onto the front of
        # the face (vertex-painted lips alone were too coarse to read at all)
        ic = int(np.argmin([abs(c[2] - mouth_z) for c in centers]))
        m_rx, m_rf = radii[ic][0], radii[ic][2] * 1.03

        def face_pt(x, z, out=0.0):
            # front of the (super-elliptic, ex=2.1) head section at lateral offset x
            u = min(abs(x) / m_rx, 0.98)
            return v3(x, face_y(z) - m_rf + m_rf * (1 - u ** 2.1) ** (1 / 2.1) + out, z)

        lip_col = lips if lips is not None else tuple(np.array(skin[:3]) * 0.8) + (1.0,)
        line_col = tuple(np.array(lip_col[:3]) * 0.4) + (1.0,)
        mw = 0.021 * s
        xs = np.linspace(-mw, mw, 7)
        tube(self.m, [face_pt(x, mouth_z + 0.0012 * s * (abs(x) / mw) ** 2, 0.0022 * s) for x in xs],
             [(0.0022 * s, 0.0016 * s)] * 7, n=6, hint=(0, 0, 1), color=line_col, weights={"Head": 1.0},
             cap0=0.001 * s, cap1=0.001 * s)
        # Lips with real depth, so they read in profile: a fuller lower lip
        # standing proud of the (fuller) muzzle, and an upper lip just behind
        # it, with the dark line between them. They used to sit inside the
        # face surface and vanished side-on.
        lw = 0.014 * s
        xs = np.linspace(-lw, lw, 5)
        taper = (0.7, 0.9, 1.0, 0.9, 0.7)
        tube(self.m, [face_pt(x, mouth_z - 0.005 * s, 0.0012 * s * t) for x, t in zip(xs, taper)],
             [(0.0056 * s * t, 0.0045 * s * t) for t in taper], n=6, hint=(0, 0, 1), color=lip_col,
             weights={"Head": 1.0}, cap0=0.002 * s, cap1=0.002 * s)
        uw = 0.016 * s
        xs = np.linspace(-uw, uw, 5)
        up_col = tuple(np.array(lip_col[:3]) * 0.9) + (1.0,)
        tube(self.m, [face_pt(x, mouth_z + 0.0042 * s + 0.0008 * s * (1 - t), 0.0 * s) for x, t in zip(xs, taper)],
             [(0.0044 * s * t, 0.003 * s * t) for t in taper], n=6, hint=(0, 0, 1), color=up_col,
             weights={"Head": 1.0}, cap0=0.002 * s, cap1=0.002 * s)
        if eyes:
            sclera = tuple(lerp(np.array(skin[:3]), np.array([0.93, 0.9, 0.86]), 0.8)) + (1.0,)
            lid = tuple(np.array(brow[:3] if brow is not None else eye[:3]) * 0.8) + (1.0,)
            for side in (1, -1):
                ex_ = side * 0.031 * s
                ey = face_y(eye_z) - 0.013 * s
                # white almond, a dark iris in front of it, and an upper lid line:
                # the eye used to be one dark lozenge with no direction to it
                tube(self.m, [v3(ex_, ey - 0.004 * s, eye_z), v3(ex_, ey + 0.003 * s, eye_z)],
                     [(0.012 * s, 0.0058 * s), (0.0115 * s, 0.0055 * s)], n=10, hint=(0, 0, 1), color=sclera,
                     weights={"Head": 1.0}, cap1=0.0025 * s)
                ix = ex_ - side * 0.001 * s
                tube(self.m, [v3(ix, ey + 0.0025 * s, eye_z - 0.0004 * s), v3(ix, ey + 0.005 * s, eye_z - 0.0004 * s)],
                     [(0.0058 * s, 0.0056 * s), (0.0054 * s, 0.0052 * s)], n=10, hint=(0, 0, 1), color=eye,
                     weights={"Head": 1.0}, cap1=0.0012 * s)
                lid_pts = [v3(ex_ - side * 0.0135 * s, ey + 0.0005 * s, eye_z - 0.001 * s),
                           v3(ex_ - side * 0.006 * s, ey + 0.0035 * s, eye_z + 0.0052 * s),
                           v3(ex_ + side * 0.004 * s, ey + 0.003 * s, eye_z + 0.0056 * s),
                           v3(ex_ + side * 0.0135 * s, ey - 0.001 * s, eye_z + 0.0015 * s)]
                tube(self.m, lid_pts, [(0.0014 * s, 0.0018 * s), (0.0018 * s, 0.0024 * s), (0.0018 * s, 0.0024 * s),
                                       (0.0014 * s, 0.0016 * s)], n=5, hint=(0, 1, 0), color=lid,
                     weights={"Head": 1.0}, cap0=0.001 * s, cap1=0.002 * s)
                if brow is not None:
                    by = face_y(brow_z) - 0.004 * s
                    tube(self.m, [v3(side * 0.012 * s, by, brow_z + 0.002 * s), v3(side * 0.03 * s, by + 0.001 * s, brow_z + 0.005 * s),
                                  v3(side * 0.05 * s, by - 0.01 * s, brow_z + 0.002 * s)],
                         [(0.003 * s, 0.004 * s), (0.0035 * s, 0.0045 * s), (0.0025 * s, 0.0035 * s)], n=6, hint=(0, 1, 0),
                         color=brow, weights={"Head": 1.0})
        if ears:
            for side in (1, -1):
                ex_x = side * 0.074 * s
                # A C-shaped rim (helix down to the lobe) standing off the side
                # of the head and angled back, instead of one short flattened
                # tube, which read as a flat diamond pasted onto the hair.
                ear_pts = [(0.066, -0.006, 0.010), (0.072, -0.014, 0.014), (0.078, -0.024, 0.009),
                           (0.080, -0.028, -0.002), (0.077, -0.025, -0.013), (0.071, -0.017, -0.02)]
                ear_col = tuple(np.array(skin[:3]) * 0.93) + (1.0,)
                tube(self.m, [v3(side * x * s, y * s, eye_z - 0.003 * s + z * s) for x, y, z in ear_pts],
                     [(0.0045 * s, 0.0035 * s), (0.005 * s, 0.004 * s), (0.0055 * s, 0.004 * s),
                      (0.0055 * s, 0.004 * s), (0.006 * s, 0.0045 * s), (0.0045 * s, 0.004 * s)],
                     n=6, hint=(side, 0, 0), color=ear_col, weights={"Head": 1.0}, cap0=0.002 * s, cap1=0.003 * s)
                # the concha filling the C, set a little deeper
                tube(self.m, [v3(side * 0.07 * s, -0.018 * s, eye_z + 0.004 * s),
                              v3(side * 0.071 * s, -0.019 * s, eye_z - 0.012 * s)],
                     [(0.007 * s, 0.003 * s), (0.006 * s, 0.003 * s)], n=6, hint=(side, 0, 0),
                     color=tuple(np.array(skin[:3]) * 0.8) + (1.0,), weights={"Head": 1.0},
                     cap0=0.003 * s, cap1=0.003 * s)
                if earrings is not None:
                    # a stack of metal rings down the (stretched) lobe: Sazed's metalminds
                    for k_ in range(earrings[1]):
                        zc = eye_z - 0.022 * s - k_ * 0.012 * s
                        c0 = v3(ex_x * 1.1, -0.016 * s, zc)
                        tube(self.m, [c0 - v3(0, 0.007 * s, 0), c0 + v3(0, 0.007 * s, 0)], [0.007 * s, 0.007 * s], n=6,
                             hint=(0, 0, 1), mat=METAL, color=earrings[0], weights={"Head": 1.0})
        lm = dict(chin_z=chin_z, eye_z=eye_z, brow_z=brow_z, mouth_z=mouth_z, top=H, s=s, centers=centers, radii=radii,
                  skin_cols=cols,
                  eye_l=v3(-0.03 * s, face_y(eye_z) - 0.012 * s, eye_z),
                  eye_r=v3(0.03 * s, face_y(eye_z) - 0.012 * s, eye_z))
        self.head_lm = lm
        return lm

    def hair_shell(self, color, *, fringe_z=None, back_z=None, puff=1.12, jag=0.012, n=20, spikes=7,
                   style="short", bald_amount=0.55, clumps=0.0, seed=0.0, ears_out=True):
        """Hair cap built from the head profile, hidden in front below the fringe.

        `style`:
          - "short" (default): the original close-cropped cap, unchanged.
          - "long": a short cap plus a tied tail hanging down the back.
          - "bun": a short cap plus a rounded knot pinned at the back/crown.
          - "bald": a thin fringe of hair low on the sides/back only, leaving
            the crown bare (pair with `bald_top=` on `head()` for the scalp
            tone to show through).

        `clumps` (0..1) breaks a short cap up so it doesn't read as a smooth
        helmet: raised, slightly swept locks (lighter on top, darker in the
        grooves) and a ragged, uneven hairline. `seed` varies the pattern.
        """
        lm = self.head_lm
        s = lm["s"]
        fz = fringe_z if fringe_z is not None else lm["brow_z"] + 0.012 * s
        bz = back_z if back_z is not None else lm["chin_z"] + 0.03 * s
        cs, rs = lm["centers"], lm["radii"]
        zs = [c[2] for c in cs]
        top_z = lm["top"] - 0.008 * s
        if style == "bald":
            # Only the lower band (above the ears, below the crown) keeps hair.
            bz = max(bz, lm["eye_z"] - 0.01 * s)
            top_z = min(top_z, lm["brow_z"] + 0.03 * s)
        # Rings bunch up a little towards the crown, where the head profile
        # curves fastest (straight segments between sparse rings cut inside it).
        t_ = np.linspace(0.0, 1.0, 15)
        rings_z = list(bz + (top_z - bz) * (1.5 * t_ - 0.5 * t_ * t_))
        sk = lm["skin_cols"]
        ear_z0, ear_z1 = lm["eye_z"] - 0.026 * s, lm["eye_z"] + 0.013 * s
        centers, radii = [], []
        for z in rings_z:
            yc = np.interp(z, zs, [c[1] for c in cs])
            r = [np.interp(z, zs, [rr[k] for rr in rs]) for k in range(4)]
            # The cap sits a little behind the face, but that offset fades out
            # towards the crown: at full offset the front of the crown dome
            # dipped under the scalp and skin poked through on puff~1.0 styles.
            back = 0.004 * s * (1.0 - smoothstep(lm["brow_z"], top_z, z))
            c = v3(0, yc - back, z)
            # Clear the skin as actually built, not just the nominal profile: the
            # head's rings lean slightly, so on the forehead and crown the skin
            # sits a few mm outside the interpolated radius and poked through.
            real = []
            for key, ax, sgn in (("x+", 0, 1), ("x-", 0, -1), ("y+", 1, 1), ("y-", 1, -1)):
                col = sk[key]
                real.append(sgn * (np.interp(z, col[:, 2], col[:, ax]) - c[ax]))
            # (the nominal radii are about the unshifted centre: re-base them)
            r = [max(a_ + d_, b_) for a_, b_, d_ in zip(r, real, (0.0, 0.0, back, -back))]
            centers.append(c)
            radii.append(tuple(max(x, 0.036 * s) * puff + (0.004 if style == "bald" else 0.008) * s for x in r))

        if clumps > 0.0:
            n = max(n, 28)

        def lump(i, th):
            """Swept lock pattern in [-1, 1]: locks run back from the hairline."""
            u = (rings_z[i] - rings_z[0]) / max(rings_z[-1] - rings_z[0], 1e-6)
            a = math.radians(th)
            v = (0.55 * math.sin(5 * a + 2.1 + seed + 5.0 * u) * math.sin(3 * a - 1.3 + 7.0 * u)
                 + 0.45 * math.sin(11 * a + 0.7 * seed + 3.0 * u))
            return max(-1.0, min(1.0, v * 1.25))

        def hairline(th):
            a = math.radians(th)
            return fz + clumps * 0.016 * s * (0.55 * math.sin(4 * a + seed) + 0.45 * math.sin(11 * a + 2 * seed))

        base_color = color
        if clumps > 0.0:
            def color(p, i, th):
                c = np.array(base_color(p, i, th) if callable(base_color) else base_color, dtype=float)
                # lock tops catch a lighter sheen, grooves go darker: dark hair
                # needs an additive lift or it stays one flat black under light
                t = clumps * (lump(i, th) + 1.0) * 0.5
                rgb = lerp(c[:3] * 0.7, c[:3] * 1.4 + 0.2, t * t)
                return tuple(rgb) + (c[3] if len(c) > 3 else 1.0,)

        def shape(i, th):
            z = rings_z[i]
            fz = hairline(th)
            front = math.exp(-((th - 90) / 55.0) ** 2)
            side_ = math.exp(-((th - 90) / 95.0) ** 2)
            k = 1.0
            if z < fz:
                # Hide inside the face below the fringe line (front), keep the
                # sides/back. The front sector is a hard step between two columns:
                # a smooth falloff left a wide band at the temples where the shell
                # sat almost exactly on the skin and z-fought into a stripe
                # running from the eye corner back to the hair.
                # (bald: only a low band round the back stays, behind the ears)
                # (a steep ramp over ~one column rather than a hard step: the
                # crossing lands inside the quads, so the sideburn corner is
                # rounded rather than a square notch)
                lim = 100 if style == "bald" else 60
                hide = 1.0 - smoothstep(lim - 6.0, lim + 6.0, abs(th - 90))
                k -= 0.35 * hide * smoothstep(fz, fz - 0.015 * s, z)
                k -= 0.12 * side_ * smoothstep(lm["eye_z"], lm["eye_z"] - 0.04 * s, z)
            if style == "choppy":
                # Uneven volume: fuller at the back and in two or three soft
                # lobes round the sides, so the profile isn't a smooth dome.
                u = (z - rings_z[0]) / max(rings_z[-1] - rings_z[0], 1e-6)
                a = math.radians(th)
                back = math.exp(-((th - 270.0) / 55.0) ** 2)
                k += math.sin(math.pi * min(u * 1.15, 1.0)) * (
                    0.07 * back + 0.05 * (0.5 + 0.5 * math.sin(3 * a + seed * 2.0)) * (1 - 0.6 * front))
                # tousled, rounder top instead of the head's peaked crown
                k += 0.16 * smoothstep(0.7, 1.0, u)
            if ears_out:
                # Cut the shell around each ear (a hard step between columns,
                # so there's no band where hair and skin z-fight): the hair
                # tucks behind the ear and the ear sits in front of it.
                # The cut is an ellipse round the ear, rather than a square
                # window. Its front edge leans back
                # towards the bottom, leaving a tapered sideburn wedge in front
                # of the ear.
                zc, hz = 0.5 * (ear_z0 + ear_z1), 0.5 * (ear_z1 - ear_z0) + 0.004 * s
                for e_th, fwd in ((-10.0, 1.0), (190.0, -1.0)):
                    d = (th - e_th + 180.0) % 360.0 - 180.0  # signed, degrees
                    f = d * fwd  # > 0 towards the face
                    dz = (z - zc) / hz
                    # sideburn: the front half narrows as it goes down
                    reach = 30.0 if f < 0 else 30.0 * (0.55 + 0.45 * min(max(dz + 0.2, 0.0), 1.0))
                    # Continuous but steep: the shell crosses the skin along one
                    # line inside the quads, so the outline interpolates
                    # smoothly (a hard in/out step gave a staircase), and the
                    # ramp is too short for a z-fighting band.
                    r = math.sqrt((f / reach) ** 2 + dz * dz)
                    k -= 0.3 * (1.0 - smoothstep(0.65, 1.05, r))
            if style == "bald":
                # A low band of close-cropped hair round the back: it swells just
                # clear of the scalp mid-band and tucks under it at both edges,
                # so there is no rim. (It used to be cut off flat and read as a
                # dark bar, or a shelf, sticking out behind the ear.) The crown
                # stays bare so the scalp (bald_top on head()) shows.
                t_b = (z - rings_z[0]) / max(rings_z[-1] - rings_z[0], 1e-6)
                k += -0.03 + 0.035 * math.sin(math.pi * t_b) * min(1.0, bald_amount / 0.55)
            if i == 0 or (z < fz + 0.01 * s and front > 0.3):
                k += jag / 0.1 * 0.25 * math.sin(math.radians(th) * spikes)
            if clumps > 0.0:
                # locks stand proud of the cap; grooves stay above the scalp
                k += clumps * 0.085 * max(lump(i, th), -0.3)
            return k

        # Level rings: letting them tilt with the (slightly forward-leaning)
        # centre line dropped the front of each ring below the scalp, which is
        # where skin poked through at the front of the crown.
        level = [(v3(1, 0, 0), v3(0, 1, 0))] * len(centers)
        tube(self.m, centers, radii, n=n, ex=2.1, color=color, shape=shape, frames=level,
             weights={"Head": 1.0}, cap1=(0.012 if style == "choppy" else 0.026) * s)

        if style == "long":
            self._hair_tail(base_color, bz, s)
        elif style == "bun":
            self._hair_bun(base_color, top_z, s)
        elif style == "choppy":
            self._choppy_locks(base_color, centers, radii, rings_z, fz, seed)

    def _choppy_locks(self, color, centers, radii, rings_z, fz, seed):
        """Short, choppy cut: uneven locks break the cap's outline.

        A swept fringe of uneven strands over the forehead (kept above the
        brows), a ragged nape and side hem of flared locks, and a few tufts
        sticking up at the crown. Each lock is a flattened, tapering strand
        laid on the cap surface.
        """
        lm = self.head_lm
        s = lm["s"]
        rng = np.random.default_rng(int(seed * 1000) + 7)
        base = np.array(color[:3], dtype=float)

        def surf(z, th, out=1.0):
            zc = min(max(z, rings_z[0]), rings_z[-1])
            c = np.array([0.0, np.interp(zc, rings_z, [p[1] for p in centers]), z])
            a = math.radians(th)
            rx = np.interp(zc, rings_z, [r[0] for r in radii])
            ry = np.interp(zc, rings_z, [r[2] if math.sin(a) >= 0 else r[3] for r in radii])
            return c + np.array([math.cos(a) * rx * out, math.sin(a) * ry * out, 0.0])

        def lock(z, th, down, length, width, sweep=0.0, flare=0.0, lift=0.0):
            a = math.radians(th)
            nrm = np.array([math.cos(a), math.sin(a), 0.0])
            tang = np.array([-math.sin(a), math.cos(a), 0.0])
            p0 = surf(z, th, 0.96)
            d = np.array([0.0, 0.0, -down]) + tang * sweep + nrm * flare
            d = d / np.linalg.norm(d)
            pts = [p0 + d * length * s * t + nrm * (lift * s * t * t + 0.004 * s) for t in (0.0, 0.35, 0.7, 1.0)]
            k = 0.8 + 0.4 * rng.random()
            col = tuple(np.clip(base * k, 0, 1)) + (1.0,)
            tube(self.m, pts, [(width * s, 0.004 * s), (width * 0.85 * s, 0.0035 * s), (width * 0.5 * s, 0.0025 * s),
                               (0.0012 * s, 0.001 * s)],
                 n=5, hint=tuple(nrm), color=col, weights={"Head": 1.0})

        # fringe: swept strands, longest on the sweep side, tips above the brows
        max_len = (fz + 0.012 * s - (lm["brow_z"] + 0.004 * s)) / s
        for j, th in enumerate(np.linspace(58, 122, 7)):
            ln = max_len * (0.55 + 0.45 * (j / 6.0)) * (0.8 + 0.25 * rng.random())
            lock(fz + 0.012 * s, th, 1.0, max(ln, 0.012), 0.011, sweep=-0.45, lift=0.004)
        # ragged hem round the sides and nape, flared out a little
        for th in np.linspace(150, 390, 13):
            ln = 0.014 + 0.018 * rng.random()
            lock(rings_z[1], th, 1.0, ln, 0.017, sweep=0.2 * (rng.random() - 0.5), flare=0.25)
        # flyaways: thin, longer strands curling off the nape and sides
        for th in list(np.linspace(215, 325, 6)) + [165.0, 185.0, 5.0, 355.0]:
            th = th + 12 * (rng.random() - 0.5)
            z = rings_z[1] + (rings_z[3] - rings_z[1]) * rng.random()
            lock(z, th, 1.0, 0.02 + 0.012 * rng.random(), 0.0055, sweep=0.6 * (rng.random() - 0.5),
                 flare=0.35 + 0.3 * rng.random(), lift=0.006)
        # crown tufts: short, broad and lying back along the head (upright
        # ones read as horns)
        for th in (215.0, 260.0, 305.0):
            z = rings_z[-4]
            lock(z, th + 15 * (rng.random() - 0.5), 0.35, 0.02 + 0.008 * rng.random(), 0.016, flare=0.35)

    def _back_point(self, z, s, push=1.0):
        """A point on the back surface of the head profile at height `z`."""
        lm = self.head_lm
        cs, rs = lm["centers"], lm["radii"]
        zs = [c[2] for c in cs]
        yc = np.interp(z, zs, [c[1] for c in cs])
        rb = np.interp(z, zs, [rr[3] for rr in rs])
        return v3(0, yc - rb * push, z)

    def _hair_tail(self, color, bz, s):
        """A tied tail of hair hanging down the back of the head/neck."""
        anchor = self._back_point(bz + 0.015 * s, s, push=0.95)
        pts = [anchor, anchor + v3(0, -0.01 * s, -0.05 * s), anchor + v3(0, -0.03 * s, -0.13 * s),
               anchor + v3(0, -0.05 * s, -0.22 * s), anchor + v3(0.005 * s, -0.06 * s, -0.3 * s)]
        radii = [(0.024 * s, 0.03 * s), (0.022 * s, 0.026 * s), (0.018 * s, 0.02 * s),
                 (0.013 * s, 0.014 * s), (0.006 * s, 0.006 * s)]
        tube(self.m, pts, radii, n=10, hint=(1, 0, 0), color=color,
             weights=self.W(["Head", "Neck"], {"Neck": 0.5}), cap1=0.004 * s)

    def _hair_bun(self, color, top_z, s):
        """A rounded knot of hair pinned at the back of the crown."""
        anchor = self._back_point(top_z - 0.02 * s, s, push=0.85)
        pts = [anchor + v3(0, -0.01 * s, 0.01 * s), anchor + v3(0, -0.025 * s, -0.005 * s),
               anchor + v3(0, -0.012 * s, -0.022 * s)]
        radii = [(0.014 * s, 0.018 * s), (0.026 * s, 0.026 * s), (0.014 * s, 0.016 * s)]
        tube(self.m, pts, radii, n=10, hint=(1, 0, 0), color=color,
             weights={"Head": 1.0}, cap0=0.012 * s, cap1=0.01 * s)

    def arm(self, side, radii_scale=1.0, color=None, sleeve=None, bare_from=None, n=12,
            cuff=None, flare=0.0, skin=None):
        """Arm tube along UpperArm/LowerArm. color(p,i,th) or const."""
        S, s = self.S, self.s * self.P["limb"] * radii_scale
        ua, la = side_name(side, "UpperArm"), side_name(side, "LowerArm")
        sh, el, wr = S.head(ua), S.head(la), S.tail(la)
        d1, d2 = S.dir(ua), S.dir(la)
        pts = [sh - d1 * 0.01 * s, sh + (el - sh) * 0.12, sh + (el - sh) * 0.4, sh + (el - sh) * 0.75,
               el, el + (wr - el) * 0.25, el + (wr - el) * 0.6, wr - d2 * 0.005]
        base = [0.047, 0.055, 0.048, 0.043, 0.039, 0.042, 0.035, 0.027]
        rr = []
        for i, r in enumerate(base):
            r *= s
            if i >= 5:
                r += flare * (i - 4) / 3.0 * self.s
            rr.append((r, r * 0.92))
        bones = [side_name(side, "Shoulder"), ua, la, side_name(side, "Hand"), "UpperChest"]
        bias = {"UpperChest": 0.3, side_name(side, "Shoulder"): 0.6, side_name(side, "Hand"): 0.5}
        tube(self.m, pts, rr, n=n, color=color, hint=(0, 1, 0), weights=self.W(bones, bias), cap1="flat")

    def hand(self, side, color, n=8, scale=1.0, curl=1.0, palm=None):
        """Mitten hand. `palm` (optional) colours the palm side: the palm and
        the inner faces of the curled fingers and thumb, judged against each
        ring's own centre so the curled fingertips keep the back colour. A
        dark glove with a pale leather palm reads as an open hand in a Push
        instead of a fist."""
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
        def sided(cs, nrm):
            """Palm colour on the side of ring i facing nrm(i) (caps: the end ring's)."""
            if palm is None:
                return color

            def f(p, i, th):
                i = min(max(i, 0), len(cs) - 1)
                return palm if float(np.dot(p - cs[i], nrm(i))) > 0.0 else color
            return f

        def finger_n(i):
            # palm normal bent along the finger curl (the curled tips face back)
            a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
            a = norm(a)
            return norm(pn - a * float(np.dot(pn, a)))

        tube(self.m, pts, [(r[0], r[1]) for r in rr], n=n, color=sided(pts, finger_n), hint=g, weights=W,
             cap1=0.01 * s, cap0=None, ex=2.4)
        # thumb
        tb = o + d * 0.2 * L + g * 0.03 * s
        tps = [tb, tb + d * 0.25 * L + g * 0.02 * s + pn * 0.012 * s, tb + d * 0.45 * L + pn * 0.03 * s * curl]
        tube(self.m, tps, [0.012 * s, 0.011 * s, 0.0095 * s], n=6, color=sided(tps, lambda i: norm(pn - g * 0.6)),
             weights=W, cap1=0.007 * s)

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
              yc_top=0.0, yc_bot=0.0, leg_share=0.85, ex=2.2, front_scale=1.0, curve=0.9, jag=0.0, seed=0):
        """Flared skirt / robe / coat tails with leg-following weights.
        `curve` < 1 flares early (hoop skirt), > 1 late (bell); `jag` (m) tatters the hem."""
        s = self.s
        zs = np.linspace(z_top, z_bot, rows)
        centers, radii = [], []
        for i, z in enumerate(zs):
            f = i / (rows - 1)
            rx = lerp(r_top[0], r_bot[0], f ** curve)
            rf = lerp(r_top[1], r_bot[1], f ** curve) * front_scale
            rb = lerp(r_top[2], r_bot[2], f ** curve)
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

        rings = tube(self.m, centers, radii, n=n, ex=ex, mat=mat, color=color, weights=weights, arc=arc)
        if jag > 0:
            rng = np.random.default_rng(seed + 11)
            for j, (idx, _, _) in enumerate(rings[-1]):
                d = jag * s * (0.25 + 0.75 * rng.random()) * (1.0 if j % 2 else 0.3)
                self.m.verts[idx] = self.m.verts[idx] + v3(0, 0, -d)
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

    # ------------------------------------------------------------ head shells
    def head_shell(self, color, z0, z1, *, puff=1.1, add=0.006, arc=None, n=16, rows=8, shape=None,
                   cap1=None, mat=CLOTH, weights=None, yoff=0.0):
        """Shell following the head profile between heights z0..z1 (beards, caps, scarves)."""
        lm = self.head_lm
        s = lm["s"]
        cs, rs = lm["centers"], lm["radii"]
        zs = [c[2] for c in cs]
        centers, radii = [], []
        for z in np.linspace(z0, z1, rows):
            zc = min(max(z, zs[0]), zs[-1])
            yc = np.interp(zc, zs, [c[1] for c in cs])
            r = [np.interp(zc, zs, [rr[k] for rr in rs]) for k in range(4)]
            centers.append(v3(0, yc + yoff, z))
            radii.append(tuple(max(x, 0.03 * s) * puff + add * s for x in r))
        # level rings, like the head itself (tilted ones folded over each other)
        level = [(v3(1, 0, 0), v3(0, 1, 0))] * len(centers)
        tube(self.m, centers, radii, n=n, ex=2.1, color=color, shape=shape, arc=arc, mat=mat,
             weights=weights or {"Head": 1.0}, cap1=cap1, frames=level)
        return centers, radii

    def beard(self, color, *, length=0.03, full=True, n=18):
        """Beard: shell over the jaw and chin, open at the back; `full` also covers the cheeks."""
        lm = self.head_lm
        s = lm["s"]
        z0 = lm["chin_z"] - length * s
        z1 = lm["eye_z"] - (0.03 if full else 0.055) * s
        mouth_z = lm["mouth_z"]
        rows = 12
        zs = np.linspace(z0, z1, rows)

        def shape(i, th):
            front = math.exp(-((th - 90) / 14.0) ** 2)
            # fuller at the chin, thinning towards the sideburns
            k = 1.0 + 0.12 * math.exp(-((th - 90) / 40.0) ** 2) * (1 - i / (rows - 1))
            # open the mouth: the shell dips inside the face there, so the lips
            # show between moustache and chin instead of a solid mask of hair
            k -= 0.3 * front * math.exp(-((zs[i] - mouth_z) / (0.0055 * s)) ** 2)
            # tuck the top edge into the cheek so it has no visible thickness
            if i == rows - 1:
                k *= 0.9
            elif i == rows - 2:
                k *= 0.97
            return k

        def col(p, i, th):
            if abs(th - 90) < 20 and abs(p[2] - mouth_z) < 0.009 * s:
                return tuple(np.array(color[:3]) * 0.7) + (color[3] if len(color) > 3 else 1.0,)
            return color

        self.head_shell(col, z0, z1, puff=1.0, add=0.009, arc=(-20, 200), n=n, rows=rows, shape=shape,
                        weights=self.W(["Head", "Neck"], {"Neck": 0.05}))

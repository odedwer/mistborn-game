"""The six Mistborn character designs, built from body.py parts."""
from __future__ import annotations

import math

import numpy as np

from body import CLOAK, CLOTH, GLOSS, GLOW, METAL, Body, side_name
from meshkit import box, hexcol, lerp, norm, rot_axis, tube, v3

# Reference torso (male, H=1.75): (zf, rx, rf, rb, yc)
TORSO_M = [
    (0.470, 0.050, 0.045, 0.045, 0.000),
    (0.495, 0.130, 0.072, 0.082, -0.004),
    (0.530, 0.158, 0.083, 0.098, -0.010),
    (0.570, 0.154, 0.080, 0.090, -0.006),
    (0.612, 0.143, 0.080, 0.080, 0.000),
    (0.655, 0.148, 0.090, 0.084, 0.002),
    (0.700, 0.160, 0.104, 0.090, 0.002),
    (0.745, 0.172, 0.105, 0.095, 0.000),
    (0.785, 0.182, 0.090, 0.092, -0.006),
    (0.810, 0.168, 0.072, 0.076, -0.010),
    (0.828, 0.110, 0.058, 0.062, -0.012),
    (0.842, 0.058, 0.050, 0.050, -0.010),
]


def torso_table(hips=1.0, waist=1.0, chest=1.0, shoulders=1.0, depth=1.0, bust=0.0, belly=0.0):
    out = []
    for zf, rx, rf, rb, yc in TORSO_M:
        if zf < 0.58:
            k = hips
        elif zf < 0.64:
            k = waist
        elif zf < 0.76:
            k = chest
        else:
            k = shoulders
        f = rf * depth
        if 0.69 < zf < 0.76:
            f += bust
        if 0.56 < zf < 0.67:
            f += belly
        out.append((zf, rx * k, f, rb * depth, yc))
    return out


def band(base, bands):
    """Vertex colour by height bands: [(z_lo, z_hi, colour), ...] over `base`."""
    def f(p, i, th):
        for lo, hi, c in bands:
            if lo <= p[2] < hi:
                return c
        return base
    return f


# ----------------------------------------------------------------------- props
def dagger(b: Body, side, reverse=True, blade=0.2):
    o, M = b.hand_frame(side)
    s = b.s
    g = M[:, 2] * (-1 if reverse else 1)
    d = M[:, 1]
    hb = side_name(side, "Hand")
    W = {hb: 1.0}
    grip = o - g * 0.05 * s
    tube(b.m, [grip, grip + g * 0.115 * s], [0.012 * s, 0.012 * s], n=6, color=hexcol("3a2a20"), weights=W,
         cap0="flat")
    box(b.m, grip + g * 0.12 * s, (0.018 * s, 0.05 * s, 0.012 * s),
        frame=np.column_stack([M[:, 0], d, g]), color=hexcol("26221f"), mat=CLOTH, weights=W)
    b0 = grip + g * 0.125 * s
    tube(b.m, [b0, b0 + g * blade * 0.45 * s, b0 + g * blade * 0.85 * s, b0 + g * blade * s],
         [(0.004 * s, 0.017 * s), (0.005 * s, 0.019 * s), (0.003 * s, 0.011 * s), (0.001 * s, 0.002 * s)],
         n=6, hint=d, mat=GLOSS, color=hexcol("121118"), weights=W, cap0="flat", smooth=False)


def spear(b: Body, side):
    o, M = b.hand_frame(side)
    s = b.s
    g = M[:, 2]
    W = {side_name(side, "Hand"): 1.0}
    wood = hexcol("5a4028")
    tube(b.m, [o - g * 0.95 * s, o + g * 1.25 * s], [0.015 * s, 0.014 * s], n=6, color=wood, weights=W,
         cap0="flat", cap1="flat")
    tube(b.m, [o + g * 1.2 * s, o + g * 1.3 * s], [0.02 * s, 0.017 * s], n=6, mat=METAL, color=hexcol("8a8f96"),
         weights=W, cap0="flat")
    h = o + g * 1.3 * s
    tube(b.m, [h, h + g * 0.07 * s, h + g * 0.17 * s, h + g * 0.26 * s],
         [(0.006 * s, 0.016 * s), (0.008 * s, 0.038 * s), (0.005 * s, 0.026 * s), (0.001 * s, 0.002 * s)],
         n=6, hint=M[:, 1], mat=METAL, color=hexcol("b4bac2"), weights=W, smooth=False)
    tube(b.m, [o - g * 0.95 * s, o - g * 1.0 * s], [0.018 * s, 0.012 * s], n=6, mat=METAL,
         color=hexcol("6d7178"), weights=W, cap1="flat")


def lantern(b: Body, side):
    o, M = b.hand_frame(side)
    s = b.s
    g = M[:, 2]
    W = {side_name(side, "Hand"): 1.0}
    iron = hexcol("3a3a3e")
    tube(b.m, [o + g * 0.03 * s, o - g * 0.07 * s], [0.004 * s, 0.004 * s], n=4, mat=METAL, color=iron, weights=W)
    top = o - g * 0.07 * s
    tube(b.m, [top, top - g * 0.04 * s], [0.018 * s, 0.058 * s], n=8, mat=METAL, color=iron, weights=W,
         cap0=0.005 * s, cap1="flat")
    tube(b.m, [top - g * 0.045 * s, top - g * 0.2 * s], [0.045 * s, 0.045 * s], n=6, mat=GLOW,
         color=hexcol("ffc070"), weights=W, cap0="flat", cap1="flat", smooth=False)
    for k in range(3):
        a = math.radians(k * 120 + 30)
        off = (M[:, 0] * math.cos(a) + M[:, 1] * math.sin(a)) * 0.05 * s
        tube(b.m, [top - g * 0.04 * s + off, top - g * 0.21 * s + off], [0.005 * s, 0.005 * s], n=4, mat=METAL,
             color=iron, weights=W)
    tube(b.m, [top - g * 0.2 * s, top - g * 0.225 * s], [0.058 * s, 0.05 * s], n=8, mat=METAL, color=iron,
         weights=W, cap0="flat", cap1="flat")
    b.sockets["lantern"] = (side_name(side, "Hand"), top - g * 0.12 * s)


def staff(b: Body, side, lo=0.8, hi=1.0):
    o, M = b.hand_frame(side)
    s = b.s
    g = M[:, 2]
    W = {side_name(side, "Hand"): 1.0}
    wood = hexcol("6e4e30")
    tube(b.m, [o - g * lo * s, o - g * (lo - 0.1) * s, o + g * (hi - 0.1) * s, o + g * hi * s],
         [0.02 * s, 0.018 * s, 0.018 * s, 0.021 * s], n=7, color=wood, weights=W, cap0=0.01 * s, cap1=0.01 * s)
    for t in (-(lo - 0.12), hi - 0.12):
        tube(b.m, [o + g * (t - 0.03) * s, o + g * (t + 0.03) * s], [0.024 * s, 0.024 * s], n=7,
             color=hexcol("2e2218"), weights=W)


def club(b: Body, side):
    o, M = b.hand_frame(side)
    s = b.s
    g = M[:, 2]
    W = {side_name(side, "Hand"): 1.0}
    tube(b.m, [o - g * 0.14 * s, o + g * 0.1 * s, o + g * 0.45 * s, o + g * 0.72 * s, o + g * 0.8 * s],
         [0.022 * s, 0.022 * s, 0.035 * s, 0.05 * s, 0.035 * s], n=8, color=hexcol("5b4029"), weights=W,
         cap0="flat", cap1=0.01 * s)
    for t in (0.5, 0.64):
        tube(b.m, [o + g * t * s, o + g * (t + 0.035) * s], [0.045 * s, 0.047 * s], n=8, color=hexcol("2a1e15"),
             weights=W)


def axe(b: Body, side):
    o, M = b.hand_frame(side)
    s = b.s
    g, d = M[:, 2], M[:, 1]
    W = {side_name(side, "Hand"): 1.0}
    tube(b.m, [o - g * 0.32 * s, o + g * 0.62 * s], [0.017 * s, 0.016 * s], n=6, color=hexcol("2b211b"),
         weights=W, cap0="flat", cap1="flat")
    top = o + g * 0.5 * s
    tube(b.m, [top - d * 0.02 * s, top + d * 0.06 * s, top + d * 0.15 * s, top + d * 0.22 * s],
         [(0.014 * s, 0.035 * s), (0.011 * s, 0.05 * s), (0.007 * s, 0.09 * s), (0.002 * s, 0.13 * s)],
         n=6, hint=g, mat=GLOSS, color=hexcol("0e0d12"), weights=W, cap0="flat", smooth=False)
    tube(b.m, [top - d * 0.02 * s, top - d * 0.1 * s], [(0.01 * s, 0.02 * s), (0.004 * s, 0.006 * s)], n=6,
         hint=g, mat=GLOSS, color=hexcol("0e0d12"), weights=W, smooth=False)


def round_shield(b: Body, side):
    S, s = b.S, b.s
    la = side_name(side, "LowerArm")
    _, M = b.hand_frame(side)
    out = -M[:, 0]  # back of the hand
    c = S.head(la) + (S.tail(la) - S.head(la)) * 0.55 + out * 0.055 * s
    W = {la: 1.0}
    R = 0.3 * s

    def wood(p, i, th):
        planks = math.floor((np.dot(p - c, M[:, 1]) / R + 1) * 3.5)
        base = [hexcol("6b4a2c"), hexcol("5e4026"), hexcol("73502f")][planks % 3]
        rr = np.linalg.norm((p - c) - out * np.dot(p - c, out))
        if rr > R * 0.9:
            return hexcol("2f241b")
        return base

    tube(b.m, [c - out * 0.012 * s, c, c + out * 0.018 * s], [R * 0.97, R, R * 0.96], n=18, hint=M[:, 1],
         color=wood, weights=W, cap0="flat", cap1="flat")
    tube(b.m, [c + out * 0.015 * s, c + out * 0.05 * s], [0.075 * s, 0.04 * s], n=10, hint=M[:, 1],
         color=hexcol("4a3320"), weights=W, cap1=0.02 * s)


# ------------------------------------------------------------------ characters
def build_vin():
    b = Body(H=1.65, sh_w=0.158, hip_w=0.088, apose=40, head=1.06, neck=0.85, limb=0.84, female=True)
    shirt, pants, boots = hexcol("4a4549"), hexcol("3e3a3f"), hexcol("33291f")
    skin, hair = hexcol("dcb49c"), hexcol("221a15")
    belt = hexcol("3d2b1f")
    H = b.H
    t = torso_table(hips=1.02, waist=0.82, chest=0.84, shoulders=0.84, depth=0.9, bust=0.012)
    b.torso(t, band(shirt, [(0, 0.555 * H, pants), (0.588 * H, 0.606 * H, belt)]))
    b.neck(skin, r=0.046)
    b.head(skin, brow=hexcol("3a2a22"), lips=hexcol("a86e66"), jaw=0.9)
    b.hair_shell(hair, puff=1.05, jag=0.02, back_z=b.head_lm["chin_z"] + 0.03 * b.s, spikes=9)
    for side in (1, -1):
        b.arm(side, color=shirt, radii_scale=0.95)
        b.hand(side, skin, scale=0.95)
        b.leg(side, pants, boot_z=0.2 * H, boot_col=boots, thigh=0.95)
        b.foot(side, boots, scale=0.9, sole=hexcol("0f0c0a"))
    dagger(b, 1)
    # second dagger sheathed at the back of the belt
    s = b.s
    c = v3(-0.07 * s, -0.098 * s, 0.585 * H)
    dd = norm(v3(1, 0, -0.35))
    tube(b.m, [c - dd * 0.1 * s, c + dd * 0.12 * s], [(0.012 * s, 0.024 * s), (0.006 * s, 0.012 * s)], n=6,
         hint=(0, 0, 1), color=hexcol("2a1f18"), weights={"Hips": 0.5, "Spine": 0.5}, cap0="flat", cap1="flat")
    tube(b.m, [c - dd * 0.2 * s, c - dd * 0.1 * s], [0.011 * s, 0.012 * s], n=6, color=hexcol("3a2a20"),
         weights={"Hips": 0.5, "Spine": 0.5}, cap0="flat")
    b.mistcloak(z_hem=0.69, z_collar=0.852, n_strips=16, len_range=(0.52, 0.6), color=hexcol("70757d"),
                color_dark=hexcol("464a51"), cape_scale=0.98, seed=3, tassel_w=0.9)
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak", GLOSS: "Obsidian"}, style="vin")


def build_guard():
    b = Body(H=1.78, sh_w=0.185, hip_w=0.097, apose=40, limb=1.0)
    tunic, pants, boots = hexcol("6e5539"), hexcol("4d463e"), hexcol("3a2a1e")
    skin, steel = hexcol("b98d72"), hexcol("a9aeb5")
    H, s = b.H, b.s
    t = torso_table(chest=1.02, shoulders=1.02)
    b.torso(t, band(tunic, [(0, 0.5 * H, pants)]))
    b.neck(skin)
    b.head(skin, brow=hexcol("3b2a20"), lips=hexcol("8c5d50"))
    b.hair_shell(hexcol("2e241c"), puff=1.04, jag=0.0, back_z=b.head_lm["chin_z"] + 0.06 * s)
    for side in (1, -1):
        b.arm(side, color=band(tunic, [(0, 0.66 * H, hexcol("3a2c20"))]))
        b.hand(side, hexcol("3a2c20"))
        b.leg(side, pants, boot_z=0.24 * H, boot_col=boots)
        b.foot(side, boots, sole=hexcol("120e0b"))
    # tunic skirt
    b.skirt(0.6 * H, 0.42 * H, (0.15 * s, 0.09 * s, 0.1 * s), (0.2 * s, 0.14 * s, 0.15 * s), tunic, rows=5)
    # belt
    tube(b.m, [v3(0, -0.004 * s, 0.585 * H), v3(0, -0.004 * s, 0.615 * H)], [(0.152 * s, 0.09 * s, 0.092 * s)] * 2,
         n=16, ex=2.3, color=hexcol("2a1d14"), weights=b.W(["Hips", "Spine"]))
    # cuirass
    cu = [r for r in t if 0.6 <= r[0] <= 0.815]
    centers = [v3(0, r[4] * s, r[0] * H) for r in cu]
    radii = [((r[1] + 0.014) * s, (r[1] + 0.014) * s, (r[2] + 0.02) * s, (r[3] + 0.016) * s) for r in cu]
    radii[-1] = (radii[-1][0] * 0.82, radii[-1][1] * 0.82, radii[-1][2], radii[-1][3])

    def keel(i, th):
        return 1.0 + 0.06 * math.exp(-((th - 90) / 25.0) ** 2)

    tube(b.m, centers, radii, n=18, ex=2.3, mat=METAL, color=steel, shape=keel,
         weights=b.W(["Spine", "Chest", "UpperChest"]))
    # pauldrons
    for side in (1, -1):
        ua = side_name(side, "UpperArm")
        sh, d = b.S.head(ua), b.S.dir(ua)
        tube(b.m, [sh - d * 0.03 * s, sh + d * 0.04 * s, sh + d * 0.1 * s, sh + d * 0.13 * s],
             [0.068 * s, 0.078 * s, 0.074 * s, 0.07 * s], n=10, hint=(0, 0, 1), arc=(-10, 190), mat=METAL,
             color=hexcol("8e939a"), weights=b.W([ua, side_name(side, "Shoulder")], {side_name(side, "Shoulder"): 0.7}))
    # helmet (kettle hat)
    lm = b.head_lm
    bz = lm["brow_z"] + 0.01 * s
    top = lm["top"] + 0.015 * s
    zs = [bz - 0.012 * s, bz - 0.004 * s, bz, bz + 0.03 * s, bz + 0.06 * s, top - 0.02 * s, top]
    rs = [0.19, 0.19, 0.098, 0.1, 0.096, 0.07, 0.03]
    tube(b.m, [v3(0, -0.01 * s, z) for z in zs], [(r * s, r * s, r * s * 1.05, r * s * 1.1) for r in rs], n=18,
         mat=METAL, color=hexcol("9ca1a8"), weights={"Head": 1.0}, cap0="flat", cap1=0.01 * s)
    tube(b.m, [v3(0, -0.01 * s, top - 0.03 * s), v3(0, -0.01 * s, top + 0.012 * s)], [(0.015 * s, 0.1 * s), (0.008 * s, 0.075 * s)],
         n=6, hint=(0, 1, 0), mat=METAL, color=hexcol("b0b5bb"), weights={"Head": 1.0}, cap1="flat")
    spear(b, 1)
    lantern(b, -1)
    b.sockets["chest"] = ("UpperChest", v3(0, 0.11 * s, 0.72 * H))
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal", GLOW: "Glow"}, style="guard")


def build_hazekiller():
    b = Body(H=1.76, sh_w=0.18, hip_w=0.095, apose=40)
    leather, pants, boots = hexcol("6a4e37"), hexcol("54513c"), hexcol("3a2b1e")
    skin, wood, hood = hexcol("b08a6e"), hexcol("8a6340"), hexcol("4d4b37")
    H, s = b.H, b.s
    t = torso_table(depth=1.02)
    b.torso(t, band(leather, [(0, 0.5 * H, pants), (0.585 * H, 0.61 * H, hexcol("2a1f16"))]))
    b.neck(hood)
    b.head(skin, brow=hexcol("2d2218"), lips=hexcol("80574a"))
    for side in (1, -1):
        b.arm(side, color=band(hexcol("4b3a2b"), []))
        b.hand(side, hexcol("3f2f22"))
        b.leg(side, band(pants, [(0.3 * H, 0.33 * H, hexcol("5c4431"))]), boot_z=0.25 * H, boot_col=boots)
        b.foot(side, boots, sole=hexcol("140f0b"))
        # wooden bracers
        la = side_name(side, "LowerArm")
        e, w = b.S.head(la), b.S.tail(la)
        tube(b.m, [e + (w - e) * 0.3, e + (w - e) * 0.95], [(0.047 * s, 0.043 * s), (0.036 * s, 0.033 * s)], n=8,
             color=wood, weights=b.W([la, side_name(side, "Hand")], {side_name(side, "Hand"): 0.3}))
        # wooden shoulder plates
        ua = side_name(side, "UpperArm")
        sh, d = b.S.head(ua), b.S.dir(ua)
        tube(b.m, [sh - d * 0.02 * s, sh + d * 0.06 * s, sh + d * 0.12 * s], [0.07 * s, 0.075 * s, 0.07 * s], n=8,
             hint=(0, 0, 1), arc=(0, 180), color=wood, weights=b.W([ua, side_name(side, "Shoulder")]))
        # knee guards
        kn = b.S.head(side_name(side, "LowerLeg"))
        tube(b.m, [kn + v3(0, 0.03 * s, 0.05 * s), kn + v3(0, 0.04 * s, -0.06 * s)], [(0.055 * s, 0.03 * s)] * 2,
             n=8, hint=(0, 1, 0), arc=(20, 160), color=wood,
             weights=b.W([side_name(side, "UpperLeg"), side_name(side, "LowerLeg")]))
    # leather tabard skirt
    b.skirt(0.6 * H, 0.44 * H, (0.15 * s, 0.09 * s, 0.1 * s), (0.19 * s, 0.13 * s, 0.14 * s), leather, rows=5,
            arc=(100, 440))
    # wooden lamellar chest plate (front)
    cu = [r for r in t if 0.63 <= r[0] <= 0.79]
    centers = [v3(0, r[4] * s, r[0] * H) for r in cu]
    radii = [((r[1] + 0.012) * s, (r[1] + 0.012) * s, (r[2] + 0.018) * s, (r[3] + 0.012) * s) for r in cu]

    def lam(p, i, th):
        k = int((p[2] / (0.035 * s))) % 2
        return hexcol("7d5836") if k else hexcol("694528")

    tube(b.m, centers, radii, n=16, ex=2.3, arc=(20, 160), color=lam, weights=b.W(["Spine", "Chest", "UpperChest"]))
    # hood / cowl
    lm = b.head_lm
    zs = [lm["chin_z"] - 0.03 * s, lm["chin_z"] + 0.03 * s, lm["eye_z"], lm["brow_z"] + 0.03 * s,
          lm["top"] - 0.02 * s, lm["top"] + 0.02 * s]
    rs = [(0.1, 0.09, 0.12), (0.092, 0.085, 0.11), (0.09, 0.1, 0.112), (0.094, 0.106, 0.115), (0.07, 0.08, 0.09), (0.03, 0.04, 0.04)]

    def hood_shape(i, th):
        # open face: pull the front sector inward (inside the head) below the brow
        if i in (1, 2):
            return 1.0 - 0.28 * math.exp(-((th - 90) / 40.0) ** 2)
        return 1.0

    tube(b.m, [v3(0, -0.012 * s - (0.02 * s if i == 0 else 0), z) for i, z in enumerate(zs)],
         [(r[0] * s, r[0] * s, r[1] * s, r[2] * s) for r in rs], n=16, color=hood, shape=hood_shape,
         weights=b.W(["Head", "Neck", "UpperChest"], {"UpperChest": 0.3, "Neck": 0.4}), cap1=0.01 * s)
    # mask over the lower face
    tube(b.m, [v3(0, 0.0, lm["chin_z"] - 0.005 * s), v3(0, 0.005 * s, lm["chin_z"] + 0.075 * s)],
         [(0.06 * s, 0.088 * s, 0.07 * s), (0.068 * s, 0.098 * s, 0.08 * s)], n=12, arc=(20, 160),
         color=hexcol("2e2c22"), weights={"Head": 1.0})
    staff(b, 1)
    round_shield(b, -1)
    return b, dict(mats={CLOTH: "Cloth"}, style="haze")


def build_thug():
    b = Body(H=2.1, sh_w=0.225, hip_w=0.1, apose=38, head=0.92, neck=1.45, width=1.18, limb=1.28)
    skin, vest, pants, boots = hexcol("a87c62"), hexcol("4e3a2b"), hexcol("5a4e44"), hexcol("3a2a1e")
    wrap = hexcol("8a7a62")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=1.02, chest=1.1, shoulders=1.12, depth=1.05, belly=0.012)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if 0.575 * H < p[2] < 0.605 * H:
            return hexcol("22170f")
        # open vest showing chest
        if 70 < th < 110 and p[2] > 0.61 * H:
            return skin
        if p[2] > 0.82 * H:
            return skin
        return vest

    b.torso(t, tcol, n=18)
    b.neck(skin, r=0.062)
    b.head(skin, brow=hexcol("4a3024"), lips=hexcol("7d5145"), jaw=1.15)
    b.hair_shell(hexcol("3a2a20"), puff=1.02, jag=0.0, back_z=b.head_lm["eye_z"])
    for side in (1, -1):
        def acol(p, i, th, side=side):
            la = b.S.head(side_name(side, "LowerArm"))
            wr = b.S.tail(side_name(side, "LowerArm"))
            if np.dot(p - la, wr - la) / np.dot(wr - la, wr - la) > 0.45:
                return wrap
            return skin
        b.arm(side, color=acol, radii_scale=1.12)
        b.hand(side, skin, scale=1.05)
        b.leg(side, pants, boot_z=0.22 * H, boot_col=boots, thigh=1.05)
        b.foot(side, boots, scale=1.0, sole=hexcol("120e0b"))
    club(b, 1)
    return b, dict(mats={CLOTH: "Cloth"}, style="thug")


def build_coinshot():
    b = Body(H=1.8, sh_w=0.18, hip_w=0.094, apose=40, limb=0.95)
    coat, shirt, pants, boots = hexcol("3a3844"), hexcol("a9a296"), hexcol("35333d"), hexcol("24211f")
    skin, hair = hexcol("c7a088"), hexcol("3a2618")
    H, s = b.H, b.s
    t = torso_table(waist=0.95, shoulders=1.02)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 4 + 26 * max(0.0, (p[2] - 0.66 * H) / (0.16 * H)) and p[2] > 0.66 * H:
            return shirt
        if 0.585 * H < p[2] < 0.61 * H:
            return hexcol("15120f")
        return coat

    b.torso(t, tcol)
    b.neck(shirt, r=0.055)
    b.head(skin, brow=hexcol("3a2618"), lips=hexcol("9a6a5c"))
    b.hair_shell(hair, puff=1.06, jag=0.01, back_z=b.head_lm["chin_z"] + 0.05 * s, spikes=5)
    for side in (1, -1):
        b.arm(side, color=band(coat, [(0, 0.0, coat)]), flare=0.006)
        b.hand(side, hexcol("1a1818"))
        b.leg(side, pants, boot_z=0.27 * H, boot_col=boots)
        b.foot(side, boots, sole=hexcol("0a0808"))
    # long coat tails (open front)
    b.skirt(0.6 * H, 0.27 * H, (0.155 * s, 0.092 * s, 0.1 * s), (0.2 * s, 0.15 * s, 0.17 * s), coat, rows=7,
            arc=(106, 434), leg_share=0.9)
    # coin pouch + buckle
    tube(b.m, [v3(0.13 * s, 0.05 * s, 0.575 * H), v3(0.13 * s, 0.05 * s, 0.53 * H)], [(0.03 * s, 0.022 * s), (0.034 * s, 0.026 * s)],
         n=8, color=hexcol("4a3526"), weights={"Hips": 1.0}, cap0="flat", cap1=0.01 * s)
    box(b.m, v3(0, 0.086 * s, 0.597 * H), (0.04 * s, 0.01 * s, 0.03 * s), mat=METAL, color=hexcol("c8a860"),
        weights={"Hips": 0.5, "Spine": 0.5})
    for k in range(4):
        box(b.m, v3(0.035 * s, 0.1 * s, (0.64 + 0.035 * k) * H), (0.012 * s, 0.008 * s, 0.012 * s), mat=METAL,
            color=hexcol("c8a860"), weights=b.W(["Spine", "Chest", "UpperChest"]))
    b.mistcloak(z_hem=0.66, z_collar=0.86, n_strips=11, len_range=(0.34, 0.4), color=hexcol("5a6370"),
                color_dark=hexcol("363c45"), cape_scale=1.03, seed=7, tassel_w=0.93, arc=(132, 408))
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak", METAL: "Metal"}, style="coinshot")


def build_inquisitor():
    b = Body(H=2.0, sh_w=0.175, hip_w=0.088, apose=38, arm=1.07, head=0.95, neck=0.9, width=0.9, limb=0.82)
    robe, under, red, black = hexcol("4b4a50"), hexcol("242228"), hexcol("8e1b14"), hexcol("161517")
    skin = hexcol("a39a95")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=0.9, chest=0.95, shoulders=1.0, depth=0.9)

    def tcol(p, i, th):
        if 0.58 * H < p[2] < 0.615 * H:
            return red
        if 82 < th < 98 and p[2] > 0.62 * H:
            return red
        return robe

    b.torso(t, tcol)
    b.neck(skin, r=0.045)

    lmh = None

    def tattoo_skin(p, i, th):
        return skin

    b.head(skin, brow=hexcol("403836"), lips=hexcol("6a5552"), eye=(0.05, 0.03, 0.03, 1), gaunt=1.0, jaw=0.95)
    for side in (1, -1):
        def scol(p, i, th, side=side):
            la = b.S.head(side_name(side, "LowerArm"))
            wr = b.S.tail(side_name(side, "LowerArm"))
            f = np.dot(p - la, wr - la) / np.dot(wr - la, wr - la)
            if f > 0.82:
                return red
            return robe
        b.arm(side, color=scol, flare=0.035)
        b.hand(side, skin, scale=1.1)
        b.leg(side, under, boot_z=0.2 * H, boot_col=black, thigh=0.9)
        b.foot(side, black, sole=hexcol("050505"))

    def robe_col(p, i, th):
        if p[2] < 0.075 * H:
            return red
        if p[2] < 0.1 * H:
            return black
        if 84 < th < 96 or 444 < th < 456:
            return black
        return robe

    b.skirt(0.6 * H, 0.03 * H, (0.145 * s, 0.085 * s, 0.095 * s), (0.25 * s, 0.22 * s, 0.26 * s), robe_col,
            rows=9, n=20, leg_share=0.95)
    # high collar
    tube(b.m, [v3(0, -0.01 * s, 0.82 * H), v3(0, -0.02 * s, 0.875 * H)], [(0.085 * s, 0.07 * s, 0.08 * s), (0.08 * s, 0.06 * s, 0.08 * s)],
         n=14, arc=(115, 425), color=under, weights=b.W(["UpperChest", "Neck"]), mat=CLOTH)
    # eye spikes: head plates in the sockets, points jutting from the back of the skull
    lm = b.head_lm
    sp = hexcol("8d9199")
    for e in (lm["eye_l"], lm["eye_r"]):
        fwd = v3(0, 1, 0)
        tube(b.m, [e + fwd * 0.0 * s, e + fwd * 0.018 * s, e + fwd * 0.024 * s], [0.03 * s, 0.03 * s, 0.024 * s], n=12,
             hint=(0, 0, 1), mat=METAL, color=sp, weights={"Head": 1.0}, cap0="flat", cap1=0.006 * s)
        back = v3(e[0] * 0.6, -0.11 * s, e[2] + 0.006 * s)
        tip = back + norm(back - e) * 0.11 * s
        tube(b.m, [back - norm(back - e) * 0.01 * s, back, tip], [0.016 * s, 0.013 * s, 0.0005 * s], n=6, mat=METAL,
             color=sp, weights={"Head": 1.0})
    # back spike between the shoulder blades, point out of the chest
    zc = 0.745 * H
    rb = 0.095 * s * b.P["width"]
    rf = 0.105 * s * b.P["width"]
    tube(b.m, [v3(0, -rb - 0.02 * s, zc), v3(0, -rb - 0.005 * s, zc)], [0.034 * s, 0.03 * s], n=10, hint=(0, 0, 1),
         mat=METAL, color=sp, weights={"UpperChest": 0.6, "Chest": 0.4}, cap0=0.006 * s, cap1="flat")
    tube(b.m, [v3(0, rf - 0.01 * s, zc), v3(0, rf + 0.08 * s, zc + 0.004 * s)], [0.013 * s, 0.0005 * s], n=6,
         mat=METAL, color=sp, weights={"UpperChest": 0.6, "Chest": 0.4}, cap0="flat")
    axe(b, 1)
    b.sockets["chest"] = ("UpperChest", v3(0, 0.1 * s, 0.745 * H))
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal", GLOSS: "Obsidian"}, style="inquisitor")


BUILDERS = {
    "vin": build_vin,
    "guard": build_guard,
    "hazekiller": build_hazekiller,
    "thug": build_thug,
    "coinshot": build_coinshot,
    "inquisitor": build_inquisitor,
}

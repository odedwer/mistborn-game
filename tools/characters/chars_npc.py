"""NPC designs: Kelsier's crew, Vin in a ball gown, nobles, obligators and skaa.

Nobles and skaa are *base* models with dyeable regions (vertex-colour alpha, see
body.dyed) and optional garments (separate G_<name> meshes).  PRESETS are the
named wrapper scenes (noble_man_1 ...) that pick garments/dyes/scale for a base;
POOLS describe what CharacterModel.randomize_variant() may pick for crowds.
"""
from __future__ import annotations

import math

import numpy as np

from anim import Rig, base_params
from body import CLOAK, CLOTH, GLOSS, METAL, Body, dyed, side_name
from chars import band, dagger, torso_table
from meshkit import box, hexcol, lerp, norm, smoothstep, tube, v3


# ----------------------------------------------------------------- utilities
def arm_t(b: Body, side, p):
    """0 at the shoulder, 1 at the elbow, 2 at the wrist."""
    S = b.S
    sh = S.head(side_name(side, "UpperArm"))
    el = S.head(side_name(side, "LowerArm"))
    wr = S.tail(side_name(side, "LowerArm"))
    L1 = el - sh
    t1 = float(np.dot(p - sh, L1) / np.dot(L1, L1))
    if t1 <= 1.0:
        return t1
    L2 = wr - el
    return 1.0 + float(np.dot(p - el, L2) / np.dot(L2, L2))


def posed_dir(b: Body, style: str, bone: str, world_dir):
    """Rest-space direction that points along `world_dir` once `bone` is in the
    style's base (idle) pose.  Used to aim hand-held props (Breeze's cane)."""
    rig = Rig(b.S)
    Q, _ = rig.solve(base_params(style))
    W = np.eye(3)
    chain = []
    n = bone
    while n is not None:
        chain.append(n)
        n = b.S.bones[n][0]
    for n in reversed(chain):
        W = W @ Q[n]
    return norm(W.T @ norm(v3(world_dir)))


def hash01(*xs):
    h = 0
    for x in xs:
        h = (h * 1000003 + int(x)) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFF) / 65535.0


def mottle(col, p, amt=0.08, cell=0.07):
    """Patchy variation (wear, patches, grime) keyed on position."""
    k = hash01(p[0] / cell + 100, p[1] / cell + 100, p[2] / cell + 100)
    f = 1.0 + (k - 0.5) * 2 * amt
    return (min(col[0] * f, 1), min(col[1] * f, 1), min(col[2] * f, 1), col[3] if len(col) > 3 else 1.0)


def belt(b: Body, z, col, r=(0.15, 0.09, 0.095), h=0.028, buckle=None):
    s, H = b.s, b.H
    w = b.P["width"]
    tube(b.m, [v3(0, -0.004 * s, z * H - h * s / 2), v3(0, -0.004 * s, z * H + h * s / 2)],
         [(r[0] * s * w, r[1] * s * w, r[2] * s * w)] * 2, n=16, ex=2.3, color=col, weights=b.W(["Hips", "Spine"]))
    if buckle is not None:
        box(b.m, v3(0, (r[1] * w + 0.004) * s, z * H), (0.035 * s, 0.01 * s, 0.028 * s), mat=METAL, color=buckle,
            weights={"Hips": 0.5, "Spine": 0.5})


def collar(b: Body, col, *, h=0.045, r=(0.07, 0.07, 0.075), arc=(110, 430), z=0.83, mat=CLOTH):
    s, H = b.s, b.H
    tube(b.m, [v3(0, -0.012 * s, z * H), v3(0, -0.018 * s, (z + h) * H)],
         [(r[0] * s, r[1] * s, r[2] * s), (r[0] * 0.95 * s, r[1] * 0.85 * s, r[2] * s)], n=14, arc=arc,
         color=col, weights=b.W(["UpperChest", "Neck"]), mat=mat)


# ---------------------------------------------------------------------- hats
def top_hat(b: Body, col, band_col, *, h=0.19, brim=0.145, tilt=0.0):
    lm = b.head_lm
    s = lm["s"]
    z0 = lm["brow_z"] + 0.028 * s
    y = -0.012 * s + tilt * s
    tube(b.m, [v3(0, y, z0 - 0.008 * s), v3(0, y, z0 + 0.002 * s)], [(brim * s, brim * 1.12 * s)] * 2, n=18,
         color=col, weights={"Head": 1.0}, cap0="flat", cap1="flat")
    zs = [z0, z0 + 0.03 * s, z0 + h * 0.6 * s, z0 + h * s]
    rr = [0.086, 0.086, 0.083, 0.09]
    cols = [band_col, band_col, col, col]
    tube(b.m, [v3(0, y, z) for z in zs], [(r * s, r * 1.16 * s) for r in rr], n=16,
         color=lambda p, i, th: cols[i], weights={"Head": 1.0}, cap1="flat")


def bowler(b: Body, col, band_col):
    lm = b.head_lm
    s = lm["s"]
    z0 = lm["brow_z"] + 0.022 * s
    y = -0.012 * s
    tube(b.m, [v3(0, y, z0 - 0.006 * s), v3(0, y, z0 + 0.004 * s)], [(0.12 * s, 0.14 * s)] * 2, n=16,
         color=col, weights={"Head": 1.0}, cap0="flat", cap1="flat")
    zs = [z0, z0 + 0.022 * s, z0 + 0.06 * s, z0 + 0.1 * s, z0 + 0.118 * s]
    rr = [0.086, 0.087, 0.084, 0.064, 0.03]
    tube(b.m, [v3(0, y, z) for z in zs], [(r * s, r * 1.16 * s) for r in rr], n=16,
         color=lambda p, i, th: band_col if i < 2 else col, weights={"Head": 1.0}, cap1=0.006 * s)


def flat_cap(b: Body, col, *, size=1.0, brim=0.07, droop=0.0):
    """Cloth cap with a stiff peak; size > 1 makes it baggy and oversized (Spook)."""
    lm = b.head_lm
    s = lm["s"]
    z0 = lm["brow_z"] - 0.004 * s
    top = lm["top"] + 0.012 * s * size
    c = [v3(0, -0.01 * s + droop * 0.4 * s, z) for z in np.linspace(z0, top, 6)]
    rr = [0.088, 0.094, 0.1, 0.098, 0.084, 0.05]
    rr = [r * size for r in rr]
    tube(b.m, c, [(r * s, r * 1.15 * s) for r in rr], n=16, color=col, weights={"Head": 1.0}, cap1=0.01 * s)
    # peak: a flattened half-disc out front, angled slightly down
    yb = 0.088 * size * 1.15 * s - 0.01 * s
    pts = [v3(x * s * size, yb + brim * s * math.cos(x / 0.09 * 1.4), z0 + 0.004 * s - 0.012 * s * abs(x) / 0.09)
           for x in (-0.085, -0.05, 0.0, 0.05, 0.085)]
    tube(b.m, pts, [(0.006 * s, 0.012 * s), (0.006 * s, brim * 0.9 * s), (0.006 * s, brim * s), (0.006 * s, brim * 0.9 * s),
                    (0.006 * s, 0.012 * s)], n=6, hint=(0, 0, 1), color=tuple(np.array(col) * np.array([0.8, 0.8, 0.8, 1])),
         weights={"Head": 1.0}, cap0=0.004 * s, cap1=0.004 * s)


def wide_hat(b: Body, col, ribbon, *, brim=0.24, tilt=0.03):
    lm = b.head_lm
    s = lm["s"]
    z0 = lm["brow_z"] + 0.03 * s
    y = -0.02 * s
    zb = [z0 - 0.012 * s + tilt * s, z0 + tilt * s * 0.5]
    tube(b.m, [v3(0, y, zb[0]), v3(0, y, zb[1])], [(brim * s, brim * 1.08 * s), (brim * 0.96 * s, brim * 1.04 * s)], n=22,
         color=col, weights={"Head": 1.0}, cap0="flat", cap1="flat")
    zs = [z0, z0 + 0.03 * s, z0 + 0.07 * s, z0 + 0.09 * s]
    rr = [0.09, 0.088, 0.075, 0.04]
    tube(b.m, [v3(0, y, z) for z in zs], [(r * s, r * 1.14 * s) for r in rr], n=16,
         color=lambda p, i, th: ribbon if i < 2 else col, weights={"Head": 1.0}, cap1=0.01 * s)
    # ribbon tails at the back
    for side in (1, -1):
        a = v3(side * 0.03 * s, y - 0.1 * s, z0 + 0.01 * s)
        tube(b.m, [a, a + v3(side * 0.02 * s, -0.04 * s, -0.12 * s)], [(0.018 * s, 0.004 * s), (0.02 * s, 0.003 * s)],
             n=4, hint=(0, 1, 0), color=ribbon, weights=b.W(["Head", "Neck"]))


def small_hat(b: Body, col, feather):
    """Small tilted lady's hat with a feather."""
    lm = b.head_lm
    s = lm["s"]
    z0 = lm["top"] - 0.03 * s
    c = v3(0.03 * s, 0.01 * s, z0)
    tube(b.m, [c, c + v3(0, 0, 0.012 * s)], [(0.1 * s, 0.1 * s), (0.1 * s, 0.1 * s)], n=14, color=col,
         weights={"Head": 1.0}, cap0="flat", cap1="flat")
    tube(b.m, [c + v3(0, 0, 0.01 * s), c + v3(0, 0, 0.05 * s)], [0.055 * s, 0.05 * s], n=12, color=col,
         weights={"Head": 1.0}, cap1="flat")
    f0 = c + v3(0.04 * s, -0.02 * s, 0.04 * s)
    tube(b.m, [f0, f0 + v3(0.03 * s, -0.05 * s, 0.09 * s), f0 + v3(0.02 * s, -0.12 * s, 0.14 * s)],
         [(0.004 * s, 0.018 * s), (0.004 * s, 0.022 * s), (0.002 * s, 0.004 * s)], n=4, hint=(1, 0, 0), color=feather,
         weights={"Head": 1.0})


def hood(b: Body, col, *, open_front=0.3, rag=False):
    lm = b.head_lm
    s = lm["s"]
    zs = [lm["chin_z"] - 0.04 * s, lm["chin_z"] + 0.03 * s, lm["eye_z"], lm["brow_z"] + 0.03 * s,
          lm["top"] - 0.01 * s, lm["top"] + 0.025 * s]
    rs = [(0.11, 0.09, 0.13), (0.096, 0.085, 0.118), (0.094, 0.1, 0.118), (0.097, 0.106, 0.12), (0.075, 0.084, 0.098),
          (0.03, 0.04, 0.045)]

    def shape(i, th):
        if i in (1, 2):
            return 1.0 - open_front * math.exp(-((th - 90) / 42.0) ** 2)
        if i == 0:
            return 1.0 - 0.1 * math.exp(-((th - 90) / 42.0) ** 2)
        return 1.0

    tube(b.m, [v3(0, -0.014 * s - (0.02 * s if i == 0 else 0), z) for i, z in enumerate(zs)],
         [(r[0] * s, r[0] * s, r[1] * s, r[2] * s) for r in rs], n=16,
         color=(lambda p, i, th: mottle(col, p, 0.12)) if rag else col, shape=shape,
         weights=b.W(["Head", "Neck", "UpperChest"], {"UpperChest": 0.3, "Neck": 0.4}), cap1=0.01 * s)


def headscarf(b: Body, col):
    """Scarf tied over the hair, knot at the nape."""
    lm = b.head_lm
    s = lm["s"]

    def shape(i, th):
        # keep the face clear: pull the front sector inside the head below the hairline
        front = math.exp(-((th - 90) / 50.0) ** 2)
        return 1.0 - 0.3 * front if i < 3 else 1.0

    b.head_shell(col, lm["eye_z"] - 0.01 * s, lm["top"] + 0.006 * s, puff=1.1, add=0.01, n=16, rows=6, shape=shape,
                 cap1=0.012 * s)
    k = v3(0, -0.105 * s, lm["eye_z"] - 0.01 * s)
    tube(b.m, [k, k + v3(0, -0.02 * s, -0.02 * s), k + v3(0.01 * s, -0.03 * s, -0.09 * s)],
         [0.022 * s, 0.018 * s, (0.02 * s, 0.006 * s)], n=6, color=col, weights=b.W(["Head", "Neck"]), cap0=0.01 * s)


def hair_bun(b: Body, col, *, bun=0.045):
    lm = b.head_lm
    s = lm["s"]
    b.hair_shell(col, puff=1.02, jag=0.0, back_z=lm["chin_z"] + 0.07 * s, fringe_z=lm["brow_z"] + 0.03 * s, spikes=4)
    c = v3(0, -0.1 * s, lm["top"] - 0.04 * s)
    tube(b.m, [c + v3(0, 0.02 * s, -0.02 * s), c, c + v3(0, -0.03 * s, 0.03 * s)], [bun * 0.6 * s, bun * s, bun * 0.5 * s],
         n=10, hint=(0, 0, 1), color=col, weights={"Head": 1.0}, cap1=0.02 * s)


def fringe_hair(b: Body, col):
    """Horseshoe of hair round the back and sides of a balding head (Clubs)."""
    lm = b.head_lm
    s = lm["s"]
    b.head_shell(col, lm["eye_z"] - 0.03 * s, lm["brow_z"] + 0.035 * s, puff=1.04, add=0.004, arc=(150, 390), n=14,
                 rows=4)


# --------------------------------------------------------------------- props
def cane(b: Body, side, style, *, length=0.86, wood="1c1410", knob="c0c4c8"):
    """Dueling cane, aimed so it points down and a little forward in the idle pose."""
    o, M = b.hand_frame(side)
    s = b.s
    hb = side_name(side, "Hand")
    d = posed_dir(b, style, hb, (0.05 * side, 0.28, -1.0))
    W = {hb: 1.0}
    tube(b.m, [o - d * 0.03 * s, o + d * length * s], [0.011 * s, 0.009 * s], n=6, color=hexcol(wood), weights=W,
         cap0="flat", cap1="flat")
    tube(b.m, [o + d * (length - 0.03) * s, o + d * (length + 0.005) * s], [0.011 * s, 0.01 * s], n=6, mat=METAL,
         color=hexcol(knob), weights=W, cap1="flat")
    tube(b.m, [o - d * 0.03 * s, o - d * 0.06 * s, o - d * 0.09 * s], [0.012 * s, 0.021 * s, 0.006 * s], n=8,
         mat=METAL, color=hexcol(knob), weights=W)


def bracers(b: Body, col, *, mat=METAL, length=(0.35, 0.92), r=(0.046, 0.037), bands=None):
    for side in (1, -1):
        la = side_name(side, "LowerArm")
        e, w = b.S.head(la), b.S.tail(la)
        s = b.s * b.P["limb"]
        c = (lambda p, i, th: bands if (bands is not None and i in (0, 2)) else col)
        tube(b.m, [e + (w - e) * length[0], e + (w - e) * (length[0] + length[1]) / 2, e + (w - e) * length[1]],
             [(r[0] * s, r[0] * 0.92 * s), ((r[0] + r[1]) / 2 * s, (r[0] + r[1]) / 2 * 0.92 * s), (r[1] * s, r[1] * 0.92 * s)],
             n=10, mat=mat, color=c, weights=b.W([la, side_name(side, "Hand")], {side_name(side, "Hand"): 0.3}),
             cap0="flat", cap1="flat")


def sack(b: Body, col, rope):
    """Sack slung over the back on a rope across the chest."""
    s, H = b.s, b.H
    c = v3(0.02 * s, -0.16 * s * b.P["width"], 0.72 * H)
    tube(b.m, [c + v3(0, 0.02 * s, 0.14 * s), c + v3(0, -0.02 * s, 0.06 * s), c + v3(0, -0.03 * s, -0.08 * s),
               c + v3(0, 0.0, -0.16 * s)], [0.04 * s, 0.1 * s, 0.12 * s, 0.07 * s], n=10, hint=(1, 0, 0),
         color=lambda p, i, th: mottle(col, p, 0.1), weights=b.W(["Chest", "UpperChest", "Spine"]), cap0=0.02 * s,
         cap1=0.03 * s)
    # rope across the chest, shoulder to hip
    w = b.P["width"]
    pts = [v3(0.12 * s * w, -0.02 * s, 0.82 * H), v3(0.02 * s, 0.11 * s * w, 0.74 * H),
           v3(-0.1 * s * w, 0.09 * s * w, 0.64 * H), v3(-0.14 * s * w, -0.02 * s, 0.6 * H)]
    tube(b.m, pts, [0.009 * s] * 4, n=5, color=rope, weights=b.W(["Chest", "UpperChest", "Spine", "Hips"]))


def shawl(b: Body, col, *, low=0.66, fringe=None):
    """Shawl draped over the shoulders, open at the front."""
    s, H = b.s, b.H
    sw = b.P["sh_w"] / 0.18
    W = b.P["width"]
    rows = [(0.845, 0.085, 0.08, 0.08), (0.83, 0.15 * sw, 0.09, 0.1), (0.8, 0.205 * sw, 0.105, 0.112),
            (0.75, 0.2 * sw, 0.11, 0.115), (low, 0.175 * sw, 0.11, 0.12)]
    centers = [v3(0, -0.012 * s, r[0] * H) for r in rows]
    radii = [(r[1] * s * W, r[1] * s * W, r[2] * s * W, r[3] * s * W) for r in rows]

    def c(p, i, th):
        if fringe is not None and i == len(rows) - 1:
            return fringe
        return col

    tube(b.m, centers, radii, n=20, arc=(118, 422), color=c, mat=CLOAK,
         weights=b.W(["Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "RightShoulder", "LeftUpperArm",
                      "RightUpperArm"], {"LeftUpperArm": 0.35, "RightUpperArm": 0.35}))


def apron(b: Body, col, *, z_top=0.6, z_bot=0.3, bib=True, strap=None):
    s, H = b.s, b.H
    w = b.P["width"]
    b.skirt(z_top * H, z_bot * H, (0.16 * s * w, 0.1 * s * w, 0.1 * s * w), (0.19 * s * w, 0.15 * s * w, 0.12 * s * w), col,
            arc=(28, 152), rows=5, n=12, leg_share=0.6)
    if bib:
        # bib: a front panel following the chest
        zs = [z_top, 0.66, 0.72, 0.77]
        cs = [v3(0, 0.0, z * H) for z in zs]
        rr = [(0.155 * s * w, 0.155 * s * w, 0.1 * s * w, 0.1), (0.15 * s * w, 0.15 * s * w, 0.1 * s * w, 0.1),
              (0.16 * s * w, 0.16 * s * w, 0.115 * s * w, 0.1), (0.16 * s * w, 0.16 * s * w, 0.108 * s * w, 0.1)]
        rr = [(a + 0.008 * s, bb + 0.008 * s, c + 0.01 * s, d) for a, bb, c, d in rr]
        tube(b.m, cs, rr, n=16, arc=(52, 128), color=col, weights=b.W(["Hips", "Spine", "Chest", "UpperChest"]))
        sc = strap if strap is not None else col
        for side in (1, -1):
            tube(b.m, [v3(side * 0.07 * s * w, 0.108 * s * w, 0.77 * H), v3(side * 0.085 * s, 0.05 * s, 0.83 * H),
                       v3(side * 0.07 * s, -0.06 * s, 0.832 * H)], [0.01 * s] * 3, n=4, color=sc,
                 weights=b.W(["UpperChest", "Neck", "Chest"]))


# ======================================================================= crew
def build_kelsier():
    b = Body(H=1.85, sh_w=0.183, hip_w=0.094, apose=40, limb=0.98)
    shirt, pants, boots = hexcol("cfc8b8"), hexcol("33333b"), hexcol("2a2420")
    skin, hair = hexcol("d6aa8e"), hexcol("9a7a50")
    scar, scar2 = hexcol("efd2c4"), hexcol("b87a6a")
    H, s = b.H, b.s
    t = torso_table(waist=0.93, shoulders=1.03, chest=1.0)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if 0.582 * H < p[2] < 0.61 * H:
            return hexcol("241a14")
        if abs(th - 90) < 9 and p[2] > 0.76 * H:  # open collar
            return skin
        return shirt

    b.torso(t, tcol)
    b.neck(skin, r=0.05)
    b.head(skin, brow=hexcol("6a5038"), lips=hexcol("a87062"), jaw=1.03)
    b.hair_shell(hair, puff=1.02, jag=0.012, back_z=b.head_lm["chin_z"] + 0.06 * s, spikes=8,
                 fringe_z=b.head_lm["brow_z"] + 0.03 * s)

    def acol(side):
        def f(p, i, th):
            t_ = arm_t(b, side, p)
            if t_ < 0.9:
                return shirt
            if t_ < 1.12:
                return hexcol("bab2a2")  # rolled cuff
            # the Pits of Hathsin: pale criss-cross scars on the forearms
            k = hash01(int(th / 25), int(t_ * 9), side + 5)
            if k > 0.62:
                return scar
            if k < 0.12:
                return scar2
            return skin
        return f

    for side in (1, -1):
        b.arm(side, color=acol(side), n=14)
        b.hand(side, skin)
        b.leg(side, pants, boot_z=0.27 * H, boot_col=boots)
        b.foot(side, boots, sole=hexcol("0e0b09"))
        # rolled-up sleeve bulge above the elbow
        el = b.S.head(side_name(side, "LowerArm"))
        d = b.S.dir(side_name(side, "UpperArm"))
        tube(b.m, [el - d * 0.03 * s, el + d * 0.02 * s], [(0.05 * s, 0.047 * s)] * 2, n=10, color=hexcol("b8b0a0"),
             weights=b.W([side_name(side, "UpperArm"), side_name(side, "LowerArm")]))
    belt(b, 0.596, hexcol("241a14"), buckle=hexcol("8a8a8a"))
    b.mistcloak(z_hem=0.7, z_collar=0.856, n_strips=18, len_range=(0.5, 0.6), color=hexcol("565b64"),
                color_dark=hexcol("2c3036"), cape_scale=1.02, seed=21, tassel_w=0.9)
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak", METAL: "Metal"}, style="kelsier")


def build_dockson():
    b = Body(H=1.76, sh_w=0.19, hip_w=0.1, apose=40, width=1.1, limb=1.05, neck=1.1)
    coat, shirt, vest = hexcol("5c4630"), hexcol("b8ae96"), hexcol("3a3630")
    pants, boots = hexcol("4a4236"), hexcol("2e241c")
    skin, hair = hexcol("c49a7c"), hexcol("3a2818")
    H, s = b.H, b.s
    t = torso_table(hips=1.05, waist=1.06, chest=1.05, shoulders=1.04, depth=1.05, belly=0.012)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 7 and p[2] > 0.74 * H:
            return shirt
        if abs(th - 90) < 24 and p[2] > 0.6 * H:
            return vest
        if 0.585 * H < p[2] < 0.608 * H:
            return hexcol("1e1610")
        return coat

    b.torso(t, tcol)
    b.neck(skin, r=0.058)
    b.head(skin, brow=hexcol("2e2016"), lips=hexcol("8a5c4e"), jaw=1.1)
    b.hair_shell(hair, puff=1.0, jag=0.004, back_z=b.head_lm["chin_z"] + 0.05 * s, fringe_z=b.head_lm["brow_z"] + 0.035 * s,
                 spikes=5)
    b.beard(hexcol("4a3624"), length=0.022, full=False)
    for side in (1, -1):
        b.arm(side, color=band(coat, [(0, 0.0, coat)]), flare=0.008, radii_scale=1.06)
        b.hand(side, skin, scale=1.05)
        b.leg(side, pants, boot_z=0.25 * H, boot_col=boots, thigh=1.05)
        b.foot(side, boots, sole=hexcol("100c09"))
    # knee-length practical coat, open at the front
    b.skirt(0.6 * H, 0.3 * H, (0.165 * s, 0.1 * s, 0.108 * s), (0.2 * s, 0.15 * s, 0.17 * s), coat, rows=6,
            arc=(104, 436), leg_share=0.6)
    collar(b, coat, h=0.04, r=(0.085, 0.078, 0.085))
    # satchel on the left hip
    tube(b.m, [v3(-0.17 * s, 0.02 * s, 0.575 * H), v3(-0.18 * s, 0.02 * s, 0.5 * H)], [(0.025 * s, 0.07 * s), (0.028 * s, 0.075 * s)],
         n=8, hint=(0, 1, 0), color=hexcol("3e2c1e"), weights={"Hips": 0.7, "LeftUpperLeg": 0.3}, cap0="flat", cap1="flat")
    return b, dict(mats={CLOTH: "Cloth"}, style="dockson")


def build_breeze():
    b = Body(H=1.74, sh_w=0.18, hip_w=0.1, apose=40, width=1.12, limb=1.02, neck=1.1)
    coat, vest, shirt = hexcol("4c2640"), hexcol("7e5e22"), hexcol("ebe5d8")
    pants, shoes = hexcol("2c2830"), hexcol("141110")
    skin, hair = hexcol("e0b49c"), hexcol("2a1e18")
    H, s = b.H, b.s
    t = torso_table(hips=1.08, waist=1.14, chest=1.06, shoulders=0.98, depth=1.1, belly=0.045)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 8 and p[2] > 0.74 * H:
            return shirt
        if abs(th - 90) < 30 and p[2] > 0.56 * H:
            # waistcoat with a line of buttons
            return hexcol("c8b070") if abs(th - 90) < 3 and int(p[2] / (0.03 * s)) % 2 == 0 else vest
        return coat

    b.torso(t, tcol)
    b.neck(skin, r=0.058)
    b.head(skin, brow=hexcol("2a1e18"), lips=hexcol("b0746a"), jaw=1.08)
    b.hair_shell(hair, puff=1.04, jag=0.0, back_z=b.head_lm["chin_z"] + 0.055 * s, fringe_z=b.head_lm["brow_z"] + 0.04 * s,
                 spikes=3)
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: hexcol("ebe5d8") if arm_t(b, side, p) > 1.9 else coat,
              flare=0.01, radii_scale=1.06)
        b.hand(side, skin)
        b.leg(side, pants, thigh=1.08)
        b.foot(side, shoes, sole=hexcol("080606"))
    # cravat
    lm = b.head_lm
    tube(b.m, [v3(0, 0.06 * s, 0.815 * H), v3(0, 0.08 * s, 0.79 * H), v3(0, 0.1 * s, 0.75 * H)],
         [(0.03 * s, 0.018 * s), (0.028 * s, 0.02 * s), (0.012 * s, 0.01 * s)], n=6, hint=(0, 1, 0),
         color=hexcol("f4f0e6"), weights=b.W(["UpperChest", "Neck"]), cap1=0.006 * s)
    collar(b, coat, h=0.045, r=(0.08, 0.075, 0.08))
    # tailcoat tails at the back
    b.skirt(0.6 * H, 0.33 * H, (0.17 * s, 0.11 * s, 0.12 * s), (0.18 * s, 0.13 * s, 0.16 * s), coat, rows=5,
            arc=(200, 340), leg_share=0.55, n=12)
    # watch chain
    tube(b.m, [v3(0.06 * s, 0.14 * s, 0.63 * H), v3(0.1 * s, 0.14 * s, 0.61 * H), v3(0.14 * s, 0.12 * s, 0.62 * H)],
         [0.003 * s] * 3, n=4, mat=METAL, color=hexcol("d8b860"), weights=b.W(["Spine", "Hips"]))
    cane(b, 1, "breeze")
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal"}, style="breeze")


def build_ham():
    b = Body(H=1.87, sh_w=0.212, hip_w=0.098, apose=38, width=1.14, limb=1.2, neck=1.15, head=0.97)
    vest, pants, boots = hexcol("5e6470"), hexcol("8a785a"), hexcol("3a2e22")
    skin, hair = hexcol("c29274"), hexcol("2a1e16")
    H, s = b.H, b.s
    t = torso_table(hips=0.96, waist=0.98, chest=1.1, shoulders=1.12, depth=1.08)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if 0.575 * H < p[2] < 0.605 * H:
            return hexcol("2a2018")
        if p[2] > 0.8 * H and abs(th - 90) < 40:
            return skin
        if p[2] > 0.815 * H:
            return skin
        if abs(th - 90) < 3:
            return hexcol("3a3e46")  # vest seam
        return vest

    b.torso(t, tcol, n=18)
    b.neck(skin, r=0.064)
    b.head(skin, brow=hexcol("2a1e16"), lips=hexcol("8a5a4c"), jaw=1.12)
    b.hair_shell(hair, puff=0.98, jag=0.0, back_z=b.head_lm["eye_z"] - 0.01 * s, fringe_z=b.head_lm["top"] - 0.02 * s)
    for side in (1, -1):
        b.arm(side, color=skin, radii_scale=1.12)
        b.hand(side, skin, scale=1.06)
        b.leg(side, pants, boot_z=0.2 * H, boot_col=boots, thigh=1.08)
        b.foot(side, boots, sole=hexcol("120e0b"))
        # leather wrist wraps
        la = side_name(side, "LowerArm")
        e, w = b.S.head(la), b.S.tail(la)
        tube(b.m, [e + (w - e) * 0.72, e + (w - e) * 0.97], [(0.042 * s * 1.2 * 1.12, 0.039 * s * 1.2 * 1.1)] * 2, n=8,
             color=hexcol("4a3624"), weights=b.W([la, side_name(side, "Hand")], {side_name(side, "Hand"): 0.3}))
    # vest armholes: a rim around the shoulders so the sleeveless cut reads
    for side in (1, -1):
        ua = side_name(side, "UpperArm")
        sh = b.S.head(ua)
        tube(b.m, [sh + v3(-side * 0.02 * s, 0, 0.03 * s), sh + v3(side * 0.005 * s, 0, -0.03 * s)],
             [(0.075 * s, 0.07 * s)] * 2, n=10, hint=(0, 1, 0), arc=(200, 520) if side > 0 else (20, 340),
             color=vest, weights=b.W([ua, side_name(side, "Shoulder"), "UpperChest"]))
    belt(b, 0.59, hexcol("2a2018"), r=(0.155, 0.098, 0.1), buckle=hexcol("7a7a7a"))
    # fighting staff slung across the back
    c = v3(0, -0.14 * s, 0.72 * H)
    d = norm(v3(0.7, 0, 1))
    tube(b.m, [c - d * 0.55 * s, c + d * 0.55 * s], [0.017 * s, 0.017 * s], n=6, color=hexcol("6e4e30"),
         weights=b.W(["Chest", "UpperChest"]), cap0=0.008 * s, cap1=0.008 * s)
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal"}, style="ham")


def build_clubs():
    b = Body(H=1.66, sh_w=0.176, hip_w=0.094, apose=40, width=1.02, limb=0.98, head=1.02)
    shirt, apron_c, pants, shoes = hexcol("77705f"), hexcol("6a482c"), hexcol("4a443c"), hexcol("2a221a")
    skin, hair = hexcol("c29a80"), hexcol("aaa69c")
    H, s = b.H, b.s
    t = torso_table(hips=1.0, waist=1.04, chest=1.0, shoulders=0.98, depth=1.04, belly=0.02)
    b.torso(t, band(shirt, [(0, 0.5 * H, pants), (0.585 * H, 0.605 * H, hexcol("2a2018"))]))
    b.neck(skin, r=0.05)
    b.head(skin, brow=hexcol("8a8478"), lips=hexcol("8a605a"), jaw=1.02, gaunt=0.4, bald_top=hexcol("d0a890"))
    fringe_hair(b, hair)
    b.beard(hexcol("9a968c"), length=0.012, full=False)

    def acol(side):
        return lambda p, i, th: shirt if arm_t(b, side, p) < 1.2 else skin

    for side in (1, -1):
        b.arm(side, color=acol(side))
        b.hand(side, skin, scale=1.04)
        b.leg(side, pants, thigh=0.96)
        b.foot(side, shoes, sole=hexcol("0e0b09"))
    apron(b, apron_c, z_top=0.6, z_bot=0.25, strap=hexcol("3a2818"))
    # knotty walking stick in the left hand? No - Clubs limps without one; a hammer hangs from the apron
    c = v3(0.14 * s, 0.1 * s, 0.52 * H)
    tube(b.m, [c + v3(0, 0, 0.05 * s), c - v3(0, 0, 0.18 * s)], [0.012 * s, 0.012 * s], n=6, color=hexcol("5a4028"),
         weights={"Hips": 0.5, "RightUpperLeg": 0.5}, cap0="flat", cap1="flat")
    box(b.m, c + v3(0, 0, 0.06 * s), (0.09 * s, 0.03 * s, 0.03 * s), mat=METAL, color=hexcol("5a5a5e"),
        weights={"Hips": 0.5, "RightUpperLeg": 0.5})
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal"}, style="clubs")


def build_spook():
    b = Body(H=1.76, sh_w=0.165, hip_w=0.088, apose=40, arm=1.05, width=0.84, limb=0.84, neck=0.95, head=0.97)
    shirt, vest, pants, shoes = hexcol("9ea39e"), hexcol("3a4a5c"), hexcol("5a503e"), hexcol("2a2018")
    skin, hair, cap = hexcol("dab69e"), hexcol("5a3a22"), hexcol("4c4a3e")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=0.9, chest=0.92, shoulders=0.95, depth=0.9)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 32 and p[2] > 0.62 * H and not abs(th - 90) < 6:
            return shirt
        if 0.585 * H < p[2] < 0.603 * H:
            return hexcol("2a2018")
        return vest

    b.torso(t, tcol)
    b.neck(skin, r=0.044)
    b.head(skin, brow=hexcol("4a3020"), lips=hexcol("a87468"), jaw=0.92)
    b.hair_shell(hair, puff=1.1, jag=0.03, back_z=b.head_lm["chin_z"] + 0.035 * s, spikes=11,
                 fringe_z=b.head_lm["brow_z"] + 0.004 * s)
    for side in (1, -1):
        # baggy sleeves, a size too big
        b.arm(side, color=lambda p, i, th, side=side: shirt if arm_t(b, side, p) < 1.85 else skin, flare=0.012,
              radii_scale=1.12)
        b.hand(side, skin, scale=0.95)
        b.leg(side, pants, thigh=0.95)
        b.foot(side, shoes, sole=hexcol("100c09"))
    # scarf round the neck
    tube(b.m, [v3(0, -0.01 * s, 0.82 * H), v3(0, -0.01 * s, 0.86 * H)], [(0.068 * s, 0.07 * s, 0.07 * s)] * 2, n=12,
         color=hexcol("7a3a2a"), weights=b.W(["UpperChest", "Neck"]))
    tube(b.m, [v3(0.04 * s, 0.06 * s, 0.83 * H), v3(0.05 * s, 0.1 * s, 0.76 * H), v3(0.045 * s, 0.11 * s, 0.68 * H)],
         [(0.022 * s, 0.006 * s)] * 3, n=4, hint=(0, 1, 0), color=hexcol("7a3a2a"), weights=b.W(["UpperChest", "Chest"]))
    # the oversized cap
    flat_cap(b, cap, size=1.42, brim=0.1, droop=0.035)
    return b, dict(mats={CLOTH: "Cloth"}, style="spook")


def v_robe(base, stripes, period, z_lo, z_hi, slope=0.9, width=0.16):
    """Terris steward pattern: a front panel of stacked V chevrons (lowest at the centre)."""
    def f(p, i, th):
        if math.sin(math.radians(th)) < 0.2 or abs(p[0]) > width:
            return base
        v = (p[2] + slope * abs(p[0])) / period
        if not (z_lo < p[2] < z_hi):
            return base
        k = int(math.floor(v)) % len(stripes)
        return stripes[k]
    return f


def build_sazed():
    b = Body(H=2.02, sh_w=0.178, hip_w=0.09, apose=39, width=0.92, limb=0.9, neck=1.15, head=0.96, arm=1.04)
    robe, gold, rust = hexcol("5c3a22"), hexcol("a8844c"), hexcol("7a2a1a")
    under, shoes = hexcol("3a2a1e"), hexcol("241a12")
    skin, metal = hexcol("b08466"), hexcol("b88a48")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=0.92, chest=0.95, shoulders=0.98, depth=0.92)
    stripes = [gold, rust, robe, rust]
    vcol = v_robe(robe, stripes, 0.11 * s, 0.1 * H, 0.82 * H, slope=1.2, width=0.13 * s)

    def tcol(p, i, th):
        if 0.58 * H < p[2] < 0.61 * H:
            return rust
        if abs(th - 90) < 18 and 0.66 * H < p[2] < 0.82 * H:
            return vcol(p, i, th)
        return robe

    b.torso(t, tcol)
    b.neck(skin, r=0.046)
    b.head(skin, brow=hexcol("3a2a20"), lips=hexcol("8a5a4a"), jaw=0.98, n=22, earrings=(metal, 4),
           bald_top=hexcol("c09474"))
    for side in (1, -1):
        b.arm(side, color=robe, flare=0.03)
        b.hand(side, skin, scale=1.05)
        b.leg(side, under, thigh=0.9)
        b.foot(side, shoes, sole=hexcol("0a0806"))

    def skirt_col(p, i, th):
        if p[2] < 0.06 * H:
            return rust
        return vcol(p, i, th)

    b.skirt(0.6 * H, 0.03 * H, (0.145 * s, 0.088 * s, 0.098 * s), (0.23 * s, 0.2 * s, 0.24 * s), skirt_col,
            rows=18, n=24, leg_share=0.55)
    # V collar
    collar(b, rust, h=0.03, r=(0.08, 0.075, 0.08), arc=(125, 415))
    # metalmind bracers (copper / tin / pewter)
    bracers(b, metal, mat=METAL, length=(0.3, 0.9), r=(0.047, 0.04), bands=hexcol("8a6a3a"))
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal"}, style="sazed")


def build_marsh():
    b = Body(H=1.84, sh_w=0.178, hip_w=0.09, apose=39, width=0.9, limb=0.9, head=0.98)
    robe, stole, under = hexcol("3c3c42"), hexcol("24242a"), hexcol("2a2a2e")
    skin, hair = hexcol("c09c86"), hexcol("4a4038")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=0.9, chest=0.95, shoulders=1.0, depth=0.9)

    def tcol(p, i, th):
        if 0.585 * H < p[2] < 0.61 * H:
            return hexcol("18181c")
        if 70 < th < 110 and p[2] > 0.62 * H and not 84 < th < 96:
            return stole
        return robe

    b.torso(t, tcol)
    b.neck(skin, r=0.047)
    b.head(skin, brow=hexcol("2a241e"), lips=hexcol("7a5a52"), jaw=1.0, gaunt=1.0)
    b.hair_shell(hair, puff=0.98, jag=0.0, back_z=b.head_lm["eye_z"] - 0.005 * s, fringe_z=b.head_lm["brow_z"] + 0.05 * s)
    for side in (1, -1):
        b.arm(side, color=robe, flare=0.02)
        b.hand(side, skin)
        b.leg(side, under, boot_z=0.2 * H, boot_col=hexcol("141214"))
        b.foot(side, hexcol("141214"), sole=hexcol("050505"))

    def robe_col(p, i, th):
        if 76 < th < 104:
            return stole
        if p[2] < 0.06 * H:
            return stole
        return robe

    b.skirt(0.6 * H, 0.04 * H, (0.145 * s, 0.088 * s, 0.096 * s), (0.22 * s, 0.19 * s, 0.23 * s), robe_col,
            rows=8, n=20, leg_share=0.55)
    collar(b, under, h=0.055, r=(0.085, 0.07, 0.08), arc=(115, 425))
    return b, dict(mats={CLOTH: "Cloth"}, style="marsh")


def build_elend():
    """Elend Venture: young noble, slightly rumpled suit, an armful of books."""
    b = Body(H=1.82, sh_w=0.176, hip_w=0.092, apose=40, width=0.94, limb=0.94, head=1.0)
    coat, coat_d = hexcol("2a3448"), hexcol("1e2636")
    vest, shirt, pants = hexcol("6a6a70"), hexcol("e6e0d2"), hexcol("2a2a30")
    shoes, skin, hair = hexcol("1a1512"), hexcol("dcb8a0"), hexcol("5a3e26")
    H, s = b.H, b.s
    t = torso_table(waist=0.92, shoulders=0.98, chest=0.95, depth=0.95)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        # waistcoat buttoned one hole off: the placket is skewed, a shirt tail pokes out
        skew = (p[2] - 0.66 * H) * 0.25
        if abs(th - 90 - skew * 300) < 10 and p[2] > 0.74 * H:
            return shirt
        if 0.555 * H < p[2] < 0.6 * H and 96 < th < 118:
            return shirt  # untucked shirt tail
        if abs(th - 90) < 26 and p[2] > 0.58 * H:
            return vest
        return coat

    b.torso(t, tcol)
    b.neck(shirt, r=0.05)
    b.head(skin, brow=hexcol("4a3020"), lips=hexcol("a87062"), jaw=0.98)
    b.hair_shell(hair, puff=1.1, jag=0.028, back_z=b.head_lm["chin_z"] + 0.05 * s, spikes=9,
                 fringe_z=b.head_lm["brow_z"] + 0.012 * s)
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: shirt if arm_t(b, side, p) > 1.92 else coat, flare=0.008)
        b.hand(side, skin)
        b.leg(side, pants, boot_z=0.1 * H, boot_col=shoes)
        b.foot(side, shoes, sole=hexcol("060505"))
    # loosened cravat hanging askew
    tube(b.m, [v3(0.01 * s, 0.062 * s, 0.81 * H), v3(0.03 * s, 0.09 * s, 0.77 * H), v3(0.045 * s, 0.1 * s, 0.72 * H)],
         [(0.022 * s, 0.006 * s), (0.02 * s, 0.006 * s), (0.016 * s, 0.005 * s)], n=4, hint=(0, 1, 0),
         color=hexcol("7a2a2a"), weights=b.W(["UpperChest", "Chest"]))
    # open frock coat, one collar flipped up
    b.skirt(0.6 * H, 0.36 * H, (0.155 * s, 0.098 * s, 0.108 * s), (0.18 * s, 0.13 * s, 0.15 * s),
            lambda p, i, th: coat_d if i == 4 else coat, rows=5, arc=(112, 428), leg_share=0.6)
    collar(b, coat, h=0.05, r=(0.08, 0.075, 0.08), arc=(115, 300))
    collar(b, coat_d, h=0.07, r=(0.085, 0.08, 0.085), arc=(300, 425))
    # stack of books pinned against the left hip by the left hand
    o, M = b.hand_frame(-1)
    W = {"LeftHand": 1.0}
    cols = [hexcol("6a2a22"), hexcol("2a4a3a"), hexcol("8a6a3a")]
    for k, (w, h, d) in enumerate([(0.17, 0.035, 0.24), (0.15, 0.03, 0.22), (0.16, 0.04, 0.2)]):
        c = o + M[:, 0] * (-0.02 - 0.037 * k) * s + M[:, 1] * 0.02 * s
        box(b.m, c, (h * s, w * s, d * s), frame=M, color=cols[k], weights=W)
    return b, dict(mats={CLOTH: "Cloth"}, style="elend")


# ======================================================================= Vin
def build_vin_gown():
    """Vin disguised as Lady Valette Renoux: pale silk ball gown, gloves, no metal."""
    b = Body(H=1.65, sh_w=0.158, hip_w=0.088, apose=40, head=1.06, neck=0.85, limb=0.84, female=True)
    silk, trim, sash = hexcol("8fb0cc"), hexcol("e8eef2"), hexcol("3e5a7e")
    skin, hair, glove = hexcol("dcb49c"), hexcol("221a15"), hexcol("f0eeea")
    H, s = b.H, b.s
    t = torso_table(hips=1.0, waist=0.78, chest=0.84, shoulders=0.84, depth=0.9, bust=0.014)

    def tcol(p, i, th):
        if p[2] > 0.78 * H:
            return skin  # off-the-shoulder neckline
        if p[2] > 0.765 * H:
            return trim
        if 0.585 * H < p[2] < 0.62 * H:
            return sash
        return silk

    b.torso(t, tcol)
    b.neck(skin, r=0.046)
    b.head(skin, brow=hexcol("3a2a22"), lips=hexcol("b86a66"), jaw=0.9)
    b.hair_shell(hair, puff=1.05, jag=0.012, back_z=b.head_lm["chin_z"] + 0.03 * b.s, spikes=9,
                 fringe_z=b.head_lm["brow_z"] + 0.02 * s)
    # hair ornament: a small silk flower
    lm = b.head_lm
    f = v3(-0.07 * s, 0.02 * s, lm["brow_z"] + 0.04 * s)
    tube(b.m, [f - v3(0.012 * s, 0, 0), f + v3(0.012 * s, 0, 0)], [0.022 * s, 0.018 * s], n=8, color=trim,
         weights={"Head": 1.0}, cap0=0.006 * s, cap1=0.008 * s)

    def acol(side):
        def c(p, i, th):
            t_ = arm_t(b, side, p)
            if t_ < 0.3:
                return trim
            if t_ < 1.05:
                return skin
            return glove
        return c

    for side in (1, -1):
        b.arm(side, color=acol(side), radii_scale=0.93)
        b.hand(side, glove, scale=0.95)
        b.leg(side, silk, thigh=0.92)
        b.foot(side, silk, scale=0.85, sole=hexcol("20242a"))
        # puffed cap sleeves
        ua = side_name(side, "UpperArm")
        sh, d = b.S.head(ua), b.S.dir(ua)
        tube(b.m, [sh - d * 0.03 * s, sh + d * 0.03 * s, sh + d * 0.08 * s], [0.052 * s, 0.062 * s, 0.045 * s], n=10,
             color=silk, weights=b.W([ua, side_name(side, "Shoulder")], {side_name(side, "Shoulder"): 0.5}))

    def skirt_col(p, i, th):
        if p[2] < 0.035 * H:
            return trim
        if i in (5, 6) and int(th / 30) % 2 == 0:
            return hexcol("a4c0d8")  # embroidered band
        return silk

    b.skirt(0.6 * H, 0.0, (0.12 * s, 0.085 * s, 0.1 * s), (0.44 * s, 0.44 * s, 0.5 * s), skirt_col, rows=9, n=24,
            leg_share=0.28, curve=0.75)
    return b, dict(mats={CLOTH: "Cloth"}, style="gown")


# ===================================================================== nobles
GREY = hexcol("767676")
GREY_D = hexcol("4c4c4c")
GREY_L = hexcol("9a9a9a")


def build_noble_man():
    b = Body(H=1.8, sh_w=0.182, hip_w=0.094, apose=40, limb=0.97)
    coat, coat_d = dyed(GREY, 1), dyed(GREY_D, 1)
    vest = dyed(GREY, 2)
    hair = dyed(GREY, 3)
    shirt, pants, shoes = hexcol("eee8dc"), hexcol("26242c"), hexcol("100e0e")
    skin = hexcol("dcb8a0")
    H, s = b.H, b.s
    t = torso_table(waist=0.95, shoulders=1.03, depth=1.0, belly=0.006)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 8 and p[2] > 0.74 * H:
            return shirt
        if abs(th - 90) < 28 and p[2] > 0.57 * H:
            return hexcol("d8c890") if abs(th - 90) < 3 and int(p[2] / (0.03 * s)) % 2 == 0 else vest
        return coat

    b.torso(t, tcol)
    b.neck(shirt, r=0.054)
    b.head(skin, brow=hexcol("3a2a20"), lips=hexcol("a87062"))
    b.hair_shell(hair, puff=1.03, jag=0.006, back_z=b.head_lm["chin_z"] + 0.05 * s, spikes=4,
                 fringe_z=b.head_lm["brow_z"] + 0.035 * s)
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: coat_d if arm_t(b, side, p) > 1.85 else coat, flare=0.008)
        b.hand(side, hexcol("f0ece4"))  # white gloves
        b.leg(side, pants, boot_z=0.23 * H, boot_col=shoes)
        b.foot(side, shoes, sole=hexcol("060505"))
    tube(b.m, [v3(0, 0.058 * s, 0.82 * H), v3(0, 0.086 * s, 0.79 * H), v3(0, 0.098 * s, 0.755 * H)],
         [(0.028 * s, 0.018 * s), (0.026 * s, 0.02 * s), (0.012 * s, 0.01 * s)], n=6, hint=(0, 1, 0),
         color=hexcol("f4f0e6"), weights=b.W(["UpperChest", "Neck"]), cap1=0.006 * s)
    collar(b, coat_d, h=0.05, r=(0.08, 0.075, 0.08))
    with b.garment("tails"):
        b.skirt(0.6 * H, 0.34 * H, (0.16 * s, 0.1 * s, 0.11 * s), (0.18 * s, 0.13 * s, 0.16 * s), coat, rows=5,
                arc=(196, 344), leg_share=0.55, n=12)
    with b.garment("longcoat"):
        b.skirt(0.6 * H, 0.27 * H, (0.158 * s, 0.098 * s, 0.108 * s), (0.2 * s, 0.15 * s, 0.17 * s),
                lambda p, i, th: coat_d if i == 6 else coat, rows=7, arc=(104, 436), leg_share=0.6)
    with b.garment("hat_top"):
        top_hat(b, hexcol("141216"), dyed(GREY_D, 1))
    with b.garment("hat_bowler"):
        bowler(b, hexcol("1e1a18"), dyed(GREY_D, 2))
    with b.garment("cape"):
        shawl(b, coat, low=0.7, fringe=dyed(GREY_L, 2))
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak"}, style="noble_m")


def build_noble_woman():
    b = Body(H=1.66, sh_w=0.156, hip_w=0.086, apose=40, head=1.04, neck=0.85, limb=0.84, female=True)
    gown, gown_d = dyed(GREY, 1), dyed(GREY_D, 1)
    trim = dyed(GREY_L, 2)
    hair = dyed(GREY, 3)
    skin = hexcol("e2c0a8")
    H, s = b.H, b.s
    t = torso_table(hips=1.0, waist=0.78, chest=0.86, shoulders=0.84, depth=0.9, bust=0.016)

    def tcol(p, i, th):
        if p[2] > 0.785 * H:
            return skin
        if p[2] > 0.768 * H:
            return trim
        if 0.585 * H < p[2] < 0.615 * H:
            return trim
        if abs(th - 90) < 14 and p[2] > 0.62 * H:
            return gown_d  # stomacher panel
        return gown

    b.torso(t, tcol)
    b.neck(skin, r=0.045)
    b.head(skin, brow=hexcol("4a3226"), lips=hexcol("b0605c"), jaw=0.88)
    hair_bun(b, hair)
    # necklace
    tube(b.m, [v3(x * s, 0.07 * s - abs(x) * 0.3 * s, 0.8 * H - (0.06 - abs(x)) * 0.35 * s) for x in (-0.06, -0.03, 0, 0.03, 0.06)],
         [0.005 * s] * 5, n=4, mat=METAL, color=hexcol("d8c070"), weights=b.W(["UpperChest", "Neck"]))

    def acol(side):
        def c(p, i, th):
            t_ = arm_t(b, side, p)
            if t_ < 0.35:
                return gown
            if t_ < 1.3:
                return skin
            return trim  # gloves to the elbow
        return c

    for side in (1, -1):
        b.arm(side, color=acol(side), radii_scale=0.93)
        b.hand(side, trim, scale=0.94)
        b.leg(side, gown, thigh=0.92)
        b.foot(side, gown_d, scale=0.85, sole=hexcol("1a1616"))
        ua = side_name(side, "UpperArm")
        sh, d = b.S.head(ua), b.S.dir(ua)
        tube(b.m, [sh - d * 0.03 * s, sh + d * 0.04 * s, sh + d * 0.1 * s], [0.05 * s, 0.058 * s, 0.042 * s], n=10,
             color=gown, weights=b.W([ua, side_name(side, "Shoulder")], {side_name(side, "Shoulder"): 0.5}))

    def skirt_col(p, i, th):
        if p[2] < 0.04 * H:
            return trim
        if i == 7 and int(th / 24) % 2 == 0:
            return gown_d
        return gown

    b.skirt(0.6 * H, 0.0, (0.12 * s, 0.085 * s, 0.1 * s), (0.42 * s, 0.4 * s, 0.5 * s), skirt_col, rows=9, n=22,
            leg_share=0.28, curve=1.1)
    with b.garment("bustle"):
        b.skirt(0.6 * H, 0.2 * H, (0.13 * s, 0.09 * s, 0.13 * s), (0.3 * s, 0.26 * s, 0.4 * s),
                lambda p, i, th: trim if i == 4 else gown_d, arc=(210, 330), rows=5, n=10, leg_share=0.2, curve=0.7)
    with b.garment("hat_wide"):
        wide_hat(b, dyed(GREY_L, 2), dyed(GREY_D, 1))
    with b.garment("hat_small"):
        small_hat(b, dyed(GREY_D, 1), hexcol("f0ece4"))
    with b.garment("shawl"):
        shawl(b, trim, low=0.7)
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak", METAL: "Metal"}, style="gown")


# ================================================================= obligators
def _obligator(b: Body, *, robe, stole, under, skin, rank, hood_cap=None, stout=False):
    H, s = b.H, b.s

    def tcol(p, i, th):
        if 0.585 * H < p[2] < 0.612 * H:
            return stole
        if (68 < th < 84 or 96 < th < 112) and p[2] > 0.6 * H:
            return stole
        return robe

    return tcol


def build_obligator():
    """Senior obligator: tall, thin, grey robes, eye tattoos of a high rank."""
    b = Body(H=1.82, sh_w=0.172, hip_w=0.088, apose=39, width=0.9, limb=0.88, head=0.98, neck=0.95)
    robe, stole, under = hexcol("6e6e74"), hexcol("2e2e36"), hexcol("4a4a50")
    skin, ink = hexcol("dcc0ac"), hexcol("2a2a44")
    H, s = b.H, b.s
    t = torso_table(hips=0.95, waist=0.9, chest=0.94, shoulders=0.98, depth=0.9)
    b.torso(t, _obligator(b, robe=robe, stole=stole, under=under, skin=skin, rank=3))
    b.neck(skin, r=0.045)
    b.head(skin, brow=None, lips=hexcol("9a7068"), jaw=0.94, gaunt=0.6, n=28, tattoo=ink, tattoo_rank=4,
           bald_top=hexcol("e4ccb8"))
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: stole if arm_t(b, side, p) > 1.8 else robe, flare=0.04)
        b.hand(side, skin)
        b.leg(side, under, thigh=0.9)
        b.foot(side, hexcol("1a1a1e"), sole=hexcol("050505"))

    def robe_col(p, i, th):
        if 78 < th < 102:
            return stole
        if p[2] < 0.07 * H:
            return stole
        return robe

    b.skirt(0.6 * H, 0.02 * H, (0.145 * s, 0.086 * s, 0.096 * s), (0.24 * s, 0.21 * s, 0.25 * s), robe_col,
            rows=8, n=20, leg_share=0.5)
    collar(b, stole, h=0.06, r=(0.082, 0.07, 0.078), arc=(112, 428))
    # rank chain across the chest
    tube(b.m, [v3(x * s, 0.1 * s - abs(x) * 0.25 * s, 0.745 * H - (0.08 - abs(x)) * 0.25 * s) for x in (-0.08, -0.04, 0, 0.04, 0.08)],
         [0.005 * s] * 5, n=4, mat=METAL, color=hexcol("a8acb4"), weights=b.W(["UpperChest", "Chest"]))
    return b, dict(mats={CLOTH: "Cloth", METAL: "Metal"}, style="obligator")


def build_obligator_2():
    """Junior obligator: shorter and stout, darker robes and skullcap, fewer tattoo spikes."""
    b = Body(H=1.72, sh_w=0.18, hip_w=0.1, apose=40, width=1.12, limb=1.02, head=1.0, neck=1.05)
    robe, stole, under = hexcol("56565c"), hexcol("8a8a90"), hexcol("3e3e44")
    skin, ink = hexcol("d0ae98"), hexcol("2e2c48")
    H, s = b.H, b.s
    t = torso_table(hips=1.08, waist=1.12, chest=1.04, shoulders=1.0, depth=1.08, belly=0.035)
    b.torso(t, _obligator(b, robe=robe, stole=stole, under=under, skin=skin, rank=1))
    b.neck(skin, r=0.056)
    b.head(skin, brow=hexcol("5a4a40"), lips=hexcol("946a60"), jaw=1.1, n=28, tattoo=ink, tattoo_rank=1)
    lm = b.head_lm
    b.head_shell(hexcol("2c2c32"), lm["brow_z"] + 0.03 * s, lm["top"] + 0.004 * s, puff=1.02, add=0.006, n=16, rows=4,
                 cap1=0.01 * s)
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: stole if arm_t(b, side, p) > 1.8 else robe, flare=0.045,
              radii_scale=1.05)
        b.hand(side, skin, scale=1.04)
        b.leg(side, under, thigh=1.05)
        b.foot(side, hexcol("1a1a1e"), sole=hexcol("050505"))

    def robe_col(p, i, th):
        if 80 < th < 100 or p[2] < 0.06 * H:
            return stole
        return robe

    b.skirt(0.6 * H, 0.025 * H, (0.165 * s, 0.11 * s, 0.11 * s), (0.25 * s, 0.23 * s, 0.25 * s), robe_col,
            rows=8, n=20, leg_share=0.5)
    collar(b, under, h=0.035, r=(0.09, 0.08, 0.085), arc=(112, 428))
    # book of the Balance hanging from the belt
    box(b.m, v3(-0.17 * s, 0.03 * s, 0.53 * H), (0.03 * s, 0.1 * s, 0.13 * s), color=hexcol("3a2a22"),
        weights={"Hips": 0.6, "LeftUpperLeg": 0.4})
    return b, dict(mats={CLOTH: "Cloth"}, style="obligator_b")


# ======================================================================= skaa
def build_skaa_man():
    b = Body(H=1.74, sh_w=0.178, hip_w=0.092, apose=40, width=0.94, limb=0.94, head=1.0)
    tunic, tunic_d = dyed(GREY, 1), dyed(GREY_D, 1)
    pants = dyed(GREY_D, 2)
    hair = dyed(GREY, 3)
    skin, ash = hexcol("b8927a"), hexcol("6a5a50")
    wrap = hexcol("5a5244")
    H, s = b.H, b.s
    t = torso_table(hips=0.96, waist=0.92, chest=0.96, shoulders=0.98, depth=0.94)

    def tcol(p, i, th):
        if p[2] < 0.5 * H:
            return pants
        if abs(th - 90) < 12 and p[2] > 0.76 * H:
            return skin
        c = tunic_d if hash01(int(p[2] / 0.09), int(th / 40), 3) > 0.8 else tunic  # patches
        return mottle(c, p, 0.1)

    b.torso(t, tcol)
    b.neck(skin, r=0.05)

    b.head(skin, brow=hexcol("2a2018"), lips=hexcol("8a6258"), jaw=1.02, gaunt=0.5)
    b.hair_shell(hair, puff=1.06, jag=0.03, back_z=b.head_lm["chin_z"] + 0.04 * s, spikes=10)

    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: mottle(tunic, p) if arm_t(b, side, p) < 1.25 else skin,
              flare=0.006)
        b.hand(side, skin)
        b.leg(side, lambda p, i, th: mottle(pants, p, 0.12) if p[2] > 0.2 * H else wrap, thigh=0.94)
        b.foot(side, wrap, sole=hexcol("2a241e"))
    b.skirt(0.6 * H, 0.4 * H, (0.15 * s, 0.09 * s, 0.1 * s), (0.18 * s, 0.13 * s, 0.14 * s),
            lambda p, i, th: mottle(tunic, p, 0.1), rows=5, n=16, leg_share=0.7, jag=0.05, seed=3)
    # rope belt
    belt(b, 0.595, hexcol("8a7a5a"), r=(0.15, 0.092, 0.1), h=0.018)
    with b.garment("cap"):
        flat_cap(b, dyed(GREY_D, 2), size=1.06, brim=0.05)
    with b.garment("hood"):
        hood(b, tunic_d, open_front=0.32, rag=True)
    with b.garment("sack"):
        sack(b, hexcol("8a7a5e"), hexcol("6a5a42"))
    with b.garment("scarf"):
        tube(b.m, [v3(0, -0.012 * s, 0.815 * H), v3(0, -0.012 * s, 0.855 * H)], [(0.072 * s, 0.074 * s, 0.074 * s)] * 2,
             n=12, color=dyed(GREY_L, 2), weights=b.W(["UpperChest", "Neck"]))
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak"}, style="skaa")


def lambda_skin(skin, ash):
    """Skin with ash smudges."""
    def f(p, i, th):
        k = hash01(int(p[0] / 0.03 + 50), int(p[1] / 0.03 + 50), int(p[2] / 0.03))
        return tuple(lerp(np.array(skin), np.array(ash), 0.35)) if k > 0.86 else skin
    return f


def build_skaa_woman():
    b = Body(H=1.62, sh_w=0.155, hip_w=0.088, apose=40, head=1.04, neck=0.88, limb=0.86, female=True, width=0.95)
    dress, dress_d = dyed(GREY, 1), dyed(GREY_D, 1)
    apron_c = dyed(GREY_L, 2)
    hair = dyed(GREY, 3)
    skin, ash = hexcol("c29e84"), hexcol("6a5a50")
    H, s = b.H, b.s
    t = torso_table(hips=1.02, waist=0.86, chest=0.88, shoulders=0.86, depth=0.92, bust=0.01)

    def tcol(p, i, th):
        if p[2] > 0.8 * H and abs(th - 90) < 25:
            return skin
        c = dress_d if hash01(int(p[2] / 0.08), int(th / 45), 7) > 0.82 else dress
        return mottle(c, p, 0.1)

    b.torso(t, tcol)
    b.neck(skin, r=0.045)
    b.head(skin, brow=hexcol("3a2a20"), lips=hexcol("9a6a60"), jaw=0.9, gaunt=0.3)
    hair_bun(b, hair, bun=0.04)
    for side in (1, -1):
        b.arm(side, color=lambda p, i, th, side=side: mottle(dress, p) if arm_t(b, side, p) < 1.4 else skin,
              radii_scale=0.95, flare=0.006)
        b.hand(side, skin, scale=0.95)
        b.leg(side, skin, thigh=0.9)
        b.foot(side, hexcol("4a4034"), scale=0.88, sole=hexcol("201a14"))
    b.skirt(0.6 * H, 0.12 * H, (0.13 * s, 0.09 * s, 0.1 * s), (0.26 * s, 0.24 * s, 0.26 * s),
            lambda p, i, th: mottle(dress, p, 0.1), rows=7, n=18, leg_share=0.45, jag=0.04, seed=5)
    apron(b, apron_c, z_top=0.61, z_bot=0.24, bib=False)
    belt(b, 0.6, hexcol("5a4a36"), r=(0.14, 0.09, 0.1), h=0.016)
    with b.garment("headscarf"):
        headscarf(b, dyed(GREY_D, 2))
    with b.garment("shawl"):
        shawl(b, dress_d, low=0.68)
    with b.garment("basket"):
        # basket carried on the left hip
        c = v3(-0.22 * s, 0.04 * s, 0.56 * H)
        tube(b.m, [c - v3(0, 0, 0.08 * s), c, c + v3(0, 0, 0.07 * s)], [(0.1 * s, 0.075 * s), (0.12 * s, 0.09 * s),
             (0.125 * s, 0.095 * s)], n=12, hint=(0, 1, 0), color=lambda p, i, th: hexcol("8a6a3e") if (i + int(th / 30)) % 2 else hexcol("6e5230"),
             weights={"Hips": 0.7, "LeftUpperLeg": 0.3}, cap0="flat")
    return b, dict(mats={CLOTH: "Cloth", CLOAK: "Cloak"}, style="skaa")


# ================================================================== registry
BUILDERS = {
    "kelsier": build_kelsier,
    "dockson": build_dockson,
    "breeze": build_breeze,
    "ham": build_ham,
    "clubs": build_clubs,
    "spook": build_spook,
    "sazed": build_sazed,
    "marsh": build_marsh,
    "elend": build_elend,
    "vin_gown": build_vin_gown,
    "noble_man": build_noble_man,
    "noble_woman": build_noble_woman,
    "obligator": build_obligator,
    "obligator_2": build_obligator_2,
    "skaa_man": build_skaa_man,
    "skaa_woman": build_skaa_woman,
}

# Colour palettes (sRGB hex) per dye slot for randomize_variant().
NOBLE_COATS = ["5e1a28", "1c2a4e", "1c3a2a", "2c2c34", "4a2246", "4a3020", "6a5a2a", "20404a"]
NOBLE_ACCENTS = ["a8883a", "9c9ca4", "c8bca0", "8a2222", "2a6a6a", "5a3a6a", "d0c8b8"]
GOWNS = ["8a1a2a", "1e3a7a", "1e5a3a", "7a5a8a", "a8883a", "a85a6a", "d8d0c0", "1a1a24", "3a6a8a", "6a1a4a"]
GOWN_TRIM = ["ece4d4", "c8a650", "b8b8c4", "1a1a1e", "f4f0e8", "8a2a3a"]
HAIR = ["1c1410", "3a2a1e", "6a4a2a", "8a8278", "2a2420", "9a7040", "4a2a1a"]
SKAA_MAIN = ["7a6c56", "5e5a52", "8a7a60", "6a5a48", "5a6068", "7a5a4a", "8a8270", "4e4a44", "6e6a50"]
SKAA_SECOND = ["4e483e", "5a5040", "3e3c38", "6a6050", "7a7262", "8a8274", "5a4a3a"]
SKAA_HAIR = ["1a1410", "2e2218", "4a3a2a", "5a5048", "3a3028"]

POOLS = {
    "noble_man": dict(garment_groups=[["hat_top", "hat_bowler", ""], ["tails", "longcoat"], ["cape", "", "", ""]],
                      palettes=[NOBLE_COATS, NOBLE_ACCENTS, HAIR], scale=[0.95, 1.05]),
    "noble_woman": dict(garment_groups=[["hat_wide", "hat_small", "", ""], ["shawl", "", ""], ["bustle", ""]],
                        palettes=[GOWNS, GOWN_TRIM, HAIR], scale=[0.95, 1.05]),
    "skaa_man": dict(garment_groups=[["cap", "hood", "", ""], ["sack", "", ""], ["scarf", "", ""]],
                     palettes=[SKAA_MAIN, SKAA_SECOND, SKAA_HAIR], scale=[0.93, 1.06]),
    "skaa_woman": dict(garment_groups=[["headscarf", "headscarf", ""], ["shawl", "", ""], ["basket", "", ""]],
                       palettes=[SKAA_MAIN, SKAA_SECOND, SKAA_HAIR], scale=[0.93, 1.05]),
    "obligator": dict(garment_groups=[], palettes=[], scale=[0.96, 1.04]),
    "obligator_2": dict(garment_groups=[], palettes=[], scale=[0.96, 1.04]),
}

# Named variant scenes: id -> (base, garments, dyes (hex per slot), scale)
PRESETS = {
    "noble_man_1": ("noble_man", ["hat_top", "tails"], ["5e1a28", "a8883a", "2a2420"], 1.0),
    "noble_man_2": ("noble_man", ["hat_bowler", "longcoat"], ["1c2a4e", "9c9ca4", "6a4a2a"], 1.03),
    "noble_man_3": ("noble_man", ["tails", "cape"], ["1c3a2a", "c8bca0", "8a8278"], 0.97),
    "noble_woman_1": ("noble_woman", ["hat_wide"], ["8a1a2a", "ece4d4", "3a2a1e"], 1.0),
    "noble_woman_2": ("noble_woman", ["shawl", "bustle"], ["1e3a7a", "c8a650", "9a7040"], 1.03),
    "noble_woman_3": ("noble_woman", ["hat_small", "bustle"], ["1e5a3a", "f4f0e8", "1c1410"], 0.97),
}
# Base models get a default look too (the first preset-like pick).
DEFAULT_VARIANTS = {
    "noble_man": (["tails"], ["2c2c34", "a8883a", "3a2a1e"], 1.0),
    "noble_woman": ([], ["7a5a8a", "ece4d4", "6a4a2a"], 1.0),
    "skaa_man": (["cap"], ["5e5446", "3e3a32", "2e2218"], 1.0),
    "skaa_woman": (["headscarf"], ["6a5a44", "5a5040", "3a3028"], 1.0),
}

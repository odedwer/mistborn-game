"""Procedural animation authoring.

A pose is built from a flat dict of *semantic parameters* (degrees / metres):
spine lean, arm flex/abduction, elbow bend, foot targets (solved with 2-bone IK)...
Every bone rotation Q is expressed in the armature's rest axes (X right, Y forward,
Z up) and composed down the hierarchy, so a Q of Rx(+a) on a hanging limb swings
it forward regardless of the bone's roll.  The Blender side converts
Q -> bone-local quaternions with  L = R_rest^T Q R_rest.
"""
from __future__ import annotations

import math

import numpy as np

from meshkit import Skel, norm, rot_axis, smoothstep, v3

FPS = 30

I3 = np.eye(3)


def Rx(a):
    return rot_axis((1, 0, 0), a)


def Ry(a):
    return rot_axis((0, 1, 0), a)


def Rz(a):
    return rot_axis((0, 0, 1), a)


SIDES = (("r", 1), ("l", -1))


def sname(side, base):
    return ("Right" if side > 0 else "Left") + base


# ------------------------------------------------------------------ parameters
def default_params():
    p = dict(hips_x=0.0, hips_y=0.0, hips_z=0.0, hips_lean=0.0, hips_yaw=0.0, hips_roll=0.0,
             spine_lean=0.0, spine_side=0.0, spine_twist=0.0,
             head_pitch=0.0, head_yaw=0.0, head_roll=0.0, leg_fk=0.0)
    for s, _ in SIDES:
        p.update({f"{s}_abd": 8.0, f"{s}_flex": 0.0, f"{s}_twist": 0.0, f"{s}_elbow": 12.0, f"{s}_wrist": 0.0,
                  f"{s}_wtwist": 0.0, f"{s}_shrug": 0.0, f"{s}_prot": 0.0,
                  f"{s}_fx": 0.0, f"{s}_fy": 0.0, f"{s}_fz": 0.0, f"{s}_fpitch": 0.0, f"{s}_toe": 0.0,
                  f"{s}_kneeout": 0.0,
                  f"{s}_lflex": 0.0, f"{s}_labd": 0.0, f"{s}_knee": 0.0, f"{s}_ankle": 0.0})
    return p


def mix(a: dict, b: dict, t: float) -> dict:
    out = dict(a)
    for k, v in b.items():
        out[k] = a.get(k, 0.0) + (v - a.get(k, 0.0)) * t
    return out


def ease(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def keyed(keys, t, base):
    """keys: [(time, {param: value})].  Params missing from a key take `base`."""
    names = set()
    for _, d in keys:
        names |= set(d)
    full = []
    for tk, d in keys:
        e = {n: d.get(n, base.get(n, 0.0)) for n in names}
        full.append((tk, e))
    out = dict(base)
    if t <= full[0][0]:
        out.update(full[0][1])
        return out
    for (t0, a), (t1, b) in zip(full, full[1:]):
        if t0 <= t <= t1:
            f = ease((t - t0) / max(t1 - t0, 1e-6))
            out.update({n: a[n] + (b[n] - a[n]) * f for n in names})
            return out
    out.update(full[-1][1])
    return out


# ----------------------------------------------------------------- pose solver
class Rig:
    def __init__(self, S: Skel):
        self.S = S
        self.parent = {b: S.bones[b][0] for b in S.order}
        self.order = S.order

    def _rest_abd(self, side):
        d = self.S.dir(sname(side, "UpperArm"))
        return math.degrees(math.atan2(abs(d[0]), -d[2]))

    def solve(self, p: dict) -> tuple[dict, np.ndarray]:
        S = self.S
        Q = {b: I3.copy() for b in S.order}
        Q["Hips"] = Rz(p["hips_yaw"]) @ Rx(-p["hips_lean"]) @ Ry(p["hips_roll"])
        sp = Rz(p["spine_twist"]) @ Rx(-p["spine_lean"]) @ Ry(p["spine_side"])
        for b, k in (("Spine", 0.3), ("Chest", 0.35), ("UpperChest", 0.35)):
            Q[b] = Rz(p["spine_twist"] * k) @ Rx(-p["spine_lean"] * k) @ Ry(p["spine_side"] * k)
        for b, k in (("Neck", 0.4), ("Head", 0.6)):
            Q[b] = Rz(p["head_yaw"] * k) @ Rx(-p["head_pitch"] * k) @ Ry(p["head_roll"] * k)
        for s, side in SIDES:
            ua, la, hb = sname(side, "UpperArm"), sname(side, "LowerArm"), sname(side, "Hand")
            d1, d2, d3 = S.dir(ua), S.dir(la), S.dir(hb)
            Q[sname(side, "Shoulder")] = Ry(-side * p[f"{s}_shrug"]) @ Rz(side * p[f"{s}_prot"])
            rest = self._rest_abd(side)
            Q[ua] = Rx(p[f"{s}_flex"]) @ Ry(side * (rest - p[f"{s}_abd"])) @ rot_axis(d1, side * p[f"{s}_twist"])
            h2 = norm(np.cross(d2, v3(0, 1, 0)))
            Q[la] = rot_axis(h2, p[f"{s}_elbow"])
            h3 = norm(np.cross(d3, v3(0, 1, 0)))
            Q[hb] = rot_axis(h3, p[f"{s}_wrist"]) @ rot_axis(d3, side * p[f"{s}_wtwist"])
        off = v3(p["hips_x"], p["hips_y"], p["hips_z"])
        if p.get("leg_fk", 0.0) > 0.5:
            for s, side in SIDES:
                Q[sname(side, "UpperLeg")] = Rx(p[f"{s}_lflex"]) @ Ry(-side * p[f"{s}_labd"])
                Q[sname(side, "LowerLeg")] = Rx(-p[f"{s}_knee"])
                Q[sname(side, "Foot")] = Rx(p[f"{s}_ankle"])
                Q[sname(side, "Toes")] = Rx(p[f"{s}_toe"])
        else:
            for s, side in SIDES:
                self._leg_ik(Q, off, s, side, p)
        return Q, off

    def _leg_ik(self, Q, off, s, side, p):
        S = self.S
        ul, ll, fb, tb = (sname(side, n) for n in ("UpperLeg", "LowerLeg", "Foot", "Toes"))
        Wh = Q["Hips"]
        hips_head = S.head("Hips") + off
        hipj = hips_head + Wh @ (S.head(ul) - S.head("Hips"))
        L1, L2 = S.length(ul), S.length(ll)
        pitch = p[f"{s}_fpitch"]
        yaw_foot = p["hips_yaw"] * 0.3
        Wf = Rz(yaw_foot) @ Rx(pitch)
        ank_rest, ball_rest = S.head(fb), S.head(tb)
        target = ank_rest + v3(p[f"{s}_fx"], p[f"{s}_fy"], p[f"{s}_fz"])
        # heel lift pivots around the ball: keep ball where the flat foot had it
        if pitch < 0:
            ball = target + (ball_rest - ank_rest)
            target = ball - Wf @ (ball_rest - ank_rest)
        T = target - hipj
        dist = float(np.linalg.norm(T))
        dist_c = min(max(dist, abs(L1 - L2) + 1e-3), L1 + L2 - 1e-4)
        Tn = T / max(dist, 1e-6)
        ca = (L1 * L1 + dist_c * dist_c - L2 * L2) / (2 * L1 * dist_c)
        a = math.acos(min(max(ca, -1.0), 1.0))
        pole = Wh @ norm(v3(side * p[f"{s}_kneeout"] * 0.02, 1, 0))
        pole = norm(pole - Tn * np.dot(pole, Tn))
        thigh = Tn * math.cos(a) + pole * math.sin(a)
        knee = hipj + thigh * L1
        shin = norm(hipj + Tn * dist_c - knee)

        def frame(d, pl):
            pl = norm(pl - d * np.dot(pl, d))
            return np.column_stack([d, pl, np.cross(d, pl)])

        fwd = v3(0, 1, 0)
        A1 = frame(S.dir(ul), fwd)
        B1 = frame(thigh, pole)
        W1 = B1 @ A1.T
        A2 = frame(S.dir(ll), fwd)
        B2 = frame(shin, pole)
        W2 = B2 @ A2.T
        Q[ul] = Wh.T @ W1
        Q[ll] = W1.T @ W2
        Q[fb] = W2.T @ Wf
        Q[tb] = Rx(p[f"{s}_toe"] if pitch >= 0 else -pitch * 0.9 + p[f"{s}_toe"])


# ------------------------------------------------------------------------ styles
STYLES = {
    "vin": dict(base={"r_elbow": 28, "l_elbow": 22, "r_wrist": -10, "r_abd": 10, "l_abd": 9},
                stride=1.0, swing=1.0, hunch=0.0, speed_k=1.0),
    "guard": dict(base={"r_elbow": 82, "r_abd": 9, "r_flex": 8, "r_twist": -8, "r_wrist": -8,
                        "l_elbow": 72, "l_flex": 12, "l_abd": 10, "l_twist": 5},
                  arm_lock={"r", "l"}, stride=1.0, swing=0.35, hunch=0.0),
    "haze": dict(base={"r_elbow": 78, "r_abd": 10, "r_flex": 6, "r_twist": -6, "r_wrist": -6,
                       "l_abd": 16, "l_elbow": 30, "l_flex": 8},
                 arm_lock={"r"}, stride=1.0, swing=0.6, hunch=2.0),
    "thug": dict(base={"r_abd": 22, "l_abd": 22, "r_elbow": 38, "l_elbow": 32, "r_twist": 10, "l_twist": 10,
                       "spine_lean": 9, "head_pitch": -6, "r_shrug": 6, "l_shrug": 6},
                 stride=1.1, swing=0.8, hunch=9.0, wide=0.035),
    "coinshot": dict(base={"r_elbow": 20, "l_elbow": 18, "r_abd": 6, "l_abd": 6}, stride=1.0, swing=1.0, hunch=0.0),
    "inquisitor": dict(base={"r_abd": 12, "l_abd": 12, "r_elbow": 58, "r_flex": 6, "l_elbow": 20, "spine_lean": 6,
                             "head_pitch": 8, "r_wrist": -10},
                       stride=1.12, swing=0.7, hunch=6.0),
    # ---- NPCs (crew, nobles, obligators, skaa)
    "kelsier": dict(base={"r_elbow": 16, "l_elbow": 14, "r_abd": 9, "l_abd": 9, "head_pitch": -4, "spine_lean": -2},
                    stride=1.06, swing=1.0, hunch=0.0),
    "dockson": dict(base={"r_elbow": 24, "l_elbow": 22, "r_abd": 13, "l_abd": 13, "spine_lean": 1},
                    stride=0.95, swing=0.8, hunch=0.0, wide=0.012),
    "breeze": dict(base={"r_elbow": 34, "r_flex": 16, "r_abd": 15, "r_twist": -6, "l_elbow": 48, "l_flex": 14,
                         "l_abd": 16, "l_twist": 12, "spine_lean": -4, "head_pitch": -5},
                   arm_lock={"r"}, stride=0.9, swing=0.5, hunch=0.0, wide=0.01),
    "ham": dict(base={"r_abd": 17, "l_abd": 17, "r_elbow": 24, "l_elbow": 22, "r_shrug": 3, "l_shrug": 3,
                      "head_pitch": -2}, stride=1.05, swing=0.9, hunch=0.0, wide=0.022),
    "clubs": dict(base={"spine_lean": 13, "head_pitch": -12, "r_abd": 13, "l_abd": 12, "r_elbow": 32, "l_elbow": 26,
                        "r_shrug": 4, "l_shrug": 2, "hips_x": -0.02, "r_fy": 0.05},
                  stride=0.8, swing=0.6, hunch=10.0, limp=1.0),
    "spook": dict(base={"spine_lean": 6, "head_pitch": 5, "r_abd": 6, "l_abd": 6, "r_elbow": 12, "l_elbow": 10,
                        "r_shrug": 5, "l_shrug": 5, "r_twist": 8, "l_twist": 8}, stride=1.05, swing=0.9, hunch=4.0),
    "sazed": dict(base={"r_abd": 12, "l_abd": 12, "r_flex": 5, "l_flex": 5, "r_elbow": 68, "l_elbow": 68,
                        "r_twist": -60, "l_twist": -60, "r_wrist": 10, "l_wrist": 10, "head_pitch": 3},
                  arm_lock={"r", "l"}, stride=1.0, swing=0.3, hunch=2.0),
    "marsh": dict(base={"r_abd": 7, "l_abd": 7, "r_elbow": 9, "l_elbow": 9, "head_pitch": 4, "spine_lean": -1},
                  stride=1.0, swing=0.45, hunch=0.0),
    "elend": dict(base={"l_abd": 28, "l_flex": 20, "l_elbow": 76, "l_twist": -90, "r_abd": 9, "r_elbow": 18,
                        "head_pitch": 5, "spine_lean": 3, "head_roll": 3}, arm_lock={"l"}, stride=1.0, swing=0.8,
                  hunch=2.0),
    "gown": dict(base={"r_abd": 13, "l_abd": 13, "r_elbow": 42, "l_elbow": 40, "r_flex": 12, "l_flex": 10,
                       "r_twist": -18, "l_twist": -18, "head_pitch": -3, "spine_lean": -2},
                 stride=0.78, swing=0.45, hunch=0.0),
    "noble_m": dict(base={"r_abd": 10, "l_abd": 10, "r_elbow": 18, "l_elbow": 20, "head_pitch": -5, "spine_lean": -3},
                    stride=1.0, swing=0.7, hunch=0.0),
    "obligator": dict(base={"r_abd": 16, "l_abd": 16, "r_flex": 15, "l_flex": 15, "r_elbow": 68, "l_elbow": 68,
                            "r_twist": -70, "l_twist": -70, "head_pitch": 6, "spine_lean": 2},
                      arm_lock={"r", "l"}, stride=0.95, swing=0.25, hunch=1.0),
    "obligator_b": dict(base={"r_abd": 12, "l_abd": 12, "r_flex": -25, "l_flex": -25, "r_elbow": 52, "l_elbow": 52,
                              "r_twist": -90, "l_twist": -90, "spine_lean": -3, "head_pitch": -4},
                        arm_lock={"r", "l"}, stride=0.9, swing=0.2, hunch=0.0),
    "skaa": dict(base={"spine_lean": 9, "head_pitch": -7, "r_abd": 10, "l_abd": 10, "r_elbow": 22, "l_elbow": 18,
                       "r_shrug": 3, "l_shrug": 3}, stride=0.88, swing=0.65, hunch=8.0),
}


def base_params(style):
    p = default_params()
    p.update(STYLES[style]["base"])
    w = STYLES[style].get("wide", 0.0)
    p["r_fx"] = w
    p["l_fx"] = -w
    return p


# --------------------------------------------------------------------- gaits
def gait(t, T, base, S: Skel, *, stride, lift, duty, bob, drop, lean, arm_amp, elbow_add, sway, yaw,
         style, pitch_on=18.0, pitch_off=-30.0, crouch=False, arm_flex_add=0.0):
    p = dict(base)
    st = STYLES[style]
    ph = (t / T) % 1.0
    stride *= st.get("stride", 1.0)
    for s, side in SIDES:
        f = (ph + (0.0 if side > 0 else 0.5)) % 1.0
        if f < duty:
            u = f / duty
            y = stride / 2 - stride * u
            z = 0.0
            pitch = pitch_on * (1 - smoothstep(0.0, 0.25, u)) + pitch_off * smoothstep(0.7, 1.0, u)
        else:
            u = (f - duty) / (1 - duty)
            y = -stride / 2 + stride * ease(u)
            z = lift * math.sin(math.pi * u) + (0.02 if u < 0.5 else 0.0) * math.sin(math.pi * u * 2)
            pitch = pitch_off * (1 - smoothstep(0.0, 0.45, u)) + pitch_on * smoothstep(0.55, 1.0, u)
        p[f"{s}_fy"] = y
        p[f"{s}_fz"] = z
        p[f"{s}_fpitch"] = pitch
        # arms swing opposite the leg on the same side
        if s not in st.get("arm_lock", set()):
            sw = -math.cos(2 * math.pi * (ph + (0.0 if side > 0 else 0.5))) * arm_amp * st.get("swing", 1.0)
            p[f"{s}_flex"] = base.get(f"{s}_flex", 0.0) + sw + arm_flex_add
            p[f"{s}_elbow"] = base.get(f"{s}_elbow", 12.0) + elbow_add + max(0.0, sw) * 0.5
        else:
            sw = -math.cos(2 * math.pi * (ph + (0.0 if side > 0 else 0.5))) * arm_amp * 0.15
            p[f"{s}_flex"] = base.get(f"{s}_flex", 0.0) + sw
    mid = duty / 2
    p["hips_z"] = -drop + bob * math.cos(4 * math.pi * (ph - mid))
    p["hips_x"] = sway * math.cos(2 * math.pi * (ph - mid))
    p["hips_yaw"] = yaw * math.cos(2 * math.pi * ph)
    p["spine_twist"] = -yaw * 1.3 * math.cos(2 * math.pi * ph)
    p["hips_lean"] = lean * 0.4
    p["spine_lean"] = base.get("spine_lean", 0.0) + lean * 0.6 + st.get("hunch", 0.0) * 0.3
    p["head_pitch"] = base.get("head_pitch", 0.0) - lean * 0.5
    p["hips_roll"] = -sway * 60 * math.cos(2 * math.pi * (ph - mid))
    limp = st.get("limp", 0.0)
    if limp > 0.0:
        # stiff right leg: the hip dips and the body lurches while it bears weight
        k = S.head("Head")[2] / 0.893 / 1.75
        f = ph % 1.0
        on_r = math.sin(math.pi * f / duty) if f < duty else 0.0
        p["hips_z"] -= limp * 0.03 * k * on_r
        p["hips_roll"] += limp * 5.0 * on_r
        p["spine_side"] = -limp * 6.0 * on_r
        p["head_roll"] = limp * 3.0 * on_r
        if f >= duty:
            p["r_fz"] *= 1.0 - 0.55 * limp
            p["r_fpitch"] *= 0.5
    return p


def make_anims(style: str, S: Skel):
    """Returns {name: (n_frames, fn(t)->params, loop, upper_only)}"""
    base = base_params(style)
    H = S.head("Head")[2] / 0.893
    k = H / 1.75
    A = {}

    def add(name, dur, fn, loop=False):
        n = max(2, int(round(dur * FPS)))
        A[name] = (n, fn, loop)

    # ---------------------------------------------------------------- idle
    def idle(t, T=3.0):
        p = dict(base)
        ph = 2 * math.pi * t / T
        br = math.sin(ph)
        p["spine_lean"] = base.get("spine_lean", 0.0) - 1.5 * br
        p["r_shrug"] = base.get("r_shrug", 0.0) + 1.5 * br
        p["l_shrug"] = base.get("l_shrug", 0.0) + 1.5 * br
        p["head_pitch"] = base.get("head_pitch", 0.0) + 1.2 * br
        p["hips_z"] = -0.005 * k + 0.002 * k * math.sin(ph)
        p["hips_x"] = 0.01 * k * math.sin(ph / 1.0 + 1)
        p["hips_roll"] = -0.8 * math.sin(ph + 1)
        p["r_fx"], p["l_fx"] = base["r_fx"] + 0.01 * k, base["l_fx"] - 0.01 * k
        p["r_fy"], p["l_fy"] = 0.03 * k, -0.02 * k
        p["r_flex"] = base.get("r_flex", 0.0) + 1.5 * br
        p["l_flex"] = base.get("l_flex", 0.0) - 1.5 * br
        return p

    add("idle", 3.0, idle, True)

    add("walk", 1.05, lambda t: gait(t, 1.05, base, S, stride=0.62 * k, lift=0.1 * k, duty=0.6, bob=0.008 * k,
                                     drop=0.01 * k, lean=3, arm_amp=16, elbow_add=5, sway=0.018 * k, yaw=6,
                                     style=style), True)
    add("run", 0.72, lambda t: gait(t, 0.72, base, S, stride=1.05 * k, lift=0.22 * k, duty=0.4, bob=0.02 * k,
                                    drop=0.035 * k, lean=10, arm_amp=38, elbow_add=62, sway=0.012 * k, yaw=10,
                                    style=style, pitch_on=10, pitch_off=-40, arm_flex_add=8), True)
    add("sprint", 0.6, lambda t: gait(t, 0.6, base, S, stride=1.35 * k, lift=0.28 * k, duty=0.34, bob=0.022 * k,
                                      drop=0.045 * k, lean=20, arm_amp=55, elbow_add=75, sway=0.008 * k, yaw=12,
                                      style=style, pitch_on=5, pitch_off=-50, arm_flex_add=12), True)

    def crouch_base(p, t, T):
        p["hips_z"] = -0.30 * k
        p["hips_lean"] = 18
        p["spine_lean"] = base.get("spine_lean", 0.0) + 12
        p["head_pitch"] = base.get("head_pitch", 0.0) - 22
        p["r_kneeout"] = p["l_kneeout"] = 4
        for s, side in SIDES:
            p[f"{s}_fx"] = base[f"{s}_fx"] + side * 0.04 * k
            if s not in STYLES[style].get("arm_lock", set()):
                p[f"{s}_flex"] = base.get(f"{s}_flex", 0.0) + 22
                p[f"{s}_elbow"] = base.get(f"{s}_elbow", 12.0) + 30
                p[f"{s}_abd"] = base.get(f"{s}_abd", 8.0) + 6
        return p

    def crouch_idle(t, T=3.0):
        p = crouch_base(dict(base), t, T)
        br = math.sin(2 * math.pi * t / T)
        p["spine_lean"] += 1.5 * br
        p["hips_z"] += 0.004 * k * br
        p["r_fy"], p["l_fy"] = 0.1 * k, -0.08 * k
        p["head_yaw"] = 10 * math.sin(2 * math.pi * t / T)
        return p

    add("crouch_idle", 3.0, crouch_idle, True)

    def crouch_walk(t, T=1.2):
        g = gait(t, T, base, S, stride=0.5 * k, lift=0.07 * k, duty=0.62, bob=0.01 * k, drop=0.0, lean=0,
                 arm_amp=10, elbow_add=0, sway=0.02 * k, yaw=5, style=style, pitch_on=8, pitch_off=-15)
        p = crouch_base(dict(g), t, T)
        p["hips_z"] += g["hips_z"]
        return p

    add("crouch_walk", 1.2, crouch_walk, True)

    # ---------------------------------------------------------------- air
    def fall(t, T=0.8):
        p = dict(base)
        ph = 2 * math.pi * t / T
        p["leg_fk"] = 1.0
        p["r_lflex"] = 30 + 8 * math.sin(ph)
        p["l_lflex"] = 12 - 8 * math.sin(ph)
        p["r_knee"] = 55 + 8 * math.sin(ph)
        p["l_knee"] = 30 - 6 * math.sin(ph)
        p["r_ankle"] = p["l_ankle"] = -15
        p["r_labd"] = p["l_labd"] = 6
        for s, side in SIDES:
            if s not in STYLES[style].get("arm_lock", set()):
                p[f"{s}_abd"] = 55 + 8 * math.sin(ph + side)
                p[f"{s}_flex"] = 20 + 6 * math.sin(ph * 1 + side)
                p[f"{s}_elbow"] = 35
        p["spine_lean"] = base.get("spine_lean", 0.0) + 6
        p["head_pitch"] = base.get("head_pitch", 0.0) + 8
        return p

    add("fall", 0.8, fall, True)

    crouch_land = {"hips_z": -0.2 * k, "hips_lean": 12, "spine_lean": 14, "head_pitch": -8,
                   "r_flex": 25, "l_flex": 25, "r_elbow": 40, "l_elbow": 40, "r_abd": 20, "l_abd": 20,
                   "r_kneeout": 5, "l_kneeout": 5}
    for s in ("r", "l"):
        if s in STYLES[style].get("arm_lock", set()):
            for key in ("flex", "elbow", "abd"):
                crouch_land.pop(f"{s}_{key}")

    def jump(t):
        keys = [
            (0.0, {}),
            (0.12, dict(crouch_land, r_flex=-25, l_flex=-25, hips_z=-0.14 * k)),
            (0.3, {"hips_z": 0.04 * k, "r_fpitch": -35, "l_fpitch": -35, "r_flex": 60, "l_flex": 50,
                   "r_abd": 18, "l_abd": 18, "spine_lean": -4, "head_pitch": -8}),
            (0.45, {"hips_z": 0.05 * k, "r_fz": 0.1 * k, "l_fz": 0.12 * k, "r_fpitch": -25, "l_fpitch": -25,
                    "r_flex": 45, "l_flex": 40, "r_abd": 30, "l_abd": 30, "spine_lean": 2}),
        ]
        keys = [(tk, {kk: vv for kk, vv in d.items()
                      if not (kk[:2] in ("r_", "l_") and kk[0] in STYLES[style].get("arm_lock", set())
                              and kk.split("_")[1] in ("flex", "elbow", "abd"))}) for tk, d in keys]
        return keyed(keys, t, base)

    add("jump", 0.45, jump)

    def land(t):
        return keyed([(0.0, dict(crouch_land, hips_z=-0.05 * k)), (0.1, crouch_land), (0.5, {})], t, base)

    add("land", 0.5, land)

    # ----------------------------------------------------------- one-shots
    def throw(t):
        return keyed([
            (0.0, {}),
            (0.2, {"r_abd": 55, "r_flex": -20, "r_elbow": 105, "r_twist": 40, "spine_twist": -22, "spine_lean": -4,
                   "l_flex": 35, "l_elbow": 40, "hips_yaw": -8}),
            (0.34, {"r_abd": 30, "r_flex": 95, "r_elbow": 10, "r_twist": 0, "r_wrist": 20, "spine_twist": 18,
                    "spine_lean": 8, "l_flex": -10, "hips_yaw": 6}),
            (0.46, {"r_abd": 20, "r_flex": 70, "r_elbow": 20, "spine_twist": 14, "spine_lean": 6}),
            (0.75, {}),
        ], t, base)

    add("throw", 0.75, throw)

    def melee(t):
        return keyed([
            (0.0, {}),
            (0.14, {"r_abd": 80, "r_flex": 20, "r_elbow": 85, "r_twist": 30, "r_wrist": -20, "spine_twist": -25,
                    "hips_yaw": -8, "l_flex": 30, "l_elbow": 50, "spine_lean": 4}),
            (0.28, {"r_abd": 35, "r_flex": 85, "r_elbow": 25, "r_twist": -40, "r_wrist": 25, "spine_twist": 28,
                    "hips_yaw": 8, "spine_lean": 10, "l_flex": -10}),
            (0.36, {"r_abd": 18, "r_flex": 70, "r_elbow": 35, "r_twist": -50, "spine_twist": 30, "spine_lean": 10}),
            (0.6, {}),
        ], t, base)

    add("melee", 0.6, melee)

    atk = {
        "guard": [  # spear thrust
            (0.0, {}),
            (0.22, {"r_flex": -25, "r_elbow": 70, "r_abd": 14, "r_wrist": 5, "r_twist": -8, "spine_twist": -18,
                    "hips_yaw": -10, "l_flex": 20, "l_elbow": 60, "r_fy": -0.08 * k, "l_fy": 0.12 * k}),
            (0.38, {"r_flex": 60, "r_elbow": 5, "r_abd": 6, "r_wrist": -35, "r_twist": -8, "spine_twist": 20,
                    "spine_lean": 10, "hips_yaw": 10, "l_flex": 5, "r_fy": -0.08 * k, "l_fy": 0.2 * k,
                    "hips_y": 0.08 * k, "hips_z": -0.05 * k}),
            (0.55, {"r_flex": 52, "r_elbow": 10, "r_wrist": -30, "spine_twist": 16, "spine_lean": 8,
                    "r_fy": -0.08 * k, "l_fy": 0.2 * k, "hips_y": 0.07 * k, "hips_z": -0.05 * k}),
            (0.9, {}),
        ],
        "haze": [  # overhead staff strike
            (0.0, {}),
            (0.28, {"r_abd": 40, "r_flex": 150, "r_elbow": 60, "r_twist": 10, "r_wrist": 20, "spine_lean": -8,
                    "spine_twist": -15, "l_flex": 30, "l_elbow": 60, "hips_yaw": -8}),
            (0.45, {"r_abd": 15, "r_flex": 55, "r_elbow": 5, "r_wrist": -30, "spine_lean": 22, "spine_twist": 12,
                    "hips_yaw": 6, "hips_z": -0.08 * k, "l_fy": 0.15 * k, "r_fy": -0.1 * k}),
            (0.6, {"r_abd": 15, "r_flex": 45, "r_elbow": 10, "r_wrist": -20, "spine_lean": 20, "hips_z": -0.08 * k,
                   "l_fy": 0.15 * k, "r_fy": -0.1 * k}),
            (0.95, {}),
        ],
        "thug": [  # overhead club smash
            (0.0, {}),
            (0.35, {"r_abd": 35, "r_flex": 165, "r_elbow": 75, "r_wrist": 25, "l_abd": 40, "l_flex": 40,
                    "spine_lean": -10, "spine_twist": -12, "head_pitch": -10}),
            (0.52, {"r_abd": 12, "r_flex": 60, "r_elbow": 5, "r_wrist": -25, "spine_lean": 30, "spine_twist": 14,
                    "hips_z": -0.12 * k, "l_fy": 0.18 * k, "r_fy": -0.08 * k, "l_flex": -20}),
            (0.7, {"r_abd": 12, "r_flex": 45, "r_elbow": 10, "spine_lean": 26, "hips_z": -0.12 * k,
                   "l_fy": 0.18 * k, "r_fy": -0.08 * k}),
            (1.1, {}),
        ],
        "inquisitor": [  # diagonal axe chop
            (0.0, {}),
            (0.25, {"r_abd": 95, "r_flex": 60, "r_elbow": 70, "r_twist": 30, "spine_twist": -30, "spine_lean": -6,
                    "hips_yaw": -10, "l_flex": 30, "l_abd": 25, "head_pitch": 0}),
            (0.42, {"r_abd": 25, "r_flex": 70, "r_elbow": 10, "r_twist": -30, "r_wrist": -20, "spine_twist": 32,
                    "spine_lean": 18, "hips_yaw": 10, "hips_z": -0.07 * k, "l_fy": 0.15 * k}),
            (0.58, {"r_abd": 18, "r_flex": 50, "r_elbow": 20, "r_twist": -35, "spine_twist": 30, "spine_lean": 16,
                    "hips_z": -0.07 * k, "l_fy": 0.15 * k}),
            (0.9, {}),
        ],
    }
    atk["vin"] = None
    atk["coinshot"] = None
    if atk.get(style):
        keys = atk[style]
        add("attack", keys[-1][0], lambda t, keys=keys: keyed(keys, t, base))
    else:
        # dagger slash (vin) / coin throw + push (coinshot)
        add("attack", 0.6, melee if style == "vin" else throw)

    def hit(t):
        return keyed([
            (0.0, {}),
            (0.08, {"spine_lean": -16, "head_pitch": -18, "hips_z": -0.04 * k, "hips_y": -0.04 * k,
                    "r_abd": 30, "l_abd": 30, "r_elbow": 50, "l_elbow": 50, "spine_twist": 8, "hips_lean": -4}),
            (0.2, {"spine_lean": -8, "head_pitch": -6, "hips_z": -0.05 * k, "hips_y": -0.03 * k}),
            (0.5, {}),
        ], t, base)

    add("hit", 0.5, hit)

    def die(t):
        fk = {"leg_fk": 1.0}
        stand = dict(fk, r_lflex=0, l_lflex=0, r_knee=0, l_knee=0, r_ankle=0, l_ankle=0)
        leg_h = S.head("Hips")[2]
        return keyed([
            (0.0, stand),
            (0.2, dict(fk, spine_lean=-10, head_pitch=-20, r_abd=35, l_abd=35, r_elbow=40, l_elbow=40,
                       hips_z=-0.04 * k, r_lflex=5, l_lflex=5, r_knee=10, l_knee=10)),
            (0.55, dict(fk, hips_z=-0.42 * leg_h, hips_lean=-35, hips_y=-0.1 * k, spine_lean=-10, head_pitch=-15,
                        r_lflex=85, l_lflex=75, r_knee=120, l_knee=110, r_ankle=30, l_ankle=25, r_abd=45, l_abd=40,
                        r_flex=30, l_flex=20, r_elbow=50, l_elbow=40)),
            (0.95, dict(fk, hips_z=-leg_h + 0.12 * k, hips_lean=-88, hips_y=-0.3 * k, spine_lean=-4,
                        head_pitch=10, head_yaw=25, r_lflex=12, l_lflex=28, r_knee=20, l_knee=45, r_labd=10,
                        l_labd=8, r_ankle=30, l_ankle=30, r_abd=80, l_abd=70, r_flex=10, l_flex=-5,
                        r_elbow=30, l_elbow=45)),
            (1.3, dict(fk, hips_z=-leg_h + 0.11 * k, hips_lean=-90, hips_y=-0.32 * k, spine_lean=0,
                       head_pitch=12, head_yaw=30, r_lflex=8, l_lflex=24, r_knee=12, l_knee=40, r_labd=12,
                       l_labd=9, r_ankle=25, l_ankle=25, r_abd=85, l_abd=72, r_flex=5, l_flex=-8,
                       r_elbow=25, l_elbow=40)),
        ], t, base)

    add("die", 1.3, die)

    blocks = {
        "haze": {"l_flex": 70, "l_abd": 25, "l_elbow": 95, "l_twist": 75, "spine_twist": 10, "spine_lean": 6,
                 "r_flex": -10, "hips_z": -0.05 * k, "l_fy": 0.12 * k},
        "guard": {"r_flex": 35, "r_abd": 40, "r_elbow": 80, "r_twist": 60, "r_wrist": -10, "l_flex": 40,
                  "l_elbow": 90, "l_abd": 30, "spine_lean": 4, "hips_z": -0.05 * k, "l_fy": 0.12 * k},
    }
    bk = blocks.get(style, {"r_flex": 65, "l_flex": 70, "r_abd": 28, "l_abd": 28, "r_elbow": 115,
                            "l_elbow": 118, "r_twist": 50, "l_twist": 50, "spine_lean": 8, "head_pitch": 12,
                            "hips_z": -0.06 * k, "l_fy": 0.1 * k, "r_fy": -0.05 * k})

    def block(t):
        return keyed([(0.0, {}), (0.12, bk), (0.6, bk), (0.85, {})], t, base)

    add("block", 0.85, block)

    def alert(t):
        up = {"spine_lean": -6, "head_pitch": -8, "r_abd": 22, "l_abd": 22, "r_elbow": 45, "l_elbow": 45,
              "hips_z": 0.01 * k, "r_shrug": 8, "l_shrug": 8}
        return keyed([
            (0.0, {}),
            (0.1, up),
            (0.4, dict(up, head_yaw=45, spine_twist=15)),
            (0.75, dict(up, head_yaw=-45, spine_twist=-15)),
            (1.05, dict(up, head_yaw=0)),
            (1.3, {}),
        ], t, base)

    add("alert", 1.3, alert)

    def push(t):
        return keyed([
            (0.0, {}),
            (0.14, {"r_abd": 18, "r_flex": 45, "r_elbow": 115, "r_twist": -10, "r_wrist": 20, "spine_twist": -14,
                    "spine_lean": 4}),
            (0.26, {"r_abd": 12, "r_flex": 88, "r_elbow": 0, "r_twist": -60, "r_wrist": 65, "spine_twist": 12,
                    "spine_lean": -6, "head_pitch": -4, "l_flex": -15, "l_elbow": 30}),
            (0.42, {"r_abd": 12, "r_flex": 85, "r_elbow": 4, "r_twist": -60, "r_wrist": 60, "spine_twist": 10,
                    "spine_lean": -4}),
            (0.65, {}),
        ], t, base)

    add("push", 0.65, push)

    def pull(t):
        return keyed([
            (0.0, {}),
            (0.18, {"r_abd": 12, "r_flex": 92, "r_elbow": 2, "r_twist": -20, "r_wrist": -15, "spine_twist": 16,
                    "spine_lean": 10}),
            (0.3, {"r_abd": 12, "r_flex": 88, "r_elbow": 5, "r_twist": -20, "r_wrist": 25, "spine_twist": 14,
                   "spine_lean": 10}),
            (0.44, {"r_abd": 30, "r_flex": 10, "r_elbow": 125, "r_twist": 30, "r_wrist": 30, "spine_twist": -18,
                    "spine_lean": -10, "head_pitch": -6, "hips_y": -0.03 * k}),
            (0.75, {}),
        ], t, base)

    add("pull", 0.75, pull)

    def drink(t):
        mouth = {"r_abd": 25, "r_flex": 55, "r_elbow": 140, "r_twist": 55, "r_wrist": 25, "head_pitch": -28,
                 "spine_lean": -6}
        return keyed([(0.0, {}), (0.35, mouth), (0.55, dict(mouth, head_pitch=-34)), (1.0, dict(mouth, head_pitch=-30)),
                      (1.4, {})], t, base)

    add("drink", 1.4, drink)

    def talk(t):
        # conversational gesture: right hand opens palm-up, a nod, a small shrug of the left
        g = {"r_abd": 22, "r_flex": 42, "r_elbow": 78, "r_twist": -30, "r_wrist": 18, "head_pitch": 3,
             "head_yaw": 6, "spine_twist": 5, "l_flex": 10, "l_elbow": 30, "l_abd": 14, "l_twist": 0}
        return keyed([
            (0.0, {}),
            (0.3, g),
            (0.55, dict(g, r_flex=48, r_elbow=66, r_wrist=-6, head_pitch=-4, r_abd=26)),
            (0.85, dict(g, r_flex=38, r_abd=32, r_elbow=82, head_pitch=6, head_yaw=-5, l_shrug=6)),
            (1.15, dict(g, r_flex=44, r_elbow=72, head_pitch=0, l_shrug=0)),
            (1.6, {}),
        ], t, base)

    add("talk", 1.6, talk)
    return A


ANIM_NAMES = ["idle", "walk", "run", "sprint", "crouch_idle", "crouch_walk", "fall", "jump", "land",
              "throw", "melee", "attack", "hit", "die", "block", "alert", "push", "pull", "drink", "talk"]
LOOPING = {"idle", "walk", "run", "sprint", "crouch_idle", "crouch_walk", "fall"}

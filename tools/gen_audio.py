#!/usr/bin/env python3
"""Procedural SFX / ambience / music generator for Mistborn: Ashes of Luthadel.

Everything is synthesized (additive/FM/modal synthesis, filtered noise,
envelopes, a synthetic convolution reverb) -- no samples, no network access.
Deterministic (fixed seeds). Output is OGG Vorbis via libsndfile.

Usage:
    python3 tools/gen_audio.py [--out assets/audio]
"""
from __future__ import annotations

import argparse
import os
import numpy as np
import soundfile as sf

SR = 44100

# --------------------------------------------------------------------------
# Low-level DSP helpers
# --------------------------------------------------------------------------

def rng_for(name: str, base: int = 20260925) -> np.random.Generator:
    import zlib
    return np.random.default_rng(base + zlib.crc32(name.encode("utf-8")))


def t_axis(dur: float, sr: int = SR) -> np.ndarray:
    return np.arange(int(dur * sr)) / sr


def env_adsr(n: int, sr: int, attack=0.01, decay=0.1, sustain=0.6, release=0.2) -> np.ndarray:
    a = max(1, int(attack * sr))
    d = max(1, int(decay * sr))
    r = max(1, int(release * sr))
    s = max(0, n - a - d - r)
    env = np.concatenate([
        np.linspace(0, 1, a, endpoint=False),
        np.linspace(1, sustain, d, endpoint=False),
        np.full(max(s, 0), sustain),
        np.linspace(sustain, 0, r),
    ])
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def env_exp_decay(n: int, sr: int, tau: float) -> np.ndarray:
    t = np.arange(n) / sr
    return np.exp(-t / max(tau, 1e-6))


def env_fade_io(n: int, sr: int, fade: float = 0.01) -> np.ndarray:
    f = max(1, int(fade * sr))
    env = np.ones(n)
    env[:f] = np.linspace(0, 1, f)
    env[-f:] = np.linspace(1, 0, f)
    return env


def one_pole_lowpass(x: np.ndarray, cutoff_hz: float, sr: int = SR) -> np.ndarray:
    rc = 1.0 / (2 * np.pi * max(cutoff_hz, 1.0))
    dt = 1.0 / sr
    a = dt / (rc + dt)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def fast_lowpass(x: np.ndarray, cutoff_hz: float, sr: int = SR) -> np.ndarray:
    """Vectorized approx via FFT brick-wall + soft rolloff (fast for long buffers)."""
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / sr)
    gain = 1.0 / np.sqrt(1.0 + (freqs / max(cutoff_hz, 1.0)) ** 4)
    return np.fft.irfft(spec * gain, n)


def fast_highpass(x: np.ndarray, cutoff_hz: float, sr: int = SR) -> np.ndarray:
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / sr)
    gain = 1.0 / np.sqrt(1.0 + (max(cutoff_hz, 1.0) / np.maximum(freqs, 1e-3)) ** 4)
    return np.fft.irfft(spec * gain, n)


def bandpass(x: np.ndarray, lo_hz: float, hi_hz: float, sr: int = SR) -> np.ndarray:
    return fast_highpass(fast_lowpass(x, hi_hz, sr), lo_hz, sr)


def white_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1, 1, n)


def synth_ir(dur: float, decay: float, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
    """A synthetic exponentially-decaying noise impulse response, used as a
    lightweight convolution 'room' reverb (no external IR files)."""
    n = int(dur * sr)
    noise = rng.normal(0, 1, n)
    t = np.arange(n) / sr
    env = np.exp(-t / decay)
    ir = noise * env
    ir = fast_lowpass(ir, 6000, sr)
    ir /= (np.max(np.abs(ir)) + 1e-9)
    return ir


def convolve_reverb(x: np.ndarray, ir: np.ndarray, wet: float = 0.25) -> np.ndarray:
    wet_sig = np.convolve(x, ir, mode="full")[: len(x) + 0]
    wet_sig = wet_sig[: len(x)] if len(wet_sig) >= len(x) else np.pad(wet_sig, (0, len(x) - len(wet_sig)))
    wet_sig /= (np.max(np.abs(wet_sig)) + 1e-9)
    dry = x / (np.max(np.abs(x)) + 1e-9)
    out = dry * (1 - wet) + wet_sig * wet * np.max(np.abs(dry))
    return out


def normalize_peak(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-9
    target = 10 ** (peak_db / 20)
    return x * (target / peak)


def rms_normalize(x: np.ndarray, target_dbfs: float = -16.0) -> np.ndarray:
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    target = 10 ** (target_dbfs / 20)
    out = x * (target / rms)
    # safety peak limiter
    peak = np.max(np.abs(out))
    if peak > 0.97:
        out = out * (0.97 / peak)
    return out


def to_stereo(x: np.ndarray, width: float = 0.0, rng: np.random.Generator | None = None) -> np.ndarray:
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], axis=-1)
    rng = rng or np.random.default_rng(0)
    delay = int(width * 0.002 * SR)
    l = x
    r = np.roll(x, delay)
    return np.stack([l, r], axis=-1)


def save(path: str, data: np.ndarray, sr: int = SR, loop: bool = False) -> None:
    """Write OGG Vorbis. NOTE: this libsndfile build segfaults on a single
    sf.write() call for buffers longer than ~45s (a known libsndfile/vorbis
    large-buffer bug) -- write in chunks through a streaming SoundFile
    instead, which sidesteps it entirely."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.asarray(data, dtype=np.float32)
    if data.ndim == 1:
        channels = 1
    else:
        channels = data.shape[1]
    chunk = 65536
    with sf.SoundFile(path, "w", samplerate=sr, channels=channels, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(data), chunk):
            f.write(data[i:i + chunk])


def modal_tone(n: int, sr: int, freq: float, partials, decay_tau: float, rng=None) -> np.ndarray:
    """Sum of decaying partials for metallic/bell-like modal synthesis.
    `partials` is a list of (ratio, amplitude, extra_decay_mult)."""
    t = np.arange(n) / sr
    out = np.zeros(n)
    for ratio, amp, dmul in partials:
        f = freq * ratio
        phase = 0.0 if rng is None else rng.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * f * t + phase) * np.exp(-t / (decay_tau * dmul))
    return out


# --------------------------------------------------------------------------
# SFX generators
# --------------------------------------------------------------------------

def sfx_push(rng):
    dur = 0.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    whoomph = np.sin(2 * np.pi * (55 + 20 * np.exp(-t * 6)) * t) * np.exp(-t * 5)
    sub = np.sin(2 * np.pi * 38 * t) * np.exp(-t * 4) * 0.6
    ring_freq = 900 + 400 * np.exp(-t * 3)
    ring = np.sin(2 * np.pi * ring_freq * t) * np.exp(-t * 2.2) * 0.35
    noise = fast_lowpass(white_noise(n, rng), 500) * np.exp(-t * 10) * 0.3
    x = whoomph * 0.7 + sub + ring + noise
    x = fast_lowpass(x, 5000)
    return rms_normalize(x, -14)


def sfx_pull(rng):
    dur = 0.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    rev_env = 1.0 - np.exp(-t * 8)  # rising instead of decaying: "reverse" feel
    rev_env *= np.exp(-((t - dur) ** 2) / (0.15 ** 2))
    ring = np.sin(2 * np.pi * (700 + 300 * t / dur) * t)
    metallic = modal_tone(n, SR, 260, [(1, 0.5, 1), (2.76, 0.3, 0.6), (5.4, 0.15, 0.4)], 0.6, rng)
    x = ring * rev_env * 0.5 + metallic * (rev_env * 0.6 + 0.1)
    x = fast_lowpass(x, 6000)
    return rms_normalize(x, -14)


def sfx_coin_throw(rng):
    dur = 0.6
    n = int(dur * SR)
    x = np.zeros(n)
    for i in range(6):
        start = rng.uniform(0, 0.35)
        s0 = int(start * SR)
        clen = int(0.15 * SR)
        if s0 + clen > n:
            clen = n - s0
        seg = modal_tone(clen, SR, rng.uniform(1800, 3200), [(1, 0.6, 1), (2.4, 0.3, 0.5), (3.8, 0.15, 0.3)], 0.08, rng)
        x[s0:s0 + clen] += seg
    x = fast_highpass(x, 400)
    return rms_normalize(x, -18)


def sfx_coin_hit(rng, variant=0):
    dur = 0.45
    n = int(dur * SR)
    base = rng.uniform(1500, 2600)
    ping = modal_tone(n, SR, base, [(1, 0.7, 1), (2.0, 0.35, 0.5), (3.3, 0.2, 0.3), (5.1, 0.1, 0.2)], 0.12, rng)
    crack = fast_highpass(white_noise(n, rng), 2000) * env_exp_decay(n, SR, 0.01) * 0.5
    x = ping + crack
    return rms_normalize(x, -16)


def sfx_coin_clink(rng, variant=0):
    dur = 0.35
    n = int(dur * SR)
    base = rng.uniform(2200, 3600)
    ping = modal_tone(n, SR, base, [(1, 0.6, 1), (1.8, 0.3, 0.6), (2.6, 0.15, 0.4)], 0.07, rng)
    return rms_normalize(ping, -20)


def sfx_flare(rng):
    dur = 1.1
    n = int(dur * SR)
    t = np.arange(n) / SR
    surge = fast_lowpass(white_noise(n, rng), 1800) * (1 - np.exp(-t * 5)) * np.exp(-t * 2)
    tone = np.sin(2 * np.pi * (300 + 500 * t) * t) * np.exp(-((t - 0.4) ** 2) / 0.08)
    x = surge * 0.8 + tone * 0.3
    return rms_normalize(x, -16)


def sfx_metal_burn_start(rng):
    dur = 0.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    thrum = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 3)
    shimmer = fast_lowpass(white_noise(n, rng), 900) * env_adsr(n, SR, 0.05, 0.2, 0.3, 0.2) * 0.2
    x = thrum * 0.6 + shimmer
    return rms_normalize(x, -20)


def sfx_metal_depleted(rng):
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    sputter = fast_bandpass_noise(n, rng, 200, 700) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t)) * np.exp(-t * 3)
    thud = np.sin(2 * np.pi * 90 * t) * np.exp(-t * 12)
    x = sputter * 0.6 + thud * 0.5
    return rms_normalize(x, -18)


def fast_bandpass_noise(n, rng, lo, hi):
    return bandpass(white_noise(n, rng), lo, hi)


def sfx_vial_drink(rng):
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    glugs = np.zeros(n)
    for i in range(4):
        c = 0.15 + i * 0.2
        glugs += np.exp(-((t - c) ** 2) / (0.02 ** 2)) * np.sin(2 * np.pi * 220 * t)
    glass = fast_bandpass_noise(n, rng, 3000, 8000) * env_exp_decay(n, SR, 0.03) * 0.2
    x = glugs * 0.5 + glass
    return rms_normalize(x, -18)


def sfx_dagger_swing(rng, variant=0):
    dur = 0.35
    n = int(dur * SR)
    t = np.arange(n) / SR
    center = 0.12
    noise = fast_bandpass_noise(n, rng, 1200, 6000)
    env = np.exp(-((t - center) ** 2) / (0.05 ** 2))
    x = noise * env
    return rms_normalize(x, -18)


def sfx_dagger_hit(rng):
    dur = 0.3
    n = int(dur * SR)
    thud = np.sin(2 * np.pi * 140 * np.arange(n) / SR) * env_exp_decay(n, SR, 0.05)
    crack = fast_bandpass_noise(n, rng, 1500, 5000) * env_exp_decay(n, SR, 0.02) * 0.5
    return rms_normalize(thud * 0.6 + crack, -16)


def sfx_hit_flesh(rng, variant=0):
    dur = 0.3
    n = int(dur * SR)
    thud = fast_lowpass(white_noise(n, rng), 300) * env_exp_decay(n, SR, 0.05)
    return rms_normalize(thud, -14)


def sfx_jump(rng):
    dur = 0.25
    n = int(dur * SR)
    t = np.arange(n) / SR
    swoosh = fast_bandpass_noise(n, rng, 400, 3000) * env_exp_decay(n, SR, 0.08)
    return rms_normalize(swoosh, -20)


def sfx_land_hard(rng):
    dur = 0.35
    n = int(dur * SR)
    thud = fast_lowpass(white_noise(n, rng), 200) * env_exp_decay(n, SR, 0.06)
    sub = np.sin(2 * np.pi * 60 * np.arange(n) / SR) * env_exp_decay(n, SR, 0.08) * 0.6
    return rms_normalize(thud + sub, -14)


def sfx_footstep(rng, variant=0):
    dur = 0.15
    n = int(dur * SR)
    knock = fast_bandpass_noise(n, rng, 200, 2500) * env_exp_decay(n, SR, 0.03)
    return rms_normalize(knock, -20)


def sfx_spear_swing(rng):
    return sfx_dagger_swing(rng)


def sfx_javelin_throw(rng):
    dur = 0.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    whoosh = fast_bandpass_noise(n, rng, 600, 4000) * np.exp(-((t - 0.1) ** 2) / (0.06 ** 2))
    return rms_normalize(whoosh, -18)


def sfx_guard_alert(rng):
    dur = 0.7
    n = int(dur * SR)
    t = np.arange(n) / SR
    freq = 700 + 200 * np.sin(2 * np.pi * 3 * t)
    tone = np.sin(2 * np.pi * freq * t) * env_adsr(n, SR, 0.05, 0.1, 0.7, 0.3)
    return rms_normalize(tone, -16)


def sfx_thug_roar(rng):
    dur = 1.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = 90 + 20 * np.sin(2 * np.pi * 5 * t)
    growl = np.sign(np.sin(2 * np.pi * base * t)) * 0.3  # square-ish for grit
    growl += np.sin(2 * np.pi * base * t)
    growl *= fast_lowpass(white_noise(n, rng), 1200) * 0.3 + 0.7
    env = env_adsr(n, SR, 0.1, 0.3, 0.6, 0.4)
    x = growl * env
    x = fast_lowpass(x, 2500)
    return rms_normalize(x, -14)


def sfx_inquisitor_scream(rng):
    dur = 1.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    freq = 1400 + 600 * np.sin(2 * np.pi * 7 * t) + 300 * np.sin(2 * np.pi * 1.3 * t)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    metallic = np.sin(phase) + 0.5 * np.sin(phase * 2.01) + 0.3 * np.sin(phase * 3.99)
    noise = fast_bandpass_noise(n, rng, 2000, 9000) * 0.4
    env = env_adsr(n, SR, 0.05, 0.2, 0.8, 0.4)
    x = (metallic * 0.5 + noise) * env
    return rms_normalize(x, -12)


def sfx_enemy_death(rng):
    dur = 0.5
    n = int(dur * SR)
    thud = fast_lowpass(white_noise(n, rng), 250) * env_exp_decay(n, SR, 0.1)
    groan = np.sin(2 * np.pi * 110 * np.arange(n) / SR) * env_exp_decay(n, SR, 0.15) * 0.3
    return rms_normalize(thud + groan, -16)


def sfx_ui_hover(rng):
    dur = 0.08
    n = int(dur * SR)
    tone = np.sin(2 * np.pi * 900 * np.arange(n) / SR) * env_fade_io(n, SR, 0.01)
    return rms_normalize(tone, -22)


def sfx_ui_click(rng):
    dur = 0.06
    n = int(dur * SR)
    tone = np.sin(2 * np.pi * 1300 * np.arange(n) / SR) * env_exp_decay(n, SR, 0.02)
    return rms_normalize(tone, -18)


def sfx_ui_back(rng):
    dur = 0.08
    n = int(dur * SR)
    tone = np.sin(2 * np.pi * 600 * np.arange(n) / SR) * env_exp_decay(n, SR, 0.02)
    return rms_normalize(tone, -18)


def sfx_objective_complete(rng):
    dur = 0.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    notes = [523.25, 659.25, 783.99]
    x = np.zeros(n)
    for i, f in enumerate(notes):
        seg_start = int(i * 0.12 * SR)
        seg = modal_tone(n - seg_start, SR, f, [(1, 0.6, 1), (2, 0.25, 0.6), (3, 0.1, 0.4)], 0.5, rng)
        x[seg_start:] += seg
    return rms_normalize(x, -16)


def sfx_mission_complete(rng):
    dur = 2.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    chord = [261.63, 329.63, 392.0, 523.25]
    x = np.zeros(n)
    for f in chord:
        x += np.sin(2 * np.pi * f * t) * 0.2
    env = env_adsr(n, SR, 0.3, 0.5, 0.6, 1.2)
    x *= env
    ir = synth_ir(1.5, 1.0, rng)
    x = convolve_reverb(x, ir, wet=0.4)
    return rms_normalize(x, -14)


SFX_SIMPLE = {
    "push": sfx_push,
    "pull": sfx_pull,
    "coin_throw": sfx_coin_throw,
    "flare": sfx_flare,
    "metal_burn_start": sfx_metal_burn_start,
    "metal_depleted": sfx_metal_depleted,
    "vial_drink": sfx_vial_drink,
    "dagger_hit": sfx_dagger_hit,
    "jump": sfx_jump,
    "land_hard": sfx_land_hard,
    "spear_swing": sfx_spear_swing,
    "javelin_throw": sfx_javelin_throw,
    "guard_alert": sfx_guard_alert,
    "thug_roar": sfx_thug_roar,
    "inquisitor_scream": sfx_inquisitor_scream,
    "enemy_death": sfx_enemy_death,
    "ui_hover": sfx_ui_hover,
    "ui_click": sfx_ui_click,
    "ui_back": sfx_ui_back,
    "objective_complete": sfx_objective_complete,
    "mission_complete": sfx_mission_complete,
}

SFX_VARIANTS = {
    "coin_hit": (sfx_coin_hit, 3),
    "coin_clink": (sfx_coin_clink, 3),
    "dagger_swing": (sfx_dagger_swing, 2),
    "hit_flesh": (sfx_hit_flesh, 2),
    "footstep_stone": (sfx_footstep, 4),
}


# --------------------------------------------------------------------------
# Ambience loops
# --------------------------------------------------------------------------

def make_seamless_loop(n: int, layers) -> np.ndarray:
    """Sum of sine components with integer-cycle frequencies over the loop
    length (perfectly periodic) plus looped filtered noise (using np.roll
    crossfade at the seam) for a seamless ambience bed."""
    return sum(layers)


def periodic_component(n: int, sr: int, base_freq_hz: float, amp: float, phase: float = 0.0) -> np.ndarray:
    dur = n / sr
    cycles = max(1, round(base_freq_hz * dur))
    freq = cycles / dur
    t = np.arange(n) / sr
    return amp * np.sin(2 * np.pi * freq * t + phase)


def seamless_noise_bed(n: int, rng, lo, hi) -> np.ndarray:
    """Filtered noise looped by crossfading the tail into the head so the
    loop point is inaudible."""
    pad = int(0.5 * SR)
    raw = white_noise(n + pad, rng)
    filt = bandpass(raw, lo, hi)
    head = filt[:n]
    tail = filt[n:n + pad]
    fade = np.linspace(0, 1, pad)
    head[:pad] = head[:pad] * fade + tail * (1 - fade)
    return head


def ambience_night_city(rng):
    dur = 60.0
    n = int(dur * SR)
    wind = seamless_noise_bed(n, rng, 80, 500) * 0.5
    wind += seamless_noise_bed(n, rng, 40, 200) * 0.3
    hiss = seamless_noise_bed(n, rng, 3000, 9000) * 0.15  # ash hiss
    low = periodic_component(n, SR, 0.05, 0.05)
    x = wind + hiss + low
    # occasional distant creak (periodic so it loops)
    creak_env = np.clip(np.sin(2 * np.pi * np.arange(n) / n * 5) - 0.9, 0, None) * 10
    creak = np.sin(2 * np.pi * 220 * np.arange(n) / SR) * creak_env * 0.05
    x += creak
    stereo = to_stereo(x, width=1.0)
    return rms_normalize(stereo, -22)


def ambience_mist(rng):
    dur = 60.0
    n = int(dur * SR)
    airy = seamless_noise_bed(n, rng, 1500, 6000) * 0.4
    low = seamless_noise_bed(n, rng, 100, 400) * 0.3
    shimmer = periodic_component(n, SR, 0.03, 0.04) + periodic_component(n, SR, 0.017, 0.03, 1.3)
    x = airy + low + shimmer * airy
    stereo = to_stereo(x, width=1.5)
    return rms_normalize(stereo, -24)


def ambience_canal_water(rng):
    dur = 60.0
    n = int(dur * SR)
    water = seamless_noise_bed(n, rng, 200, 2500) * 0.5
    bubbles = seamless_noise_bed(n, rng, 800, 4000) * 0.2
    lap = periodic_component(n, SR, 0.12, 0.08) ** 2 * water
    x = water + bubbles * 0.3 + lap * 0.3
    stereo = to_stereo(x, width=0.8)
    return rms_normalize(stereo, -22)


AMBIENCE = {
    "ambience_night_city": ambience_night_city,
    "ambience_mist": ambience_mist,
    "ambience_canal_water": ambience_canal_water,
}


# --------------------------------------------------------------------------
# Music: 3 layered, tempo/key-synced loops for dynamic intensity
# --------------------------------------------------------------------------

MUSIC_DUR = 64.0
MUSIC_BPM = 66.0
MUSIC_KEY_ROOT = 220.0 * (2 ** (-9 / 12))  # ~ D3-ish minor tonal center


def note_freq(semitones_from_root: float) -> float:
    return MUSIC_KEY_ROOT * (2 ** (semitones_from_root / 12))


def pad_layer(n, sr, rng, chord_semis, tau=6.0):
    t = np.arange(n) / sr
    x = np.zeros(n)
    for semis in chord_semis:
        f = note_freq(semis)
        # slow filtered-noise-modulated sine for a string-pad texture
        vib = 1.0 + 0.002 * np.sin(2 * np.pi * 0.13 * t)
        x += np.sin(2 * np.pi * f * vib * t) * 0.18
        x += np.sin(2 * np.pi * f * 2.0 * vib * t) * 0.05
    x = fast_lowpass(x, 1200, sr)
    return x


def pluck_layer(n, sr, rng, beat_dur, notes_semis):
    x = np.zeros(n)
    beats = int(n / sr / beat_dur)
    for i in range(beats):
        if rng.random() < 0.35:
            continue  # sparse
        s0 = int(i * beat_dur * sr)
        note_dur = beat_dur * rng.uniform(0.6, 0.95)
        ln = int(note_dur * sr)
        if s0 + ln > n:
            ln = n - s0
        if ln <= 0:
            continue
        semis = notes_semis[i % len(notes_semis)]
        f = note_freq(semis + 12)
        seg = modal_tone(ln, sr, f, [(1, 0.5, 1), (2.0, 0.2, 0.5), (3.0, 0.1, 0.3)], note_dur * 0.6, rng)
        seg *= env_adsr(ln, sr, 0.005, note_dur * 0.2, 0.3, note_dur * 0.4)
        x[s0:s0 + ln] += seg
    return x


def ostinato_layer(n, sr, rng, beat_dur, notes_semis):
    x = np.zeros(n)
    steps = int(n / sr / (beat_dur / 2))
    for i in range(steps):
        s0 = int(i * beat_dur / 2 * sr)
        ln = int(beat_dur / 2 * 0.9 * sr)
        if s0 + ln > n:
            ln = n - s0
        if ln <= 0:
            continue
        semis = notes_semis[i % len(notes_semis)]
        f = note_freq(semis)
        seg = np.sin(2 * np.pi * f * np.arange(ln) / sr)
        seg *= env_exp_decay(ln, sr, beat_dur * 0.2)
        x[s0:s0 + ln] += seg * 0.15
    return fast_lowpass(x, 2000, sr)


def perc_layer(n, sr, rng, beat_dur):
    x = np.zeros(n)
    beats = int(n / sr / beat_dur)
    for i in range(beats):
        s0 = int(i * beat_dur * sr)
        ln = int(0.12 * sr)
        if s0 + ln > n:
            ln = n - s0
        if ln <= 0:
            continue
        kind_kick = (i % 4 == 0)
        if kind_kick:
            hit = np.sin(2 * np.pi * 60 * np.arange(ln) / sr) * env_exp_decay(ln, sr, 0.08)
        else:
            hit = fast_bandpass_noise(ln, rng, 800, 4000) * env_exp_decay(ln, sr, 0.04) * 0.6
        x[s0:s0 + ln] += hit
    return x


def make_loop_length():
    beat_dur = 60.0 / MUSIC_BPM
    beats_total = round(MUSIC_DUR / beat_dur)
    dur = beats_total * beat_dur  # exact integer number of beats -> loops cleanly
    return int(dur * SR), beat_dur


CHORD_PROGRESSION = [
    [0, 3, 7],      # i
    [-2, 3, 7],     # bVII-ish
    [-5, 0, 3],     # iv
    [-3, 0, 3, 7],  # V-ish (raised for tension)
]


def music_calm(rng):
    n, beat_dur = make_loop_length()
    x = np.zeros(n)
    chord_dur = n / len(CHORD_PROGRESSION)
    for i, chord in enumerate(CHORD_PROGRESSION):
        s0 = int(i * chord_dur)
        seg_n = int(chord_dur) if i < len(CHORD_PROGRESSION) - 1 else n - s0
        x[s0:s0 + seg_n] += pad_layer(seg_n, SR, rng, chord)
    notes = [0, 3, 7, 10, 7, 3]
    x += pluck_layer(n, SR, rng, beat_dur * 2, notes) * 0.6
    ir = synth_ir(2.0, 1.6, rng)
    x = convolve_reverb(x, ir, wet=0.3)
    stereo = to_stereo(x, width=1.2)
    return rms_normalize(stereo, -18), n


def music_tension(rng):
    n, beat_dur = make_loop_length()
    x = np.zeros(n)
    chord_dur = n / len(CHORD_PROGRESSION)
    for i, chord in enumerate(CHORD_PROGRESSION):
        s0 = int(i * chord_dur)
        seg_n = int(chord_dur) if i < len(CHORD_PROGRESSION) - 1 else n - s0
        x[s0:s0 + seg_n] += pad_layer(seg_n, SR, rng, chord) * 1.1
    notes = [0, 3, 7, 10, 7, 3]
    x += pluck_layer(n, SR, rng, beat_dur, notes) * 0.7
    x += ostinato_layer(n, SR, rng, beat_dur, [0, 3, 0, -2])
    ir = synth_ir(1.2, 1.0, rng)
    x = convolve_reverb(x, ir, wet=0.25)
    stereo = to_stereo(x, width=1.0)
    return rms_normalize(stereo, -16), n


def music_combat(rng):
    n, beat_dur = make_loop_length()
    x = np.zeros(n)
    chord_dur = n / len(CHORD_PROGRESSION)
    for i, chord in enumerate(CHORD_PROGRESSION):
        s0 = int(i * chord_dur)
        seg_n = int(chord_dur) if i < len(CHORD_PROGRESSION) - 1 else n - s0
        x[s0:s0 + seg_n] += pad_layer(seg_n, SR, rng, chord) * 1.2
    notes = [0, 3, 7, 10, 12, 10, 7, 3]
    x += pluck_layer(n, SR, rng, beat_dur / 2, notes) * 0.8
    x += ostinato_layer(n, SR, rng, beat_dur, [0, 3, 0, -2]) * 1.2
    x += perc_layer(n, SR, rng, beat_dur / 2) * 0.9
    ir = synth_ir(0.8, 0.6, rng)
    x = convolve_reverb(x, ir, wet=0.15)
    stereo = to_stereo(x, width=0.8)
    return rms_normalize(stereo, -14), n


MUSIC = {
    "music_calm": music_calm,
    "music_tension": music_tension,
    "music_combat": music_combat,
}


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=str, default="assets/audio")
    args = ap.parse_args()

    sfx_dir = os.path.join(args.out, "sfx")
    amb_dir = os.path.join(args.out, "ambience")
    mus_dir = os.path.join(args.out, "music")
    for d in (sfx_dir, amb_dir, mus_dir):
        os.makedirs(d, exist_ok=True)

    print("Generating simple SFX (mono, for 3D positional playback) ...")
    for name, fn in SFX_SIMPLE.items():
        rng = rng_for(name)
        x = fn(rng)
        save(os.path.join(sfx_dir, f"{name}.ogg"), x)
        print(f"  {name}.ogg")

    print("Generating variant SFX (mono) ...")
    for name, (fn, count) in SFX_VARIANTS.items():
        for v in range(count):
            rng = rng_for(f"{name}_{v}")
            x = fn(rng, variant=v)
            save(os.path.join(sfx_dir, f"{name}_{v + 1}.ogg"), x)
        print(f"  {name}_1..{count}.ogg")

    print("Generating ambience loops (60s) ...")
    for name, fn in AMBIENCE.items():
        rng = rng_for(name)
        x = fn(rng)
        save(os.path.join(amb_dir, f"{name}.ogg"), x)
        print(f"  {name}.ogg")

    print("Generating music layers (64s, synced tempo/key) ...")
    for name, fn in MUSIC.items():
        rng = rng_for(name)
        x, n = fn(rng)
        save(os.path.join(mus_dir, f"{name}.ogg"), x)
        print(f"  {name}.ogg ({n / SR:.2f}s)")

    print("Done.")


if __name__ == "__main__":
    main()

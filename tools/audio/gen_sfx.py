#!/usr/bin/env python3
"""Sound effects of stage D: monster voices, materials, traps, steps, UI,
the town - and variants of the sounds heard most often.

Writes assets/audio/sfx/<id>.wav (+ <id>_2.wav, <id>_3.wav: variants that
AudioManager picks at random) and the list of new ids into
scripts/core/asset_paths.gd between the GENERATED SFX markers.

  voices   14 families x aggro / attack / hurt / death, 3 takes each
           (bone, slime, beast, hiss, winged, spirit, human, brute, stone,
           frost, water, plant, void, mimic); EnemyData.voice picks them
  hits     a blow on bone, stone, slime, wood, a spirit (EnemyData.hit_sound)
  steps    grass, sand, water, metal (BiomeData.step_sound)
  traps    arrow, spikes, acid sizzle (trap_flame), a pressure plate (Trap)
  ui       tab, error, buy, sell, build, page
  town     anvil, bell
  variants 2 more takes of the frequent old sounds (VARIANTS): the same
           recipe pitched, filtered and re-timed a little
Mono 16-bit 44.1 kHz, cut to their sound. Deterministic (crc32 seeds).

  python3 tools/audio/gen_sfx.py
"""
import importlib.util
import os
import re
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
_spec = importlib.util.spec_from_file_location("gen_audio", os.path.join(TOOLS, "gen_audio.py"))
ga = importlib.util.module_from_spec(_spec)
sys.path.insert(0, TOOLS)
_spec.loader.exec_module(ga)
SR = ga.SR
osc, noise, adsr, decay, bandpass, fft_filter = ga.osc, ga.noise, ga.adsr, ga.decay, ga.bandpass, ga.fft_filter
mix, at, sat, whoosh, thud, metal = ga.mix, ga.at, ga.sat, ga.whoosh, ga.thud, ga.metal
SFX_DIR = ga.SFX
ASSET_PATHS = os.path.join(ROOT, "scripts", "core", "asset_paths.gd")
written = []


def seed_of(*parts):
    return zlib.crc32("/".join(str(p) for p in parts).encode()) & 0xFFFF


def save(name, x, peak=0.8, room=0.0):
    x = np.asarray(x, dtype=np.float64)
    if room > 0:
        x = ga.reverb(x, 0.45, room, 6000, seed=seed_of(name))
    # trim the silent tail, short fade-out
    env = np.abs(x)
    thr = np.max(env) * 0.004
    last = np.nonzero(env > thr)[0]
    if len(last):
        x = x[: min(len(x), last[-1] + ga.n_of(0.02))]
    fade = min(len(x) // 4, ga.n_of(0.012))
    x[-fade:] *= np.linspace(1, 0, fade)
    ga.write_wav(os.path.join(SFX_DIR, name + ".wav"), ga.normalize(x, peak))


# ------------------------------------------------------------ voice parts
def vox(f0, f1, sec, formants, breath=0.25, rough=0.0, vib=0.0, seed=0, kind="saw"):
    """A voice: a glottal saw gliding f0 -> f1 (+ vibrato, + roughness)
    through formant band passes, with breath noise."""
    n = ga.n_of(sec)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n) * (1 + vib * np.sin(2 * np.pi * 6.0 * t))
    src = osc(kind, f, sec) + noise(sec, seed) * breath
    if rough:
        am = 1 + rough * fft_filter(noise(sec, seed + 1), hi=70) * 4
        src = src * am
    out = np.zeros(n)
    for fc, g, q in formants:
        out += bandpass(src, fc, q) * g
    return out * adsr(sec, min(0.03, sec * 0.2), sec * 0.4, 0.6, sec * 0.35)


def clicks(sec, count, f=2400, seed=0, spread=1.0):
    """Bony / chitin clicks scattered over sec."""
    rng = np.random.default_rng(seed)
    parts = []
    for _ in range(count):
        tclick = rng.uniform(0, sec * spread)
        c = metal(f * rng.uniform(0.8, 1.3), 0.06, 60, (1.0, 2.3, 3.9), seed=int(rng.integers(1 << 16)))
        parts.append(at(c * rng.uniform(0.5, 1.0), tclick))
    return mix(*parts)


def squelch(sec, seed=0, low=180):
    body = fft_filter(noise(sec, seed), hi=900) * adsr(sec, 0.01, sec * 0.3, 0.5, sec * 0.4)
    rng = np.random.default_rng(seed)
    bub = [at(osc("sine", np.linspace(f, f * 0.55, ga.n_of(0.07)), 0.07) * decay(0.07, 40) * 0.6, rng.uniform(0, sec * 0.8))
           for f in rng.uniform(low, low * 3, 4)]
    return mix(body, *bub)


def crumble(sec, seed=0):
    rng = np.random.default_rng(seed)
    parts = [fft_filter(noise(sec, seed), lo=200, hi=3000) * decay(sec, 4.0) * 0.6]
    for _ in range(9):
        parts.append(at(thud(0.12, rng.uniform(90, 200), 50, 30) * rng.uniform(0.3, 0.8), rng.uniform(0, sec * 0.7)))
    return mix(*parts)


def hiss(sec, seed=0, hi_pass=3000):
    return fft_filter(noise(sec, seed), lo=hi_pass) * adsr(sec, sec * 0.15, sec * 0.3, 0.7, sec * 0.4)


def shimmer(sec, base=900, seed=0):
    rng = np.random.default_rng(seed)
    return mix(*[at(osc("sine", f, sec * 0.6) * decay(sec * 0.6, 6) * 0.3, rng.uniform(0, sec * 0.4))
                 for f in base * rng.uniform(1, 3, 6)])


def rumble(sec, seed=0):
    return fft_filter(noise(sec, seed), hi=220) * adsr(sec, sec * 0.2, sec * 0.3, 0.8, sec * 0.4) * 1.5


# ------------------------------------------------------- voice families
# Each recipe(kind, take) -> signal. take 0..2: three takes (different
# seeds and a little pitch) of the same idea.
def fam_bone(k, v):
    s = seed_of("bone", k, v)
    p = 1 + 0.06 * (v - 1)
    if k == "aggro":
        return mix(clicks(0.45, 9, 2600 * p, s), vox(140 * p, 110 * p, 0.4, [(500, 1, 2), (1100, 0.6, 3)], 0.6, 0.6, seed=s) * 0.4)
    if k == "attack":
        return mix(whoosh(0.22, 2500, 700, 1.4, s) * 0.8, at(clicks(0.08, 3, 3000 * p, s), 0.12))
    if k == "hurt":
        return clicks(0.18, 6, 2200 * p, s, 0.6)
    return mix(clicks(0.7, 16, 2000 * p, s), at(thud(0.3, 120, 50) * 0.7, 0.45))


def fam_slime(k, v):
    s = seed_of("slime", k, v)
    p = 1 + 0.08 * (v - 1)
    if k == "aggro":
        return squelch(0.4, s, 160 * p)
    if k == "attack":
        return mix(squelch(0.25, s, 220 * p), whoosh(0.2, 900, 400, 1.0, s) * 0.4)
    if k == "hurt":
        return squelch(0.2, s, 260 * p)
    return mix(squelch(0.6, s, 140 * p), at(squelch(0.3, s + 9, 100 * p) * 0.7, 0.3))


def fam_beast(k, v):
    s = seed_of("beast", k, v)
    p = 1 + 0.07 * (v - 1)
    F = [(400, 1, 1.5), (900, 0.7, 2), (2200, 0.25, 3)]
    if k == "aggro":
        return vox(95 * p, 120 * p, 0.7, F, 0.35, 0.9, seed=s)
    if k == "attack":
        return mix(vox(160 * p, 110 * p, 0.25, F, 0.4, 0.7, seed=s), whoosh(0.2, 1800, 600, 1.2, s) * 0.5)
    if k == "hurt":
        return vox(420 * p, 260 * p, 0.22, [(800, 1, 2), (1600, 0.6, 3)], 0.3, 0.2, seed=s)
    return vox(300 * p, 110 * p, 0.8, [(700, 1, 2), (1400, 0.5, 3)], 0.35, 0.4, 0.02, seed=s)


def fam_hiss(k, v):
    s = seed_of("hiss", k, v)
    p = 1 + 0.06 * (v - 1)
    if k == "aggro":
        return mix(hiss(0.55, s, 3200 * p), clicks(0.4, 5, 3500, s) * 0.5)
    if k == "attack":
        return mix(hiss(0.2, s, 2500 * p), at(clicks(0.06, 2, 3800, s), 0.1))
    if k == "hurt":
        return vox(1300 * p, 900 * p, 0.15, [(2500, 1, 3), (4200, 0.6, 4)], 0.6, 0.3, seed=s)
    return mix(hiss(0.7, s, 2200 * p) * np.linspace(1, 0.2, ga.n_of(0.7)), clicks(0.6, 8, 3000, s) * 0.6)


def fam_winged(k, v):
    s = seed_of("winged", k, v)
    p = 1 + 0.08 * (v - 1)
    F = [(2200, 1, 3), (3600, 0.6, 4)]
    if k == "aggro":
        return vox(1500 * p, 1900 * p, 0.35, F, 0.3, 0.3, 0.04, seed=s)
    if k == "attack":
        flaps = mix(*[at(whoosh(0.09, 1200, 400, 1.0, s + i) * 0.7, i * 0.08) for i in range(3)])
        return mix(flaps, vox(1800 * p, 1500 * p, 0.15, F, 0.3, 0.2, seed=s) * 0.6)
    if k == "hurt":
        return vox(2200 * p, 1600 * p, 0.12, F, 0.3, 0.1, seed=s)
    return vox(1900 * p, 700 * p, 0.55, F, 0.4, 0.3, 0.03, seed=s)


def fam_spirit(k, v):
    s = seed_of("spirit", k, v)
    p = 1 + 0.05 * (v - 1)
    F = [(600, 1, 2), (1000, 0.7, 3)]
    if k == "aggro":
        return mix(vox(330 * p, 280 * p, 1.0, F, 0.5, 0.0, 0.015, seed=s, kind="tri"), shimmer(0.8, 900, s) * 0.5)
    if k == "attack":
        return mix(whoosh(0.4, 400, 2200, 0.8, s), vox(400 * p, 520 * p, 0.3, F, 0.6, seed=s, kind="tri") * 0.5)
    if k == "hurt":
        return vox(520 * p, 380 * p, 0.3, F, 0.5, 0.0, 0.03, seed=s, kind="tri")
    return mix(vox(440 * p, 160 * p, 1.1, F, 0.5, 0.0, 0.02, seed=s, kind="tri"), shimmer(1.0, 1200, s))


def fam_human(k, v):
    s = seed_of("human", k, v)
    p = 1 + 0.08 * (v - 1)
    if k == "aggro":  # "hey!"
        return vox(170 * p, 210 * p, 0.32, [(700, 1, 2), (1700, 0.7, 3), (2600, 0.3, 4)], 0.25, 0.1, seed=s)
    if k == "attack":  # "hah"
        return mix(vox(190 * p, 150 * p, 0.18, [(800, 1, 2), (1300, 0.7, 3)], 0.5, 0.1, seed=s), whoosh(0.2, 2200, 700, 1.3, s) * 0.5)
    if k == "hurt":  # "ugh"
        return vox(220 * p, 160 * p, 0.2, [(500, 1, 2), (1000, 0.6, 3)], 0.4, 0.2, seed=s)
    return vox(200 * p, 90 * p, 0.7, [(500, 1, 2), (900, 0.5, 3)], 0.5, 0.3, seed=s)


def fam_brute(k, v):
    s = seed_of("brute", k, v)
    p = 1 + 0.06 * (v - 1)
    F = [(350, 1, 1.5), (700, 0.7, 2)]
    if k == "aggro":
        return mix(vox(80 * p, 100 * p, 0.9, F, 0.35, 0.8, seed=s), rumble(0.8, s) * 0.3)
    if k == "attack":
        return mix(vox(110 * p, 80 * p, 0.3, F, 0.4, 0.6, seed=s), whoosh(0.35, 900, 250, 1.0, s) * 0.7)
    if k == "hurt":
        return vox(140 * p, 100 * p, 0.25, F, 0.3, 0.5, seed=s)
    return mix(vox(120 * p, 55 * p, 1.0, F, 0.4, 0.6, seed=s), at(thud(0.5, 90, 35, 8) * 0.9, 0.7))


def fam_stone(k, v):
    s = seed_of("stone", k, v)
    if k == "aggro":
        return mix(rumble(0.8, s), fft_filter(noise(0.8, s + 1), lo=400, hi=1500) * adsr(0.8, 0.2, 0.3, 0.5, 0.3) * 0.5)
    if k == "attack":
        return mix(fft_filter(noise(0.3, s), lo=300, hi=1500) * adsr(0.3, 0.05, 0.1, 0.6, 0.1), at(thud(0.3, 110, 40) * 0.8, 0.2))
    if k == "hurt":
        return mix(metal(900 + 100 * v, 0.15, 30, (1.0, 1.7, 2.9), seed=s) * 0.6, crumble(0.15, s) * 0.5)
    return crumble(0.9, s)


def fam_frost(k, v):
    s = seed_of("frost", k, v)
    if k == "aggro":
        return mix(shimmer(0.6, 1600, s), hiss(0.5, s, 4000) * 0.4)
    if k == "attack":
        return mix(whoosh(0.25, 3000, 900, 1.5, s), shimmer(0.25, 2200, s) * 0.6)
    if k == "hurt":
        return mix(*[at(metal(f, 0.12, 30, (1.0, 2.7), seed=s + i) * 0.4, i * 0.03) for i, f in enumerate((2400, 3100, 2700))])
    return mix(shimmer(0.9, 1400, s), crumble(0.5, s) * 0.4)


def fam_water(k, v):
    s = seed_of("water", k, v)
    p = 1 + 0.06 * (v - 1)
    gurgle = lambda sec, sd: mix(*[at(osc("sine", np.linspace(f, f * 1.7, ga.n_of(0.05)), 0.05) * decay(0.05, 60) * 0.5, t)
                                    for f, t in zip(np.random.default_rng(sd).uniform(300, 900, 7),
                                                    np.random.default_rng(sd + 1).uniform(0, sec * 0.8, 7))])
    if k == "aggro":
        return mix(vox(110 * p, 90 * p, 0.6, [(400, 1, 2), (900, 0.5, 3)], 0.6, 0.6, seed=s) * 0.6, gurgle(0.6, s))
    if k == "attack":
        return mix(whoosh(0.3, 1500, 500, 1.0, s) * 0.7, gurgle(0.25, s))
    if k == "hurt":
        return gurgle(0.25, s) * 1.2
    return mix(gurgle(0.9, s), vox(140 * p, 60 * p, 0.8, [(350, 1, 2)], 0.6, 0.5, seed=s) * 0.5)


def fam_plant(k, v):
    s = seed_of("plant", k, v)
    creak = lambda sec, f: vox(f, f * 0.8, sec, [(600, 1, 4), (1500, 0.5, 5)], 0.1, 1.5, seed=s, kind="square") * 0.6
    rustle = lambda sec: fft_filter(noise(sec, s), lo=1500, hi=7000) * adsr(sec, 0.02, sec * 0.3, 0.5, sec * 0.4)
    if k == "aggro":
        return mix(creak(0.6, 70 + 8 * v), rustle(0.6) * 0.6)
    if k == "attack":
        return mix(whoosh(0.18, 2500, 600, 1.6, s), rustle(0.2) * 0.5)
    if k == "hurt":
        return mix(rustle(0.2), metal(500, 0.1, 40, (1.0, 1.9), seed=s) * 0.3)
    return mix(creak(0.9, 60 + 6 * v), rustle(0.9) * 0.7)


def fam_void(k, v):
    s = seed_of("void", k, v)
    if k == "aggro":
        n = ga.n_of(0.8)
        swell = osc("saw", np.linspace(55, 80, n), 0.8) * np.linspace(0, 1, n) ** 2
        return mix(fft_filter(swell, hi=600), shimmer(0.8, 300, s) * 0.4)
    if k == "attack":
        return mix(osc("square", np.linspace(900, 120, ga.n_of(0.25)), 0.25) * decay(0.25, 10) * 0.4, whoosh(0.25, 300, 2000, 1.0, s) * 0.6)
    if k == "hurt":
        g = osc("square", 300 + 60 * v, 0.15) * (np.random.default_rng(s).uniform(0, 1, ga.n_of(0.15)) > 0.5)
        return fft_filter(g, hi=3000) * decay(0.15, 12)
    n = ga.n_of(0.9)
    return mix(fft_filter(osc("saw", np.linspace(200, 30, n), 0.9), hi=800) * decay(0.9, 3), shimmer(0.9, 200, s) * 0.5)


def fam_mimic(k, v):
    s = seed_of("mimic", k, v)
    creak = vox(80 + 10 * v, 60, 0.4, [(500, 1, 4), (1200, 0.6, 5)], 0.05, 2.0, seed=s, kind="square")
    chomp = mix(thud(0.12, 220, 90, 30), metal(1800, 0.06, 60, (1.0, 2.2), seed=s) * 0.5)
    if k == "aggro":
        return mix(creak, at(chomp, 0.35))
    if k == "attack":
        return mix(chomp, at(chomp * 0.8, 0.12))
    if k == "hurt":
        return mix(creak * 0.5, metal(700, 0.1, 30, (1.0, 2.0), seed=s) * 0.4)
    return mix(creak, at(crumble(0.6, s) * 0.7, 0.3))


FAMILIES = {"bone": fam_bone, "slime": fam_slime, "beast": fam_beast, "hiss": fam_hiss, "winged": fam_winged,
            "spirit": fam_spirit, "human": fam_human, "brute": fam_brute, "stone": fam_stone, "frost": fam_frost,
            "water": fam_water, "plant": fam_plant, "void": fam_void, "mimic": fam_mimic}
KINDS = ("aggro", "attack", "hurt", "death")


# ---------------------------------------------------------------- others
def hits(v):
    s = seed_of("hit", v)
    return {
        "hit_bone": mix(clicks(0.1, 4, 2400 + 200 * v, s, 0.4), thud(0.1, 300, 120, 30) * 0.5),
        "hit_stone": mix(metal(700 + 80 * v, 0.2, 25, (1.0, 1.6, 2.5), seed=s) * 0.5, crumble(0.2, s) * 0.6, thud(0.12, 200, 80, 25) * 0.6),
        "hit_slime": squelch(0.18, s, 300 + 40 * v),
        "hit_wood": mix(thud(0.15, 260 + 30 * v, 120, 25), bandpass(noise(0.1, s), 1800, 1.2) * decay(0.1, 30) * 0.6),
        "hit_spirit": mix(shimmer(0.25, 1500 + 200 * v, s), whoosh(0.15, 3000, 1200, 1.2, s) * 0.5),
    }


def steps(v):
    s = seed_of("step", v)
    return {
        "step_grass": fft_filter(noise(0.09, s), lo=1500, hi=6000) * adsr(0.09, 0.005, 0.03, 0.4, 0.04) * 0.8,
        "step_sand": fft_filter(noise(0.11, s), lo=800, hi=4000) * adsr(0.11, 0.01, 0.04, 0.4, 0.05),
        "step_water": mix(fft_filter(noise(0.14, s), lo=500, hi=3000) * decay(0.14, 18),
                          osc("sine", np.linspace(500 + 40 * v, 260, ga.n_of(0.06)), 0.06) * decay(0.06, 50) * 0.4),
        "step_metal": mix(metal(1400 + 90 * v, 0.12, 35, (1.0, 2.4, 3.8), seed=s) * 0.4, thud(0.07, 180, 90, 40) * 0.6),
    }


def traps(v):
    s = seed_of("trap", v)
    return {
        "trap_arrow": mix(metal(1100, 0.05, 80, (1.0, 2.0), seed=s) * 0.5, at(whoosh(0.3, 3500, 1500, 2.0, s), 0.03)),
        "trap_spike": mix(metal(1600 + 100 * v, 0.2, 18, (1.0, 2.6, 4.1), seed=s) * 0.6, thud(0.1, 300, 150, 30) * 0.6),
        "trap_flame": fft_filter(noise(0.6, s), hi=2500) * adsr(0.6, 0.05, 0.3, 0.7, 0.25) * (1 + 0.3 * fft_filter(noise(0.6, s + 1), hi=20)),
        "trap_click": mix(metal(2600, 0.04, 90, (1.0, 1.8), seed=s) * 0.7, thud(0.05, 400, 200, 60) * 0.5),
    }


def ui(v):
    s = seed_of("ui", v)
    b = lambda f, sec, k=2.5: ga.bell(f, sec, k, 2.0)
    return {
        "ui_tab": mix(bandpass(noise(0.05, s), 2500, 2.0) * decay(0.05, 60), ga.pluck(880, 0.08, 1.0) * 0.4),
        "ui_error": mix(osc("square", 220, 0.09) * decay(0.09, 25) * 0.3, at(osc("square", 165, 0.12) * decay(0.12, 20) * 0.3, 0.09)),
        "ui_buy": mix(b(1320, 0.3), at(b(1760, 0.35), 0.06) * 0.8, metal(3200, 0.08, 40, seed=s) * 0.2),
        "ui_sell": mix(metal(2600, 0.15, 25, seed=s) * 0.4, at(metal(2900, 0.15, 25, seed=s + 1) * 0.35, 0.05), at(b(990, 0.3) * 0.5, 0.08)),
        "ui_build": mix(thud(0.2, 160, 70, 20), at(thud(0.2, 170, 70, 20) * 0.8, 0.18), at(b(660, 0.5) * 0.5, 0.36)),
        "ui_page": whoosh(0.16, 2500, 6000, 1.0, s) * 0.8,
    }


def town(v):
    s = seed_of("town", v)
    return {
        "town_anvil": mix(metal(1900 + 60 * v, 0.6, 7, (1.0, 2.76, 5.4, 8.9), seed=s), thud(0.08, 300, 150, 40) * 0.4),
        "town_bell": ga.reverb(ga.bell(392 - 20 * v, 2.2, 1.2, 3.0), 1.2, 0.3, 4000, seed=s),
    }


# Frequent old sounds that get two more takes: (id, how to vary).
VARIANTS = ["step_stone", "step_wood", "step_soft", "jump", "land", "dash", "attack_sword", "attack_axe",
            "attack_spear", "attack_dagger", "attack_bow", "attack_staff", "attack_mace", "hit_flesh", "hit_crit",
            "player_hurt", "enemy_hurt", "enemy_death", "enemy_shoot", "chest_open", "pickup_common", "pickup_rare",
            "coin", "potion_drink", "dig", "explosion", "cast_fire", "cast_frost", "cast_bolt", "cast_holy",
            "cast_shadow", "cast_void", "cast_heal", "cast_swing_quick", "cast_swing_heavy", "cast_swing_wide",
            "ui_click", "ui_hover", "ui_equip", "splash", "swim", "skill_cast", "item_use", "cast_throw"]


def vary(x, v):
    """Take v (2, 3) of a recorded sound: pitched +-, a slightly different
    brightness and length - the same sound, not a copy."""
    x = np.asarray(x, dtype=np.float64)
    rate = [1.0, 1.0, 1.06, 0.94][v]
    idx = np.arange(0, len(x) - 1, rate)
    y = np.interp(idx, np.arange(len(x)), x)
    if v == 2:
        y = fft_filter(y, hi=9000)
    else:
        y = y + fft_filter(y, lo=3000) * 0.15
    return y


def read_wav(path):
    import wave
    with wave.open(path, "rb") as w:
        data = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32767
        if w.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(axis=1)
    return data


def register(ids):
    """New ids into AssetPaths.SFX between the GENERATED SFX markers."""
    with open(ASSET_PATHS, encoding="utf-8") as fh:
        text = fh.read()
    start = "\t# --- GENERATED SFX (tools/audio/gen_sfx.py) ---\n"
    end = "\t# --- END GENERATED SFX ---\n"
    lines = "".join('\t&"%s": SFX_DIR + "%s.wav",\n' % (i, i) for i in sorted(ids))
    block = start + lines + end
    if start in text:
        text = re.sub(re.escape(start) + r".*?" + re.escape(end), lambda m: block, text, flags=re.S)
    else:
        text = text.replace('\t&"skill_cast": SFX_DIR + "skill_cast.wav",\n',
                            '\t&"skill_cast": SFX_DIR + "skill_cast.wav",\n' + block, 1)
    with open(ASSET_PATHS, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def main():
    new_ids = set()
    files = 0
    for fam, fn in FAMILIES.items():
        for k in KINDS:
            for v in range(3):
                name = "%s_%s" % (fam, k) + ("" if v == 0 else "_%d" % (v + 1))
                save(name, fn(k, v), 0.75 if k != "death" else 0.8, room=0.08)
                files += 1
            new_ids.add("%s_%s" % (fam, k))
    for gen in (hits, steps, traps, ui, town):
        for v in range(3):
            for name, x in gen(v).items():
                save(name + ("" if v == 0 else "_%d" % (v + 1)), x, 0.7)
                files += 1
                new_ids.add(name)
    for sid in VARIANTS:
        path = os.path.join(SFX_DIR, sid + ".wav")
        if not os.path.exists(path):
            continue
        base = read_wav(path)
        for v in (2, 3):
            save("%s_%d" % (sid, v), vary(base, v), float(np.max(np.abs(base))) or 0.8)
            files += 1
    register(new_ids)
    print("sfx: %d files, %d new ids" % (files, len(new_ids)))


if __name__ == "__main__":
    main()

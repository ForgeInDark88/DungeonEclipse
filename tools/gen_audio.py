#!/usr/bin/env python3
"""Sounds and music for DungeonEclipse — procedural synthesis with numpy.

Run from the project root:  python3 tools/gen_audio.py   (needs ffmpeg for music)
  * assets/audio/sfx/<id>.wav    — 44.1 kHz mono, layered (transient + body +
    tail), filtered, with a short room reverb;
  * assets/audio/music/<id>.ogg  — 44.1 kHz stereo OGG Vorbis: composed loops
    (chord progression, bass, pads, arpeggios, motif-based melody, drums) with
    a circular reverb so the loop point is seamless; stings are one-shots.
Every track is described in TRACKS (key, scale, tempo, metre, progression,
instruments); change a line and re-run. See docs/AUDIO_LIST.md.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
SR = 44100


# =========================================================================== DSP
class Sig(np.ndarray):
    """1-D signal whose `+` pads the shorter operand with silence, so layers of
    different lengths can simply be added."""

    def __add__(self, other):
        a, b = np.asarray(self), np.asarray(other)
        if a.ndim == 1 and b.ndim == 1 and len(a) != len(b):
            n = max(len(a), len(b))
            a = np.pad(a, (0, n - len(a)))
            b = np.pad(b, (0, n - len(b)))
        return (a + b).view(Sig)

    __radd__ = __add__


def sig(x):
    return np.asarray(x, dtype=np.float64).view(Sig)


def n_of(sec):
    return max(1, int(round(sec * SR)))


def tt(sec):
    return np.arange(n_of(sec)) / SR


def osc(kind, freq, sec, phase0=0.0):
    """Oscillator; `freq` is a number or an array (glide / vibrato)."""
    n = n_of(sec)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,)) if np.ndim(freq) else np.full(n, float(freq))
    ph = phase0 + 2 * np.pi * np.cumsum(f) / SR
    if kind == "sine":
        return sig(np.sin(ph))
    frac = (ph / (2 * np.pi)) % 1.0
    if kind == "saw":
        return sig(2 * frac - 1)
    if kind == "square":
        return sig(np.where(frac < 0.5, 1.0, -1.0))
    if kind == "tri":
        return sig(2 * np.abs(2 * frac - 1) - 1)
    raise ValueError(kind)


def noise(sec, seed=0):
    return sig(np.random.default_rng(seed).uniform(-1, 1, n_of(sec)))


def adsr(sec, a=0.005, d=0.05, s=0.7, r=0.1):
    n = n_of(sec)
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-5), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-5)))
    rel = np.clip((sec - t) / max(r, 1e-5), 0, 1)
    return e * rel


def decay(sec, k):
    """Exponential decay (k = 1/seconds) with a 2 ms click-free attack."""
    t = tt(sec)
    return np.exp(-t * k) * np.clip(t / 0.002, 0, 1)


def fft_filter(x, lo=None, hi=None, order=2):
    """Butterworth-like low / high / band pass in the frequency domain (no
    phase smearing worth worrying about for these sounds; fast for long buffers)."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        return np.stack([fft_filter(x[:, c], lo, hi, order) for c in range(x.shape[1])], axis=1)
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    H = np.ones_like(f)
    if hi:
        H /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        H /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return sig(np.fft.irfft(X * H, n))


def bandpass(x, center, q=1.0):
    return fft_filter(x, lo=center / (1 + 0.5 / q), hi=center * (1 + 0.5 / q), order=2)


def impulse(sec=1.6, damp=5000, seed=1, early=True):
    """Reverb impulse response: decaying filtered noise + a few early echoes."""
    n = n_of(sec)
    t = np.arange(n) / SR
    ir = np.random.default_rng(seed).normal(0, 1, n) * np.exp(-t * 6.9 / sec)
    ir = fft_filter(ir, lo=120, hi=damp)
    if early:
        rng = np.random.default_rng(seed + 7)
        for k in range(6):
            i = int(SR * rng.uniform(0.008, 0.06))
            ir[i] += rng.uniform(0.3, 0.8) * (-1) ** k * np.max(np.abs(ir))
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-9)


def convolve(x, ir, circular=False):
    if circular:  # loop-friendly: the tail wraps around to the start
        n = len(x)
        h = np.zeros(n)
        m = min(n, len(ir))
        h[:m] = ir[:m]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


def reverb(x, sec=1.2, mix=0.25, damp=5000, seed=1):
    """Mono reverb for SFX (the output is longer by the tail)."""
    wet = convolve(x, impulse(sec, damp, seed))
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return sig(dry * (1 - mix * 0.5) + wet * mix * 0.35)


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return sig(out)


def at(x, delay):
    return sig(np.concatenate([np.zeros(n_of(delay)), x]))


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write_wav(path, x, channels=1):
    x = np.clip(np.asarray(x, dtype=np.float64), -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def sfx(name, x, peak=0.8, room=0.0):
    x = np.asarray(x, dtype=np.float64)
    if room > 0:
        x = reverb(x, 0.5, room, 6000, seed=hash(name) & 0xFF)
    fade = min(len(x) // 4, n_of(0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    write_wav(os.path.join(SFX, name + ".wav"), normalize(x, peak))


# ===================================================================== sounds
def whoosh(sec, f0, f1, q=1.2, seed=0):
    """Air swish: noise through a band pass sliding from f0 to f1."""
    x = noise(sec, seed)
    n = len(x)
    out = np.zeros(n)
    steps = 12
    for i in range(steps):
        c = f0 * (f1 / f0) ** (i / (steps - 1))
        seg = bandpass(x, c, q)
        w = np.clip(1 - np.abs(np.linspace(0, steps - 1, n) - i), 0, 1)
        out += seg * w
    return out * adsr(sec, sec * 0.35, sec * 0.3, 0.4, sec * 0.5)


def thud(sec, f0, f1, k=18.0):
    return osc("sine", np.geomspace(f0, f1, n_of(sec)), sec) * decay(sec, k)


def metal(f, sec, k=6.0, partials=(1.0, 2.76, 5.4, 8.93), seed=0):
    """Inharmonic metallic ring (coins, clinks, bells)."""
    rng = np.random.default_rng(seed)
    out = np.zeros(n_of(sec))
    for i, p in enumerate(partials):
        out += osc("sine", f * p * rng.uniform(0.995, 1.005), sec) * decay(sec, k * (1 + i * 0.8)) / (1 + i * 0.7)
    return out


def pluck(f, sec, bright=1.0, k=3.0):
    """Harp / guitar-like pluck: harmonics decaying faster the higher they are."""
    t = tt(sec)
    out = np.zeros(len(t))
    for h in range(1, 12):
        if f * h > 12000:
            break
        out += np.sin(2 * np.pi * f * h * t) * np.exp(-t * (k + h * 1.6 / bright)) / h ** 1.15
    return sig(out * np.clip(t / 0.003, 0, 1))


def bell(f, sec, k=2.5, index=3.0):
    """FM bell: modulation index decays with the note."""
    t = tt(sec)
    i_t = index * np.exp(-t * k * 1.5)
    out = np.sin(2 * np.pi * f * t + i_t * np.sin(2 * np.pi * f * 3.5 * t))
    return sig(out * np.exp(-t * k) * np.clip(t / 0.002, 0, 1))


def make_sfx():
    # ---- UI
    sfx("ui_click", mix(bandpass(noise(0.012, 1), 3500, 1.5) * decay(0.012, 300),
                        0.5 * osc("sine", 1250, 0.035) * decay(0.035, 90)), 0.45)
    sfx("ui_hover", osc("sine", 1900, 0.025) * decay(0.025, 160) * 0.6 + bandpass(noise(0.01, 2), 6000) * decay(0.01, 500), 0.2)
    rustle = bandpass(noise(0.42, 3), 2500, 0.6) * (0.6 + 0.4 * np.abs(fft_filter(noise(0.42, 4), hi=30)) * 4)
    sfx("ui_book_open", mix(rustle * adsr(0.42, 0.04, 0.1, 0.7, 0.25), 0.8 * thud(0.15, 110, 70, 30)), 0.55, room=0.15)
    sfx("ui_book_close", mix(0.9 * thud(0.18, 95, 55, 28), at(bandpass(noise(0.16, 5), 2000) * adsr(0.16, 0.005, 0.05, 0.4, 0.1), 0.01)), 0.6,
        room=0.2)
    sfx("ui_equip", mix(0.5 * metal(1450, 0.25, 14, seed=2), 0.4 * bandpass(noise(0.08, 6), 1800) * decay(0.08, 50),
                        at(0.35 * metal(2100, 0.2, 18, seed=3), 0.035)), 0.5)
    notes = (523.3, 659.3, 784.0, 1046.5, 1318.5)
    lv = mix(*[at(bell(f, 0.9, 3.0, 2.0) * 0.6 + pluck(f, 0.9, 1.5) * 0.5, i * 0.075) for i, f in enumerate(notes)],
             at(fft_filter(noise(0.8, 7), lo=6000) * adsr(0.8, 0.2, 0.3, 0.3, 0.4) * 0.25, 0.25))
    sfx("level_up", lv, 0.7, room=0.35)
    # ---- movement
    sfx("step_stone", mix(0.9 * thud(0.07, 140, 70, 60), bandpass(noise(0.06, 8), 1400, 0.8) * decay(0.06, 70) * 0.7), 0.35)
    sfx("step_wood", mix(osc("sine", 230, 0.09) * decay(0.09, 45), 0.5 * osc("sine", 345, 0.09) * decay(0.09, 60),
                         bandpass(noise(0.02, 9), 3000) * decay(0.02, 200) * 0.6), 0.35)
    sfx("step_soft", fft_filter(noise(0.09, 10), hi=700) * adsr(0.09, 0.01, 0.03, 0.5, 0.05) + 0.4 * thud(0.06, 90, 60, 50), 0.28)
    sfx("jump", mix(whoosh(0.16, 600, 2200, 1.0, 11) * 0.8, 0.4 * bandpass(noise(0.05, 12), 1200) * decay(0.05, 60)), 0.35)
    sfx("land", mix(thud(0.16, 120, 45, 22), fft_filter(noise(0.14, 13), lo=200, hi=2500) * decay(0.14, 30) * 0.6), 0.55)
    sfx("dash", mix(whoosh(0.3, 400, 3000, 0.9, 14), 0.3 * whoosh(0.3, 3000, 900, 1.5, 15)), 0.5)
    # ---- weapons: whooshes tuned per weight
    sfx("attack_sword", mix(whoosh(0.2, 900, 2600, 1.4, 16), at(0.25 * metal(2600, 0.15, 25, seed=4), 0.02)), 0.5)
    sfx("attack_axe", mix(whoosh(0.3, 300, 1100, 1.0, 17), 0.5 * thud(0.25, 90, 60, 10) * 0.4), 0.6)
    sfx("attack_mace", mix(whoosh(0.28, 250, 900, 0.9, 18), 0.4 * thud(0.25, 80, 55, 12)), 0.6)
    sfx("attack_spear", whoosh(0.14, 1400, 3200, 2.0, 19), 0.45)
    sfx("attack_dagger", whoosh(0.09, 2200, 4500, 2.0, 20), 0.4)
    twang = pluck(98, 0.35, 2.5, 9.0) + 0.5 * pluck(196, 0.3, 2.0, 12.0)
    sfx("attack_bow", mix(twang, at(whoosh(0.15, 1800, 3500, 2.0, 21) * 0.5, 0.02),
                          bandpass(noise(0.01, 22), 4000) * decay(0.01, 400)), 0.55)
    t = tt(0.35)
    shimmer = np.sin(2 * np.pi * np.geomspace(400, 1300, len(t)) * t + 2 * np.sin(2 * np.pi * 7 * t)) * adsr(0.35, 0.03, 0.1, 0.6, 0.2)
    sfx("attack_staff", mix(shimmer * 0.6, whoosh(0.35, 800, 2500, 1.0, 23) * 0.6), 0.5, room=0.25)
    # ---- hits and deaths
    sfx("hit_flesh", mix(thud(0.14, 160, 55, 28), fft_filter(noise(0.08, 24), lo=300, hi=3000) * decay(0.08, 45) * 0.8,
                         bandpass(noise(0.006, 25), 5000) * decay(0.006, 800) * 0.6), 0.7)
    sfx("hit_crit", mix(thud(0.2, 180, 50, 20), 0.7 * metal(1750, 0.4, 7, seed=5),
                        fft_filter(noise(0.1, 26), lo=800) * decay(0.1, 40) * 0.7), 0.8, room=0.3)
    t = tt(0.26)
    grunt = osc("saw", np.linspace(150, 105, len(t)), 0.26)
    grunt = (bandpass(grunt, 650, 2.5) + 0.7 * bandpass(grunt, 1100, 3)) * adsr(0.26, 0.01, 0.08, 0.6, 0.1)
    sfx("player_hurt", mix(grunt, 0.8 * thud(0.15, 140, 60, 25)), 0.6)
    death = osc("saw", np.geomspace(220, 55, n_of(1.3)), 1.3)
    death = fft_filter(death, hi=900) * adsr(1.3, 0.02, 0.4, 0.7, 0.8) + 0.6 * thud(0.6, 100, 40, 5)
    sfx("player_death", death, 0.7, room=0.5)
    squelch = bandpass(noise(0.14, 27), 900, 1.5) * decay(0.14, 30) + 0.6 * osc("tri", np.geomspace(500, 200, n_of(0.14)), 0.14) * decay(0.14, 28)
    sfx("enemy_hurt", squelch, 0.5)
    crunch = fft_filter(noise(0.4, 28), lo=150, hi=4000) * (decay(0.4, 9) * (0.6 + 0.4 * (noise(0.4, 29) > 0.6)))
    sfx("enemy_death", mix(crunch, thud(0.35, 130, 40, 9), at(0.5 * osc("square", np.geomspace(400, 70, n_of(0.3)), 0.3) * decay(0.3, 10), 0.02)),
        0.6, room=0.35)
    t = tt(0.25)
    spit = np.sin(2 * np.pi * np.geomspace(500, 1500, len(t)) * t + 1.5 * np.sin(2 * np.pi * 40 * t)) * adsr(0.25, 0.01, 0.1, 0.5, 0.12)
    sfx("enemy_shoot", mix(spit * 0.6, whoosh(0.25, 1200, 2800, 1.5, 30) * 0.6), 0.45)
    # ---- world
    t = tt(0.45)
    creak = bandpass(osc("saw", 90 + 25 * np.sin(2 * np.pi * 3.5 * t) + np.linspace(0, 40, len(t)), 0.45), 700, 1.5)
    sfx("chest_open", mix(at(bandpass(noise(0.015, 31), 3000) * decay(0.015, 300), 0.0), at(creak * adsr(0.45, 0.05, 0.2, 0.6, 0.15), 0.03),
                          at(0.5 * metal(2400, 0.5, 6, seed=6) + 0.4 * metal(3200, 0.5, 7, seed=7), 0.4)), 0.6, room=0.25)
    sfx("chest_locked", mix(thud(0.12, 200, 120, 40), 0.7 * metal(900, 0.15, 25, seed=8), at(0.5 * metal(1100, 0.12, 30, seed=9), 0.07)), 0.55)
    for name, fs in (("pickup_common", (880, 1175)), ("pickup_rare", (880, 1175, 1568)), ("pickup_epic", (880, 1175, 1568, 2093, 2637))):
        x = mix(*[at(bell(f, 0.5, 6, 1.2) * 0.6 + pluck(f, 0.4, 2) * 0.4, i * 0.06) for i, f in enumerate(fs)])
        if name != "pickup_common":
            x = mix(x, at(fft_filter(noise(0.5, 32), lo=7000) * adsr(0.5, 0.1, 0.2, 0.3, 0.3) * 0.2, 0.1))
        sfx(name, x, 0.55, room=0.3 if name == "pickup_epic" else 0.15)
    sfx("coin", mix(metal(2350, 0.3, 10, seed=10), at(0.8 * metal(2950, 0.28, 11, seed=11), 0.05)), 0.45)
    gulps = []
    for i, f0 in enumerate((260, 300, 340)):
        t = tt(0.11)
        g = np.sin(2 * np.pi * np.geomspace(f0, f0 * 1.8, len(t)) * t) * adsr(0.11, 0.01, 0.04, 0.5, 0.05)
        gulps.append(at(g + 0.3 * fft_filter(noise(0.11, 33 + i), hi=900) * decay(0.11, 30), i * 0.16))
    sfx("potion_drink", mix(*gulps), 0.5)
    sfx("item_use", mix(whoosh(0.15, 800, 2000, 1.2, 36) * 0.6, bandpass(noise(0.01, 37), 3000) * decay(0.01, 300)), 0.4)
    debris = sum(at(bandpass(noise(0.02, 40 + k), 2500 + k * 300) * decay(0.02, 150) * 0.4, 0.04 + k * 0.035) for k in range(4))
    sfx("dig", mix(thud(0.2, 110, 50, 18), fft_filter(noise(0.18, 38), lo=400, hi=3500) * decay(0.18, 22), debris), 0.65, room=0.2)
    boom = mix(thud(1.4, 90, 28, 3.5) * 1.2, fft_filter(noise(1.4, 39), hi=900) * decay(1.4, 3.0),
               fft_filter(noise(0.25, 40), lo=1500) * decay(0.25, 18) * 0.6,
               sum(at(bandpass(noise(0.03, 50 + k), 3000) * decay(0.03, 120) * 0.3, 0.1 + k * 0.08) for k in range(8)))
    sfx("explosion", sat(boom, 1.6), 0.9, room=0.4)
    t = tt(1.0)
    portal = sum(np.sin(2 * np.pi * np.geomspace(200 * r, 700 * r, len(t)) * t + 1.5 * np.sin(2 * np.pi * 5 * t)) for r in (1, 1.5, 2.01))
    sfx("portal", portal * adsr(1.0, 0.25, 0.3, 0.7, 0.4), 0.55, room=0.5)
    t = tt(0.4)
    cast = np.sin(2 * np.pi * np.geomspace(500, 1400, len(t)) * t + 2.0 * np.sin(2 * np.pi * 11 * t)) * adsr(0.4, 0.02, 0.15, 0.5, 0.2)
    sfx("skill_cast", mix(cast * 0.6, fft_filter(noise(0.4, 41), lo=5000) * adsr(0.4, 0.05, 0.1, 0.4, 0.2) * 0.3), 0.5, room=0.35)


# ====================================================================== music
SCALES = {
    "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11], "major": [0, 2, 4, 5, 7, 9, 11],
}
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


class Song:
    """A loop: notes are placed into named buses (wrapping at the end), then
    each bus gets a filter, a pan and a reverb send; the reverb is circular."""

    def __init__(self, key, scale, bpm, beats=4, bars=16, seed=0):
        self.root = 48 + NOTE[key]  # C3-based
        self.scale = SCALES[scale]
        self.bpm = bpm
        self.beats = beats
        self.bars = bars
        self.beat = 60.0 / bpm
        self.bar = self.beat * beats
        self.length = n_of(self.bar * bars)
        self.buses = {}
        self.rng = np.random.default_rng(seed)

    def deg(self, d, octave=0):
        """MIDI note of scale degree d (0-based, may exceed 6)."""
        o, i = divmod(d, len(self.scale))
        return self.root + 12 * (o + octave) + self.scale[i]

    def chord(self, d, octave=0, size=3):
        return [self.deg(d + 2 * k, octave) for k in range(size)]

    def add(self, bus, start_sec, sig, gain=1.0):
        buf = self.buses.setdefault(bus, np.zeros(self.length))
        s = int(start_sec * SR) % self.length
        sig = np.asarray(sig) * gain
        while len(sig):
            take = min(len(sig), self.length - s)
            buf[s:s + take] += sig[:take]
            sig = sig[take:]
            s = 0

    def render(self, setup):
        """setup: bus -> dict(lo, hi, pan (-1..1), width (Haas ms), send, drive, gain)."""
        L = np.zeros(self.length)
        R = np.zeros(self.length)
        send = np.zeros(self.length)
        for bus, buf in self.buses.items():
            cfg = setup.get(bus, {})
            x = buf
            if cfg.get("lo") or cfg.get("hi"):
                x = fft_filter(x, cfg.get("lo"), cfg.get("hi"))
            if cfg.get("drive"):
                x = sat(x, cfg["drive"])
            x = x * cfg.get("gain", 1.0)
            pan = cfg.get("pan", 0.0)
            gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            width = cfg.get("width", 0.0)
            xr = np.roll(x, n_of(width / 1000.0)) if width else x
            L += x * gl * 1.41
            R += xr * gr * 1.41
            send += x * cfg.get("send", 0.2)
        size = min(2.8, self.bar * 1.2)
        wl = convolve(send, impulse(size, 4500, 11), circular=True)
        wr = convolve(send, impulse(size, 4500, 23), circular=True)
        L += wl * 0.9
        R += wr * 0.9
        st = np.stack([L, R], axis=1)
        st = sat(st / (np.max(np.abs(st)) + 1e-9) * 1.25, 1.3)
        return st / np.max(np.abs(st)) * 0.6  # headroom for the sound effects


# ---- instruments (mono signals)
def i_pad(m, sec, bright=1.0):
    f = midi_hz(m)
    t = tt(sec)
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t)
    x = sum(osc("saw", f * d * vib, sec, ph) for d, ph in ((1.0, 0), (1.006, 1.1), (0.994, 2.3)))
    x += 0.6 * osc("sine", f / 2, sec)
    x = fft_filter(x, hi=900 * bright + f)
    return x * adsr(sec, min(0.35, sec * 0.2), 0.3, 0.85, min(0.7, sec * 0.35)) * 0.18


def i_choir(m, sec):
    f = midi_hz(m)
    t = tt(sec)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t + m)
    x = osc("saw", f * vib, sec) + osc("saw", f * 1.004 * vib, sec, 0.7)
    x = bandpass(x, 700, 1.2) + 0.7 * bandpass(x, 1150, 2.0) + 0.3 * bandpass(x, 2600, 3.0)
    return x * adsr(sec, min(0.3, sec * 0.2), 0.3, 0.85, min(0.6, sec * 0.35)) * 0.5


def i_bass(m, sec, grit=0.0):
    f = midi_hz(m)
    x = osc("sine", f, sec) + 0.35 * osc("saw", f, sec) + 0.25 * osc("sine", f * 2, sec)
    if grit:
        x = sat(x, 1 + grit * 3)
    return x * adsr(sec, 0.006, 0.12, 0.75, 0.06) * 0.6


def i_pluck(m, sec, bright=1.0):
    return pluck(midi_hz(m), sec, bright, 2.5) * 0.5


def i_bell(m, sec):
    return bell(midi_hz(m), sec, 2.2, 2.5) * 0.35


def i_box(m, sec):
    """Music box / celesta: a few bright partials, fast decay."""
    f = midi_hz(m)
    t = tt(sec)
    x = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 4.02 * t) * np.exp(-t * 9) + 0.2 * np.sin(2 * np.pi * f * 10.1 * t) * np.exp(-t * 20)
    return sig(x * np.exp(-t * 3.2) * np.clip(t / 0.002, 0, 1) * 0.35)


def i_flute(m, sec):
    f = midi_hz(m)
    t = tt(sec)
    vib = 1 + 0.008 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    x = osc("sine", f * vib, sec) + 0.25 * osc("sine", f * 2 * vib, sec) + 0.08 * osc("tri", f * 3 * vib, sec)
    x += 0.06 * bandpass(noise(sec, m), f * 2, 2)
    return x * adsr(sec, 0.05, 0.1, 0.85, 0.08) * 0.3


def i_lead(m, sec):
    f = midi_hz(m)
    t = tt(sec)
    vib = 1 + 0.01 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.1) / 0.15, 0, 1)
    x = osc("saw", f * vib, sec) * 0.6 + osc("square", f * vib * 1.003, sec) * 0.4
    return fft_filter(x, hi=2400) * adsr(sec, 0.01, 0.15, 0.7, 0.06) * 0.22


def i_brass(m, sec):
    f = midi_hz(m)
    x = sum(osc("saw", f * d, sec, ph) for d, ph in ((1, 0), (1.005, 0.9), (0.995, 1.7)))
    env = adsr(sec, 0.04, 0.2, 0.7, 0.08)
    return fft_filter(x, hi=1600) * env * 0.2


def d_kick(sec=0.45, punch=1.0):
    return thud(sec, 140 * punch, 42, 9) * 1.1 + bandpass(noise(0.01, 1), 3000) * decay(0.01, 400) * 0.3


def d_snare(sec=0.25):
    return fft_filter(noise(sec, 2), lo=1200, hi=9000) * decay(sec, 18) * 0.55 + osc("sine", 190, sec) * decay(sec, 30) * 0.5


def d_hat(sec=0.06, open_=False):
    return fft_filter(noise(sec, 3), lo=7000) * decay(sec, 12 if open_ else 60) * 0.3


def d_tom(f=110, sec=0.5):
    return thud(sec, f * 1.6, f, 7) + fft_filter(noise(0.03, 4), hi=2000) * decay(0.03, 80) * 0.2


def d_taiko(sec=0.9):
    return thud(sec, 120, 55, 5) * 1.2 + fft_filter(noise(0.05, 5), hi=1200) * decay(0.05, 40) * 0.4


def d_shaker(sec=0.08):
    return fft_filter(noise(sec, 6), lo=4000, hi=11000) * adsr(sec, 0.02, 0.02, 0.4, 0.04) * 0.18


def melody(song, prog, bar_from, bars, instr, octave=1, density=0.6, gain=1.0, length=0.9, seed=0):
    """Motif-based melody: a 1-bar rhythm/contour, repeated over the chords
    (AABA'), chord tones on strong beats, steps in between."""
    rng = np.random.default_rng(seed)
    steps = song.beats * 2
    rhythm = [i for i in range(steps) if i == 0 or rng.random() < density]
    contour = np.cumsum(rng.choice([-1, 0, 1, 1, 2, -2], size=len(rhythm)))
    motifs = [(rhythm, contour), (rhythm, contour), (rhythm[::-1] if len(rhythm) > 2 else rhythm, -contour), (rhythm, contour + 1)]
    for b in range(bars):
        bar = bar_from + b
        d = prog[bar % len(prog)]
        rh, co = motifs[(b // 1) % 4]
        for k, step in enumerate(rh):
            nxt = rh[k + 1] if k + 1 < len(rh) else steps
            dur = (nxt - step) * song.beat / 2 * length
            deg = d + int(co[k % len(co)])
            if step % 4 == 0:  # strong: snap to the nearest chord tone
                chord = [d, d + 2, d + 4]
                deg = min(chord, key=lambda c: abs(c - deg))
            song.add("lead", bar * song.bar + step * song.beat / 2, instr(song.deg(deg, octave), max(0.12, dur)), gain)


# ---- arrangements
def compose(spec):
    s = Song(spec["key"], spec["scale"], spec["bpm"], spec.get("beats", 4), spec.get("bars", 16), spec.get("seed", 1))
    prog = spec["prog"]
    B, b = s.bar, s.beat
    for bar in range(s.bars):
        d = prog[bar % len(prog)]
        chord = s.chord(d, 0, 4 if spec.get("sevenths") else 3)
        part = bar // max(1, s.bars // 4)  # 0..3 intensity sections
        t0 = bar * B
        # Pads / choir: whole bar.
        pad = spec.get("pad", "pad")
        for m in chord:
            # Notes overlap the next bar: chords cross-fade instead of dipping.
            if pad == "choir":
                s.add("pad", t0, i_choir(m + 12, B + 0.6), 0.8)
            elif pad == "pad":
                s.add("pad", t0, i_pad(m + 12, B + 0.7, spec.get("bright", 1.0)), 1.0)
        # Bass.
        bass = spec.get("bass", "roots")
        root = s.deg(d, -1)
        if bass == "roots":
            s.add("bass", t0, i_bass(root, B * 0.95))
        elif bass == "pulse":
            for k in range(s.beats * 2):
                s.add("bass", t0 + k * b / 2, i_bass(root + (12 if k % 4 == 3 else 0), b * 0.45, spec.get("grit", 0)), 0.8)
        elif bass == "waltz":
            s.add("bass", t0, i_bass(root, b * 0.9), 1.0)
            for k in (1, 2):
                for m in chord:
                    s.add("comp", t0 + k * b, i_pluck(m + 12, b * 0.8, 1.2), 0.5)
        elif bass == "ostinato":
            pat = [0, 0, 7, 0, 3, 0, 7, 10]
            for k, iv in enumerate(pat):
                s.add("bass", t0 + k * b / 2, i_bass(root + iv if iv < 12 else root, b * 0.45, spec.get("grit", 0)), 0.8)
        # Arpeggio from section 1 (always for bosses).
        arp = spec.get("arp")
        if arp and (part >= 1 or spec.get("full")):
            inst = {"pluck": i_pluck, "bell": i_bell, "box": i_box}[arp]
            notes = chord + [chord[1] + 12, chord[2] + 12]
            per = spec.get("arp_rate", 2)
            n = s.beats * per
            for k in range(n):
                m = notes[[0, 1, 2, 3, 2, 1, 4, 1][k % 8] % len(notes)] + 12
                s.add("arp", t0 + k * b / per, inst(m, b / per * 2.5), 0.7)
        # Tolling bell on bar starts (eerie biomes).
        if spec.get("toll") and bar % 2 == 0:
            s.add("bell", t0, i_bell(s.deg(d, -1) + 12, B * 1.5), 0.9)
        # Drums.
        drums = spec.get("drums")
        if drums and (part >= spec.get("drums_from", 0) or spec.get("full")):
            for k in range(s.beats):
                tb = t0 + k * b
                if drums == "rock":
                    if k % 2 == 0:
                        s.add("kick", tb, d_kick())
                        s.add("kick", tb + b * 0.75, d_kick(0.3), 0.6) if k == 2 else None
                    else:
                        s.add("snare", tb, d_snare())
                    s.add("hat", tb, d_hat())
                    s.add("hat", tb + b / 2, d_hat(), 0.6)
                elif drums == "heartbeat":
                    if k == 0:
                        s.add("kick", tb, d_kick(0.4, 0.7), 0.7)
                        s.add("kick", tb + b * 0.3, d_kick(0.35, 0.6), 0.45)
                elif drums == "hand":
                    s.add("tom", tb, d_tom(150 if k % 2 else 110, 0.35), 0.6)
                    if k % 2 == 1:
                        s.add("tom", tb + b / 2, d_tom(190, 0.25), 0.4)
                    s.add("hat", tb + b / 2, d_shaker(), 1.0)
                elif drums == "taiko":
                    if k == 0 or (k == 2 and bar % 2):
                        s.add("kick", tb, d_taiko(), 1.0)
                    s.add("tom", tb + b / 2, d_tom(140, 0.3), 0.5)
                    if k == s.beats - 1:
                        s.add("tom", tb + b * 0.75, d_tom(170, 0.25), 0.5)
                elif drums == "waltz":
                    s.add("kick" if k == 0 else "snare", tb, d_kick() if k == 0 else d_snare(0.15), 1.0 if k == 0 else 0.4)
                    s.add("hat", tb, d_hat(), 0.5)
                elif drums == "shaker":
                    s.add("hat", tb, d_shaker(), 1.0)
                    s.add("hat", tb + b / 2, d_shaker(), 0.6)
        # Brass stabs (bosses / lava); bosses drop them in the 3rd quarter (breakdown).
        breakdown = spec.get("full") and part == 2
        if spec.get("stabs") and (part >= 1 or spec.get("full")) and not breakdown:
            for m in chord:
                s.add("brass", t0, i_brass(m + 12, b * 0.9), 0.8)
                if bar % 2:
                    s.add("brass", t0 + b * (s.beats - 1.5), i_brass(m + 12, b * 0.4), 0.6)
    # Melody in the second half (or throughout for bosses), a new motif every
    # 8 bars so long loops do not repeat one phrase.
    lead = spec.get("lead")
    if lead:
        inst = {"flute": i_flute, "lead": i_lead, "box": i_box, "bell": i_bell, "pluck": i_pluck}[lead]
        start = 0 if spec.get("full") else s.bars // 2
        for k, b0 in enumerate(range(start, s.bars, 8)):
            if spec.get("full") and b0 // max(1, s.bars // 4) == 2 and k % 2 == 0:
                continue  # breakdown: no lead for a while
            melody(s, prog, b0, min(8, s.bars - b0), inst, spec.get("lead_octave", 1) + (1 if k == 3 else 0),
                   spec.get("density", 0.5), spec.get("lead_gain", 1.0), seed=spec.get("seed", 1) * 10 + k)
    setup = {
        "pad": dict(hi=4000, pan=0, width=14, send=0.5, gain=0.9),
        "bass": dict(hi=900, pan=0, send=0.05, gain=1.0, drive=spec.get("bass_drive")),
        "comp": dict(hi=5000, pan=0.25, width=8, send=0.3, gain=0.7),
        "arp": dict(hi=7000, pan=-0.35, width=10, send=0.45, gain=0.7),
        "bell": dict(hi=6000, pan=0.3, width=12, send=0.6, gain=0.8),
        "lead": dict(hi=7000, pan=0.1, width=6, send=0.4, gain=0.9),
        "brass": dict(hi=3500, pan=-0.1, width=10, send=0.3, gain=0.8),
        "kick": dict(hi=5000, pan=0, send=0.08, gain=1.0),
        "snare": dict(lo=120, pan=0.05, send=0.25, gain=0.7),
        "hat": dict(lo=5000, pan=0.3, send=0.1, gain=0.6),
        "tom": dict(hi=4000, pan=-0.15, send=0.25, gain=0.8),
    }
    return s.render(setup)


TRACKS = {
    "menu": dict(key="A", scale="dorian", bpm=76, prog=[0, 5, 3, 4], pad="pad", bass="roots", arp="pluck",
                 lead="flute", sevenths=True, seed=3),
    "catacombs": dict(key="D", scale="phrygian", bpm=64, prog=[0, 1, 0, 6], pad="choir", bass="roots", toll=True,
                      drums="heartbeat", lead="box", density=0.35, lead_octave=1, seed=5),
    "fungal": dict(key="E", scale="dorian", bpm=92, prog=[0, 3, 5, 4], pad="pad", bright=0.8, bass="roots", arp="bell",
                   arp_rate=2, drums="hand", drums_from=1, lead="pluck", density=0.45, seed=7),
    "ruins": dict(key="A", scale="minor", bpm=84, prog=[0, 5, 2, 6], pad="pad", bass="roots", arp="pluck", arp_rate=2,
                  drums="shaker", drums_from=2, lead="flute", density=0.5, sevenths=True, seed=9),
    "lava": dict(key="C", scale="harmonic", bpm=100, prog=[0, 5, 3, 4], pad="pad", bright=0.6, bass="ostinato", grit=0.6,
                 bass_drive=1.8, drums="taiko", drums_from=1, stabs=True, lead="lead", density=0.4, seed=11),
    "mirror_halls": dict(key="B", scale="harmonic", bpm=126, beats=3, prog=[0, 3, 4, 0, 5, 3, 1, 4], pad="pad",
                         bass="waltz", arp="box", arp_rate=1, drums="waltz", drums_from=2, lead="box", density=0.55,
                         lead_octave=2, bars=32, seed=13),
    "boss": dict(key="D", scale="minor", bpm=140, prog=[0, 5, 3, 4], pad="pad", bass="pulse", grit=0.5, bass_drive=1.5,
                 drums="rock", stabs=True, lead="lead", density=0.6, full=True, bars=32, seed=15),
    "boss_bone_king": dict(key="E", scale="phrygian", bpm=128, prog=[0, 1, 0, 6, 0, 1, 3, 4], pad="choir", bass="ostinato",
                           grit=0.4, bass_drive=1.4, drums="taiko", toll=True, stabs=True, lead="lead", density=0.5,
                           full=True, bars=32, seed=17),
    "boss_flame_witch": dict(key="C", scale="harmonic", bpm=150, prog=[0, 5, 1, 4], pad="pad", bass="pulse", grit=0.7,
                             bass_drive=2.0, drums="rock", arp="pluck", arp_rate=4, stabs=True, lead="lead", density=0.65,
                             full=True, bars=32, seed=19),
    "boss_illusionist": dict(key="B", scale="harmonic", bpm=168, beats=3, prog=[0, 3, 4, 0, 5, 1, 4, 4], pad="pad",
                             bass="waltz", drums="waltz", arp="box", arp_rate=2, stabs=True, lead="box", lead_octave=2,
                             density=0.7, full=True, bars=48, seed=21),
}


def sting(notes, sec, inst, chord_inst=None, drum=None, minor=False):
    """One-shot: notes one after another, then the chord rings out."""
    n = n_of(sec)
    out = np.zeros(n + n_of(3))
    step = sec / (len(notes) + 2)
    for i, m in enumerate(notes):
        dur = step * (3.5 if i == len(notes) - 1 else 1.4)
        sig = inst(m, dur)
        s0 = n_of(i * step)
        out[s0:s0 + len(sig)] += sig
    if chord_inst:
        last = notes[-1]
        for iv in ((0, 3, 7) if minor else (0, 4, 7)):
            sig = chord_inst(last - 12 + iv, sec * 0.7)
            s0 = n_of(step * (len(notes) - 1))
            out[s0:s0 + len(sig)] += sig * 0.8
    if drum:
        for k in range(len(notes)):
            sig = drum()
            s0 = n_of(k * step)
            out[s0:s0 + len(sig)] += sig * 0.5
    wet = convolve(out, impulse(2.2, 5000, 31))[: len(out)]
    wr = convolve(out, impulse(2.2, 5000, 37))[: len(out)]
    st = np.stack([out + wet * 0.35, out + wr * 0.35], axis=1)
    fade = n_of(0.3)
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return st / np.max(np.abs(st)) * 0.6


def write_ogg(name, stereo):
    os.makedirs(MUSIC, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        write_wav(wav, stereo.reshape(-1), channels=2)
        out = os.path.join(MUSIC, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    print("music:", name)


def make_music():
    for name, spec in TRACKS.items():
        write_ogg("music_" + name, compose(spec))
    write_ogg("music_victory", sting([60, 64, 67, 72, 76, 79, 84], 3.2, i_brass, i_pad, drum=lambda: d_tom(110, 0.6)))
    write_ogg("music_death", sting([69, 67, 65, 64, 62, 57], 4.5, i_choir, i_choir, minor=True))


if __name__ == "__main__":
    make_sfx()
    print("sfx done")
    make_music()

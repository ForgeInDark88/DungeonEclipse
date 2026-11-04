#!/usr/bin/env python3
"""Ambience loops of the open surface and the camp, synthesized as layered
field recordings: 20 s stereo OGG Vorbis at 44.1 kHz, seamless (every bed
is shaped in the frequency domain over the whole loop, so it wraps around;
every event that runs past the end continues at the start; reverb is
circular).

  amb_wind   wind in three bands with gusts, leaves rustling in the gusts
  amb_birds  a forest morning: songbirds, a two-note tit, a distant cuckoo,
             a woodpecker, leaves and a soft breeze
  amb_night  a chorus of crickets, a tawny owl now and then, a cool breeze
  amb_frogs  a swamp: ribbits and a bullfrog calling back and forth, water
             lapping, insects
  amb_rain   rain: a hiss, fine drops, heavy drops on leaves, a far thunder
  amb_fire   a campfire: crackles and pops, the hiss and roar of the flames,
             a log settling now and then

Uses the DSP of tools/gen_audio.py (filters, reverb). Replace with real
recordings of the same name (docs/AUDIO_LIST.md).
Run from the project root:  python3 tools/gen_ambience.py   (needs ffmpeg)
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402

SR = ga.SR
LEN = 20.0
N = int(LEN * SR)
OUT = os.path.join(ga.ROOT, "assets", "audio", "ambience")


# ------------------------------------------------------------------ helpers
def shaped_noise(seed, lo=None, hi=None, tilt=0.0, order=2):
    """A loop-length noise bed, band-limited and tilted (-0.5 = pink,
    -1.0 = brown); circular by construction."""
    x = np.random.default_rng(seed).normal(0, 1, N)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(N, 1 / SR)
    H = np.power(np.maximum(f, 20.0) / 1000.0, tilt)
    if hi:
        H /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        H /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    y = np.fft.irfft(X * H, N)
    return y / (np.std(y) + 1e-9)


def slow(seed, rate=0.2, lo=0.0, hi=1.0, power=1.0):
    """A smooth random envelope that loops: noise with everything above
    `rate` Hz removed, mapped to lo..hi."""
    x = np.random.default_rng(seed).normal(0, 1, N)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(N, 1 / SR)
    X[f > rate] = 0
    y = np.fft.irfft(X, N)
    y = (y - y.min()) / (y.max() - y.min() + 1e-9)
    return lo + (hi - lo) * y ** power


class Scene:
    """A stereo loop; events wrap around its end."""

    def __init__(self):
        self.buf = np.zeros((N, 2))
        self.wet = np.zeros((N, 2))  # sent to the reverb

    def bed(self, x, gain=1.0, width=0.0, seed=0):
        """A continuous layer; `width` decorrelates the right channel."""
        if width > 0:
            r = np.roll(x, int(SR * 0.013 * width + seed))
            self.buf[:, 0] += x * gain
            self.buf[:, 1] += (x * (1 - width) + r * width) * gain
        else:
            self.buf[:, 0] += x * gain
            self.buf[:, 1] += x * gain

    def add(self, x, start, gain=1.0, pan=0.0, send=0.2):
        """One sound at `start` seconds, constant-power pan (-1..1)."""
        x = np.asarray(x, dtype=np.float64)
        i = int(start * SR) % N
        a = (pan + 1) * np.pi / 4
        lr = np.array([np.cos(a), np.sin(a)]) * gain
        idx = (np.arange(len(x)) + i) % N
        np.add.at(self.buf, idx, np.outer(x, lr) * (1 - send * 0.5))
        np.add.at(self.wet, idx, np.outer(x, lr) * send)

    def render(self, room=1.4, damp=6000, peak=0.8):
        ir = ga.impulse(room, damp, seed=5)
        out = self.buf.copy()
        for c in range(2):
            out[:, c] += ga.convolve(self.wet[:, c], ga.impulse(room, damp, seed=5 + c), circular=True) * 0.5
        del ir
        m = np.max(np.abs(out)) or 1.0
        return out / m * peak


def env(n, a, r):
    """Attack / release envelope of n samples (a, r in samples)."""
    e = np.ones(n)
    a = max(1, min(a, n // 2))
    r = max(1, min(r, n - a))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def tone(freq, sec, harm=(1.0,), phase=0.0):
    """A sine (plus harmonics) following `freq` (a number or an array)."""
    n = max(1, int(sec * SR))
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,)) if np.ndim(freq) else np.full(n, float(freq))
    ph = phase + 2 * np.pi * np.cumsum(f) / SR
    return sum(h * np.sin(ph * (k + 1)) for k, h in enumerate(harm))


def burst(sec, lo, hi, k, seed):
    """A short filtered noise burst with exponential decay."""
    n = max(8, int(sec * SR))
    x = np.random.default_rng(seed).normal(0, 1, n)
    x = np.asarray(ga.fft_filter(x, lo=lo, hi=hi))
    return x * np.exp(-np.arange(n) / SR * k) * env(n, 12, n // 3)


def save(name, stereo):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        ga.write_wav(wav, stereo.reshape(-1), channels=2)
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    print("ambience:", name)


# ------------------------------------------------------------------- layers
def wind_bed(sc, seed=1, gain=1.0, gusty=1.0):
    """Wind in three bands, each with its own gusts; leaves in the gusts."""
    low = shaped_noise(seed, lo=60, hi=380, tilt=-0.6)
    mid = shaped_noise(seed + 1, lo=300, hi=1400, tilt=-0.4)
    whistle = shaped_noise(seed + 2, lo=1400, hi=2600, order=4)
    g1 = slow(seed + 3, 0.12, 0.35, 1.0, 1.5)
    g2 = slow(seed + 4, 0.18, 0.15, 1.0, 2.0 * gusty)
    g3 = slow(seed + 5, 0.25, 0.0, 1.0, 4.0)
    sc.bed(low * g1 * 0.9 * gain, width=0.6, seed=3)
    sc.bed(mid * g2 * 0.45 * gain, width=0.8, seed=7)
    sc.bed(whistle * g3 * 0.08 * gain, width=0.9, seed=11)
    leaves = shaped_noise(seed + 6, lo=2500, hi=9000, tilt=0.2)
    rustle = slow(seed + 7, 1.5, 0.0, 1.0, 3.0) * g2
    sc.bed(leaves * rustle * 0.18 * gain, width=1.0, seed=13)


def songbird(rng):
    """A warbling phrase: 5..10 quick notes with sweeps and trills."""
    parts = []
    base = rng.uniform(2600, 4600)
    for _ in range(rng.integers(5, 11)):
        sec = rng.uniform(0.035, 0.09)
        n = int(sec * SR)
        t = np.arange(n) / SR
        f0 = base * rng.uniform(0.8, 1.35)
        sweep = rng.uniform(-1800, 2200)
        trill = rng.uniform(0, 400) * np.sin(2 * np.pi * rng.uniform(40, 90) * t)
        x = tone(f0 + sweep * t / sec + trill, sec, (1.0, 0.12)) * np.sin(np.pi * t / sec) ** 1.5
        parts.append(x)
        parts.append(np.zeros(int(rng.uniform(0.01, 0.05) * SR)))
    return np.concatenate(parts)


def tit_call(rng):
    """The two-note 'tea-cher' of a tit, repeated 2..4 times."""
    hi, lo = rng.uniform(3600, 4300), rng.uniform(2800, 3300)
    out = []
    for _ in range(rng.integers(2, 5)):
        for f, sec in ((hi, 0.12), (lo, 0.14)):
            n = int(sec * SR)
            t = np.arange(n) / SR
            out.append(tone(f * (1 - 0.04 * t / sec), sec, (1.0, 0.08)) * np.sin(np.pi * t / sec) ** 0.8)
            out.append(np.zeros(int(0.03 * SR)))
        out.append(np.zeros(int(0.09 * SR)))
    return np.concatenate(out)


def cuckoo():
    out = []
    for f, sec in ((690, 0.22), (560, 0.34)):
        n = int(sec * SR)
        t = np.arange(n) / SR
        out.append(tone(f, sec, (1.0, 0.25, 0.05)) * env(n, int(0.03 * SR), int(0.12 * SR)))
        out.append(np.zeros(int(0.08 * SR)))
    return np.asarray(ga.fft_filter(np.concatenate(out), hi=1800))


def woodpecker(rng):
    hits = int(rng.integers(12, 20))
    gap = 1 / rng.uniform(15, 20)
    out = np.zeros(int((hits * gap + 0.2) * SR))
    for k in range(hits):
        b = burst(0.03, 700, 2600, 140, int(rng.integers(1 << 30)))
        i = int(k * gap * SR)
        out[i:i + len(b)] += b * (1 - k / hits * 0.6)
    return out


def cricket(rng, f):
    """One cricket: chirps of 3..4 syllables (carrier f, ~30 Hz syllables)."""
    syl = int(rng.integers(3, 5))
    rate = rng.uniform(26, 34)
    sec = syl / rate + 0.02
    n = int(sec * SR)
    t = np.arange(n) / SR
    gate = np.clip(np.sin(2 * np.pi * rate * t), 0, 1) ** 2.5
    return tone(f + 60 * np.sin(2 * np.pi * rate * t), sec, (1.0, 0.18)) * gate * env(n, 40, 200)


def owl(rng):
    """A tawny owl: 'hoo ... hoo-hoo-hooo' with a breathy edge."""
    out = []
    f = rng.uniform(370, 430)
    for sec, gap, bend in ((0.35, 0.55, 0.0), (0.12, 0.05, 0.0), (0.12, 0.05, 0.0), (0.7, 0.0, -0.05)):
        n = int(sec * SR)
        t = np.arange(n) / SR
        vib = 1 + 0.02 * np.sin(2 * np.pi * 6 * t) + bend * t / sec
        x = tone(f * vib, sec, (1.0, 0.2)) + np.asarray(ga.fft_filter(np.random.default_rng(int(f)).normal(0, 0.08, n), lo=300, hi=1200))
        out.append(x * env(n, int(0.04 * SR), int(sec * 0.5 * SR)))
        out.append(np.zeros(int(gap * SR)))
    return np.asarray(ga.fft_filter(np.concatenate(out), hi=2000))


def ribbit(rng, f):
    """A tree frog's 'rib-bit': two bursts of glottal pulses through a
    resonance."""
    out = []
    for k in range(2):
        pulses = int(rng.integers(5, 9))
        rate = rng.uniform(55, 85)
        n = int((pulses / rate + 0.03) * SR)
        x = np.zeros(n)
        for p in range(pulses):
            i = int(p / rate * SR)
            m = min(n - i, int(0.012 * SR))
            tt = np.arange(m) / SR
            x[i:i + m] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * 260)
        x = np.asarray(ga.bandpass(x, f * 1.1, 1.4)) + x * 0.4
        out.append(x * env(n, 30, n // 3))
        out.append(np.zeros(int(rng.uniform(0.04, 0.08) * SR)))
    return np.concatenate(out)


def bullfrog(rng):
    """A deep 'jug-o-rum'."""
    sec = rng.uniform(0.45, 0.7)
    n = int(sec * SR)
    t = np.arange(n) / SR
    f = rng.uniform(95, 130)
    am = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(16, 24) * t)
    x = tone(f * (1 - 0.08 * t / sec), sec, (1.0, 0.6, 0.35, 0.15)) * am
    return np.asarray(ga.fft_filter(x, hi=900)) * env(n, int(0.05 * SR), int(0.15 * SR))


def drop(rng, lo, hi, k):
    """A raindrop: a tiny ringing tick."""
    sec = rng.uniform(0.004, 0.02)
    n = max(8, int(sec * SR))
    t = np.arange(n) / SR
    f = rng.uniform(lo, hi)
    return np.sin(2 * np.pi * f * t * (1 + 3 * t)) * np.exp(-t * k)


# ------------------------------------------------------------------ scenes
def wind():
    sc = Scene()
    wind_bed(sc, seed=11, gain=1.0, gusty=1.2)
    rng = np.random.default_rng(12)
    for _ in range(6):  # grass and twigs knocked about in the gusts
        sc.add(burst(rng.uniform(0.2, 0.6), 1800, 7000, 5, int(rng.integers(1 << 30))) * 0.25,
               rng.uniform(0, LEN), 1.0, rng.uniform(-0.8, 0.8), 0.3)
    return sc.render(room=1.0, peak=0.75)


def birds():
    sc = Scene()
    wind_bed(sc, seed=21, gain=0.35, gusty=0.6)
    rng = np.random.default_rng(22)
    t = 0.3
    while t < LEN:  # songbirds, near and far
        far = rng.random() < 0.45
        x = songbird(rng)
        if far:
            x = np.asarray(ga.fft_filter(x, hi=5000))
        sc.add(x, t, 0.12 if far else 0.32, rng.uniform(-0.9, 0.9), 0.55 if far else 0.25)
        t += rng.uniform(0.7, 2.2)
    for k in range(3):
        sc.add(tit_call(rng), rng.uniform(0, LEN), 0.22, rng.uniform(-0.7, 0.7), 0.3)
    sc.add(cuckoo(), 3.5, 0.18, -0.6, 0.7)
    sc.add(cuckoo(), 4.6, 0.18, -0.6, 0.7)
    sc.add(cuckoo(), 13.2, 0.15, -0.5, 0.7)
    sc.add(woodpecker(rng), 9.0, 0.16, 0.7, 0.6)
    return sc.render(room=1.8, damp=7000, peak=0.7)


def night():
    sc = Scene()
    wind_bed(sc, seed=31, gain=0.18, gusty=0.4)
    rng = np.random.default_rng(32)
    for c in range(7):  # a chorus of crickets
        f = rng.uniform(4100, 5300)
        pan = rng.uniform(-1, 1)
        g = rng.uniform(0.05, 0.16) * (0.5 if c > 4 else 1.0)
        period = rng.uniform(0.45, 0.9)
        t = rng.uniform(0, period)
        while t < LEN:
            sc.add(cricket(rng, f), t, g, pan, 0.35)
            t += period * rng.uniform(0.92, 1.08)
    sc.add(owl(rng), 5.0, 0.3, 0.5, 0.6)
    sc.add(owl(rng), 15.5, 0.22, -0.4, 0.7)
    return sc.render(room=2.2, damp=5000, peak=0.65)


def frogs():
    sc = Scene()
    water = shaped_noise(41, lo=80, hi=700, tilt=-0.5) * slow(42, 0.6, 0.2, 1.0, 2.0)
    sc.bed(water * 0.25, width=0.7, seed=5)
    rng = np.random.default_rng(43)
    for _ in range(3):  # gnats and a dragonfly
        sec = rng.uniform(1.5, 3.0)
        n = int(sec * SR)
        tt = np.arange(n) / SR
        f = rng.uniform(450, 620) * (1 + 0.03 * np.sin(2 * np.pi * rng.uniform(3, 7) * tt))
        x = np.asarray(ga.fft_filter(np.sign(tone(f, sec)) * 0.3, lo=400, hi=3000)) * env(n, n // 3, n // 3)
        sc.add(x, rng.uniform(0, LEN), 0.05, rng.uniform(-1, 1), 0.2)
    frogs_ = [(rng.uniform(900, 1400), rng.uniform(-0.9, 0.9), rng.uniform(0.2, 0.4)) for _ in range(4)]
    t = 0.2
    while t < LEN:  # tree frogs answer each other
        f, pan, g = frogs_[int(rng.integers(len(frogs_)))]
        for k in range(int(rng.integers(1, 4))):
            sc.add(ribbit(rng, f), t + k * 0.32, g, pan, 0.3)
        t += rng.uniform(0.5, 1.6)
    for t in (2.0, 7.5, 12.0, 17.3):
        sc.add(bullfrog(rng), t, 0.5, rng.uniform(-0.5, 0.5), 0.35)
    for _ in range(8):  # a plop now and then
        sc.add(drop(rng, 500, 900, 60) * 0.6, rng.uniform(0, LEN), 0.4, rng.uniform(-1, 1), 0.4)
    return sc.render(room=1.6, damp=4500, peak=0.7)


def rain():
    sc = Scene()
    hiss = shaped_noise(51, lo=400, hi=9000, tilt=-0.3)
    sc.bed(hiss * slow(52, 0.1, 0.75, 1.0) * 0.5, width=1.0, seed=17)
    rumble = shaped_noise(53, lo=40, hi=250, tilt=-0.8)
    sc.bed(rumble * 0.15, width=0.5)
    rng = np.random.default_rng(54)
    for _ in range(int(LEN * 220)):  # fine drops
        sc.add(drop(rng, 2500, 7000, 900), rng.uniform(0, LEN), rng.uniform(0.02, 0.08), rng.uniform(-1, 1), 0.1)
    for _ in range(int(LEN * 18)):  # heavy drops on leaves
        sc.add(drop(rng, 700, 2200, 300), rng.uniform(0, LEN), rng.uniform(0.08, 0.2), rng.uniform(-1, 1), 0.25)
    # a far roll of thunder
    n = int(5.0 * SR)
    th = shaped_noise(55, lo=25, hi=160, tilt=-1.0)[:n] * env(n, int(1.2 * SR), int(3.0 * SR))
    th *= slow(56, 3.0, 0.4, 1.0)[:n]
    sc.add(th, 11.0, 0.5, -0.3, 0.6)
    return sc.render(room=1.2, damp=7000, peak=0.7)


def fire():
    sc = Scene()
    roar = shaped_noise(61, lo=60, hi=420, tilt=-0.7) * slow(62, 2.0, 0.5, 1.0)
    sc.bed(roar * 0.55, width=0.4, seed=3)
    hiss = shaped_noise(63, lo=1800, hi=7000) * slow(64, 0.8, 0.2, 1.0, 1.5)
    sc.bed(hiss * 0.12, width=0.8, seed=9)
    rng = np.random.default_rng(65)
    t = 0.0
    while t < LEN:  # crackles, often in little clusters
        for k in range(int(rng.integers(1, 5))):
            b = burst(rng.uniform(0.004, 0.02), 1500, 9000, rng.uniform(200, 600), int(rng.integers(1 << 30)))
            sc.add(b, t + k * rng.uniform(0.01, 0.05), rng.uniform(0.15, 0.7), rng.uniform(-0.4, 0.4), 0.15)
        t += rng.exponential(0.16)
    for _ in range(14):  # bigger pops of sap
        b = burst(0.03, 600, 6000, 120, int(rng.integers(1 << 30)))
        sc.add(b, rng.uniform(0, LEN), rng.uniform(0.6, 1.0), rng.uniform(-0.3, 0.3), 0.25)
    for t in (6.0, 15.0):  # a log settles
        th = np.asarray(ga.thud(0.35, 140, 60))
        sc.add(th * 0.6, t, 0.5, 0.1, 0.3)
        sc.add(burst(0.4, 1200, 6000, 9, int(t)) * 0.5, t + 0.03, 0.4, 0.1, 0.3)
    return sc.render(room=0.9, damp=6000, peak=0.75)


SCENES = {"amb_wind": wind, "amb_birds": birds, "amb_night": night, "amb_frogs": frogs, "amb_rain": rain, "amb_fire": fire}

if __name__ == "__main__":
    names = sys.argv[1:] or list(SCENES)
    for name in names:
        save(name, SCENES[name]())
    print("ambience: ok")

#!/usr/bin/env python3
"""Ambience loops of the open surface (stage 15), synthesized: wind, birds,
night crickets, frogs, rain. 8 s mono 22.05 kHz WAV, seamless (the end
crossfades into the start). Replace with real recordings of the same name
(docs/AUDIO_LIST.md).

Run from the project root:  python3 tools/gen_ambience.py
"""
import os
import wave

import numpy as np

SR = 22050
LEN = 8.0
OUT = "assets/audio/ambience"
rng = np.random.default_rng(15)


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def loopify(x, fade=0.5):
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x[:n] = head * ramp + tail * (1 - ramp)
    return x[:-n]


def save(name, x, gain=0.5):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def t_axis(sec=LEN + 0.5):
    return np.arange(int(sec * SR)) / SR


def wind():
    t = t_axis()
    n = rng.standard_normal(t.size)
    w = lowpass(n, 0.02) * (0.6 + 0.4 * np.sin(t * 2 * np.pi * 0.17)) + lowpass(n, 0.06) * 0.3
    return loopify(w)


def birds():
    t = t_axis()
    base = wind() * 0.25
    x = np.zeros(t.size)
    for _ in range(14):
        start = rng.uniform(0, LEN - 0.6)
        f0 = rng.uniform(2500, 4200)
        for k in range(rng.integers(2, 5)):
            s = int((start + k * 0.11) * SR)
            d = int(0.07 * SR)
            tt = np.arange(d) / SR
            chirp = np.sin(2 * np.pi * (f0 + 2500 * tt / 0.07) * tt) * np.sin(np.pi * tt / 0.07)
            x[s:s + d] += chirp[: max(0, min(d, x.size - s))] * 0.5
    return base + loopify(x)[: base.size]


def night():
    t = t_axis()
    pulse = (np.sin(2 * np.pi * 28 * t) > 0.6).astype(float)
    cr = np.sin(2 * np.pi * 4300 * t) * pulse * (0.5 + 0.5 * np.sin(2 * np.pi * 0.6 * t)) * 0.3
    return loopify(cr) + wind()[: int((LEN) * SR)] * 0.15


def frogs():
    t = t_axis()
    x = np.zeros(t.size)
    for _ in range(12):
        s = int(rng.uniform(0, LEN - 0.4) * SR)
        d = int(0.25 * SR)
        tt = np.arange(d) / SR
        f = rng.uniform(140, 260)
        croak = np.sin(2 * np.pi * f * tt) * (np.sin(2 * np.pi * 30 * tt) > 0) * np.exp(-tt * 8)
        x[s:s + d] += croak[: max(0, min(d, x.size - s))]
    return loopify(x) + night()[: int(LEN * SR)] * 0.4


def rain():
    t = t_axis()
    n = rng.standard_normal(t.size)
    r = lowpass(n, 0.35) - lowpass(n, 0.05)
    drops = np.zeros(t.size)
    for _ in range(160):
        s = int(rng.uniform(0, LEN) * SR)
        d = int(0.01 * SR)
        drops[s:s + d] += rng.uniform(0.3, 1.0) * np.exp(-np.arange(min(d, t.size - s)) / 40)
    return loopify(r + drops * 0.6)


if __name__ == "__main__":
    save("amb_wind", wind(), 0.45)
    save("amb_birds", birds(), 0.4)
    save("amb_night", night(), 0.35)
    save("amb_frogs", frogs(), 0.4)
    save("amb_rain", rain(), 0.4)
    print("ambience: ok")

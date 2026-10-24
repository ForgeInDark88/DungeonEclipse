#!/usr/bin/env python3
"""Distinct cast sounds for skill families (so skills stop sharing one click).
Uses gen_audio's synth helpers. Run from tools/: python gen_cast_sfx.py
"""
from __future__ import annotations

import gen_audio as ga

np = ga.np
mix, at, osc, noise, bandpass, fft_filter = ga.mix, ga.at, ga.osc, ga.noise, ga.bandpass, ga.fft_filter
whoosh, thud, metal, bell, pluck, adsr, decay, tt = ga.whoosh, ga.thud, ga.metal, ga.bell, ga.pluck, ga.adsr, ga.decay, ga.tt
sfx = ga.sfx


def make_cast_sfx():
    # --- sword family: weight separates them
    sfx("cast_swing_heavy", mix(whoosh(0.3, 250, 900, 0.9, 31), 0.4 * metal(1900, 0.3, 9, seed=31),
                                at(0.5 * thud(0.12, 100, 60, 25), 0.24)), 0.6, room=0.25)
    sfx("cast_swing_wide", mix(whoosh(0.42, 350, 1500, 1.2, 32), at(0.3 * whoosh(0.3, 1500, 500, 1.6, 33), 0.12)), 0.6, room=0.3)
    sfx("cast_swing_quick", mix(whoosh(0.12, 2500, 5000, 2.0, 34), 0.35 * metal(3100, 0.12, 22, seed=34)), 0.5)
    sfx("cast_blades", mix(*[at(whoosh(0.1, 2200 + k * 250, 4200, 2.0, 35 + k), k * 0.035) for k in range(4)],
                           at(0.4 * metal(2700, 0.25, 15, seed=35), 0.05)), 0.55)
    # --- fire family: spark, flare, sun
    crackle = bandpass(noise(0.3, 41), 900, 0.5) * (0.5 + 0.5 * np.abs(fft_filter(noise(0.3, 42), lo=80)))
    sfx("cast_fire", mix(whoosh(0.26, 600, 1800, 1.1, 36), 0.5 * crackle, at(0.3 * thud(0.1, 120, 70, 30), 0.05)), 0.55, room=0.2)
    sfx("cast_fire_wave", mix(whoosh(0.5, 180, 700, 0.8, 37), 0.6 * crackle, 0.5 * thud(0.3, 80, 45, 12)), 0.65, room=0.35)
    t = tt(0.7)
    flare = np.sin(2 * np.pi * np.geomspace(200, 1600, len(t)) * t) * adsr(0.7, 0.05, 0.25, 0.4, 0.25)
    sfx("cast_sun", mix(flare, 0.4 * whoosh(0.6, 300, 2000, 1.0, 38), at(0.5 * bell(1046.5, 0.5, 2.0, 2.0), 0.05)), 0.7, room=0.4)
    # --- frost: glass and crack
    shimmer = np.sin(2 * np.pi * np.geomspace(1800, 3600, len(tt(0.3))) * tt(0.3)) * adsr(0.3, 0.01, 0.1, 0.5, 0.15)
    sfx("cast_frost", mix(shimmer * 0.6, 0.4 * metal(3400, 0.15, 28, seed=39), bandpass(noise(0.08, 40), 5000) * decay(0.08, 90)), 0.5, room=0.3)
    wind = fft_filter(noise(0.7, 43), lo=300, hi=1800) * adsr(0.7, 0.15, 0.3, 0.4, 0.2)
    sfx("cast_frost_big", mix(wind, at(0.5 * shimmer, 0.1), at(0.4 * bell(1568, 0.6, 2.0, 2.0), 0.2)), 0.6, room=0.4)
    # --- void / arcane: falling hum + sparkle
    t = tt(0.45)
    hum = np.sin(2 * np.pi * np.geomspace(600, 140, len(t)) * t) * adsr(0.45, 0.02, 0.2, 0.5, 0.2)
    sfx("cast_void", mix(hum, 0.3 * bandpass(noise(0.4, 44), 2200) * decay(0.4, 20), at(0.3 * bell(830, 0.4, 3.0, 2.0), 0.1)), 0.55, room=0.35)
    t = tt(0.2)
    zap = np.sin(2 * np.pi * (2400 * t + 900 * np.sin(2 * np.pi * 38 * t))) * adsr(0.2, 0.004, 0.05, 0.5, 0.08)
    sfx("cast_bolt", mix(zap * 0.7, 0.3 * bandpass(noise(0.12, 45), 3800) * decay(0.12, 120)), 0.55)
    # --- holy: bells and light
    sfx("cast_holy", mix(bell(784, 0.5, 2.0, 2.0) * 0.6, bell(1175, 0.6, 2.5, 2.0) * 0.4,
                         at(0.3 * bell(1568, 0.5, 3.0, 2.0), 0.06)), 0.55, room=0.4)
    swell = np.sin(2 * np.pi * np.geomspace(300, 900, len(tt(0.5))) * tt(0.5)) * adsr(0.5, 0.2, 0.2, 0.4, 0.2)
    sfx("cast_holy_ray", mix(swell, at(0.6 * zap, 0.3), at(0.4 * bell(1046.5, 0.6, 2.5, 2.0), 0.15)), 0.65, room=0.45)
    # --- shadow: dry dark puff
    sfx("cast_shadow", mix(whoosh(0.3, 900, 250, 1.4, 46), 0.5 * fft_filter(noise(0.25, 47), hi=900) * decay(0.25, 25),
                           at(0.3 * metal(1500, 0.2, 20, seed=46), 0.03)), 0.5, room=0.3)
    # --- force: quake, bash, shout
    sfx("cast_quake", mix(thud(0.5, 70, 35, 8), fft_filter(noise(0.5, 48), lo=80, hi=500) * adsr(0.5, 0.05, 0.3, 0.5, 0.15)), 0.75, room=0.3)
    sfx("cast_bash", mix(thud(0.2, 200, 90, 35), 0.6 * metal(700, 0.25, 6, seed=49), 0.4 * bandpass(noise(0.1, 50), 1500) * decay(0.1, 60)), 0.7, room=0.25)
    t = tt(0.4)
    growl = np.sin(2 * np.pi * (110 * t - 40 * t * t)) * adsr(0.4, 0.03, 0.15, 0.6, 0.12)
    sfx("cast_shout", mix(growl, 0.4 * fft_filter(noise(0.35, 51), lo=200, hi=1400) * adsr(0.35, 0.05, 0.2, 0.5, 0.15)), 0.7, room=0.3)
    # --- support: shield, heal
    sfx("cast_shield", mix(metal(520, 0.4, 5, seed=52) * 0.7, 0.4 * osc("sine", 260, 0.35) * decay(0.35, 25),
                           at(0.3 * metal(780, 0.3, 8, seed=53), 0.08)), 0.55, room=0.3)
    sfx("cast_heal", mix(*[at(bell(f, 0.7, 2.5, 2.0) * 0.5, i * 0.06) for i, f in enumerate((659.3, 784.0, 987.8))],
                         0.3 * osc("sine", 523.3, 0.5) * adsr(0.5, 0.1, 0.2, 0.5, 0.2)), 0.55, room=0.45)
    # --- throws
    sfx("cast_throw", mix(whoosh(0.16, 1500, 3400, 1.8, 54), at(0.4 * pluck(180, 0.2, 2.0, 8.0), 0.02),
                          bandpass(noise(0.02, 55), 4200) * decay(0.02, 300)), 0.5)


if __name__ == "__main__":
    make_cast_sfx()
    print("cast sfx done")

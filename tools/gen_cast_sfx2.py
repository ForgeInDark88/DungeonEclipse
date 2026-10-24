#!/usr/bin/env python3
"""Second pass of cast sounds: the meteor (fall + impact), the executioner,
novas, smites and shadow strikes. Run from tools/."""
from __future__ import annotations

import gen_audio as ga

np = ga.np
mix, at, osc, noise, bandpass, fft_filter = ga.mix, ga.at, ga.osc, ga.noise, ga.bandpass, ga.fft_filter
whoosh, thud, metal, bell, pluck, adsr, decay, tt = ga.whoosh, ga.thud, ga.metal, ga.bell, ga.pluck, ga.adsr, ga.decay, ga.tt
sfx = ga.sfx


def make_cast_sfx2():
    # ---- the meteor: a whistling fall from the sky...
    t = tt(0.5)
    whistle = np.sin(2 * np.pi * np.geomspace(2800, 420, len(t)) * t) * adsr(0.5, 0.25, 0.5, 0.6, 0.1)
    rumble = fft_filter(noise(0.5, 61), lo=90, hi=420) * adsr(0.5, 0.3, 0.4, 0.7, 0.1)
    sfx("meteor_fall", mix(whistle * 0.7, rumble * 0.8, at(0.25 * thud(0.1, 300, 120, 40), 0.42)), 0.7, room=0.3)
    # ...and a colossal impact: sub drop + crack + debris rain.
    t = tt(0.9)
    sub = np.sin(2 * np.pi * np.geomspace(160, 34, len(t)) * t) * adsr(0.9, 0.005, 0.25, 0.6, 0.3)
    crackle = bandpass(noise(0.5, 62), 700, 0.7) * adsr(0.5, 0.002, 0.1, 0.6, 0.15)
    debris = fft_filter(noise(0.9, 63), lo=500, hi=3200) * adsr(0.9, 0.15, 0.2, 0.5, 0.25) * 0.6
    boom = thud(0.35, 90, 38, 6) * 1.2
    sfx("meteor_impact", mix(sub * 0.9, boom, crackle * 0.8, at(debris, 0.08)), 0.95, room=0.5)
    # ---- the executioner: a guillotine of a swing - sub whoosh + sharp ring
    sfx("cast_exec", mix(whoosh(0.34, 200, 700, 0.8, 71), 0.5 * thud(0.2, 70, 40, 8),
                         at(0.6 * metal(2300, 0.35, 11, seed=71), 0.22)), 0.75, room=0.35)
    # ---- novas: a breath in, then a bursting bloom
    t = tt(0.5)
    bloom = np.sin(2 * np.pi * np.geomspace(180, 900, len(t)) * t) * adsr(0.5, 0.35, 0.2, 0.5, 0.15)
    sfx("cast_nova", mix(bloom, 0.4 * whoosh(0.4, 900, 2200, 1.4, 72), at(0.4 * thud(0.12, 130, 70, 26), 0.3)), 0.65, room=0.35)
    # ---- holy smite: a choir swell cracking into light
    swell = np.sin(2 * np.pi * np.geomspace(240, 720, len(tt(0.4))) * tt(0.4)) * adsr(0.4, 0.15, 0.2, 0.5, 0.15)
    t2 = tt(0.16)
    snap = np.sin(2 * np.pi * (2600 * t2 + 700 * np.sin(2 * np.pi * 44 * t2))) * adsr(0.16, 0.004, 0.05, 0.5, 0.08)
    sfx("cast_holy_smite", mix(swell * 0.8, at(0.7 * snap, 0.34), at(0.4 * bell(1318.5, 0.5, 2.5, 2.0), 0.36)), 0.7, room=0.45)
    # ---- shadow strike: a whisper and a wet cut
    whisper = fft_filter(noise(0.2, 73), lo=600, hi=2600) * adsr(0.2, 0.06, 0.2, 0.6, 0.1)
    sfx("cast_shadow_strike", mix(whoosh(0.14, 2600, 5200, 2.2, 74) * 0.8, whisper * 0.7,
                                  at(0.5 * thud(0.1, 220, 110, 45), 0.06)), 0.6, room=0.3)


if __name__ == "__main__":
    make_cast_sfx2()
    print("cast sfx pass 2 done")

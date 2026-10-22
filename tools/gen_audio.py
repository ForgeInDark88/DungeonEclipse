#!/usr/bin/env python3
"""Placeholder sounds and music for DungeonEclipse (simple synthesis, numpy).

Run from the project root:  python3 tools/gen_audio.py
Writes 16-bit mono WAV files to assets/audio/sfx and assets/audio/music.
Replace any file with your own sound of the same name (WAV or OGG — for OGG
change the extension in scripts/core/asset_paths.gd). See docs/AUDIO_LIST.md.
"""
from __future__ import annotations

import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
SR = 22050
rng = np.random.default_rng(42)


def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def env(n, attack=0.005, release=0.1, dur=None):
    dur = dur or n / SR
    tt = np.linspace(0, dur, n, endpoint=False)
    a = np.clip(tt / max(attack, 1e-4), 0, 1)
    r = np.clip((dur - tt) / max(release, 1e-4), 0, 1)
    return a * r


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, k=0.2):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def tone(freq, dur, kind="sine"):
    tt = t(dur)
    f = np.asarray(freq) if np.ndim(freq) else freq
    phase = 2 * np.pi * np.cumsum(np.broadcast_to(f, tt.shape)) / SR
    if kind == "square":
        return np.sign(np.sin(phase))
    if kind == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if kind == "tri":
        return 2 * np.abs(2 * ((phase / (2 * np.pi)) % 1.0) - 1) - 1
    return np.sin(phase)


def sweep(f0, f1, dur, kind="sine"):
    return tone(np.linspace(f0, f1, int(SR * dur)), dur, kind)


def save(path, x, vol=0.6):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = np.clip(x / peak * vol, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def sfx(name, x, vol=0.6):
    save(os.path.join(SFX, name + ".wav"), x, vol)


def make_sfx():
    # UI
    sfx("ui_click", tone(900, 0.04, "square") * env(int(SR * 0.04), release=0.03), 0.3)
    sfx("ui_hover", tone(1400, 0.02) * env(int(SR * 0.02), release=0.015), 0.15)
    b = lowpass(noise(0.35), 0.08) * env(int(SR * 0.35), 0.05, 0.2)
    sfx("ui_book_open", b + 0.3 * sweep(200, 320, 0.35) * env(int(SR * 0.35), 0.02, 0.2), 0.45)
    sfx("ui_book_close", lowpass(noise(0.2), 0.12) * env(int(SR * 0.2), 0.005, 0.15), 0.45)
    sfx("ui_equip", (tone(520, 0.08, "tri") + tone(780, 0.08, "tri")) * env(int(SR * 0.08), release=0.06), 0.4)
    lv = np.concatenate([tone(f, 0.11, "square") * env(int(SR * 0.11), release=0.08) for f in (523, 659, 784, 1047)])
    sfx("level_up", lv, 0.4)
    # Movement
    for name, k, f in (("step_stone", 0.5, 0.05), ("step_wood", 0.25, 0.07), ("step_soft", 0.08, 0.06)):
        x = lowpass(noise(f), k) * env(int(SR * f), 0.002, f * 0.8)
        if name == "step_wood":
            x += 0.4 * tone(180, f) * env(int(SR * f), 0.002, f * 0.7)
        sfx(name, x, 0.25)
    sfx("jump", sweep(220, 420, 0.12, "tri") * env(int(SR * 0.12), 0.005, 0.08), 0.3)
    sfx("land", lowpass(noise(0.12), 0.2) * env(int(SR * 0.12), 0.002, 0.1) + 0.5 * sweep(140, 60, 0.12) * env(int(SR * 0.12), 0.002, 0.1), 0.45)
    sfx("dash", lowpass(noise(0.25), 0.35) * env(int(SR * 0.25), 0.02, 0.2) * np.linspace(0.3, 1, int(SR * 0.25)), 0.4)
    # Combat: swings per weapon type
    def swing(dur, k, f0, f1):
        x = lowpass(noise(dur), k) * env(int(SR * dur), 0.01, dur * 0.7)
        return x + 0.25 * sweep(f0, f1, dur) * env(int(SR * dur), 0.01, dur * 0.7)
    sfx("attack_sword", swing(0.16, 0.35, 700, 300), 0.4)
    sfx("attack_axe", swing(0.26, 0.15, 300, 120), 0.5)
    sfx("attack_mace", swing(0.24, 0.12, 250, 100), 0.5)
    sfx("attack_spear", swing(0.12, 0.45, 900, 600), 0.35)
    sfx("attack_dagger", swing(0.08, 0.6, 1200, 800), 0.3)
    sfx("attack_bow", tone(140, 0.18, "tri") * env(int(SR * 0.18), 0.002, 0.15) + 0.4 * lowpass(noise(0.18), 0.5) * env(int(SR * 0.18), 0.002, 0.05), 0.45)
    sfx("attack_staff", sweep(300, 900, 0.25, "sine") * env(int(SR * 0.25), 0.02, 0.2) + 0.3 * tone(1200, 0.25) * env(int(SR * 0.25), 0.02, 0.2), 0.35)
    sfx("hit_flesh", lowpass(noise(0.1), 0.25) * env(int(SR * 0.1), 0.001, 0.09) + 0.6 * sweep(180, 70, 0.1) * env(int(SR * 0.1), 0.001, 0.09), 0.5)
    sfx("hit_crit", lowpass(noise(0.14), 0.45) * env(int(SR * 0.14), 0.001, 0.12) + 0.5 * tone(1600, 0.14, "square") * env(int(SR * 0.14), 0.001, 0.05), 0.6)
    sfx("player_hurt", sweep(400, 150, 0.2, "square") * env(int(SR * 0.2), 0.002, 0.15) + 0.4 * lowpass(noise(0.2), 0.3) * env(int(SR * 0.2), 0.002, 0.1), 0.45)
    sfx("player_death", sweep(300, 50, 1.0, "saw") * env(int(SR * 1.0), 0.01, 0.8), 0.45)
    sfx("enemy_hurt", sweep(500, 250, 0.1, "tri") * env(int(SR * 0.1), 0.001, 0.08), 0.35)
    sfx("enemy_death", lowpass(noise(0.35), 0.2) * env(int(SR * 0.35), 0.005, 0.3) + 0.5 * sweep(300, 60, 0.35, "square") * env(int(SR * 0.35), 0.005, 0.3), 0.45)
    sfx("enemy_shoot", sweep(600, 1400, 0.18) * env(int(SR * 0.18), 0.005, 0.15), 0.3)
    # World
    sfx("chest_open", np.concatenate([lowpass(noise(0.08), 0.2) * env(int(SR * 0.08), 0.002, 0.06),
                                      sweep(300, 500, 0.2, "tri") * env(int(SR * 0.2), 0.01, 0.15)]), 0.45)
    sfx("chest_locked", (tone(200, 0.1, "square") * env(int(SR * 0.1), 0.001, 0.05)), 0.35)
    for name, notes in (("pickup_common", (660, 880)), ("pickup_rare", (660, 880, 1175)), ("pickup_epic", (660, 880, 1175, 1568))):
        x = np.concatenate([tone(f, 0.06, "tri") * env(int(SR * 0.06), 0.002, 0.05) for f in notes])
        sfx(name, x, 0.35)
    sfx("coin", (tone(1800, 0.12) + tone(2400, 0.12)) * env(int(SR * 0.12), 0.001, 0.11), 0.3)
    sfx("potion_drink", np.concatenate([lowpass(noise(0.06), 0.15) * env(int(SR * 0.06), 0.005, 0.04) * (1 + 0.5 * tone(8, 0.06)) for _ in range(3)]), 0.4)
    sfx("item_use", sweep(500, 700, 0.1, "tri") * env(int(SR * 0.1), 0.005, 0.08), 0.3)
    sfx("dig", lowpass(noise(0.18), 0.5) * env(int(SR * 0.18), 0.001, 0.15) + 0.4 * tone(90, 0.18) * env(int(SR * 0.18), 0.001, 0.12), 0.5)
    sfx("explosion", lowpass(noise(0.9), 0.06) * env(int(SR * 0.9), 0.002, 0.8) + 0.6 * sweep(120, 30, 0.9) * env(int(SR * 0.9), 0.002, 0.7), 0.7)
    sfx("portal", sweep(200, 800, 0.8) * env(int(SR * 0.8), 0.1, 0.4) + 0.4 * sweep(400, 1600, 0.8, "tri") * env(int(SR * 0.8), 0.1, 0.4), 0.4)
    sfx("skill_cast", sweep(400, 1000, 0.2, "tri") * env(int(SR * 0.2), 0.01, 0.15), 0.3)


def chord_loop(root, minor=True, dur=16.0, tempo=0.5, flavor="drone"):
    """Slow ambient loop: low drone + arpeggio of a minor chord + soft noise."""
    tt = t(dur)
    third = root * (1.189 if minor else 1.26)
    fifth = root * 1.498
    x = 0.35 * np.sin(2 * np.pi * root / 2 * tt) + 0.2 * np.sin(2 * np.pi * root / 2 * 1.005 * tt)
    notes = [root, third, fifth, root * 2, fifth, third]
    step = tempo
    for i in range(int(dur / step)):
        f = notes[i % len(notes)]
        start = int(i * step * SR)
        n = int(step * SR * 1.5)
        seg = tone(f, n / SR, "tri" if flavor != "boss" else "square") * env(n, 0.02, n / SR * 0.8) * 0.25
        end = min(len(x), start + n)
        x[start:end] += seg[: end - start]
    x += 0.04 * lowpass(noise(dur), 0.02)
    if flavor == "boss":
        beat = np.zeros_like(x)
        for i in range(int(dur / 0.5)):
            s = int(i * 0.5 * SR)
            n = int(0.15 * SR)
            beat[s:s + n] += sweep(120, 40, 0.15)[: len(beat[s:s + n])] * env(n, 0.001, 0.12)[: len(beat[s:s + n])]
        x += 0.6 * beat
    # Smooth loop seam.
    fade = int(0.05 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def _fit(a, n):
    """Exactly n samples (rounding in tone()/env() can differ by one)."""
    return a[:n] if len(a) >= n else np.pad(a, (0, n - len(a)))


def sting(notes, dur, kind="tri"):
    """One-shot jingle: notes one after another, the last one rings out."""
    x = np.zeros(int(dur * SR))
    step = dur / (len(notes) + 2)
    for i, f in enumerate(notes):
        start = int(i * step * SR)
        n = len(x) - start if i == len(notes) - 1 else int(step * SR * 1.6)
        seg = (_fit(tone(f, n / SR, kind), n) + 0.5 * _fit(tone(f * 2, n / SR, "sine"), n)) * _fit(env(n, 0.01, n / SR * (0.9 if i == len(notes) - 1 else 0.6)), n) * 0.3
        end = min(len(x), start + n)
        x[start:end] += seg[: end - start]
    x += 0.15 * np.sin(2 * np.pi * notes[0] / 2 * np.arange(len(x)) / SR) * np.linspace(1, 0, len(x))
    x[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))
    return x


def make_music():
    save(os.path.join(MUSIC, "music_menu.wav"), chord_loop(110.0, True, 16, 0.6), 0.35)
    save(os.path.join(MUSIC, "music_catacombs.wav"), chord_loop(98.0, True, 16, 0.55), 0.35)
    save(os.path.join(MUSIC, "music_fungal.wav"), chord_loop(130.8, False, 16, 0.45), 0.35)
    save(os.path.join(MUSIC, "music_ruins.wav"), chord_loop(116.5, True, 16, 0.5), 0.35)
    save(os.path.join(MUSIC, "music_lava.wav"), chord_loop(87.3, True, 16, 0.35), 0.4)
    save(os.path.join(MUSIC, "music_boss.wav"), chord_loop(73.4, True, 16, 0.25, "boss"), 0.45)
    save(os.path.join(MUSIC, "music_boss_bone_king.wav"), chord_loop(65.4, True, 16, 0.3, "boss"), 0.45)
    save(os.path.join(MUSIC, "music_boss_flame_witch.wav"), chord_loop(82.4, True, 16, 0.2, "boss"), 0.45)
    # Stings (not looped): victory — rising major arpeggio, death — falling minor line.
    save(os.path.join(MUSIC, "music_victory.wav"), sting([261.6, 329.6, 392.0, 523.3, 659.3], 4.0), 0.45)
    save(os.path.join(MUSIC, "music_death.wav"), sting([220.0, 196.0, 174.6, 164.8, 110.0], 4.5, "sine"), 0.45)


if __name__ == "__main__":
    make_sfx()
    make_music()
    print("audio generated")

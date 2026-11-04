#!/usr/bin/env python3
"""All looping music of the game, 2-4 minutes each, with combat layers.

Tracks: TRACKS of tools/gen_audio.py and of tools/gen_abyss.py (the deep
biomes), composed by gen_audio.compose (LONG_SECONDS, a bridge in the third
quarter, the lead an octave up in the last). For every place where fights
happen (dungeon biomes, the surface) also music_<id>_combat.ogg: the same
length, key and tempo, heavy drums and a driving bass that AudioManager
fades in during a fight. Bosses, the menu, the town and the camp have no
combat layer (a boss track is the fight; no fights in town).

  python3 tools/audio/gen_music.py               everything (4 processes)
  python3 tools/audio/gen_music.py catacombs town  some tracks
Stings (victory, death, ending) and the Eclipse boss stay in gen_audio.py.
"""
import importlib.util
import os
import sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
NO_COMBAT = ("menu", "town", "camp")


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(TOOLS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, TOOLS)
    spec.loader.exec_module(mod)
    return mod


ga = _load("gen_audio")


def all_tracks():
    tracks = dict(ga.TRACKS)
    tracks.update(_load("gen_abyss").TRACKS)
    return tracks


def has_combat(name):
    return not name.startswith("boss") and name not in NO_COMBAT


def build(job):
    name, spec = job
    ga.write_ogg("music_" + name, ga.compose(spec))
    if has_combat(name):
        ga.write_ogg("music_%s_combat" % name, ga.compose(spec, layer="combat"))
    return name


def main():
    tracks = all_tracks()
    names = sys.argv[1:] or list(tracks)
    with Pool(4) as pool:
        for n in pool.imap_unordered(build, [(n, tracks[n]) for n in names]):
            print("done", n, "(%d bars)" % ga.song_bars(tracks[n]))


if __name__ == "__main__":
    main()

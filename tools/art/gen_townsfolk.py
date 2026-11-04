#!/usr/bin/env python3
"""Passers-by of the town: 26 people built from layers.

Writes assets/sprites/npc/folk_<role>_idle.png (2 frames, 40x30) and
folk_<role>_walk.png (4 frames, 80x30), facing right like the residents.
A person = build (adult / stout / child / elder) + skin + hair (+ beard) +
clothes (tunic / dress / robe / armour / apron / rags / cloak) + headwear
(hood, cap, straw hat, helmet, scarf, mitre) + a thing in hand (basket,
spear, staff, book, bucket, bread, lantern, sack, pick, bow, broom).
Shaded by the decor renderer (tools/art/gen_decor_pack.py): light from the
top left, a dark outline. ROLES lists the 26 people; scripts/world/
town_passerby.gd walks them along the street.

  python3 tools/art/gen_townsfolk.py
"""
import importlib.util
import os
import random
import zlib

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NPC = os.path.join(ROOT, "assets", "sprites", "npc")
_spec = importlib.util.spec_from_file_location("decor", os.path.join(HERE, "gen_decor_pack.py"))
decor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(decor)
Sprite, ramp = decor.Sprite, decor.ramp

W, H = 20, 30
SKINS = [(236, 196, 160), (214, 168, 128), (180, 126, 88), (138, 92, 62), (100, 68, 48)]
HAIRS = [(60, 40, 28), (110, 70, 40), (200, 160, 80), (150, 60, 30), (200, 196, 190), (30, 26, 30)]

# role: build, clothes, colour, headwear, held, extra
ROLES = {
    "farmer": ("adult", "tunic", (120, 100, 60), "straw", "basket", ""),
    "guard": ("adult", "armour", (110, 112, 120), "helmet", "spear", ""),
    "boy": ("child", "tunic", (70, 110, 160), "", "", ""),
    "girl": ("child", "dress", (180, 80, 90), "", "bread", ""),
    "noble": ("adult", "dress", (110, 50, 120), "", "", "gold"),
    "monk": ("adult", "robe", (110, 84, 60), "hood", "book", ""),
    "beggar": ("elder", "rags", (110, 100, 86), "", "staff", ""),
    "baker": ("stout", "apron", (220, 210, 190), "cap", "bread", ""),
    "fisher": ("adult", "tunic", (60, 90, 110), "cap", "bucket", ""),
    "miner": ("stout", "tunic", (90, 80, 70), "helmet", "pick", "lamp"),
    "maid": ("adult", "dress", (60, 70, 110), "scarf", "bucket", ""),
    "elder": ("elder", "robe", (90, 90, 110), "", "staff", "beard"),
    "merchant": ("stout", "tunic", (150, 110, 50), "cap", "sack", "beard"),
    "hunter": ("adult", "cloak", (70, 100, 60), "hood", "bow", ""),
    "scholar": ("adult", "robe", (60, 60, 100), "", "book", ""),
    "lamplighter": ("adult", "tunic", (90, 70, 50), "cap", "lantern", ""),
    "washer": ("stout", "apron", (180, 170, 160), "scarf", "bucket", ""),
    "shepherd": ("adult", "cloak", (140, 120, 90), "straw", "staff", ""),
    "priest": ("adult", "robe", (220, 214, 200), "mitre", "book", "gold"),
    "apprentice": ("adult", "apron", (120, 90, 60), "", "pick", ""),
    "traveller": ("adult", "cloak", (100, 80, 70), "hood", "staff", ""),
    "veteran": ("stout", "armour", (130, 120, 100), "", "", "beard"),
    "herbalist": ("elder", "dress", (80, 110, 70), "scarf", "basket", ""),
    "sweeper": ("adult", "rags", (120, 110, 90), "cap", "broom", ""),
    "bard": ("adult", "tunic", (160, 60, 50), "cap", "", "feather"),
    "courier": ("child", "tunic", (150, 120, 60), "cap", "sack", ""),
}


def palette(role, r):
    build, clothes, col, head, held, extra = ROLES[role]
    skin = SKINS[r.randrange(len(SKINS))]
    hair = HAIRS[4] if build == "elder" else HAIRS[r.randrange(len(HAIRS) - 1)]
    pal = {
        "skin": ramp(skin, 0.3), "hair": ramp(hair, 0.4), "cloth": ramp(col),
        "cloth2": ramp(tuple(int(c * 0.7) for c in col)), "metal": ramp((140, 142, 150)),
        "wood": ramp((120, 84, 50)), "gold": ramp((210, 170, 70)), "straw": ramp((210, 180, 100)),
        "bone": ramp((230, 222, 200)), "glow": ramp((255, 210, 120), 0.3), "leather": ramp((100, 70, 46)),
        "stone": ramp((60, 50, 50)), "dark": ramp((40, 32, 36)),
    }
    return pal


def person(role, frame, walk, r):
    """One frame. walk: 0..3 walking frames, None = idle (frame 0/1 bob)."""
    build, clothes, col, head, held, extra = ROLES[role]
    s = Sprite(W, H)
    child = build == "child"
    stout = build == "stout"
    elder = build == "elder"
    bob = 0
    if walk is None:
        bob = frame  # idle: a one-pixel breath
    else:
        bob = walk % 2
    top = (10 if child else 3) + bob + (1 if elder else 0)
    body_top = top + 9
    feet = H - 1
    bx0, bx1 = (7, 12) if child else ((5, 14) if stout else (6, 13))
    # legs
    legs = [(8, 9), (11, 12)]
    if walk is not None:
        shift = (0, 1, 0, -1)[walk]
        legs = [(8 - shift, 9 - shift), (11 + shift, 12 + shift)]
    leg_top = feet - (4 if child else 5)
    long_skirt = clothes in ("dress", "robe")
    for (a, b) in legs:
        for y in range(leg_top, feet + 1):
            s.put(a, y, "leather" if y >= feet - 1 else "cloth2")
            s.put(b, y, "leather" if y >= feet - 1 else "cloth2")
    # body
    bottom = feet - 1 if long_skirt else leg_top
    for y in range(body_top, bottom + 1):
        flare = (y - body_top) // 4 if long_skirt else 0
        x0, x1 = bx0 - flare // 2, bx1 + (flare + 1) // 2
        for x in range(x0, x1 + 1):
            mat = "cloth"
            if clothes == "apron" and 8 <= x <= bx1 - 1 and y > body_top + 2:
                mat = "bone"
            if clothes == "armour" and (y - body_top) % 3 == 0:
                mat = "metal"
            if clothes == "rags" and (x * 5 + y * 3) % 7 == 0:
                mat = "cloth2"
            s.put(x, y, mat)
    if clothes == "armour":
        for x in range(bx0, bx1 + 1):
            s.put(x, body_top, "metal", 1)
    if clothes == "cloak":
        for y in range(body_top, bottom + 2):
            s.put(bx0 - 1, y, "cloth2")
    belt = body_top + (6 if not child else 4)
    if not long_skirt:
        for x in range(bx0, bx1 + 1):
            s.put(x, belt, "leather", -1)
    if extra == "gold":
        for x in range(bx0 + 1, bx1):
            s.put(x, body_top + 1, "gold", 1)
    # back arm, front arm (swings when walking)
    swing = 0 if walk is None else (0, 1, 0, -1)[walk]
    for y in range(body_top + 1, body_top + (5 if child else 7)):
        s.put(bx0 - 0, y, "cloth2")
    hand_y = body_top + (5 if child else 7) + (swing if held == "" else 0)
    hx = bx1 + 1
    for y in range(body_top + 1, hand_y):
        s.put(hx, y, "cloth", 0)
    s.put(hx, hand_y, "skin", 1)
    # head
    hx0, hx1 = (6, 13) if not child else (6, 12)
    for y in range(top, top + 8):
        for x in range(hx0, hx1 + 1):
            if (y == top or y == top + 7) and (x == hx0 or x == hx1):
                continue
            s.put(x, y, "skin")
    s.mark(hx1 - 1, top + 3, "dark", 1)  # eye
    s.mark(hx1, top + 5, "skin", 1)      # nose
    if not child:
        s.mark(hx1 - 1, top + 6, "skin", 0)  # mouth line
    # hair (behind and on top)
    hstyle = r.choice(("short", "long", "bun", "short"))
    if elder and r.random() < 0.4:
        hstyle = "bald"
    if hstyle != "bald":
        for x in range(hx0, hx1 + 1):
            s.put(x, top, "hair", 1)
        for y in range(top, top + (7 if hstyle == "long" else 4)):
            s.put(hx0, y, "hair")
            s.put(hx0 + 1, y, "hair")
        if hstyle == "long":
            for y in range(top + 4, top + 10):
                s.put(hx0 - 1, y, "hair", -1)
        if hstyle == "bun":
            s.put(hx0 - 1, top + 1, "hair", 1)
            s.put(hx0 - 1, top + 2, "hair")
        for x in range(hx0 + 2, hx1 - 1):
            s.put(x, top + 1, "hair")
    if extra == "beard":
        for y in range(top + 5, top + 9):
            for x in range(hx1 - 4, hx1 + 1):
                s.put(x, y, "hair", 0 if y < top + 8 else -1)
        s.mark(hx1 - 1, top + 3, "dark", 1)
    # headwear
    if head == "hood":
        for y in range(top - 1, top + 9):
            for x in range(hx0 - 1, hx1 + 1):
                inside = x > hx0 + 2 and top + 2 <= y <= top + 7
                if not inside:
                    s.put(x, y, "cloth2")
    elif head == "cap":
        for x in range(hx0, hx1 + 2):
            s.put(x, top, "cloth2", 1)
            s.put(x, top - 1, "cloth2")
        s.put(hx1 + 2, top, "cloth2", -1)
    elif head == "straw":
        for x in range(hx0 - 2, hx1 + 3):
            s.put(x, top, "straw")
        for x in range(hx0 + 1, hx1):
            s.put(x, top - 1, "straw", 1)
            s.put(x, top - 2, "straw")
    elif head == "helmet":
        for y in range(top - 1, top + 3):
            for x in range(hx0, hx1 + 1):
                s.put(x, y, "metal", 1 if y == top - 1 else 0)
        if extra == "lamp":
            s.mark(hx1, top, "glow", 4)
    elif head == "scarf":
        for y in range(top - 1, top + 3):
            for x in range(hx0 - 1, hx1):
                s.put(x, y, "cloth2", 1)
        s.put(hx0 - 2, top + 3, "cloth2")
    elif head == "mitre":
        for y in range(top - 4, top + 1):
            for x in range(hx0 + 1 + (top - y) // 2, hx1 - (top - y) // 2):
                s.put(x, y, "bone", 1)
        s.mark((hx0 + hx1) // 2, top - 2, "gold", 3)
    if extra == "feather":
        s.put(hx0, top - 2, "cloth", 2)
        s.put(hx0 - 1, top - 3, "cloth", 2)
    # the thing in hand (front hand at hx, hand_y)
    if held == "basket":
        for y in range(hand_y, hand_y + 3):
            for x in range(hx, hx + 4):
                s.put(x, y, "straw", -1 if y == hand_y + 2 else 0)
        s.mark(hx + 1, hand_y - 1, "cloth", 3)
    elif held in ("spear", "staff", "broom"):
        x = hx + 1
        tip = top - (3 if held == "spear" else 0)
        for y in range(tip, feet + 1):
            s.put(x, y, "wood")
        if held == "spear":
            s.put(x, tip - 1, "metal", 2)
            s.put(x, tip - 2, "metal", 2)
        if held == "broom":
            for y in range(feet - 3, feet + 1):
                for dx in (-1, 0, 1):
                    s.put(x + dx, y, "straw")
    elif held == "book":
        s.rect(hx, hand_y - 2, hx + 2, hand_y, "cloth2", 1)
        s.mark(hx + 2, hand_y - 1, "bone", 3)
    elif held == "bucket":
        s.rect(hx, hand_y + 1, hx + 3, hand_y + 4, "wood")
        s.put(hx + 1, hand_y, "metal")
    elif held == "bread":
        s.ellipse(hx + 1.5, hand_y, 2, 1.2, "straw", 1)
    elif held == "lantern":
        s.rect(hx, hand_y + 1, hx + 2, hand_y + 4, "glow", 1)
        s.put(hx + 1, hand_y, "metal")
    elif held == "sack":
        s.ellipse(hx + 1, hand_y + 2, 2, 2.5, "leather", 1)
    elif held == "pick":
        for y in range(hand_y - 5, hand_y + 2):
            s.put(hx + 1, y, "wood")
        s.line(hx - 1, hand_y - 6, hx + 3, hand_y - 5, "metal", 1)
    elif held == "bow":
        for y in range(body_top - 1, body_top + 9):
            dx = 1 if body_top + 1 <= y <= body_top + 6 else 0
            s.put(hx + 1 + dx, y, "wood")
    return s


def sheet(role, frames):
    r = random.Random(zlib.crc32(role.encode()))
    pal = palette(role, r)
    out = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
    for i, (frame, walk) in enumerate(frames):
        rr = random.Random(zlib.crc32(role.encode()) + 7)  # same hair in every frame
        out.alpha_composite(person(role, frame, walk, rr).render(pal), (i * W, 0))
    return out


def main():
    os.makedirs(NPC, exist_ok=True)
    for role in ROLES:
        sheet(role, [(0, None), (1, None)]).save(os.path.join(NPC, "folk_%s_idle.png" % role), optimize=True)
        sheet(role, [(0, k) for k in range(4)]).save(os.path.join(NPC, "folk_%s_walk.png" % role), optimize=True)
    print("townsfolk:", len(ROLES))


if __name__ == "__main__":
    main()

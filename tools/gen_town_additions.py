"""Town additions for the guild: the herald, the quest board, the return
stairs. Palette follows tools/gen_town.py so everything sits in one street.
Run from tools/:  py -3 gen_town_additions.py
"""
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import gen_placeholders as gp
from gen_monsters import lit, mask
from gen_structures import finish

from PIL import Image, ImageDraw

A = gp.A
OUT = "sprites/town/"

TIMBER = (86, 56, 36)
WOOD = (126, 86, 50)
WOOD_DARK = (96, 62, 36)
PAPER = (222, 204, 168)
PAPER_DARK = (188, 168, 132)
STONE = (128, 122, 116)
STONE_DARK = (92, 86, 82)
ROBE = (74, 48, 110)      # deep eclipse violet
ROBE_LIGHT = (104, 70, 150)
GOLD = (232, 190, 90)
INK = (26, 18, 30)


def save(im, name):
    path = os.path.join(A, OUT + name + ".png")
    im.save(path)
    print("wrote", name, im.size)


def _c(x, f):
    return tuple(min(255, int(v * f)) for v in x[:3])


# ----------------------------------------------------------------- herald
def quest_giver():
    """A hooded guild herald in eclipse violet, holding an open scroll."""
    W, H = 20, 30
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # robe: a long cone, volume lit from the top-left
    def _m(dd):
        dd.polygon([(4, 29), (6, 14), (10, 10), (14, 12), (16, 29)], fill=(255, 255, 255, 255))
    lit(im, mask(W, H, _m), ROBE, 9, 18, 8, 12)
    # hood over the head
    def _h(dd):
        dd.ellipse((6, 2, 15, 12), fill=(255, 255, 255, 255))
    lit(im, mask(W, H, _h), ROBE_LIGHT, 10, 6, 4, 4)
    # face shadow inside the hood: two calm eyes
    d.ellipse((8, 5, 13, 10), fill=(20, 12, 28, 255))
    d.point((9, 7), fill=(230, 200, 255, 255))
    d.point((12, 7), fill=(230, 200, 255, 255))
    # hood rim catches light
    for x in range(7, 14):
        im.putpixel((x, 3), ROBE_LIGHT + (255,))
    im.putpixel((6, 4), _c(ROBE_LIGHT, 0.8) + (255,))
    im.putpixel((14, 4), _c(ROBE_LIGHT, 0.7) + (255,))
    # the eclipse sigil on the chest
    d.ellipse((9, 15, 13, 19), outline=GOLD + (255,))
    im.putpixel((11, 16), GOLD + (255,))
    # belt rope
    d.line((6, 21, 15, 21), fill=WOOD_DARK + (255,))
    # scroll in the hands: pale parchment, slightly unrolled
    d.rectangle((12, 17, 18, 21), fill=PAPER + (255,))
    d.rectangle((12, 17, 18, 18), fill=PAPER_DARK + (255,))
    d.line((13, 19, 17, 19), fill=(*INK, 160))
    d.line((13, 20, 16, 20), fill=(*INK, 120))
    d.rectangle((11, 16, 12, 22), fill=WOOD + (255,))
    d.rectangle((18, 16, 19, 22), fill=WOOD + (255,))
    # feet peek from under the robe
    d.rectangle((6, 28, 8, 29), fill=(*INK, 255))
    d.rectangle((12, 28, 14, 29), fill=(*INK, 255))
    finish(im)
    save(im, "quest_giver")


# ----------------------------------------------------------------- board
def quest_board():
    """A notice board on two posts: pinned orders, one glowing rune page."""
    W, H = 28, 30
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # posts
    d.rectangle((4, 12, 6, 29), fill=WOOD_DARK + (255,))
    d.rectangle((21, 12, 23, 29), fill=WOOD_DARK + (255,))
    d.rectangle((4, 12, 6, 13), fill=WOOD + (255,))
    d.rectangle((21, 12, 23, 13), fill=WOOD + (255,))
    # board with a timber frame
    d.rectangle((1, 3, 26, 14), fill=TIMBER + (255,))
    d.rectangle((2, 4, 25, 13), fill=WOOD + (255,))
    # wood grain
    for y in (6, 9, 12):
        d.line((3, y, 24, y), fill=_c(WOOD, 0.85) + (255,))
    # pinned papers, slightly rotated by hand-placed pixels
    d.rectangle((4, 5, 9, 11), fill=PAPER + (255,))
    d.line((5, 7, 8, 7), fill=(*INK, 150))
    d.line((5, 9, 8, 9), fill=(*INK, 110))
    d.rectangle((11, 6, 16, 12), fill=PAPER_DARK + (255,))
    d.line((12, 8, 15, 8), fill=(*INK, 130))
    d.line((12, 10, 15, 10), fill=(*INK, 100))
    # the guild's rune page: violet glow
    d.rectangle((18, 5, 23, 11), fill=(66, 44, 104, 255))
    d.ellipse((19, 6, 22, 9), outline=(190, 150, 255, 255))
    im.putpixel((20, 8), (230, 200, 255, 255))
    # nails
    for x, y in ((2, 4), (25, 4), (2, 13), (25, 13)):
        im.putpixel((x, y), (200, 200, 210, 255))
    finish(im)
    save(im, "quest_board")


# ----------------------------------------------------------------- stairs
def return_stairs():
    """Stone steps up into the light, for leaving a dungeon floor."""
    W, H = 16, 18
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # three steps rising to the right-top, each with a lit tread
    steps = [(1, 13, 8), (3, 10, 11), (5, 7, 14)]
    for sx, sy, ex in steps:
        d.rectangle((sx, sy + 2, ex, 16), fill=STONE_DARK + (255,))
        d.rectangle((sx, sy, ex, sy + 2), fill=STONE + (255,))
        d.line((sx, sy, ex, sy), fill=(168, 162, 156, 255))
    # warm daylight at the top
    d.ellipse((4, 1, 13, 6), fill=(255, 224, 160, 90))
    d.ellipse((6, 2, 11, 5), fill=(255, 240, 200, 140))
    # side stones
    d.rectangle((0, 15, 15, 17), fill=(70, 64, 60, 255))
    for x in (0, 5, 10, 15):
        im.putpixel((x, 16), (56, 50, 46, 255))
    # glow overlay for the light2d to pick up
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((3, 0, 14, 7), fill=(255, 214, 140, 60))
    im.alpha_composite(glow)
    finish(im)
    save(im, "return_stairs")


if __name__ == "__main__":
    quest_giver()
    quest_board()
    return_stairs()

"""New parallax backgrounds for the two deep biomes (floor 16+).
Three 320x180 layers per biome, horizontally tileable (mirrored at 640x360
by the engine, so only the horizontal seam must close).
Run from tools/:  py -3 gen_deep_backgrounds.py
"""
import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import gen_placeholders as gp
from PIL import Image, ImageDraw, ImageFilter

A = gp.A
OUT = "sprites/backgrounds/"
W, H = 320, 180


def save(im, name):
    im.save(os.path.join(A, OUT + name + ".png"))
    print("wrote", name)


def _vgrad(draw, top, bottom, y0=0, y1=H):
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line((0, y, W, y), fill=c + (255,))


def _wrapped(fn):
    """Draws fn(dx) three times so silhouettes close the seam."""
    for dx in (-W, 0, W):
        fn(dx)


def _px(im, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        im.putpixel((x, y), c)


# ================================================================== ASHEN
def ashen_far():
    """Burning sky: maroon to ember gradient, dim eclipse, fire glow on the
    horizon, drifting ash."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    _vgrad(d, (30, 12, 18), (86, 34, 20))
    # the dim eclipse behind the haze
    d.ellipse((132, 18, 188, 74), fill=(54, 22, 26, 255))
    d.ellipse((140, 26, 180, 66), fill=(66, 28, 30, 255))
    d.ellipse((150, 36, 170, 56), fill=(96, 42, 32, 255))
    # horizon fires: soft glow spots (kept off the seam)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for cx, r in ((48, 26), (120, 18), (230, 30), (285, 16)):
        for i in range(3, 0, -1):
            gd.ellipse((cx - r * i // 3, 150 - r * i // 3, cx + r * i // 3, 150 + r * i // 3),
                       fill=(255, 120 + 30 * i, 50, 26))
    glow = glow.filter(ImageFilter.GaussianBlur(6))
    im.alpha_composite(glow)
    # ash veil: sparse drifting specks
    for i in range(90):
        x = (i * 73) % W
        y = (i * 37) % H
        im.putpixel((x, y), (220, 180, 150, 26))
    save(im, "ashen_halls_far")


def ashen_mid():
    """A ruined cathedral skyline: broken towers, arches, ember windows."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = (24, 12, 16, 255)
    col2 = (34, 17, 20, 255)

    def tower(dx, x, w, top, broken=False):
        pts = [(x + dx, 180), (x + dx, top), (x + dx + w, top), (x + dx + w, 180)]
        if broken:
            pts = [(x + dx, 180), (x + dx, top + 6), (x + dx + w * 0.3, top),
                   (x + dx + w * 0.55, top + 8), (x + dx + w, top + 3), (x + dx + w, 180)]
        d.polygon(pts, fill=col)

    def spire(dx, x, w, base):
        d.polygon([(x + dx, base), (x + dx + w / 2, base - 34), (x + dx + w, base)], fill=col)

    def _draw(dx):
        tower(dx, 8, 26, 92, broken=True)
        spire(dx, 40, 18, 120)
        spire(dx, 40, 18, 120)
        tower(dx, 62, 20, 78)
        tower(dx, 96, 30, 104, broken=True)
        spire(dx, 132, 22, 88)
        tower(dx, 158, 24, 70)
        tower(dx, 190, 34, 96, broken=True)
        spire(dx, 232, 20, 116)
        tower(dx, 258, 22, 84)
        # an arch bridge between two towers
        d.polygon([(88 + dx, 110), (96 + dx, 110), (96 + dx, 122), (88 + dx, 122)], fill=col)
        d.polygon([(126 + dx, 96), (134 + dx, 96), (134 + dx, 108), (126 + dx, 108)], fill=col)
        # ember windows
        for wx, wy in ((18, 104), (30, 118), (70, 92), (104, 116), (166, 84), (200, 110),
                       (214, 122), (266, 98)):
            d.rectangle((wx + dx, wy, wx + dx + 2, wy + 4), fill=(255, 140, 60, 200))
            _px(im, wx + dx + 1, wy - 1, (255, 190, 110, 180))
        # ground haze line
        for x in range(W):
            im.putpixel((x, 176 + (x * 7) % 3), col2)
    _wrapped(_draw)
    save(im, "ashen_halls_mid")


def ashen_near():
    """Close ruins: broken columns and arches, darker, cracks with embers."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = (14, 7, 10, 255)

    def column(dx, x, top):
        d.rectangle((x + dx, top, x + dx + 8, 180), fill=col)
        d.rectangle((x + dx - 2, top, x + dx + 10, top + 4), fill=col)
        d.rectangle((x + dx - 2, 172, x + dx + 10, 180), fill=col)

    def arch(dx, x):
        d.arc((x + dx, 96, x + dx + 64, 160), 180, 360, fill=col, width=9)

    def _draw(dx):
        column(dx, 20, 60)
        column(dx, 88, 88)
        column(dx, 150, 52)
        column(dx, 236, 76)
        arch(dx, 160)
        arch(dx, -8)
        # ember cracks at the base
        for cx, cy in ((36, 168), (110, 174), (196, 170), (268, 176)):
            d.line((cx + dx, cy, cx + dx + 10, cy + 2), fill=(255, 120, 40, 160))
            _px(im, cx + dx + 5, cy + 1, (255, 200, 120, 200))
    _wrapped(_draw)
    save(im, "ashen_halls_near")


# ================================================================ CRYSTAL
def crystal_far():
    """Aurora over the deep: blue-teal gradient, light bands, far spires."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    _vgrad(d, (8, 14, 34), (20, 46, 66))
    # aurora ribbons: soft sine bands
    bands = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bands)
    for k, (col, amp, y0, ph) in enumerate([
            ((70, 220, 190), 14, 44, 0.0), ((110, 140, 240), 20, 66, 1.8), ((70, 200, 230), 10, 30, 3.1)]):
        pts = []
        for x in range(0, W + 1, 8):
            pts.append((x, y0 + amp * math.sin(x * 0.03 + ph)))
        for i in range(len(pts) - 1):
            bd.line((pts[i], pts[i + 1]), fill=col + (46,), width=6 + 3 * (i % 2))
    bands = bands.filter(ImageFilter.GaussianBlur(4))
    im.alpha_composite(bands)
    # dim giant spires on the horizon (tileable)
    col = (13, 26, 40, 255)

    def _draw(dx):
        for x, w, top in ((30, 26, 96), (88, 18, 74), (150, 30, 104), (216, 20, 84), (272, 24, 92)):
            d.polygon([(x + dx, 180), (x + dx + w // 2, top), (x + dx + w, 180)], fill=col)
    _wrapped(_draw)
    # star sparkles
    for i in range(40):
        x = (i * 89 + 13) % W
        y = (i * 53) % 90
        im.putpixel((x, y), (190, 230, 255, 120))
    save(im, "crystal_depths_far")


def crystal_mid():
    """Crystal clusters on the cavern floor, glowing cores."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    dark = (16, 34, 52)
    lit = (60, 170, 200)
    pale = (150, 230, 245)

    def cluster(dx, x, h, w):
        d.polygon([(x + dx, 180), (x + dx + w // 2, 180 - h), (x + dx + w, 180)], fill=dark)
        d.line((x + dx + w // 2, 180 - h, x + dx + w // 2, 180), fill=(*lit, 150))
        d.polygon([(x + dx + w // 2, 180 - h), (x + dx + w // 2 + 2, 180 - h + 6),
                   (x + dx + w // 2, 180 - h + 10)], fill=(*pale, 170))

    def _draw(dx):
        cluster(dx, 12, 62, 30)
        cluster(dx, 58, 40, 20)
        cluster(dx, 96, 74, 34)
        cluster(dx, 150, 48, 22)
        cluster(dx, 196, 80, 36)
        cluster(dx, 252, 56, 26)
        # under-glow at the base of each cluster
        for x, h, w in ((12, 62, 30), (96, 74, 34), (196, 80, 36), (252, 56, 26)):
            d.ellipse((x + dx - 6, 168, x + dx + w + 6, 184), fill=(40, 120, 150, 60))
    _wrapped(_draw)
    save(im, "crystal_depths_mid")


def crystal_near():
    """Near rock columns with bright ice-crystal spikes."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rock = (9, 20, 32)
    ice = (120, 220, 240)

    def column(dx, x, w, top):
        d.polygon([(x + dx, 180), (x + dx + w * 0.2, top), (x + dx + w * 0.8, top + 8),
                   (x + dx + w, 180)], fill=rock)

    def spike(dx, x, h):
        d.polygon([(x + dx, 180), (x + dx + 3, 180 - h), (x + dx + 6, 180)], fill=(*ice, 190))
        d.line((x + dx + 3, 180 - h, x + dx + 3, 180), fill=(210, 245, 255, 160))

    def _draw(dx):
        column(dx, 6, 34, 66)
        column(dx, 120, 40, 44)
        column(dx, 236, 30, 78)
        for x, h in ((46, 38), (104, 26), (176, 44), (214, 30), (292, 36), (70, 22)):
            spike(dx, x, h)
    _wrapped(_draw)
    save(im, "crystal_depths_near")


if __name__ == "__main__":
    ashen_far()
    ashen_mid()
    ashen_near()
    crystal_far()
    crystal_mid()
    crystal_near()

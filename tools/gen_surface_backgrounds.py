#!/usr/bin/env python3
"""Backgrounds of the open surface, one set per surface biome (320x180,
drawn at x2 by the game's parallax):

  surface_<b>_far.png     the sky: a rich gradient, a warm horizon, the sun
                          with its halo (no clouds: they drift, see below)
  surface_<b>_clouds.png  cumulus with a lit top, a cool shaded belly and
                          dithered edges, tileable in x (the game scrolls it
                          slowly over the sky)
  surface_<b>_mid.png     the far land: hills / forest / peaks tinted toward
                          the sky (aerial perspective), but keeping colour
  surface_<b>_near.png    the near land: saturated, lit from the top left,
                          trees and rocks with a lit side and a dark side
  surface_<b>_front.png   a rare dark branch hanging over the top of the
                          screen (the game slides it faster than the world)
  surface_<b>_*_sway.png  white where the mid / near layer is foliage: only
                          those pixels sway in the wind (parallax_life shader)

Everything tiles horizontally (the game mirrors the layers every 640 px).
The game sways the tree tops of mid/near a pixel in the wind (shader).
Run from the project root:  python3 tools/gen_surface_backgrounds.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

BACK = "assets/sprites/backgrounds"
W, H = 320, 180

# sky top, sky horizon, sun glow, far land, near land, accent (flowers /
# snow / ivy), kind
BIOMES = {
    "forest":    ((64, 128, 214), (196, 228, 244), (255, 238, 196), (96, 150, 140), (52, 118, 60), (240, 214, 90), "forest"),
    "hills":     ((72, 140, 226), (214, 236, 236), (255, 236, 190), (120, 170, 128), (92, 156, 64), (250, 236, 120), "hills"),
    "swamp":     ((66, 142, 168), (212, 234, 196), (252, 240, 184), (86, 136, 104), (60, 112, 62), (170, 210, 120), "swamp"),
    "ruins":     ((92, 132, 210), (232, 220, 206), (255, 226, 186), (132, 140, 160), (96, 132, 82), (120, 170, 90), "ruins"),
    "mountains": ((56, 110, 200), (206, 226, 246), (255, 244, 222), (120, 140, 176), (82, 112, 110), (246, 250, 255), "peaks"),
    "wasteland": ((150, 112, 132), (246, 196, 140), (255, 214, 150), (176, 120, 96), (150, 92, 64), (230, 170, 90), "mesas"),
}
# The town (town_far / _clouds / _mid / _near): a day sky with the Eclipse
# for its sun, fields and a windmill far away, the roofs of the outer town.
TOWN = ((70, 118, 200), (230, 220, 210), (255, 226, 190), (118, 160, 120), (88, 140, 72), (240, 214, 90), "town")


def clamp(v) -> int:
    return max(0, min(255, int(v)))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


def mul(c, k):
    return tuple(clamp(v * k) for v in c[:3])


def rgba(c, a=255):
    return (clamp(c[0]), clamp(c[1]), clamp(c[2]), a)


def wave(rnd, terms):
    """A tileable 1-D profile: a sum of sines with whole periods over W."""
    parts = [(rnd.choice(periods), rnd.uniform(0, math.tau), amp) for periods, amp in terms]

    def f(x):
        return sum(a * math.sin(x / W * math.tau * p + ph) for p, ph, a in parts)
    return f


# ---------------------------------------------------------------- the sky
def sky(name, top, horizon, glow, rnd, eclipse=False):
    im = Image.new("RGBA", (W, H))
    px = im.load()
    sun = (rnd.randint(70, 250), rnd.randint(34, 54))
    for y in range(H):
        t = (y / (H - 1)) ** 0.85
        base = mix(top, horizon, t)
        for x in range(W):
            dx = min(abs(x - sun[0]), W - abs(x - sun[0]))  # tiles in x
            dist = math.hypot(dx, (y - sun[1]) * 1.3)
            g = max(0.0, 1.0 - dist / 110.0) ** 2.2 * 0.55
            c = mix(base, glow, g)
            # a faint dithered band of warmth along the horizon
            if y > H * 0.62 and (x + y) % 2 == 0:
                c = mix(c, glow, 0.06)
            px[x, y] = rgba(c)
    if eclipse:
        # the Eclipse over the town: a dark disc in a bright corona with rays
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        lp = layer.load()
        for y in range(max(0, sun[1] - 30), min(H, sun[1] + 31)):
            for x in range(sun[0] - 30, sun[0] + 31):
                dx, dy = x - sun[0], y - sun[1]
                r = math.hypot(dx, dy)
                a = math.atan2(dy, dx)
                ray = 0.5 + 0.5 * math.cos(a * 9 + 0.6) * math.cos(a * 4)
                corona = max(0.0, 1.0 - (r - 7) / (10 + 14 * ray)) if r >= 7 else 0.0
                if r < 7.5:
                    lp[x % W, y] = rgba((40, 30, 52), 255)
                elif corona > 0:
                    c = mix(glow, (255, 252, 240), min(1.0, corona * 1.4))
                    lp[x % W, y] = rgba(c, int(255 * min(1.0, corona ** 1.3)))
                if 7 <= r < 8.4:
                    lp[x % W, y] = rgba((255, 248, 226), 255)  # the burning rim
        im.alpha_composite(layer)
        return im
    # the sun: a soft disc in three rings, blended over the sky (an RGBA
    # ellipse straight on the sky would punch see-through holes)
    for r, k in ((11, 0.25), (8, 0.55), (6, 1.0)):
        disc = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        col = mix(glow, (255, 252, 236), k)
        ImageDraw.Draw(disc).ellipse((sun[0] - r, sun[1] - r, sun[0] + r, sun[1] + r), fill=rgba(col, int(255 * (0.35 + 0.65 * k))))
        im.alpha_composite(disc)
    return im


def cumulus(d, px, cx, cy, size, light, shade, rnd):
    """One cloud: puffs on a flat base, lit top-left, cool belly."""
    puffs = []
    n = rnd.randint(4, 7)
    for k in range(n):
        r = rnd.uniform(size * 0.45, size) * (1.0 - abs(k - n / 2) / n * 0.6)
        puffs.append((cx + (k - n / 2) * size * 0.75 + rnd.uniform(-2, 2), cy - r * 0.35, r))
    base = cy + size * 0.35
    pts = list(range(int(cx - n * size * 0.5 - size), int(cx + n * size * 0.5 + size)))
    for y in range(int(cy - size * 1.6), int(base) + 1):
        for x in pts:
            inside = False
            nx = ny = 0.0
            for (qx, qy, r) in puffs:
                dx, dy = x - qx, (y - qy) * 1.25
                dd = dx * dx + dy * dy
                if dd <= r * r:
                    inside = True
                    nx, ny = dx / r, dy / r
                    break
            if not inside:
                continue
            xx = x % W
            if not (0 <= y < H):
                continue
            lightness = 0.5 - 0.45 * ny - 0.25 * nx  # top-left lit
            v = (y - (cy - size)) / (base - (cy - size) + 1e-6)
            lightness -= 0.35 * v  # darker belly
            if lightness > 0.45:
                c, a = light, 240
            elif lightness > 0.15:
                c, a = mix(light, shade, 0.35), 236
            elif lightness > -0.1:
                c, a = mix(light, shade, 0.7), 232
            else:
                c, a = shade, 228
            # dithered borders between tones
            if 0.4 < lightness < 0.5 and (xx + y) % 2:
                c = mix(light, shade, 0.35)
            # soft ragged rim
            edge = (nx * nx + ny * ny)
            if edge > 0.86:
                a = 150 if (xx + y) % 2 else 90
            px[xx, y] = rgba(c, a)


def clouds(name, glow, rnd, sunset=False):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    d = ImageDraw.Draw(im)
    light = mix((255, 255, 255), glow, 0.25)
    shade = (176, 190, 216) if not sunset else (190, 150, 160)
    for k in range(6):
        far = k < 2
        size = rnd.uniform(8, 11) if far else rnd.uniform(12, 18)
        cy = rnd.uniform(20, 46) if far else rnd.uniform(40, 84)
        cumulus(d, px, rnd.uniform(0, W), cy, size, light if not far else mix(light, (210, 225, 245), 0.3),
                shade if not far else mix(shade, (200, 214, 236), 0.4), rnd)
    # a few thin streaks high up
    for k in range(4):
        y = rnd.randint(8, 30)
        x0 = rnd.randint(0, W)
        ln = rnd.randint(30, 70)
        for x in range(x0, x0 + ln):
            if (x * 7 + y) % 5:
                a = int(110 * math.sin(math.pi * (x - x0) / ln))
                px[x % W, y] = rgba(light, max(px[x % W, y][3], a))
    return im


# ------------------------------------------------------------ the land
def land(name, color, sky_col, accent, kind, layer, rnd):
    """The far (mid) or near land of a biome."""
    M = 40  # margin: shapes crossing the seam are folded onto the other side
    im = Image.new("RGBA", (W + 2 * M, H), (0, 0, 0, 0))
    px = im.load()
    d0 = ImageDraw.Draw(im)
    mk = Image.new("RGBA", (W + 2 * M, H), (0, 0, 0, 0))  # what sways in the wind
    dm = ImageDraw.Draw(mk)
    sway = [False]

    class Shifted:
        """ImageDraw that draws at x + M (and, for foliage, into the mask)."""
        def __getattr__(self, name):
            fn = getattr(d0, name)
            fm = getattr(dm, name)

            def call(xy, *a, **k):
                if isinstance(xy, (list, tuple)) and xy and isinstance(xy[0], (list, tuple)):
                    xy = [(p[0] + M, p[1]) for p in xy]
                else:
                    xy = [v + M if i % 2 == 0 else v for i, v in enumerate(xy)]
                if sway[0]:
                    k2 = dict(k)
                    k2["fill"] = (255, 255, 255, 255)
                    fm(xy, *a, **k2)
                return fn(xy, *a, **k)
            return call
    d = Shifted()
    near = layer == "near"
    base = 132 if near else 108
    amp = (10, 5) if kind != "peaks" else ((8, 4) if near else (26, 12))
    prof = wave(rnd, [((1, 2), amp[0]), ((3, 4, 5), amp[1]), ((9, 11), 1.5)])
    crest = [int(base + prof(x)) for x in range(W)]
    col = color
    # body: lit crest, gentle gradient, dithered tone steps, a few strata
    for x in range(W):
        y0 = crest[x]
        slope = crest[(x + 1) % W] - crest[x - 1]
        for y in range(max(0, y0), H):
            t = (y - y0) / max(1, H - y0)
            k = 1.06 - 0.28 * t
            if (x + y) % 2 and 0.3 < t < 0.36:
                k -= 0.04
            c = mul(col, k)
            if kind == "mesas" and (y - y0) % 9 in (0, 1):
                c = mul(c, 0.9 if (y - y0) % 9 == 0 else 1.08)
            if kind == "town" and not near and ((x // 23 + (y - y0) // 7) % 3 == 0):
                c = mix(c, (200, 186, 110), 0.28)  # fields of wheat between the meadows
            px[x + M, y] = rgba(c)
        for dy in range(2):
            if 0 <= y0 + dy < H:
                px[x + M, y0 + dy] = rgba(mul(col, 1.22 - 0.1 * dy))
    lit = mul(col, 1.22)
    dark = mul(col, 0.74)
    flat = col

    def canopy(x, y, r):
        """A round deciduous crown: lit top-left puffs over a dark body."""
        sway[0] = True
        d.ellipse((x - r, y - r, x + r, y + r * 0.8), fill=rgba(dark))
        for k in range(4):
            a = math.pi * (1.1 + k * 0.28)
            cx, cy = x + math.cos(a) * r * 0.45, y + math.sin(a) * r * 0.45
            rr = r * 0.62
            d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr * 0.85), fill=rgba(flat))
        d.ellipse((x - r * 0.75, y - r * 0.85, x - r * 0.05, y - r * 0.2), fill=rgba(lit))
        if near:
            for _ in range(int(r)):
                qx, qy = x + rnd.uniform(-r, r), y + rnd.uniform(-r, r * 0.6)
                if (qx - x) ** 2 + (qy - y) ** 2 < r * r * 0.8:
                    d.point((qx, qy), fill=rgba(mul(col, 1.38 if qy < y else 0.62)))
        sway[0] = False

    def fir(x, y, hh):
        sway[0] = True
        for k in range(4):
            ty = y - hh + k * hh // 5
            hw = 2 + k * (2 if not near else 3)
            d.polygon([(x - hw, ty + hh // 3), (x, ty), (x + hw, ty + hh // 3)], fill=rgba(flat))
            d.polygon([(x, ty), (x + hw, ty + hh // 3), (x + 1, ty + hh // 3)], fill=rgba(dark))
            d.line((x - hw + 1, ty + hh // 3 - 1, x - 1, ty + 1), fill=rgba(lit))
        sway[0] = False
        d.line((x, y - 3, x, y), fill=rgba(mul(dark, 0.8)))

    count = 30 if near else 22
    xs = sorted(rnd.uniform(0, W) for _ in range(count))
    for x in xs:
        xi = int(x) % W
        y = crest[xi] + 2
        if kind == "forest":
            if rnd.random() < 0.55:
                canopy(xi, y - (9 if near else 6), rnd.uniform(6, 11) if near else rnd.uniform(4, 7))
                d.line((xi, y - 4, xi, y), fill=rgba(mul((90, 64, 40), 0.9 if near else 0.7)))
            else:
                fir(xi, y, rnd.randint(22, 40) if near else rnd.randint(14, 24))
        elif kind == "hills":
            if rnd.random() < 0.35:
                canopy(xi, y - (8 if near else 5), rnd.uniform(5, 8) if near else rnd.uniform(3, 5))
                d.line((xi, y - 3, xi, y), fill=rgba(dark))
            elif near and rnd.random() < 0.5:  # a hedge of bushes
                sway[0] = True
                for k in range(3):
                    d.ellipse((xi + k * 6 - 7, y - 6, xi + k * 6 + 1, y + 2), fill=rgba(flat))
                    d.ellipse((xi + k * 6 - 6, y - 6, xi + k * 6 - 2, y - 2), fill=rgba(lit))
                sway[0] = False
        elif kind == "swamp":
            # willows: a lit crown and drooping strands
            r = rnd.uniform(7, 12) if near else rnd.uniform(5, 8)
            d.line((xi, y - r, xi, y), fill=rgba(mul(dark, 0.9)), width=2 if near else 1)
            sway[0] = True
            d.ellipse((xi - r, y - r * 2.2, xi + r, y - r * 0.8), fill=rgba(flat))
            d.ellipse((xi - r * 0.8, y - r * 2.2, xi + r * 0.1, y - r * 1.4), fill=rgba(lit))
            for k in range(-int(r) + 1, int(r), 2):
                ln = rnd.randint(int(r * 0.6), int(r * 1.2))
                d.line((xi + k, y - r * 1.2, xi + k, y - r * 1.2 + ln), fill=rgba(mul(flat, 0.86 + 0.1 * (k % 3))))
            sway[0] = False
        elif kind == "ruins":
            if rnd.random() < 0.45:
                hh = rnd.randint(16, 40) if near else rnd.randint(10, 24)
                wdt = rnd.randint(4, 7)
                stone = mix((170, 166, 158), col, 0.35)
                d.rectangle((xi - wdt, y - hh, xi + wdt, y), fill=rgba(stone))
                d.rectangle((xi - wdt, y - hh, xi - wdt + 2, y), fill=rgba(mul(stone, 1.18)))
                d.rectangle((xi + wdt - 2, y - hh, xi + wdt, y), fill=rgba(mul(stone, 0.78)))
                for yy in range(y - hh + 3, y, 4):
                    d.line((xi - wdt, yy, xi + wdt, yy), fill=rgba(mul(stone, 0.86)))
                for k in range(rnd.randint(1, 3)):
                    d.rectangle((xi - wdt + k * 4, y - hh - rnd.randint(2, 5), xi - wdt + 2 + k * 4, y - hh), fill=rgba(stone))
                if near:  # ivy
                    for k in range(rnd.randint(4, 9)):
                        d.point((xi - wdt + rnd.randint(0, wdt * 2), y - rnd.randint(0, hh)), fill=rgba(accent))
            else:
                canopy(xi, y - (7 if near else 4), rnd.uniform(4, 7) if near else rnd.uniform(3, 5))
        elif kind == "peaks":
            if not near:
                hh = rnd.randint(30, 64)
                d.polygon([(xi - hh, y + 4), (xi, y - hh), (xi + hh, y + 4)], fill=rgba(flat))
                d.polygon([(xi, y - hh), (xi + hh, y + 4), (xi + hh // 4, y + 4)], fill=rgba(dark))
                d.polygon([(xi - hh // 3, y - hh * 2 // 3), (xi, y - hh), (xi + hh // 3, y - hh * 2 // 3),
                           (xi + hh // 6, y - hh * 2 // 3 + 3), (xi, y - hh * 2 // 3 - 1), (xi - hh // 6, y - hh * 2 // 3 + 4)],
                          fill=rgba(accent))
                d.polygon([(xi, y - hh), (xi + hh // 3, y - hh * 2 // 3), (xi + hh // 6, y - hh * 2 // 3 + 3)],
                          fill=rgba(mix(accent, (170, 190, 220), 0.5)))
            else:
                fir(xi, y, rnd.randint(18, 34))
        elif kind == "town":
            if near and rnd.random() < 0.62:
                # a house of the outer town: a wall, a pitched roof, a chimney, windows
                hw = rnd.randint(7, 12)
                hh = rnd.randint(10, 18)
                wall = mix((206, 190, 160), col, 0.25)
                roof = rnd.choice([(150, 66, 50), (120, 86, 60), (96, 92, 110)])
                d.rectangle((xi - hw, y - hh, xi + hw, y + 2), fill=rgba(wall))
                d.rectangle((xi - hw, y - hh, xi - hw + 1, y + 2), fill=rgba(mul(wall, 1.12)))
                d.rectangle((xi + hw - 1, y - hh, xi + hw, y + 2), fill=rgba(mul(wall, 0.8)))
                peak = y - hh - hw + 2
                d.polygon([(xi - hw - 2, y - hh), (xi, peak), (xi + hw + 2, y - hh)], fill=rgba(roof))
                d.polygon([(xi, peak), (xi + hw + 2, y - hh), (xi + 1, y - hh)], fill=rgba(mul(roof, 0.76)))
                d.line((xi - hw - 2, y - hh, xi, peak), fill=rgba(mul(roof, 1.3)))
                cx = xi + hw // 2
                d.rectangle((cx, peak + 3, cx + 2, y - hh - 2), fill=rgba(mul(wall, 0.7)))
                for k in range(-1, 2, 2):
                    wx = xi + k * hw // 2
                    d.rectangle((wx - 1, y - hh + 4, wx + 1, y - hh + 7), fill=rgba((250, 210, 120)))
                    d.point((wx, y - hh + 4), fill=rgba((255, 240, 190)))
                d.rectangle((xi - 1, y - 5, xi + 1, y + 2), fill=rgba((90, 62, 40)))
            elif near:
                canopy(xi, y - 8, rnd.uniform(5, 8))
                d.line((xi, y - 3, xi, y), fill=rgba(mul((90, 64, 40), 0.9)))
            else:
                r = rnd.random()
                if r < 0.12:  # a windmill on a hill
                    d.polygon([(xi - 3, y), (xi - 2, y - 14), (xi + 2, y - 14), (xi + 3, y)], fill=rgba(mul(flat, 1.1)))
                    d.polygon([(xi - 3, y - 14), (xi, y - 18), (xi + 3, y - 14)], fill=rgba(mul(dark, 0.9)))
                    for a in range(4):
                        ang = a * math.pi / 2 + 0.4
                        d.line((xi, y - 15, xi + math.cos(ang) * 9, y - 15 + math.sin(ang) * 9), fill=rgba(mul(lit, 1.1)))
                elif r < 0.2:  # the old castle on the far hill
                    d.rectangle((xi - 4, y - 22, xi + 4, y), fill=rgba(mul(flat, 1.05)))
                    d.rectangle((xi + 4, y - 12, xi + 12, y), fill=rgba(mul(flat, 0.95)))
                    for k in range(3):
                        d.rectangle((xi - 4 + k * 3, y - 24, xi - 3 + k * 3, y - 22), fill=rgba(mul(flat, 1.05)))
                    d.polygon([(xi - 5, y - 22), (xi, y - 30), (xi + 5, y - 22)], fill=rgba(mul(dark, 0.95)))
                else:
                    canopy(xi, y - 4, rnd.uniform(3, 5))
        else:  # mesas and spires of the wasteland
            if rnd.random() < 0.5:
                hh = rnd.randint(16, 44) if near else rnd.randint(12, 30)
                d.polygon([(xi - 6, y), (xi - 2, y - hh), (xi + 2, y - hh + 3), (xi + 6, y)], fill=rgba(flat))
                d.polygon([(xi + 1, y - hh + 2), (xi + 2, y - hh + 3), (xi + 6, y), (xi + 2, y)], fill=rgba(dark))
                d.line((xi - 2, y - hh, xi - 6, y), fill=rgba(lit))
                for yy in range(y - hh + 4, y, 5):
                    d.line((xi - 5, yy, xi + 5, yy), fill=rgba(mul(flat, 0.88)))
            elif near:
                # a dead bush
                for k in range(4):
                    a = math.pi * (1.2 + k * 0.2)
                    d.line((xi, y, xi + math.cos(a) * 7, y + math.sin(a) * 7), fill=rgba(mul(dark, 0.8)))
    # aerial perspective of the far land: toward the sky's horizon colour
    def fold(src):
        o = src.crop((M, 0, W + M, H))
        o.alpha_composite(src.crop((0, 0, M, H)), (W - M, 0))      # spilled left -> right edge
        o.alpha_composite(src.crop((W + M, 0, W + 2 * M, H)), (0, 0))  # spilled right -> left edge
        return o
    out = fold(im)
    mask = fold(mk)
    if not near:
        px = out.load()
        for y in range(H):
            for x in range(W):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = rgba(mix((r, g, b), sky_col, 0.38), a)
    return out, mask


def build(name, spec, seed):
    top, horizon, glow, far, near, accent, kind = spec
    rnd = random.Random(seed)
    os.makedirs(BACK, exist_ok=True)
    pre = "town" if kind == "town" else f"surface_{name}"
    sky(name, top, horizon, glow, rnd, eclipse=kind == "town").save(os.path.join(BACK, f"{pre}_far.png"))
    clouds(name, glow, rnd, kind == "mesas").save(os.path.join(BACK, f"{pre}_clouds.png"))
    if kind != "town":
        front(name, near, kind, rnd).save(os.path.join(BACK, f"{pre}_front.png"))
    for layer, col in (("mid", far), ("near", near)):
        im, mask = land(name, col, horizon, accent, kind, layer, rnd)
        im.save(os.path.join(BACK, f"{pre}_{layer}.png"))
        mask.save(os.path.join(BACK, f"{pre}_{layer}_sway.png"))


def front(name, near, kind, rnd):
    """A foreground over the scene (the game slides it faster than the world):
    rare dark, soft-edged branches hanging from the top of the screen. Only
    the top 34 px of the 180 are used, one cluster per tile width."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    dark = mul(near, 0.42) if kind != "mesas" else mul(near, 0.5)
    x0 = rnd.randint(40, 260)
    leaves = []
    # a bough coming in from the top, with leaves (or twigs) along it
    pts = [(x0 + int(t * 46 + math.sin(t * 5) * 4), int(-2 + t * 26 - t * t * 10)) for t in [i / 20 for i in range(21)]]
    for (x, y) in pts:
        for dy in range(-1, 2):
            if 0 <= y + dy < H:
                px[x % W, y + dy] = rgba(mul(dark, 0.8), 240)
    for i, (x, y) in enumerate(pts[2:], 2):
        if i % 2 == 0:
            leaves.append((x + rnd.randint(-3, 3), y + rnd.randint(1, 7)))
    for (lx, ly) in leaves:
        if kind == "mesas":
            for k in range(4):
                xx, yy = lx + k, ly + k // 2
                if 0 <= yy < H:
                    px[xx % W, yy] = rgba(dark, 220)
            continue
        r = rnd.uniform(3.5, 6.5)
        for yy in range(int(ly - r), int(ly + r) + 1):
            for xx in range(int(lx - r), int(lx + r) + 1):
                dd = math.hypot(xx - lx, (yy - ly) * 1.2) / r
                if dd <= 1.0 and 0 <= yy < 34:
                    a = 230 if dd < 0.7 else (150 if (xx + yy) % 2 else 80)  # soft, out-of-focus rim
                    c = mul(dark, 1.15 if yy < ly - r * 0.3 else 1.0)
                    old = px[xx % W, yy]
                    if a > old[3]:
                        px[xx % W, yy] = rgba(c, a)
    return im


def stars():
    """The night sky, shared by every biome (shown by the parallax_life
    shader with the night): stars of three sizes, a faint milky band."""
    rnd = random.Random(99)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    for x in range(W):  # the milky way: a faint diagonal band of dust
        for y in range(H):
            band = abs((y - 30) - (x - 160) * 0.35)
            if band < 18 and rnd.random() < 0.25 * (1 - band / 18):
                px[x, y] = (200, 205, 235, rnd.randint(30, 70))
    for _ in range(170):
        x, y = rnd.randrange(W), rnd.randrange(int(H * 0.75))
        px[x, y] = (255, 255, 255, rnd.randint(120, 255)) if rnd.random() < 0.8 else (255, 230, 190, 230)
    for _ in range(12):  # bright ones with a cross
        x, y = rnd.randrange(2, W - 2), rnd.randrange(2, int(H * 0.6))
        px[x, y] = (255, 255, 255, 255)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px[x + dx, y + dy] = (200, 215, 255, 140)
    im.save(os.path.join(BACK, "surface_stars.png"))


def main():
    stars()
    for i, (name, spec) in enumerate(BIOMES.items()):
        build(name, spec, 700 + i * 31)
    build("town", TOWN, 1313)
    print("surface backgrounds: ok")


if __name__ == "__main__":
    main()

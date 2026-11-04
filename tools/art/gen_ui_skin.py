#!/usr/bin/env python3
"""The rest of the interface skin, in the palette of the book buttons
(assets/ui/button*.png): parchment, two woods, brass rivets, dark ink.

Writes assets/ui/skin/*.png; tools/art/build_theme.gd puts them into the
theme (assets/ui/theme.tres) for the controls that still had Godot's grey
look: scroll bars, sliders, check boxes and toggles, text fields, spin
boxes, drop-down arrows and their pop-up menus, lists, progress bars,
panels.

  python3 tools/art/gen_ui_skin.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "ui", "skin")

PARCH = (202, 177, 123)
PARCH_LIGHT = (246, 216, 150)
PARCH_DARK = (170, 145, 98)
PARCH_DEEP = (146, 120, 80)
WOOD = (79, 48, 31)
WOOD_DARK = (52, 31, 20)
WOOD_LIGHT = (112, 72, 44)
BRASS = (232, 196, 90)
BRASS_DARK = (160, 120, 50)
BRASS_LIGHT = (255, 238, 160)
INK = (64, 36, 15)


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), tuple(c) + (255,))


def box(im, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(im, x, y, c)


def frame(w, h, fill, border=WOOD, outer=WOOD_DARK, inset=False, rivets=True):
    """A 9-slice box: dark outer line, wood border, fill; inset = sunken."""
    im = img(w, h)
    box(im, 0, 0, w - 1, h - 1, outer)
    box(im, 1, 1, w - 2, h - 2, border)
    box(im, 2, 2, w - 3, h - 3, fill)
    if inset:  # inner shadow on the top and left: the field sits lower
        for x in range(2, w - 2):
            px(im, x, 2, tuple(int(c * 0.82) for c in fill))
        for y in range(2, h - 2):
            px(im, 2, y, tuple(int(c * 0.88) for c in fill))
    else:  # a lit inner edge on the top
        for x in range(2, w - 2):
            px(im, x, 2, tuple(min(255, int(c * 1.06)) for c in fill))
    if rivets:
        for (x, y) in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)):
            px(im, x, y, BRASS)
    return im


def scroll_track(vertical):
    w, h = (6, 16) if vertical else (16, 6)
    im = img(w, h)
    box(im, 0, 0, w - 1, h - 1, WOOD_DARK)
    box(im, 1, 1, w - 2, h - 2, (40, 24, 16))
    return im


def scroll_grab(vertical, fill):
    w, h = (6, 12) if vertical else (12, 6)
    im = img(w, h)
    box(im, 0, 0, w - 1, h - 1, WOOD_DARK)
    box(im, 1, 1, w - 2, h - 2, fill)
    if vertical:
        for x in range(1, w - 1):
            px(im, x, 1, tuple(min(255, int(c * 1.1)) for c in fill))
        for y in (h // 2 - 2, h // 2, h // 2 + 2):  # grip lines
            for x in range(2, w - 2):
                px(im, x, y, WOOD)
    else:
        for x in (w // 2 - 2, w // 2, w // 2 + 2):
            for y in range(2, h - 2):
                px(im, x, y, WOOD)
    return im


def slider_track():
    im = img(16, 6)
    box(im, 0, 1, 15, 4, WOOD_DARK)
    box(im, 1, 2, 14, 3, (40, 24, 16))
    return im


def slider_fill():
    im = img(16, 6)
    box(im, 0, 1, 15, 4, WOOD_DARK)
    box(im, 1, 2, 14, 3, BRASS_DARK)
    for x in range(1, 15):
        px(im, x, 2, BRASS)
    return im


def grabber(light):
    im = img(8, 10)
    body = BRASS_LIGHT if light else BRASS
    box(im, 1, 0, 6, 9, WOOD_DARK)
    box(im, 0, 1, 7, 8, WOOD_DARK)
    box(im, 1, 1, 6, 8, body)
    box(im, 2, 2, 5, 2, BRASS_LIGHT)
    box(im, 1, 7, 6, 8, BRASS_DARK)
    px(im, 3, 4, WOOD)
    px(im, 4, 4, WOOD)
    px(im, 3, 5, WOOD)
    px(im, 4, 5, WOOD)
    return im


def check(on, disabled=False):
    im = img(10, 10)
    box(im, 0, 0, 9, 9, WOOD_DARK)
    box(im, 1, 1, 8, 8, WOOD)
    box(im, 2, 2, 7, 7, PARCH_DEEP if disabled else PARCH_LIGHT)
    for x in range(2, 8):
        px(im, x, 2, PARCH_DARK if not disabled else PARCH_DEEP)
    if on:
        ink = PARCH_DARK if disabled else INK
        for (x, y) in ((2, 5), (3, 6), (4, 7), (5, 6), (6, 5), (7, 4), (7, 3), (3, 5), (4, 6), (5, 5), (6, 4)):
            px(im, x, y, ink)
    return im


def toggle(on):
    im = img(20, 10)
    box(im, 1, 0, 18, 9, WOOD_DARK)
    box(im, 0, 1, 19, 8, WOOD_DARK)
    box(im, 2, 2, 17, 7, (60, 110, 50) if on else (40, 24, 16))
    kx = 11 if on else 2
    box(im, kx, 1, kx + 6, 8, WOOD_DARK)
    box(im, kx + 1, 2, kx + 5, 7, BRASS)
    box(im, kx + 2, 2, kx + 4, 3, BRASS_LIGHT)
    return im


def arrow(down=True, colour=INK):
    im = img(8, 6)
    for i in range(4):
        y = (1 + i) if down else (4 - i)
        for x in range(i, 8 - i):
            px(im, x, y, colour)
    return im


def updown():
    im = img(8, 14)
    up = arrow(False)
    dn = arrow(True)
    im.alpha_composite(up, (0, 0))
    im.alpha_composite(dn, (0, 8))
    return im


def flat(w, h, c):
    im = img(w, h)
    box(im, 0, 0, w - 1, h - 1, c)
    return im


def hover_row():
    im = img(8, 8)
    box(im, 0, 0, 7, 7, PARCH_LIGHT)
    for x in range(8):
        px(im, x, 7, BRASS_DARK)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {
        "panel": frame(16, 16, PARCH),
        "popup": frame(16, 16, PARCH_LIGHT),
        "field": frame(12, 12, PARCH_LIGHT, inset=True, rivets=False),
        "field_focus": frame(12, 12, PARCH_LIGHT, border=BRASS_DARK, inset=True, rivets=False),
        "field_read_only": frame(12, 12, PARCH_DARK, inset=True, rivets=False),
        "scroll_v": scroll_track(True),
        "scroll_h": scroll_track(False),
        "grab_v": scroll_grab(True, PARCH),
        "grab_v_hover": scroll_grab(True, PARCH_LIGHT),
        "grab_v_pressed": scroll_grab(True, PARCH_DARK),
        "grab_h": scroll_grab(False, PARCH),
        "grab_h_hover": scroll_grab(False, PARCH_LIGHT),
        "grab_h_pressed": scroll_grab(False, PARCH_DARK),
        "slider": slider_track(),
        "slider_fill": slider_fill(),
        "grabber": grabber(False),
        "grabber_hover": grabber(True),
        "check_on": check(True),
        "check_off": check(False),
        "check_on_disabled": check(True, True),
        "check_off_disabled": check(False, True),
        "toggle_on": toggle(True),
        "toggle_off": toggle(False),
        "arrow": arrow(),
        "updown": updown(),
        "row_hover": hover_row(),
        "row_selected": flat(8, 8, PARCH_DARK),
        "progress_bg": frame(12, 8, (40, 24, 16), rivets=False),
        "progress_fill": flat(4, 4, BRASS),
    }
    for name, im in files.items():
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("ui skin:", len(files), "textures ->", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()

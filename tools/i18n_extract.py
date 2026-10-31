#!/usr/bin/env python3
"""Collects every Russian line of the game into locale/messages.json:
the string literals of scripts/**.gd (GDScript escapes resolved) and the
data texts dumped by Localizer.collect_data_texts() (a JSON list, argv[1]).
Run from tools/:  python3 i18n_extract.py <data_texts.json>
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CYR = re.compile(r"[А-Яа-яЁё]")
ESC = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "r": "\r"}


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(ESC.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def code_texts():
    import i18n_wrap
    seen = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        for line in open(path, encoding="utf-8"):
            if "# i18n-skip" in line:
                continue
            for a, b in i18n_wrap.literals(line):
                lit = line[a + 1:b - 1]
                if CYR.search(lit) and not line[:a].endswith("&"):
                    seen.setdefault(unescape(lit), os.path.relpath(path, ROOT))
    return seen


def main():
    code = code_texts()
    data = json.load(open(sys.argv[1], encoding="utf-8")) if len(sys.argv) > 1 else []
    msgs = {}
    for k, where in code.items():
        msgs[k] = where
    for k in data:
        msgs.setdefault(k, "data")
    out = os.path.join(ROOT, "locale", "messages.json")
    json.dump(msgs, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
    print("code:", len(code), "data:", len(data), "total:", len(msgs))


if __name__ == "__main__":
    main()

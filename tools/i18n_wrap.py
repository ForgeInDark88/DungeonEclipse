#!/usr/bin/env python3
"""Wraps every Russian string literal in the game scripts for translation:
tr("...") in instance code, TranslationServer.translate("...") in static
functions / static vars. Skips what must stay constant: const blocks,
default parameters, match patterns, annotations, comments, StringNames
(&"..."), NodePaths (^"..."), literals already wrapped, and lines marked
"# i18n-src" (a Russian source line translated by its receiver, still
extracted) or "# i18n-skip" (never a translation).

Idempotent. Run from tools/:  python3 i18n_wrap.py [--dry]
"""
from __future__ import annotations

import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CYR = re.compile(r"[А-Яа-яЁё]")


def literals(line):
    """(start, end) of every double-quoted literal outside comments."""
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "#":
            break
        if c == "'":  # single-quoted literal: skip it whole
            j = i + 1
            while j < n and line[j] != "'":
                j += 2 if line[j] == "\\" else 1
            i = j + 1
            continue
        if c == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 2 if line[j] == "\\" else 1
            out.append((i, j + 1))
            i = j + 1
            continue
        i += 1
    return out


def indent_of(line):
    return len(line) - len(line.lstrip("\t "))


HEADER_END = re.compile(r"\)\s*(->\s*[\w\[\]\.]+\s*)?:")


def process(text):
    lines = text.split("\n")
    out = []
    depth_const = 0  # bracket depth inside a const / enum block
    in_const = False
    static_indent = None  # indentation of the current static func header
    in_header = False  # inside a (multi-line) func header: defaults stay constant
    changed = 0
    for line in lines:
        stripped = line.strip()
        ind = indent_of(line)
        # leave the static func when the code dedents back to its header
        if static_indent is not None and stripped and ind <= static_indent and not stripped.startswith("#"):
            static_indent = None
        if re.match(r"(static\s+)?func\b", stripped):
            in_header = True
            if stripped.startswith("static"):
                static_indent = ind
        if not in_const and re.match(r"(const|enum)\b", stripped):
            in_const = True
            depth_const = 0
        # where translatable code starts on this line (after a header's "):")
        start = 0
        if in_header:
            m = HEADER_END.search(line)
            if m:
                start = m.end()
                in_header = False
            else:
                start = len(line)
        skip = in_const or stripped.startswith("@") or stripped.startswith("#") or "# i18n-" in line
        if re.fullmatch(r'("[^"]*"\s*,\s*)*"[^"]*"\s*:', stripped):
            skip = True  # a match pattern
        new = line
        if not skip:
            static_ctx = static_indent is not None or stripped.startswith("static var")
            fn = "TranslationServer.translate" if static_ctx else "tr"
            for (a, b) in reversed(literals(line)):
                if a < start:
                    continue
                lit = line[a:b]
                if not CYR.search(lit):
                    continue
                before = line[:a]
                if before.endswith("&") or before.endswith("^"):
                    continue
                if re.search(r"(tr|translate|tr_n|atr)\(\s*$", before):
                    continue
                new = new[:a] + fn + "(" + lit + ")" + new[b:]
                changed += 1
        out.append(new)
        if in_const:
            depth_const += line.count("[") + line.count("{") + line.count("(")
            depth_const -= line.count("]") + line.count("}") + line.count(")")
            if depth_const <= 0:
                in_const = False
    return "\n".join(out), changed


def main():
    dry = "--dry" in sys.argv
    total = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        new, n = process(src)
        if n:
            total += n
            if not dry:
                open(path, "w", encoding="utf-8", newline="\n").write(new)
    print("wrapped literals:", total)


if __name__ == "__main__":
    main()

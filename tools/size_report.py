#!/usr/bin/env python3
"""Size of DungeonEclipse against its asset budget (docs/ASSET_BUDGET.md).

  python3 tools/size_report.py            the report: categories, file types,
                                          the 50 heaviest files
  python3 tools/size_report.py --check    the same, exit 1 when a category
                                          is over its budget, the total over
                                          the ceiling, or a file over 100 MB
  python3 tools/size_report.py --build DIR   also the size of an exported
                                          build (the .pck / executables)
  python3 tools/size_report.py --json     machine-readable totals

Counts the files of the repository's working tree (not .git, .godot,
build/, __pycache__). Each file goes to the first category whose rule
matches (see CATEGORIES).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MB = 1024 * 1024
CEILING_MB = 1024
FILE_LIMIT_MB = 100
PNG_LFS_MB = 1  # a PNG heavier than this must match an LFS rule
LFS_RULES = os.path.join("tools", "lfs", "gitattributes.lfs")
SKIP_DIRS = {".git", ".godot", "build", "__pycache__", ".import", "export"}

# name, budget (MB), rule(path relative to the root, extension) -> bool
CATEGORIES = [
    ("Шрифты", 15, lambda p, e: e in (".ttf", ".otf", ".fnt", ".woff", ".woff2")),
    ("Музыка", 330, lambda p, e: p.startswith("assets/audio/music/")),
    ("Звуковые эффекты и амбиент", 120, lambda p, e: p.startswith("assets/audio/")),
    ("Фоны и тайлсеты", 120, lambda p, e: p.startswith(("assets/sprites/backgrounds/", "assets/sprites/tiles/"))),
    ("UI и иконки", 40, lambda p, e: p.startswith(("assets/ui/", "assets/sprites/items/", "assets/sprites/skills/",
                                                    "assets/sprites/achievements/", "assets/sprites/meta/",
                                                    "assets/icons/"))),
    ("Текстуры и спрайты", 250, lambda p, e: p.startswith("assets/") and e in (".png", ".webp", ".jpg", ".svg", ".webm")),
    ("Данные, сцены, код", 30, lambda p, e: e in (".tres", ".tscn", ".gd", ".gdshader", ".po", ".csv", ".json", ".cfg",
                                                   ".res", ".godot") and not p.startswith(("tools/", "docs/", "tests/"))),
    ("Прочее", 20, lambda p, e: True),
]


def walk():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            yield rel, size


def lfs_patterns() -> list:
    """Path patterns that go to Git LFS (the active .gitattributes, or the
    prepared rules of tools/lfs/ before LFS is switched on)."""
    out = []
    for name in (".gitattributes", LFS_RULES):
        try:
            with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
                for line in fh:
                    parts = line.split()
                    if len(parts) > 1 and "filter=lfs" in parts[1:]:
                        out.append(parts[0])
        except OSError:
            pass
    return out


def in_lfs(rel: str, patterns: list) -> bool:
    for p in patterns:
        if "/" not in p and fnmatch.fnmatch(os.path.basename(rel), p):
            return True
        if fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(rel, p.replace("**/", "")):
            return True
    return False


def category_of(rel: str) -> str:
    ext = os.path.splitext(rel)[1].lower()
    for name, _budget, rule in CATEGORIES:
        if rule(rel, ext):
            return name
    return "Прочее"


def human(n: float) -> str:
    return "%.1f МБ" % (n / MB) if n >= 0.1 * MB else "%.0f КБ" % (n / 1024)


def dir_size(path: str) -> int:
    total = 0
    for dirpath, _d, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(dirpath, f))
            except OSError:
                pass
    return total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--build", default="")
    ap.add_argument("--top", type=int, default=50)
    args = ap.parse_args()

    by_cat: dict[str, int] = {name: 0 for name, _b, _r in CATEGORIES}
    by_ext: dict[str, list] = {}
    files = []
    for rel, size in walk():
        cat = category_of(rel)
        by_cat[cat] += size
        ext = os.path.splitext(rel)[1].lower() or "(без расширения)"
        e = by_ext.setdefault(ext, [0, 0])
        e[0] += 1
        e[1] += size
        files.append((size, rel))
    total = sum(by_cat.values())
    budget_total = sum(b for _n, b, _r in CATEGORIES)
    over = []
    too_big = [(s, r) for s, r in files if s > FILE_LIMIT_MB * MB]
    pats = lfs_patterns()
    heavy_png = [(s, r) for s, r in files if r.endswith(".png") and s > PNG_LFS_MB * MB and not in_lfs(r, pats)]

    if args.json:
        print(json.dumps({"total_mb": round(total / MB, 2), "categories": {k: round(v / MB, 2) for k, v in by_cat.items()},
                          "files": len(files)}, ensure_ascii=False, indent=1))
    else:
        print("DungeonEclipse — размер против бюджета (docs/ASSET_BUDGET.md)\n")
        print("%-30s %12s %12s %7s" % ("Категория", "Сейчас", "Бюджет", "Доля"))
        for name, budget, _r in CATEGORIES:
            used = by_cat[name]
            mark = "  ПРЕВЫШЕН" if used > budget * MB else ""
            if mark:
                over.append(name)
            print("%-30s %12s %9d МБ %6.1f%%%s" % (name, human(used), budget, 100.0 * used / (budget * MB), mark))
        print("%-30s %12s %9d МБ %6.1f%%  (потолок %d МБ)" % ("Итого", human(total), budget_total, 100.0 * total / (budget_total * MB), CEILING_MB))
        print("\nПо типам файлов:")
        for ext, (n, size) in sorted(by_ext.items(), key=lambda kv: -kv[1][1])[:16]:
            print("  %-12s %6d файлов %12s" % (ext, n, human(size)))
        print("\nСамые тяжёлые файлы (%d):" % args.top)
        for size, rel in sorted(files, reverse=True)[:args.top]:
            print("  %10s  %s" % (human(size), rel))
        if args.build:
            b = os.path.join(ROOT, args.build) if not os.path.isabs(args.build) else args.build
            if os.path.isdir(b):
                print("\nСборка %s: %s" % (args.build, human(dir_size(b))))
                for dirpath, _d, fs in os.walk(b):
                    for f in fs:
                        p = os.path.join(dirpath, f)
                        size = os.path.getsize(p)
                        # One exported file (the .pck, or an executable with
                        # the pack inside) holds the whole game: the ceiling.
                        mark = "  БОЛЬШЕ ПОТОЛКА" if size > CEILING_MB * MB else ""
                        if mark:
                            over.append("сборка " + f)
                        print("  %10s  %s%s" % (human(size), os.path.relpath(p, b), mark))
            else:
                print("\nСборки %s нет" % args.build)
        if heavy_png:
            print("\nPNG больше %d МБ вне правил LFS (назовите *_large.png или *_atlas.png):" % PNG_LFS_MB)
            for s_, r in heavy_png:
                print("  %s  %s" % (human(s_), r))
        if too_big:
            print("\nФайлы больше %d МБ (GitHub их не примет):" % FILE_LIMIT_MB)
            for s, r in too_big:
                print("  %s  %s" % (human(s), r))
    for name, budget, _r in CATEGORIES:
        if by_cat[name] > budget * MB and name not in over:
            over.append(name)
    if heavy_png:
        over.append("PNG вне LFS")
    failed = bool(over) or bool(too_big) or total > CEILING_MB * MB
    if args.check:
        print("\nПРОВЕРКА: %s" % ("НЕ ПРОЙДЕНА — " + ", ".join(over or ["потолок или файл > 100 МБ"]) if failed else "в пределах бюджета"))
        return 1 if failed else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

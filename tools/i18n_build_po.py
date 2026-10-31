#!/usr/bin/env python3
"""Builds locale/en.po from tools/i18n/en_*.json (Russian msgid -> English).

Run after tools/i18n_extract.py; prints the msgids still missing a translation.
"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def main() -> None:
    tr = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "tools/i18n/en_*.json"))):
        with open(f, encoding="utf-8") as fh:
            tr.update(json.load(fh))
    with open(os.path.join(ROOT, "locale/messages.json"), encoding="utf-8") as fh:
        messages = json.load(fh)
    out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Language: en\\n"', ""]
    missing = []
    for msgid in sorted(messages):
        if msgid not in tr:
            missing.append(msgid)
            continue
        out.append("#: " + str(messages[msgid]))
        out.append('msgid "%s"' % esc(msgid))
        out.append('msgstr "%s"' % esc(tr[msgid]))
        out.append("")
    with open(os.path.join(ROOT, "locale/en.po"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    print("en.po: %d strings, %d missing" % (len(messages) - len(missing), len(missing)))
    for m in missing:
        print("  missing:", m)


if __name__ == "__main__":
    main()

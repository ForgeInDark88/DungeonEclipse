#!/usr/bin/env bash
# Rebuilds the string table and the English translation in one go:
# data texts (through the engine) + code texts -> locale/messages.json,
# tools/i18n/en_*.json -> locale/en.po. Prints the strings still missing.
set -eu
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
TMP=$(mktemp -d)
"$GODOT" --headless -s tools/i18n_dump_data.gd -- "$TMP/data_texts.json" 2>/dev/null | grep "data texts"
(cd tools && python3 i18n_extract.py "$TMP/data_texts.json" | tail -1)
python3 tools/i18n_build_po.py
rm -rf "$TMP"

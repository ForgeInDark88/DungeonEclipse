#!/usr/bin/env bash
# Exports DungeonEclipse with every preset of export_presets.cfg whose
# template is installed, then reports the build size against the budget.
#   tools/build.sh                 Windows, Linux, Web (what has templates)
#   tools/build.sh Linux           one preset
# Output: build/<preset>/ ; the size: python3 tools/size_report.py --build build
# Templates: Godot editor -> Editor -> Manage Export Templates (4.3.stable).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
TPL=${TPL:-$HOME/.local/share/godot/export_templates/4.3.stable}
declare -A OUT=([Windows]=build/windows/DungeonEclipse.exe [Linux]=build/linux/DungeonEclipse.x86_64 [Web]=build/web/index.html)
declare -A NEED=([Windows]=windows_release_x86_64.exe [Linux]=linux_release.x86_64 [Web]=web_nothreads_release.zip)
PRESETS=("$@")
[ ${#PRESETS[@]} -eq 0 ] && PRESETS=(Windows Linux Web)
"$GODOT" --headless --import > /dev/null 2>&1
rc=0
for p in "${PRESETS[@]}"; do
	if [ ! -f "$TPL/${NEED[$p]}" ]; then
		echo "skip  $p: no template $TPL/${NEED[$p]}"
		continue
	fi
	mkdir -p "$(dirname "${OUT[$p]}")"
	if "$GODOT" --headless --export-release "$p" "${OUT[$p]}" > "build/export_$p.log" 2>&1 && [ -f "${OUT[$p]}" ]; then
		echo "ok    $p -> ${OUT[$p]} ($(du -h "${OUT[$p]}" | cut -f1))"
	else
		echo "FAIL  $p (build/export_$p.log)"; rc=1
	fi
done
python3 tools/size_report.py --build build --top 0 | sed -n '/^Сборка/,$p'
exit $rc

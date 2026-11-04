#!/usr/bin/env bash
# All the automatic checks of DungeonEclipse, headless. Non-zero exit code
# when any check fails (CI: .github/workflows/tests.yml).
#   tools/run_tests.sh           everything (~45 min on a 4-core machine)
#   tools/run_tests.sh --quick   the fast set (~8 min): data, saves, map,
#                                town, combat, 100 seeds of floors, the co-op
#                                smoke tests
# GODOT=/path/to/godot overrides the binary; LOG_DIR keeps the logs.
# A test fails on a non-zero exit, on "FAIL:" / "RESULT: FAILURES" in its
# output, or on a runtime "SCRIPT ERROR" (the "GDScript::reload ...
# Identifier not found" lines some old -s scripts print while compiling
# before the autoloads exist are counted separately: docs/AUDIT.md).
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LOG_DIR=${LOG_DIR:-/tmp/dungeoneclipse_tests}
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1
mkdir -p "$LOG_DIR"
FAILED=()
PASSED=0
COMPILE_NOISE=0

result() {  # name rc log
	local name=$1 rc=$2 log=$3
	local runtime noise
	runtime=$(grep -A1 "SCRIPT ERROR" "$log" | grep -E "^\s+at: " | grep -vc "GDScript::reload" || true)
	noise=$(grep -A1 "SCRIPT ERROR" "$log" | grep -c "GDScript::reload" || true)
	COMPILE_NOISE=$((COMPILE_NOISE + noise))
	if [ "$rc" -ne 0 ] || grep -qE "^FAIL:|RESULT: FAILURES|^FAILURES: [1-9]" "$log" || [ "$runtime" -gt 0 ]; then
		FAILED+=("$name")
		echo "  FAIL  $name (exit $rc, runtime errors $runtime) — $log"
		grep -hE "^FAIL|SCRIPT ERROR" "$log" | head -5 | sed 's/^/        /'
	else
		PASSED=$((PASSED + 1))
		echo "  ok    $name $(grep -hE '^FAILURES|RESULT|floors:|duels:|data files:|locations:' "$log" | tail -1)"
	fi
}

script_test() {  # name path [timeout]
	local name=$1 path=$2 t=${3:-900}
	timeout "$t" "$GODOT" --headless -s "$path" > "$LOG_DIR/$name.log" 2>&1
	result "$name" $? "$LOG_DIR/$name.log"
}

scene_test() {  # name scene [args...]
	local name=$1 scene=$2
	shift 2
	timeout 900 "$GODOT" --headless --fixed-fps 60 --path . "$scene" -- "$@" > "$LOG_DIR/$name.log" 2>&1
	result "$name" $? "$LOG_DIR/$name.log"
}

pair_test() {  # name scene: host + client on 127.0.0.1
	local name=$1 scene=$2
	NET_ROLE=host timeout 120 "$GODOT" --headless --path . "$scene" > "$LOG_DIR/$name.host.log" 2>&1 &
	local hp=$!
	sleep 2
	NET_ROLE=client timeout 120 "$GODOT" --headless --path . "$scene" > "$LOG_DIR/$name.client.log" 2>&1
	local crc=$?
	wait $hp
	local hrc=$?
	cat "$LOG_DIR/$name.host.log" "$LOG_DIR/$name.client.log" > "$LOG_DIR/$name.log"
	result "$name" $((hrc + crc)) "$LOG_DIR/$name.log"
}

echo "== import / parse"
# Import first (a fresh clone has nothing imported; its first pass prints
# compile noise for scripts that preload art), then the clean parse check.
timeout 900 "$GODOT" --headless --import > "$LOG_DIR/import_first.log" 2>&1
timeout 600 "$GODOT" --headless --editor --quit > "$LOG_DIR/import.log" 2>&1
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG_DIR/import.log"; then
	FAILED+=("import"); echo "  FAIL  import — $LOG_DIR/import.log"; grep -E "SCRIPT ERROR|Parse Error" "$LOG_DIR/import.log" | head -5
else
	PASSED=$((PASSED + 1)); echo "  ok    import (the project parses)"
fi

echo "== data, generation, balance"
script_test data tools/tests/data_test.gd
script_test assets tools/tests/asset_test.gd
script_test audio tools/tests/audio_test.gd
if [ $QUICK -eq 1 ]; then SEEDS=100 script_test level_gen tools/tests/level_gen_test.gd; else script_test level_gen tools/tests/level_gen_test.gd 1800; fi
script_test combat tools/tests/combat_sim.gd
script_test layer_balance tests/layer_balance_sim.gd
script_test loop_balance tests/loop_balance_sim.gd
scene_test loot tests/loot_sim.tscn

echo "== saves, town, map, events, relics, quests"
script_test save tests/save_test.gd
script_test town tests/town_test.gd
script_test map tests/map_test.gd
script_test event tests/event_test.gd
script_test relic tests/relic_test.gd
scene_test quest tests/quest_sim.tscn
scene_test hotkeys tests/hotkey_sim.tscn
scene_test input tests/input_sim.tscn

echo "== AI and combat in the engine"
scene_test ai_behaviour tests/ai_behaviour_test.tscn
if [ $QUICK -eq 0 ]; then
	scene_test ai_dungeon tests/ai_sim.tscn --levels=20 --seconds=20
	scene_test ai_surface tests/ai_sim.tscn --surface --levels=20 --seconds=20
	scene_test ai_drowned tests/ai_sim.tscn --biome=drowned_vaults --levels=10 --seconds=20
else
	# A short run in the quick set too: a change of the level RNG (decor,
	# generation) can put a monster on a trap that only the engine shows.
	scene_test ai_dungeon tests/ai_sim.tscn --levels=8 --seconds=15
fi

echo "== the game flow, locations, water, life"
script_test flow tests/flow_test.gd 1200
script_test water tests/water_test.gd
script_test surface_life tests/surface_life_test.gd
if [ $QUICK -eq 0 ]; then
	SEEDS=12 script_test layer_load tests/layer_load_test.gd 1500
	bash tests/location_test.sh "$LOG_DIR/location" > "$LOG_DIR/location.log" 2>&1
	result location $? "$LOG_DIR/location.log"
fi

echo "== co-op (several processes on 127.0.0.1)"
pair_test net_smoke tests/net_sim.tscn
pair_test net_game tests/net_game_sim.tscn
if [ $QUICK -eq 0 ]; then
	for w in world_layers world_coop world_flow world_net; do
		timeout 1200 bash "tests/$w.sh" > "$LOG_DIR/$w.log" 2>&1
		result "$w" $? "$LOG_DIR/$w.log"
	done
fi

echo
echo "passed: $PASSED, failed: ${#FAILED[@]}${FAILED:+ (${FAILED[*]})}; compile-order noise lines in old -s tests: $COMPILE_NOISE"
[ ${#FAILED[@]} -eq 0 ]

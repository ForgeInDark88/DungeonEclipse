extends Node
## Current run: the hero, the floor, the run seed and run statistics.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const CHARACTER_CREATION := "res://scenes/ui/character_creation.tscn"
const GAME := "res://scenes/game/game.tscn"
const SANCTUM := "res://scenes/ui/sanctum.tscn"
const CODEX := "res://scenes/ui/codex.tscn"
const DAILY := "res://scenes/ui/daily.tscn"
## A new biome every N floors (see data/biomes, BiomeData.order).
const FLOORS_PER_BIOME := 3
## Floor number of the town where every run starts.
const TOWN_FLOOR := 0
## Every N-th floor is a boss arena.
const BOSS_EVERY := 5

var hero: Hero
var floor_number: int = 1
var run_seed: int = 0
var kills: int = 0
var run_active: bool = false
## Statistics of the current run (death screen, achievements):
## gold, kills, floor, found_common/rare/epic, bosses, time.
var run_stats: Dictionary = {}
## Non-empty during a daily run: its date "YYYY-MM-DD" (seed and leaderboard key).
var daily_date: String = ""
## Blessings and curses of the altars of fate taken this run (RunPactData).
var pacts: Array[RunPactData] = []
## Difficulty of this run (data/difficulties; daily runs: «normal»).
var difficulty: DifficultyData
## Pet of this run (null = none).
var pet: PetData
## Combo: kills in a row, each within COMBO_WINDOW of the previous one,
## without taking damage. Every step adds COMBO_STEP to XP and gold.
const COMBO_WINDOW := 4.0
const COMBO_STEP := 0.05
const COMBO_MAX_BONUS := 0.5
var combo: int = 0
var _combo_time := 0.0
## The guild's quest chain for this run (progress from EventBus signals).
var quests := QuestLog.new()
## The floor the hero left mid-run to visit the town; the town gate leads
## back to it (regenerated fresh). 0 = the hero has not left a floor.
var town_return_floor: int = 0


func _ready() -> void:
	quests.attach()
	EventBus.enemy_killed.connect(func(_d: EnemyData, _p: Vector2) -> void:
		kills += 1
		_add_combo())
	EventBus.damage_dealt.connect(func(_pos: Vector2, _a: int, _c: bool, on_player: bool) -> void:
		if on_player:
			_set_combo(0))
	EventBus.floor_changed.connect(func(_f: int) -> void: _set_combo(0))
	EventBus.elite_killed.connect(func(_d: EnemyData) -> void:
		run_stats["elites"] = int(run_stats.get("elites", 0)) + 1)


## `seed_value` >= 0 makes the whole run reproducible (daily runs, tests).
func start_new_run(race: RaceData, class_data: ClassData, seed_value: int = -1, daily := "", female := false,
		difficulty_id: StringName = &"normal") -> void:
	SaveManager.clear_run()  # a new run replaces any saved one
	daily_date = daily
	difficulty = ItemDatabase.difficulty(&"normal" if daily != "" else difficulty_id)
	hero = Hero.new(race, class_data, ItemDatabase.equipment_layout)
	hero.female = female
	hero.give_starting_kit()
	hero.skills.add_points(1)  # the run opens with a choice: the first learned skill commits the branch
	MetaProgress.apply_to(hero, daily == "")
	floor_number = TOWN_FLOOR
	kills = 0
	pacts.clear()
	pet = null
	combo = 0
	town_return_floor = 0
	quests.reset()
	reset_run_stats()
	run_seed = randi() if seed_value < 0 else seed_value
	run_active = true
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME)


func reset_run_stats() -> void:
	run_stats = {"gold": 0, "found": [0, 0, 0, 0], "bosses": 0, "elites": 0, "start_ms": Time.get_ticks_msec()}


func set_pet(p_pet: PetData) -> void:
	pet = p_pet
	EventBus.pet_changed.emit(pet)


func _process(delta: float) -> void:
	if combo > 0:
		_combo_time -= delta
		if _combo_time <= 0.0:
			_set_combo(0)


func _add_combo() -> void:
	_combo_time = COMBO_WINDOW
	_set_combo(combo + 1)
	if combo > int(run_stats.get("best_combo", 0)):
		run_stats["best_combo"] = combo


func _set_combo(value: int) -> void:
	if value == combo:
		return
	combo = value
	EventBus.combo_changed.emit(combo)


## Seconds left before the combo breaks.
func combo_time_left() -> float:
	return _combo_time if combo > 0 else 0.0


## XP / gold bonus of the current combo (the first kill gives none).
func combo_bonus() -> float:
	return minf(COMBO_MAX_BONUS, COMBO_STEP * maxi(0, combo - 1))


## Takes a blessing / curse until the end of the run.
func add_pact(pact: RunPactData) -> void:
	pacts.append(pact)
	if hero and not pact.stats.is_empty():
		hero.stats.set_modifier("pact_%s_%d" % [pact.id, pacts.size()], pact.stats)
	EventBus.pact_taken.emit(pact)


## Sum of a run multiplier over every pact (see RunPactData.effects) and
## the difficulty (DifficultyData.effects).
func run_effect(key: String) -> float:
	var v := float(difficulty.effects.get(key, 0.0)) if difficulty else 0.0
	for p in pacts:
		v += float(p.effects.get(key, 0.0))
	return v


## Seed of the current floor: each run and each floor is different.
## Today's date (local time) as used by daily runs.
static func today() -> String:
	return Time.get_date_string_from_system()


## Seed, race and class of the daily run of `date`: the same for every player.
## Only races / classes available without the Sanctum take part.
static func daily_setup(date: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("eclipse-daily:" + date)
	var races := ItemDatabase.races.filter(func(r: RaceData) -> bool: return r.unlock_shards <= 0 and r.unlock_gold <= 0)
	var classes := ItemDatabase.classes.filter(func(c: ClassData) -> bool: return c.unlock_shards <= 0 and c.unlock_gold <= 0)
	var setup := {"seed": rng.randi() & 0x7FFFFFFF, "race": races[rng.randi() % races.size()],
		"class": classes[rng.randi() % classes.size()]}
	setup["female"] = rng.randi() % 2 == 1  # drawn last: older days keep their seed
	return setup


func start_daily_run(date: String = "") -> void:
	if date == "":
		date = today()
	var d := daily_setup(date)
	start_new_run(d["race"], d["class"], d["seed"], date, d["female"])


## Difficulty multipliers that are not run effects (1.0 without a run).
func elite_chance_mult() -> float:
	return difficulty.elite_chance_mult if difficulty else 1.0


func trap_damage_mult() -> float:
	return difficulty.trap_damage_mult if difficulty else 1.0


func is_daily() -> bool:
	return daily_date != ""


func floor_seed() -> int:
	return hash([run_seed, floor_number])


func is_boss_floor(f: int = -1) -> bool:
	var n := floor_number if f < 0 else f
	return n > TOWN_FLOOR and n % BOSS_EVERY == 0


func is_town() -> bool:
	return floor_number == TOWN_FLOOR


func current_biome() -> BiomeData:
	if is_town():
		return load(AssetPaths.TOWN_BIOME) as BiomeData
	return ItemDatabase.biome_for_floor(floor_number)


func next_floor() -> void:
	floor_number += 1
	EventBus.floor_changed.emit(floor_number)


## Climbs out of the dungeon at the current floor: back to the town street
## without ending the run. The town gate then leads back to this floor.
func return_to_town() -> void:
	if not run_active or floor_number <= TOWN_FLOOR:
		return
	town_return_floor = floor_number
	floor_number = TOWN_FLOOR
	EventBus.floor_changed.emit(floor_number)


## The town gate mid-run: descends to the floor the hero left.
func resume_from_town() -> void:
	floor_number = maxi(1, town_return_floor)
	town_return_floor = 0
	EventBus.floor_changed.emit(floor_number)


## Resumes the saved run (the snapshot of its last floor start). Returns
## false when there is no save or it cannot be read.
func continue_run() -> bool:
	var d := SaveManager.run_data()
	if d.is_empty() or not RunCodec.load_run(d):
		SaveManager.clear_run()
		return false
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME)
	return true


## Records the run and pays the Sanctum rewards. Safe to call twice: the
## second call returns {} (death screen first, then "back to menu").
func end_run() -> Dictionary:
	var reward := {}
	if run_active:
		SaveManager.clear_run()  # permadeath: the snapshot dies with the hero
		SaveManager.record_run(floor_number, kills)
		reward = MetaProgress.finish_run(hero, floor_number, run_stats)
		if is_daily():
			reward["daily"] = _submit_daily()
		Codex.add(&"runs")
		Codex.save_progress()
	run_active = false
	return reward


## Daily leaderboard entry; returns {"place", "score"}.
func _submit_daily() -> Dictionary:
	var bosses := int(run_stats.get("bosses", 0))
	var gold := int(run_stats.get("gold", 0))
	var lvl := hero.level if hero else 1
	var entry := {
		"score": Leaderboard.score(floor_number, kills, gold, bosses, lvl),
		"floor": floor_number, "kills": kills, "gold": gold, "bosses": bosses, "level": lvl,
		"time_s": (Time.get_ticks_msec() - int(run_stats.get("start_ms", 0))) / 1000,
		"race": hero.race.display_name if hero else "", "class": hero.class_data.display_name if hero else "",
		"at": Time.get_datetime_string_from_system().right(8),
	}
	return {"place": Leaderboard.submit(daily_date, entry), "score": entry["score"]}


func go_to_menu() -> void:
	# Leaving through the pause menu keeps the between-floors snapshot, so the
	# run can be continued from the main menu. Death ends it (end_run there).
	if not (run_active and hero != null and hero.stats.hp > 0):
		end_run()
	hero = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

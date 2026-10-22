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


func _ready() -> void:
	EventBus.enemy_killed.connect(func(_d: EnemyData, _p: Vector2) -> void: kills += 1)


## `seed_value` >= 0 makes the whole run reproducible (daily runs, tests).
func start_new_run(race: RaceData, class_data: ClassData, seed_value: int = -1, daily := "") -> void:
	daily_date = daily
	hero = Hero.new(race, class_data, ItemDatabase.equipment_layout)
	hero.give_starting_kit()
	MetaProgress.apply_to(hero, daily == "")
	floor_number = 1
	kills = 0
	reset_run_stats()
	run_seed = randi() if seed_value < 0 else seed_value
	run_active = true
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME)


func reset_run_stats() -> void:
	run_stats = {"gold": 0, "found": [0, 0, 0], "bosses": 0, "start_ms": Time.get_ticks_msec()}


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
	return {"seed": rng.randi() & 0x7FFFFFFF, "race": races[rng.randi() % races.size()],
		"class": classes[rng.randi() % classes.size()]}


func start_daily_run(date: String = "") -> void:
	if date == "":
		date = today()
	var d := daily_setup(date)
	start_new_run(d["race"], d["class"], d["seed"], date)


func is_daily() -> bool:
	return daily_date != ""


func floor_seed() -> int:
	return hash([run_seed, floor_number])


func is_boss_floor(f: int = -1) -> bool:
	return (floor_number if f < 0 else f) % BOSS_EVERY == 0


func current_biome() -> BiomeData:
	return ItemDatabase.biome_for_floor(floor_number)


func next_floor() -> void:
	floor_number += 1
	EventBus.floor_changed.emit(floor_number)


## Records the run and pays the Sanctum rewards. Safe to call twice: the
## second call returns {} (death screen first, then "back to menu").
func end_run() -> Dictionary:
	var reward := {}
	if run_active:
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
	end_run()
	hero = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

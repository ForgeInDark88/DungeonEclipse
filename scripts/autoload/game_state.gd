extends Node
## Current run: the hero, the floor, the run seed and run statistics.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const CHARACTER_CREATION := "res://scenes/ui/character_creation.tscn"
const GAME := "res://scenes/game/game.tscn"
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


func _ready() -> void:
	EventBus.enemy_killed.connect(func(_d: EnemyData, _p: Vector2) -> void: kills += 1)


## `seed_value` >= 0 makes the whole run reproducible (daily runs, tests).
func start_new_run(race: RaceData, class_data: ClassData, seed_value: int = -1) -> void:
	hero = Hero.new(race, class_data, ItemDatabase.equipment_layout)
	hero.give_starting_kit()
	floor_number = 1
	kills = 0
	reset_run_stats()
	run_seed = randi() if seed_value < 0 else seed_value
	run_active = true
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME)


## Seed of the current floor: each run and each floor is different.
func reset_run_stats() -> void:
	run_stats = {"gold": 0, "found": [0, 0, 0], "bosses": 0, "start_ms": Time.get_ticks_msec()}


func floor_seed() -> int:
	return hash([run_seed, floor_number])


func is_boss_floor(f: int = -1) -> bool:
	return (floor_number if f < 0 else f) % BOSS_EVERY == 0


func current_biome() -> BiomeData:
	return ItemDatabase.biome_for_floor(floor_number)


func next_floor() -> void:
	floor_number += 1
	EventBus.floor_changed.emit(floor_number)


func end_run() -> void:
	if run_active:
		SaveManager.record_run(floor_number, kills)
	run_active = false
	hero = null


func go_to_menu() -> void:
	end_run()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

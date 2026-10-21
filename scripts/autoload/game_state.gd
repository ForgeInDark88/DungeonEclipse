extends Node
## Current run: the hero, the floor, the run seed and run statistics.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const CHARACTER_CREATION := "res://scenes/ui/character_creation.tscn"
const GAME := "res://scenes/game/game.tscn"

var hero: Hero
var floor_number: int = 1
var run_seed: int = 0
var kills: int = 0
var run_active: bool = false


func _ready() -> void:
	EventBus.enemy_killed.connect(func(_d: EnemyData, _p: Vector2) -> void: kills += 1)


func start_new_run(race: RaceData, class_data: ClassData) -> void:
	hero = Hero.new(race, class_data, ItemDatabase.equipment_layout)
	hero.give_starting_kit()
	floor_number = 1
	kills = 0
	run_seed = randi()
	run_active = true
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME)


## Seed of the current floor: each run and each floor is different.
func floor_seed() -> int:
	return hash([run_seed, floor_number])


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

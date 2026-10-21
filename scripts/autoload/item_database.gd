extends Node
## Loads every data resource from res://data at startup, so new content is
## picked up just by dropping a .tres file into the right folder.

const ITEMS_DIR := "res://data/items"
const RACES_DIR := "res://data/races"
const CLASSES_DIR := "res://data/classes"
const ENEMIES_DIR := "res://data/enemies"
const LOOT_DIR := "res://data/loot_tables"
const EQUIPMENT_LAYOUT := "res://data/equipment_layout.tres"

var items: Dictionary = {}  # StringName -> ItemData
var races: Array[RaceData] = []
var classes: Array[ClassData] = []
var enemies: Array[EnemyData] = []
var loot_tables: Dictionary = {}  # StringName (file name) -> LootTable
var equipment_layout: EquipmentLayout


func _ready() -> void:
	reload()


func reload() -> void:
	items.clear()
	races.clear()
	classes.clear()
	enemies.clear()
	loot_tables.clear()
	for res in _load_dir(ITEMS_DIR):
		if res is ItemData:
			if items.has(res.id):
				push_warning("Duplicate item id: %s" % res.id)
			items[res.id] = res
	for res in _load_dir(RACES_DIR):
		if res is RaceData:
			races.append(res)
	for res in _load_dir(CLASSES_DIR):
		if res is ClassData:
			classes.append(res)
	for res in _load_dir(ENEMIES_DIR):
		if res is EnemyData:
			enemies.append(res)
	for res in _load_dir(LOOT_DIR):
		if res is LootTable:
			loot_tables[StringName(res.resource_path.get_file().get_basename())] = res
	races.sort_custom(func(a: RaceData, b: RaceData) -> bool: return a.order < b.order)
	classes.sort_custom(func(a: ClassData, b: ClassData) -> bool: return a.order < b.order)
	equipment_layout = load(EQUIPMENT_LAYOUT) as EquipmentLayout


func get_item(id: StringName) -> ItemData:
	if not items.has(id):
		push_warning("Unknown item id: %s" % id)
		return null
	return items[id]


func get_loot_table(table_name: StringName) -> LootTable:
	return loot_tables.get(table_name)


func enemies_for_floor(floor_number: int) -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	for e in enemies:
		if e.min_floor <= floor_number:
			list.append(e)
	return list


## Recursively loads resources. Handles ".remap" names of exported builds.
func _load_dir(path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	var files := dir.get_files()
	files.sort()
	for f in files:
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res := load(path.path_join(file))
			if res:
				result.append(res)
	var dirs := dir.get_directories()
	dirs.sort()
	for sub in dirs:
		result.append_array(_load_dir(path.path_join(sub)))
	return result

class_name TownState
extends RefCounted
## Everything that lives between expeditions (saved to user://town.save by
## SaveManager): the hero who calls the town home, buildings and their
## levels, residents, the town's resources, discoveries and story flags,
## the warehouse (items that never leave town), trophies and records.
## Plain data: GameFlow changes it, UI listens to `changed`.

signal changed

## The hero of this town (RunCodec.save_hero snapshot; {} = none yet).
var hero: Dictionary = {}
## building id -> level (0 = foundation / ruins, 1..3 = built / upgraded).
var buildings: Dictionary = {}
## Ids of the people who moved in (NpcData.id).
var residents: Array[StringName] = []
## Building materials and rare finds: wood, stone, iron, crystal...
var resources: Dictionary = {}
## Story flags and discoveries: id -> value (bool / int / String).
var flags: Dictionary = {}
## Items stored in the warehouse (RunCodec item dictionaries).
var warehouse: Array = []
## Trophies on display in the hall of fame (RunCodec item dictionaries).
var trophies: Array = []
## Blueprints found (building ids): they open the levels that need one.
var blueprints: Array[StringName] = []
## Ids of region bosses beaten at least once.
var bosses_defeated: Array[StringName] = []
## Highest region an expedition may start in (0 = the first one).
var region_unlocked: int = 0
## Prosperity of the town: grows with buildings, rescues and victories.
var prosperity: int = 0
## Difficulty and level of the Eclipse picked at hero creation.
var difficulty_id: StringName = &"normal"
var eclipse_level: int = 0
## An expedition is under way: a game quit mid-expedition counts as lost
## when the town is loaded again (see GameFlow.continue_game).
var expedition_active := false
## Records: expeditions, deaths, retreats, victories, nodes, rescues.
var stats: Dictionary = {}
## Heroes of the players of this world by nickname key (PlayerProfiles).
var players: Dictionary = {}
## Seed of the world (made with it, kept for later use).
var world_seed: int = 0
## Changes since the hero last walked the street (news on return).
var news: Array[String] = []


func resource(id: StringName) -> int:
	return int(resources.get(String(id), 0))


func add_resource(id: StringName, amount: int) -> void:
	if amount == 0:
		return
	resources[String(id)] = maxi(0, resource(id) + amount)
	changed.emit()


func building_level(id: StringName) -> int:
	return int(buildings.get(String(id), 0))


func set_building_level(id: StringName, level: int) -> void:
	buildings[String(id)] = level
	changed.emit()


func has_resident(id: StringName) -> bool:
	return id in residents


func add_resident(id: StringName) -> bool:
	if has_resident(id):
		return false
	residents.append(id)
	changed.emit()
	return true


func flag(id: String, default: Variant = false) -> Variant:
	return flags.get(id, default)


func set_flag(id: String, value: Variant = true) -> void:
	flags[id] = value
	changed.emit()


func add_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


# ------------------------------------------------------------- save / load
func to_dict() -> Dictionary:
	return {
		"hero": hero,
		"buildings": buildings.duplicate(),
		"residents": residents.map(func(r: StringName) -> String: return String(r)),
		"resources": resources.duplicate(),
		"flags": flags.duplicate(),
		"warehouse": warehouse.duplicate(true),
		"trophies": trophies.duplicate(true),
		"blueprints": blueprints.map(func(b: StringName) -> String: return String(b)),
		"bosses": bosses_defeated.map(func(b: StringName) -> String: return String(b)),
		"region_unlocked": region_unlocked,
		"prosperity": prosperity,
		"difficulty": String(difficulty_id),
		"eclipse": eclipse_level,
		"expedition_active": expedition_active,
		"stats": stats.duplicate(),
		"news": Array(news),
		"world_seed": world_seed,
		"players": players.duplicate(true),
	}


## A TownState from a saved dictionary; missing keys take defaults, wrong
## types are ignored (a damaged save never crashes the game).
static func from_dict(d: Dictionary) -> TownState:
	var t := TownState.new()
	t.hero = _dict(d.get("hero"))
	t.buildings = _dict(d.get("buildings"))
	for r in _arr(d.get("residents")):
		t.residents.append(StringName(str(r)))
	t.resources = _dict(d.get("resources"))
	t.flags = _dict(d.get("flags"))
	t.warehouse = _arr(d.get("warehouse"))
	t.trophies = _arr(d.get("trophies"))
	for id in _arr(d.get("blueprints")):
		t.blueprints.append(StringName(str(id)))
	for id in _arr(d.get("bosses")):
		t.bosses_defeated.append(StringName(str(id)))
	t.region_unlocked = int(d.get("region_unlocked", 0)) if d.get("region_unlocked") is int else 0
	t.prosperity = int(d.get("prosperity", 0)) if d.get("prosperity") is int else 0
	t.difficulty_id = StringName(str(d.get("difficulty", "normal")))
	t.eclipse_level = int(d.get("eclipse", 0)) if d.get("eclipse") is int else 0
	t.expedition_active = d.get("expedition_active", false) == true
	t.stats = _dict(d.get("stats"))
	t.world_seed = int(d.get("world_seed", 0)) if d.get("world_seed") is int else 0
	t.players = _dict(d.get("players"))
	for n in _arr(d.get("news")):
		t.news.append(str(n))
	return t


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []

class_name LocationInstance
extends Resource
## One location of the expedition, planned from its node and its seed: the
## layers (the surface, the dungeon floors, the guardian's arena), the
## portals between them and what has changed in each layer since the party
## came (opened chests, the fallen, broken bricks, disarmed traps, opened
## shortcuts). The same node always plans the same location: LocationBuilder
## turns the plan into tiles from `gen_seed`; `play_seed` drives the luck of
## play (respawns), so generation never depends on what happened in play.
##
## Lives in GameState.location["instance"] as a Dictionary (to_dict), so the
## expedition save and the network flow carry it as plain data.

enum Kind { SURFACE, DUNGEON, ARENA }

## Portal kinds. MAP: back to the expedition map (the surface's start).
## ENTRANCE / SIDE: the way down from the surface (main / side). UP / DOWN:
## stairs between floors. ARENA_EXIT: out of a beaten guardian's arena.
const MAP := &"map"
const ENTRANCE := &"entrance"
const SIDE := &"side"
const UP := &"up"
const DOWN := &"down"
const ARENA_EXIT := &"arena_exit"

@export var node_type: StringName = &"level"
@export var depth: int = 1
@export var biome: StringName = &""
@export var region: int = 0
@export var seed_value: int = 0
@export var gen_seed: int = 0
@export var play_seed: int = 0
## [{id: StringName, kind: Kind, depth: int, seed: int}], the surface first.
@export var layers: Array = []
## [{id: StringName, layer: int, kind: StringName, to: StringName (portal),
##   locked: bool (opens later: a beaten guardian, a key...)}]
@export var portals: Array = []
## Layer id -> {chests: [loc ids], dead: [loc ids], traps: [loc ids],
##   tiles: [[x, y, tile]] (layer cells), opened: [portal ids], flags: {}}
@export var state: Dictionary = {}
## The last save point: the portal the party went through last (the hero
## comes back there after a load).
@export var save_portal: StringName = &""
## A camp fire saved last: the hero comes back there instead ([x, y] px).
@export var save_pos: Array = []
## The guardian of this location fell (the map exit and the arena exit open).
@export var boss_beaten: bool = false


## The plan of the node's location, or null when its type has no layers.
static func plan(node: Dictionary) -> LocationInstance:
	var def: LocationDefinition = ItemDatabase.locations.get(StringName(node.get("type", &"")))
	if def == null:
		return null
	var li := LocationInstance.new()
	li.node_type = def.id
	li.depth = int(node.get("depth", 1))
	li.biome = StringName(node.get("biome", &""))
	li.region = int(node.get("region", 0))
	li.seed_value = int(node.get("seed", 0))
	li.gen_seed = hash([li.seed_value, "gen"])
	li.play_seed = hash([li.seed_value, "play"])
	var rng := RandomNumberGenerator.new()
	rng.seed = li.gen_seed
	var floors := rng.randi_range(def.floors_min, maxi(def.floors_min, def.floors_max))
	var sides := rng.randi_range(def.side_entrances_min, maxi(def.side_entrances_min, def.side_entrances_max))
	if def.has_surface:
		li.layers.append({"id": &"surface", "kind": Kind.SURFACE, "depth": li.depth, "seed": rng.randi(),
				"biome": surface_biome_for(li.region, rng.randi()),
				"screens": rng.randi_range(def.surface_screens_min, maxi(def.surface_screens_min, def.surface_screens_max))})
		li.portals.append({"id": &"map", "layer": 0, "kind": MAP, "to": &"", "locked": def.boss_arena})
	for f in floors:
		var arena := def.boss_arena and f == floors - 1
		li.layers.append({"id": StringName("floor_%d" % (f + 1)), "kind": Kind.ARENA if arena else Kind.DUNGEON,
				"depth": li.depth + f, "seed": rng.randi(), "last": f == floors - 1})
	var first := 1 if def.has_surface else 0
	# The surface's main entrance and the first floor's way up.
	if def.has_surface:
		li._link(&"main", 0, ENTRANCE, &"f1_up", first, UP)
		for k in sides:
			li._link(StringName("side_%d" % (k + 1)), 0, SIDE, StringName("f1_side_%d" % (k + 1)), first, UP)
	else:
		li.portals.append({"id": &"f1_up", "layer": first, "kind": MAP, "to": &"", "locked": def.boss_arena})
	for f in range(1, floors):
		var down := StringName("f%d_down" % f)
		var up := StringName("f%d_up" % (f + 1))
		li._link(down, first + f - 1, DOWN, up, first + f, UP)
	# No way out of the guardian's arena until the guardian falls.
	for p in li.portals:
		if int(p["layer"]) == li.layers.size() - 1 and def.boss_arena:
			p["locked"] = true
	if def.boss_arena and def.has_surface:
		# Out of the beaten guardian's arena: straight up to the main entrance.
		li.portals.append({"id": &"arena_exit", "layer": li.layers.size() - 1, "kind": ARENA_EXIT, "to": &"main", "locked": true})
	li.save_portal = &"map" if def.has_surface else &"f1_up"
	return li


## The open land of a node's region (RegionData.surface_biomes), picked by
## the seed. `region` is the node's index on its map.
static func surface_biome_for(region: int, roll: int) -> StringName:
	var abs_region := region
	if GameState.run and GameState.run.map:
		abs_region += GameState.run.map.first_region
	var ids: Array[StringName] = [&"forest"]
	if abs_region >= 0 and abs_region < ItemDatabase.regions.size():
		var r: RegionData = ItemDatabase.regions[abs_region]
		if not r.surface_biomes.is_empty():
			ids = r.surface_biomes
	var id := StringName("surface_" + String(ids[absi(roll) % ids.size()]))
	return id if ItemDatabase.surface_biomes.has(id) else &"surface_forest"


func _link(a: StringName, layer_a: int, kind_a: StringName, b: StringName, layer_b: int, kind_b: StringName) -> void:
	portals.append({"id": a, "layer": layer_a, "kind": kind_a, "to": b, "locked": false})
	portals.append({"id": b, "layer": layer_b, "kind": kind_b, "to": a, "locked": false})


func portal(id: StringName) -> Dictionary:
	for p in portals:
		if StringName(p["id"]) == id:
			return p
	return {}


func portals_of(layer: int) -> Array:
	return portals.filter(func(p: Dictionary) -> bool: return int(p["layer"]) == layer)


func layer_id(layer: int) -> StringName:
	return StringName(layers[layer]["id"]) if layer >= 0 and layer < layers.size() else &""


func has_surface() -> bool:
	return not layers.is_empty() and int(layers[0]["kind"]) == Kind.SURFACE


func is_open(portal_id: StringName) -> bool:
	var p := portal(portal_id)
	if p.is_empty():
		return false
	if not bool(p.get("locked", false)):
		return true
	if StringName(p["kind"]) in [MAP, ARENA_EXIT] or int(layers[int(p["layer"])]["kind"]) == Kind.ARENA:
		return boss_beaten
	for l in state:
		if portal_id in (state[l] as Dictionary).get("opened", []):
			return true
	return false


## What changed in a layer (created on first use).
func layer_state(layer: int) -> Dictionary:
	var key := String(layer_id(layer))
	if not state.has(key):
		state[key] = {"chests": [], "dead": [], "traps": [], "tiles": [], "opened": [], "flags": {}}
	return state[key]


func floors() -> int:
	return layers.filter(func(l: Dictionary) -> bool: return int(l["kind"]) != Kind.SURFACE).size()


func to_dict() -> Dictionary:
	return {"type": node_type, "depth": depth, "biome": biome, "region": region, "seed": seed_value,
			"gen_seed": gen_seed, "play_seed": play_seed, "layers": layers.duplicate(true),
			"portals": portals.duplicate(true), "state": state.duplicate(true),
			"save_portal": save_portal, "save_pos": save_pos.duplicate(), "boss_beaten": boss_beaten}


static func from_dict(d: Dictionary) -> LocationInstance:
	if d.is_empty():
		return null
	var li := LocationInstance.new()
	li.node_type = StringName(d.get("type", &"level"))
	li.depth = int(d.get("depth", 1))
	li.biome = StringName(d.get("biome", &""))
	li.region = int(d.get("region", 0))
	li.seed_value = int(d.get("seed", 0))
	li.gen_seed = int(d.get("gen_seed", 0))
	li.play_seed = int(d.get("play_seed", 0))
	li.layers = (d.get("layers", []) as Array).duplicate(true)
	li.portals = (d.get("portals", []) as Array).duplicate(true)
	li.state = (d.get("state", {}) as Dictionary).duplicate(true)
	li.save_portal = StringName(d.get("save_portal", &""))
	li.save_pos = (d.get("save_pos", []) as Array).duplicate()
	li.boss_beaten = bool(d.get("boss_beaten", false))
	return li

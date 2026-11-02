class_name RegionData
extends Resource
## A region (act) of the expedition map: its lands (biomes), the depth range
## its locations scale to (every depth multiplier and loot table reads the
## node's depth), the length of the road and the guardian at its end.
## Add a .tres to data/regions/ to add a region (ordered by `order`).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var order: int = 0
## Biomes of the region, near → far (the road walks through them in order).
@export var biomes: Array[StringName] = []
## The open land above its dungeons (data/surface ids without "surface_"):
## a location's seed picks one of them.
@export var surface_biomes: Array[StringName] = [&"forest"]
## Depth of the first step and of the boss (the boss fights at depth_to).
@export var depth_from: int = 1
@export var depth_to: int = 5
## Steps on the road, the boss step included (6–8).
@export var steps_min: int = 6
@export var steps_max: int = 8
## Region boss (BossData.id) at the end of the road.
@export var boss: StringName
## Optional guardian lairs on the road (BossData ids): a side node with an
## arena fight and a better reward.
@export var lair_bosses: Array[StringName] = []
## Weights of the node types on the road (ExpeditionMap.TYPES keys).
@export var node_weights: Dictionary = {
	"level": 46, "elite": 12, "special": 8, "event": 16, "camp": 9, "rescue": 9,
}
## Ink of the region on the map.
@export var color: Color = Color(0.45, 0.32, 0.22)

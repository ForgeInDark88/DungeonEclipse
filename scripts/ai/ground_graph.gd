class_name GroundGraph
extends AStar2D
## Platformer navigation graph for walking monsters (built by LevelNav).
## Points are cells (id = y * width + x, position = cell coordinates) where a
## body can stand or climb. Every connection has a kind (LevelNav.Edge) and a
## cost; A* uses those instead of plain distance. Dangerous target cells add
## LevelNav.danger to the cost, forbidden ones are disabled points.

## key (from * KEY + to) -> cost
var edge_cost: Dictionary = {}
## key (from * KEY + to) -> LevelNav.Edge
var edge_kind: Dictionary = {}
## point id -> extra cost (traps nearby)
var extra: Dictionary = {}

const KEY := 1 << 20


func link(from: int, to: int, kind: int, cost: float) -> void:
	var k := from * KEY + to
	if edge_cost.has(k) and edge_cost[k] <= cost:
		return
	edge_cost[k] = cost
	edge_kind[k] = kind
	connect_points(from, to, false)


func kind_of(from: int, to: int) -> int:
	return edge_kind.get(from * KEY + to, -1)


func _compute_cost(from_id: int, to_id: int) -> float:
	return float(edge_cost.get(from_id * KEY + to_id, 1000.0)) + float(extra.get(to_id, 0.0))


func _estimate_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id))

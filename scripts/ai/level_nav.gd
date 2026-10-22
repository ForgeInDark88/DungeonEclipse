class_name LevelNav
extends RefCounted
## Navigation data of one floor, built from a LevelLayout once at generation
## and rebuilt (lazily, by DungeonLevel) when bricks break or ropes appear.
##
## Walkers: GroundGraph per body height (1 or 2 cells) with edges
##   WALK  — to the next cell on the same floor,
##   JUMP  — up to MAX_JUMP_UP cells up / MAX_JUMP_ACROSS across (arc checked),
##   FALL  — step off a ledge, at most MAX_FALL cells down (deeper = a pit),
##   DROP  — through a one-way platform,
##   CLIMB — along ladders and ropes.
## Flyers: AStarGrid2D over free cells (diagonals only past free corners).
## Dangers (traps): cells are forbidden (spikes, acid, plates — monsters never
## step on them, but may jump over) or get an extra cost (arrow lines, rocks).

enum Edge { WALK, JUMP, FALL, DROP, CLIMB }
enum Danger { NONE, COSTLY, FORBIDDEN }

const MAX_FALL := 6
const MAX_JUMP_UP := 3
const MAX_JUMP_ACROSS := 3
const T = LevelLayout.Tile
const EDGE_NAMES := ["walk", "jump", "fall", "drop", "climb"]

var layout: LevelLayout
## [clearance 1 graph, clearance 2 graph]
var graphs: Array[GroundGraph] = []
var fly := AStarGrid2D.new()
## cell -> [Danger, extra cost]
var dangers: Dictionary = {}
## Increases on every rebuild (paths computed earlier are outdated).
var version := 0


func _init(p_layout: LevelLayout) -> void:
	layout = p_layout
	rebuild()


func id_of(cell: Vector2i) -> int:
	return cell.y * layout.width + cell.x


func cell_of(id: int) -> Vector2i:
	return Vector2i(id % layout.width, id / layout.width)


# --------------------------------------------------------------- tiles
func passable(x: int, y: int) -> bool:
	var t := layout.get_tile(x, y)
	return layout.in_bounds(x, y) and not LevelLayout.is_solid(t)


## A body `clearance` cells tall fits with its feet in (x, y).
func fits(x: int, y: int, clearance: int) -> bool:
	for i in clearance:
		if not passable(x, y - i):
			return false
	return true


func standable(x: int, y: int, clearance: int = 1) -> bool:
	return fits(x, y, clearance) and LevelLayout.is_ground(layout.get_tile(x, y + 1))


func is_ladder(x: int, y: int) -> bool:
	return LevelLayout.is_ladder(layout.get_tile(x, y))


func is_node(x: int, y: int, clearance: int = 1) -> bool:
	return standable(x, y, clearance) or (is_ladder(x, y) and fits(x, y, 1))


# --------------------------------------------------------------- dangers
func set_danger(cell: Vector2i, level: int, cost: float = 0.0) -> void:
	var cur: Array = dangers.get(cell, [Danger.NONE, 0.0])
	dangers[cell] = [maxi(cur[0], level), cur[1] + cost]


func is_forbidden(cell: Vector2i) -> bool:
	return dangers.has(cell) and dangers[cell][0] == Danger.FORBIDDEN


func is_dangerous(cell: Vector2i) -> bool:
	return dangers.has(cell)


func _apply_dangers() -> void:
	for g in graphs:
		g.extra.clear()
	for cell: Vector2i in dangers:
		if not layout.in_bounds(cell.x, cell.y):
			continue
		var id := id_of(cell)
		var d: Array = dangers[cell]
		for g in graphs:
			if not g.has_point(id):
				continue
			if d[0] == Danger.FORBIDDEN:
				g.set_point_disabled(id, true)
			else:
				g.extra[id] = float(d[1])
		fly.set_point_weight_scale(cell, 1.0 + float(d[1]) * 0.3 + (8.0 if d[0] == Danger.FORBIDDEN else 0.0))


# --------------------------------------------------------------- building
func rebuild() -> void:
	graphs = [_build_ground(1), _build_ground(2)]
	_build_fly()
	_apply_dangers()
	version += 1


func _build_ground(clearance: int) -> GroundGraph:
	var g := GroundGraph.new()
	var w := layout.width
	var h := layout.height
	g.reserve_space(w * h / 2)
	for y in h:
		for x in w:
			if is_node(x, y, clearance):
				g.add_point(id_of(Vector2i(x, y)), Vector2(x, y))
	for y in h:
		for x in w:
			if not g.has_point(id_of(Vector2i(x, y))):
				continue
			var from := id_of(Vector2i(x, y))
			var stand := standable(x, y, clearance)
			# Ladders: up and down the shaft (both ways).
			for dy in [-1, 1]:
				var ny: int = y + dy
				if (is_ladder(x, y) or is_ladder(x, ny)) and g.has_point(id_of(Vector2i(x, ny))):
					g.link(from, id_of(Vector2i(x, ny)), Edge.CLIMB, 1.4)
			if not stand:
				continue
			for sx in [-1, 1]:
				var nx: int = x + sx
				# Walk to the neighbour or step off the ledge.
				if standable(nx, y, clearance):
					g.link(from, id_of(Vector2i(nx, y)), Edge.WALK, 1.0)
				elif fits(nx, y, clearance):
					for k in range(1, MAX_FALL + 1):
						if not fits(nx, y + k, clearance):
							break
						if standable(nx, y + k, clearance):
							g.link(from, id_of(Vector2i(nx, y + k)), Edge.FALL, 1.0 + k * 0.4)
							break
				_add_jumps(g, x, y, sx, clearance)
			# Drop through a one-way platform under the feet.
			if layout.get_tile(x, y + 1) == T.PLATFORM:
				for k in range(2, MAX_FALL + 2):
					if not fits(x, y + k, clearance):
						break
					if standable(x, y + k, clearance):
						g.link(from, id_of(Vector2i(x, y + k)), Edge.DROP, 1.5 + k * 0.4)
						break
	return g


## Jumps from (x, y) towards `sx`: up to MAX_JUMP_UP up, across gaps and
## over cells that must not be stepped on (traps). The arc must be free:
## rise in the start column, fly along the apex row, come down at the target.
func _add_jumps(g: GroundGraph, x: int, y: int, sx: int, clearance: int) -> void:
	for dy in range(-2, MAX_JUMP_UP + 1):
		for dx in range(1, MAX_JUMP_ACROSS + 1):
			if dx == 1 and dy <= 0:
				continue  # plain walking / falling covers these
			var tx := x + sx * dx
			var ty := y - dy
			if not standable(tx, ty, clearance):
				continue
			var apex := mini(y, ty) - 1
			if not _arc_free(x, y, tx, ty, apex, sx, clearance):
				continue
			g.link(id_of(Vector2i(x, y)), id_of(Vector2i(tx, ty)), Edge.JUMP, 2.0 + dx * 1.2 + maxi(dy, 0) * 0.8)


func _arc_free(x: int, y: int, tx: int, ty: int, apex: int, sx: int, clearance: int) -> bool:
	for yy in range(apex, y + 1):
		if not fits(x, yy, clearance):
			return false
	var cx := x
	while cx != tx:
		cx += sx
		if not fits(cx, apex, clearance):
			return false
	for yy in range(apex, ty + 1):
		if not fits(tx, yy, clearance):
			return false
	return true


func _build_fly() -> void:
	fly = AStarGrid2D.new()
	fly.region = Rect2i(0, 0, layout.width, layout.height)
	fly.cell_size = Vector2(1, 1)
	fly.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	fly.update()
	for y in layout.height:
		for x in layout.width:
			if LevelLayout.is_solid(layout.get_tile(x, y)):
				fly.set_point_solid(Vector2i(x, y), true)


# --------------------------------------------------------------- queries
func graph(clearance: int) -> GroundGraph:
	return graphs[clampi(clearance, 1, 2) - 1]


## Nearest usable node to `cell` (never a forbidden one).
func closest_node(cell: Vector2i, clearance: int) -> int:
	var g := graph(clearance)
	if g.has_point(id_of(cell)) and not g.is_point_disabled(id_of(cell)):
		return id_of(cell)
	if g.get_point_count() == 0:
		return -1
	return g.get_closest_point(Vector2(cell))


## Path for a walker: Array of {"cell": Vector2i, "kind": Edge} (first entry is
## the start). Empty when there is no way.
func ground_path(from: Vector2i, to: Vector2i, clearance: int) -> Array:
	var g := graph(clearance)
	var a := closest_node(from, clearance)
	var b := closest_node(to, clearance)
	if a < 0 or b < 0:
		return []
	var ids := g.get_id_path(a, b)
	var out := []
	for i in ids.size():
		var kind := Edge.WALK if i == 0 else g.kind_of(ids[i - 1], ids[i])
		out.append({"cell": cell_of(ids[i]), "kind": kind})
	return out


## Path for a flyer: cells from `from` to `to` (empty when unreachable).
func fly_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not fly.region.has_point(from) or not fly.region.has_point(to):
		return out
	if fly.is_point_solid(to):
		return out
	out.assign(fly.get_id_path(from, to, true))
	return out


## A safe standing cell near `cell` (anti-stuck teleport target).
func safe_cell_near(cell: Vector2i, clearance: int, exclude: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var g := graph(clearance)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in range(0, 6):
		for y in range(cell.y - r, cell.y + r + 1):
			for x in range(cell.x - r, cell.x + r + 1):
				var c := Vector2i(x, y)
				if c == exclude or not standable(x, y, clearance) or is_dangerous(c):
					continue
				if not g.has_point(id_of(c)) or g.is_point_disabled(id_of(c)):
					continue
				var d := Vector2(c).distance_to(Vector2(cell))
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return best

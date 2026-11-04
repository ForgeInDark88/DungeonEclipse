class_name LevelGenerator
extends RefCounted
## Spelunky-like procedural floor: a grid of rooms, a guaranteed path from a
## top room to a bottom room (left/right doorways and ladder shafts down),
## optional side rooms, sealed "secret" rooms that must be dug into,
## one-way platforms, brick pillars, chests and enemy spawn points.
## Everything that is not the outer border is diggable brick.

const ROOM_W := 18
const ROOM_H := 12
const T = LevelLayout.Tile

var rng := RandomNumberGenerator.new()
var cols: int
var rows: int
var layout: LevelLayout
var _connected: Dictionary = {}  # Vector2i room -> true
var _path: Array[Vector2i] = []
var _spots: Dictionary = {}  # Vector2i room -> Array[Vector2i]
var _used: Dictionary = {}
## Rooms taken by merchants / events: no chests or monsters there.
var _reserved: Dictionary = {}
var _secret_rooms: Dictionary = {}  # sealed rooms with a cracked secret wall into them
## Chance that a floor has a merchant room.
const MERCHANT_CHANCE := 0.4
## Chance that a floor has a blacksmith room.
const SMITH_CHANCE := 0.3
## Event rooms per floor: 1, sometimes 2.
const SECOND_EVENT_CHANCE := 0.4
## Chance of an ambush room on a floor (from floor 2).
const AMBUSH_CHANCE := 0.8
## Monster places per floor at most (squad companions come on top).
const MAX_MONSTERS := 30


## Flooded pits on the floors (BiomeData.flooded_pools; the caller sets it
## for the biome of the floor - the Drowned Vaults).
var flooded_pools := 0


func generate(floor_number: int, seed_value: int) -> LevelLayout:
	rng.seed = seed_value
	cols = clampi(3 + floor_number / 2, 3, 6)
	rows = clampi(2 + floor_number / 3, 2, 5)
	if GameState.expedition:
		# Expedition locations are short trips: one sweep to the exit.
		cols = clampi(3 + floor_number / 6, 3, 5)
		rows = clampi(2 + floor_number / 12, 2, 3)
	layout = LevelLayout.new(cols * ROOM_W + 1, rows * ROOM_H + 1, T.BRICK)
	_connected.clear()
	_path.clear()
	_spots.clear()
	_used.clear()
	_reserved.clear()
	_secret_rooms.clear()

	_make_border()
	for r in rows:
		for c in cols:
			_carve_room(c, r)
	_make_path()
	_connect_side_rooms()
	for r in rows:
		for c in cols:
			_decorate_room(Vector2i(c, r))
	for r in rows:
		for c in cols:
			_collect_spots(Vector2i(c, r))
	_place_start_and_exit()
	_place_specials(floor_number)
	_place_secret_walls()
	_place_chests(floor_number)
	_chests_within_reach()
	_place_enemies(floor_number)
	_place_lore()
	if flooded_pools > 0:
		_flood(seed_value)
	return layout


## Flooded basins: the bottom of a room between two walls fills with water
## two cells deep (layout.water). No tile changes - the paths of the floor
## stay as they are; monsters walk on the bottom, the hero swims. Never
## over the start or the exit, a chest, a special, the lore note or a
## ladder. Its own RNG: the rest of the floor stays the same.
func _flood(seed_value: int) -> void:
	var frng := RandomNumberGenerator.new()
	frng.seed = hash([seed_value, "flood"])
	var keep := {}
	for c in [layout.start_cell, layout.exit_cell, layout.lore_cell]:
		keep[c] = true
	for ch in layout.chests:
		keep[ch["cell"]] = true
	for sp in layout.specials:
		keep[sp["cell"]] = true
	var basins: Array = []
	for y in range(3, layout.height - 1):
		var x := 1
		while x < layout.width - 1:
			if not _wet(x, y):
				x += 1
				continue
			var x0 := x
			while x < layout.width - 1 and _wet(x, y):
				x += 1
			var x1 := x - 1
			var walled := LevelLayout.is_solid(layout.get_tile(x0 - 1, y - 1)) and LevelLayout.is_solid(layout.get_tile(x0 - 1, y - 2)) \
					and LevelLayout.is_solid(layout.get_tile(x1 + 1, y - 1)) and LevelLayout.is_solid(layout.get_tile(x1 + 1, y - 2))
			var clear := true
			for k in keep:
				var c: Vector2i = k
				if c.x >= x0 - 1 and c.x <= x1 + 1 and c.y >= y - 3 and c.y <= y:
					clear = false
			if walled and clear and x1 - x0 + 1 >= 3 and x1 - x0 + 1 <= 30:
				basins.append(Rect2i(x0, y - 2, x1 - x0 + 1, 2))
	for i in range(basins.size() - 1, 0, -1):
		var j := frng.randi_range(0, i)
		var tmp: Rect2i = basins[i]
		basins[i] = basins[j]
		basins[j] = tmp
	for r: Rect2i in basins.slice(0, flooded_pools):
		layout.water.append(r)


## A cell of a room's bottom that water could fill: floor under it, open
## water room (no ledge, no ladder) in it and above it.
func _wet(x: int, y: int) -> bool:
	return LevelLayout.is_solid(layout.get_tile(x, y)) and layout.get_tile(x, y - 1) == T.EMPTY \
			and layout.get_tile(x, y - 2) == T.EMPTY


## A road event's room: a short hall with a few ledges, the event's scenery
## in the middle (special "road_event" with the cells a fight would come
## from), in on the left, out on the right.
func generate_event_room(_floor_number: int, seed_value: int) -> LevelLayout:
	rng.seed = seed_value
	var w := 40
	var h := 14
	layout = LevelLayout.new(w, h, T.BRICK)
	_make_border()
	for y in range(1, h - 2):
		for x in range(1, w - 1):
			layout.set_tile(x, y, T.EMPTY)
	var fy := h - 2
	for seg in [[6, 10, fy - 4], [w - 11, w - 7, fy - 4], [w / 2 - 3, w / 2 + 2, fy - 7]]:
		for x in range(seg[0], seg[1] + 1):
			layout.set_tile(x, seg[2], T.PLATFORM)
	# a little unevenness of the floor
	for x in [3 + rng.randi() % 3, w - 5 - rng.randi() % 3]:
		layout.set_tile(x, fy - 1, T.BRICK)
	layout.start_cell = Vector2i(2, fy - 1)
	layout.exit_cell = Vector2i(w - 3, fy - 1)
	var cells: Array[Vector2i] = []
	for dx in [-9, 9, -12, 12, -6, 6]:
		cells.append(Vector2i(w / 2 + dx, fy - 1))
	layout.specials.append({"type": &"road_event", "cell": Vector2i(w / 2, fy - 1), "cells": cells})
	layout.is_event_room = true
	return layout


## Boss arena: one wide hall with platforms on two tiers.
func generate_arena(floor_number: int, seed_value: int) -> LevelLayout:
	rng.seed = seed_value
	var w := 46
	var h := 16
	layout = LevelLayout.new(w, h, T.BRICK)
	_make_border()
	for y in range(1, h - 2):
		for x in range(1, w - 1):
			layout.set_tile(x, y, T.EMPTY)
	var fy := h - 2  # floor row
	var boss := ItemDatabase.boss_for_floor(floor_number)
	var style: StringName = boss.arena_style if boss else &""
	var segs: Array = [[7, 12, fy - 4], [w - 13, w - 8, fy - 4], [w / 2 - 4, w / 2 + 3, fy - 7]]
	match style:
		&"pyre":
			# Lava pits under the witch; boards in three tiers to dodge the walls of fire.
			segs = [[4, 9, fy - 3], [w - 10, w - 5, fy - 3], [12, 17, fy - 6], [w - 18, w - 13, fy - 6], [w / 2 - 3, w / 2 + 2, fy - 9]]
			_pit(12, 17, fy, BossHazard.Style.LAVA)
			_pit(w - 18, w - 13, fy, BossHazard.Style.LAVA)
		&"mirrors":
			# A hall of small floating boards: the stage of the show.
			segs = []
			for row in [fy - 3, fy - 6, fy - 9]:
				var shift := 0 if row % 2 == 0 else 3
				for x0 in range(4 + shift, w - 6, 8):
					segs.append([x0, x0 + 3, row])
		&"crystal":
			# Crystal pillars to hide behind from the stalactites.
			for px in [13, w - 14]:
				for y in range(fy - 3, fy):
					layout.set_tile(px, y, T.BRICK)
			segs = [[5, 10, fy - 4], [w - 11, w - 6, fy - 4], [w / 2 - 5, w / 2 + 4, fy - 7]]
		&"flooded":
			# The floor is under water (slows), boards are the dry ground.
			segs = [[4, 11, fy - 3], [w - 12, w - 5, fy - 3], [w / 2 - 5, w / 2 + 4, fy - 5], [w / 2 - 2, w / 2 + 1, fy - 8]]
			layout.arena_hazards.append({"style": BossHazard.Style.WATER, "x0": 6, "x1": w - 7, "row": fy - 1, "h": 10.0, "damage": false})
		&"ashen":
			# Burnt hall: embers smoulder along the walls, the boards are broken.
			segs = [[5, 8, fy - 4], [11, 13, fy - 4], [w - 9, w - 6, fy - 4], [w - 14, w - 12, fy - 4], [w / 2 - 4, w / 2 + 3, fy - 7]]
			layout.arena_hazards.append({"style": BossHazard.Style.ASH, "x0": 2, "x1": 3, "row": fy - 1, "h": 12.0, "damage": true})
			layout.arena_hazards.append({"style": BossHazard.Style.ASH, "x0": w - 4, "x1": w - 3, "row": fy - 1, "h": 12.0, "damage": true})
		&"eclipse":
			# A void splits the arena; islands of boards float over it.
			_pit(w / 2 - 6, w / 2 + 5, fy, BossHazard.Style.VOID)
			segs = [[w / 2 - 5, w / 2 - 2, fy - 3], [w / 2 + 1, w / 2 + 4, fy - 3], [w / 2 - 2, w / 2 + 1, fy - 6],
					[6, 11, fy - 5], [w - 12, w - 7, fy - 5], [w / 2 - 9, w / 2 - 6, fy - 9], [w / 2 + 5, w / 2 + 8, fy - 9]]
		&"ossuary":
			# The Bone King's throne room: a raised dais in the middle, bone heaps.
			for x in range(w / 2 - 3, w / 2 + 3):
				layout.set_tile(x, fy - 1, T.BRICK)
			layout.arena_hazards.append({"style": BossHazard.Style.BONE, "x0": 5, "x1": 9, "row": fy - 1, "h": 8.0, "damage": false})
			layout.arena_hazards.append({"style": BossHazard.Style.BONE, "x0": w - 10, "x1": w - 6, "row": fy - 1, "h": 8.0, "damage": false})
	for seg in segs:
		for x in range(seg[0], seg[1] + 1):
			layout.set_tile(x, seg[2], T.PLATFORM)
	# Pillars at the walls so the boss cannot be cheesed in a corner.
	for y in range(fy - 2, fy):
		layout.set_tile(1, y, T.BRICK)
		layout.set_tile(w - 2, y, T.BRICK)
	layout.start_cell = Vector2i(4, fy - 1)
	layout.exit_cell = Vector2i(w - 5, fy - 1)
	layout.boss_cell = Vector2i(w / 2 + 6, fy - 1)
	layout.is_arena = true
	# The guardian's note lies near the entrance: read it before the fight.
	layout.lore_cell = layout.start_cell + Vector2i(3, 0)
	return layout


## Arena pit one tile deep with a lasting hazard at the bottom.
func _pit(x0: int, x1: int, fy: int, hazard: int) -> void:
	for x in range(x0, x1 + 1):
		layout.set_tile(x, fy, T.EMPTY)
	layout.arena_hazards.append({"style": hazard, "x0": x0, "x1": x1, "row": fy, "h": 12.0, "damage": true})


# ------------------------------------------------------------------ geometry
func _room_rect(room: Vector2i) -> Rect2i:
	# Interior cells (walls are shared between neighbours).
	return Rect2i(room.x * ROOM_W + 1, room.y * ROOM_H + 1, ROOM_W - 1, ROOM_H - 1)


func _floor_y(room: Vector2i) -> int:
	return (room.y + 1) * ROOM_H


func _make_border() -> void:
	for x in layout.width:
		layout.set_tile(x, 0, T.BEDROCK)
		layout.set_tile(x, layout.height - 1, T.BEDROCK)
	for y in layout.height:
		layout.set_tile(0, y, T.BEDROCK)
		layout.set_tile(layout.width - 1, y, T.BEDROCK)


func _carve_room(c: int, r: int) -> void:
	var rect := _room_rect(Vector2i(c, r))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			layout.set_tile(x, y, T.EMPTY)


## Doorway through the wall between room (c, r) and (c + 1, r).
func _connect_h(c: int, r: int) -> void:
	var x := (c + 1) * ROOM_W
	var fy := _floor_y(Vector2i(c, r))
	for y in range(fy - 4, fy):
		layout.set_tile(x, y, T.EMPTY)


## Ladder shaft from room (c, r) down into (c, r + 1).
func _connect_v(c: int, r: int) -> void:
	var rect := _room_rect(Vector2i(c, r))
	var hx := rng.randi_range(rect.position.x + 3, rect.end.x - 4)
	var fy := _floor_y(Vector2i(c, r))
	layout.set_tile(hx, fy, T.LADDER_TOP)
	for y in range(fy + 1, _floor_y(Vector2i(c, r + 1))):
		layout.set_tile(hx, y, T.LADDER)


func _make_path() -> void:
	var c := rng.randi_range(0, cols - 1)
	var r := 0
	var dir := -1 if rng.randf() < 0.5 else 1
	_path.append(Vector2i(c, r))
	_connected[Vector2i(c, r)] = true
	var guard := 0
	while guard < 200:
		guard += 1
		var go_down := rng.randf() >= 0.6
		if not go_down:
			var nc := c + dir
			if nc < 0 or nc >= cols or _path.has(Vector2i(nc, r)):
				dir = -dir
				nc = c + dir
				if nc < 0 or nc >= cols or _path.has(Vector2i(nc, r)):
					go_down = true
			if not go_down:
				_connect_h(mini(c, nc), r)
				c = nc
				_path.append(Vector2i(c, r))
				_connected[Vector2i(c, r)] = true
				continue
		if r == rows - 1:
			break
		_connect_v(c, r)
		r += 1
		dir = -1 if rng.randf() < 0.5 else 1
		_path.append(Vector2i(c, r))
		_connected[Vector2i(c, r)] = true


func _connect_side_rooms() -> void:
	for pass_i in 3:
		for r in rows:
			for c in cols:
				var room := Vector2i(c, r)
				if _connected.has(room):
					continue
				var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
				_shuffle(dirs)
				for d in dirs:
					var other := room + d
					if not _connected.has(other) or rng.randf() > 0.55:
						continue
					if d == Vector2i.LEFT:
						_connect_h(c - 1, r)
					elif d == Vector2i.RIGHT:
						_connect_h(c, r)
					elif d == Vector2i.UP:
						_connect_v(c, r - 1)
					else:
						_connect_v(c, r)
					_connected[room] = true
					break


func _decorate_room(room: Vector2i) -> void:
	var rect := _room_rect(room)
	var fy := _floor_y(room)
	# One-way platforms on two tiers (reachable with a jump).
	for i in rng.randi_range(1, 3):
		var tier := rng.randi_range(0, 1)
		var y := fy - (rng.randi_range(3, 4) if tier == 0 else rng.randi_range(6, 7))
		var length := rng.randi_range(3, 6)
		var x0 := rng.randi_range(rect.position.x + 1, rect.end.x - length - 1)
		for x in range(x0, x0 + length):
			if layout.get_tile(x, y) == T.EMPTY:
				layout.set_tile(x, y, T.PLATFORM)
	# Brick pillars: obstacles to jump over or dig through.
	for i in rng.randi_range(0, 2):
		var x := rng.randi_range(rect.position.x + 3, rect.end.x - 4)
		var h := rng.randi_range(1, 2)
		if _near_ladder(x, fy):
			continue
		for y in range(fy - h, fy):
			if layout.get_tile(x, y) == T.EMPTY:
				layout.set_tile(x, y, T.BRICK)


func _near_ladder(x: int, fy: int) -> bool:
	for dx in range(-1, 2):
		for y in range(fy - ROOM_H, fy + 1):
			if LevelLayout.is_ladder(layout.get_tile(x + dx, y)):
				return true
	return false


## Cells where a 1x2 thing can stand.
func _collect_spots(room: Vector2i) -> void:
	var rect := _room_rect(room)
	var list: Array[Vector2i] = []
	for y in range(rect.position.y + 1, rect.end.y):
		for x in range(rect.position.x + 1, rect.end.x - 1):
			if layout.get_tile(x, y) == T.EMPTY and layout.get_tile(x, y - 1) == T.EMPTY \
					and LevelLayout.is_ground(layout.get_tile(x, y + 1)) \
					and layout.get_tile(x, y + 1) != T.LADDER_TOP:
				list.append(Vector2i(x, y))
	_spots[room] = list


func _take_spot(room: Vector2i, prefer_floor := false) -> Variant:
	var list: Array = _spots.get(room, [])
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in list:
		if _used.has(cell) or _used.has(cell + Vector2i.LEFT) or _used.has(cell + Vector2i.RIGHT):
			continue
		if prefer_floor and cell.y != _floor_y(room) - 1:
			continue
		candidates.append(cell)
	if candidates.is_empty():
		return _take_spot(room, false) if prefer_floor else null
	var cell := candidates[rng.randi_range(0, candidates.size() - 1)]
	_used[cell] = true
	return cell


func _place_start_and_exit() -> void:
	var start: Variant = _take_spot(_path[0], true)
	layout.start_cell = start if start != null else _room_rect(_path[0]).get_center()
	var exit_room := _path[_path.size() - 1]
	var exit: Variant = _take_spot(exit_room, true)
	if exit == null:
		# Guarantee an exit: clear a spot on the room floor.
		var rect := _room_rect(exit_room)
		exit = Vector2i(rect.get_center().x, _floor_y(exit_room) - 1)
		layout.set_tile(exit.x, exit.y, T.EMPTY)
		layout.set_tile(exit.x, exit.y - 1, T.EMPTY)
	layout.exit_cell = exit


## A note of the chronicle in some room off the start (placed last, so the
## rest of the floor is laid out exactly as before).
func _place_lore() -> void:
	var rooms: Array[Vector2i] = []
	for room: Vector2i in _spots:
		if room != _path[0] and _connected.has(room):
			rooms.append(room)
	_shuffle(rooms)
	for room in rooms:
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.lore_cell = cell
			return


## Reserves side rooms for the merchant (and random events, see below).
func _place_specials(_floor_number: int) -> void:
	var floor_number_for_specials := _floor_number
	var rooms: Array[Vector2i] = []
	for room: Vector2i in _spots:
		if room != _path[0] and room != _path[_path.size() - 1] and _connected.has(room):
			rooms.append(room)
	_shuffle(rooms)
	# A rescue node: the prisoner's cage in the room before the exit, its
	# guards around it (DungeonLevel spawns them, RescueCage opens after).
	if GameState.location_type() == &"rescue" and GameState.location.get("band_last", true):
		var room: Vector2i = _path[maxi(1, _path.size() - 2)]
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			var guards: Array[Vector2i] = []
			for k in 4:
				var gc: Variant = _take_spot(room, true)
				if gc != null:
					guards.append(gc)
			layout.specials.append({"type": &"rescue", "cell": cell, "cells": guards})
			_reserved[room] = true
			rooms.erase(room)
	# The floor guardian: a champion in a room whose doors slam shut on entry.
	if not rooms.is_empty():
		var room: Vector2i = rooms.pop_back()
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.specials.append({"type": &"miniboss", "cell": cell, "room": _room_rect(room)})
			_reserved[room] = true
	# An ambush room (from floor 2): the doors slam, three waves, a relic altar.
	if floor_number_for_specials >= 2 and not rooms.is_empty() and rng.randf() < AMBUSH_CHANCE:
		var room: Vector2i = rooms.pop_back()
		var cells: Array[Vector2i] = []
		for k in 6:
			var c: Variant = _take_spot(room, true)
			if c != null:
				cells.append(c)
		if cells.size() >= 3:
			layout.specials.append({"type": &"ambush", "cell": cells[0], "room": _room_rect(room), "cells": cells})
			_reserved[room] = true
	if not rooms.is_empty() and rng.randf() < MERCHANT_CHANCE:
		var room: Vector2i = rooms.pop_back()
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.specials.append({"type": &"merchant", "cell": cell})
			_reserved[room] = true
	if not rooms.is_empty() and rng.randf() < SMITH_CHANCE:
		var room: Vector2i = rooms.pop_back()
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.specials.append({"type": &"smith", "cell": cell})
			_reserved[room] = true
	# Random event rooms (altar, fountain, cursed chest, puzzle, prisoner...).
	var events := 1 + (1 if rng.randf() < SECOND_EVENT_CHANCE else 0)
	for i in events:
		if rooms.is_empty():
			break
		var room: Vector2i = rooms.pop_back()
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.specials.append({"type": &"event", "cell": cell, "room": _room_rect(room), "roll": rng.randi()})
			_reserved[room] = true


func _place_chests(floor_number: int) -> void:
	var rooms: Array[Vector2i] = []
	for room: Vector2i in _spots:
		if room != _path[0] and not _reserved.has(room):
			rooms.append(room)
	_shuffle(rooms)
	# Fewer chests (was 2 + rooms / 3): finds should feel like finds.
	var count := 1 + (cols * rows) / 6 + int(GameState.location_mod("chests", 0))
	var placed := 0
	# Sealed (secret) rooms always hide a good chest, often a second one -
	# and greed is punished: a third of them are mimics.
	for room in rooms:
		if not _connected.has(room):
			for k in 2:
				var tier := 2 if rng.randf() < 0.5 else 1
				var mimic := rng.randf() < 0.3
				var extra := rng.randf() < 0.5
				if k == 1 and not extra:
					break
				var cell: Variant = _take_spot(room, true)
				if cell != null:
					# how the hero gets in: through a cracked secret wall, or only with a bomb
					layout.chests.append({"cell": cell, "tier": tier, "mimic": mimic,
							"entry": &"secret" if _secret_rooms.has(room) else &"bomb"})
	for room in rooms:
		if placed >= count:
			break
		if not _connected.has(room):
			continue
		var cell: Variant = _take_spot(room)
		if cell == null:
			continue
		var roll := rng.randf()
		var gold_chance := 0.06 + 0.02 * floor_number + float(GameState.location_mod("chest_tier", 0.0))
		var iron_chance := 0.22 + 0.03 * floor_number + float(GameState.location_mod("chest_tier", 0.0))
		var tier := 2 if roll < gold_chance else (1 if roll < gold_chance + iron_chance else 0)
		# From floor 3 a few ordinary chests bite back.
		var mimic_chance := (0.0 if floor_number < 3 else minf(0.04 + 0.01 * floor_number, 0.14)) \
				+ float(GameState.location_mod("mimic", 0.0))
		layout.chests.append({"cell": cell, "tier": tier, "mimic": rng.randf() < mimic_chance})
		placed += 1


## Secret rooms (rooms no corridor leads to): a cracked wall to a connected
## neighbour on the same row, 3 cells tall at the floor. A hit breaks it.
## No chest on a ledge the hero cannot jump to: one look at what the hero
## reaches (HeroReach, the secret walls taken as broken), and a chest out of
## reach moves to a reachable place of its room (or of the floor). Chests
## behind bomb-only walls stay where they are. No RNG: the floor is the same
## on every machine.
func _chests_within_reach() -> void:
	# only a chest on a ledge can be out of reach (the floors of the rooms
	# are joined): no ledge chest, no search (it costs ~0.2 s a floor)
	var on_ledge := false
	for ch in layout.chests:
		var c: Vector2i = ch["cell"]
		if ch.get("entry", &"") != &"bomb" and layout.get_tile(c.x, c.y + 1) != T.BRICK:
			on_ledge = true
			break
	if not on_ledge:
		return
	var open := LevelLayout.new(layout.width, layout.height)
	open.tiles = layout.tiles.duplicate()
	for wall in layout.secret_walls:
		for c: Vector2i in wall:
			open.set_tile(c.x, c.y, T.EMPTY)
	var reach := HeroReach.cells(open, layout.start_cell)
	for ch in layout.chests:
		if ch.get("entry", &"") == &"bomb" or reach.has(ch["cell"]):
			continue
		var old: Vector2i = ch["cell"]
		var room := Vector2i(old.x / ROOM_W, old.y / ROOM_H)
		var spot := _reachable_spot(room, reach)
		if spot == Vector2i(-1, -1):
			for r: Vector2i in _spots:
				spot = _reachable_spot(r, reach)
				if spot != Vector2i(-1, -1):
					break
		if spot != Vector2i(-1, -1):
			_used.erase(old)
			_used[spot] = true
			ch["cell"] = spot


func _reachable_spot(room: Vector2i, reach: Dictionary) -> Vector2i:
	for cell: Vector2i in _spots.get(room, []):
		if reach.has(cell) and not _used.has(cell) and not _used.has(cell + Vector2i.LEFT) and not _used.has(cell + Vector2i.RIGHT):
			return cell
	return Vector2i(-1, -1)


func _place_secret_walls() -> void:
	for r in rows:
		for c in cols:
			var room := Vector2i(c, r)
			if _connected.has(room):
				continue
			var sides: Array[int] = []
			if c > 0 and _connected.has(Vector2i(c - 1, r)):
				sides.append(c * ROOM_W)  # left wall
			if c < cols - 1 and _connected.has(Vector2i(c + 1, r)):
				sides.append((c + 1) * ROOM_W)  # right wall
			if sides.is_empty():
				continue  # only bombs get in here
			var x: int = sides[rng.randi_range(0, sides.size() - 1)]
			var fy := _floor_y(room)
			var wall: Array[Vector2i] = []
			for y in range(fy - 3, fy):
				if layout.get_tile(x, y) == T.BRICK:
					wall.append(Vector2i(x, y))
			if not wall.is_empty():
				layout.secret_walls.append(wall)
				_secret_rooms[room] = true


func _place_enemies(floor_number: int) -> void:
	var rooms: Array[Vector2i] = []
	for room: Vector2i in _spots:
		if room != _path[0] and _connected.has(room) and not _reserved.has(room):
			rooms.append(room)
	if rooms.is_empty():
		return
	# Pacing: fewer, tougher monsters gathered in lairs (packs of 3-5 in
	# some rooms), quiet rooms in between - fight, breathe, fight - instead
	# of a carpet of mobs to mow through (it was ~70 places on floor 22).
	var horde := (1.0 + EclipseLevels.value(GameState.eclipse_level, "monster_count")) \
			* float(GameState.location_mod("monsters", 1.0)) * Net.monster_count_mult()
	var per_depth := 0.5 if GameState.expedition else 0.75  # compact locations: fewer, not denser
	var count := mini(roundi(MAX_MONSTERS * horde), roundi((4 + roundi(floor_number * per_depth) + rooms.size() / 4) * horde))
	_shuffle(rooms)
	var lairs := rooms.slice(0, clampi(ceili(count / 4.0), 1, rooms.size()))
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 6:
		guard += 1
		var room: Vector2i = lairs[guard % lairs.size()]
		var cell: Variant = _take_spot(room)
		if cell != null:
			layout.enemy_cells.append(cell)
			placed += 1


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

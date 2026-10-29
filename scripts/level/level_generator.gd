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
## Chance that a floor has a merchant room.
const MERCHANT_CHANCE := 0.4
## Chance that a floor has a blacksmith room.
const SMITH_CHANCE := 0.3
## Event rooms per floor: 1, sometimes 2.
const SECOND_EVENT_CHANCE := 0.4
## Monster places per floor at most (squad companions come on top).
const MAX_MONSTERS := 30


func generate(floor_number: int, seed_value: int) -> LevelLayout:
	rng.seed = seed_value
	cols = clampi(3 + floor_number / 2, 3, 6)
	rows = clampi(2 + floor_number / 3, 2, 5)
	layout = LevelLayout.new(cols * ROOM_W + 1, rows * ROOM_H + 1, T.BRICK)
	_connected.clear()
	_path.clear()
	_spots.clear()
	_used.clear()
	_reserved.clear()

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
	_place_enemies(floor_number)
	_place_lore()
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
	var rooms: Array[Vector2i] = []
	for room: Vector2i in _spots:
		if room != _path[0] and room != _path[_path.size() - 1] and _connected.has(room):
			rooms.append(room)
	_shuffle(rooms)
	# The floor guardian: a champion in a room whose doors slam shut on entry.
	if not rooms.is_empty():
		var room: Vector2i = rooms.pop_back()
		var cell: Variant = _take_spot(room, true)
		if cell != null:
			layout.specials.append({"type": &"miniboss", "cell": cell, "room": _room_rect(room)})
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
	var count := 2 + (cols * rows) / 3
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
					layout.chests.append({"cell": cell, "tier": tier, "mimic": mimic})
	for room in rooms:
		if placed >= count:
			break
		if not _connected.has(room):
			continue
		var cell: Variant = _take_spot(room)
		if cell == null:
			continue
		var roll := rng.randf()
		var gold_chance := 0.06 + 0.02 * floor_number
		var iron_chance := 0.22 + 0.03 * floor_number
		var tier := 2 if roll < gold_chance else (1 if roll < gold_chance + iron_chance else 0)
		# From floor 3 a few ordinary chests bite back.
		var mimic_chance := 0.0 if floor_number < 3 else minf(0.04 + 0.01 * floor_number, 0.14)
		layout.chests.append({"cell": cell, "tier": tier, "mimic": rng.randf() < mimic_chance})
		placed += 1


## Secret rooms (rooms no corridor leads to): a cracked wall to a connected
## neighbour on the same row, 3 cells tall at the floor. A hit breaks it.
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
	var count := mini(MAX_MONSTERS, 4 + roundi(floor_number * 0.75) + rooms.size() / 4)
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

extends Node2D
## Rune puzzle room: a sealed treasure chest behind a magic barrier, three
## levers with runes and a tablet showing the right order. A wrong pull
## resets the levers (and zaps the hero a little).

const LEVER_SCENE := "res://scenes/events/lever.tscn"
const RUNE_SIZE := 8

var level: DungeonLevel
var order: Array[int] = []  # rune ids in the right order
var progress := 0
var levers: Array[Node] = []
var chest: Chest
var barrier: AnimatedSprite2D
var solved := false
## LAN co-op: deterministic puzzle identity across machines.
var net_seq := 0


static func _shuffled(arr: Array, rng: RandomNumberGenerator) -> void:
	# Array.shuffle() uses the global RNG and would diverge between machines.
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func setup_event(p_level: DungeonLevel, info: Dictionary) -> void:
	level = p_level
	var room: Rect2i = info["room"]
	var spots: Array[Vector2i] = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x + 1, room.end.x - 1):
			var c := Vector2i(x, y)
			if level.layout.get_tile(x, y) == LevelLayout.Tile.EMPTY and level.layout.get_tile(x, y + 1) == LevelLayout.Tile.BRICK \
					and absi(x - info["cell"].x) > 2:
				spots.append(c)
	# Same lever spots and rune order on every machine: seeded by the run.
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = hash([GameState.run_seed, level.floor_number, info["roll"], "puzzle"])
	_shuffled(spots, pick_rng)
	# Three levers far enough from each other.
	var chosen: Array[Vector2i] = []
	for s in spots:
		if chosen.all(func(o: Vector2i) -> bool: return absi(o.x - s.x) >= 3 or o.y != s.y):
			chosen.append(s)
		if chosen.size() == 3:
			break
	var runes := [0, 1, 2, 3]
	_shuffled(runes, pick_rng)
	for i in chosen.size():
		var lever: Node2D = (load(LEVER_SCENE) as PackedScene).instantiate()
		lever.rune = runes[i]
		lever.puzzle = self
		level.add_entity(lever, level.cell_bottom(chosen[i]))
		levers.append(lever)
		order.append(runes[i])
	_shuffled(order, pick_rng)


func _ready() -> void:
	add_to_group("puzzles")
	# Chest behind the barrier at this node's position.
	chest = (load("res://scenes/world/chest.tscn") as PackedScene).instantiate()
	chest.tier = 2
	chest.unlocked_by_default = true
	chest.sealed = true
	chest.floor_number = level.floor_number if level else 1
	add_child(chest)
	barrier = AnimatedSprite2D.new()
	AssetPaths.layout(AssetPaths.BARRIER_LAYOUT).apply_to(barrier, AssetPaths.tex(AssetPaths.BARRIER_SHEET))
	barrier.play(&"hum")
	barrier.scale = Vector2(1.6, 1.0)
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	barrier.material = m
	add_child(barrier)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(0.6, 0.4, 1.0)
	light.texture_scale = 0.5
	light.position = Vector2(0, -16)
	add_child(light)
	queue_redraw()


## Tablet above the barrier: the runes in the right order.
func _draw() -> void:
	if solved or order.is_empty():
		return
	var tex := AssetPaths.tex(AssetPaths.RUNES)
	var w := order.size() * (RUNE_SIZE + 2)
	draw_rect(Rect2(Vector2(-w / 2.0 - 2, -44), Vector2(w + 2, RUNE_SIZE + 4)), Color(0.15, 0.12, 0.18, 0.9))
	for i in order.size():
		draw_texture_rect_region(tex, Rect2(Vector2(-w / 2.0 + i * (RUNE_SIZE + 2), -42), Vector2(RUNE_SIZE, RUNE_SIZE)),
				Rect2(order[i] * RUNE_SIZE, 0, RUNE_SIZE, RUNE_SIZE))


func pull(lever: Node, player: Node) -> void:
	if solved:
		return
	if Net.active and not Net.is_host:
		# Guests ask the host; the verdict comes back as puzzle_state.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_puzzle_pull.rpc_id(1, net_seq, levers.find(lever))
		return
	if lever.rune == order[progress]:
		progress += 1
		lever.set_down(true)
		AudioManager.play_sfx(&"ui_equip", lever.global_position)
		if progress == order.size():
			_solve()
	else:
		EventBus.message.emit("Руны вспыхивают — не тот порядок!")
		AudioManager.play_sfx(&"chest_locked", lever.global_position)
		player.take_damage(5, lever.global_position, WeaponItemData.DamageType.MAGIC)
		progress = 0
		for l in levers:
			l.set_down(false)
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.puzzle_state.rpc(net_seq, progress, solved)


## Host's verdict applied on guests (and in the late-join snapshot).
func net_apply(prog: int, solved_: bool) -> void:
	progress = prog
	for l in levers:
		l.set_down(solved_ or order.find(l.rune) < prog)
	if solved_ and not solved:
		_solve()


func _solve() -> void:
	solved = true
	chest.sealed = false
	EventBus.message.emit("Барьер рассеивается!")
	AudioManager.play_sfx(&"portal", global_position)
	Fx.sparks(get_parent(), global_position + Vector2(0, -16), Color(0.7, 0.5, 1.0), 30, 100.0)
	var tw := create_tween()
	tw.tween_property(barrier, "modulate:a", 0.0, 0.6)
	tw.tween_callback(barrier.queue_free)
	queue_redraw()

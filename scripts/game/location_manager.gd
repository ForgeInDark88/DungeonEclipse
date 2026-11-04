class_name LocationManager
extends Node
## The layers of the current location (game.gd adds it when the location
## has a LocationInstance):
## - the portals between the layers: a fade, the hero moves to the other
##   end, the camera, light, background and music of the new layer;
## - the save points: going through a portal saves the expedition there
##   (the host / single player), a load puts the hero back at that portal;
## - what changed in each layer (LocationInstance.state): captured for the
##   save, applied when the location is rebuilt from its seed;
## - the host simulates only the layers with a hero in them: the monsters of
##   empty layers sleep (process off) and their state is not sent;
## - ordinary surface monsters come back after a while, never near a hero
##   (LocationDefinition respawn rules);
## - co-op: Shift+E at a portal calls the party through it; a guest's call
##   needs the host's yes (F2).

const FADE := 0.22
const TICK := 0.5

var instance: LocationInstance
var definition: LocationDefinition
var game: Node
var level: DungeonLevel
## Local hero's band (-1 before placement).
var band := -1
var _portals: Dictionary = {}  # portal id -> LayerPortal
## Spawned monsters of the build: loc id -> {node, band, cell, data, elite}.
var _tracked: Dictionary = {}
var _dead: Dictionary = {}  # loc id -> true
## Respawns waiting: [{data, cell, band, left, count}].
var _respawns: Array = []
var _respawn_count: Dictionary = {}  # cell -> returns so far
var _tick := 0.0
var _busy := false
var _fade: ColorRect
var _rng := RandomNumberGenerator.new()
## A guest's call of the party waiting for the host: [peer, portal id].
var _pull_request: Array = []
## Time of day and weather over the surface (null without a surface).
var sky: SurfaceSky
var life: SurfaceLife
var grass: GrassField


func _init() -> void:
	name = "LocationManager"


func _ready() -> void:
	add_to_group("location_manager")
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


## After the level is built: portals, the saved state, the hero's place.
func setup(p_game: Node, p_level: DungeonLevel, li: LocationInstance) -> void:
	game = p_game
	level = p_level
	instance = li
	definition = ItemDatabase.locations.get(li.node_type)
	_rng.seed = li.play_seed
	for p in li.portals:
		var pid := StringName(p["id"])
		if not level.layout.portal_cells.has(pid):
			continue
		var lp := LayerPortal.new()
		lp.portal_id = pid
		lp.kind = StringName(p["kind"])
		lp.manager = self
		lp.look = StringName(level.layout.portal_kinds.get(pid, &""))
		level.add_entity(lp, level.cell_bottom(level.layout.portal_cells[pid]))
		_portals[pid] = lp
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and en.has_meta(&"loc"):
			_tracked[int(en.get_meta(&"loc"))] = {"node": en, "band": level.band_index_at(en.global_position),
					"pos": en.global_position, "data": en.data, "elite": en.elite != null or en.champion or en is Boss}
	apply_state()
	var sb := level.layout_band(0).get("biome") as SurfaceBiomeData if li.has_surface() else null
	if sb:
		sky = SurfaceSky.new()
		add_child(sky)
		sky.setup(sb, li.play_seed, game.get_node_or_null("Ambient") as CanvasModulate, game.player.camera)
		# small life and the grass of the surface (decoration, every machine its own)
		life = SurfaceLife.new()
		level.add_child(life)
		life.setup(level, 0, sky, li.play_seed)
		grass = GrassField.new()
		level.add_child(grass)
		grass.setup(level, 0, sb.grass_color, sb.grass_density, li.play_seed + 1)


## The hero stands at the last save point (the start of the surface on a
## fresh location).
func place_player(player: Node2D) -> void:
	var pid := instance.save_portal
	var pos: Vector2 = level.start_position()
	if instance.save_pos.size() == 2:
		pos = Vector2(float(instance.save_pos[0]) + 12.0, float(instance.save_pos[1]))
	elif level.layout.portal_cells.has(pid):
		pos = level.cell_bottom(level.layout.portal_cells[pid]) + Vector2(14, 0)
	player.global_position = pos
	_enter_band(level.band_index_at(pos), true)


# ------------------------------------------------------------------ portals
func portal_open(pid: StringName) -> bool:
	return instance.is_open(pid)


func portal_prompt(pid: StringName) -> String:
	var p := instance.portal(pid)
	var kind := StringName(p.get("kind", &""))
	if not portal_open(pid):
		if kind == LocationInstance.MAP:
			return tr("Дорога закрыта: сначала одолейте стража")
		match StringName(p.get("lock", &"")):
			&"key":
				return tr("Решётка заперта: нужен ключ") + (tr(" · E — отпереть") if _hero_has(&"key") else "")
			&"rubble":
				return tr("Завал: нужна кирка или бомба") + (tr(" · E — разобрать") if _hero_has(&"pickaxe") or _hero_has(&"bomb") else "")
			&"below":
				return tr("Подъёмник поднят: его можно спустить только снизу")
		return tr("Пути нет, пока жив страж")
	var to := instance.portal(StringName(p.get("to", &"")))
	var where := _layer_name(int(to.get("layer", 0))) if not to.is_empty() else ""
	var text := ""
	match kind:
		LocationInstance.MAP:
			text = tr("На карту похода")
			if Net.world_session:
				var ns := get_tree().get_first_node_in_group("net_game") as NetSync
				if ns:
					var c := ns.party_count_at(_portals[pid].global_position)
					text += tr(" · отряд здесь: %d из %d") % [c.x, c.y]
			return text
		LocationInstance.ENTRANCE:
			text = tr("Спуститься в подземелье: %s") % where
		LocationInstance.SIDE:
			text = tr("Боковой лаз вниз: %s") % where
		LocationInstance.DOWN:
			text = tr("Спуститься: %s") % where
		LocationInstance.UP:
			text = tr("Подняться: %s") % where
		LocationInstance.ARENA_EXIT:
			text = tr("Подняться на поверхность")
		LocationInstance.LIFT:
			text = tr("Подъёмник наверх: %s") % where
		LocationInstance.LIFT_TOP:
			text = tr("Подъёмник вниз: %s") % where
	if Net.active and Net.players.size() > 1:
		text += tr(" · Shift+E — позвать отряд")
	return text


func _layer_name(i: int) -> String:
	if i < 0 or i >= instance.layers.size():
		return ""
	var l: Dictionary = instance.layers[i]
	if l.has("special"):
		return {&"treasury": tr("сокровищница"), &"mine": tr("старая шахта"), &"cache": tr("тайник")}.get(StringName(l["special"]), tr("тайник"))
	match int(l["kind"]):
		LocationInstance.Kind.SURFACE:
			return tr("поверхность")
		LocationInstance.Kind.ARENA:
			return tr("логово стража")
	var first := 1 if instance.has_surface() else 0
	return tr("этаж %d") % (i - first + 1)


func use_portal(pid: StringName, player: Node, call_party := false) -> void:
	if _busy:
		return
	if not portal_open(pid):
		if not _try_unlock(pid):
			EventBus.message.emit(portal_prompt(pid))
			AudioManager.play_sfx(&"chest_locked")
		return
	var p := instance.portal(pid)
	if StringName(p["kind"]) == LocationInstance.LIFT:
		# found from below: the lift stays down for everybody
		open_lock(StringName(p["to"]), true)
	if StringName(p["kind"]) == LocationInstance.MAP:
		_leave_to_map()
		return
	var to := StringName(p["to"])
	if call_party and Net.active:
		request_pull(to)
		return
	travel(to)


# ------------------------------------------------------------------ locks
func _hero_has(id: StringName) -> bool:
	var hero: Hero = GameState.hero
	return hero != null and hero.inventory.count_of(id) > 0


## A key opens the grate (and is spent), a pickaxe clears the rubble (a bomb
## too, spent). The lock opens for the whole party (the host keeps it).
func _try_unlock(pid: StringName) -> bool:
	var p := instance.portal(pid)
	var hero: Hero = GameState.hero
	match StringName(p.get("lock", &"")):
		&"key":
			if not _hero_has(&"key"):
				return false
			hero.inventory.remove_by_id(&"key", 1)
			EventBus.message.emit(tr("Ключ подошёл: решётка открыта."))
		&"rubble":
			if _hero_has(&"pickaxe"):
				EventBus.message.emit(tr("Вы разобрали завал киркой."))
			elif _hero_has(&"bomb"):
				hero.inventory.remove_by_id(&"bomb", 1)
				Fx.explosion(level.entities, _portals[pid].global_position + Vector2(0, -10), 30.0, Color(1, 0.6, 0.2))
				EventBus.message.emit(tr("Бомба расчистила завал."))
			else:
				return false
		_:
			return false
	AudioManager.play_sfx(&"dig", _portals[pid].global_position)
	open_lock(pid, true)
	return true


## Marks a lock open here and (host / guest) across the party.
func open_lock(pid: StringName, announce: bool) -> void:
	if instance.is_unlocked(pid):
		return
	instance.unlock(pid)
	if _portals.has(pid):
		_portals[pid].refresh()
	if StringName(instance.portal(pid).get("lock", &"")) == &"below" and announce:
		EventBus.message.emit(tr("Найден короткий путь: подъёмник на поверхность."))
	if announce and Net.active:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			if Net.is_host:
				Net.send(ns, &"lock_opened", [pid])
			else:
				ns.lock_opened_request.rpc_id(1, pid)


## The local hero goes to portal `to` (another layer): fade, move, save.
func travel(to: StringName) -> void:
	if _busy or not level.layout.portal_cells.has(to):
		return
	var player: Player = game.player
	if player == null or player.dead:
		return
	_busy = true
	AudioManager.play_sfx(&"portal")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE)
	await tw.finished
	if not is_instance_valid(level):
		return
	var pos := level.cell_bottom(level.layout.portal_cells[to]) + Vector2(14, 0)
	player.global_position = pos
	player.velocity = Vector2.ZERO
	for pet in get_tree().get_nodes_in_group("pets"):
		(pet as Node2D).global_position = pos + Vector2(-10, -4)
	_enter_band(level.band_index_at(pos))
	# A save point: the host's (or the lone hero's) expedition is saved here.
	if not GameFlow.is_guest():
		instance.save_portal = to
		instance.save_pos = []
		save_point()
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, FADE)
	await tw.finished
	_busy = false


func _leave_to_map() -> void:
	if GameState.expedition and Net.world_session:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			if Net.is_host:
				ns.host_party_move(Net.multiplayer.get_unique_id(), &"exit")
			else:
				ns.request_floor.rpc_id(1, &"exit")
		return
	if game and game.has_method("finish_location"):
		game.finish_location()
	else:
		GameFlow.location_cleared()


## The local hero's layer changed: camera bounds, light, background, music.
func _enter_band(i: int, first := false) -> void:
	if i < 0:
		return
	var changed := i != band
	band = i
	var b := level.layout_band(i)
	var player: Player = game.player
	if player:
		player.set_camera_rect(level.band_rect_px(player.global_position))
	GameState.floor_number = int(b["depth"])
	if game.has_method("apply_layer_biome"):
		game.apply_layer_biome(b["biome"])
	if sky:
		sky.set_active(int(b["kind"]) == LocationInstance.Kind.SURFACE)
	if life:
		life.active = i == 0
	if grass:
		grass.active = i == 0
	if int(b["kind"]) == LocationInstance.Kind.ARENA and not instance.boss_beaten:
		for boss in get_tree().get_nodes_in_group("bosses"):
			AudioManager.play_music((boss as Boss).boss.music)
	if changed or first:
		EventBus.message.emit(_layer_title(i))
		EventBus.floor_changed_quiet.emit(GameState.floor_number)


func _layer_title(i: int) -> String:
	var b := level.layout_band(i)
	var bd: BiomeData = b["biome"]
	var name := _layer_name(i)
	return "%s · %s" % [name.capitalize(), bd.display_name if bd else ""]


# ------------------------------------------------------------- the party
## Shift+E: everybody goes through. The host calls at once; a guest asks
## the host (F2 agrees).
func request_pull(to: StringName) -> void:
	if Net.is_host:
		_pull(to)
		return
	var ns := get_tree().get_first_node_in_group("net_game") as NetSync
	if ns:
		ns.request_pull.rpc_id(1, to)
	EventBus.message.emit(tr("Вы зовёте отряд. Ждём согласия хоста…"))


## Host: a guest wants the party at portal `to`.
func on_pull_request(peer: int, to: StringName) -> void:
	if not level.layout.portal_cells.has(to):
		return
	_pull_request = [peer, to]
	var nick := String(Net.players.get(peer, {}).get("name", tr("Игрок")))
	EventBus.message.emit(tr("%s зовёт отряд: %s. F2 — согласиться.") % [nick, _layer_name(int(instance.portal(to).get("layer", 0)))])


func _unhandled_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F2 and Net.is_host and not _pull_request.is_empty():
		var to: StringName = _pull_request[1]
		_pull_request = []
		_pull(to)
		get_viewport().set_input_as_handled()


func _pull(to: StringName) -> void:
	var ns := get_tree().get_first_node_in_group("net_game") as NetSync
	if ns:
		Net.send(ns, &"pull_party", [to])
	travel(to)


# ------------------------------------------------------------------ state
## What changed, into instance.state (before a save).
func capture_state() -> void:
	for i in instance.layers.size():
		var st := instance.layer_state(i)
		st["chests"] = []
		st["dead"] = []
		st["traps"] = []
		st["tiles"] = []
	for c in get_tree().get_nodes_in_group("chests"):
		if c.opened and c.has_meta(&"loc"):
			instance.layer_state(_band_of(c)).get("chests").append(int(c.get_meta(&"loc")))
	for t in get_tree().get_nodes_in_group("traps"):
		if t.disarmed and t.has_meta(&"loc"):
			instance.layer_state(_band_of(t)).get("traps").append(int(t.get_meta(&"loc")))
	if instance.has_surface():
		(instance.layer_state(0)["flags"] as Dictionary)["found"] = _found.keys()
	# the surface: what was gathered and smashed (the saving machine's own)
	for i in instance.layers.size():
		instance.layer_state(i)["gathered"] = []
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if r.has_meta(&"loc") and r.charges < int(ResourceNode.KINDS[r.kind]["charges"]):
			instance.layer_state(_band_of(r))["gathered"].append([int(r.get_meta(&"loc")), r.charges])
	for b in get_tree().get_nodes_in_group("breakables"):
		if b.has_meta(&"loc") and b.broken:
			instance.layer_state(_band_of(b))["gathered"].append([int(b.get_meta(&"loc")), 0])
	_scan_dead()
	for id in _dead:
		var info: Dictionary = _tracked.get(id, {})
		if not info.is_empty() and _keeps_dead(info):
			instance.layer_state(int(info["band"])).get("dead").append(id)
	var seen := {}
	for cell in level.changed_cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		var bi := level.band_index_at_cell(cell)
		if bi >= 0:
			instance.layer_state(bi).get("tiles").append([cell.x, cell.y, level.layout.get_tile(cell.x, cell.y)])
	GameState.location["instance"] = instance.to_dict()


## The saved state onto the freshly built location.
func apply_state() -> void:
	var chests := {}
	var traps := {}
	var dead := {}
	for key in instance.state:
		var st: Dictionary = instance.state[key]
		for id in st.get("chests", []):
			chests[int(id)] = true
		for id in st.get("traps", []):
			traps[int(id)] = true
		for id in st.get("dead", []):
			dead[int(id)] = true
		for t in st.get("tiles", []):
			level.apply_remote_tile(Vector2i(int(t[0]), int(t[1])), int(t[2]))
	for c in get_tree().get_nodes_in_group("chests"):
		if c.has_meta(&"loc") and chests.has(int(c.get_meta(&"loc"))) and not c.opened:
			c.opened = true
			c.locked = false
			c.sprite.play(&"open")
	for t in get_tree().get_nodes_in_group("traps"):
		if t.has_meta(&"loc") and traps.has(int(t.get_meta(&"loc"))) and not t.disarmed:
			t._apply_disarmed()
	if instance.has_surface():
		for i in (instance.layer_state(0)["flags"] as Dictionary).get("found", []):
			_found[int(i)] = true
	var gathered := {}
	for key in instance.state:
		for g in (instance.state[key] as Dictionary).get("gathered", []):
			gathered[int(g[0])] = int(g[1])
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if r.has_meta(&"loc") and gathered.has(int(r.get_meta(&"loc"))):
			r.charges = gathered[int(r.get_meta(&"loc"))]
			if r.charges <= 0:
				r._spent()
	for b in get_tree().get_nodes_in_group("breakables"):
		if b.has_meta(&"loc") and gathered.has(int(b.get_meta(&"loc"))):
			b.broken = true
			b.remove_from_group("interactable")
			b.modulate.a = 0.0
	for id in dead:
		_dead[id] = true
		var info: Dictionary = _tracked.get(id, {})
		if not info.is_empty() and is_instance_valid(info["node"]):
			var n: Node = info["node"]
			n.remove_from_group("enemies")
			n.queue_free()
	for lp in _portals.values():
		lp.refresh()


func _band_of(n: Node) -> int:
	return maxi(0, level.band_index_at((n as Node2D).global_position))


## Does a fallen monster stay dead in the save? Ordinary surface monsters
## come back (respawn rules); everyone else stays down.
func _keeps_dead(info: Dictionary) -> bool:
	return info["elite"] or not _respawns_here(int(info["band"]))


func _respawns_here(bi: int) -> bool:
	if definition == null or definition.respawn_max <= 0:
		return false
	var kind := int(level.layout_band(bi).get("kind", 0))
	return kind == LocationInstance.Kind.SURFACE or (definition.respawn_in_dungeon and kind == LocationInstance.Kind.DUNGEON)


## «Сохранить и выйти»: at the fire the hero sits by, else the nearest portal.
func save_where_standing(player: Node2D) -> void:
	for f in get_tree().get_nodes_in_group("camp_fires"):
		if (f as Node2D).global_position.distance_to(player.global_position) < 64.0:
			save_at_fire((f as Node2D).global_position)
			return
	instance.save_portal = nearest_portal(player)
	instance.save_pos = []
	save_point()


## A camp fire of the surface: the save point is the fire itself.
func save_at_fire(pos: Vector2) -> void:
	instance.save_pos = [pos.x, pos.y]
	save_point()


## Save point: the expedition with this location's state.
func save_point() -> void:
	capture_state()
	GameFlow.save_expedition("location")


## «Сохранить и выйти» is allowed here: next to a portal of the location (a
## way in or out, the road sign) or a camp fire, with no monster close by.
func at_safe_spot(player: Node2D) -> bool:
	if player == null:
		return false
	var near := false
	for lp in _portals.values():
		if lp.global_position.distance_to(player.global_position) < 64.0:
			near = true
	for f in get_tree().get_nodes_in_group("camp_fires"):
		if (f as Node2D).global_position.distance_to(player.global_position) < 64.0:
			near = true
	if not near:
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and not en.is_dead() and en.global_position.distance_to(player.global_position) < 200.0:
			return false
	return true


## Before «Сохранить и выйти»: the hero comes back to the nearest portal.
func nearest_portal(player: Node2D) -> StringName:
	var best := instance.save_portal
	var best_d := INF
	for pid in _portals:
		var d: float = (_portals[pid] as Node2D).global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = pid
	return best


# ---------------------------------------------------------- the guardian
func on_boss_beaten() -> void:
	instance.boss_beaten = true
	for lp in _portals.values():
		lp.refresh()
	EventBus.message.emit(tr("Страж повержен! Путь наверх открыт."))
	if not GameFlow.is_guest():
		save_point()


# ------------------------------------------------------- the host's world
func _process(delta: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var player: Player = game.player
	if player and not _busy:
		var bi := level.band_index_at(player.global_position)
		if bi >= 0 and bi != band:
			_enter_band(bi)  # fell or was pulled through
		_discover(player)
	if GameFlow.is_guest() or (Net.active and not Net.is_host):
		return
	var active := active_bands()
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null:
			continue
		var on := level.band_index_at(en.global_position) in active
		var mode := Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if en.process_mode != mode:
			en.process_mode = mode
	_scan_dead()
	_step_respawns(TICK)
	_step_night()


## Every hero of the party (alone: just this machine's, the co-op party
## list is empty without a network).
func _heroes() -> Array:
	var list: Array = game.party() if game.has_method("party") else []
	if list.is_empty() and game.player:
		list = [game.player]
	return list


## Bands with a living hero in them (the host simulates only these).
func active_bands() -> Array[int]:
	var out: Array[int] = []
	for p in _heroes():
		var pl := p as Player
		if pl and is_instance_valid(pl):
			var bi := level.band_index_at(pl.global_position)
			if bi >= 0 and not bi in out:
				out.append(bi)
	return out


func _scan_dead() -> void:
	for id in _tracked:
		if _dead.has(id):
			continue
		var info: Dictionary = _tracked[id]
		var n = info["node"]
		if not is_instance_valid(n) or (n as Enemy).is_dead():
			_dead[id] = true
			if not info["elite"] and _respawns_here(int(info["band"])):
				var key: Vector2 = info["pos"]
				if int(_respawn_count.get(key, 0)) < definition.respawn_max:
					_respawns.append({"data": info["data"], "pos": key, "band": info["band"],
							"left": definition.respawn_time * _rng.randf_range(0.8, 1.2)})


# ----------------------------------------------------------- discoveries
const POI_NAMES := {
	&"bandit_camp": "Лагерь бандитов", &"shrine": "Святилище", &"tower": "Разрушенная башня",
	&"cart": "Повозка торговца", &"graveyard": "Старое кладбище", &"well": "Заброшенный колодец",
	&"hunters": "Стоянка охотников", &"stranger": "Костёр странника",
}
var _found: Dictionary = {}


## The hero comes near a point of interest of the surface: it is found
## (a line on the screen; the town's scouts learn of it on a safe return).
func _discover(player: Node2D) -> void:
	var b := level.layout_band(0)
	if b.is_empty() or int(b["kind"]) != LocationInstance.Kind.SURFACE:
		return
	var sub: LevelLayout = b["layout"]
	for i in sub.pois.size():
		if _found.has(i):
			continue
		var poi: Dictionary = sub.pois[i]
		var pos := level.cell_bottom((poi["cell"] as Vector2i) + (b["origin"] as Vector2i))
		if pos.distance_to(player.global_position) < 90.0:
			_found[i] = true
			var kind := StringName(poi["type"])
			EventBus.message.emit(tr("Найдено место: %s") % tr(POI_NAMES.get(kind, String(kind))))
			EventBus.place_discovered.emit(kind)
			if GameState.run and not GameFlow.is_guest():
				var places: Array = GameState.run.flags.get("places", [])
				places.append(String(kind))
				GameState.run.flags["places"] = places


# ------------------------------------------------------- night creatures
const NIGHT_COUNT := Vector2i(4, 7)
var _night_out := false
var _night_foes: Array[Enemy] = []


## Host: at nightfall the night creatures of the biome come out on the
## surface (far from every hero); at dawn the ones nobody is near fade.
func _step_night() -> void:
	if sky == null:
		return
	var night := sky.is_night()
	if night and not _night_out:
		_night_out = true
		_spawn_night()
	elif not night and _night_out:
		_night_out = false
		for e in _night_foes:
			if is_instance_valid(e) and not e.is_dead() and not _hero_near(e.global_position, 300.0):
				e.remove_from_group("enemies")
				var ns := get_tree().get_first_node_in_group("net_game") as NetSync
				if ns and Net.active:
					ns.enemies.erase(e.net_id)
					Net.send(ns, &"enemy_gone", [e.net_id])
				e.queue_free()
		_night_foes.clear()


func _spawn_night() -> void:
	var b := level.layout_band(0)
	if b.is_empty() or int(b["kind"]) != LocationInstance.Kind.SURFACE:
		return
	var sb: BiomeData = b["biome"]
	var pool := ItemDatabase.enemies_for_floor(int(b["depth"]), sb.id, true)
	if pool.is_empty():
		return
	var sub: LevelLayout = b["layout"]
	var origin: Vector2i = b["origin"]
	var cells: Array[Vector2i] = sub.enemy_cells.duplicate()
	for i in cells.size():
		var j := _rng.randi_range(0, cells.size() - 1)
		var t := cells[i]
		cells[i] = cells[j]
		cells[j] = t
	var want := _rng.randi_range(NIGHT_COUNT.x, NIGHT_COUNT.y)
	for c in cells:
		if _night_foes.size() >= want:
			break
		var pos := level.cell_bottom(c + origin)
		if _hero_near(pos, definition.respawn_min_distance if definition else 360.0):
			continue
		var e := level.spawn_enemy_at(pool[_rng.randi_range(0, pool.size() - 1)], pos)
		if e:
			_night_foes.append(e)
	if not _night_foes.is_empty():
		EventBus.message.emit(tr("Из темноты выходят ночные твари."))


func _hero_near(pos: Vector2, dist: float) -> bool:
	for p in _heroes():
		if is_instance_valid(p) and (p as Node2D).global_position.distance_to(pos) < dist:
			return true
	return false


func _step_respawns(dt: float) -> void:
	for r in _respawns.duplicate():
		r["left"] = float(r["left"]) - dt
		if float(r["left"]) > 0.0:
			continue
		var pos: Vector2 = r["pos"]
		var near := false
		for p in _heroes():
			if is_instance_valid(p) and (p as Node2D).global_position.distance_to(pos) < definition.respawn_min_distance:
				near = true
		if near:
			r["left"] = 5.0  # later, when nobody is looking
			continue
		_respawns.erase(r)
		var e := level.spawn_enemy_at(r["data"], pos)
		if e:
			_respawn_count[pos] = int(_respawn_count.get(pos, 0)) + 1
			_tracked[int(e.get_meta(&"loc"))] = {"node": e, "band": r["band"], "pos": pos, "data": r["data"], "elite": false}

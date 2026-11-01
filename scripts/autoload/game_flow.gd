extends Node
## The loop of the game as a state machine:
##   MAIN_MENU → HERO_CREATE → TOWN → EXPEDITION_MAP → LOCATION → … →
##   RUN_RESULT → TOWN
## Owns the TownState (saved to user://town.save) and the RunState of the
## expedition under way, and moves between scenes through a fade.
## LAN co-op keeps the classic floor-after-floor run (GameState.expedition
## stays false there).

signal state_changed(state: State)

enum State { MAIN_MENU, HERO_CREATE, TOWN, EXPEDITION_MAP, LOCATION, RUN_RESULT }

const MAP_SCENE := "res://scenes/ui/expedition_map.tscn"
const RESULT_SCENE := "res://scenes/ui/run_result.tscn"
const CAMP_SCENE := "res://scenes/ui/camp.tscn"
## Node types played as a platformer location in the game scene.
const PLATFORMER_TYPES := [&"level", &"elite", &"special", &"rescue", &"lair", &"boss", &"event"]
const FADE_TIME := 0.25

var state: State = State.MAIN_MENU
## Summary of the expedition that just ended (RunResult screen).
var last_result: Dictionary = {}
var _fade: ColorRect
var _busy := false
## The world in play (its slot is SaveManager.slot): name, when it was made,
## seconds of play (counted while a world is loaded).
var world_name := ""
var world_created := 0
var playtime := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.01, 0.03, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	add_child(SaveIndicator.new())
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.chest_opened.connect(_on_chest_opened)


# ================================================================== scenes
## Fades out, switches the scene, fades back in.
func change_scene(path: String, new_state: State) -> void:
	if _busy:
		return
	_busy = true
	# A world session: everyone follows the host's move (WorldNet.flow).
	if new_state != State.MAIN_MENU:
		WorldNet.broadcast_flow(new_state)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	state = new_state
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	state_changed.emit(state)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func is_busy() -> bool:
	return _busy


## A guest of a world session: the host decides everything about the world.
func is_guest() -> bool:
	return WorldNet.session and Net.active and not Net.is_host


## The loop as the host sees it now, for the guests (WorldNet.flow): the
## state entered, the town (without the players' private profiles), the
## expedition, the location, the result.
func flow_payload(new_state: State = state) -> Dictionary:
	var town: Dictionary = GameState.town.to_dict() if GameState.town else {}
	town.erase("players")
	town.erase("hero")
	town.erase("warehouse")
	return {
		"state": new_state, "town": town, "run": GameState.run.to_dict() if GameState.run else {},
		"location": GameState.location.duplicate(true), "floor": GameState.floor_number,
		"result": last_result.duplicate(true) if new_state == State.RUN_RESULT else {},
	}


## A guest follows the host: the same town, map, location; the guest's own
## hero. An expedition lost by the party costs the guest its own gear.
func apply_remote_flow(p: Dictionary) -> void:
	var town := TownState.from_dict(p.get("town", {}))
	var had_run := GameState.run != null
	GameState.town = town
	GameState.expedition = true
	GameState.difficulty = ItemDatabase.difficulty(town.difficulty_id)
	GameState.eclipse_level = town.eclipse_level
	var run_d: Dictionary = p.get("run", {})
	GameState.run = RunState.from_dict(run_d) if not run_d.is_empty() else null
	if GameState.run:
		GameState.run_seed = GameState.run.seed_value
		if not had_run:
			GameState.pacts.clear()
			GameState.reset_run_stats()
	GameState.location = p.get("location", {})
	GameState.floor_number = int(p.get("floor", 0))
	GameState.run_active = true
	var st: State = int(p.get("state", State.TOWN))
	match st:
		State.TOWN:
			change_scene(GameState.GAME, State.TOWN)
		State.EXPEDITION_MAP:
			change_scene(MAP_SCENE, State.EXPEDITION_MAP)
		State.LOCATION:
			change_scene(CAMP_SCENE if GameState.location_type() == &"camp" else GameState.GAME, State.LOCATION)
		State.RUN_RESULT:
			last_result = p.get("result", {})
			if int(last_result.get("outcome", 0)) == RunState.Outcome.DEATH:
				last_result["lost"] = _strip_hero()  # the guest's own gear is lost too
				PlayerProfiles.push_now()
			change_scene(RESULT_SCENE, State.RUN_RESULT)


## A guest is out of the session (kicked, the host left): back to the menu.
func client_left_session(reason: String) -> void:
	GameState.town = null
	GameState.run = null
	GameState.hero = null
	GameState.location = {}
	GameState.expedition = false
	change_scene(GameState.MAIN_MENU, State.MAIN_MENU)
	EventBus.message.emit.call_deferred(reason)
	_menu_notice = reason


## The reason the last session ended (the main menu shows it once).
var _menu_notice := ""


func take_menu_notice() -> String:
	var n := _menu_notice
	_menu_notice = ""
	return n


func _process(delta: float) -> void:
	if GameState.town != null and GameState.expedition:
		playtime += delta


# ================================================================ the town
## A world to continue: the last slot played.
func has_save() -> bool:
	return SaveManager.last_slot > 0 and SaveManager.slot_exists(SaveManager.last_slot)


## «Новая игра»: a new, empty world in slot `slot` (whatever was there is
## wiped - the menu asks first), then a new hero.
func new_game(slot := -1, name := "") -> void:
	if slot <= 0:
		slot = SaveManager.free_slot() if SaveManager.free_slot() > 0 else 1
	if SaveManager.slot_exists(slot):
		SaveManager.delete_slot(slot)
	SaveManager.use_slot(slot)
	world_name = name.strip_edges() if name.strip_edges() != "" else tr("Мир %d") % slot
	world_created = int(Time.get_unix_time_from_system())
	playtime = 0.0
	GameState.town = null
	GameState.hero = null
	GameState.run = null
	change_scene(GameState.CHARACTER_CREATION, State.HERO_CREATE)


## Hero creation done: a new town with this hero (single player).
func create_hero(race: RaceData, cls: ClassData, female: bool, difficulty_id: StringName, eclipse: int) -> void:
	var town := TownState.new()
	town.difficulty_id = difficulty_id
	town.eclipse_level = clampi(eclipse, 0, EclipseLevels.MAX)
	town.world_seed = randi()
	Buildings.init_town(town)
	GameState.town = town
	_apply_run_rules(town)
	var hero := Hero.new(race, cls, ItemDatabase.equipment_layout)
	hero.female = female
	hero.give_starting_kit()
	GameState.apply_eclipse(hero)
	hero.skills.add_points(1)
	MetaProgress.apply_to(hero, true)
	GameState.hero = hero
	GameState.reset_run_stats()
	GameState.kills = 0
	if world_name == "":
		world_name = tr("Мир %d") % maxi(1, SaveManager.slot)
		world_created = int(Time.get_unix_time_from_system())
	save_town()
	enter_town()


## «Продолжить» / «Загрузить»: the world of `slot` (default: the last one).
## An expedition saved on the road goes on from its last save; one whose
## save was already used (a quit or a crash after a load) is lost, as a
## death - the warehouse is safe. False when the world cannot be read.
func continue_game(slot := -1) -> bool:
	if slot <= 0:
		slot = SaveManager.last_slot
	if slot <= 0 or not SaveManager.slot_exists(slot):
		return false
	SaveManager.use_slot(slot)
	var town := SaveManager.load_town()
	if town == null:
		return false
	var hero := RunCodec.load_hero(town.hero)
	if hero == null:
		return false
	var info := SaveManager.world_info()
	world_name = String(info.get("name", tr("Мир %d") % slot))
	world_created = int(info.get("created", 0))
	playtime = float(info.get("playtime", 0))
	GameState.town = town
	_apply_run_rules(town)
	GameState.hero = hero
	hero.stats.set_modifier("meta", MetaProgress.stat_bonuses())
	GameState.apply_eclipse(hero)
	GameState.reset_run_stats()
	GameState.kills = 0
	if town.expedition_active:
		if _resume_expedition():
			return true
		_strip_hero()
		town.expedition_active = false
		town.add_stat("lost")
		town.news.append(tr("Прошлый поход прерван: снаряжение похода потеряно."))
		SaveManager.clear_expedition()
	save_town()
	enter_town()
	return true


## Difficulty and Eclipse of this town apply to every expedition.
func _apply_run_rules(town: TownState) -> void:
	GameState.expedition = true
	GameState.difficulty = ItemDatabase.difficulty(town.difficulty_id)
	GameState.eclipse_level = town.eclipse_level
	GameState.pacts.clear()
	GameState.quests.reset()


## Saves the world in play. On the road the town keeps the hero as they
## left (run.save holds the expedition's hero).
func save_town() -> void:
	var town := GameState.town
	if town == null:
		return
	if is_guest():
		PlayerProfiles.push_now()  # the host's save is the truth
		return
	if WorldNet.session:
		PlayerProfiles.save_host()
		PlayerProfiles.request_all()
	if GameState.hero and GameState.run == null:
		town.hero = RunCodec.save_hero(GameState.hero)
	SaveManager.save_town(town, {"name": world_name, "created": world_created, "playtime": int(playtime)})
	EventBus.saved.emit()


## Autosave of the expedition under way: `at` = "map", "camp" or
## "location" (inside a platformer location only its entry is saved).
func save_expedition(at := "map") -> void:
	var run := GameState.run
	var hero := GameState.hero
	if run == null or hero == null or is_guest():
		return
	var pact_ids: Array = []
	for p in GameState.pacts:
		pact_ids.append(String(p.id))
	var stats: Dictionary = GameState.run_stats.duplicate()
	stats.erase("start_ms")
	SaveManager.save_expedition({
		"used": false, "at": at, "run": run.to_dict(), "hero": RunCodec.save_hero(hero),
		"pacts": pact_ids, "pet": String(GameState.pet.id) if GameState.pet else "",
		"kills": GameState.kills, "stats": stats, "location": GameState.location.duplicate(true),
	})
	save_town()


## Loads run.save (once: it is marked used right away). Saved on the map:
## back on the map; at a camp: back at the fire; inside a location: the
## hero fled it - it counts as walked, without its rewards.
func _resume_expedition() -> bool:
	var d := SaveManager.load_expedition()
	if d.is_empty() or d.get("used", true):
		return false
	d["used"] = true
	SaveManager.save_expedition(d)
	var hero := RunCodec.load_hero(d.get("hero", {}))
	if hero == null:
		return false
	hero.stats.set_modifier("meta", MetaProgress.stat_bonuses())
	GameState.apply_eclipse(hero)
	Buildings.apply_trophies(hero)
	if Buildings.level(&"temple") >= 3:
		hero.stats.set_modifier("blessing", {StatTypes.MAX_HP: roundi(hero.stats.max_hp() / 11.0)})
	GameState.hero = hero
	var run := RunState.from_dict(d.get("run", {}))
	GameState.run = run
	GameState.run_seed = run.seed_value
	GameState.pacts.clear()
	for pid in d.get("pacts", []):
		for p in ItemDatabase.pacts:
			if String(p.id) == String(pid):
				GameState.add_pact(p)
	GameState.pet = ItemDatabase.pets.get(StringName(d.get("pet", "")))
	GameState.kills = int(d.get("kills", 0))
	GameState.run_stats = d.get("stats", {})
	GameState.run_stats["start_ms"] = Time.get_ticks_msec()
	match String(d.get("at", "map")):
		"camp":
			GameState.location = d.get("location", {})
			GameState.floor_number = int(GameState.location.get("depth", 1))
			change_scene(CAMP_SCENE, State.LOCATION)
		"location":
			GameState.location = {}
			GameState.run.flags["fled"] = int(GameState.run.flags.get("fled", 0)) + 1
			change_scene(MAP_SCENE, State.EXPEDITION_MAP)
			EventBus.message.emit.call_deferred(tr("Вы бежали из локации: она пройдена без награды."))
		_:
			GameState.location = {}
			change_scene(MAP_SCENE, State.EXPEDITION_MAP)
	return true


## «Сохранить и выйти» (town, map, camp): the world and the expedition are
## saved where they stand, then the main menu.
func save_and_quit() -> void:
	if is_guest():
		PlayerProfiles.push_now()
		WorldNet.close_session()
		_leave_to_menu()
		return
	if GameState.run != null:
		save_expedition("camp" if GameState.location_type() == &"camp" else "map")
	else:
		save_town()
	_leave_to_menu()


## Walks the hero into the town street.
func enter_town() -> void:
	GameState.expedition = true
	GameState.run = null
	GameState.location = {"type": &"town", "depth": 0, "seed": hash([GameState.town.stats.get("expeditions", 0), 7])}
	GameState.floor_number = GameState.TOWN_FLOOR
	GameState.run_active = true
	GameState.town_return_floor = 0
	Buildings.apply_trophies(GameState.hero)
	save_town()
	change_scene(GameState.GAME, State.TOWN)


# ============================================================== expedition
## The town gate: a new expedition (map from a fresh seed) or back to the
## map of the one under way.
func open_map(start_region := -1) -> void:
	if is_guest():
		EventBus.message.emit(tr("Это решает хост."))
		return
	var town := GameState.town
	if GameState.run == null:
		var run := RunState.new()
		run.seed_value = randi()
		run.start_region = clampi(start_region if start_region >= 0 else 0, 0, town.region_unlocked)
		run.map = ExpeditionMap.generate(run.seed_value, run.start_region, map_options())
		_assign_prisoners(run)
		run.gold_at_start = GameState.hero.gold
		run.kills_at_start = GameState.kills
		run.start_ms = Time.get_ticks_msec()
		GameState.run = run
		GameState.run_seed = run.seed_value
		GameState.reset_run_stats()
		GameState.pacts.clear()
		# Rumours bought in the tavern: every sign on this map can be read.
		run.flags["rumours"] = town.flag("rumours", false)
		town.flags.erase("rumours")
		Buildings.on_expedition_start(GameState.hero)
		town.expedition_active = true
		town.add_stat("expeditions")
		var keep := GameState.run
		GameState.run = null
		save_town()  # the hero as they left town
		GameState.run = keep
		save_expedition("map")
	change_scene(MAP_SCENE, State.EXPEDITION_MAP)


## Map generation options the town has unlocked: special places (cache,
## mine, crypt) once the town has some life (prosperity 4), guardian lairs
## once a region guardian has fallen. Rescues are always on the road.
func map_options() -> Dictionary:
	var town := GameState.town
	return {
		"rescue": true,
		"special": town == null or town.prosperity >= 4,
		"lair": town == null or not town.bosses_defeated.is_empty(),
	}


## Regenerates the map of the expedition under way (debug, F5 on the map).
func reroll_map(seed_value := -1) -> void:
	var run := GameState.run
	if run == null or run.node_id >= 0:
		return
	run.seed_value = randi() if seed_value < 0 else seed_value
	run.map = ExpeditionMap.generate(run.seed_value, run.start_region, map_options())
	_assign_prisoners(run)
	GameState.run_seed = run.seed_value


## Who waits in each rescue node: people of the town not living there yet
## (data/npcs, by order, from their depth), else a nameless townsman.
func _assign_prisoners(run: RunState) -> void:
	var town := GameState.town
	var taken := {}
	var people: Array = ItemDatabase.npcs.values().filter(func(n: NpcData) -> bool:
		return not n.resident_from_start and (town == null or not town.has_resident(n.id)))
	people.sort_custom(func(a: NpcData, b: NpcData) -> bool: return a.order < b.order)
	var rescues := run.map.nodes.filter(func(n: Dictionary) -> bool: return n["type"] == &"rescue")
	rescues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["col"]) < int(b["col"]))
	for node: Dictionary in rescues:
		node["npc"] = RescueCage.REFUGEE
		for p: NpcData in people:
			if not taken.has(p.id) and p.depth_min <= int(node["depth"]):
				node["npc"] = p.id
				taken[p.id] = true
				break


## A prisoner freed: they come to town if the hero comes home alive.
func rescue(npc_id: StringName) -> void:
	var run := GameState.run
	if run == null:
		return
	run.rescued.append(npc_id)
	run.loc["rescued"] = npc_id


## Steps onto a node next to the hero; returns false when it is not one.
func enter_node(id: int) -> bool:
	if is_guest():
		return false
	var run := GameState.run
	if run == null or not id in run.next_choices():
		return false
	run.node_id = id
	run.path.append(id)
	var n := run.map.node(id)
	GameState.location = {
		"type": n["type"], "depth": n["depth"], "biome": n["biome"], "seed": n["seed"],
		"boss": n["boss"], "sub": n["sub"], "node": id, "region": n["region"],
		"npc": n.get("npc", &""),
	}
	GameState.location["mods"] = ExpeditionMap.MODS.get(StringName(n["sub"]) if StringName(n["sub"]) != &"" else StringName(n["type"]), {})
	GameState.floor_number = int(n["depth"])
	if StringName(n["type"]) == &"event":
		var reg := run.map.region_of(id)
		var ev := EventRunner.pick(reg.id if reg else &"", int(n["depth"]), int(n["seed"]))
		GameState.location["event"] = ev.id if ev else &""
		if ev:
			var seen: Array = run.flags.get("events_seen", [])
			seen.append(String(ev.id))
			run.flags["events_seen"] = seen
	var hero := GameState.hero
	run.loc = {"gold": hero.gold if hero else 0, "kills": GameState.kills, "shards": _shards(),
			"finds": [], "picked": 0, "resources": {}, "cleared": false}
	EventBus.floor_changed.emit(GameState.floor_number)
	var type := StringName(n["type"])
	if type in PLATFORMER_TYPES:
		save_expedition("location")
		change_scene(GameState.GAME, State.LOCATION)
	else:
		save_expedition("camp")
		change_scene(CAMP_SCENE, State.LOCATION)
	return true


# ================================================================= rewards
## A town resource found on the way (carried home on a safe return).
func gain_resource(id: StringName, amount: int, world_pos := Vector2.INF) -> void:
	var run := GameState.run
	if run == null or amount <= 0 or not GameState.expedition:
		return
	run.add_resource(id, amount)
	var lr: Dictionary = run.loc.get("resources", {})
	lr[String(id)] = int(lr.get(String(id), 0)) + amount
	run.loc["resources"] = lr
	if world_pos != Vector2.INF:
		EventBus.floating_text.emit(world_pos + Vector2(0, -14), "+%d %s" % [amount, TownResources.display_name(id)],
				Color(0.65, 0.95, 0.6))


func _on_item_collected(item: ItemData, _pos: Vector2) -> void:
	var run := GameState.run
	if run == null or item == null:
		return
	run.loc["picked"] = int(run.loc.get("picked", 0)) + 1
	if item.rarity >= ItemData.Rarity.RARE:
		run.finds.append(item.id)
		(run.loc.get("finds", []) as Array).append(item.display_name)


## Chests in an expedition sometimes hold building materials.
func _on_chest_opened(chest: Node) -> void:
	if GameState.run == null or not (chest is Node2D):
		return
	if randf() < 0.4:
		var id: StringName = [&"wood", &"stone", &"herbs"].pick_random()
		gain_resource(id, randi_range(1, 2), (chest as Node2D).global_position)


## A blueprint the town does not have yet (&"" = none left).
func _roll_blueprint() -> StringName:
	var owned: Array = GameState.town.blueprints.duplicate() if GameState.town else []
	owned.append_array(GameState.run.blueprints)
	var pool := ItemDatabase.buildings.filter(func(b: BuildingData) -> bool:
		return b.blueprint_level > 0 and not b.id in owned)
	return (pool.pick_random() as BuildingData).id if not pool.is_empty() else &""


func _shards() -> int:
	var hero := GameState.hero
	return hero.inventory.count_of(MetaProgress.SHARD_ITEM) if hero else 0


## Pays the clear reward of the location once (resources by node type and
## depth); returns the location's summary for the exit screen.
func location_summary() -> Dictionary:
	var run := GameState.run
	if run == null:
		return {}
	var n := run.current_node()
	if not run.loc.get("cleared", false):
		run.loc["cleared"] = true
		if run.flags.has("after_fight_rescue"):
			rescue(StringName(run.flags["after_fight_rescue"]))
			run.flags.erase("after_fight_rescue")
		var key := StringName(n.get("sub", &"")) if StringName(n.get("sub", &"")) != &"" else StringName(n.get("type", &"level"))
		var table: Dictionary = ExpeditionMap.CLEAR_REWARD.get(key, {})
		var bonus := int(n.get("depth", 1)) / 10
		for id in table:
			var amount := randi_range(int(table[id][0]), int(table[id][1]))
			if amount > 0:
				gain_resource(id, amount + bonus)
		# Guardians (and now and then a crypt) keep blueprints of the town.
		if key in [&"boss", &"lair"] or (key == &"crypt" and randf() < 0.35):
			var bp := _roll_blueprint()
			if bp != &"":
				run.blueprints.append(bp)
				run.loc["blueprint"] = bp
	var hero := GameState.hero
	return {
		"gold": (hero.gold if hero else 0) - int(run.loc.get("gold", 0)),
		"kills": GameState.kills - int(run.loc.get("kills", 0)),
		"shards": _shards() - int(run.loc.get("shards", 0)),
		"finds": run.loc.get("finds", []),
		"picked": int(run.loc.get("picked", 0)),
		"resources": run.loc.get("resources", {}),
		"blueprint": run.loc.get("blueprint", &""),
		"rescued": run.loc.get("rescued", &""),
		"type": n.get("type", &"level"),
	}


## The location is done (its exit, a camp left forward, an event closed):
## back to the map, or the end of the road after the last guardian.
func location_cleared() -> void:
	if is_guest():
		return
	var run := GameState.run
	if run == null:
		return
	var n := run.current_node()
	run.flags["nodes_done"] = int(run.flags.get("nodes_done", 0)) + 1
	if StringName(n.get("type", &"")) == &"lair":
		run.bosses.append(StringName(n["boss"]))
	if StringName(n.get("type", &"")) == &"boss":
		var reg := run.map.region_of(int(n["id"]))
		run.bosses.append(StringName(n["boss"]))
		var abs_region := run.map.first_region + int(n["region"])
		if GameState.town.region_unlocked < abs_region + 1 and abs_region + 1 < ItemDatabase.regions.size():
			GameState.town.region_unlocked = abs_region + 1
		if run.map.links_of(int(n["id"])).is_empty():
			# The last guardian of the last region: the road ends in victory.
			GameState.run_stats["victory"] = true
			end_expedition(RunState.Outcome.VICTORY)
			return
		EventBus.message.emit(tr("%s позади. Дорога ведёт дальше.") % (reg.display_name if reg else ""))
	GameState.location = {}
	save_expedition("map")
	change_scene(MAP_SCENE, State.EXPEDITION_MAP)


## Home with the loot (from a camp, or the map right after a region boss).
func retreat() -> void:
	if is_guest():
		EventBus.message.emit(tr("Это решает хост."))
		return
	end_expedition(RunState.Outcome.RETREAT)


## The hero fell in a location.
func hero_died() -> void:
	end_expedition(RunState.Outcome.DEATH)


## Settles the expedition with the town and shows the result screen.
func end_expedition(outcome: RunState.Outcome) -> void:
	var run := GameState.run
	var town := GameState.town
	if run == null or town == null:
		enter_town()
		return
	run.outcome = outcome
	var hero := GameState.hero
	var prosperity_before := Buildings.prosperity(town)
	var region_before := town.region_unlocked
	var path_types: Array = []
	for id in run.path:
		var pn := run.map.node(id)
		path_types.append(StringName(pn["sub"]) if StringName(pn["sub"]) != &"" else StringName(pn["type"]))
	var r := {
		"outcome": outcome,
		"nodes": run.path.size(),
		"depth": GameState.floor_number,
		"kills": GameState.kills - run.kills_at_start,
		"gold": (hero.gold - run.gold_at_start) if hero else 0,
		"seconds": (Time.get_ticks_msec() - run.start_ms) / 1000,
		"resources": run.resources.duplicate(),
		"finds": run.finds.duplicate(),
		"rescued": run.rescued.duplicate(),
		"bosses": run.bosses.duplicate(),
		"blueprints": run.blueprints.duplicate(),
		"path": path_types,
		"lost": [],
	}
	# The Sanctum's shards (depth, guardians, shard items) - as before.
	GameState.floor_number = maxi(GameState.floor_number, 1)
	r["sanctum"] = GameState.end_run()
	if outcome == RunState.Outcome.DEATH:
		r["lost"] = _strip_hero()
		r["resources"] = {}
		r["rescued"] = []
		r["blueprints"] = []
		town.add_stat("deaths")
	else:
		for k in run.resources:
			town.add_resource(StringName(k), int(run.resources[k]))
		for id in run.rescued:
			if id == RescueCage.REFUGEE:
				town.add_stat("refugees")
				town.news.append(tr("В город пришёл спасённый горожанин."))
			elif town.add_resident(id):
				var npc: NpcData = ItemDatabase.npcs.get(id)
				town.news.append(tr("В город переехал(а) %s.") % (npc.display_name if npc else String(id)))
		for k in run.flags:
			if not k in ["nodes_done", "rumours", "events_seen", "after_fight_rescue"]:
				town.flags[k] = run.flags[k]
		for bp in run.blueprints:
			if not bp in town.blueprints:
				town.blueprints.append(bp)
		town.add_stat("victories" if outcome == RunState.Outcome.VICTORY else "retreats")
		if hero:
			hero.stats.hp = hero.stats.max_hp()
			hero.stats.mana = hero.stats.max_mana()
	for b in run.bosses:
		if not b in town.bosses_defeated:
			town.bosses_defeated.append(b)
			town.prosperity += 5
	town.add_stat("nodes", run.path.size())
	# The journal remembers every road event met (whatever the outcome).
	var known: Array = town.flags.get("events_known", [])
	for e in run.flags.get("events_seen", []):
		if not e in known:
			known.append(e)
	town.flags["events_known"] = known
	if outcome != RunState.Outcome.DEATH:
		var arrived: Array = town.flags.get("arrived", [])
		for id in run.rescued:
			if id != RescueCage.REFUGEE and not id in arrived:
				arrived.append(String(id))
		town.flags["arrived"] = arrived
	Buildings.on_expedition_end(GameState.hero)
	town.prosperity = Buildings.prosperity(town)
	r["prosperity"] = [prosperity_before, town.prosperity]
	r["region_opened"] = town.region_unlocked > region_before
	r["region"] = ItemDatabase.regions[town.region_unlocked].display_name if town.region_unlocked < ItemDatabase.regions.size() else ""
	SaveManager.clear_expedition()
	town.expedition_active = false
	GameState.run = null
	GameState.location = {}
	last_result = r
	save_town()
	change_scene(RESULT_SCENE, State.RUN_RESULT)


## The result screen's «В город».
func back_to_town() -> void:
	if is_guest():
		EventBus.message.emit(tr("Это решает хост."))
		return
	GameState.run_active = true
	GameState.reset_run_stats()
	enter_town()


## Pause → main menu. In town the game is saved; mid-expedition the
## expedition is lost (the save still says it was under way).
func quit_to_menu() -> void:
	if is_guest():
		save_and_quit()
		return
	if GameState.run == null:
		save_town()
	elif GameState.location.is_empty() or GameState.location_type() == &"camp":
		save_expedition("camp" if GameState.location_type() == &"camp" else "map")
	_leave_to_menu()


func _leave_to_menu() -> void:
	if WorldNet.session:
		WorldNet.close_session()
	GameState.hero = null
	GameState.run = null
	GameState.location = {}
	GameState.run_active = false
	change_scene(GameState.MAIN_MENU, State.MAIN_MENU)


## Death: the expedition's gear, backpack and gold are gone; the class
## kit is handed out again. Level, skills and the warehouse stay.
## Returns the names of the lost items (result screen).
func _strip_hero() -> Array:
	var hero := GameState.hero
	if hero == null:
		return []
	var lost: Array = []
	for st in hero.inventory.slots:
		if st and st.item and st.item.rarity >= ItemData.Rarity.RARE:
			lost.append(st.item.display_name)
	for slot in hero.equipment.items:
		var it: ItemData = hero.equipment.items[slot]
		if it and it.rarity >= ItemData.Rarity.RARE:
			lost.append(it.display_name)
	var d := RunCodec.save_hero(hero)
	d["inventory"] = []
	d["pouch"] = []
	d["equipment"] = {}
	d["quick_bar"] = []
	d["gold"] = 0
	var fresh := RunCodec.load_hero(d)
	if fresh == null:
		return lost
	fresh.give_starting_kit()
	fresh.stats.set_modifier("meta", MetaProgress.stat_bonuses())
	GameState.apply_eclipse(fresh)
	fresh.stats.hp = fresh.stats.max_hp()
	fresh.stats.mana = fresh.stats.max_mana()
	GameState.hero = fresh
	return lost

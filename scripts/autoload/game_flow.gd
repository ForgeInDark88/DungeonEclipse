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
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.chest_opened.connect(_on_chest_opened)


# ================================================================== scenes
## Fades out, switches the scene, fades back in.
func change_scene(path: String, new_state: State) -> void:
	if _busy:
		return
	_busy = true
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


# ================================================================ the town
func has_save() -> bool:
	return SaveManager.has_town() and SaveManager.load_town() != null


## Main menu → «Новая игра»: the old town is wiped, a new hero is made.
func new_game() -> void:
	SaveManager.clear_town()
	GameState.town = null
	GameState.hero = null
	change_scene(GameState.CHARACTER_CREATION, State.HERO_CREATE)


## Hero creation done: a new town with this hero (single player).
func create_hero(race: RaceData, cls: ClassData, female: bool, difficulty_id: StringName, eclipse: int) -> void:
	var town := TownState.new()
	town.difficulty_id = difficulty_id
	town.eclipse_level = clampi(eclipse, 0, EclipseLevels.MAX)
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
	save_town()
	enter_town()


## Main menu → «Продолжить»: loads the town; an expedition cut short by
## quitting the game is lost (as a death, the warehouse is safe).
func continue_game() -> bool:
	var town := SaveManager.load_town()
	if town == null:
		return false
	var hero := RunCodec.load_hero(town.hero)
	if hero == null:
		return false
	GameState.town = town
	_apply_run_rules(town)
	GameState.hero = hero
	hero.stats.set_modifier("meta", MetaProgress.stat_bonuses())
	GameState.apply_eclipse(hero)
	if town.expedition_active:
		_strip_hero()
		town.expedition_active = false
		town.add_stat("lost")
		town.news.append(tr("Прошлый поход прерван: снаряжение похода потеряно."))
	GameState.reset_run_stats()
	GameState.kills = 0
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


func save_town() -> void:
	var town := GameState.town
	if town == null:
		return
	if GameState.hero:
		town.hero = RunCodec.save_hero(GameState.hero)
	SaveManager.save_town(town)


## Walks the hero into the town street.
func enter_town() -> void:
	GameState.expedition = true
	GameState.run = null
	GameState.location = {"type": &"town", "depth": 0, "seed": hash([GameState.town.stats.get("expeditions", 0), 7])}
	GameState.floor_number = GameState.TOWN_FLOOR
	GameState.run_active = true
	GameState.town_return_floor = 0
	Buildings.apply_trophies(GameState.hero)
	change_scene(GameState.GAME, State.TOWN)


# ============================================================== expedition
## The town gate: a new expedition (map from a fresh seed) or back to the
## map of the one under way.
func open_map(start_region := -1) -> void:
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
		save_town()  # the hero as they left: a quit mid-expedition loses the rest
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
		change_scene(GameState.GAME, State.LOCATION)
	else:
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
	change_scene(MAP_SCENE, State.EXPEDITION_MAP)


## Home with the loot (from a camp, or the map right after a region boss).
func retreat() -> void:
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
	town.expedition_active = false
	GameState.run = null
	GameState.location = {}
	last_result = r
	save_town()
	change_scene(RESULT_SCENE, State.RUN_RESULT)


## The result screen's «В город».
func back_to_town() -> void:
	GameState.run_active = true
	GameState.reset_run_stats()
	enter_town()


## Pause → main menu. In town the game is saved; mid-expedition the
## expedition is lost (the save still says it was under way).
func quit_to_menu() -> void:
	if GameState.run == null:
		save_town()
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

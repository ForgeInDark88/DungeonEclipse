extends Node
## The town in a world session (child of WorldNet: the same node path on
## every machine). The town belongs to the world: guests build through the
## host (if the world allows), the host sends the town to everyone after
## every change. Each player keeps a personal safe in the warehouse (the
## host's in TownState.warehouse, a guest's in its profile: "safe").


## Host → everyone: the town changed (buildings, resources, residents).
func push_town() -> void:
	if not (WorldNet.session and Net.is_host and Net.active) or GameState.town == null:
		return
	var d := GameState.town.to_dict()
	d.erase("players")
	d.erase("hero")
	d.erase("warehouse")
	town_sync.rpc(d)


@rpc("authority", "call_remote", "reliable")
func town_sync(d: Dictionary) -> void:
	GameState.town = TownState.from_dict(d)
	_refresh_street()


func _refresh_street() -> void:
	for b in get_tree().get_nodes_in_group("town_buildings"):
		(b as TownBuilding).refresh()


# ------------------------------------------------------------- building
## Guest: build / upgrade `id` (its gold is checked and paid here).
func request_build(id: StringName) -> void:
	var b := ItemDatabase.building(id)
	if b == null:
		return
	build_request.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func build_request(id: StringName) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	var b := ItemDatabase.building(id)
	if b == null or not WorldNet.roster.has(peer):
		return
	if String(GameState.town.flag("build_rule", "all")) == "host":
		build_answer.rpc_id(peer, id, false, 0, "Строить может только хост.")  # i18n-src
		return
	var next := GameState.town.building_level(id) + 1
	var gold := int(Buildings.cost(b, next).get("gold", 0))
	var reason := Buildings.block_reason(b, true)
	if reason != "" or not Buildings.build(b, true):
		build_answer.rpc_id(peer, id, false, 0, reason)
		return
	GameFlow.save_town()
	_refresh_street()
	push_town()
	WorldNet.system_line("%s строит: %s, уровень %d.", [String(WorldNet.roster[peer]["nick"]), b.display_name, next])  # i18n-src
	build_answer.rpc_id(peer, id, true, gold, "")


## Host → guest: built (the guest pays its gold) or why not.
@rpc("authority", "call_remote", "reliable")
func build_answer(id: StringName, ok: bool, gold: int, reason: String) -> void:
	if ok:
		GameState.hero.gold = maxi(0, GameState.hero.gold - gold)
		GameState.hero.gold_changed.emit(GameState.hero.gold)
		for b in get_tree().get_nodes_in_group("town_buildings"):
			if (b as TownBuilding).data.id == id:
				(b as TownBuilding).play_built()
	else:
		EventBus.message.emit(tr(reason) if reason != "" else tr("Не получилось построить."))


# ---------------------------------------------------------- personal safe
signal safe_changed(items: Array, cap: int)

var safe_cache: Array = []


func _safe_of(peer: int) -> Array:
	var r: Dictionary = WorldNet.roster.get(peer, {})
	var p: Dictionary = GameState.town.players.get(String(r.get("key", "")), {}) if not r.is_empty() else {}
	if p.is_empty():
		return []
	if not p.has("safe"):
		p["safe"] = []
	return p["safe"]


## Guest: what is in my safe (answer: safe_changed).
func request_safe() -> void:
	safe_list_request.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func safe_list_request() -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	safe_list.rpc_id(peer, _safe_of(peer), Buildings.warehouse_slots())


@rpc("authority", "call_remote", "reliable")
func safe_list(items: Array, cap: int) -> void:
	safe_cache = items
	safe_changed.emit(items, cap)


## Guest: put a stack (already taken out of the backpack) into my safe; a
## full safe gives it back.
func put(st: ItemStack) -> void:
	safe_put.rpc_id(1, RunCodec._item_to_dict(st))


@rpc("any_peer", "call_remote", "reliable")
func safe_put(d: Dictionary) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	var safe := _safe_of(peer)
	if RunCodec._item_from_dict(d) == null:
		return
	if safe.size() >= Buildings.warehouse_slots() or not WorldNet.roster.has(peer):
		safe_returned.rpc_id(peer, d)
		return
	safe.append(d)
	GameFlow.save_town()
	safe_list.rpc_id(peer, safe, Buildings.warehouse_slots())


@rpc("authority", "call_remote", "reliable")
func safe_returned(d: Dictionary) -> void:
	var st := RunCodec._item_from_dict(d)
	if st:
		GameState.hero.inventory.add_item(st.item, st.count)
	EventBus.message.emit(tr("Сейф полон."))


## Guest: take stack `index` out of my safe.
func take(index: int) -> void:
	safe_take.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func safe_take(index: int) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	var safe := _safe_of(peer)
	if index < 0 or index >= safe.size():
		return
	var d: Dictionary = safe.pop_at(index)
	GameFlow.save_town()
	safe_given.rpc_id(peer, d)
	safe_list.rpc_id(peer, safe, Buildings.warehouse_slots())


@rpc("authority", "call_remote", "reliable")
func safe_given(d: Dictionary) -> void:
	var st := RunCodec._item_from_dict(d)
	if st == null:
		return
	var left := GameState.hero.inventory.add_item(st.item, st.count)
	if left > 0:
		EventBus.message.emit(tr("Рюкзак полон: вещь осталась в сейфе."))
		put(ItemStack.new(st.item, left))
	PlayerProfiles.push_now()

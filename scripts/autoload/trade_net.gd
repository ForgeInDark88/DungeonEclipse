extends Node
## Trading between players of a world session (child of WorldNet). The host
## keeps every trade: invite → both open the window → each puts items and
## gold on its side (any change unconfirms both) → both confirm → PREPARE:
## each side takes its offer out of its own backpack and reports what it
## really took → COMMIT: each side receives the other's (or ABORT: each
## gets its own back). Nothing is created or lost on the way.

signal invited(trade_id: int, from_nick: String)
signal opened(trade_id: int, other_nick: String)
signal state_changed(mine: Array, mine_gold: int, theirs: Array, theirs_gold: int, my_ok: bool, their_ok: bool)
signal closed(reason: String)

## Host: trade id -> {a, b, offer: {peer: [indices]}, gold: {peer: n}, ok: {peer: bool},
## stage: "invite" / "open" / "prepare", taken: {peer: [dicts]}, gold_taken: {peer: n}}
var trades := {}
var _next := 1
## Client: the trade window's id (0 = none) and my offer (inventory indices).
var current := 0
var my_offer: Array = []
var my_gold := 0
var _taken: Array = []  # what I took out on PREPARE (to give back on ABORT)
var _gold_taken := 0


# ---------------------------------------------------------------- client
func invite(peer: int) -> void:
	request_trade.rpc_id(1, peer) if not Net.is_host else _host_invite(1, peer)


func accept(trade_id: int) -> void:
	_call_host(&"accept_trade", [trade_id])


func set_offer(indices: Array, gold: int) -> void:
	my_offer = indices
	my_gold = gold
	_call_host(&"offer", [current, indices, gold])


func confirm() -> void:
	_call_host(&"confirm_rpc", [current])


func cancel() -> void:
	if current != 0:
		_call_host(&"cancel_trade", [current])


func _call_host(method: StringName, args: Array) -> void:
	if Net.is_host:
		_host_call(1, method, args)
	else:
		callv("rpc_id", [1, method] + args)


func _host_call(peer: int, method: StringName, args: Array) -> void:
	match method:
		&"accept_trade":
			_accept(peer, int(args[0]))
		&"offer":
			_offer(peer, int(args[0]), args[1], int(args[2]))
		&"confirm_rpc":
			_confirm(peer, int(args[0]))
		&"cancel_trade":
			_cancel(int(args[0]), "cancel")


# ------------------------------------------------------------ host RPCs
@rpc("any_peer", "call_remote", "reliable")
func request_trade(to: int) -> void:
	if Net.is_host:
		_host_invite(multiplayer.get_remote_sender_id(), to)


@rpc("any_peer", "call_remote", "reliable")
func accept_trade(trade_id: int) -> void:
	if Net.is_host:
		_accept(multiplayer.get_remote_sender_id(), trade_id)


@rpc("any_peer", "call_remote", "reliable")
func offer(trade_id: int, indices: Array, gold: int) -> void:
	if Net.is_host:
		_offer(multiplayer.get_remote_sender_id(), trade_id, indices, gold)


@rpc("any_peer", "call_remote", "reliable")
func confirm_rpc(trade_id: int) -> void:
	if Net.is_host:
		_confirm(multiplayer.get_remote_sender_id(), trade_id)


@rpc("any_peer", "call_remote", "reliable")
func cancel_trade(trade_id: int) -> void:
	if Net.is_host:
		var t: Dictionary = trades.get(trade_id, {})
		if not t.is_empty() and multiplayer.get_remote_sender_id() in [t["a"], t["b"]]:
			_cancel(trade_id, "cancel")


@rpc("any_peer", "call_remote", "reliable")
func prepared(trade_id: int, items: Array, gold: int) -> void:
	if Net.is_host:
		_prepared(multiplayer.get_remote_sender_id(), trade_id, items, gold)


# ------------------------------------------------------------ host logic
func _online(peer: int) -> bool:
	return WorldNet.roster.has(peer) and WorldNet.roster[peer]["status"] == "online"


func _host_invite(from: int, to: int) -> void:
	if from == to or not _online(from) or not _online(to):
		return
	for t in trades.values():
		if from in [t["a"], t["b"]] or to in [t["a"], t["b"]]:
			return  # one trade at a time
	var id := _next
	_next += 1
	trades[id] = {"a": from, "b": to, "offer": {from: [], to: []}, "gold": {from: 0, to: 0},
			"ok": {from: false, to: false}, "stage": "invite", "taken": {}, "gold_taken": {}}
	_to(to, &"invite_in", [id, String(WorldNet.roster[from]["nick"])])


func _accept(peer: int, id: int) -> void:
	var t: Dictionary = trades.get(id, {})
	if t.is_empty() or t["b"] != peer or t["stage"] != "invite":
		return
	t["stage"] = "open"
	_to(t["a"], &"window", [id, String(WorldNet.roster[t["b"]]["nick"])])
	_to(t["b"], &"window", [id, String(WorldNet.roster[t["a"]]["nick"])])


func _offer(peer: int, id: int, indices: Array, gold: int) -> void:
	var t: Dictionary = trades.get(id, {})
	if t.is_empty() or t["stage"] != "open" or not peer in [t["a"], t["b"]]:
		return
	t["offer"][peer] = indices.slice(0, 12)
	t["gold"][peer] = maxi(0, gold)
	t["ok"][t["a"]] = false
	t["ok"][t["b"]] = false
	_send_state(t)


func _confirm(peer: int, id: int) -> void:
	var t: Dictionary = trades.get(id, {})
	if t.is_empty() or t["stage"] != "open" or not peer in [t["a"], t["b"]]:
		return
	t["ok"][peer] = true
	_send_state(t)
	if t["ok"][t["a"]] and t["ok"][t["b"]]:
		t["stage"] = "prepare"
		for p in [t["a"], t["b"]]:
			_to(p, &"prepare", [id, t["offer"][p], t["gold"][p]])


func _prepared(peer: int, id: int, items: Array, gold: int) -> void:
	var t: Dictionary = trades.get(id, {})
	if t.is_empty() or t["stage"] != "prepare" or not peer in [t["a"], t["b"]]:
		return
	t["taken"][peer] = items
	t["gold_taken"][peer] = gold
	if not (t["taken"].has(t["a"]) and t["taken"].has(t["b"])):
		return
	# both sides took exactly what they offered: swap; otherwise give back
	var ok: bool = t["taken"][t["a"]].size() == t["offer"][t["a"]].size() and t["taken"][t["b"]].size() == t["offer"][t["b"]].size() \
			and int(t["gold_taken"][t["a"]]) == int(t["gold"][t["a"]]) and int(t["gold_taken"][t["b"]]) == int(t["gold"][t["b"]])
	trades.erase(id)
	if ok:
		_to(t["a"], &"commit", [t["taken"][t["b"]], int(t["gold_taken"][t["b"]])])
		_to(t["b"], &"commit", [t["taken"][t["a"]], int(t["gold_taken"][t["a"]])])
		WorldNet.system_line("%s и %s обменялись.", [String(WorldNet.roster[t["a"]]["nick"]), String(WorldNet.roster[t["b"]]["nick"])])  # i18n-src
	else:
		for p in [t["a"], t["b"]]:
			_to(p, &"abort", ["changed"])


func _cancel(id: int, reason: String) -> void:
	var t: Dictionary = trades.get(id, {})
	if t.is_empty() or t["stage"] == "prepare":
		return
	trades.erase(id)
	for p in [t["a"], t["b"]]:
		_to(p, &"abort", [reason])


## Host: a player left - its trades end.
func on_peer_left(peer: int) -> void:
	for id in trades.keys():
		var t: Dictionary = trades[id]
		if peer in [t["a"], t["b"]]:
			trades.erase(id)
			for p in [t["a"], t["b"]]:
				if p != peer:
					_to(p, &"abort", ["left"])


func _send_state(t: Dictionary) -> void:
	for p in [t["a"], t["b"]]:
		var o: int = t["b"] if p == t["a"] else t["a"]
		_to(p, &"state", [_describe(t["offer"][p], o, p), int(t["gold"][p]), _describe(t["offer"][o], o, p), int(t["gold"][o]),
				t["ok"][p], t["ok"][o]])


## The offer as indices only (each client describes its own side; the
## other's items are named on PREPARE). Kept simple: indices travel.
func _describe(indices: Array, _o: int, _p: int) -> Array:
	return indices


func _to(peer: int, method: StringName, args: Array) -> void:
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


# ---------------------------------------------------------- client RPCs
@rpc("authority", "call_remote", "reliable")
func invite_in(id: int, from_nick: String) -> void:
	invited.emit(id, from_nick)


@rpc("authority", "call_remote", "reliable")
func window(id: int, other_nick: String) -> void:
	current = id
	my_offer = []
	my_gold = 0
	opened.emit(id, other_nick)


@rpc("authority", "call_remote", "reliable")
func state(mine: Array, mine_gold: int, theirs: Array, theirs_gold: int, my_ok: bool, their_ok: bool) -> void:
	state_changed.emit(mine, mine_gold, theirs, theirs_gold, my_ok, their_ok)


## PREPARE: take my offer out of my backpack (what is really there).
@rpc("authority", "call_remote", "reliable")
func prepare(id: int, indices: Array, gold: int) -> void:
	var hero := GameState.hero
	_taken = []
	var sorted := indices.duplicate()
	sorted.sort()
	sorted.reverse()  # take from the end, indices stay valid
	for i in sorted:
		var st := hero.inventory.take_at(int(i))
		if st:
			_taken.append(RunCodec._item_to_dict(st))
	_gold_taken = gold if hero.spend_gold(gold) else 0
	if Net.is_host:
		_prepared(1, id, _taken, _gold_taken)
	else:
		prepared.rpc_id(1, id, _taken, _gold_taken)


## COMMIT: the other side's things are mine now.
@rpc("authority", "call_remote", "reliable")
func commit(items: Array, gold: int) -> void:
	_receive(items, gold)
	_taken = []
	_gold_taken = 0
	current = 0
	closed.emit("done")
	PlayerProfiles.push_now()


## ABORT: whatever I took out goes back.
@rpc("authority", "call_remote", "reliable")
func abort(reason: String) -> void:
	_receive(_taken, _gold_taken)
	_taken = []
	_gold_taken = 0
	current = 0
	closed.emit(reason)


func _receive(items: Array, gold: int) -> void:
	var hero := GameState.hero
	for d in items:
		var st := RunCodec._item_from_dict(d)
		if st:
			var left := hero.inventory.add_item(st.item, st.count)
			if left > 0:
				# a full backpack: the rest lands at my feet (my own pickup)
				var me := get_tree().get_first_node_in_group("player") as Node2D
				if me:
					EventBus.spawn_items.emit(me.global_position + Vector2(0, -12), [{"item": st.item, "count": left}])
	if gold > 0:
		hero.add_gold(gold)

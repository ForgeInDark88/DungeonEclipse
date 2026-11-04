extends Node
## LAN co-op: ENet transport (port 24565) + UDP auto-discovery (port 24566).
## The host is the authority: it simulates enemies, loot and floor changes;
## clients simulate their own hero and send hits/pickups to the host.
## Discovery: the host answers broadcast probes, so the client sees a server
## list without typing IPs.

const GAME_PORT := 24565
const DISCOVERY_PORT := 24566
const PROBE := "eclipse-probe"
const ANNOUNCE := "eclipse-host"
const MAX_PLAYERS := 4
## Difficulty grows with the party: data/coop/rules.tres (CoopRules).

signal player_joined(info: Dictionary)
signal player_left(peer_id: int)
signal players_changed
signal run_started
signal host_closed

var active := false            # a network session exists (host or client)
var is_host := false
## A world session (WorldNet: the town and expeditions of a save slot)
## rather than the classic floor-after-floor co-op run.
var world_session := false
## Seats of this session (host included), at most MAX_PLAYERS.
var max_players := MAX_PLAYERS
var players := {}              # peer_id -> {"name", "race", "cls", "female"}
## The party size the current floor was built for (layout_party()).
var floor_players := 0
## Race/class ids each peer picked, stored until the run starts.
var my_info := {"name": tr("Игрок"), "race": &"human", "cls": &"warrior", "female": false}

## World sessions: which scene each machine has loaded (a token of the
## location: "" = no game scene). Frequent world messages go only to the
## machines that stand in the same place (Net.send).
var scene_token := ""
var peer_tokens := {}  # peer id -> token

var _udp := PacketPeerUDP.new()
var _udp_open := false
var _discovering := false
var _found := {}               # ip -> {"ip", "names", "count"}
var _probe_time := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not _udp_open:
		return
	# Host: answer probes. Client during discovery: collect announces.
	if _discovering and is_instance_valid(_udp):
		_probe_time -= delta
		if _probe_time <= 0.0:
			_probe_time = 0.5
			_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_udp.put_packet(PROBE.to_utf8_buffer())
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var txt := pkt.get_string_from_utf8()
		if is_host and txt == PROBE:
			var names := ", ".join(_names_list())
			# reply straight to the sender's source address and port
			_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
			var extra := WorldNet.announce_extra() if world_session else ""
			_udp.put_packet(("%s;%d;%s%s" % [ANNOUNCE, players.size(), names, extra]).to_utf8_buffer())
		elif _discovering and txt.begins_with(ANNOUNCE):
			var parts := txt.split(";")
			if parts.size() >= 3:
				var entry := {"ip": _udp.get_packet_ip(), "count": int(parts[1]), "names": parts[2]}
				if parts.size() >= 8:  # a world session: name, seats, lock, protocol, port
					entry.merge({"world": parts[3], "max": int(parts[4]), "locked": parts[5] == "1",
							"protocol": int(parts[6]), "port": int(parts[7])})
				_found[_udp.get_packet_ip()] = entry


func _names_list() -> Array[String]:
	var out: Array[String] = []
	for id in players:
		out.append(String(players[id]["name"]))
	return out


# ---------------------------------------------------------- scene routing
## Calls `method` as an RPC on `node` for every peer - in a world session
## only for the peers whose loaded scene is ours (a guest still on the map
## must not get the fight of a location it has not loaded: it receives the
## whole state with net_hello once it has).
func send(node: Node, method: StringName, args: Array = []) -> void:
	if not world_session:
		node.callv("rpc", [method] + args)
		return
	for p in scene_peers():
		node.callv("rpc_id", [p, method] + args)


func scene_peers() -> Array[int]:
	var out: Array[int] = []
	if multiplayer.multiplayer_peer == null:
		return out
	for p in multiplayer.get_peers():
		if scene_token != "" and peer_tokens.get(p, "") == scene_token:
			out.append(p)
	return out


## This machine loaded (or left) a game scene: tell everyone.
func set_scene_token(token: String) -> void:
	scene_token = token
	if active and world_session and multiplayer.multiplayer_peer != null:
		announce_token.rpc(token, true)


@rpc("any_peer", "call_remote", "reliable")
func announce_token(token: String, reply: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var known := peer_tokens.has(peer)
	peer_tokens[peer] = token
	if reply and not known:
		announce_token.rpc_id(peer, scene_token, false)  # a new face: it learns ours


## Whether `peer` has the same scene loaded as this machine.
func peer_in_scene(peer: int) -> bool:
	return scene_token != "" and peer_tokens.get(peer, "") == scene_token


# ------------------------------------------------------------- host / join
## Game port, overridable by NET_PORT (headless test runs on one machine
## must not fight the real game for 24565).
func game_port() -> int:
	var env := OS.get_environment("NET_PORT")
	return int(env) if env != "" else GAME_PORT


func host_game(port := -1, seats := MAX_PLAYERS, discoverable := true) -> bool:
	var peer := ENetMultiplayerPeer.new()
	max_players = clampi(seats, 2, MAX_PLAYERS)
	# One extra connection slot: a full session still answers «мир полон».
	if peer.create_server(port if port > 0 else game_port(), max_players) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	players.clear()
	players[1] = my_info.duplicate(true)
	# UDP responder for discovery
	_udp.close()
	_udp_open = discoverable and _udp.bind(DISCOVERY_PORT) == OK
	players_changed.emit()
	return true


func join_game(ip: String, port := -1) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port if port > 0 else game_port()) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	players.clear()
	start_discovery(false)
	return true


func leave(reason := "") -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false
	is_host = false
	world_session = false
	scene_token = ""
	peer_tokens.clear()
	players.clear()
	floor_players = 0
	_stop_udp()
	_discovering = false
	if reason != "":
		EventBus.message.emit(reason)
	host_closed.emit()


## Host: every peer registers itself right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func register_player(info: Dictionary) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = info
	broadcast_players()
	player_joined.emit(info)
	EventBus.message.emit(tr("%s присоединился") % info.get("name", tr("Игрок")))


## Host: keep everyone's player list in sync.
@rpc("authority", "call_remote", "reliable")
func sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


func broadcast_players() -> void:
	if is_host:
		sync_players.rpc(players)


# The host tells a newly connected peer everything (players, run in progress).
func send_full_state(peer_id: int) -> void:
	if is_host:
		sync_players.rpc_id(peer_id, players)


# ------------------------------------------------------------------ run
## Host presses "start": every client enters the game with the same seed.
@rpc("authority", "call_remote", "reliable")
func start_run(seed_value: int, difficulty_id: StringName, eclipse := 0) -> void:
	GameState.begin_network_run(seed_value, difficulty_id, GameState.TOWN_FLOOR, eclipse)


func rpc_start_run(seed_value: int, difficulty_id: StringName) -> void:
	if is_host:
		start_run.rpc(seed_value, difficulty_id, GameState.eclipse_level)


## Host moved everyone to another floor (or the town); `party` is the
## party size the host builds that floor for.
@rpc("authority", "call_remote", "reliable")
func set_floor(floor_number: int, town_return: int = -1, party := 0) -> void:
	floor_players = party
	GameState.net_set_floor(floor_number, town_return)


func rpc_set_floor(floor_number: int, town_return: int = -1) -> void:
	if is_host:
		floor_players = players.size()
		set_floor.rpc(floor_number, town_return, floor_players)


## Host pushes its run state to a peer that joined mid-run.
@rpc("authority", "call_remote", "reliable")
func late_join(floor_number: int, seed_value: int, difficulty_id: StringName, eclipse := 0, party := 0) -> void:
	floor_players = party  # the floor already stands: built for the party before us
	GameState.begin_network_run(seed_value, difficulty_id, floor_number, eclipse)


func rpc_late_join(peer_id: int) -> void:
	if is_host:
		late_join.rpc_id(peer_id, GameState.floor_number, GameState.run_seed,
				GameState.difficulty.id if GameState.difficulty else &"normal", GameState.eclipse_level, floor_players)


# ------------------------------------------------------------ difficulty
const RULES_PATH := "res://data/coop/rules.tres"
var _rules: CoopRules


## The party's rules (data/coop/rules.tres).
func rules() -> CoopRules:
	if _rules == null:
		_rules = load(RULES_PATH) as CoopRules if ResourceLoader.exists(RULES_PATH) else CoopRules.new()
	return _rules


## Extra players in the party (0 alone).
func extra_players() -> int:
	if not active:
		return 0
	return maxi(0, mini(players.size(), MAX_PLAYERS) - 1)


func enemy_hp_mult() -> float:
	return 1.0 + rules().hp_per_extra * extra_players()


func enemy_damage_mult() -> float:
	return 1.0 + rules().damage_per_extra * extra_players()


func boss_hp_mult() -> float:
	return 1.0 + rules().boss_hp_per_extra * extra_players()


## How many monsters a layout gets: the party the floor is built for. The
## host builds for the party it has and remembers it (floor_players); a
## guest builds the same floor with the host's number, never with its own
## view of the party - a friend joining mid-floor would otherwise roll a
## floor with more monster places, and every roll after them (traps!)
## would land elsewhere than on the host.
func monster_count_mult() -> float:
	return 1.0 + rules().monsters_per_extra * maxi(0, mini(layout_party(), MAX_PLAYERS) - 1)


## The party size the current floor's layout is built for (see above).
func layout_party() -> int:
	if not active:
		floor_players = 1  # hosted later: the floor that stands was built for one
		return 1
	if is_host:
		floor_players = players.size()
	return floor_players if floor_players > 0 else players.size()


func reward_mult() -> float:
	return 1.0 + rules().reward_per_extra * extra_players()


# -------------------------------------------------------------- discovery
func start_discovery(on: bool) -> void:
	_discovering = on
	_found.clear()
	_probe_time = 0.0
	if on and not is_host:
		_udp.close()
		_udp_open = _udp.bind(0) == OK  # ephemeral port for probes/replies
		_udp.set_broadcast_enabled(true)
	elif not on:
		if is_host and _udp_open:
			return  # keep the responder bound
		_stop_udp()


func discovered() -> Array:
	var out := []
	for ip in _found:
		out.append(_found[ip])
	out.sort_custom(func(a, b): return a["ip"] < b["ip"])
	return out


func _stop_udp() -> void:
	if _udp_open:
		_udp.close()
	_udp_open = false


# ------------------------------------------------------- connection events
func _on_peer_connected(id: int) -> void:
	if world_session:
		return  # WorldNet: the handshake comes first
	if is_host:
		send_full_state(id)
		if GameState.run_active:
			# A friend arrived mid-run: pull them straight into the dungeon.
			late_join.rpc_id(id, GameState.floor_number, GameState.run_seed,
					GameState.difficulty.id if GameState.difficulty else &"normal", GameState.eclipse_level, floor_players)


func _on_peer_disconnected(id: int) -> void:
	if world_session:
		WorldNet.on_peer_left(id)
		return
	if is_host and players.has(id):
		EventBus.message.emit(tr("%s вышел") % players[id].get("name", tr("Игрок")))
		players.erase(id)
		broadcast_players()
		player_left.emit(id)
		# The host informs the game scene so the puppet gets removed.
		get_tree().call_group("net_game", "on_peer_left", id)


func _on_connected() -> void:
	if world_session:
		WorldNet.on_connected()
		return
	register_player.rpc_id(1, my_info)


func _on_connect_failed() -> void:
	var world := world_session
	leave()
	EventBus.message.emit(tr("Не удалось подключиться"))
	if world:
		WorldNet.fail("unreachable")


func _on_server_disconnected() -> void:
	if world_session:
		WorldNet.on_host_lost()
		return
	leave(tr("Хост покинул игру"))
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.MAIN_MENU)

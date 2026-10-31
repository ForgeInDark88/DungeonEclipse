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
## Difficulty grows with the party: enemy HP/damage multiplier.
const HP_PER_EXTRA := 0.8
const DAMAGE_PER_EXTRA := 0.5

signal player_joined(info: Dictionary)
signal player_left(peer_id: int)
signal players_changed
signal run_started
signal host_closed

var active := false            # a network session exists (host or client)
var is_host := false
var players := {}              # peer_id -> {"name", "race", "cls", "female"}
## Race/class ids each peer picked, stored until the run starts.
var my_info := {"name": tr("Игрок"), "race": &"human", "cls": &"warrior", "female": false}

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
			_udp.put_packet(("%s;%d;%s" % [ANNOUNCE, players.size(), names]).to_utf8_buffer())
		elif _discovering and txt.begins_with(ANNOUNCE):
			var parts := txt.split(";")
			if parts.size() >= 3:
				_found[_udp.get_packet_ip()] = {"ip": _udp.get_packet_ip(),
					"count": int(parts[1]), "names": parts[2]}


func _names_list() -> Array[String]:
	var out: Array[String] = []
	for id in players:
		out.append(String(players[id]["name"]))
	return out


# ------------------------------------------------------------- host / join
## Game port, overridable by NET_PORT (headless test runs on one machine
## must not fight the real game for 24565).
func game_port() -> int:
	var env := OS.get_environment("NET_PORT")
	return int(env) if env != "" else GAME_PORT


func host_game() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(game_port(), MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	players.clear()
	players[1] = my_info.duplicate(true)
	# UDP responder for discovery
	_udp.close()
	_udp_open = _udp.bind(DISCOVERY_PORT) == OK
	players_changed.emit()
	return true


func join_game(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, game_port()) != OK:
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
	players.clear()
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


## Host moved everyone to another floor (or the town).
@rpc("authority", "call_remote", "reliable")
func set_floor(floor_number: int, town_return: int = -1) -> void:
	GameState.net_set_floor(floor_number, town_return)


func rpc_set_floor(floor_number: int, town_return: int = -1) -> void:
	if is_host:
		set_floor.rpc(floor_number, town_return)


## Host pushes its run state to a peer that joined mid-run.
@rpc("authority", "call_remote", "reliable")
func late_join(floor_number: int, seed_value: int, difficulty_id: StringName, eclipse := 0) -> void:
	GameState.begin_network_run(seed_value, difficulty_id, floor_number, eclipse)


func rpc_late_join(peer_id: int) -> void:
	if is_host:
		late_join.rpc_id(peer_id, GameState.floor_number, GameState.run_seed,
				GameState.difficulty.id if GameState.difficulty else &"normal", GameState.eclipse_level)


# ------------------------------------------------------------ difficulty
func enemy_hp_mult() -> float:
	if not active or players.size() <= 1:
		return 1.0
	return 1.0 + HP_PER_EXTRA * (mini(players.size(), MAX_PLAYERS) - 1)


func enemy_damage_mult() -> float:
	if not active or players.size() <= 1:
		return 1.0
	return 1.0 + DAMAGE_PER_EXTRA * (mini(players.size(), MAX_PLAYERS) - 1)


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
	if is_host:
		send_full_state(id)
		if GameState.run_active:
			# A friend arrived mid-run: pull them straight into the dungeon.
			late_join.rpc_id(id, GameState.floor_number, GameState.run_seed,
					GameState.difficulty.id if GameState.difficulty else &"normal", GameState.eclipse_level)


func _on_peer_disconnected(id: int) -> void:
	if is_host and players.has(id):
		EventBus.message.emit(tr("%s вышел") % players[id].get("name", tr("Игрок")))
		players.erase(id)
		broadcast_players()
		player_left.emit(id)
		# The host informs the game scene so the puppet gets removed.
		get_tree().call_group("net_game", "on_peer_left", id)


func _on_connected() -> void:
	register_player.rpc_id(1, my_info)


func _on_connect_failed() -> void:
	leave()
	EventBus.message.emit(tr("Не удалось подключиться"))


func _on_server_disconnected() -> void:
	leave(tr("Хост покинул игру"))
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.MAIN_MENU)

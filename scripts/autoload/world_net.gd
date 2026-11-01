extends Node
## Network manager of the world sessions (co-op in a save slot's world, up
## to Net.MAX_PLAYERS): the host loads a world and listens (ENet through
## Net), clients join by IP / LAN discovery with a nickname and an optional
## password. The host is the authority: it checks every join (protocol,
## game data checksum, password, seats, nickname), keeps the roster and the
## chat, decides every move of the loop (town → map → locations → result)
## and sends it to everyone (flow); clients send intentions only. Every RPC
## that a client may call checks its sender on the host.
## Profiles by nickname (the hero of each player kept in the host's world):
## see PlayerProfiles. Classic floor-after-floor co-op stays in Net/NetSync.

signal roster_changed
signal chat_received(nick: String, text: String)
## A join attempt ended: ok, or a reason key (FAIL_TEXT).
signal join_result(ok: bool, reason: String)
## The host wants this client to create a hero for its nickname.
signal hero_needed

## Bumped when the session messages change shape.
const PROTOCOL := 3
const DEFAULT_PORT := 7777
const NICK_MAX := 16
const CHAT_MAX := 160
const FAIL_TEXT := {
	"version": "Другая версия игры или игровых данных.",
	"password": "Неверный пароль.",
	"full": "Мир полон.",
	"nick": "Этот ник уже в игре.",
	"nick_bad": "Недопустимый ник.",
	"kicked": "Хост исключил вас из сессии.",
	"unreachable": "Хост не отвечает.",
	"host_left": "Хост завершил сессию. Мир сохранён у хоста.",
	"token": "Профиль с этим ником принадлежит другому игроку.",
	"busy": "Хост ещё не готов принять игроков.",
}

## A session of a world exists on this machine.
var session := false
var password := ""
var world_name := ""
## peer id -> {nick, key, status ("online" / "offline"), ready, race, cls, female}
var roster := {}
## Last chat lines [nick, text] (the HUD shows the tail).
var chat_log: Array = []
## Client: what we asked to join with (kept for the hero creation step).
var my_nick := ""
var my_token := ""
var _join_password := ""
var _accepted := {}  # host: peer id -> true once the handshake passed
## Tests: pretend to be another build (a different protocol in the hello).
var protocol_override := 0


## The town of the session (guests building, personal safes) and trading.
var town_net: Node
var trade: Node


func _ready() -> void:
	town_net = load("res://scripts/autoload/town_net.gd").new()
	town_net.name = "Town"
	add_child(town_net)
	trade = load("res://scripts/autoload/trade_net.gd").new()
	trade.name = "Trade"
	add_child(trade)
	add_child(SessionHud.new())  # after the trade node: it listens to it


# ================================================================== host
## Hosts the world of `slot`: loads it, then listens. "" on success, else
## the reason.
func host_world(slot: int, port := DEFAULT_PORT, p_password := "", seats := Net.MAX_PLAYERS, discoverable := true) -> String:
	if Net.active:
		Net.leave()
	if not GameFlow.continue_game(slot):
		return "load"
	if not Net.host_game(port, seats, discoverable):
		GameFlow.quit_to_menu()
		return "port"
	Net.world_session = true
	session = true
	_host_port = port
	password = p_password
	world_name = GameFlow.world_name
	roster.clear()
	_accepted.clear()
	chat_log.clear()
	var nick := normalize_nick(SaveManager.last_name)
	if nick == "":
		nick = tr("Хост")
	roster[1] = {"nick": nick, "key": nick_key(nick), "status": "online", "ready": true,
			"race": GameState.hero.race.id, "cls": GameState.hero.class_data.id, "female": GameState.hero.female}
	Net.players[1] = _net_info(roster[1])
	roster_changed.emit()
	return ""


## The string the LAN discovery answer carries: world, seats, lock, protocol, port.
func announce_extra() -> String:
	return ";%s;%d;%d;%d;%d" % [world_name.replace(";", ","), Net.max_players, 1 if password != "" else 0, PROTOCOL, _host_port]


var _host_port := DEFAULT_PORT


## Checksum of the game's data: every item, enemy, boss, biome, region,
## building, person and event id. Different data = a different game.
static func data_checksum() -> String:
	var ids: Array[String] = []
	for k in ItemDatabase.items:
		ids.append("i:" + String(k))
	for e in ItemDatabase.enemies:
		ids.append("e:" + String(e.id))
	for b in ItemDatabase.bosses:
		ids.append("b:" + String(b.id))
	for b in ItemDatabase.biomes:
		ids.append("m:" + String(b.id))
	for r in ItemDatabase.regions:
		ids.append("r:%s:%d:%d" % [r.id, r.depth_from, r.depth_to])
	for b in ItemDatabase.buildings:
		ids.append("h:" + String(b.id))
	for k in ItemDatabase.npcs:
		ids.append("n:" + String(k))
	for e in ItemDatabase.road_events:
		ids.append("v:" + String(e.id))
	ids.sort()
	var r: CoopRules = Net.rules()
	ids.append("c:%s:%s:%s:%s:%s:%s" % [r.hp_per_extra, r.damage_per_extra, r.boss_hp_per_extra,
			r.monsters_per_extra, r.reward_per_extra, r.friendly_bomb_mult])
	ids.append(String(ProjectSettings.get_setting("application/config/version", "")))
	return "|".join(ids).sha256_text()


## Trims, limits and filters a nickname (letters, digits, space, _ - .).
static func normalize_nick(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.is_valid_identifier() or ch.unicode_at(0) > 127 or ch in "0123456789 _-.":
			out += ch
	while "  " in out:
		out = out.replace("  ", " ")
	return out.strip_edges().left(NICK_MAX)


## Case-insensitive key of a nickname (profiles, conflicts).
static func nick_key(nick: String) -> String:
	return normalize_nick(nick).to_lower()


func _net_info(r: Dictionary) -> Dictionary:
	return {"name": r["nick"], "race": r["race"], "cls": r["cls"], "female": r["female"]}


# ---------------------------------------------------------------- client
## Joins the session at ip:port. The handshake starts once connected.
func join_world(ip: String, port: int, nick: String, p_password := "") -> bool:
	if Net.active:
		Net.leave()
	my_nick = normalize_nick(nick)
	_join_password = p_password
	my_token = PlayerProfiles.local_token()
	if my_nick == "":
		join_result.emit(false, "nick_bad")
		return false
	if not Net.join_game(ip, port):
		join_result.emit(false, "unreachable")
		return false
	Net.world_session = true
	session = true
	return true


## Net: connected to the host - introduce ourselves.
func on_connected() -> void:
	hello.rpc_id(1, {"protocol": protocol_override if protocol_override > 0 else PROTOCOL,
			"checksum": data_checksum(), "nick": my_nick,
			"password": _join_password, "token": my_token,
			"version": String(ProjectSettings.get_setting("application/config/version", ""))})


func fail(reason: String) -> void:
	session = false
	join_result.emit(false, reason)


static func fail_text(reason: String) -> String:
	return TranslationServer.translate(FAIL_TEXT.get(reason, TranslationServer.translate("Ошибка соединения.")))


## Host: a client introduces itself. Checks everything, then asks the
## profiles for its hero (PlayerProfiles.on_hello).
@rpc("any_peer", "call_remote", "reliable")
func hello(info: Dictionary) -> void:
	if not Net.is_host or not session:
		return
	var peer := multiplayer.get_remote_sender_id()
	var reason := ""
	var nick := normalize_nick(String(info.get("nick", "")))
	if int(info.get("protocol", 0)) != PROTOCOL or String(info.get("checksum", "")) != data_checksum():
		reason = "version"
	elif password != "" and String(info.get("password", "")) != password:
		reason = "password"
	elif nick == "" or nick != String(info.get("nick", "")).strip_edges().left(NICK_MAX):
		reason = "nick_bad"
	elif _online_count() >= Net.max_players:
		reason = "full"
	elif _nick_online(nick_key(nick)):
		reason = "nick"
	elif GameFlow.state != GameFlow.State.TOWN and GameFlow.state != GameFlow.State.EXPEDITION_MAP \
			and GameFlow.state != GameFlow.State.LOCATION:
		reason = "busy"
	if reason == "":
		reason = PlayerProfiles.check_token(nick, String(info.get("token", "")), peer)
		if reason == "pending":
			return  # the host decides (bind this device to the profile?)
	if reason != "":
		reject(peer, reason)
		return
	_accepted[peer] = {"nick": nick}
	PlayerProfiles.on_hello(peer, nick, String(info.get("token", "")))


## Host: refuses a peer with a reason and drops it a moment later.
func reject(peer: int, reason: String) -> void:
	rejected.rpc_id(peer, reason)
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if Net.multiplayer.multiplayer_peer and peer in Net.multiplayer.get_peers():
			Net.multiplayer.multiplayer_peer.disconnect_peer(peer))


@rpc("authority", "call_remote", "reliable")
func rejected(reason: String) -> void:
	session = false
	Net.leave()
	join_result.emit(false, reason)
	if reason == "kicked":
		GameFlow.client_left_session(fail_text(reason))


func _online_count() -> int:
	var n := 0
	for id in roster:
		if roster[id]["status"] == "online":
			n += 1
	return n


func _nick_online(key: String) -> bool:
	for id in roster:
		if roster[id]["key"] == key and roster[id]["status"] == "online":
			return true
	return false


## Host: the peer's hero is settled (an old profile or a new one) - it
## joins the roster and receives the world as it is now.
func admit(peer: int, nick: String, hero: Hero) -> void:
	for id in roster.keys():
		if roster[id]["key"] == nick_key(nick):
			roster.erase(id)  # the same player coming back
	roster[peer] = {"nick": nick, "key": nick_key(nick), "status": "online", "ready": false,
			"race": hero.race.id, "cls": hero.class_data.id, "female": hero.female}
	Net.players[peer] = _net_info(roster[peer])
	_broadcast_roster()
	system_line("%s входит в мир.", [nick])  # i18n-src
	enter_world.rpc_id(peer, RunCodec.save_hero(hero), GameFlow.flow_payload(), world_name)


## Client: we are in. The hero is ours, the world is the host's.
@rpc("authority", "call_remote", "reliable")
func enter_world(hero_dict: Dictionary, payload: Dictionary, p_world_name: String) -> void:
	world_name = p_world_name
	var hero := RunCodec.load_hero(hero_dict)
	if hero == null:
		join_result.emit(false, "version")
		Net.leave()
		return
	GameState.hero = hero
	PlayerProfiles.store_local_copy(hero_dict)
	join_result.emit(true, "")
	GameFlow.apply_remote_flow(payload)


# ---------------------------------------------------------------- roster
func _broadcast_roster() -> void:
	if not Net.is_host:
		return
	for id in roster:
		Net.players[id] = _net_info(roster[id]) if roster[id]["status"] == "online" else Net.players.get(id, {})
	sync_roster.rpc(roster, Net.players)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func sync_roster(p_roster: Dictionary, p_players: Dictionary) -> void:
	roster = p_roster
	Net.players = p_players
	roster_changed.emit()
	Net.players_changed.emit()


## Client → host: ready (or not) for the next expedition.
@rpc("any_peer", "call_remote", "reliable")
func set_ready(on: bool) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if roster.has(peer):
		roster[peer]["ready"] = on
		_broadcast_roster()


func toggle_ready() -> void:
	var me := multiplayer.get_unique_id()
	var on := not bool(roster.get(me, {}).get("ready", false))
	if Net.is_host:
		roster[1]["ready"] = on
		_broadcast_roster()
	else:
		set_ready.rpc_id(1, on)


func everyone_ready() -> bool:
	for id in roster:
		if roster[id]["status"] == "online" and not roster[id]["ready"]:
			return false
	return true


## Host: removes a player from the session (their profile stays).
func kick(peer: int) -> void:
	if not Net.is_host or peer == 1 or not roster.has(peer):
		return
	var nick := String(roster[peer]["nick"])
	PlayerProfiles.save_peer(peer)
	roster.erase(peer)
	Net.players.erase(peer)
	reject(peer, "kicked")
	_broadcast_roster()
	system_line("%s исключён из сессии.", [nick])  # i18n-src


## Net: a peer is gone. The host keeps its place as «offline» (the hero
## and the gear stay in the profile; the same nick comes back to them).
func on_peer_left(peer: int) -> void:
	_accepted.erase(peer)
	if Net.is_host and trade:
		trade.on_peer_left(peer)
	if not Net.is_host:
		return
	if roster.has(peer):
		PlayerProfiles.save_peer(peer)
		roster[peer]["status"] = "offline"
		roster[peer]["ready"] = false
		Net.players.erase(peer)
		system_line("%s отключился.", [String(roster[peer]["nick"])])  # i18n-src
		_broadcast_roster()
	get_tree().call_group("net_game", "on_peer_left", peer)


## Client: the host is gone - the session is over (the world is the host's).
func on_host_lost() -> void:
	session = false
	Net.leave()
	GameFlow.client_left_session(fail_text("host_left"))


## Host: ends the session (the world was saved by the caller).
func close_session() -> void:
	if session and Net.is_host:
		for id in roster:
			if id != 1 and roster[id]["status"] == "online":
				PlayerProfiles.save_peer(id)
	session = false
	roster.clear()
	if Net.active:
		Net.leave()


# ------------------------------------------------------------------ chat
## Anyone → host: a chat line (the host stamps the nickname).
@rpc("any_peer", "call_remote", "reliable")
func chat_send(text: String) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not roster.has(peer):
		return
	_chat_out(String(roster[peer]["nick"]), text)


func say(text: String) -> void:
	text = text.strip_edges().left(CHAT_MAX)
	if text == "" or not session:
		return
	if Net.is_host:
		_chat_out(String(roster.get(1, {}).get("nick", tr("Хост"))), text)
	else:
		chat_send.rpc_id(1, text)


func _chat_out(nick: String, text: String) -> void:
	text = text.strip_edges().left(CHAT_MAX).replace("[", "(")
	if text == "":
		return
	chat_line(nick, text)
	chat_line.rpc(nick, text)


@rpc("authority", "call_remote", "reliable")
func chat_line(nick: String, text: String) -> void:
	chat_log.append([nick, text])
	if chat_log.size() > 50:
		chat_log.pop_front()
	chat_received.emit(nick, text)
	AudioManager.play_ui(&"ui_click")


## Host: a line of the session's log (joins, leaves, deaths, finds) for
## everyone, each in their own language.
func system_line(fmt: String, args: Array = []) -> void:
	if not Net.is_host:
		return
	_system(fmt, args)
	_system.rpc(fmt, args)


@rpc("authority", "call_remote", "reliable")
func _system(fmt: String, args: Array) -> void:
	var text := tr(fmt) % args if not args.is_empty() else tr(fmt)
	chat_log.append(["", text])
	if chat_log.size() > 50:
		chat_log.pop_front()
	chat_received.emit("", text)


# -------------------------------------------------------- world settings
## Settings of the world for its sessions (TownState.flags, the host's):
## path: "vote" (majority, the host breaks ties) | "host";
## friendly_fire: "bombs" (default: bombs hurt allies a little) | "off" | "all";
## build_rule: "all" (default) | "host".
const SETTINGS := {"path": ["vote", "host"], "friendly_fire": ["bombs", "off", "all"], "build_rule": ["all", "host"]}


func setting(key: String) -> String:
	var t := GameState.town
	var d: String = SETTINGS[key][0]
	return String(t.flag(key, d)) if t else d


## Host: the next value of a setting (lobby buttons).
func cycle_setting(key: String) -> void:
	if not Net.is_host or GameState.town == null:
		return
	var vals: Array = SETTINGS[key]
	var i := vals.find(setting(key))
	GameState.town.set_flag(key, vals[(i + 1) % vals.size()])
	GameFlow.save_town()
	town_net.push_town()
	roster_changed.emit()


# ------------------------------------------------------------ path votes
signal votes_changed(votes: Dictionary)

## Host: peer -> map node id voted for (the current fork).
var votes := {}
var _vote_left := 0.0
const VOTE_TIME := 30.0


## Anyone: pick the next node. «host» rule: only the host's pick counts;
## «vote»: every online player votes, the majority wins once all voted (or
## the time is up), a tie goes the way the host voted.
func pick_node(id: int) -> void:
	if not session:
		GameFlow.enter_node(id)
		return
	if Net.is_host:
		_vote(1, id)
	else:
		vote_rpc.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func vote_rpc(id: int) -> void:
	if Net.is_host:
		_vote(multiplayer.get_remote_sender_id(), id)


func _vote(peer: int, id: int) -> void:
	var run := GameState.run
	if run == null or not id in run.next_choices() or not roster.has(peer):
		return
	if setting("path") == "host":
		if peer == 1:
			votes.clear()
			GameFlow.enter_node(id)
		return
	if votes.is_empty():
		_vote_left = VOTE_TIME
	votes[peer] = id
	_send_votes()
	var online := roster.keys().filter(func(p: int) -> bool: return roster[p]["status"] == "online")
	if online.all(func(p: int) -> bool: return votes.has(p)):
		_resolve_votes()


func _process(delta: float) -> void:
	if Net.is_host and not votes.is_empty() and _vote_left > 0.0:
		_vote_left -= delta
		if _vote_left <= 0.0:
			_resolve_votes()


func _resolve_votes() -> void:
	var count := {}
	for p in votes:
		count[votes[p]] = int(count.get(votes[p], 0)) + 1
	var best := -1
	var best_n := 0
	var tie := false
	for id in count:
		if count[id] > best_n:
			best = id
			best_n = count[id]
			tie = false
		elif count[id] == best_n:
			tie = true
	if tie and votes.has(1):
		best = votes[1]
	var host_vote: int = votes.get(1, best)
	if tie and not votes.has(1):
		best = host_vote
	votes.clear()
	_send_votes()
	if best >= 0:
		system_line("Отряд выбрал путь.")  # i18n-src
		GameFlow.enter_node(best)


func _send_votes() -> void:
	votes_changed.emit(votes)
	votes_sync.rpc(votes)


@rpc("authority", "call_remote", "reliable")
func votes_sync(v: Dictionary) -> void:
	votes = v
	votes_changed.emit(v)


# ------------------------------------------------------------ road events
## Host: the outcome of a road event reaches every hero of the party.
func share_event(event_id: StringName, text: String, effects: Dictionary) -> void:
	if session and Net.is_host and Net.active:
		event_result.rpc(event_id, text, effects)


@rpc("authority", "call_remote", "reliable")
func event_result(event_id: StringName, text: String, effects: Dictionary) -> void:
	var lines := EventRunner.apply(effects, true)
	for s in get_tree().get_nodes_in_group("event_spots"):
		(s as EventSpot).finish()
	var spot := get_tree().get_first_node_in_group("event_spots") as EventSpot
	var dlg: EventDialog = null
	for c in get_tree().current_scene.get_children() if get_tree().current_scene else []:
		if c is EventDialog:
			dlg = c
	if dlg == null and spot and spot.event:
		dlg = EventDialog.new()
		get_tree().current_scene.add_child(dlg)
		dlg.open(spot.event, null)
	if dlg:
		dlg.show_result(text, lines)


# --------------------------------------------------------------- rescues
## Guest → host: open the cage of this location (if its guards are dead).
@rpc("any_peer", "call_remote", "reliable")
func cage_request() -> void:
	if not Net.is_host:
		return
	var cage := get_tree().get_first_node_in_group("rescue_cages") as RescueCage
	var peer := multiplayer.get_remote_sender_id()
	if cage == null or cage.freed:
		return
	if cage.guards_left() > 0:
		_note.rpc_id(peer, "Ключ у тюремщика: сначала разберитесь с охраной.")  # i18n-src
		return
	cage.interact(get_tree().get_first_node_in_group("player"))


## Host: the cage is open - every guest sees the prisoner come out.
func cage_opened_all() -> void:
	if session and Net.is_host and Net.active:
		Net.send(self, &"cage_opened", [])


@rpc("authority", "call_remote", "reliable")
func cage_opened() -> void:
	var cage := get_tree().get_first_node_in_group("rescue_cages") as RescueCage
	if cage:
		cage.open_up(get_tree().get_first_node_in_group("player"))


@rpc("authority", "call_remote", "reliable")
func _note(text: String) -> void:
	EventBus.message.emit(tr(text))


# --------------------------------------------------------------- revives
## Anyone: raise a fallen ally standing next to them.
func revive(target_peer: int) -> void:
	if Net.is_host:
		_revive(multiplayer.get_unique_id(), target_peer)
	else:
		revive_request.rpc_id(1, target_peer)


@rpc("any_peer", "call_remote", "reliable")
func revive_request(target_peer: int) -> void:
	if Net.is_host:
		_revive(multiplayer.get_remote_sender_id(), target_peer)


func _revive(by: int, target: int) -> void:
	var game := get_tree().current_scene
	if game == null or not game.has_method("party"):
		return
	var helper: Player = null
	var fallen: Player = null
	for p: Player in game.party():
		if p.peer_id == by:
			helper = p
		if p.peer_id == target:
			fallen = p
	if helper == null or fallen == null or helper.dead or not fallen.dead \
			or helper.global_position.distance_to(fallen.global_position) > 48.0:
		return
	system_line("%s поднимает %s.", [String(roster.get(by, {}).get("nick", "?")), String(roster.get(target, {}).get("nick", "?"))])  # i18n-src
	if target == multiplayer.get_unique_id():
		_revived()
	else:
		_revived.rpc_id(target)


## The fallen hero of this machine stands up (35% health).
@rpc("authority", "call_remote", "reliable")
func _revived() -> void:
	var game := get_tree().current_scene
	if game and game.has_method("revive_local"):
		game.revive_local()


# ---------------------------------------------------------- marks, emotes
## G: «look here» - a mark at the mouse for everyone in this location.
func mark(pos: Vector2) -> void:
	var nick := String(roster.get(multiplayer.get_unique_id(), {}).get("nick", ""))
	_show_mark(pos, nick)
	Net.send(self, &"_show_mark", [pos, nick])


@rpc("any_peer", "call_remote", "unreliable")
func _show_mark(pos: Vector2, nick: String) -> void:
	var game := get_tree().current_scene
	if game == null or not ("level" in game) or game.level == null:
		return
	var m := UIStyle.outlined_label("▼ " + nick, 7, UIStyle.GOLD)
	m.position = pos + Vector2(-10, -24)
	m.z_index = 50
	game.level.add_child(m)
	var tw := m.create_tween()
	tw.tween_property(m, "position:y", pos.y - 30.0, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(2.4)
	tw.tween_property(m, "modulate:a", 0.0, 0.5)
	tw.tween_callback(m.queue_free)
	AudioManager.play_ui(&"ui_click")


const EMOTES := ["!", "?", "♥", "→", "Сюда!", "Помогите!"]


## F5–F8 (+): a short sign over my hero for the party.
func emote(i: int) -> void:
	var me := multiplayer.get_unique_id()
	_show_emote(me, i)
	Net.send(self, &"_show_emote", [me, i])


@rpc("any_peer", "call_remote", "unreliable")
func _show_emote(peer: int, i: int) -> void:
	var game := get_tree().current_scene
	if game == null or not game.has_method("party") or i < 0 or i >= EMOTES.size():
		return
	for p: Player in game.party():
		if p.peer_id == peer:
			var b := UIStyle.outlined_label(tr(EMOTES[i]), 9, UIStyle.PARCHMENT)
			b.position = Vector2(-8, -60)
			p.add_child(b)
			var tw := b.create_tween()
			tw.tween_property(b, "position:y", -68.0, 0.3)
			tw.tween_interval(1.6)
			tw.tween_property(b, "modulate:a", 0.0, 0.4)
			tw.tween_callback(b.queue_free)


# ------------------------------------------------------------------ flow
## Host → everyone: the loop moved on (state, town, expedition, location).
func broadcast_flow(new_state: int) -> void:
	if session and Net.is_host and Net.active:
		flow.rpc(GameFlow.flow_payload(new_state))


@rpc("authority", "call_remote", "reliable")
func flow(payload: Dictionary) -> void:
	GameFlow.apply_remote_flow(payload)

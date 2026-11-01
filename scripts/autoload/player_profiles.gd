extends Node
## Heroes of the players of a world, by nickname (stage 11). The host's
## world save is the only truth: TownState.players[nick key] = {nick, hero
## (RunCodec hero dict), token (sha256 of the client's secret), created,
## last_seen, stats}. A client proves its nickname with a secret token kept
## in user://identity.cfg; a different device asks the host to bind it.
## Clients push their hero to the host at save points (and every PUSH_EVERY
## seconds); the host keeps the last one, also when the client drops. A
## read-only copy lives on the client (user://client_profiles/<world>/<nick>.save):
## profiles never travel between worlds.

signal approval_needed(peer: int, nick: String)

const IDENTITY := "user://identity.cfg"
## Where this machine's token lives (tests run several "machines" at once).
static var identity_path := IDENTITY
const PUSH_EVERY := 20.0
## A pushed hero may not jump more levels than this between two pushes.
const MAX_LEVEL_STEP := 4

## Host: peers waiting for the host to bind their device to a profile.
var pending := {}  # peer -> {nick, token}
## Host: peers creating a new hero.
var creating := {}  # peer -> nick
var _push_left := PUSH_EVERY


func _process(delta: float) -> void:
	if not WorldNet.session or Net.is_host or GameState.hero == null:
		return
	_push_left -= delta
	if _push_left <= 0.0:
		_push_left = PUSH_EVERY
		push_now()


# ------------------------------------------------------------ identity
## This machine's secret token (made once).
static func local_token() -> String:
	var cfg := ConfigFile.new()
	cfg.load(identity_path)
	var t: String = cfg.get_value("identity", "token", "")
	if t == "":
		var c := Crypto.new()
		t = c.generate_random_bytes(24).hex_encode()
		cfg.set_value("identity", "token", t)
		cfg.save(identity_path)
	return t


## «Мои профили» → reset: a new token (old profiles need the host's bind).
static func reset_token() -> void:
	var cfg := ConfigFile.new()
	cfg.load(identity_path)
	cfg.set_value("identity", "token", "")
	cfg.save(identity_path)
	local_token()


static func hash_token(token: String) -> String:
	return ("eclipse:" + token).sha256_text()


# ---------------------------------------------------------------- host
func _profiles() -> Dictionary:
	return GameState.town.players if GameState.town else {}


func profile(nick: String) -> Dictionary:
	return _profiles().get(WorldNet.nick_key(nick), {})


## "" when `token` may use `nick`'s profile; "pending" puts the peer on
## hold until the host binds the device (approve) or refuses (deny).
func check_token(nick: String, token: String, peer: int) -> String:
	var p := profile(nick)
	if p.is_empty() or String(p.get("token", "")) == "" or String(p["token"]) == hash_token(token):
		return ""
	pending[peer] = {"nick": nick, "token": token}
	approval_needed.emit(peer, nick)
	WorldNet.system_line("%s просит войти с нового устройства: хост должен подтвердить.", [nick])  # i18n-src
	waiting_approval.rpc_id(peer)
	return "pending"


@rpc("authority", "call_remote", "reliable")
func waiting_approval() -> void:
	WorldNet.join_result.emit(false, "pending")


## Host: «Привязать этот клиент к профилю Nick?» - yes.
func approve(peer: int) -> void:
	if not pending.has(peer):
		return
	var info: Dictionary = pending[peer]
	pending.erase(peer)
	var p := profile(info["nick"])
	p["token"] = hash_token(info["token"])
	on_hello(peer, info["nick"], info["token"])


func deny(peer: int) -> void:
	if pending.has(peer):
		pending.erase(peer)
		WorldNet.reject(peer, "token")


## Host: the handshake passed. A known nickname gets its hero back, a new
## one creates a hero first.
func on_hello(peer: int, nick: String, token: String) -> void:
	var key := WorldNet.nick_key(nick)
	var p := profile(nick)
	if not p.is_empty():
		var hero := RunCodec.load_hero(p.get("hero", {}))
		if hero != null:
			p["last_seen"] = int(Time.get_unix_time_from_system())
			p["nick"] = nick
			if String(p.get("token", "")) == "":
				p["token"] = hash_token(token)
			WorldNet.admit(peer, nick, hero)
			return
	creating[peer] = {"nick": nick, "token": token, "key": key}
	need_hero.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func need_hero() -> void:
	WorldNet.hero_needed.emit()


## Client: the new hero's race, class and sex (CharacterCreation).
func create_hero(race: StringName, cls: StringName, female: bool) -> void:
	create_hero_request.rpc_id(1, race, cls, female)


## Host: builds the new player's hero (starting kit) - only for a peer that
## was asked to, only from races and classes that exist.
@rpc("any_peer", "call_remote", "reliable")
func create_hero_request(race_id: StringName, cls_id: StringName, female: bool) -> void:
	if not Net.is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not creating.has(peer):
		return
	var info: Dictionary = creating[peer]
	creating.erase(peer)
	var race: RaceData = null
	var cls: ClassData = null
	for r in ItemDatabase.races:
		if r.id == race_id:
			race = r
	for c in ItemDatabase.classes:
		if c.id == cls_id:
			cls = c
	if race == null or cls == null:
		WorldNet.reject(peer, "version")
		return
	var hero := Hero.new(race, cls, ItemDatabase.equipment_layout)
	hero.female = female
	hero.give_starting_kit()
	GameState.apply_eclipse(hero)
	hero.skills.add_points(1)
	GameState.town.players[info["key"]] = {
		"nick": info["nick"], "hero": RunCodec.save_hero(hero), "token": hash_token(info["token"]),
		"created": int(Time.get_unix_time_from_system()), "last_seen": int(Time.get_unix_time_from_system()),
		"stats": {},
	}
	GameFlow.save_town()
	WorldNet.admit(peer, info["nick"], hero)


## Host: the host's own hero is a profile too (its nickname).
func save_host() -> void:
	if not Net.is_host or GameState.town == null or GameState.hero == null:
		return
	var r: Dictionary = WorldNet.roster.get(1, {})
	if r.is_empty():
		return
	var key := String(r["key"])
	var p: Dictionary = GameState.town.players.get(key, {"nick": r["nick"], "created": int(Time.get_unix_time_from_system()), "stats": {}})
	p["hero"] = RunCodec.save_hero(GameState.hero)
	p["token"] = hash_token(local_token())
	p["last_seen"] = int(Time.get_unix_time_from_system())
	GameState.town.players[key] = p


## Host: keep what a peer last pushed (it is already in the profile).
func save_peer(peer: int) -> void:
	var r: Dictionary = WorldNet.roster.get(peer, {})
	if r.is_empty() or GameState.town == null:
		return
	var p: Dictionary = GameState.town.players.get(String(r["key"]), {})
	if not p.is_empty():
		p["last_seen"] = int(Time.get_unix_time_from_system())
	GameFlow.save_town()


## Host → clients: send your heroes (an autosave is under way).
func request_all() -> void:
	if Net.is_host and WorldNet.session:
		send_hero.rpc()


@rpc("authority", "call_remote", "reliable")
func send_hero() -> void:
	push_now()


## Client → host: my hero as it is now.
func push_now() -> void:
	if GameState.hero == null or not WorldNet.session or Net.is_host:
		return
	var d := RunCodec.save_hero(GameState.hero)
	store_local_copy(d)
	push_hero.rpc_id(1, d)


## Host: a peer's hero. Sane only: the same race and class as its profile,
## no wild jump in level; then it replaces the profile's hero.
@rpc("any_peer", "call_remote", "reliable")
func push_hero(d: Dictionary) -> void:
	if not Net.is_host or GameState.town == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	var r: Dictionary = WorldNet.roster.get(peer, {})
	if r.is_empty() or r.get("status") != "online":
		return
	var p: Dictionary = GameState.town.players.get(String(r["key"]), {})
	if p.is_empty():
		return
	var old: Dictionary = p.get("hero", {})
	if String(d.get("race", "")) != String(old.get("race", "")) or String(d.get("class", "")) != String(old.get("class", "")):
		return
	if int(d.get("level", 1)) > int(old.get("level", 1)) + MAX_LEVEL_STEP:
		return
	if RunCodec.load_hero(d) == null:
		return
	p["hero"] = d
	p["last_seen"] = int(Time.get_unix_time_from_system())


## Host: the profile's hero of a nickname (tests, the journal).
func hero_of(nick: String) -> Hero:
	var p := profile(nick)
	return RunCodec.load_hero(p.get("hero", {})) if not p.is_empty() else null


# --------------------------------------------------------------- client
## A read-only copy of my hero in this world (never loaded back into
## another world: the host's save is the truth).
func store_local_copy(hero_dict: Dictionary) -> void:
	if not WorldNet.session or Net.is_host:
		return
	var dir := "user://client_profiles/%s/" % _world_tag()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "hero", hero_dict)
	cfg.set_value("profile", "world", WorldNet.world_name)
	cfg.save(dir + WorldNet.nick_key(WorldNet.my_nick).validate_filename() + ".save")


func _world_tag() -> String:
	var seed_value: int = GameState.town.world_seed if GameState.town else 0
	return ("%s_%d" % [WorldNet.world_name, seed_value]).validate_filename()

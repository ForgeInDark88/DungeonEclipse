class_name NetSettings
extends RefCounted
## The network options of this computer (main menu → Мультиплеер), kept in
## user://net_settings.cfg: the defaults of the host form (port, players,
## password, LAN visibility, the world rules of a session) and of the join
## screen (nickname, last address).

const PATH := "user://net_settings.cfg"
static var path := PATH

const DEFAULTS := {
	"port": 7777, "seats": 4, "password": "", "lan": true,
	"path": "vote", "friendly_fire": "bombs", "build_rule": "all",
	"nick": "", "address": "127.0.0.1", "join_port": 7777,
}


static func get_value(key: String) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg.get_value("net", key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("net", key, value)
	cfg.save(path)


## The rules a new session of any world starts with (WorldNet.SETTINGS keys).
static func rules() -> Dictionary:
	var out := {}
	for k in ["path", "friendly_fire", "build_rule"]:
		out[k] = String(get_value(k))
	return out


## The local read-only copies of my heroes in other people's worlds:
## [{world, nick, race, class, level}].
static func local_profiles() -> Array:
	var out := []
	var root := "user://client_profiles/"
	for world in DirAccess.get_directories_at(root):
		for f in DirAccess.get_files_at(root + world):
			if not f.ends_with(".save"):
				continue
			var cfg := ConfigFile.new()
			if cfg.load(root + world + "/" + f) != OK:
				continue
			var h: Dictionary = cfg.get_value("profile", "hero", {})
			out.append({"world": String(cfg.get_value("profile", "world", world)), "nick": f.get_basename(),
					"race": String(h.get("race", "")), "class": String(h.get("class", "")), "level": int(h.get("level", 1))})
	return out

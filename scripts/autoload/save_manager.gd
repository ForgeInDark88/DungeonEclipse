extends Node
## Saves settings and meta progress (the run itself is not saved: permadeath).

const SETTINGS_PATH := "user://settings.cfg"
const META_PATH := "user://meta.cfg"

var master_volume: float = 0.8
var fullscreen: bool = false

var best_floor: int = 0
var total_runs: int = 0
var total_kills: int = 0


func _ready() -> void:
	load_settings()
	load_meta()
	apply_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func load_meta() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return
	best_floor = cfg.get_value("meta", "best_floor", 0)
	total_runs = cfg.get_value("meta", "total_runs", 0)
	total_kills = cfg.get_value("meta", "total_kills", 0)


func save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "best_floor", best_floor)
	cfg.set_value("meta", "total_runs", total_runs)
	cfg.set_value("meta", "total_kills", total_kills)
	cfg.save(META_PATH)


func record_run(floor_reached: int, kills: int) -> void:
	total_runs += 1
	total_kills += kills
	best_floor = maxi(best_floor, floor_reached)
	save_meta()

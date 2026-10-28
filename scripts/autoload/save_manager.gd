extends Node
## Saves settings and meta progress. The run itself is saved between floors
## (the snapshot of the last floor start, user://run.cfg): the floor is
## deterministic, so Continue rebuilds it from the run seed.

## Emitted after settings are saved (HUD refreshes key hints).
signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const META_PATH := "user://meta.cfg"
const RUN_PATH := "user://run.cfg"

var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
var ui_volume: float = 0.7
var fullscreen: bool = false
## World brightness multiplier (Settings → «Яркость»).
var brightness: float = 1.0
## Size of the bottom HUD panel (Settings → «Размер панели»), 0.6–1.0.
var hud_scale: float = 1.0
## Graphics (Settings): bloom glow of bright pixels, block shadows on the back wall.
var bloom: bool = true
var block_shadows: bool = true
var show_damage_numbers: bool = true
var show_hints: bool = true
## Difficulty picked last time in hero creation (DifficultyData.id).
var last_difficulty: String = "normal"
## Network nickname (persisted between sessions).
var last_name: String = ""
## Ids of beginner hints already shown (HintManager).
var seen_hints: Array = []

var best_floor: int = 0
var total_runs: int = 0
var total_kills: int = 0


func _ready() -> void:
	InputBindings.capture_defaults()
	load_settings()
	load_meta()
	apply_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	ui_volume = cfg.get_value("audio", "ui_volume", ui_volume)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	brightness = cfg.get_value("video", "brightness", brightness)
	hud_scale = cfg.get_value("video", "hud_scale", hud_scale)
	bloom = cfg.get_value("video", "bloom", bloom)
	block_shadows = cfg.get_value("video", "block_shadows", block_shadows)
	show_damage_numbers = cfg.get_value("game", "damage_numbers", show_damage_numbers)
	show_hints = cfg.get_value("game", "hints", show_hints)
	seen_hints = cfg.get_value("game", "seen_hints", [])
	last_difficulty = cfg.get_value("game", "difficulty", last_difficulty)
	last_name = cfg.get_value("game", "name", last_name)
	InputBindings.apply_overrides(cfg.get_value("input", "bindings", {}))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "hud_scale", hud_scale)
	cfg.set_value("video", "bloom", bloom)
	cfg.set_value("video", "block_shadows", block_shadows)
	cfg.set_value("game", "damage_numbers", show_damage_numbers)
	cfg.set_value("game", "hints", show_hints)
	cfg.set_value("game", "seen_hints", seen_hints)
	cfg.set_value("game", "difficulty", last_difficulty)
	cfg.set_value("game", "name", last_name)
	cfg.set_value("input", "bindings", InputBindings.overrides())
	cfg.save(SETTINGS_PATH)
	settings_changed.emit()


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.apply_volumes()
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
	if FileAccess.file_exists(META_PATH):
		cfg.load(META_PATH)  # keep the other sections (sanctum, achievements...)
	cfg.set_value("meta", "best_floor", best_floor)
	cfg.set_value("meta", "total_runs", total_runs)
	cfg.set_value("meta", "total_kills", total_kills)
	cfg.save(META_PATH)


func record_run(floor_reached: int, kills: int) -> void:
	total_runs += 1
	total_kills += kills
	best_floor = maxi(best_floor, floor_reached)
	save_meta()


# --------------------------------------------------------------- run save
## A between-floors snapshot exists (main menu shows «Продолжить»).
func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


## Writes the current GameState as the floor-start snapshot. Only call it
## right after a floor is (re)built — the floor regenerates from the seed,
## so a mid-floor snapshot would duplicate picked-up loot.
func save_run() -> void:
	if GameState.hero == null or not GameState.run_active:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("run", "data", RunCodec.save_run())
	cfg.save(RUN_PATH)


## The saved run data ({} = no save).
func run_data() -> Dictionary:
	if not has_run():
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(RUN_PATH) != OK:
		return {}
	return cfg.get_value("run", "data", {})


## Death or a brand new run: the snapshot is gone (permadeath).
func clear_run() -> void:
	if has_run():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))

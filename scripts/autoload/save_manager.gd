extends Node
## Saves settings and meta progress. The run itself is saved between floors
## (the snapshot of the last floor start, user://run.cfg): the floor is
## deterministic, so Continue rebuilds it from the run seed.

## Emitted after settings are saved (HUD refreshes key hints).
signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const META_PATH := "user://meta.cfg"
const RUN_PATH := "user://run.cfg"
## The town between expeditions (TownState + the hero): GameFlow.
const TOWN_PATH := "user://town.save"
## Format of the town save. Bump it when TownState changes shape and add the
## step to migrate_town(); a save of a newer game is never half-loaded.
const TOWN_FORMAT := 2
## Format of the meta save (sanctum, codex, records). Bump it when a section
## changes shape and add the step to migrate_meta(); older files are
## upgraded on load, files of a newer game are left untouched.
const META_FORMAT := 2

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
## Settings → «Живость мира»: the quiet life of the world - grass, small
## animals, swaying foliage, drifting clouds, shafts of light, the
## foreground branch. 2 full, 1 a little, 0 off (weak machines, or a
## player whom it distracts). Water, light and the night sky stay.
var scenery: int = 2
## Language (Localizer): "ru", "en"; "" = pick by the system language.
var language: String = ""
var show_damage_numbers: bool = true
var show_hints: bool = true
## Difficulty picked last time in hero creation (DifficultyData.id).
var last_difficulty: String = "normal"
## Level of the Eclipse picked last time.
var last_eclipse: int = 0
## Network nickname (persisted between sessions).
var last_name: String = ""
## Ids of beginner hints already shown (HintManager).
var seen_hints: Array = []

var best_floor: int = 0
var total_runs: int = 0
var total_kills: int = 0


## How much of the quiet life of the world to show: 0, 0.5 or 1.
func scenery_amount() -> float:
	return [0.0, 0.5, 1.0][clampi(scenery, 0, 2)]


func _ready() -> void:
	InputBindings.capture_defaults()
	load_settings()
	migrate_legacy_town()
	load_meta()
	apply_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if read_cfg(cfg, SETTINGS_PATH) != OK:
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
	scenery = clampi(int(cfg.get_value("video", "scenery", scenery)), 0, 2)
	show_damage_numbers = cfg.get_value("game", "damage_numbers", show_damage_numbers)
	language = cfg.get_value("game", "language", language)
	show_hints = cfg.get_value("game", "hints", show_hints)
	seen_hints = cfg.get_value("game", "seen_hints", [])
	last_difficulty = cfg.get_value("game", "difficulty", last_difficulty)
	last_eclipse = cfg.get_value("game", "eclipse", last_eclipse)
	last_name = cfg.get_value("game", "name", last_name)
	last_slot = cfg.get_value("game", "last_slot", last_slot)
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
	cfg.set_value("video", "scenery", scenery)
	cfg.set_value("game", "damage_numbers", show_damage_numbers)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "hints", show_hints)
	cfg.set_value("game", "seen_hints", seen_hints)
	cfg.set_value("game", "difficulty", last_difficulty)
	cfg.set_value("game", "eclipse", last_eclipse)
	cfg.set_value("game", "name", last_name)
	cfg.set_value("game", "last_slot", last_slot)
	cfg.set_value("input", "bindings", InputBindings.overrides())
	write_cfg(cfg, SETTINGS_PATH)
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
	if read_cfg(cfg, meta_path) != OK:
		return
	best_floor = cfg.get_value("meta", "best_floor", 0)
	total_runs = cfg.get_value("meta", "total_runs", 0)
	total_kills = cfg.get_value("meta", "total_kills", 0)


func save_meta() -> void:
	var cfg := ConfigFile.new()
	read_cfg(cfg, meta_path)  # keep the other sections (sanctum, achievements...)
	migrate_meta(cfg)
	cfg.set_value("meta", "best_floor", best_floor)
	cfg.set_value("meta", "total_runs", total_runs)
	cfg.set_value("meta", "total_kills", total_kills)
	write_cfg(cfg, meta_path)


func record_run(floor_reached: int, kills: int) -> void:
	total_runs += 1
	total_kills += kills
	best_floor = maxi(best_floor, floor_reached)
	save_meta()


# --------------------------------------------------------------- run save
## A between-floors snapshot exists (main menu shows «Продолжить»).
# ------------------------------------------------------- safe file access
## Writes `cfg` so that a crash mid-write never breaks the save: into a
## temporary file first, the previous version kept as `.bak`, then swapped.
func write_cfg(cfg: ConfigFile, path: String) -> Error:
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return err
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		# Only a readable file becomes the backup (never back up garbage).
		if ConfigFile.new().load(path) == OK:
			DirAccess.copy_absolute(abs_path, abs_path + ".bak")
		DirAccess.remove_absolute(abs_path)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)


## Loads `path` into `cfg`; a broken or missing file falls back to the
## `.bak` copy written by write_cfg. OK when either one loaded.
func read_cfg(cfg: ConfigFile, path: String) -> Error:
	if FileAccess.file_exists(path) and cfg.load(path) == OK:
		return OK
	if FileAccess.file_exists(path + ".bak") and cfg.load(path + ".bak") == OK:
		push_warning("Save %s was unreadable: restored the backup copy" % path)
		return OK
	return ERR_FILE_NOT_FOUND


## The meta save of an older game is upgraded step by step (format 1 had
## no «save» section; format 2 added the levels of the Eclipse - defaults).
func migrate_meta(cfg: ConfigFile) -> void:
	var fmt: int = cfg.get_value("save", "format", 1)
	if fmt > META_FORMAT:
		push_warning("meta.cfg comes from a newer game (format %d)" % fmt)
		return
	if fmt < 2:
		if not cfg.has_section_key("sanctum", "eclipse_unlocked"):
			cfg.set_value("sanctum", "eclipse_unlocked", 0)
	cfg.set_value("save", "format", META_FORMAT)


# ------------------------------------------------------------ world slots
## A world = one save slot: the town and its people, the Sanctum, the
## chronicle, the records, the heroes' profiles, the expedition under way.
##   user://saves/slot_N/world.save  - TownState + world info (checksum)
##   user://saves/slot_N/meta.cfg    - Sanctum, codex, records of the world
##   user://saves/slot_N/run.save    - the expedition under way (checksum)
##   user://saves/slot_N/thumb.png   - a miniature for the load screen
const SAVES_DIR := "user://saves/"
const SLOT_COUNT := 5
## Where the slots live (tests use their own folder).
var saves_dir := SAVES_DIR
## The town save of the old game (before the slots; tests point it elsewhere).
var legacy_town_path := TOWN_PATH
## Remember the slot in play in the settings (tests turn it off).
var remember_slot := true

## Slot in play (0 = none: the classic co-op run, tests).
var slot := 0
## The last slot played (main menu «Продолжить»).
var last_slot := 0
## Where the world of the slot in play is saved (tests point it elsewhere).
var town_path := TOWN_PATH
## Where the meta progress (Sanctum, codex, records) of the world lives.
var meta_path := META_PATH
## Why the last load_town() failed: "" | "missing" | "damaged" | "newer".
var last_error := ""
## The last load_town() came from the .bak copy (the main file was damaged).
var used_backup := false


func slot_dir(n: int) -> String:
	return saves_dir + "slot_%d/" % n


func slot_exists(n: int) -> bool:
	var w := slot_dir(n) + "world.save"
	return FileAccess.file_exists(w) or FileAccess.file_exists(w + ".bak")


## Makes slot `n` the world in play: every save goes there from now on and
## the world's meta progress (Sanctum, codex, records) is loaded.
func use_slot(n: int) -> void:
	slot = n
	if n > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slot_dir(n)))
		town_path = slot_dir(n) + "world.save"
		meta_path = slot_dir(n) + "meta.cfg"
		if remember_slot:
			last_slot = n
			save_settings()
	else:
		town_path = TOWN_PATH
		meta_path = META_PATH
	reload_meta()


## (Re)loads the meta progress of the world in play from `meta_path`.
func reload_meta() -> void:
	best_floor = 0
	total_runs = 0
	total_kills = 0
	load_meta()
	MetaProgress.reset_values()
	MetaProgress.load_progress()
	Codex.clear_progress()
	Codex.load_progress()


## What the load screen shows of a slot: {exists, name, updated (unix),
## playtime (s), region, prosperity, heroes, state, broken}.
func slot_info(n: int) -> Dictionary:
	var out := {"exists": slot_exists(n), "slot": n}
	if not out["exists"]:
		return out
	var r := _read_checked(slot_dir(n) + "world.save", "town")
	if r.is_empty():
		out["broken"] = true
		return out
	var info: Dictionary = r.get("info", {})
	var t: Dictionary = r.get("data", {})
	out["name"] = String(info.get("name", tr("Мир %d") % n))
	out["updated"] = int(info.get("updated", 0))
	out["playtime"] = int(info.get("playtime", 0))
	out["prosperity"] = int(t.get("prosperity", 0))
	var reg := int(t.get("region_unlocked", 0))
	out["region"] = ItemDatabase.regions[mini(reg, ItemDatabase.regions.size() - 1)].display_name if not ItemDatabase.regions.is_empty() else ""
	out["heroes"] = maxi(1, (t.get("players", {}) as Dictionary).size()) if t.get("players") is Dictionary else 1
	out["state"] = tr("в походе") if FileAccess.file_exists(slot_dir(n) + "run.save") else tr("в городе")
	out["backup"] = r.get("backup", false)
	return out


func rename_slot(n: int, new_name: String) -> bool:
	var r := _read_checked(slot_dir(n) + "world.save", "town")
	if r.is_empty():
		return false
	var info: Dictionary = r.get("info", {})
	info["name"] = new_name.strip_edges().left(32)
	return _write_checked(slot_dir(n) + "world.save", "town", r["data"], info, int(r["format"])) == OK


## Wipes slot `n` for good (the confirmation is the menu's job).
func delete_slot(n: int) -> void:
	var dir := ProjectSettings.globalize_path(slot_dir(n))
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			da.remove(f)
	DirAccess.remove_absolute(dir)
	if last_slot == n and remember_slot:
		last_slot = 0
		save_settings()


## The first slot with no world in it (0 = all taken).
func free_slot() -> int:
	for n in range(1, SLOT_COUNT + 1):
		if not slot_exists(n):
			return n
	return 0


## A miniature of the world for the load screen (taken in town).
func save_thumbnail(img: Image) -> void:
	if slot <= 0 or img == null or img.is_empty():
		return
	var t := img.duplicate() as Image
	t.resize(128, 72, Image.INTERPOLATE_BILINEAR)
	t.save_png(slot_dir(slot) + "thumb.png")


func slot_thumbnail(n: int) -> Texture2D:
	var path := slot_dir(n) + "thumb.png"
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


# ----------------------------------------------- checked files (checksum)
## Writes `data` with a format number and a checksum of its contents (a
## ConfigFile: every value keeps its type), atomically with a backup.
func _write_checked(path: String, section: String, data: Variant, info: Dictionary, fmt: int) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "format", fmt)
	cfg.set_value("save", "version", ProjectSettings.get_setting("application/config/version", ""))
	cfg.set_value("save", "checksum", var_to_str(data).sha256_text())
	cfg.set_value("save", "info", info)
	cfg.set_value(section, "data", data)
	return write_cfg(cfg, path)


## Reads a checked file (the main one, then its .bak): {data, info, format,
## backup} or {} with last_error set. A newer format is never half-loaded.
func _read_checked(path: String, section: String) -> Dictionary:
	last_error = "missing"
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(p) != OK:
			last_error = "damaged"
			continue
		var fmt: Variant = cfg.get_value("save", "format", 0)
		var d: Variant = cfg.get_value(section, "data", null)
		if not (fmt is int) or fmt <= 0 or d == null:
			last_error = "damaged"
			push_warning("%s is damaged, trying the backup" % p)
			continue
		if fmt > TOWN_FORMAT:
			last_error = "newer"
			push_warning("%s comes from a newer game (format %d)" % [p, fmt])
			return {}
		var sum: Variant = cfg.get_value("save", "checksum", "")
		if sum is String and sum != "" and sum != var_to_str(d).sha256_text():
			last_error = "damaged"
			push_warning("%s: checksum mismatch, trying the backup" % p)
			continue
		last_error = ""
		return {"data": d, "info": cfg.get_value("save", "info", {}), "format": fmt, "backup": p != path}
	return {}


# -------------------------------------------------------------- town save
func has_town() -> bool:
	return FileAccess.file_exists(town_path) or FileAccess.file_exists(town_path + ".bak")


## Writes the town of the world in play (with the world's info).
func save_town(town: TownState, info: Dictionary = {}) -> Error:
	if town == null:
		return ERR_INVALID_PARAMETER
	if info.is_empty():
		var old := _read_checked(town_path, "town")
		info = old.get("info", {}) if not old.is_empty() else {}
	info["updated"] = int(Time.get_unix_time_from_system())
	return _write_checked(town_path, "town", town.to_dict(), info, TOWN_FORMAT)


## The saved town, or null when there is none, it cannot be read (the
## backup copy is tried first, used_backup tells) or it is from a newer game.
func load_town() -> TownState:
	used_backup = false
	var r := _read_checked(town_path, "town")
	if r.is_empty() or not (r["data"] is Dictionary):
		return null
	used_backup = r.get("backup", false)
	return TownState.from_dict(migrate_town(r["data"], int(r["format"])))


## The world's info (name, playtime, created, updated) of the slot in play.
func world_info() -> Dictionary:
	var r := _read_checked(town_path, "town")
	return r.get("info", {}) if not r.is_empty() else {}


## Upgrades an older town save one format step at a time.
##  1 → 2: the world gets its slot info (name, playtime) - defaults.
func migrate_town(d: Dictionary, from: int) -> Dictionary:
	if from < 2:
		d["world_seed"] = int(d.get("world_seed", randi()))
	return d


## A new game: the town and its hero are gone.
func clear_town() -> void:
	for p in [town_path, town_path + ".bak", town_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## The town save of the old game (user://town.save, before the slots) moves
## into slot 1 together with the meta progress, once.
func migrate_legacy_town() -> void:
	if not FileAccess.file_exists(legacy_town_path) or slot_exists(1):
		return
	var keep_path := town_path
	town_path = legacy_town_path
	var old := load_town()
	town_path = keep_path
	if old == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slot_dir(1)))
	var tp := town_path
	town_path = slot_dir(1) + "world.save"
	save_town(old, {"name": tr("Мир 1"), "created": int(Time.get_unix_time_from_system()), "playtime": 0})
	town_path = tp
	if FileAccess.file_exists(legacy_meta_path()):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(legacy_meta_path()), ProjectSettings.globalize_path(slot_dir(1) + "meta.cfg"))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(legacy_town_path), ProjectSettings.globalize_path(legacy_town_path + ".migrated"))
	if remember_slot:
		last_slot = 1
		save_settings()


func legacy_meta_path() -> String:
	return META_PATH if legacy_town_path == TOWN_PATH else legacy_town_path.get_base_dir() + "/meta.cfg"


# --------------------------------------------------------- expedition save
## The expedition under way in the slot in play (anti save-scumming: a
## loaded run.save is marked used; a death deletes it).
func run_save_path() -> String:
	return (slot_dir(slot) if slot > 0 else "user://") + "run.save"


func save_expedition(data: Dictionary) -> Error:
	return _write_checked(run_save_path(), "run", data, {"updated": int(Time.get_unix_time_from_system())}, TOWN_FORMAT)


## {} when there is no expedition save (or it cannot be read).
func load_expedition() -> Dictionary:
	var r := _read_checked(run_save_path(), "run")
	return r["data"] if not r.is_empty() and r["data"] is Dictionary else {}


func has_expedition() -> bool:
	return FileAccess.file_exists(run_save_path()) or FileAccess.file_exists(run_save_path() + ".bak")


func clear_expedition() -> void:
	for p in [run_save_path(), run_save_path() + ".bak", run_save_path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


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
	write_cfg(cfg, RUN_PATH)


## The saved run data ({} = no save).
func run_data() -> Dictionary:
	if not has_run():
		return {}
	var cfg := ConfigFile.new()
	if read_cfg(cfg, RUN_PATH) != OK:
		return {}
	return cfg.get_value("run", "data", {})


## Death or a brand new run: the snapshot is gone (permadeath).
func clear_run() -> void:
	for p in [RUN_PATH, RUN_PATH + ".bak", RUN_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

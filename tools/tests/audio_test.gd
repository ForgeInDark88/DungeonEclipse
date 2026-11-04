extends SceneTree
## The sound system (AudioManager, docs/AUDIO_LIST.md):
## - buses Music / SFX / UI / Ambient, ambience on its own bus;
## - every biome has acoustics, reverb on in a crypt, off under the sky;
## - voice priorities: a step never takes a voice from a hero's cry;
## - the combat layer switches on and off;
## - every sound id and music track has its file, variants are found.
##   godot --headless -s tools/tests/audio_test.gd

var fails := 0


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		print("FAIL: " + what)


func _initialize() -> void:
	await process_frame
	var am = root.get_node("AudioManager")
	var ap: Script = load("res://scripts/core/asset_paths.gd")
	for b in ["Music", "SFX", "UI", "Ambient"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	am.play_ambience(&"amb_wind", 0, -10.0)
	var amb_ok := true
	for p in am._amb:
		amb_ok = amb_ok and p.bus == &"Ambient"
	check(amb_ok, "ambience plays on the Ambient bus")

	# acoustics
	var spaces: Dictionary = am.SPACES
	var dirs := ["res://data/biomes", "res://data/surface", "res://data/town"]
	var n := 0
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".tres"):
				continue
			var b = load(d.path_join(f))
			if b and b.has_method("space"):
				n += 1
				check(spaces.has(b.space()), "%s has known acoustics (%s)" % [f, b.space()])
				if d == "res://data/surface" or f == "town.tres":
					check(b.space() == &"open", "%s: open sky, no reverb" % f)
	check(n >= 18, "acoustics for every biome (%d)" % n)
	am.set_space(&"crypt")
	check(am.current_space() == &"crypt" and am._reverb.wet > 0.0, "a crypt has reverb")
	am.set_space(&"open")
	var bus := AudioServer.get_bus_index(&"SFX")
	var on := false
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == am._reverb:
			on = AudioServer.is_bus_effect_enabled(bus, i)
	check(not on, "open sky: reverb off")

	# priorities
	check(am.priority_of(&"step_stone") < am.priority_of(&"attack_sword"), "steps below attacks")
	check(am.priority_of(&"attack_sword") < am.priority_of(&"player_hurt"), "attacks below the hero's cry")
	for i in am.WORLD_VOICES:
		am._last_played.clear()
		am.play_sfx(&"player_hurt", Vector2(i, 0))
	var busy := 0
	for p in am._world:
		if p.playing:
			busy += 1
	if busy == am.WORLD_VOICES:  # the dummy driver plays: the stealing rule can be checked
		am._last_played.clear()
		am.play_sfx(&"step_stone", Vector2.ZERO)
		var stole := false
		for i in am._world.size():
			if am._world_prio[i] == am.priority_of(&"step_stone"):
				stole = true
		check(not stole, "a step does not take a voice from the hero's cry")
		am._last_played.clear()
		am.play_sfx(&"boss_roar", Vector2.ZERO)
		var boss := 0
		for i in am._world.size():
			if am._world_prio[i] == am.priority_of(&"boss_roar"):
				boss += 1
		check(boss >= 1, "a boss roar gets a voice")
	else:
		print("note: the audio driver does not play here (%d busy), stealing not checked" % busy)

	# combat layer
	am.set_combat(true)
	check(am.in_combat(), "the combat layer switches on")
	am.set_combat(false)
	check(not am.in_combat(), "and off")

	# files
	for id in ap.SFX:
		check(ResourceLoader.exists(ap.SFX[id]), "sound %s: %s" % [id, ap.SFX[id]])
		check(am.variant_count(id) >= 1, "sound %s has a file" % id)
	for id in ap.MUSIC:
		check(ResourceLoader.exists(ap.MUSIC[id]), "track %s: %s" % [id, ap.MUSIC[id]])
	print("sounds: %d ids" % ap.SFX.size())
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

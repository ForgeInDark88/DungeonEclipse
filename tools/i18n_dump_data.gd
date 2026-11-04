extends SceneTree
## Writes the data texts (Localizer.collect_data_texts) as a JSON list for
## tools/i18n_extract.py. Used by tools/i18n_refresh.sh.
##   godot --headless -s tools/i18n_dump_data.gd -- out.json

func _initialize() -> void:
	await process_frame
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://data_texts.json"
	var texts: PackedStringArray = root.get_node("Localizer").collect_data_texts()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(Array(texts)))
	f.close()
	print("data texts: %d -> %s" % [texts.size(), out])
	quit()

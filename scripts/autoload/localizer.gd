extends Node
## Languages. Russian is the source language of the game: every text in the
## code is wrapped in tr() / TranslationServer.translate() with the Russian
## line as its key, and locale/en.po holds the English lines.
##
## Game data (.tres under res://data: names, descriptions, lore, boss lines,
## affix prefixes...) is translated in place: every Russian String field of
## every loaded resource (and its sub-resources, arrays and dictionaries) is
## replaced by its translation; the Russian original is kept in a meta field,
## so switching back restores it. Resources are cached by Godot, so the
## change reaches every place that shows them.

signal language_changed(lang: String)

const LANGUAGES := {"ru": "Русский", "en": "English"}
const DATA_DIR := "res://data"
const META := "_src_"

var lang := "ru"
var _cyr := RegEx.new()
var _done := {}  # resource instance id -> true (walked once per apply)


func _ready() -> void:
	_cyr.compile("[А-Яа-яЁё]")  # i18n-skip
	set_language(SaveManager.language if SaveManager.language != "" else _system_language(), false)


static func _system_language() -> String:
	return "ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk"] else "en"


func set_language(code: String, save := true) -> void:
	lang = code if LANGUAGES.has(code) else "en"
	TranslationServer.set_locale(lang)
	_apply_data()
	if save:
		SaveManager.language = lang
		SaveManager.save_settings()
	language_changed.emit(lang)


## Translates every data resource (all of res://data, as cached instances).
func _apply_data() -> void:
	_done.clear()
	for res in ItemDatabase.load_dir(DATA_DIR):
		_walk(res)


func _walk(res: Resource) -> void:
	if res == null or res is Script or res is Texture2D or _done.has(res.get_instance_id()):
		return
	_done[res.get_instance_id()] = true
	for p in res.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = p["name"]
		if name == "resource_path" or name == "resource_name" or name == "script" or name.begins_with("metadata/"):
			continue
		var v: Variant = res.get(name)
		match typeof(v):
			TYPE_STRING:
				var src: String = res.get_meta(META + name, v)
				if _cyr.search(src):
					if not res.has_meta(META + name):
						res.set_meta(META + name, src)
					res.set(name, TranslationServer.translate(src))
			TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.is_empty():
					continue
				var src_d: Dictionary = res.get_meta(META + name, d)
				var has := false
				for k in src_d:
					if src_d[k] is String and _cyr.search(src_d[k]):
						has = true
						break
				if has:
					if not res.has_meta(META + name):
						res.set_meta(META + name, src_d.duplicate())
					var out := src_d.duplicate()
					for k in out:
						if out[k] is String:
							out[k] = TranslationServer.translate(out[k])
					res.set(name, out)
				for k in d:
					if d[k] is Resource:
						_walk(d[k])
			TYPE_ARRAY:
				var arr: Array = v
				var has_text := false
				for e in arr:
					if e is Resource:
						_walk(e)
					elif e is String and _cyr.search(e):
						has_text = true
				if has_text or res.has_meta(META + name):
					var src_a: Array = res.get_meta(META + name, arr.duplicate())
					if not res.has_meta(META + name):
						res.set_meta(META + name, src_a)
					var out_a := arr.duplicate()
					for i in mini(out_a.size(), src_a.size()):
						if src_a[i] is String:
							out_a[i] = TranslationServer.translate(src_a[i])
					res.set(name, out_a)
			TYPE_PACKED_STRING_ARRAY:
				var ps: PackedStringArray = res.get_meta(META + name, v)
				var any := false
				for e in ps:
					if _cyr.search(e):
						any = true
				if any:
					if not res.has_meta(META + name):
						res.set_meta(META + name, ps)
					var out_p := PackedStringArray()
					for e in ps:
						out_p.append(TranslationServer.translate(e))
					res.set(name, out_p)
			TYPE_OBJECT:
				if v is Resource:
					_walk(v)


## Every Russian text of the game data (tools: building the .pot).
func collect_data_texts() -> PackedStringArray:
	var seen := {}
	_done.clear()
	for res in ItemDatabase.load_dir(DATA_DIR):
		_collect(res, seen)
	return PackedStringArray(seen.keys())


func _collect(res: Resource, seen: Dictionary) -> void:
	if res == null or res is Script or res is Texture2D or _done.has(res.get_instance_id()):
		return
	_done[res.get_instance_id()] = true
	for p in res.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = p["name"]
		if name.begins_with("metadata/"):
			continue
		var v: Variant = res.get_meta(META + name) if res.has_meta(META + name) else res.get(name)
		if v is String and _cyr.search(v):
			seen[v] = true
		elif v is Dictionary:
			for k in v:
				if v[k] is String and _cyr.search(v[k]):
					seen[v[k]] = true
				elif v[k] is Resource:
					_collect(v[k], seen)
		elif v is Array or v is PackedStringArray:
			for e in v:
				if e is String and _cyr.search(e):
					seen[e] = true
				elif e is Resource:
					_collect(e, seen)
		elif v is Resource:
			_collect(v, seen)

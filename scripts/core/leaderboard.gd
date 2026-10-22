class_name Leaderboard
extends RefCounted
## Local leaderboard of daily runs: section [daily] of user://meta.cfg,
## key "scores" = {"YYYY-MM-DD": [entry, ...]} sorted by score, best first.
## entry = {score, floor, kills, gold, bosses, level, time_s, race, class, at}.

const SECTION := "daily"
const KEEP_PER_DAY := 10


## Score of a finished run: depth matters most, then bosses, kills and gold.
static func score(floor_reached: int, kills: int, gold: int, bosses: int, level: int) -> int:
	return floor_reached * 100 + bosses * 300 + kills * 5 + gold / 2 + level * 20


static func _load() -> Dictionary:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(SaveManager.META_PATH) or cfg.load(SaveManager.META_PATH) != OK:
		return {}
	return cfg.get_value(SECTION, "scores", {})


static func _save(scores: Dictionary) -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SaveManager.META_PATH):
		cfg.load(SaveManager.META_PATH)  # keep the other sections
	cfg.set_value(SECTION, "scores", scores)
	cfg.save(SaveManager.META_PATH)


## Adds a result; returns its place for that day (1 = best, 0 = not in the top).
static func submit(date: String, entry: Dictionary) -> int:
	var scores := _load()
	var day: Array = scores.get(date, [])
	day.append(entry)
	day.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	var place := day.find(entry) + 1
	if day.size() > KEEP_PER_DAY:
		day.resize(KEEP_PER_DAY)
	scores[date] = day
	_save(scores)
	return place if place <= KEEP_PER_DAY else 0


static func top(date: String) -> Array:
	return _load().get(date, [])


## Best result of each recorded day, newest day first: [[date, entry], ...].
static func best_by_day(limit: int = 7) -> Array:
	var scores := _load()
	var dates: Array = scores.keys()
	dates.sort()
	dates.reverse()
	var out := []
	for d in dates.slice(0, limit):
		var day: Array = scores[d]
		if not day.is_empty():
			out.append([d, day[0]])
	return out


## Removes one day (tests).
static func clear_day(date: String) -> void:
	var scores := _load()
	if scores.erase(date):
		_save(scores)

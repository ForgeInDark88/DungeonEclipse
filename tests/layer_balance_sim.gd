extends SceneTree
## Loot of the layers of a location (stage 17): the mean strength of the
## equipment that drops on the surface (depth of the node − 1, its chest
## odds), in the dungeon below (floors at the node's depth +0..+2, the
## floors' chest odds) and from the guardians (the boss table one floor
## deeper). Strength = item level + 4 × rarity. Writes the section
## «Слои локации» of docs/BALANCE.md and checks surface < dungeon < boss
## at every depth.
##   godot --headless -s tests/layer_balance_sim.gd

const DEPTHS := [2, 5, 8, 11, 14, 17, 20, 23]
const N := 1500
var fails := 0
var idb


func _initialize() -> void:
	await process_frame
	idb = root.get_node("ItemDatabase")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1717
	var rows := []
	for d in DEPTHS:
		var surface := _mean(func() -> Array: return _surface_drop(d, rng), N)
		var dungeon := _mean(func() -> Array: return _dungeon_drop(d, rng), N)
		var boss := _mean(func() -> Array:
			return idb.get_loot_table(&"boss").roll(d + 2, rng), N / 3)
		rows.append([d, surface, dungeon, boss])
		var ok: bool = surface[0] < dungeon[0] and dungeon[0] < boss[0]
		if not ok:
			fails += 1
		print("depth %2d: surface %.1f (%d items), dungeon %.1f (%d), guardians %.1f (%d) %s" % [
			d, surface[0], surface[1], dungeon[0], dungeon[1], boss[0], boss[1], "" if ok else "FAIL"])
	_write(rows)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


## A drop of the surface: a monster's loot (its chance) or a chest by the
## surface's odds, all at the surface's depth.
func _surface_drop(d: int, rng: RandomNumberGenerator) -> Array:
	var sd := maxi(1, d - 1)
	if rng.randf() < 0.5:
		return idb.get_loot_table(&"enemy_common").roll(sd, rng) if rng.randf() < 0.3 else []
	var r := rng.randf()
	var tier := 2 if r < 0.04 + 0.01 * sd else (1 if r < 0.22 else 0)
	return idb.get_loot_table([&"chest_common", &"chest_rare", &"chest_epic"][tier]).roll(sd, rng)


## A drop of the dungeon: a floor 0..2 below the node's depth, LevelGenerator's
## chest odds.
func _dungeon_drop(d: int, rng: RandomNumberGenerator) -> Array:
	var f := d + rng.randi_range(0, 2)
	if rng.randf() < 0.5:
		var t := &"enemy_rare" if rng.randf() < 0.1 else &"enemy_common"
		return idb.get_loot_table(t).roll(f, rng) if rng.randf() < 0.35 else []
	var gold := 0.06 + 0.02 * f
	var iron := 0.22 + 0.03 * f
	var r := rng.randf()
	var tier := 2 if r < gold else (1 if r < gold + iron else 0)
	return idb.get_loot_table([&"chest_common", &"chest_rare", &"chest_epic"][tier]).roll(f, rng)


## Mean strength of the equipment among n drops: [mean, count].
func _mean(drop: Callable, n: int) -> Array:
	var total := 0.0
	var count := 0
	for i in n:
		for e in drop.call():
			var it: ItemData = e["item"]
			if it and it.item_type == ItemData.ItemType.EQUIPMENT:
				total += it.item_level + 4.0 * int(it.rarity)
				count += 1
	return [total / maxf(1.0, count), count]


func _write(rows: Array) -> void:
	var path := "res://docs/BALANCE.md"
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("## Слои локации")
	if start >= 0:
		var nxt := text.find("\n## ", start + 5)
		text = text.substr(0, start) + (text.substr(nxt + 1) if nxt >= 0 else "")
	var s := "## Слои локации: поверхность, данж, стражи\n\n"
	s += "`tests/layer_balance_sim.gd`: средняя сила выпавшей экипировки\n"
	s += "(уровень предмета + 4 × редкость), %d выпадений на столбец\n" % N
	s += "(у стражей — %d).\n\n" % (N / 3)
	s += "| Глубина узла | Поверхность (глубина −1) | Данж (глубина +0…+2) | Стражи |\n|---|---|---|---|\n"
	for r in rows:
		s += "| %d | %.1f (%d) | %.1f (%d) | %.1f (%d) |\n" % [r[0], r[1][0], r[1][1], r[2][0], r[2][1], r[3][0], r[3][1]]
	s += "\nНа каждой глубине поверхность слабее данжа, а данж слабее стражей.\n"
	s += "Множители заданы в данных:\n"
	s += "- `LocationDefinition.surface_depth_offset = -1`;\n"
	s += "- шансы сундуков в `SurfaceGenerator._place_chests`;\n"
	s += "- глубина этажей: глубина узла + номер этажа − 1.\n"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(text.rstrip("\n") + "\n\n" + s)
	f.close()

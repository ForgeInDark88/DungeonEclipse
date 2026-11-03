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
const SEEDS := 24
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
	var rewards := _rewards()
	_write(rows, rewards)
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


## XP and gold of the monsters of real locations (stage 20): for each depth
## SEEDS level nodes are planned and built; per layer kind the monsters
## placed, the mean reward of one kill (Enemy._give_rewards without
## bonuses: REWARD_MULT × (xp + depth − 1), GOLD_MULT × mean coins ×
## (1 + 0.1 × (depth − 1)), the habitat's monsters weighted by spawn
## weight) and the chests. A kill on the surface must not pay more than
## one in the dungeon below.
func _rewards() -> Array:
	var LB = load("res://scripts/level/location_builder.gd")
	var LI = load("res://scripts/core/location_instance.gd")
	var Enemy = load("res://scripts/enemies/enemy.gd")
	var out := []
	for d in DEPTHS:
		var acc := {0: [0, 0.0, 0.0, 0, 0], 1: [0, 0.0, 0.0, 0, 0]}  # monsters, xp, gold, chests, layers
		for i in SEEDS:
			var node := {"type": &"level", "depth": d, "biome": idb.biomes[i % idb.biomes.size()].id,
					"seed": 9100 + i * 613, "region": 0, "boss": &"", "sub": &""}
			var lay = LB.build(LI.plan(node))
			for b in lay.bands:
				var k := 0 if int(b["kind"]) == 0 else (1 if int(b["kind"]) == 1 else -1)
				if k < 0:
					continue
				var depth := int(b["depth"])
				var pool: Array = idb.enemies_for_floor(depth, b["biome"].id if b["biome"] else &"")
				var w := 0.0
				var xp := 0.0
				var gold := 0.0
				for e in pool:
					if e.neutral or e.no_rewards:
						continue
					w += e.spawn_weight
					xp += e.spawn_weight * Enemy.REWARD_MULT * (e.xp_reward + depth - 1)
					gold += e.spawn_weight * Enemy.GOLD_MULT * (e.gold_min + e.gold_max) / 2.0 * (1.0 + 0.1 * (depth - 1))
				var n: int = b["layout"].enemy_cells.size()
				acc[k][0] += n
				acc[k][1] += n * xp / maxf(w, 0.001)
				acc[k][2] += n * gold / maxf(w, 0.001)
				acc[k][3] += b["layout"].chests.size()
				acc[k][4] += 1
		var row := [d]
		for k in [0, 1]:
			var a: Array = acc[k]
			row.append([float(a[0]) / SEEDS, a[1] / maxf(1, a[0]), a[2] / maxf(1, a[0]), a[1] / SEEDS, a[2] / SEEDS, float(a[3]) / SEEDS])
		var ok: bool = row[1][1] <= row[2][1] and row[1][2] <= row[2][2] * 1.05
		if not ok:
			fails += 1
		print("depth %2d rewards: surface %.0f monsters, %.1f xp / %.1f gold a kill; dungeon %.0f monsters, %.1f xp / %.1f gold a kill %s" % [
				d, row[1][0], row[1][1], row[1][2], row[2][0], row[2][1], row[2][2], "" if ok else "FAIL"])
		out.append(row)
	return out


func _write(rows: Array, rewards: Array) -> void:
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
	s += "\n### Опыт и золото по слоям\n\n"
	s += "Те же прогоны: %d настоящих локаций `level` на глубину (план и\n" % SEEDS
	s += "постройка как в игре). Монстры — расставленные генератором на слое\n"
	s += "(все этажи данжа вместе), награда за убийство — как в\n"
	s += "`Enemy._give_rewards` без бонусов героя и комбо, средняя по монстрам\n"
	s += "среды обитания слоя с весами появления; мирные (олень) не считаются.\n\n"
	s += "| Глубина | Поверхность: монстров | опыт / золото за убийство | всего опыта / золота | сундуков | Данж: монстров | опыт / золото за убийство | всего опыта / золота | сундуков |\n"
	s += "|---|---|---|---|---|---|---|---|---|\n"
	for r in rewards:
		s += "| %d | %.0f | %.1f / %.1f | %.0f / %.0f | %.1f | %.0f | %.1f / %.1f | %.0f / %.0f | %.1f |\n" % [r[0],
				r[1][0], r[1][1], r[1][2], r[1][3], r[1][4], r[1][5], r[2][0], r[2][1], r[2][2], r[2][3], r[2][4], r[2][5]]
	s += "\nЗа одно убийство поверхность не платит больше данжа (она на глубину\n"
	s += "мельче, и звери поверхности дешевле). Поверхность даёт ресурсы\n"
	s += "(дерево, камень, железо, травы), ягоды и клады — это её главная\n"
	s += "награда, а опыт и золото копятся внизу.\n"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(text.rstrip("\n") + "\n\n" + s)
	f.close()

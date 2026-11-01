extends SceneTree
## Balance of the town ↔ expedition loop. Random walks over generated maps
## (a random fork at every step, start to the region's guardian): how long
## a road is, what it meets (camps, rescues, events, elites), what it brings
## to the town (resources from clears, chests, ore), against what the whole
## town costs. Also locations against the old floors (rooms, monsters,
## chests by depth). Writes its section of docs/BALANCE.md (between the
## loop-balance markers) and checks the targets below.
##   godot --headless -s tests/loop_balance_sim.gd

const REPORT := "res://docs/BALANCE.md"
const WALKS := 300
const LAYOUT_SAMPLES := 40
## Targets: a road of 6–8 nodes, at least one camp on it, the whole town
## built in 10–40 expeditions of the first region.
const TARGET_NODES := Vector2(6, 8)
const TARGET_TOWN := Vector2(10, 40)

var md: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	gs.expedition = true
	md.append("<!-- loop-balance:start -->")
	md.append("## Новый цикл: дорога, город, локации")
	md.append("")
	md.append("Отчёт `tests/loop_balance_sim.gd`: %d случайных прогулок по картам каждого региона (на каждом шаге — случайная развилка, от начала до стража региона)." % WALKS)
	md.append("")
	var income := _roads(idb, gs)
	_town(idb, income)
	_locations(idb, gs)
	md.append("### Проверки")
	md.append("")
	md.append("Все цели выполнены." if failures.is_empty() else "Не выполнено: " + ", ".join(failures))
	md.append("<!-- loop-balance:end -->")
	_write()
	print("\n".join(md))
	print("FAILURES: %d" % failures.size())
	quit(1 if failures.size() > 0 else 0)


## One road per walk; returns the average resources a first-region road brings.
func _roads(idb, gs) -> Dictionary:
	md.append("### Дорога до стража")
	md.append("")
	md.append("| Регион | Узлов | Лагерей | Пленников | Событий | Элиты | Особых | Логов | Ресурсов за дорогу |")
	md.append("|---|---|---|---|---|---|---|---|---|")
	var first_income := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for ri in idb.regions.size():
		var sums := {"nodes": 0.0, "camp": 0.0, "rescue": 0.0, "event": 0.0, "elite": 0.0, "special": 0.0, "lair": 0.0}
		var res := {}
		for w in WALKS:
			var m := ExpeditionMap.generate(10007 * w + ri, ri)
			var id: int = m.start_nodes()[rng.randi() % m.start_nodes().size()]
			var steps := 0
			while true:
				var n := m.node(id)
				steps += 1
				var t := String(n["type"])
				if sums.has(t):
					sums[t] += 1.0
				var key := StringName(n["sub"]) if StringName(n["sub"]) != &"" else StringName(n["type"])
				var table: Dictionary = ExpeditionMap.CLEAR_REWARD.get(key, {})
				for r in table:
					res[r] = float(res.get(r, 0.0)) + (float(table[r][0]) + float(table[r][1])) / 2.0 + int(n["depth"]) / 10
				if t == "boss":
					break
				var links := m.links_of(id)
				id = links[rng.randi() % links.size()]
			sums["nodes"] += steps
		for k in sums:
			sums[k] /= WALKS
		for k in res:
			res[k] = float(res[k]) / WALKS
		# chests and ore of the platformer nodes (a sample of real layouts)
		var extra := _layout_income(idb, gs, ri)
		for k in extra:
			res[k] = float(res.get(k, 0.0)) + float(extra[k])
		if ri == 0:
			first_income = res
		md.append("| %s | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %s |" % [idb.regions[ri].display_name, sums["nodes"], sums["camp"],
				sums["rescue"], sums["event"], sums["elite"], sums["special"], sums["lair"], _res_text(res)])
		if sums["nodes"] < TARGET_NODES.x or sums["nodes"] > TARGET_NODES.y:
			failures.append("длина дороги региона %d" % ri)
		if sums["camp"] < 1.0:
			failures.append("лагерь на дороге региона %d" % ri)
	md.append("")
	md.append("Ресурсы за дорогу: награды за зачистку по типу узла и глубине (`ExpeditionMap.CLEAR_REWARD`), сундуки (40% × 1.5) и рудные жилы (по выборке настоящих раскладок). События и стражи сверх этого.")
	md.append("")
	return first_income


## Chests and ore veins of the platformer nodes of a region, per road.
func _layout_income(idb, gs, ri: int) -> Dictionary:
	var reg: RegionData = idb.regions[ri]
	var out := {}
	var steps := (reg.steps_min + reg.steps_max) / 2.0
	var chests := 0.0
	var ore := 0.0
	for i in LAYOUT_SAMPLES:
		var depth := reg.depth_from + i % maxi(1, reg.depth_to - reg.depth_from)
		var mine := i % 8 == 0
		gs.location = {"type": &"special" if mine else &"level", "sub": &"mine" if mine else &"", "depth": depth,
				"mods": ExpeditionMap.MODS[&"mine" if mine else &"level"]}
		gs.floor_number = depth
		var l: LevelLayout = LevelGenerator.new().generate(depth, 5000 + i)
		chests += l.chests.size()
		var biome: BiomeData = idb.biome_by_id(reg.biomes[0])
		ore += _exposed(l) * (biome.ore_chance if biome else 0.04) * float(gs.location_mod("ore", 1.0))
	gs.location = {}
	var per_node_chests := chests / LAYOUT_SAMPLES
	var per_node_ore := ore / LAYOUT_SAMPLES
	var platform_nodes := steps * 0.75  # camps and events have no chests
	out["wood"] = per_node_chests * platform_nodes * 0.4 * 1.5 / 3.0
	out["stone"] = per_node_chests * platform_nodes * 0.4 * 1.5 / 3.0 + per_node_ore * platform_nodes * 0.55
	out["herbs"] = per_node_chests * platform_nodes * 0.4 * 1.5 / 3.0
	out["iron"] = per_node_ore * platform_nodes * 0.45
	return out


func _exposed(l: LevelLayout) -> int:
	var n := 0
	for y in range(1, l.height - 1):
		for x in range(1, l.width - 1):
			if l.get_tile(x, y) != LevelLayout.Tile.BRICK:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not LevelLayout.is_solid(l.get_tile(x + d.x, y + d.y)):
					n += 1
					break
	return n


## What the whole town costs against what a first-region road brings.
func _town(idb, income: Dictionary) -> void:
	md.append("### Стоимость города")
	md.append("")
	var total := {}
	for b in idb.buildings:
		for lvl in range(b.start_level + 1, b.max_level + 1):
			var c: Dictionary = b.costs[lvl - 1]
			for k in c:
				total[k] = int(total.get(k, 0)) + int(c[k])
	md.append("Все здания до последнего уровня: %s, золото %d." % [_res_text(total, true), int(total.get("gold", 0))])
	md.append("")
	md.append("| Ресурс | Нужно на весь город | Приносит дорога 1-го региона | Походов (без каменщика) | С каменщиком (−20%) |")
	md.append("|---|---|---|---|---|")
	var worst := 0.0
	for k in TownResources.ALL:
		var need := float(total.get(String(k), 0))
		var per := float(income.get(String(k), 0.0))
		var runs := need / per if per > 0.0 else INF
		worst = maxf(worst, runs * 0.8)
		md.append("| %s | %d | %.1f | %s | %s |" % [TownResources.display_name(k), int(need), per,
				"%.0f" % runs if runs != INF else "—", "%.0f" % (runs * 0.8) if runs != INF else "—"])
	md.append("")
	md.append("Узкое место — ресурс, которому нужно больше всего походов: **%.0f** походов первого региона с каменщиком (дороги дальних регионов приносят больше, а кристаллы — в основном от стражей и логов)." % worst)
	md.append("")
	if worst < TARGET_TOWN.x or worst > TARGET_TOWN.y:
		failures.append("город строится за %.0f походов (цель %d–%d)" % [worst, TARGET_TOWN.x, TARGET_TOWN.y])


## Expedition locations against the old floors.
func _locations(idb, gs) -> void:
	md.append("### Локации против прежних этажей")
	md.append("")
	md.append("| Глубина | Комнат: этаж → локация | Мест монстров: этаж → локация | Сундуков: этаж → локация |")
	md.append("|---|---|---|---|")
	for depth in [1, 5, 10, 15, 20, 30]:
		gs.expedition = false
		gs.location = {}
		var a := LevelGenerator.new()
		var la := a.generate(depth, 77)
		gs.expedition = true
		gs.location = {"type": &"level", "depth": depth, "mods": {}}
		var b := LevelGenerator.new()
		var lb := b.generate(depth, 77)
		md.append("| %d | %d → %d | %d → %d | %d → %d |" % [depth, a.cols * a.rows, b.cols * b.rows, la.enemy_cells.size(), lb.enemy_cells.size(), la.chests.size(), lb.chests.size()])
	gs.location = {}
	md.append("")
	md.append("Лечение: перед каждым стражем лагерь с бесплатным отдыхом (+45% здоровья, +60% маны), дальше — за 20 + 3×глубина золота. Город лечит полностью и бесплатно (храм).")
	md.append("")


func _res_text(res: Dictionary, ints := false) -> String:
	var parts: Array[String] = []
	for k in TownResources.ALL:
		if res.has(String(k)) and float(res[String(k)]) > 0.0:
			parts.append(("%s %d" if ints else "%s %.1f") % [TownResources.display_name(k), res[String(k)]])
	return ", ".join(parts)


func _write() -> void:
	var old := FileAccess.get_file_as_string(REPORT)
	var a := old.find("<!-- loop-balance:start -->")
	var b := old.find("<!-- loop-balance:end -->")
	var text := "\n".join(md)
	if a >= 0 and b > a:
		old = old.substr(0, a) + text + old.substr(b + "<!-- loop-balance:end -->".length())
	else:
		old = old.strip_edges() + "\n\n" + text + "\n"
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string(old)
	f.close()

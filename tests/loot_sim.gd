extends Node
## Loot balance simulator:
##   godot --headless --path . res://tests/loot_sim.tscn
## Opens every loot table 1000 times on floors 1, 3, 5, 8 and 12 (fixed seed),
## prints the rarity distribution, the average / highest item level and the
## number of items per opening, checks the balance targets and writes the
## report to docs/BALANCE.md. Exit code 1 when a target is missed.

const FLOORS := [1, 3, 5, 8, 12]
const OPENS := 1000
const TABLES := ["chest_common", "chest_rare", "chest_epic", "enemy_common", "enemy_rare", "special", "boss", "merchant"]
const REPORT := "res://docs/BALANCE.md"

var failures: Array[String] = []
var md: Array[String] = []


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		failures.append(msg)


## Stats of `opens` rolls: {"n": items, "rar": [c,r,e,l] counts, "lvl_sum", "lvl_max", "gear": n}.
func _simulate(table: LootTable, floor_number: int, opens: int, rng: RandomNumberGenerator) -> Dictionary:
	var st := {"n": 0, "rar": [0, 0, 0, 0], "lvl_sum": 0, "lvl_max": 0, "gear": 0, "gear_rar": [0, 0, 0, 0]}
	for i in opens:
		for e in table.roll(floor_number, rng):
			var item: ItemData = e["item"]
			if item.currency_value > 0:
				continue
			st["n"] += 1
			st["rar"][item.rarity] += 1
			if item.item_type == ItemData.ItemType.EQUIPMENT:
				st["gear"] += 1
				st["gear_rar"][item.rarity] += 1
				st["lvl_sum"] += item.item_level
				st["lvl_max"] = maxi(st["lvl_max"], item.item_level)
	return st


func _pct(part: int, whole: int) -> String:
	return "%.1f%%" % (100.0 * part / maxf(1.0, whole))


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	md.append("# Баланс лута и сложности")
	md.append("")
	md.append("Отчёт создан `tests/loot_sim.tscn` (%d открытий каждой таблицы на этаж, фиксированное зерно)." % OPENS)
	md.append("Таблицы настраиваются в `tools/gen_loot_tables.py`, после правки: `python3 tools/gen_loot_tables.py`")
	md.append("и `godot --headless --path . res://tests/loot_sim.tscn` (перезапишет этот файл).")
	md.append("")
	md.append("Предел уровня предмета: `1 + 0.75 × этаж + бонус таблицы` (деревянный сундук +0, железный +1,")
	md.append("золотой +2, особые комнаты +2, босс +3). Редкости открываются с этажа `rarity_min_floor`.")
	md.append("Доли редкостей — по всем выпавшим предметам (кроме золота); уровень — только по снаряжению.")
	md.append("")
	var results := {}
	for tname in TABLES:
		var table := ItemDatabase.get_loot_table(StringName(tname))
		if table == null:
			failures.append("no table " + tname)
			continue
		md.append("## %s" % tname)
		md.append("")
		md.append("| Этаж | Предел ур. | Обычные | Редкие | Эпические | Легендарные | Ср. ур. снаряжения | Макс. ур. | Предметов за открытие |")
		md.append("|---|---|---|---|---|---|---|---|---|")
		print("== ", tname)
		for f in FLOORS:
			var st := _simulate(table, f, OPENS, rng)
			results["%s_%d" % [tname, f]] = st
			var r: Array = st["rar"]
			var avg := float(st["lvl_sum"]) / maxf(1.0, st["gear"])
			var line := "| %d | %d | %s | %s | %s | %s | %.1f | %d | %.2f |" % [f, table.item_level_cap(f),
				_pct(r[0], st["n"]), _pct(r[1], st["n"]), _pct(r[2], st["n"]), _pct(r[3], st["n"]),
				avg, st["lvl_max"], float(st["n"]) / OPENS]
			md.append(line)
			print("  floor %2d: common %s rare %s epic %s legendary %s | avg lvl %.1f max %d | %.2f items/open" % [f,
				_pct(r[0], st["n"]), _pct(r[1], st["n"]), _pct(r[2], st["n"]), _pct(r[3], st["n"]), avg, st["lvl_max"], float(st["n"]) / OPENS])
		md.append("")

	# A "random chest" of a floor, with the generator's tier odds (LevelGenerator._place_chests).
	md.append("## Случайный сундук этажа (с учётом шансов деревянный / железный / золотой)")
	md.append("")
	md.append("| Этаж | Эпические | Легендарные | Ср. ур. снаряжения |")
	md.append("|---|---|---|---|")
	var mixed := {}
	for f in FLOORS:
		var gold_c: float = 0.06 + 0.02 * f
		var iron_c: float = 0.22 + 0.03 * f
		var tot := {"n": 0, "e": 0, "l": 0, "lvl": 0, "gear": 0}
		for t in [["chest_epic", gold_c], ["chest_rare", iron_c], ["chest_common", 1.0 - gold_c - iron_c]]:
			var st: Dictionary = results["%s_%d" % [t[0], f]]
			tot["n"] += st["n"] * t[1]
			tot["e"] += st["rar"][2] * t[1]
			tot["l"] += st["rar"][3] * t[1]
			tot["lvl"] += st["lvl_sum"] * t[1]
			tot["gear"] += st["gear"] * t[1]
		mixed[f] = tot
		md.append("| %d | %.2f%% | %.2f%% | %.1f |" % [f, 100.0 * tot["e"] / tot["n"], 100.0 * tot["l"] / tot["n"], tot["lvl"] / maxf(1.0, tot["gear"])])
	md.append("")

	print("== targets")
	var e1: float = 100.0 * mixed[1]["e"] / mixed[1]["n"]
	check(e1 < 1.0, "floor 1: epics < 1%% of chest loot (%.2f%%)" % e1)
	for t in ["chest_common", "chest_rare", "chest_epic"]:
		var st: Dictionary = results["%s_1" % t]
		check(st["rar"][2] + st["rar"][3] == 0 and st["lvl_max"] <= 3, "floor 1 %s: no epic/legendary, item level ≤ 3 (max %d)" % [t, st["lvl_max"]])
	var e8: float = 100.0 * mixed[8]["e"] / mixed[8]["n"]
	check(e8 >= 5.0, "floor 8: epics are a regular find (%.1f%% of chest loot)" % e8)
	var e12: float = 100.0 * mixed[12]["e"] / mixed[12]["n"]
	check(e12 > e8, "epics get more common deeper (%.1f%% on floor 12)" % e12)
	for f in FLOORS:
		var gear_avg: float = mixed[f]["lvl"] / maxf(1.0, mixed[f]["gear"])
		if f > 1:
			var prev: float = mixed[FLOORS[FLOORS.find(f) - 1]]["lvl"] / maxf(1.0, mixed[FLOORS[FLOORS.find(f) - 1]]["gear"])
			check(gear_avg > prev, "average item level grows: floor %d %.1f > %.1f" % [f, gear_avg, prev])
	for t in ["chest_common", "chest_rare", "chest_epic", "enemy_common", "enemy_rare", "merchant"]:
		for f in [1, 3, 5]:
			check(results["%s_%d" % [t, f]]["rar"][3] == 0, "%s floor %d: no legendary" % [t, f])
	var has_legendary := ItemDatabase.items.values().any(func(it: ItemData) -> bool: return it.rarity == ItemData.Rarity.LEGENDARY)
	if has_legendary:
		var boss_l: int = results["boss_8"]["rar"][3]
		check(boss_l > 0, "bosses are the main source of legendary items (%d per %d on floor 8)" % [boss_l, OPENS])
		check(results["chest_epic_5"]["rar"][3] == 0, "no legendary before floor 8 in chests")
	for t in ["chest_common", "chest_rare", "chest_epic"]:
		for f in FLOORS:
			var per_open: float = float(results["%s_%d" % [t, f]]["n"]) / OPENS
			check(per_open >= 1.0 and per_open <= 3.0, "%s floor %d: 1–3 items per chest (%.2f)" % [t, f, per_open])
	for c in ItemDatabase.classes:
		for id in c.starting_equipment:
			var it := ItemDatabase.get_item(id)
			check(it.rarity == ItemData.Rarity.COMMON and it.item_level <= 1, "%s starts with a plain %s" % [c.id, id])

	_monster_section()
	md.append("## Проверки")
	md.append("")
	md.append("Все цели выполнены." if failures.is_empty() else "Не выполнено: " + ", ".join(failures))
	md.append("")
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(md))
		f.close()
		print("report written to ", REPORT)
	print("FAILURES: ", failures.size())
	get_tree().quit(1 if failures.size() > 0 else 0)


## Monster scaling per floor (Enemy constants, generator density, elite odds).
func _monster_section() -> void:
	md.append("## Сила и число монстров")
	md.append("")
	md.append("HP × (1 + %.2f × (этаж − 1)), урон × (1 + %.2f × (этаж − 1)); монстров на этаже: 3 + 2.4 × этаж + комнаты / 2;" % [Enemy.HP_SCALE_PER_FLOOR, Enemy.DMG_SCALE_PER_FLOOR])
	md.append("элита: 6% на 1-м этаже, +2.5% за этаж, максимум 35%. Аффиксы элиты: быстрый, огненный, регенерирующий,")
	md.append("вампирский, бронированный, щитоносный (щит поглощает урон). Элита: ×2.5–3 опыта, ×3–3.5 золота,")
	md.append("осколок Затмения и гарантированный лут из `enemy_rare`.")
	md.append("")
	md.append("| Этаж | HP скелета | Урон скелета | HP голема | Монстров (≈) | Шанс элиты |")
	md.append("|---|---|---|---|---|---|")
	var skel: EnemyData = null
	var golem: EnemyData = null
	for e in ItemDatabase.enemies:
		if e.id == &"skeleton":
			skel = e
		elif e.id == &"golem":
			golem = e
	for f in [1, 3, 5, 8, 12]:
		var hp_k: float = 1.0 + Enemy.HP_SCALE_PER_FLOOR * (f - 1)
		var dmg_k: float = 1.0 + Enemy.DMG_SCALE_PER_FLOOR * (f - 1)
		var rooms := clampi(3 + f / 2, 3, 6) * clampi(2 + f / 3, 2, 5)
		md.append("| %d | %d | %d | %d | %d | %d%% |" % [f, roundi(skel.max_hp * hp_k), roundi(skel.damage * dmg_k),
			roundi(golem.max_hp * hp_k), 3 + roundi(f * 2.4) + rooms / 2, roundi(100.0 * minf(0.06 + 0.025 * (f - 1), 0.35))])
	md.append("")

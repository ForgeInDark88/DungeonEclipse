extends SceneTree
## Combat by the numbers (the game's own formulas): every class with its
## starting kit at hero level = floor, against every monster at its first
## floor and four floors deeper (Enemy.setup scaling, armor of both sides,
## the class / weapon attack interval, crits x2), and against each guardian
## on its floor. Time to kill both ways, written to docs/BALANCE.md
## («Бой: время на убийство»). Deterministic (averages, no dice).
## Fails on extremes only: a monster at its first floor that kills a
## fresh hero in under 3 s of non-stop hits, or that a hero needs more than
## 30 s to kill; a guardian under 10 s or over 6 min.
##   godot --headless -s tools/tests/combat_sim.gd

const HIT_RATE := 0.6  # monsters land ~60% of their swings (dodging, positioning)
var fails := 0
var rows: Array = []


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		if fails < 40:
			print("FAIL: " + what)


func _hero(idb, cls, level: int):
	var H = load("res://scripts/core/hero.gd")
	var h = H.new(idb.races[0], cls, idb.equipment_layout)
	h.give_starting_kit()
	h.stats.set_level(level)
	h.stats.recalculate()
	return h


## [hero seconds to kill it, its seconds to kill the hero]
func _duel(hero, data, floor_number: int, guardian := false) -> Array:
	var f := float(floor_number - 1)
	var Enemy = load("res://scripts/enemies/enemy.gd")
	var hp: float = float(data.max_hp) * (1.0 + Enemy.HP_SCALE_PER_FLOOR * f)
	var dmg: float = float(data.damage) * (1.0 + Enemy.DMG_SCALE_PER_FLOOR * f)
	if guardian:
		dmg *= float(data.contact_damage_mult) * 2.0  # its attacks hit harder than its touch
	var per_hit: float = maxf(1.0, hero.stats.damage() - float(data.armor)) * (1.0 + hero.stats.crit_chance())
	var hero_dps: float = per_hit / maxf(0.1, hero.attack_interval())
	var taken: float = maxf(1.0, dmg * 100.0 / (100.0 + hero.stats.armor() * 4.0))
	var its_dps: float = taken / maxf(0.2, float(data.attack_cooldown)) * HIT_RATE
	return [hp / hero_dps, float(hero.stats.max_hp()) / its_dps]


func _initialize() -> void:
	await process_frame
	var idb = root.get_node("ItemDatabase")
	var worst_kill := 0.0
	var fastest_death := 1e9
	for cls in idb.classes:
		for e in idb.enemies:
			if e.neutral or e.no_rewards or e.get_script().resource_path.ends_with("boss_data.gd"):
				continue
			for extra in [0, 4]:
				var fl: int = maxi(1, e.min_floor) + extra
				var hero = _hero(idb, cls, fl)
				var r := _duel(hero, e, fl)
				rows.append([cls.id, e.id, fl, r[0], r[1]])
				if extra == 0:
					worst_kill = maxf(worst_kill, r[0])
					fastest_death = minf(fastest_death, r[1])
					check(r[1] >= 3.0, "%s at floor %d kills a fresh %s in %.1f s" % [e.id, fl, cls.id, r[1]])
					check(r[0] <= 30.0, "a %s needs %.1f s to kill %s at floor %d" % [cls.id, r[0], e.id, fl])
	var boss_rows: Array = []
	for b in idb.bosses:
		var fl: int = 5 * (int(b.order) + 1)
		for cls in idb.classes:
			var hero = _hero(idb, cls, fl)
			var r := _duel(hero, b, fl, true)
			boss_rows.append([cls.id, b.id, fl, r[0], r[1]])
			check(r[0] >= 10.0 and r[0] <= 360.0, "%s on floor %d: a %s needs %.0f s" % [b.id, fl, cls.id, r[0]])
	_write(boss_rows)
	print("duels: %d, guardians: %d; slowest kill at a first floor %.1f s, fastest death %.1f s" % [rows.size(), boss_rows.size(), worst_kill, fastest_death])
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _write(boss_rows: Array) -> void:
	var path := "res://docs/BALANCE.md"
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("## Бой: время на убийство")
	if start >= 0:
		var nxt := text.find("\n## ", start + 5)
		text = text.substr(0, start) + (text.substr(nxt + 1) if nxt >= 0 else "")
	var s := "## Бой: время на убийство\n\n"
	s += "`tools/tests/combat_sim.gd`: формулы игры (масштаб врага по этажу, броня обеих\n"
	s += "сторон, интервал атаки класса и оружия, крит x2). Герой со стартовым набором,\n"
	s += "уровень = этаж. Монстр попадает в %d%% случаев. Время в секундах: сколько\n" % int(HIT_RATE * 100)
	s += "герою бить монстра / сколько монстру бить героя без остановки.\n\n"
	var by_class := {}
	for r in rows:
		by_class[r[0]] = by_class.get(r[0], []) + [r]
	s += "| Класс | Боёв | Среднее «герой убивает» | Худшее | Среднее «монстр убивает» | Быстрее всего |\n|---|---|---|---|---|---|\n"
	for k in by_class:
		var list: Array = by_class[k]
		var a := 0.0
		var b := 0.0
		var worst := 0.0
		var best := 1e9
		for r in list:
			a += r[3]
			b += r[4]
			worst = maxf(worst, r[3])
			best = minf(best, r[4])
		s += "| %s | %d | %.1f | %.1f | %.1f | %.1f |\n" % [k, list.size(), a / list.size(), worst, b / list.size(), best]
	s += "\n### Стражи (этаж = 5 × (порядок + 1))\n\n| Страж | Этаж | Класс | Герою нужно, с | Стражу нужно, с |\n|---|---|---|---|---|\n"
	for r in boss_rows:
		s += "| %s | %d | %s | %.0f | %.0f |\n" % [r[1], r[2], r[0], r[3], r[4]]
	s += "\nСтражу герой со стартовым набором нужен надолго: в игре к этому этажу\n"
	s += "у героя уже найденное снаряжение, навыки и зелья.\n"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(text.rstrip("\n") + "\n\n" + s)
	f.close()

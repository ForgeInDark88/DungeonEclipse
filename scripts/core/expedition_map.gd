class_name ExpeditionMap
extends RefCounted
## The road of an expedition: a graph of nodes, region after region (data/
## regions), forks of 2–3 ways on every step that split and merge, the
## region boss at the end of each road. Pure data, generated from a seed:
## the same seed and options always give the same map.
##
## A node is a Dictionary:
##   id, region (index into `regions`), step, col (step counted from the
##   start of the map), lane (0..LANES-1),
##   type (TYPES key), sub (special kind: cache / mine / crypt),
##   depth (difficulty and loot of the location), biome (BiomeData id),
##   boss (BossData id for boss / lair), seed, links (ids of the next step),
##   hint (&"" or a sign seen through the fog: danger / gold / blood).

const LANES := 4
## Node types: [name for the map, short description for the tooltip].
const TYPES := {
	&"level": ["Подземелье", "Обычная вылазка: враги, сундуки, выход в конце."],
	&"elite": ["Логово элиты", "Сильные враги и награда получше."],
	&"special": ["Особое место", "Тайник, шахта или склеп."],
	&"camp": ["Лагерь", "Костёр, отдых, торговец. Отсюда можно вернуться домой."],
	&"rescue": ["Пленник", "Кого-то держат под стражей. Освободи, и он придёт в город."],
	&"event": ["Происшествие", "Встреча на дороге и выбор с риском."],
	&"lair": ["Логово стража", "Арена одного из стражей Затмения. Опасно, но щедро."],
	&"boss": ["Страж региона", "Хозяин этих земель. Победа открывает путь дальше."],
}
## Kinds of special places.
const SPECIALS := [&"cache", &"mine", &"crypt"]
const SPECIAL_NAMES := {&"cache": "Тайник", &"mine": "Заброшенная шахта", &"crypt": "Склеп"}
## Signs seen through the fog.
const HINT_TEXT := {&"danger": "Знаки опасности", &"gold": "Блеск золота", &"blood": "Следы крови"}

var seed_value := 0
## Regions on this map (RegionData), the first one is where the road starts.
var regions: Array[RegionData] = []
## Absolute index of regions[0] in ItemDatabase.regions.
var first_region := 0
var nodes: Array[Dictionary] = []
## Ids of the first step's nodes.
var _starts: Array[int] = []
var _rng := RandomNumberGenerator.new()
## Columns so far (a node's "col" counts steps from the start of the map).
var _cols := 0
var _col0 := 0


## `options`: "allowed" = node types the town has unlocked (default all but
## rescue/special decide themselves), "rescue" / "special" / "lair" (bool).
static func generate(seed_value: int, start_region := 0, options := {}) -> ExpeditionMap:
	var m := ExpeditionMap.new()
	m.seed_value = seed_value
	m._rng.seed = seed_value
	m.first_region = clampi(start_region, 0, maxi(0, ItemDatabase.regions.size() - 1))
	for i in range(m.first_region, ItemDatabase.regions.size()):
		m.regions.append(ItemDatabase.regions[i])
	var prev_boss := -1
	for ri in m.regions.size():
		prev_boss = m._build_region(ri, prev_boss, options)
	return m


func node(id: int) -> Dictionary:
	return nodes[id] if id >= 0 and id < nodes.size() else {}


func columns() -> int:
	return _cols


func links_of(id: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(node(id).get("links", []))
	return out


func start_nodes() -> Array[int]:
	return _starts.duplicate()


func region_of(id: int) -> RegionData:
	var n := node(id)
	return regions[int(n["region"])] if not n.is_empty() else null


## Number of steps of region `ri` (boss included).
func steps_of(ri: int) -> int:
	var last := 0
	for n in nodes:
		if int(n["region"]) == ri:
			last = maxi(last, int(n["step"]))
	return last + 1


func nodes_of(ri: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in nodes:
		if int(n["region"]) == ri:
			out.append(n)
	return out


static func type_name(type: StringName) -> String:
	return TranslationServer.translate(TYPES.get(type, ["?", ""])[0])


static func type_description(type: StringName) -> String:
	return TranslationServer.translate(TYPES.get(type, ["", ""])[1])


# ------------------------------------------------------------- generation
func _build_region(ri: int, prev_boss: int, options: Dictionary) -> int:
	var reg := regions[ri]
	var steps := _rng.randi_range(reg.steps_min, reg.steps_max)
	_col0 = _cols
	_cols += steps
	var layers: Array = []  # step -> Array[int] of node ids
	for s in steps:
		var ids: Array[int] = []
		if s == steps - 1:
			ids.append(_add(ri, s, 1, &"boss"))
		else:
			var count := 2 if s == 0 else _rng.randi_range(2, 3)
			var lanes := [0, 1, 2, 3]
			_shuffle(lanes)
			var picked := lanes.slice(0, count)
			picked.sort()
			for lane in picked:
				ids.append(_add(ri, s, lane, &""))
		layers.append(ids)
	# links: every node goes on, every node is reachable
	for s in steps - 1:
		_link_layers(layers[s], layers[s + 1])
	if prev_boss >= 0:
		for id in layers[0]:
			nodes[prev_boss]["links"].append(id)
	elif _starts.is_empty():
		_starts.assign(layers[0])
	_assign_types(ri, reg, layers, options)
	return layers[steps - 1][0]


func _add(ri: int, step: int, lane: int, type: StringName) -> int:
	var id := nodes.size()
	nodes.append({
		"id": id, "region": ri, "step": step, "col": _col0 + step, "lane": lane, "type": type, "sub": &"",
		"depth": 1, "biome": &"", "boss": &"", "seed": hash([seed_value, id]),
		"links": [], "hint": &"",
	})
	return id


## Each node of `a` links to its nearest lanes in `b`; nodes of `b` nobody
## reaches get a link from their nearest node in `a`. Nearest-lane links
## keep the roads from crossing much.
func _link_layers(a: Array, b: Array) -> void:
	for id in a:
		var lane := int(nodes[id]["lane"])
		var sorted := b.duplicate()
		sorted.sort_custom(func(x: int, y: int) -> bool:
			return absi(int(nodes[x]["lane"]) - lane) < absi(int(nodes[y]["lane"]) - lane))
		var n := 1 if b.size() == 1 or _rng.randf() < 0.55 else 2
		for k in mini(n, sorted.size()):
			if not sorted[k] in nodes[id]["links"]:
				nodes[id]["links"].append(sorted[k])
	for id in b:
		var reached := false
		for src in a:
			if id in nodes[src]["links"]:
				reached = true
				break
		if not reached:
			var lane := int(nodes[id]["lane"])
			var best: int = a[0]
			for src in a:
				if absi(int(nodes[src]["lane"]) - lane) < absi(int(nodes[best]["lane"]) - lane):
					best = src
			nodes[best]["links"].append(id)
	for id in a:
		(nodes[id]["links"] as Array).sort_custom(func(x: int, y: int) -> bool:
			return int(nodes[x]["lane"]) < int(nodes[y]["lane"]))


func _assign_types(ri: int, reg: RegionData, layers: Array, options: Dictionary) -> void:
	var steps := layers.size()
	var weights: Dictionary = reg.node_weights.duplicate()
	if not options.get("rescue", true):
		weights.erase("rescue")
	if not options.get("special", true):
		weights.erase("special")
	var lair_step := -1
	if options.get("lair", true) and not reg.lair_bosses.is_empty() and steps >= 5:
		lair_step = steps / 2
	for s in steps:
		var ids: Array = layers[s]
		var has_camp := false
		for i in ids.size():
			var id: int = ids[i]
			var n: Dictionary = nodes[id]
			var type := StringName(n["type"])
			if type == &"":
				if s == 0:
					type = &"level"
				elif s == steps - 2 and i == ids.size() / 2:
					type = &"camp"  # a fire before every guardian
				elif s == lair_step and i == 0:
					type = &"lair"
				else:
					type = _roll_type(weights, s)
			if type == &"camp":
				if has_camp:
					type = &"level"
				has_camp = true
			n["type"] = type
			# depth: from the region's first depth to one below its boss
			var k := float(s) / float(maxi(1, steps - 2))
			n["depth"] = reg.depth_to if type == &"boss" else \
					clampi(roundi(lerpf(reg.depth_from, reg.depth_to - 1, minf(k, 1.0))), reg.depth_from, reg.depth_to - 1)
			if type == &"elite" or type == &"lair":
				n["depth"] = mini(int(n["depth"]) + 1, reg.depth_to)
			var bi := mini(int(k * reg.biomes.size()), reg.biomes.size() - 1)
			n["biome"] = reg.biomes[bi] if not reg.biomes.is_empty() else &""
			if type == &"boss":
				n["boss"] = reg.boss
			elif type == &"lair":
				n["boss"] = reg.lair_bosses[_rng.randi() % reg.lair_bosses.size()]
			if type in [&"boss", &"lair"]:
				var bd := ItemDatabase.boss_by_id(StringName(n["boss"]))
				if bd and bd.arena_biome != &"":
					n["biome"] = bd.arena_biome
			if type == &"special":
				n["sub"] = SPECIALS[_rng.randi() % SPECIALS.size()]
			n["hint"] = _roll_hint(type, StringName(n["sub"]))


func _roll_type(weights: Dictionary, step: int) -> StringName:
	var total := 0.0
	var pool := {}
	for k in weights:
		var w := float(weights[k])
		if k == "camp" and step < 2:
			continue
		if k == "elite" and step < 1:
			continue
		pool[k] = w
		total += w
	var r := _rng.randf() * total
	for k in pool:
		r -= float(pool[k])
		if r <= 0.0:
			return StringName(k)
	return &"level"


func _roll_hint(type: StringName, sub: StringName) -> StringName:
	if _rng.randf() > 0.4:
		return &""
	match type:
		&"elite", &"lair":
			return &"danger"
		&"rescue":
			return &"blood"
		&"special":
			return &"gold" if sub != &"crypt" else &"danger"
		&"level":
			return [&"gold", &"danger", &"blood"][_rng.randi() % 3]
	return &""


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t

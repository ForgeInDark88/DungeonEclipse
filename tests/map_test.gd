extends SceneTree
## Expedition maps (ExpeditionMap): 200 seeds × every start region. Every
## node has a type; every node is reachable from the start and leads on
## (no dead ends); the guardian closes every region; forks of 2–3 ways;
## depth never goes down along a road; the same seed gives the same map.
##   godot --headless -s tests/map_test.gd

var fails := 0


func check(c: bool, what: String) -> void:
	if not c:
		print("FAIL: " + what)
		fails += 1


func _initialize() -> void:
	await process_frame
	var idb = root.get_node("ItemDatabase")
	check(idb.regions.size() >= 3, "at least three regions")
	var maps := 0
	for start in idb.regions.size():
		for i in 200:
			var seed_value := 1000 + i * 7919
			var m := ExpeditionMap.generate(seed_value, start)
			maps += 1
			_check_map(m, "seed %d start %d" % [seed_value, start])
	var a := ExpeditionMap.generate(42)
	var b := ExpeditionMap.generate(42)
	check(var_to_str(a.nodes) == var_to_str(b.nodes), "the same seed gives the same map")
	print("maps checked: %d" % maps)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _check_map(m: ExpeditionMap, tag: String) -> void:
	var by_region := {}
	for n in m.nodes:
		check(ExpeditionMap.TYPES.has(StringName(n["type"])), "%s: node %d has a type" % [tag, n["id"]])
		check(int(n["depth"]) >= 1, "%s: node %d has a depth" % [tag, n["id"]])
		check(StringName(n["biome"]) != &"", "%s: node %d has a biome" % [tag, n["id"]])
		by_region[int(n["region"])] = true
		var is_last_boss := StringName(n["type"]) == &"boss" and int(n["region"]) == m.regions.size() - 1
		if not is_last_boss:
			check(not (n["links"] as Array).is_empty(), "%s: node %d (%s) is no dead end" % [tag, n["id"], n["type"]])
		for to in n["links"]:
			var t := m.node(to)
			check(int(t["col"]) == int(n["col"]) + 1, "%s: links go one step forward" % tag)
			check(int(t["depth"]) >= int(n["depth"]) or StringName(n["type"]) in [&"elite", &"lair"],
				"%s: depth never drops along a road (%d → %d)" % [tag, n["id"], to])
	check(by_region.size() == m.regions.size(), "%s: every region has nodes" % tag)
	# reachability from the start
	var seen := {}
	var queue: Array = m.start_nodes()
	for s in queue:
		seen[s] = true
	while not queue.is_empty():
		var id: int = queue.pop_front()
		for to in m.links_of(id):
			if not seen.has(to):
				seen[to] = true
				queue.append(to)
	check(seen.size() == m.nodes.size(), "%s: every node is reachable (%d of %d)" % [tag, seen.size(), m.nodes.size()])
	for ri in m.regions.size():
		var steps := m.steps_of(ri)
		var reg: RegionData = m.regions[ri]
		check(steps >= reg.steps_min and steps <= reg.steps_max, "%s: region %d has %d steps" % [tag, ri, steps])
		var bosses := m.nodes_of(ri).filter(func(n: Dictionary) -> bool: return n["type"] == &"boss")
		check(bosses.size() == 1 and int(bosses[0]["step"]) == steps - 1, "%s: region %d ends with its guardian" % [tag, ri])
		check(bosses.size() == 1 and int(bosses[0]["depth"]) == reg.depth_to, "%s: the guardian fights at the region's depth" % tag)
		for s in steps - 1:
			var on_step := m.nodes_of(ri).filter(func(n: Dictionary) -> bool: return int(n["step"]) == s)
			check(on_step.size() >= 2 and on_step.size() <= 3, "%s: region %d step %d has 2–3 ways" % [tag, ri, s])
		var camps := m.nodes_of(ri).filter(func(n: Dictionary) -> bool: return n["type"] == &"camp" and int(n["step"]) == steps - 2)
		check(camps.size() >= 1, "%s: a camp before region %d's guardian" % [tag, ri])

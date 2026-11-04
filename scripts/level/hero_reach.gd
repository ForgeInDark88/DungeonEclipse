class_name HeroReach
extends RefCounted
## Where the hero can get on a floor, from a start cell: walking, ladders
## (climbing, stepping off sideways), jumps of up to 4 cells up and 3
## across through open air (the hero's jump is ~66 px), falls, dropping
## through one-way ledges. A little more cautious than the hero (no double
## jump, no dash), so what it reaches the hero surely does.
## Used by LevelGenerator (no chest on a ledge out of reach) and the tests.


static func cells(lay: LevelLayout, start: Vector2i) -> Dictionary:
	# straight on the tile bytes: 0 empty, 1 bedrock, 2 brick, 3 ledge,
	# 4 ladder, 5 ladder top (LevelLayout.Tile)
	var w: int = lay.width
	var hgt: int = lay.height
	var t: PackedByteArray = lay.tiles
	var seen := {}
	var todo: Array[int] = [start.y * w + start.x]
	seen[todo[0]] = true
	var out := {}
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var sx := i % w
		var sy := i / w
		out[Vector2i(sx, sy)] = true
		var cand: Array[int] = []
		# walk / step off
		for dx in [-1, 1]:
			var x: int = sx + dx
			if x > 0 and x < w - 1:
				var tt: int = t[sy * w + x]
				if tt == 0 or tt == 4 or tt == 5:
					cand.append(land(t, w, hgt, x, sy))
		var here: int = t[i]
		var below: int = t[i + w] if sy + 1 < hgt else 1
		# ladders
		if here == 4 or here == 5 or below == 4 or below == 5:
			if sy > 1:
				var up: int = t[i - w]
				if up == 4 or up == 5 or here == 4 or here == 5:
					if up == 0 or up == 4 or up == 5 or up == 3:
						cand.append(i - w)
			if below == 4 or below == 5:
				cand.append(i + w)
		# drop through a ledge
		if below == 3 and sy + 2 < hgt:
			cand.append(land(t, w, hgt, sx, sy + 2))
		# jumps: up to 4 cells, then up to 3 across, then the fall
		for up in range(1, 5):
			var ty := sy - up
			if ty < 1:
				break
			var c: int = t[ty * w + sx]
			if c == 1 or c == 2:
				break
			for dx in range(-3, 4):
				var ok := true
				var stp := 1 if dx > 0 else -1
				for k in range(1, absi(dx) + 1):
					var x2: int = sx + stp * k
					if x2 <= 0 or x2 >= w - 1:
						ok = false
						break
					var c2: int = t[ty * w + x2]
					if c2 != 0 and c2 != 4 and c2 != 5:
						ok = false
						break
				if ok:
					cand.append(land(t, w, hgt, sx + dx, ty))
		for n in cand:
			if n >= 0 and not seen.has(n):
				seen[n] = true
				todo.append(n)
	return out


## Where a fall from (x, y) ends: the first cell whose floor holds the feet
## (or a ladder), or -1 off the map / into rock.
static func land(t: PackedByteArray, w: int, hgt: int, x: int, y: int) -> int:
	var yy := y
	while yy < hgt - 1:
		var c: int = t[yy * w + x]
		if c == 1 or c == 2:
			return -1
		var b: int = t[(yy + 1) * w + x]
		if c == 4 or c == 5 or b == 1 or b == 2 or b == 3 or b == 4 or b == 5:
			if c == 3:
				yy += 1  # a ledge cell itself is not a place to stand in
				continue
			return yy * w + x
		yy += 1
	return -1

class_name Minimap
extends CanvasLayer
## Fog-of-war map of the floor. Small map in the top-right corner, the big
## one toggles with M. Shows explored cells, the hero, the exit, unopened
## chests, the merchant, event rooms, elites and the boss.

const SMALL_SCALE := 1.0
const BIG_SCALE := 3.0
const COLORS := {
	LevelLayout.Tile.EMPTY: Color(0.32, 0.26, 0.22, 0.9),
	LevelLayout.Tile.BEDROCK: Color(0.08, 0.06, 0.06, 0.95),
	LevelLayout.Tile.BRICK: Color(0.55, 0.42, 0.3, 0.95),
	LevelLayout.Tile.PLATFORM: Color(0.75, 0.58, 0.3, 0.95),
	LevelLayout.Tile.LADDER: Color(0.95, 0.85, 0.35, 0.95),
	LevelLayout.Tile.LADDER_TOP: Color(0.95, 0.85, 0.35, 0.95),
}

var _small: Control
var _big: Control
var _small_tex: TextureRect
var _big_tex: TextureRect
var _small_marks: Control
var _big_marks: Control
var _image: Image
var _texture: ImageTexture
var _level: DungeonLevel
var _version := -1
var _blink := 0.0
var _marks: Array = []  # [cell, color]
var _marks_timer := 0.0
var _legend: RichTextLabel


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_small = _make_panel(Vector2(116, 70))
	_small.anchor_left = 1.0
	_small.anchor_right = 1.0
	_small.offset_left = -120
	_small.offset_right = -4
	_small.offset_top = 4
	_small.offset_bottom = 74
	_small_tex = _small.get_node("Clip/Map")
	_small_marks = _small.get_node("Clip/Marks")
	_big = _make_panel(Vector2(360, 220))
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.offset_left = -180
	_big.offset_right = 180
	_big.offset_top = -150
	_big.offset_bottom = 70
	_big_tex = _big.get_node("Clip/Map")
	_big_marks = _big.get_node("Clip/Marks")
	_big.visible = false
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.scroll_active = false
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_font_size_override("normal_font_size", 6)
	_legend.add_theme_color_override("default_color", UIStyle.INK)
	_legend.text = "Карта этажа (M)   [color=#ffffff]■[/color] герой  [color=#cc66ff]■[/color] выход  [color=#ffd933]■[/color] сундук  [color=#4dff66]■[/color] торговец  [color=#4de6ff]■[/color] событие  [color=#ff4033]■[/color] элита/босс"
	_legend.position = Vector2(12, 202)
	_legend.size = Vector2(340, 12)
	_big.add_child(_legend)
	EventBus.inventory_toggled.connect(func(open: bool) -> void:
		if open:
			_big.visible = false)
	_small_marks.draw.connect(func() -> void: _draw_marks(_small_marks, SMALL_SCALE, true))
	_big_marks.draw.connect(func() -> void: _draw_marks(_big_marks, BIG_SCALE, false))


func _make_panel(size_px: Vector2) -> Control:
	var root := Control.new()
	root.size = size_px
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.35))
	var clip := Control.new()
	clip.name = "Clip"
	clip.clip_contents = true
	clip.position = Vector2(8, 8)
	clip.size = size_px - Vector2(16, 16)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var tex := TextureRect.new()
	tex.name = "Map"
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clip.add_child(tex)
	var marks := Control.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(marks)
	return root


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("minimap"):
		_big.visible = not _big.visible
		AudioManager.play_ui(&"ui_book_open" if _big.visible else &"ui_book_close")
		get_viewport().set_input_as_handled()


func toggle_big(show: bool) -> void:
	_big.visible = show


func is_big_open() -> bool:
	return _big.visible


func _process(delta: float) -> void:
	_blink += delta
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.level == null:
		return
	if player.level != _level:
		_level = player.level
		_version = -1
		_image = Image.create(_level.layout.width, _level.layout.height, false, Image.FORMAT_RGBA8)
		_texture = ImageTexture.create_from_image(_image)
		_small_tex.texture = _texture
		_big_tex.texture = _texture
	if _version == -1:
		_version = _level.explored_version
		_level.changed_cells.clear()
		_redraw_image()
	elif not _level.changed_cells.is_empty():
		_version = _level.explored_version
		_update_cells(_level.changed_cells)
		_level.changed_cells.clear()
	_layout(player)
	# Marks (chests, door, elites...) refresh 10 times a second, not every frame.
	_marks_timer -= delta
	if _marks_timer <= 0.0:
		_marks_timer = 0.1
		_collect_marks()
		_small_marks.queue_redraw()
		if _big.visible:
			_big_marks.queue_redraw()


## Only the cells that changed since the last frame.
func _update_cells(cells: Array[Vector2i]) -> void:
	var lay := _level.layout
	for c in cells:
		if lay.in_bounds(c.x, c.y):
			_image.set_pixel(c.x, c.y, COLORS.get(lay.get_tile(c.x, c.y), Color.MAGENTA) if _level.explored[c.y * lay.width + c.x] == 1 else Color(0, 0, 0, 0))
	_texture.update(_image)


## Entities worth a mark, gathered once per refresh.
func _collect_marks() -> void:
	_marks.clear()
	for n in _level.entities.get_children():
		var color := Color(0, 0, 0, 0)
		if n is ExitDoor:
			color = Color(0.8, 0.4, 1.0)
		elif n is Chest and not n.opened:
			color = Color(1.0, 0.85, 0.2)
		elif n is Merchant or n is Blacksmith:
			color = Color(0.3, 1.0, 0.4)
		elif n is EventObject and not n.used:
			color = Color(0.3, 0.9, 1.0)
		elif n is Boss or (n is Enemy and n.elite != null and not n.is_dead()):
			color = Color(1.0, 0.25, 0.2)
		if color.a == 0.0:
			continue
		var cell := _level.world_to_cell(n.global_position + Vector2(0, -4))
		if _level.is_explored(cell):
			_marks.append([cell, color])


func _redraw_image() -> void:
	var lay := _level.layout
	for y in lay.height:
		for x in lay.width:
			if _level.explored[y * lay.width + x] == 1:
				_image.set_pixel(x, y, COLORS.get(lay.get_tile(x, y), Color.MAGENTA))
			else:
				_image.set_pixel(x, y, Color(0, 0, 0, 0))
	_texture.update(_image)


## Small map follows the hero; the big map shows the whole floor centred.
func _layout(player: Player) -> void:
	var lay := _level.layout
	var map_size := Vector2(lay.width, lay.height)
	var hero_cell := Vector2(_level.world_to_cell(player.global_position + Vector2(0, -8)))
	var clip_small: Control = _small_tex.get_parent()
	var offset := clip_small.size / 2.0 - hero_cell * SMALL_SCALE
	offset = offset.clamp(clip_small.size - map_size * SMALL_SCALE, Vector2.ZERO) if map_size.x * SMALL_SCALE > clip_small.size.x else offset
	_small_tex.position = offset
	_small_tex.size = map_size * SMALL_SCALE
	_small_marks.position = offset
	_small_marks.size = _small_tex.size
	var clip_big: Control = _big_tex.get_parent()
	var big_scale := minf(BIG_SCALE, minf(clip_big.size.x / map_size.x, (clip_big.size.y - 12.0) / map_size.y))
	_big_tex.size = map_size * big_scale
	_big_tex.position = (clip_big.size - Vector2(0, 12) - _big_tex.size) / 2.0
	_big_marks.position = _big_tex.position
	_big_marks.size = _big_tex.size
	_big_marks.set_meta("scale", big_scale)


func _draw_marks(canvas: Control, scale_default: float, small: bool) -> void:
	if _level == null:
		return
	var sc: float = canvas.get_meta("scale", scale_default)
	var dot := maxf(2.0, sc)
	for m in _marks:
		var cell: Vector2i = m[0]
		canvas.draw_rect(Rect2(Vector2(cell) * sc - Vector2(dot, dot) / 2.0 + Vector2(sc, sc) / 2.0, Vector2(dot, dot)), m[1])
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and int(_blink * 4.0) % 2 == 0:
		var pc := _level.world_to_cell(player.global_position + Vector2(0, -8))
		canvas.draw_rect(Rect2(Vector2(pc) * sc - Vector2(dot, dot) / 2.0 + Vector2(sc, sc) / 2.0, Vector2(dot, dot) * 1.2), Color.WHITE)


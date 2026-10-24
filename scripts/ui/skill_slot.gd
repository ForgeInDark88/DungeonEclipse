class_name SkillSlot
extends Control
## HUD skill cell: icon, cooldown shade with seconds, key hint and the row of
## level dots underneath (blue = learned levels, grey = still available).
## Click spends a skill point when the hero has one.

const DOT_SIZE := 4

var hero: Hero
var index: int
var key_label := ""

var _frame: PixelFrame
var _icon: TextureRect
var _shade: TextureProgressBar
var _ready_flash: ColorRect
var _was_cooling := false
var _cd_label: Label
var _key: Label
var _plus: Label
var _dots: HBoxContainer


static func create(p_hero: Hero, p_index: int, p_key: String) -> SkillSlot:
	var s := SkillSlot.new()
	s.hero = p_hero
	s.index = p_index
	s.key_label = p_key
	return s


func _ready() -> void:
	custom_minimum_size = UIStyle.SLOT_SIZE + Vector2(0, DOT_SIZE + 2)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Control.new()
	box.size = UIStyle.SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_frame = UIStyle.frame(AssetPaths.SLOT_EMPTY, 5)
	box.add_child(_frame)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 3
	_icon.offset_top = 3
	_icon.offset_right = -3
	_icon.offset_bottom = -3
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon)
	# Radial cooldown: a dark sector that shrinks clockwise.
	_shade = TextureProgressBar.new()
	var img := Image.create(int(UIStyle.SLOT_SIZE.x) - 8, int(UIStyle.SLOT_SIZE.y) - 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.03, 0.08, 0.72))
	_shade.texture_progress = ImageTexture.create_from_image(img)
	_shade.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_shade.max_value = 1.0
	_shade.step = 0.001
	_shade.position = Vector2(4, 4)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_shade)
	_ready_flash = ColorRect.new()
	_ready_flash.color = Color(1, 1, 0.85, 0)
	_ready_flash.position = Vector2(4, 4)
	_ready_flash.size = UIStyle.SLOT_SIZE - Vector2(8, 8)
	_ready_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_ready_flash)
	box.add_child(UIStyle.icon_border())
	_cd_label = UIStyle.outlined_label("", 8, Color.WHITE)
	_cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_cd_label)
	_key = UIStyle.outlined_label(key_label, 6, UIStyle.GOLD)
	_key.position = Vector2(3, 0)
	box.add_child(_key)
	_plus = UIStyle.outlined_label("+", 9, Color(0.4, 1.0, 0.4))
	_plus.position = Vector2(UIStyle.SLOT_SIZE.x - 9, -3)
	box.add_child(_plus)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 1)
	_dots.position = Vector2(0, UIStyle.SLOT_SIZE.y + 1)
	_dots.size = Vector2(UIStyle.SLOT_SIZE.x, DOT_SIZE)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dots)
	mouse_entered.connect(_show_tip)
	mouse_exited.connect(func() -> void: Tooltip.hide_tip(self))
	refresh()


func refresh() -> void:
	var skill := hero.skills.get_skill(index) if hero else null
	_icon.texture = skill.icon if skill else null
	_frame.texture = AssetPaths.tex(AssetPaths.SLOT if skill else AssetPaths.SLOT_EMPTY)
	_key.visible = skill != null
	_plus.visible = skill != null and hero.skills.can_upgrade(index)
	for c in _dots.get_children():
		c.queue_free()
	if skill:
		var lvl := hero.skills.get_level(index)
		for i in skill.max_level:
			var d := TextureRect.new()
			d.texture = AssetPaths.tex(AssetPaths.DOT_FULL if i < lvl else AssetPaths.DOT_EMPTY)
			d.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_dots.add_child(d)
	_update_cooldown()


func _process(_delta: float) -> void:
	_update_cooldown()


func _update_cooldown() -> void:
	if hero == null or hero.skills.get_skill(index) == null:
		_shade.visible = false
		_cd_label.text = ""
		return
	var ratio := hero.skills.cooldown_ratio(index)
	_shade.visible = ratio > 0.0
	_shade.value = ratio
	if _was_cooling and ratio <= 0.0:
		_flash_ready()
	_was_cooling = ratio > 0.0
	var left: float = hero.skills.cooldown_left(index)
	_cd_label.text = ("%.1f" % left if left < 1.0 else str(ceili(left))) if left > 0.0 else ""
	var skill := hero.skills.get_skill(index)
	var no_mana := hero.stats.mana < skill.mana_cost
	_icon.modulate = Color(0.5, 0.5, 0.8) if no_mana else Color.WHITE


## Bright blink + bounce when the skill becomes available again.
func _flash_ready() -> void:
	_ready_flash.color.a = 0.8
	var tw := create_tween()
	tw.tween_property(_ready_flash, "color:a", 0.0, 0.3)
	pivot_offset = UIStyle.SLOT_SIZE / 2.0
	scale = Vector2(1.15, 1.15)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_tip() -> void:
	var skill := hero.skills.get_skill(index) if hero else null
	if skill:
		Tooltip.show_text(TooltipText.skill(skill, hero.skills.get_level(index), hero.skills.skill_points), self)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if hero.skills.can_upgrade(index):
			hero.skills.upgrade(index)
			_show_tip()
		else:
			var player := get_tree().get_first_node_in_group("player") as Player
			if player and not get_tree().paused:
				player.use_skill(index)


func set_key_label(text: String) -> void:
	key_label = text
	if _key:
		_key.text = text

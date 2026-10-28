class_name BossStage
extends Control
## Boss fight presentation over the HUD: the intro card (black bars slide
## in, the boss's name and title, its line typed out) and the big banner for
## phase changes, rage and the last words. Listens to EventBus only.

const BAR_H := 34.0
const INTRO_TIME := 2.6
const BANNER_TIME := 2.2

var _top: ColorRect
var _bottom: ColorRect
var _name: Label
var _title: Label
var _line: Label
var _banner_title: Label
var _banner_text: Label
var _tween: Tween
var _banner_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top = _bar()
	_bottom = _bar()
	_top.anchor_bottom = 0.0
	_bottom.anchor_top = 1.0
	_name = _label(18, UIStyle.GOLD)
	_title = _label(9, UIStyle.PARCHMENT)
	_line = _label(8, Color(0.85, 0.8, 0.75))
	_name.offset_top = -34
	_name.offset_bottom = -12
	_title.offset_top = -10
	_title.offset_bottom = 2
	_line.offset_top = 8
	_line.offset_bottom = 22
	_banner_title = _label(8, UIStyle.PARCHMENT)
	_banner_text = _label(14, Color.WHITE)
	_banner_title.offset_top = -64
	_banner_title.offset_bottom = -52
	_banner_text.offset_top = -50
	_banner_text.offset_bottom = -30
	for c in [_name, _title, _line, _banner_title, _banner_text]:
		c.modulate.a = 0.0
	EventBus.boss_intro.connect(_on_intro)
	EventBus.boss_banner.connect(_on_banner)
	EventBus.floor_changed.connect(func(_f: int) -> void: _hide_all())


func _bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.92)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0
	r.anchor_bottom = 1.0
	r.offset_top = 0.0
	r.offset_bottom = 0.0
	r.visible = false
	add_child(r)
	return r


func _label(size: int, color: Color) -> Label:
	var l := UIStyle.outlined_label("", size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _on_intro(b: Node) -> void:
	var boss := b as Boss
	if boss == null or boss.boss == null:
		return
	var parts := boss.boss.title.split(" — ", false, 1)
	_name.text = boss.boss.display_name
	_title.text = parts[1] if parts.size() > 1 else ""
	_name.add_theme_color_override("font_color", boss.boss.glow_color.lerp(UIStyle.GOLD, 0.5))
	_line.text = ("«%s»" % boss.boss.intro_line) if boss.boss.intro_line != "" else ""
	_line.visible_ratio = 0.0
	if _tween:
		_tween.kill()
	_top.visible = true
	_bottom.visible = true
	_top.offset_bottom = 0.0
	_bottom.offset_top = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_top, "offset_bottom", BAR_H, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bottom, "offset_top", -BAR_H, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_name.scale = Vector2.ONE
	_tween.tween_property(_name, "modulate:a", 1.0, 0.4).set_delay(0.2)
	_tween.tween_property(_title, "modulate:a", 1.0, 0.4).set_delay(0.45)
	_tween.tween_property(_line, "modulate:a", 1.0, 0.2).set_delay(0.7)
	_tween.tween_property(_line, "visible_ratio", 1.0, 1.0).set_delay(0.7)
	_tween.chain().tween_interval(INTRO_TIME - 1.7)
	_tween.chain().tween_callback(_close_intro)


func _close_intro() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "offset_bottom", 0.0, 0.3)
	tw.tween_property(_bottom, "offset_top", 0.0, 0.3)
	for c in [_name, _title, _line]:
		tw.tween_property(c, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		_top.visible = false
		_bottom.visible = false)
	_tween = tw


func _on_banner(title: String, text: String, color: Color) -> void:
	_banner_title.text = title
	_banner_text.text = text
	_banner_text.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	if _banner_tween:
		_banner_tween.kill()
	_banner_text.pivot_offset = Vector2(_banner_text.size.x * 0.5, 10)
	_banner_text.scale = Vector2(1.4, 1.4)
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_banner_title, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_property(_banner_text, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_property(_banner_text, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(BANNER_TIME)
	_banner_tween.chain().tween_property(_banner_title, "modulate:a", 0.0, 0.5)
	_banner_tween.parallel().tween_property(_banner_text, "modulate:a", 0.0, 0.5)


func _hide_all() -> void:
	for t in [_tween, _banner_tween]:
		if t:
			t.kill()
	_top.visible = false
	_bottom.visible = false
	for c in [_name, _title, _line, _banner_title, _banner_text]:
		c.modulate.a = 0.0

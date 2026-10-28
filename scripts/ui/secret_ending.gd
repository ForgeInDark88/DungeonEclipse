class_name SecretEnding
extends CanvasLayer
## «Рассвет над Аурелией»: the other way to end it. The hero remembers the
## guardians' names and lets the black sun go instead of breaking it - the
## dark turns gold, the sun rises through the vaults, the lines of the ending
## appear one by one. `finished` fires when the player goes on.

signal finished

const LINES := [
	"Ты вспоминаешь их имена.",
	"Олдрик — могильщик, дважды поднятый из праха. Илара, что хотела зажечь новое солнце. Пип, спрятавшийся в зеркалах. Каменный — сердце горы. Брат Оствин и его колокол.",
	"Чёрное солнце слушает. Оно так долго ждало, что кто-то посмотрит на него — и не ударит.",
	"Ты не разбиваешь его. Ты отпускаешь.",
	"Свет поднимается сквозь своды — сквозь пепел, воду и кристалл — вверх, туда, где ему место.",
	"Над деревней у ущелья впервые за долгие годы встаёт солнце. Летописец закрывает книгу: история дописана.",
	"А где-то в катакомбах кости Олдрика наконец ложатся в землю.",
]

var _bg: ColorRect
var _sun: Control
var _box: VBoxContainer
var _t := 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.01, 0.04)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_sun = Control.new()
	_sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.draw.connect(_draw_sun)
	add_child(_sun)
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = 60
	_box.offset_right = -60
	_box.offset_top = 150
	_box.offset_bottom = -20
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	AudioManager.play_sting(&"ending", &"")
	_play()


func _process(delta: float) -> void:
	_t += delta
	_sun.queue_redraw()


## The black sun turns gold and rises: its rim warms first, then the disc.
func _draw_sun() -> void:
	var size := _sun.size
	var k := clampf(_t / 9.0, 0.0, 1.0)
	var center := Vector2(size.x / 2.0, lerpf(size.y * 0.45, size.y * 0.16, k))
	var r := lerpf(34.0, 26.0, k)
	for i in 8:
		var a := 0.06 * (1.0 - i / 8.0) * (0.3 + k)
		_sun.draw_circle(center, r + 10.0 + i * 9.0 + sin(_t * 2.0) * 2.0, Color(1.0, 0.8, 0.4, a))
	_sun.draw_circle(center, r + 3.0, Color(1.0, 0.75, 0.35).lerp(Color(1.0, 0.95, 0.7), k))
	_sun.draw_circle(center, r, Color(0.06, 0.03, 0.08).lerp(Color(1.0, 0.86, 0.5), k))
	for i in 16:
		var ang := i * TAU / 16.0 + _t * 0.15
		var ln := r + 14.0 + 10.0 * k + sin(_t * 3.0 + i) * 3.0
		_sun.draw_line(center + Vector2.from_angle(ang) * (r + 4.0), center + Vector2.from_angle(ang) * ln,
				Color(1.0, 0.85, 0.5, 0.5 + 0.4 * k), 2.0)


func _play() -> void:
	var tw := create_tween()
	tw.tween_property(_bg, "color", Color(0.35, 0.22, 0.1), 9.0)
	var seq := create_tween()
	for line in LINES:
		var l := UIStyle.outlined_label(line, 9, Color(1.0, 0.94, 0.8))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate.a = 0.0
		_box.add_child(l)
		seq.tween_property(l, "modulate:a", 1.0, 0.9)
		seq.tween_interval(clampf(line.length() / 40.0, 1.2, 3.2))
	var title := UIStyle.outlined_label("Рассвет над Аурелией", 16, UIStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	_box.add_child(title)
	seq.tween_property(title, "modulate:a", 1.0, 1.2)
	seq.tween_callback(func() -> void:
		var b := BookPageScreen.button("Дальше", func() -> void:
			finished.emit()
			queue_free())
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box.add_child(b)
		b.grab_focus())

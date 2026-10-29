class_name FishingGame
extends CanvasLayer
## The fishing mini-game: wait for a bite, strike on the «!», then reel in by
## pressing when the needle is inside the green zone (rarer fish - narrower
## zone, faster needle). Interact / attack / Space press; Esc gives up.

const BAR_W := 200.0
const BITE_WINDOW := 0.75

enum Stage { WAIT, BITE, REEL, DONE }

## [item id, weight, zone width (0..1), needle speed]
const CATCH := [
	[&"cave_fish", 55.0, 0.34, 1.0],
	[&"glow_eel", 24.0, 0.24, 1.35],
	[&"golden_carp", 7.0, 0.13, 1.8],
	[&"iron_ore", 6.0, 0.4, 0.9],
	[&"bone", 5.0, 0.4, 0.9],
	[&"eclipse_shard", 3.0, 0.2, 1.5],
]

var _spot: FishingSpot
var _player: Player
var _stage: Stage = Stage.WAIT
var _t := 0.0
var _wait := 2.0
var _catch: Array
var _zone_from := 0.4
var _needle := 0.0
var _dir := 1.0
var _panel: Control
var _label: Label
var _bar: Control
var _paused_here := false


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(spot: FishingSpot, player: Player) -> void:
	_spot = spot
	_player = player
	_player.busy = true
	if not Net.active:
		get_tree().paused = true
		_paused_here = true
	_wait = randf_range(1.2, 3.4)
	_catch = _roll()
	_zone_from = randf_range(0.05, 0.95 - _catch[2])
	_build()
	_say("Закидываешь удочку... ждём поклёвки")
	AudioManager.play_sfx(&"jump", player.global_position, -10.0)


func _roll() -> Array:
	var total := 0.0
	for c in CATCH:
		total += c[1]
	var r := randf() * total
	for c in CATCH:
		r -= c[1]
		if r <= 0.0:
			return c
	return CATCH[0]


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -130
	_panel.offset_right = 130
	_panel.offset_top = -150
	_panel.offset_bottom = -88
	add_child(_panel)
	_panel.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.35))
	_label = UIStyle.label("", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(10, 8)
	_label.size = Vector2(240, 14)
	_panel.add_child(_label)
	_bar = Control.new()
	_bar.position = Vector2(30, 28)
	_bar.size = Vector2(BAR_W, 14)
	_bar.draw.connect(_draw_bar)
	_panel.add_child(_bar)
	var hint := UIStyle.label("[%s] / ЛКМ — подсечь · Esc — бросить" % InputBindings.key_for("interact"), 6, UIStyle.INK_SOFT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(10, 44)
	hint.size = Vector2(240, 10)
	_panel.add_child(hint)


func _say(text: String) -> void:
	if _label:
		_label.text = text


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		Stage.WAIT:
			if _player.dead:
				_end(false, "Не до рыбалки!")
			elif _t >= _wait:
				_stage = Stage.BITE
				_t = 0.0
				_say("! ! !  Клюёт — подсекай!")
				AudioManager.play_sfx(&"ui_click", _player.global_position)
		Stage.BITE:
			if _t >= BITE_WINDOW:
				_end(false, "Рыба сорвалась с крючка.")
		Stage.REEL:
			_needle += _dir * delta * 0.9 * float(_catch[3])
			if _needle >= 1.0 or _needle <= 0.0:
				_dir = -_dir
				_needle = clampf(_needle, 0.0, 1.0)
	if _bar:
		_bar.queue_redraw()


func _draw_bar() -> void:
	_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(0.15, 0.25, 0.3))
	if _stage == Stage.REEL or _stage == Stage.DONE:
		_bar.draw_rect(Rect2(Vector2(_zone_from * BAR_W, 0), Vector2(float(_catch[2]) * BAR_W, _bar.size.y)), Color(0.3, 0.85, 0.4, 0.85))
		var x := _needle * BAR_W
		_bar.draw_rect(Rect2(Vector2(x - 1, -3), Vector2(3, _bar.size.y + 6)), Color(1.0, 0.95, 0.7))
	elif _stage == Stage.BITE:
		_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(1.0, 0.5, 0.3, 0.5 + 0.5 * absf(sin(_t * 30.0))))
	else:
		# The float bobbing on the water while you wait.
		var fx := BAR_W * 0.5 + sin(_t * 2.0) * 8.0
		_bar.draw_circle(Vector2(fx, _bar.size.y * 0.5 + sin(_t * 5.0) * 1.5), 3.0, Color(0.9, 0.25, 0.2))
	_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(0.1, 0.06, 0.03), false, 1.0)


## _input, not _unhandled_input: the HUD would swallow the mouse click, and
## in co-op (no pause) the hero would take the key first.
func _input(event: InputEvent) -> void:
	if _stage == Stage.DONE:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_end(false, "Ты сматываешь удочку.")
		return
	var strike := event.is_action_pressed("interact") or event.is_action_pressed("attack") or event.is_action_pressed("ui_accept")
	if not strike:
		return
	get_viewport().set_input_as_handled()
	match _stage:
		Stage.WAIT:
			_end(false, "Рано! Рыбу спугнул.")
		Stage.BITE:
			_stage = Stage.REEL
			_t = 0.0
			_needle = 0.0
			_dir = 1.0
			_say("Тяни! Жми, когда стрелка в зелёной зоне")
		Stage.REEL:
			if _needle >= _zone_from and _needle <= _zone_from + float(_catch[2]):
				_land()
			else:
				_end(false, "Леска лопнула — ушла.")


func _land() -> void:
	var item := ItemDatabase.get_item(_catch[0])
	if item == null:
		_end(false, "Пусто.")
		return
	var left := _player.hero.inventory.add_item(item, 1)
	_spot.caught()
	if left > 0:
		_end(false, "Поймал «%s», но рюкзак полон — пришлось отпустить." % item.display_name)
		return
	AudioManager.play_ui(&"pickup_rare" if item.rarity >= ItemData.Rarity.RARE else &"pickup_common")
	Fx.sparks(_player.get_parent(), _spot.global_position + Vector2(0, -8), Color(0.7, 0.95, 1.0), 12, 70.0)
	_end(true, "Улов: «%s»!" % item.display_name)


func _end(ok: bool, text: String) -> void:
	_stage = Stage.DONE
	_say(text)
	EventBus.message.emit(text)
	if not ok:
		AudioManager.play_sfx(&"chest_locked", _player.global_position, -6.0)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_player):
			_player.busy = false
		if _paused_here:
			get_tree().paused = false
		queue_free())


func _exit_tree() -> void:
	# Whatever ends the game (floor change, the scene freed): free the hero.
	if is_instance_valid(_player):
		_player.busy = false
	if _paused_here and get_tree():
		get_tree().paused = false

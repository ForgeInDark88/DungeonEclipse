class_name AchievementToast
extends CanvasLayer
## Parchment card that slides in from the top when an achievement unlocks.
## Lives under the Codex autoload, so it works in every scene. Queued: one at a time.

const SHOW_TIME := 3.0

var _queue: Array[AchievementData] = []
var _busy := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.achievement_unlocked.connect(func(a: AchievementData) -> void:
		_queue.append(a)
		if not _busy:
			_show_next())


func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var a: AchievementData = _queue.pop_front()
	var card := Control.new()
	card.size = Vector2(190, 34)
	card.position = Vector2((get_viewport().get_visible_rect().size.x - card.size.x) / 2.0, -40)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(UIStyle.frame(AssetPaths.TOOLTIP, 4))
	var icon := TextureRect.new()
	icon.texture = a.icon
	icon.position = Vector2(8, 9)
	icon.size = Vector2(16, 16)
	card.add_child(icon)
	var title := UIStyle.label("Достижение: " + a.display_name, 8)
	title.position = Vector2(30, 4)
	card.add_child(title)
	var sub := UIStyle.label(a.description + ("  +%d оск." % a.reward_shards if a.reward_shards > 0 else ""), 6, UIStyle.INK_SOFT)
	sub.position = Vector2(30, 18)
	card.add_child(sub)
	add_child(card)
	AudioManager.play_ui(&"pickup_epic")
	var tw := create_tween()
	tw.tween_property(card, "position:y", 6.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(card, "position:y", -40.0, 0.3)
	tw.tween_callback(func() -> void:
		card.queue_free()
		_show_next())

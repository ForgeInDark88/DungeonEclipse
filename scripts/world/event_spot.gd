class_name EventSpot
extends Area2D
## A road event in its room: the scenery of the event (EventData.prop), the
## hero walks up and presses E - the choice opens (EventDialog). The outcome
## happens right here: a reward, a wound, a blessing - or the monsters come
## out of the dark and the exit stays sealed until they are dead.

var level: DungeonLevel
var event: EventData
var done := false
## Cells where a fight's monsters appear (left and right of the scenery).
var fight_cells: Array[Vector2i] = []
var _sprite: Sprite2D
var _mark: Label


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("event_spots")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	for e in ItemDatabase.road_events:
		if e.id == StringName(GameState.location.get("event", &"")):
			event = e
	var tex := AssetPaths.tex(AssetPaths.SPRITES_DIR + "road_events/%s.png" % (event.prop if event else &"shrine"))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(24.0, tex.get_width() if tex else 24.0), 32)
	shape.shape = rect
	shape.position = Vector2(0, -16)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = false
	if tex:
		_sprite.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())
	_sprite.z_index = -1
	add_child(_sprite)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(1.0, 0.85, 0.6)
	light.energy = 0.9
	light.texture_scale = 0.6
	light.position = Vector2(0, -16)
	add_child(light)
	_mark = UIStyle.outlined_label("?", 11, UIStyle.GOLD)
	_mark.position = Vector2(-3, -(tex.get_height() if tex else 30) - 16)
	add_child(_mark)
	if event:
		EventBus.message.emit.call_deferred(tr(event.title))


func _process(_delta: float) -> void:
	if _mark.visible:
		_mark.position.y += sin(Time.get_ticks_msec() / 220.0) * 0.08


func can_interact() -> bool:
	return not done and event != null


func get_prompt() -> String:
	return tr("Подойти: %s") % tr(event.title) if event else ""


func interact(_player: Node) -> void:
	if done or event == null:
		return
	AudioManager.play_ui(&"ui_book_open")
	var dlg := EventDialog.new()
	get_tree().current_scene.add_child(dlg)
	dlg.open(event, self)


## The answer is taken: nothing more to do here.
func finish() -> void:
	done = true
	_mark.visible = false
	remove_from_group("interactable")
	Fx.sparks(get_parent(), global_position + Vector2(0, -14), Color(1.0, 0.9, 0.6), 14, 70.0)


## The answer brought a fight: monsters come out of the dark on both sides,
## the exit is sealed until they fall (then the rescue of the event, if any,
## is paid at the exit by GameFlow.location_summary).
func start_fight(kind: StringName) -> void:
	if level == null or fight_cells.is_empty():
		return
	var count := (3 if kind == &"elite" else 4) + GameState.depth() / 10
	var foes := level.spawn_ambush_wave(fight_cells, count, kind == &"elite")
	level.seal_for_fight(foes.size())
	EventBus.screen_shake.emit(3.0)
	AudioManager.play_sfx(&"boss_roar", global_position, -6.0)
	EventBus.message.emit(tr("Из темноты выходят враги! Выход запечатан, пока они живы."))

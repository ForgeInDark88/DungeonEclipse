class_name TownNpc
extends Area2D
## A person living in the town: strolls near their door (or the square),
## shows "!" when they have something new to say, talks (DialogBook) on E.

const WANDER := 26.0
const SPEED := 12.0

var data: NpcData
## Where this person is by the hour (TownBuilder): {"morning", "day",
## "evening", "night"} -> x in px. The hour comes from the town's sky.
var schedule: Dictionary = {}
var _hour: StringName = &""
var _hour_check := 0.0
var _bubble: Label
var _bubble_left := 0.0
var _chat_cool := 0.0
## Small talk of the street (two neighbours who stop by each other).
const CHATTER := [
	"Слыхал? У ворот опять видели волков.", "Цены на железо снова выросли.",
	"Кузнец говорит, в горах есть руда получше.", "Ночью на кладбище кто-то бродит.",
	"Говорят, под руинами есть старая шахта.", "Хорошо, что стену подлатали.",
	"В таверне сегодня новый эль!", "Без разведчиков мы бы и шагу не ступили.",
	"Помнишь тех, кто не вернулся? Я каждое утро хожу к мемориалу.",
	"Если найдёшь чертёж — неси в город, мастера скажут спасибо.",
	"Стражей региона лучше бить вчетвером.", "Ягоды с поверхности — лучшая еда в дорогу.",
]
var _sprite: Sprite2D
var _mark: Label
var _home_x := 0.0
var _target := 0.0
var _wait := 0.0


func setup(p_data: NpcData) -> void:
	data = p_data


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("town_npcs")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = data.sprite
	var sheet := AssetPaths.npc_sheet(data.id)
	if sheet:
		_sprite.texture = sheet
		_sprite.hframes = 2
	_sprite.centered = false
	_sprite.offset = Vector2(-10, -30)
	add_child(_sprite)
	_mark = UIStyle.outlined_label("!", 10, UIStyle.GOLD)
	_mark.position = Vector2(-3, -46)
	add_child(_mark)
	_home_x = position.x
	_target = _home_x
	_wait = randf_range(0.5, 3.0)
	refresh_mark()


func refresh_mark() -> void:
	_mark.visible = Dialogs.has_news(data)


func _process(delta: float) -> void:
	_follow_schedule(delta)
	_chatter(delta)
	if _sprite.hframes > 1:
		_sprite.frame = int(Time.get_ticks_msec() / 700 + get_instance_id()) % 2
	if _mark.visible:
		_mark.position.y = -46 + sin(Time.get_ticks_msec() / 200.0) * 1.5
	if _wait > 0.0:
		_wait -= delta
		return
	var dx := _target - position.x
	if absf(dx) < 1.0:
		_wait = randf_range(1.5, 4.0)
		_target = _home_x + randf_range(-WANDER, WANDER)
		return
	var spd := SPEED * (3.0 if absf(dx) > 80.0 else 1.0)  # far away: hurry
	position.x += signf(dx) * minf(absf(dx), spd * delta)
	_sprite.flip_h = dx < 0.0
	_stick_to_street()


## On the terraces of the town the street is higher: walk on it.
func _stick_to_street() -> void:
	var lvl := get_parent().get_parent() as DungeonLevel
	if lvl == null or not lvl.layout.is_town or lvl.layout.width != TownBuilder.HUB_WIDTH:
		return
	var cx := lvl.world_to_cell(global_position).x
	global_position.y = lvl.cell_bottom(Vector2i(cx, TownBuilder.ground_at(cx) - 1)).y


## The hour changed (morning, day, evening, night): off to the next place.
func _follow_schedule(delta: float) -> void:
	if schedule.is_empty():
		return
	_hour_check -= delta
	if _hour_check > 0.0:
		return
	_hour_check = 2.0
	var sky := get_tree().get_first_node_in_group("town_sky") as SurfaceSky
	var phase := SurfaceSky.phase_name(sky.phase) if sky else &"day"
	var hour: StringName = {&"dawn": &"morning", &"day": &"day", &"evening": &"evening", &"night": &"night"}.get(phase, &"day")
	if hour != _hour and schedule.has(String(hour)):
		_hour = hour
		_home_x = float(schedule[String(hour)])
		_target = _home_x + randf_range(-8.0, 8.0)
		_wait = randf_range(0.0, 3.0)


## Two neighbours standing by each other trade a word now and then.
func _chatter(delta: float) -> void:
	_chat_cool -= delta
	if _bubble:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.queue_free()
			_bubble = null
	if _chat_cool > 0.0 or _wait <= 0.0:
		return
	_chat_cool = randf_range(6.0, 14.0)
	for n in get_tree().get_nodes_in_group("town_npcs"):
		if n != self and (n as Node2D).global_position.distance_to(global_position) < 40.0 and randf() < 0.5:
			say(tr(CHATTER[randi() % CHATTER.size()]))
			return


func say(text: String) -> void:
	if _bubble:
		_bubble.queue_free()
	_bubble = UIStyle.outlined_label(text, 6, UIStyle.PARCHMENT)
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.custom_minimum_size = Vector2(110, 0)
	_bubble.position = Vector2(-55, -64)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_bubble)
	_bubble_left = 4.0


func get_prompt() -> String:
	return tr("Поговорить: %s") % data.display_name


func interact(_player: Node) -> void:
	AudioManager.play_ui(&"ui_book_open")
	var book := DialogBook.new()
	get_tree().current_scene.add_child(book)
	book.open(data)
	book.closed.connect(func() -> void:
		for n in get_tree().get_nodes_in_group("town_npcs"):
			(n as TownNpc).refresh_mark())

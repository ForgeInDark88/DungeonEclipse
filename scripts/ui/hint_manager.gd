class_name HintManager
extends CanvasLayer
## Beginner hints: each tip is shown once (ids saved in SaveManager.seen_hints)
## when its moment comes, as a small parchment card under the floor plaque.
## Texts use {action} placeholders replaced by the current key bindings.
## Off with Settings → «Подсказки новичку».

const SHOW_TIME := 6.0
const HINTS := {
	&"move": "{move_left} / {move_right} — ходьба, {jump} — прыжок, {attack} — атака. Esc — пауза и настройки.",
	&"interact": "{interact} — открыть, подобрать, войти. Сундуки бывают заперты: нужен ключ.",
	&"inventory": "Предмет в рюкзаке! {inventory} — книга-инвентарь: перетаскивайте вещи на героя.",
	&"skills": "Новый уровень: {skill_tree} — дерево навыков, клик по слоту навыка — улучшить его.",
	&"low_hp": "Мало здоровья! Зелья лежат в быстрых слотах (1–7).",
	&"status": "На вас статус — значки над панелью. Противоядие лечит яд и кровотечение.",
	&"map": "{minimap} — большая карта этажа. Тёмные места ещё не исследованы.",
	&"boss": "Страж этажа! Красные зоны на полу — сигнал атаки: уходите из них.",
	&"merchant": "Торговец: покупайте за золото, продавайте вещи из рюкзака.",
	&"defend_parry": "{defend} — поднять щит: удар в этот миг парируется, враг оглушён.",
	&"defend_roll": "{defend} — перекат: пока катитесь, вас не задеть.",
	&"defend_none": "{defend} — защитный приём вашего класса.",
	&"defend_blink": "{defend} — скачок: короткий рывок, во время которого вас не задеть. Перезарядка 1,6 с.",
	&"skill_use": "Навыки — на клавишах {skill_1}–{skill_4} (панель внизу). Тратят ману, у каждого своя перезарядка.",
	&"seal": "Печать выхода: дверь на следующий этаж откроется, когда убьёте нужное число монстров (счётчик слева вверху).",
	&"trap": "Ловушка! Подойдите и нажмите {interact}, чтобы обезвредить. Неудача — сработает. Шанс выше с ловкостью.",
	&"junk": "Рюкзак полнится: Ctrl+клик по вещи — пометить мусором, у торговца «Продать мусор». Материалы идут в мешок сами.",
}

var _queue: Array[StringName] = []
var _card: Control
var _label: Label
var _busy := false


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = Control.new()
	_card.position = Vector2(8, 40)
	_card.size = Vector2(240, 30)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_card.add_child(UIStyle.frame(AssetPaths.TOOLTIP, 4))
	_label = UIStyle.label("", 7)
	_label.position = Vector2(8, 5)
	_label.size = Vector2(224, 20)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_label)
	add_child(_card)


## Connects the triggers to the player of this run.
func setup(player: Player) -> void:
	var hero := player.hero
	show_hint.call_deferred(&"move")
	player.interact_hint_changed.connect(func(t: String) -> void:
		if t != "":
			show_hint(&"interact"))
	EventBus.item_collected.connect(func(_i: ItemData, _p: Vector2) -> void: show_hint(&"inventory"))
	hero.leveled_up.connect(func(_l: int) -> void: show_hint(&"skills"))
	hero.stats.hp_changed.connect(func(hp: int, mx: int) -> void:
		if hp > 0 and hp < mx * 0.35:
			show_hint(&"low_hp"))
	player.status.applied.connect(func(id: StringName) -> void:
		if id in StatusEffects.NEGATIVE:
			show_hint(&"status"))
	EventBus.floor_changed.connect(func(_f: int) -> void: show_hint(&"map"))
	EventBus.boss_spawned.connect(func(_b: Node) -> void: show_hint(&"boss"))
	EventBus.shop_requested.connect(func(_m: Node, _p: Node) -> void: show_hint(&"merchant"))
	# First floor basics, one after another after «move».
	var move: StringName = hero.class_data.defense_move if hero.class_data else &""
	show_hint.call_deferred({&"parry": &"defend_parry", &"roll": &"defend_roll", &"blink": &"defend_blink"}.get(move, &"defend_none"))
	show_hint.call_deferred(&"skill_use")
	EventBus.seal_changed.connect(func(kills: int, _req: int) -> void:
		if kills >= 1:
			show_hint(&"seal"))
	player.interact_hint_changed.connect(func(t: String) -> void:
		if t.contains(tr("Обезвредить")):
			show_hint(&"trap"))
	var picked := [0]
	EventBus.item_collected.connect(func(_i: ItemData, _p: Vector2) -> void:
		picked[0] += 1
		if picked[0] >= 8:
			show_hint(&"junk"))


static func format(text: String) -> String:
	for entry in InputBindings.REBINDABLE:
		text = text.replace("{%s}" % entry[0], InputBindings.key_for(entry[0]))
	return text


func show_hint(id: StringName) -> void:
	if not SaveManager.show_hints or id in SaveManager.seen_hints or id in _queue or not HINTS.has(id):
		return
	SaveManager.seen_hints.append(id)
	SaveManager.save_settings()
	_queue.append(id)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var id: StringName = _queue.pop_front()
	_label.text = format(tr(HINTS[id]))
	_card.size.y = maxf(30.0, _label.get_minimum_size().y + 10.0)
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.25)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(_card, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_next)


## Id currently on screen (tests).
func current_text() -> String:
	return _label.text if _busy else ""

class_name InfoBook
extends CanvasLayer
## A book of chapters: the list on the left page, the chosen chapter on the
## right. Used for «Как играть» (InfoBook.how_to_play()) and «Авторы»
## (InfoBook.credits()) from the main menu and the pause menu.
## Texts may hold {action} placeholders - replaced by the current key
## bindings (HintManager.format).

signal closed

const BOOK_SIZE := Vector2(560, 310)

var title := ""
## [[chapter name, text], ...]
var chapters: Array = []

var _root: Control
var _text: Label
var _head: Label
var _buttons: Array[Button] = []
var _scroll: ScrollContainer


static func how_to_play() -> InfoBook:
	var b := InfoBook.new()
	b.title = "Как играть"
	b.chapters = [
		["Цель", "Город Аурелия живёт под вечным Затмением. Спуститесь через 35 этажей подземелья, победите шестерых " +
			"стражей и само Затмение.\n\nКаждые 5 этажей — страж. Смерть обрывает забег: начнёте с первого этажа, " +
			"но осколки Затмения останутся — тратьте их в Святилище на постоянные усиления."],
		["Управление", "{move_left} / {move_right} — ходьба, {jump} — прыжок (держите — выше), {move_down} — спрыгнуть " +
			"с платформы, {move_up} / {move_down} — лестницы.\n{attack} — атака (держите — атакует сам), прицел — мышью.\n" +
			"{defend} — защита класса.\n{interact} — открыть, подобрать, говорить, обезвредить.\n" +
			"{skill_1}–{skill_8} — навыки, {quick_1}–{quick_7} — быстрые слоты.\n" +
			"{inventory} — рюкзак, {skill_tree} — дерево навыков, {minimap} — карта, Esc — пауза.\n" +
			"Клавиши переназначаются в настройках; геймпад работает всегда."],
		["Бой и защита", "У каждого оружия своя скорость и дальность. Критический удар — двойной урон.\n\n" +
			"{defend}: воин и паладин парируют — удар в окно парирования не проходит, враг оглушён. " +
			"Разбойник делает перекат и неуязвим, пока катится. Маг и некромант защищаются дистанцией и слугами.\n\n" +
			"У монстров есть слабости: огонь, лёд, яд, магия (смотрите в Летописи). Красные зоны на полу — сигнал атаки."],
		["Этажи", "Дверь вниз открывается печатью выхода: убейте нужное число монстров (счётчик слева вверху).\n\n" +
			"Сундуки, тайные стены, алтари судьбы, фонтаны, пленники и записки Летописи разбросаны по этажу. " +
			"Ловушки можно обезвредить ({interact}) — неудача их запускает. Кирпичи можно ломать, руду — добывать.\n\n" +
			"Элиты (с приставкой к имени) сильнее и щедрее. Засада: двери захлопываются, три волны — и алтарь реликвий. " +
			"Стражи сменяют фазы и ненадолго неуязвимы; после каждого — алтарь: одна реликвия из трёх."],
		["Вещи", "{inventory} — книга-инвентарь: перетаскивайте вещи на героя. Правый клик — надеть или использовать.\n\n" +
			"Материалы сами идут в мешок. Ctrl+клик — пометить вещь мусором: торговец купит весь мусор разом, " +
			"кузнец переплавит.\n\nКузнец улучшает и чинит снаряжение, ремесло — во вкладке рюкзака. Неопознанные вещи могут " +
			"оказаться проклятыми. Наборы предметов дают бонус за комплект."],
		["Навыки", "С каждым уровнем — очки характеристик и навыков. {skill_tree} — дерево навыков: три ветви, " +
			"на ярусах 2 и 4 выбор одного из двух.\n\nНавыки тратят ману и стоят на панели внизу; клик по " +
			"слоту — улучшить. Некоторые навыки сильнее с подходящим оружием."],
		["Город", "Между забегами — город Аурелия: торговец, кузнец, квестодатель, Летописец (награды за собранные " +
			"записки) и тренировочный манекен.\n\nСвятилище Затмения: осколки → постоянные усиления и новые классы. " +
			"Летопись: бестиарий, предметы, достижения, история мира."],
		["Кооп", "Игра по сети в локальной сети: один игрок — хост, остальные присоединяются по IP.\n\n" +
			"Монстры сильнее с каждым героем. Лут общий: кто первым подобрал — того и вещь. Павший герой " +
			"наблюдает за остальными и встаёт на следующем этаже. Стрелки по краям экрана ведут к союзникам."],
	]
	return b


static func credits() -> InfoBook:
	var b := InfoBook.new()
	b.title = "Авторы"
	b.chapters = [
		["Игра", "DungeonEclipse — версия %s.\n\nИдея, дизайн и тестирование — команда DungeonEclipse и друзья, " % ProjectSettings.get_setting("application/config/version", "1.0") +
			"прошедшие с нами не один забег.\n\nВся графика, музыка и звуки сгенерированы скриптами проекта (папка tools)."],
		["Движок", "Сделано на Godot Engine (godotengine.org). Шрифт интерфейса — Noto Sans (SIL Open Font License), " +
			"встроен в движок.\n\nСписок всех сторонних компонентов и их лицензий — THIRD_PARTY_LICENSES.md."],
		["Лицензия Godot", Engine.get_license_text().replace("\n\n", "\u0001").replace("\n", " ").replace("\u0001", "\n\n")],
		["Спасибо", "Спасибо всем, кто спускался в подземелье Затмения, находил ошибки и возвращался снова.\n\n" +
			"Да вернётся солнце над Аурелией."],
	]
	return b


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_show(0)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -BOOK_SIZE.x / 2.0
	_root.offset_right = BOOK_SIZE.x / 2.0
	_root.offset_top = -BOOK_SIZE.y / 2.0
	_root.offset_bottom = BOOK_SIZE.y / 2.0
	add_child(_root)
	_root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var margin := 18.0
	var page := Vector2(BOOK_SIZE.x / 2.0 - margin - 10, BOOK_SIZE.y - margin * 2)
	var left := VBoxContainer.new()
	left.position = Vector2(margin + 4, margin)
	left.size = page
	left.add_theme_constant_override("separation", 3)
	_root.add_child(left)
	left.add_child(UIStyle.label(title, 12))
	for i in chapters.size():
		var idx := i
		var b := BookPageScreen.button(chapters[i][0], func() -> void: _show(idx))
		left.add_child(b)
		_buttons.append(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	left.add_child(BookPageScreen.button("Закрыть", close))
	var right := VBoxContainer.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, margin)
	right.size = page
	right.add_theme_constant_override("separation", 4)
	_root.add_child(right)
	_head = UIStyle.label("", 11)
	right.add_child(_head)
	_text = UIStyle.label("", 7)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(page.x - 8, 0)
	var scroll := ScrollContainer.new()  # long chapters (the license) scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_text)
	right.add_child(scroll)
	_scroll = scroll
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()


func _show(i: int) -> void:
	if i < 0 or i >= chapters.size():
		return
	_head.text = chapters[i][0]
	_text.text = _keys(chapters[i][1])
	_text.add_theme_font_size_override("font_size", 6 if _text.text.length() > 700 else 7)
	_scroll.scroll_vertical = 0
	for k in _buttons.size():
		_buttons[k].modulate = Color(1, 0.92, 0.7) if k == i else Color.WHITE


## {action} -> the key currently bound to it.
static func _keys(text: String) -> String:
	for entry in InputBindings.REBINDABLE:
		text = text.replace("{%s}" % entry[0], InputBindings.key_for(entry[0]))
	return text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()

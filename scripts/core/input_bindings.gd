class_name InputBindings
extends RefCounted
## Key rebinding on top of the InputMap. Only keyboard / mouse events are
## rebound; gamepad events from project.godot stay untouched. Overrides are
## stored by SaveManager in [input] of user://settings.cfg as
## action -> Array of {"key": physical_keycode} / {"mouse": button_index}.

## Actions shown in the settings, in order: [action, label].
const REBINDABLE := [
	["move_left", "Влево"], ["move_right", "Вправо"], ["move_up", "Вверх / лезть"],
	["move_down", "Вниз / спуск"], ["jump", "Прыжок"], ["attack", "Атака"],
	["interact", "Взаимодействие"], ["inventory", "Инвентарь"], ["skill_tree", "Дерево навыков"],
	["minimap", "Карта"], ["pause", "Пауза"],
	["skill_1", "Навык 1"], ["skill_2", "Навык 2"], ["skill_3", "Навык 3"], ["skill_4", "Навык 4"],
	["skill_5", "Навык 5"], ["skill_6", "Навык 6"], ["skill_7", "Навык 7"], ["skill_8", "Навык 8"],
	["quick_1", "Предмет 1"], ["quick_2", "Предмет 2"], ["quick_3", "Предмет 3"], ["quick_4", "Предмет 4"],
	["quick_5", "Предмет 5"], ["quick_6", "Предмет 6"], ["quick_7", "Предмет 7"],
]

## action -> keyboard/mouse events from project.godot (captured before overrides).
static var _defaults: Dictionary = {}


static func is_rebindable_event(ev: InputEvent) -> bool:
	return ev is InputEventKey or ev is InputEventMouseButton


static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for entry in REBINDABLE:
		var list: Array = []
		for ev in InputMap.action_get_events(entry[0]):
			if is_rebindable_event(ev):
				list.append(ev)
		_defaults[entry[0]] = list


static func serialize(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"key": k.physical_keycode if k.physical_keycode != 0 else k.keycode}
	if ev is InputEventMouseButton:
		return {"mouse": (ev as InputEventMouseButton).button_index}
	return {}


static func deserialize(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(d["key"])
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d["mouse"])
		return m
	return null


## Replaces the keyboard/mouse events of `action`, keeping gamepad events.
static func set_events(action: String, events: Array) -> void:
	for ev in InputMap.action_get_events(action):
		if is_rebindable_event(ev):
			InputMap.action_erase_event(action, ev)
	for ev in events:
		if ev:
			InputMap.action_add_event(action, ev)


static func keyboard_events(action: String) -> Array:
	return InputMap.action_get_events(action).filter(func(ev: InputEvent) -> bool: return is_rebindable_event(ev))


## Binds `ev` as the main key of `action`; other keyboard keys of the action stay.
## The same key is removed from other actions to avoid conflicts (E/F double use is
## a deliberate default and is only broken up when the player rebinds).
static func rebind(action: String, ev: InputEvent) -> void:
	for entry in REBINDABLE:
		if entry[0] == action:
			continue
		for other in keyboard_events(entry[0]):
			if _same(other, ev):
				InputMap.action_erase_event(entry[0], other)
	var list := keyboard_events(action)
	if list.is_empty():
		list.append(ev)
	else:
		list[0] = ev
	set_events(action, list)


static func reset_all() -> void:
	for action: String in _defaults:
		var copies: Array = []
		for ev: InputEvent in _defaults[action]:
			copies.append(ev.duplicate())
		set_events(action, copies)


static func _same(a: InputEvent, b: InputEvent) -> bool:
	return serialize(a) == serialize(b)


## Overrides of every rebindable action that differs from its default.
static func overrides() -> Dictionary:
	var out := {}
	for entry in REBINDABLE:
		var cur: Array = keyboard_events(entry[0]).map(serialize)
		var def: Array = _defaults.get(entry[0], []).map(serialize)
		if cur != def:
			out[entry[0]] = cur
	return out


static func apply_overrides(data: Dictionary) -> void:
	for action: String in data:
		if InputMap.has_action(action):
			set_events(action, (data[action] as Array).map(deserialize))


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "ЛКМ"
			MOUSE_BUTTON_RIGHT:
				return "ПКМ"
			MOUSE_BUTTON_MIDDLE:
				return "СКМ"
		return "Мышь %d" % (ev as InputEventMouseButton).button_index
	return "?"


## Short label of the main key of `action` (HUD hints, tips).
static func key_for(action: String) -> String:
	var list := keyboard_events(action)
	return event_text(list[0]) if not list.is_empty() else "—"

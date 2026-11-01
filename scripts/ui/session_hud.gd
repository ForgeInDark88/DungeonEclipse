class_name SessionHud
extends CanvasLayer
## The world session on screen (WorldNet keeps it across scenes):
## - the party: nickname, online / offline, ready, the host's crown;
## - the chat and the session log (who came, who left, who fell, what was
##   found): the last lines fade, Enter opens the input;
## - F4: ready for the next expedition; F1: the lobby (the host kicks
##   players and binds new devices to profiles there).

const LINES := 6
const LINE_LIFE := 9.0

var _roster: VBoxContainer
var _log: VBoxContainer
var _input: LineEdit
var _lobby: PanelContainer
var _lines: Array = []  # [Label, time left]


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roster = VBoxContainer.new()
	_roster.position = Vector2(8, 44)
	_roster.add_theme_constant_override("separation", 0)
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roster)
	_log = VBoxContainer.new()
	_log.position = Vector2(8, 200)
	_log.add_theme_constant_override("separation", 0)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	_input = LineEdit.new()
	_input.position = Vector2(8, 300)
	_input.size = Vector2(220, 14)
	_input.max_length = WorldNet.CHAT_MAX
	_input.placeholder_text = tr("Сообщение (Enter — отправить, Esc — закрыть)")
	_input.add_theme_font_size_override("font_size", 7)
	_input.visible = false
	_input.text_submitted.connect(_send)
	_input.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_input.visible = false
			_input.release_focus()
			_input.accept_event())
	add_child(_input)
	WorldNet.roster_changed.connect(_refresh)
	WorldNet.chat_received.connect(_on_chat)
	PlayerProfiles.approval_needed.connect(func(_p: int, _n: String) -> void: _refresh_lobby())
	_refresh()


func _process(delta: float) -> void:
	visible = WorldNet.session
	for entry in _lines.duplicate():
		entry[1] -= delta
		(entry[0] as Label).modulate.a = clampf(entry[1] / 1.5, 0.0, 1.0)
		if entry[1] <= 0.0:
			(entry[0] as Label).queue_free()
			_lines.erase(entry)


func _unhandled_input(e: InputEvent) -> void:
	if not WorldNet.session:
		return
	var key := e as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER and not _input.visible:
		_input.visible = true
		_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F4:
		WorldNet.toggle_ready()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F1:
		_toggle_lobby()
		get_viewport().set_input_as_handled()


func _send(text: String) -> void:
	WorldNet.say(text)
	_input.text = ""
	_input.visible = false
	_input.release_focus()


func _refresh() -> void:
	for c in _roster.get_children():
		c.queue_free()
	for id in WorldNet.roster:
		var r: Dictionary = WorldNet.roster[id]
		var online: bool = r["status"] == "online"
		var mark := ("♛ " if int(id) == 1 else "") + String(r["nick"])
		if not online:
			mark += tr(" (отключён)")
		elif r.get("ready", false):
			mark += " ✓"
		var col := UIStyle.ally_color(int(id)) if online else Color(0.6, 0.6, 0.6)
		_roster.add_child(UIStyle.outlined_label(mark, 7, col))
	_refresh_lobby()


func _on_chat(nick: String, text: String) -> void:
	var l := UIStyle.outlined_label(("%s: %s" % [nick, text]) if nick != "" else "· " + text, 7,
			UIStyle.PARCHMENT if nick != "" else Color(0.75, 0.85, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	_log.add_child(l)
	_lines.append([l, LINE_LIFE])
	while _lines.size() > LINES:
		(_lines[0][0] as Label).queue_free()
		_lines.pop_front()


# ------------------------------------------------------------------ lobby
func _toggle_lobby() -> void:
	if _lobby:
		_lobby.queue_free()
		_lobby = null
		return
	_lobby = PanelContainer.new()
	_lobby.add_theme_stylebox_override("panel", UIStyle.texture_box(AssetPaths.TOOLTIP, 4))
	_lobby.position = Vector2(200, 60)
	_lobby.custom_minimum_size = Vector2(240, 0)
	add_child(_lobby)
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _lobby == null:
		return
	for c in _lobby.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	_lobby.add_child(box)
	box.add_child(UIStyle.label(tr("Лобби: %s") % WorldNet.world_name, 9))
	for id in WorldNet.roster:
		var r: Dictionary = WorldNet.roster[id]
		var row := HBoxContainer.new()
		var l := UIStyle.label("%s · %s%s" % [r["nick"], tr("в игре") if r["status"] == "online" else tr("отключён"),
				tr(" · готов") if r.get("ready", false) else ""], 7)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if Net.is_host and int(id) != 1 and r["status"] == "online":
			var kick := BookPageScreen.button(tr("Исключить"), func() -> void: WorldNet.kick(int(id)))
			kick.add_theme_font_size_override("font_size", 7)
			row.add_child(kick)
		box.add_child(row)
	if Net.is_host:
		for peer in PlayerProfiles.pending:
			var nick := String(PlayerProfiles.pending[peer]["nick"])
			box.add_child(UIStyle.label(tr("Привязать этот клиент к профилю %s?") % nick, 7, Color(0.55, 0.15, 0.1)))
			var row2 := HBoxContainer.new()
			row2.add_child(BookPageScreen.button(tr("Да"), func() -> void:
				PlayerProfiles.approve(peer)
				_refresh_lobby()))
			row2.add_child(BookPageScreen.button(tr("Нет"), func() -> void:
				PlayerProfiles.deny(peer)
				_refresh_lobby()))
			box.add_child(row2)
	var ready := BookPageScreen.button(tr("Готов (F4)"), func() -> void: WorldNet.toggle_ready())
	box.add_child(ready)
	box.add_child(UIStyle.label(tr("Enter — чат · F1 — закрыть"), 6, UIStyle.INK_SOFT))

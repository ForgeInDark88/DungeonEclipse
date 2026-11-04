extends SceneTree
## Adds the rest of the interface skin (tools/art/gen_ui_skin.py,
## assets/ui/skin/) to assets/ui/theme.tres: scroll bars, sliders, check
## boxes and toggles, text and spin fields, drop-downs and pop-up menus,
## lists, progress bars, panels. The buttons and the font stay as they are.
## Idempotent: run again after redrawing the skin.
##   godot --headless -s tools/art/build_theme.gd

const THEME := "res://assets/ui/theme.tres"
const SKIN := "res://assets/ui/skin/"
const INK := Color(0.25, 0.14, 0.08)
const INK_SOFT := Color(0.42, 0.29, 0.18)
const INK_OFF := Color(0.5, 0.42, 0.33)


func tex(n: String) -> Texture2D:
	return load(SKIN + n + ".png")


func box(n: String, margin: int, content := Vector4(-1, -1, -1, -1)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(n)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, margin)
	if content.x >= 0:
		s.content_margin_left = content.x
		s.content_margin_top = content.y
		s.content_margin_right = content.z
		s.content_margin_bottom = content.w
	return s


func _initialize() -> void:
	var t: Theme = load(THEME)
	# panels and pop-ups
	for type in ["Panel", "PanelContainer", "PopupPanel"]:
		t.set_stylebox("panel", type, box("panel", 4, Vector4(6, 5, 6, 5)))
	t.set_stylebox("panel", "PopupMenu", box("popup", 4, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", box("row_hover", 1, Vector4(4, 1, 4, 1)))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", INK_OFF)
	t.set_icon("checked", "PopupMenu", tex("check_on"))
	t.set_icon("unchecked", "PopupMenu", tex("check_off"))
	t.set_icon("radio_checked", "PopupMenu", tex("check_on"))
	t.set_icon("radio_unchecked", "PopupMenu", tex("check_off"))
	# text fields
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, box("field", 3, Vector4(4, 2, 4, 2)))
		t.set_stylebox("focus", type, box("field_focus", 3, Vector4(4, 2, 4, 2)))
		t.set_stylebox("read_only", type, box("field_read_only", 3, Vector4(4, 2, 4, 2)))
		t.set_color("font_color", type, INK)
		t.set_color("font_placeholder_color", type, INK_OFF)
		t.set_color("font_readonly_color", type, INK_SOFT)
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, Color(0.8, 0.62, 0.3, 0.6))
	t.set_icon("updown", "SpinBox", tex("updown"))
	# scroll bars
	for v in [true, false]:
		var type := "VScrollBar" if v else "HScrollBar"
		var k := "v" if v else "h"
		# A StyleBoxTexture's minimum size is its content margins: they make
		# the bar 6 px thick (the textures' width) and the grabber 12 long.
		var bar := Vector4(3, 0, 3, 0) if v else Vector4(0, 3, 0, 3)
		var grab := Vector4(3, 6, 3, 6) if v else Vector4(6, 3, 6, 3)
		t.set_stylebox("scroll", type, box("scroll_" + k, 2, bar))
		t.set_stylebox("scroll_focus", type, box("scroll_" + k, 2, bar))
		t.set_stylebox("grabber", type, box("grab_" + k, 2, grab))
		t.set_stylebox("grabber_highlight", type, box("grab_%s_hover" % k, 2, grab))
		t.set_stylebox("grabber_pressed", type, box("grab_%s_pressed" % k, 2, grab))
		for ic in ["increment", "increment_highlight", "decrement", "decrement_highlight"]:
			t.set_icon(ic, type, ImageTexture.new())  # no arrow buttons
	# sliders
	t.set_stylebox("slider", "HSlider", box("slider", 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area", "HSlider", box("slider_fill", 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box("slider_fill", 3, Vector4(0, 2, 0, 2)))
	t.set_icon("grabber", "HSlider", tex("grabber"))
	t.set_icon("grabber_highlight", "HSlider", tex("grabber_hover"))
	t.set_icon("grabber_disabled", "HSlider", tex("grabber"))
	# check boxes and toggles: no button frame, the box is the icon
	var empty := StyleBoxEmpty.new()
	for type in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type, INK)
		t.set_color("font_disabled_color", type, INK_OFF)
	t.set_icon("checked", "CheckBox", tex("check_on"))
	t.set_icon("unchecked", "CheckBox", tex("check_off"))
	t.set_icon("checked_disabled", "CheckBox", tex("check_on_disabled"))
	t.set_icon("unchecked_disabled", "CheckBox", tex("check_off_disabled"))
	t.set_icon("radio_checked", "CheckBox", tex("check_on"))
	t.set_icon("radio_unchecked", "CheckBox", tex("check_off"))
	t.set_icon("checked", "CheckButton", tex("toggle_on"))
	t.set_icon("unchecked", "CheckButton", tex("toggle_off"))
	t.set_icon("checked_disabled", "CheckButton", tex("toggle_on"))
	t.set_icon("unchecked_disabled", "CheckButton", tex("toggle_off"))
	# drop-downs (the rest comes from Button)
	t.set_icon("arrow", "OptionButton", tex("arrow"))
	# lists
	t.set_stylebox("panel", "ItemList", box("field", 3, Vector4(3, 3, 3, 3)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	for st in ["selected", "selected_focus"]:
		t.set_stylebox(st, "ItemList", box("row_selected", 1))
	t.set_stylebox("hovered", "ItemList", box("row_hover", 1))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	# progress bars
	t.set_stylebox("background", "ProgressBar", box("progress_bg", 3))
	t.set_stylebox("fill", "ProgressBar", box("progress_fill", 1))
	t.set_color("font_color", "ProgressBar", Color(0.96, 0.86, 0.59))
	t.set_color("font_outline_color", "ProgressBar", Color(0.1, 0.06, 0.03))
	var err := ResourceSaver.save(t, THEME)
	print("theme -> %s (%s)" % [THEME, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)

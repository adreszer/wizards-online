class_name KeyChip
extends Label
## A key cap with the key bound to an action (docs/ui.md, "Components"), read from the
## InputMap, so a rebinding shows in every hint; when the last input came from a
## gamepad it shows the pad button instead, drawn as a glyph (a ring for a face button,
## a shoulder tab for a bumper or trigger, a cross for the d-pad, a stick cap), all
## plain shapes with the button's letter, no controller art. `key_text` gives a fixed
## label ("1", "Esc").

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
}
## Keys whose own names are too long for a cap.
const SHORT_KEYS := {KEY_ESCAPE: "Esc", KEY_SPACE: "UI_KEY_SPACE",
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→"}
const PAD_AXES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}
const MOUSE_KEYS := {MOUSE_BUTTON_LEFT: "UI_MOUSE_LEFT", MOUSE_BUTTON_RIGHT: "UI_MOUSE_RIGHT", MOUSE_BUTTON_MIDDLE: "UI_MOUSE_MIDDLE",
	MOUSE_BUTTON_WHEEL_UP: "UI_MOUSE_WHEEL", MOUSE_BUTTON_WHEEL_DOWN: "UI_MOUSE_WHEEL"}

## The glyph drawn round the label: &"" (a key cap from the theme), &"face", &"shoulder",
## &"trigger", &"dpad" or &"stick".
var glyph: StringName = &""

var action: StringName = &"":
	set(value):
		action = value
		refresh()
var key_text := "":
	set(value):
		key_text = value
		refresh()


func _init(for_action: StringName = &"", fixed := "") -> void:
	theme_type_variation = &"KeyChip"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size.x = 26
	action = for_action
	key_text = fixed


func _ready() -> void:
	UiRouter.device_changed.connect(func(_pad: bool) -> void: refresh())
	# Rebinding happens in the settings window; hints catch up when it closes.
	UiRouter.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var g: StringName = &""
	if key_text != "":
		text = key_text
	elif action != &"":
		var pad := is_inside_tree() and UiRouter.using_pad()
		text = label_for(action, pad)
		if pad:
			g = glyph_for(text)
	if g != glyph:
		glyph = g
		# The glyph is drawn here instead of the key cap, and its letter on top of it.
		if glyph != &"":
			add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
			add_theme_color_override(&"font_color", Color.TRANSPARENT)
		else:
			remove_theme_stylebox_override(&"normal")
			remove_theme_color_override(&"font_color")
		custom_minimum_size.x = 26 if glyph == &"" else 30
	queue_redraw()


## What a pad button's label is drawn as (see `glyph`); &"" for a key or mouse name.
static func glyph_for(label: String) -> StringName:
	match label:
		"A", "B", "X", "Y":
			return &"face"
		"LB", "RB":
			return &"shoulder"
		"LT", "RT":
			return &"trigger"
		"↑", "↓", "←", "→":
			return &"dpad"
		"LS", "RS":
			return &"stick"
	return &""


func _draw() -> void:
	if glyph == &"":
		return
	var col := UiTokens.CANDLE
	var line := Color(UiTokens.BRASS_BRIGHT, 0.9)
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 1.0
	match glyph:
		&"face", &"stick":
			draw_circle(c, r, Color(UiTokens.OAK_PRESSED, 0.85), true, -1.0, true)
			draw_arc(c, r, 0.0, TAU, 32, line, 1.5, true)
			if glyph == &"stick":
				draw_arc(c, r - 3.0, 0.0, TAU, 32, Color(line, 0.5), 1.0, true)
		&"shoulder", &"trigger":
			var w := maxf(size.x - 2.0, 28.0)
			var rect := Rect2(c - Vector2(w, size.y - 2.0) / 2.0, Vector2(w, size.y - 2.0))
			var box := StyleBoxFlat.new()
			box.bg_color = Color(UiTokens.OAK_PRESSED, 0.85)
			box.border_color = line
			box.set_border_width_all(1)
			box.anti_aliasing = true
			# A bumper is a flat tab, a trigger rounder at the top.
			var top := 9 if glyph == &"trigger" else 4
			box.corner_radius_top_left = top
			box.corner_radius_top_right = top
			box.corner_radius_bottom_left = 2
			box.corner_radius_bottom_right = 2
			draw_style_box(box, rect)
		&"dpad":
			var a := r * 0.42
			var cross := PackedVector2Array([
				c + Vector2(-a, -r), c + Vector2(a, -r), c + Vector2(a, -a), c + Vector2(r, -a),
				c + Vector2(r, a), c + Vector2(a, a), c + Vector2(a, r), c + Vector2(-a, r),
				c + Vector2(-a, a), c + Vector2(-r, a), c + Vector2(-r, -a), c + Vector2(-a, -a)])
			draw_colored_polygon(cross, Color(UiTokens.OAK_PRESSED, 0.85))
			cross.append(cross[0])
			draw_polyline(cross, Color(line, 0.6), 1.0, true)
	var font := get_theme_font(&"font")
	var fs := get_theme_font_size(&"font_size")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((size.x - w) / 2.0, (size.y - font.get_height(fs)) / 2.0 + font.get_ascent(fs))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A key hint: the chip for `action` and `verb` (translated text) beside it in the
## label style `variation`; the label is the row's second child.
static func hint_row(action: StringName, verb: String, variation: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	var chip := KeyChip.new(action)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var l := Label.new()
	l.text = verb
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


## The name of what triggers `action`: its pad button when `pad`, else its key or mouse
## button; "—" when nothing is bound.
static func label_for(for_action: StringName, pad: bool) -> String:
	if not InputMap.has_action(for_action):
		return "—"
	var events := InputMap.action_get_events(for_action)
	if pad:
		for e in events:
			if e is InputEventJoypadButton and PAD_NAMES.has((e as InputEventJoypadButton).button_index):
				return PAD_NAMES[(e as InputEventJoypadButton).button_index]
			if e is InputEventJoypadMotion and PAD_AXES.has((e as InputEventJoypadMotion).axis):
				return PAD_AXES[(e as InputEventJoypadMotion).axis]
	for e in events:
		if e is InputEventKey:
			var k := e as InputEventKey
			var code: Key = k.keycode
			if k.physical_keycode != 0:
				# The key's letter on this keyboard layout; headless has no layout.
				code = k.physical_keycode if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			if SHORT_KEYS.has(code):
				return TranslationServer.translate(SHORT_KEYS[code])
			return OS.get_keycode_string(code)
		if e is InputEventMouseButton and MOUSE_KEYS.has((e as InputEventMouseButton).button_index):
			return TranslationServer.translate(MOUSE_KEYS[(e as InputEventMouseButton).button_index])
	return "—"

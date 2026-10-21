class_name KeyChip
extends Label
## A key cap with the key bound to an action (docs/ui.md, "Components"), read from the
## InputMap, so a rebinding shows in every hint; when the last input came from a
## gamepad it shows the pad button instead. `key_text` gives a fixed label ("1", "Esc").

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
	if key_text != "":
		text = key_text
	elif action != &"":
		text = label_for(action, is_inside_tree() and UiRouter.using_pad())


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
			var code: Key = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode) if k.physical_keycode != 0 else k.keycode
			if SHORT_KEYS.has(code):
				return TranslationServer.translate(SHORT_KEYS[code])
			return OS.get_keycode_string(code)
		if e is InputEventMouseButton and MOUSE_KEYS.has((e as InputEventMouseButton).button_index):
			return TranslationServer.translate(MOUSE_KEYS[(e as InputEventMouseButton).button_index])
	return "—"

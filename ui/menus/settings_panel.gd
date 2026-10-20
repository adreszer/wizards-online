class_name SettingsPanel
extends FeaturePanel
## Settings (pause menu → Settings, or /settings): graphics with presets, accessibility
## and key bindings (GameSettings). Changes apply at once and are saved.

var _rebinding := ""
var _key_buttons: Dictionary = {}
var _checks: Dictionary = {}
var _preset: OptionButton
var _scale: HSlider
var _ui: HSlider
var _fps: SpinBox


func _ready() -> void:
	half_size = Vector2(380, 300)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "settings":
			open_panel())


func _build() -> void:
	title_label.text = tr("SETTINGS_TITLE")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 480)
	body.add_child(tabs)
	var gfx := VBoxContainer.new()
	gfx.name = tr("SETTINGS_TAB_GRAPHICS")
	tabs.add_child(gfx)
	var row := HBoxContainer.new()
	gfx.add_child(row)
	row.add_child(_row_label("SETTINGS_PRESET"))
	_preset = OptionButton.new()
	for p in GameSettings.PRESETS:
		_preset.add_item(tr("SETTINGS_PRESET_" + p.to_upper()))
	_preset.item_selected.connect(func(i: int) -> void:
		GameSettings.set_preset(GameSettings.PRESETS[i])
		_changed())
	row.add_child(_preset)
	_scale = _slider(gfx, "SETTINGS_RENDER_SCALE", 0.5, 1.0, "render_scale")
	for k in ["fsr", "shadows", "ssao", "ssil", "gi", "glow", "fog", "vsync"]:
		_check(gfx, k)
	var fps_row := HBoxContainer.new()
	gfx.add_child(fps_row)
	fps_row.add_child(_row_label("SETTINGS_FPS_CAP"))
	_fps = SpinBox.new()
	_fps.max_value = 360
	_fps.step = 10
	_fps.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value("fps_cap", int(v))
		_changed())
	fps_row.add_child(_fps)
	var acc := VBoxContainer.new()
	acc.name = tr("SETTINGS_TAB_ACCESS")
	tabs.add_child(acc)
	_ui = _slider(acc, "SETTINGS_UI_SCALE", 0.75, 1.75, "ui_scale")
	for k in ["reduce_motion", "house_symbols", "captions"]:
		_check(acc, k)
	acc.add_child(label(tr("SETTINGS_CLICK_CAST"), 13))
	var keys := VBoxContainer.new()
	keys.name = tr("SETTINGS_TAB_KEYS")
	tabs.add_child(keys)
	for action: String in GameSettings.BINDABLE:
		var r := HBoxContainer.new()
		var l := label(tr("ACTION_" + action.to_upper()), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var b := button("", func() -> void: _start_rebind(action))
		b.custom_minimum_size = Vector2(120, 0)
		r.add_child(b)
		_key_buttons[action] = b
		keys.add_child(r)


func _slider(parent: Node, key: String, lo: float, hi: float, setting: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_row_label(key))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.custom_minimum_size = Vector2(200, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value(setting, v)
		_changed())
	row.add_child(s)
	return s


## The caption in front of a row's control; a fixed width keeps it from being squeezed
## to one letter per line (it word-wraps).
func _row_label(key: String) -> Label:
	var l := label(tr(key), 15)
	l.custom_minimum_size = Vector2(260, 0)
	return l


func _check(parent: Node, setting: String) -> void:
	var c := CheckBox.new()
	c.text = tr("SETTINGS_" + setting.to_upper())
	c.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(setting, on)
		_changed())
	parent.add_child(c)
	_checks[setting] = c


func refresh() -> void:
	_preset.select(maxi(0, GameSettings.PRESETS.find(str(GameSettings.get_value("preset")))))
	_scale.set_value_no_signal(float(GameSettings.get_value("render_scale")))
	_ui.set_value_no_signal(float(GameSettings.get_value("ui_scale")))
	_fps.set_value_no_signal(float(GameSettings.get_value("fps_cap")))
	for k: String in _checks:
		(_checks[k] as CheckBox).set_pressed_no_signal(bool(GameSettings.get_value(k)))
	for action: String in _key_buttons:
		var code := GameSettings.key_of(action)
		(_key_buttons[action] as Button).text = OS.get_keycode_string(code) if code != 0 else "—"


func _changed() -> void:
	GameSettings.apply(get_tree())
	refresh()


func _start_rebind(action: String) -> void:
	_rebinding = action
	(_key_buttons[action] as Button).text = tr("SETTINGS_PRESS_KEY")


func _input(event: InputEvent) -> void:
	if is_open and _rebinding != "" and event is InputEventKey and event.is_pressed():
		var k := event as InputEventKey
		if k.physical_keycode != KEY_ESCAPE:
			GameSettings.bind(_rebinding, k.physical_keycode)
		_rebinding = ""
		refresh()
		get_viewport().set_input_as_handled()

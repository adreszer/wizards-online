class_name SettingsPanel
extends FeaturePanel
## Settings (main menu, pause menu, or /settings): a chrome window with six tabs:
## graphics (a preset, full screen, render scale, the effects, VSync, an FPS cap), audio
## (a volume per bus), controls (look speed, invert, every rebindable key as a key chip
## with Change, and a way back to the defaults), interface (size, the F2 hint),
## accessibility, language and the account (protect the character with an email and
## password; take a protected character to this computer). Changes apply at once and
## are saved (GameSettings).

const FPS_CAPS := [0, 30, 60, 90, 120, 144, 240]
const TABS := ["SETTINGS_TAB_GRAPHICS", "SETTINGS_TAB_AUDIO", "SETTINGS_TAB_KEYS", "SETTINGS_TAB_INTERFACE", "SETTINGS_TAB_ACCESS", "SETTINGS_TAB_LANGUAGE", "SETTINGS_TAB_ACCOUNT"]

var tabs: TabContainer
var _rebinding := ""
var _key_chips: Dictionary = {}
var _change_buttons: Dictionary = {}
var _checks: Dictionary = {}
var _sliders: Dictionary = {}
var _preset: OptionButton
var _fps: OptionButton
var _language: OptionButton
var _account_state: Label
var _account_status: Label
var _email: LineEdit
var _password: LineEdit
var _protect: Button
var _delete: Button


func _ready() -> void:
	half_size = Vector2(470, 320)
	family = UiWindow.Family.CHROME
	scrolls = false
	super()
	card.add_key_hint(&"pause", tr("UI_CLOSE"))
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "settings":
			open_panel())


func _build() -> void:
	title_label.text = tr("SETTINGS_TITLE")
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var pages: Array[VBoxContainer] = []
	for key: String in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tr(key)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var page := UiBox.v(UiTokens.SPACE_2)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll.add_child(page)
		pages.append(page)
	_build_graphics(pages[0])
	_build_audio(pages[1])
	_build_controls(pages[2])
	_build_interface(pages[3])
	_build_access(pages[4])
	_build_language(pages[5])
	_build_account(pages[6])


func _build_graphics(page: VBoxContainer) -> void:
	_preset = OptionButton.new()
	for p: String in GameSettings.PRESETS:
		_preset.add_item(tr("SETTINGS_PRESET_" + p.to_upper()))
	_preset.item_selected.connect(func(i: int) -> void:
		GameSettings.set_preset(GameSettings.PRESETS[i])
		_changed())
	_row(page, "SETTINGS_PRESET", _preset)
	_toggle(page, "fullscreen")
	_slider(page, "SETTINGS_RENDER_SCALE", 0.5, 1.0, "render_scale")
	for k: String in ["fsr", "shadows", "ssao", "ssil", "gi", "glow", "fog", "vsync"]:
		_toggle(page, k)
	_fps = OptionButton.new()
	for cap: int in FPS_CAPS:
		_fps.add_item(tr("SETTINGS_FPS_UNLIMITED") if cap == 0 else str(cap))
	_fps.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("fps_cap", FPS_CAPS[i])
		_changed())
	_row(page, "SETTINGS_FPS_CAP", _fps)


func _build_audio(page: VBoxContainer) -> void:
	for key: String in GameSettings.VOLUMES:
		_slider(page, "SETTINGS_" + key.to_upper(), 0.0, 1.0, key)


func _build_controls(page: VBoxContainer) -> void:
	_slider(page, "SETTINGS_LOOK_SENSITIVITY", 0.25, 2.0, "look_sensitivity")
	_toggle(page, "invert_y")
	page.add_child(_caption("SETTINGS_KEYS_HEADER", &"TitleLabel"))
	for action: String in GameSettings.BINDABLE:
		var chip := KeyChip.new(StringName(action))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var change := Button.new()
		change.text = tr("SETTINGS_CHANGE_KEY")
		change.pressed.connect(_start_rebind.bind(action))
		var right := UiBox.h(UiTokens.SPACE_3, BoxContainer.ALIGNMENT_END)
		right.add_child(chip)
		right.add_child(change)
		_row(page, "ACTION_" + action.to_upper(), right)
		_key_chips[action] = chip
		_change_buttons[action] = change
	var reset := Button.new()
	reset.text = tr("SETTINGS_RESET_KEYS")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(func() -> void:
		GameSettings.reset_bindings()
		status_label.text = tr("SETTINGS_KEYS_RESTORED")
		refresh())
	page.add_child(reset)
	page.add_child(_caption("SETTINGS_CLICK_CAST", &"HintLabel"))


func _build_interface(page: VBoxContainer) -> void:
	_slider(page, "SETTINGS_UI_SCALE", 0.75, 1.75, "ui_scale")
	var hint := KeyChip.hint_row(&"toggle_hud", tr("SETTINGS_HIDE_HUD_HINT"), &"HintLabel")
	page.add_child(hint)


func _build_access(page: VBoxContainer) -> void:
	for k: String in ["reduce_motion", "captions", "house_symbols"]:
		_toggle(page, k)


func _build_language(page: VBoxContainer) -> void:
	_language = OptionButton.new()
	_language.add_item(tr("MENU_LANGUAGE_AUTO"))
	_language.set_item_metadata(0, Localization.AUTO)
	for locale: String in Localization.SUPPORTED:
		_language.add_item(str(Localization.NATIVE_NAMES[locale]))
		_language.set_item_metadata(_language.item_count - 1, locale)
	_language.item_selected.connect(func(i: int) -> void: GameSession.set_language(str(_language.get_item_metadata(i))))
	_row(page, "MENU_LANGUAGE", _language)


func _build_account(page: VBoxContainer) -> void:
	_account_state = _caption("ACCOUNT_UNPROTECTED", &"")
	page.add_child(_account_state)
	page.add_child(_caption("ACCOUNT_HELP", &"HintLabel"))
	_email = LineEdit.new()
	_email.placeholder_text = tr("ACCOUNT_EMAIL_HINT")
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_row(page, "ACCOUNT_EMAIL", _email)
	_password = LineEdit.new()
	_password.secret = true
	_password.placeholder_text = tr("ACCOUNT_PASSWORD_HINT")
	_row(page, "ACCOUNT_PASSWORD", _password)
	var buttons := UiBox.h(UiTokens.SPACE_2)
	_protect = Button.new()
	_protect.text = tr("ACCOUNT_PROTECT")
	_protect.pressed.connect(_on_protect)
	buttons.add_child(_protect)
	var recover := Button.new()
	recover.text = tr("ACCOUNT_RECOVER")
	recover.pressed.connect(_on_recover)
	buttons.add_child(recover)
	page.add_child(buttons)
	_account_status = _caption("", &"HintLabel")
	page.add_child(_account_status)
	_delete = Button.new()
	_delete.text = tr("ACCOUNT_DELETE")
	_delete.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_delete.pressed.connect(_on_delete)
	page.add_child(_delete)


func _refresh_account() -> void:
	if _account_state == null:
		return
	var online := NetworkManager.is_in_world()
	_protect.disabled = not online
	_delete.disabled = not online
	_protect.tooltip_text = "" if online else tr("ACCOUNT_NEEDS_ONLINE")
	var email: String = await NetworkManager.account_email() if online else ""
	if not is_instance_valid(_account_state):
		return
	_account_state.text = tr("ACCOUNT_PROTECTED") % email if not email.is_empty() \
		else tr("ACCOUNT_UNPROTECTED" if online else "ACCOUNT_OFFLINE")


func _on_protect() -> void:
	_account_status.text = tr("ACCOUNT_WORKING")
	var err: String = await NetworkManager.protect_account(_email.text.strip_edges(), _password.text)
	_password.text = ""
	_account_status.text = err if not err.is_empty() else tr("ACCOUNT_PROTECT_DONE")
	_refresh_account()


func _on_delete() -> void:
	var dialog := UiDialog.confirm(self, tr("ACCOUNT_DELETE"), tr("ACCOUNT_DELETE_CONFIRM"), "ACCOUNT_DELETE_YES", "UI_NO")
	if not await dialog.answered:
		return
	_account_status.text = tr("ACCOUNT_WORKING")
	var err: String = await NetworkManager.delete_account()
	_account_status.text = err if not err.is_empty() else tr("ACCOUNT_DELETE_DONE")
	_refresh_account()


func _on_recover() -> void:
	_account_status.text = tr("ACCOUNT_WORKING")
	var err: String = await NetworkManager.recover_account(_email.text.strip_edges(), _password.text)
	_password.text = ""
	_account_status.text = err if not err.is_empty() else tr("ACCOUNT_RECOVER_DONE")
	_refresh_account()


# --- Rows ----------------------------------------------------------------------------------

## A caption on the left and `control` filling the right.
func _row(page: VBoxContainer, key: String, control: Control) -> void:
	var row := UiBox.h(UiTokens.SPACE_4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var caption := _caption(key, &"")
	caption.custom_minimum_size.x = 280
	caption.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	page.add_child(row)


func _caption(key: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A slider with its value as a percentage beside it.
func _slider(page: VBoxContainer, key: String, lo: float, hi: float, setting: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := Label.new()
	value.custom_minimum_size.x = 56
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	s.value_changed.connect(func(v: float) -> void:
		value.text = "%d %%" % roundi(v * 100.0)
		GameSettings.set_value(setting, v)
		_changed())
	var box := UiBox.h(UiTokens.SPACE_3)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(s)
	box.add_child(value)
	_row(page, key, box)
	_sliders[setting] = [s, value]
	return s


## A switch with its caption (SETTINGS_<SETTING>).
func _toggle(page: VBoxContainer, setting: String) -> void:
	var c := CheckButton.new()
	c.text = tr("SETTINGS_" + setting.to_upper())
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(setting, on)
		_changed())
	page.add_child(c)
	_checks[setting] = c


func refresh() -> void:
	_preset.select(maxi(0, GameSettings.PRESETS.find(str(GameSettings.get_value("preset")))))
	_fps.select(maxi(0, FPS_CAPS.find(int(GameSettings.get_value("fps_cap")))))
	for setting: String in _sliders:
		var pair: Array = _sliders[setting]
		var v := float(GameSettings.get_value(setting))
		(pair[0] as HSlider).set_value_no_signal(v)
		(pair[1] as Label).text = "%d %%" % roundi(v * 100.0)
	for k: String in _checks:
		(_checks[k] as CheckButton).set_pressed_no_signal(bool(GameSettings.get_value(k)))
	for action: String in _key_chips:
		(_key_chips[action] as KeyChip).refresh()
		(_change_buttons[action] as Button).text = tr("SETTINGS_PRESS_KEY") if action == _rebinding else tr("SETTINGS_CHANGE_KEY")
	for i in _language.item_count:
		if _language.get_item_metadata(i) == GameSession.language:
			_language.select(i)
	_refresh_account()


func _changed() -> void:
	GameSettings.apply(get_tree())
	refresh()


func _start_rebind(action: String) -> void:
	_rebinding = action
	status_label.text = ""
	refresh()


func _input(event: InputEvent) -> void:
	if is_open and _rebinding != "" and event is InputEventKey and event.is_pressed():
		var k := event as InputEventKey
		if k.physical_keycode != KEY_ESCAPE:
			var swapped := GameSettings.bind(_rebinding, k.physical_keycode)
			if swapped != "":
				status_label.text = tr("SETTINGS_KEY_SWAPPED") % tr("ACTION_" + swapped.to_upper())
		_rebinding = ""
		refresh()
		get_viewport().set_input_as_handled()


## The language changed: build every caption again in the new one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and tabs != null:
		var current := tabs.current_tab
		for child in body.get_children():
			body.remove_child(child)
			child.queue_free()
		_key_chips.clear()
		_change_buttons.clear()
		_checks.clear()
		_sliders.clear()
		_build()
		tabs.current_tab = current
		refresh()

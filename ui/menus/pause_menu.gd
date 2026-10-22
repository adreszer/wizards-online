extends CanvasLayer
## Pause (docs/ui.md, Milestone 68): a chrome window over the blurred, dimmed world
## with resume, settings, return to menu and quit; leaving asks first. Esc opens it when
## no panel is open; while it is open it sits on the UiRouter stack (the HUD fades) and
## Esc resumes.

signal return_to_menu_requested()

const HALF := Vector2(200, 170)

var card: UiWindow
var resume_button: Button
var settings_button: Button
var menu_button: Button
var quit_button: Button
var _root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	card = UiWindow.new(UiWindow.Family.CHROME, false)
	card.centre(HALF)
	card.title_label.text = "PAUSE_TITLE"
	card.close_requested.connect(_set_paused.bind(false))
	_root.add_child(card)
	var buttons := UiBox.v(UiTokens.SPACE_2)
	buttons.mouse_filter = Control.MOUSE_FILTER_PASS
	buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	card.body.add_child(buttons)
	resume_button = _button(buttons, "PAUSE_RESUME", _set_paused.bind(false))
	settings_button = _button(buttons, "SETTINGS_TITLE", func() -> void:
		_set_paused(false)
		GameEvents.panel_requested.emit("settings", {}))
	menu_button = _button(buttons, "PAUSE_RETURN_TO_MENU", _ask.bind("PAUSE_CONFIRM_MENU", func() -> void:
		_set_paused(false)
		return_to_menu_requested.emit()))
	quit_button = _button(buttons, "PAUSE_QUIT", _ask.bind("PAUSE_CONFIRM_QUIT", func() -> void: get_tree().quit()))
	card.add_key_hint(&"pause", tr("PAUSE_RESUME"))


func _button(parent: Control, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(300, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Asks `question` (a translation key) before `then`.
func _ask(question: String, then: Callable) -> void:
	var dialog := UiDialog.confirm(self, tr("PAUSE_TITLE"), tr(question))
	dialog.answered.connect(func(yes: bool) -> void:
		if yes:
			then.call())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not GameSession.ui_input_captured:
		_set_paused(true)
		get_viewport().set_input_as_handled()


## Esc (UiRouter) resumes.
func ui_back() -> void:
	_set_paused(false)


func _set_paused(paused: bool) -> void:
	if paused == _root.visible:
		return
	get_tree().paused = paused
	_root.visible = paused
	UiSounds.play(&"panel_open" if paused else &"back")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if paused:
		card.show_window()
		UiRouter.opened(self)
		resume_button.grab_focus.call_deferred()
	else:
		UiRouter.closed(self)

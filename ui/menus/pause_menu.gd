extends CanvasLayer
## Pause overlay: resume, return to menu, settings, quit. Esc opens it when no panel is
## open; while it is open it sits on the UiRouter stack (the world dims, the HUD steps
## back) and Esc resumes.

signal return_to_menu_requested()

@onready var _root: Control = %Root
@onready var _resume: Button = %ResumeButton
@onready var _menu: Button = %MenuButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume.pressed.connect(_toggle)
	_menu.pressed.connect(func() -> void: _set_paused(false); return_to_menu_requested.emit())
	_quit.pressed.connect(get_tree().quit)
	var settings := Button.new()
	settings.name = "SettingsButton"
	settings.text = tr("SETTINGS_TITLE")
	settings.custom_minimum_size = _resume.custom_minimum_size
	settings.pressed.connect(func() -> void:
		_set_paused(false)
		GameEvents.panel_requested.emit("settings", {}))
	_quit.get_parent().add_child(settings)
	_quit.get_parent().move_child(settings, _quit.get_index())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not GameSession.ui_input_captured:
		_set_paused(true)
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_paused(not get_tree().paused)


## Esc (UiRouter) resumes.
func ui_back() -> void:
	_set_paused(false)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_root.visible = paused
	UiSounds.play(&"panel_open" if paused else &"back")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if paused:
		UiRouter.opened(self)
		_resume.grab_focus()
	else:
		UiRouter.closed(self)

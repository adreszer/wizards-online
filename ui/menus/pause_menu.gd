extends CanvasLayer
## Pause overlay: resume, return to menu, quit.

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not GameSession.ui_input_captured:
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_root.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused:
		_resume.grab_focus()

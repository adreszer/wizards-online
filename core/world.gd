extends Node
## In-game root: level + player spawner + UI layers. Created by Game after the
## menu; frees everything on return.

signal return_to_menu_requested()

@onready var _spawner: PlayerSpawner = $PlayerSpawner
@onready var _level: Node = $Level
@onready var _pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
	_pause_menu.return_to_menu_requested.connect(return_to_menu_requested.emit)
	_spawner.spawn_point = _level.get_node("StartPoint")
	_spawner.spawn_local(GameSession.display_name, NetworkManager.local_user_id)
	GameEvents.level_completed.connect(_on_level_completed)


## F1: free / recapture the mouse without pausing (screenshots, window juggling).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_cursor") and not get_tree().paused and not GameSession.ui_input_captured:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _on_level_completed() -> void:
	GameEvents.notification_requested.emit(tr("NOTIFY_SLICE_COMPLETE") % [
		GameSession.get_collected(&"arcane_fragment"), GameSession.get_total(&"arcane_fragment")], 8.0)

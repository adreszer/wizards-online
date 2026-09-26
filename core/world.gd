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
	var player: Node = _spawner.spawn_local(GameSession.display_name, NetworkManager.local_user_id)
	GameEvents.level_completed.connect(_on_level_completed)
	_show_satchel_hint(player)


## F1: free / recapture the mouse without pausing (screenshots, window juggling).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_cursor") and not get_tree().paused and not GameSession.ui_input_captured:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## First-time nudge toward the torch (the server inventory may arrive a moment
## after the spawn, hence the short delay).
func _show_satchel_hint(player: Node) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(player) or not is_inside_tree():
		return
	var inventory: Inventory = player.inventory
	if inventory.held_item == null and not inventory.is_empty():
		GameEvents.notification_requested.emit(tr("NOTIFY_INVENTORY_HINT"), 8.0)


func _on_level_completed() -> void:
	GameEvents.notification_requested.emit(tr("NOTIFY_SLICE_COMPLETE") % [
		GameSession.get_collected(&"arcane_fragment"), GameSession.get_total(&"arcane_fragment")], 8.0)

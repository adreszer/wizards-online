extends Node
## Game root. Shows the main menu, then swaps in the world scene.
## Handles pause and returning to the menu. Lives at res://core/game.tscn.

@export var world_scene: PackedScene
@export var menu_scene: PackedScene

var _current: Node


func _ready() -> void:
	_show_menu()


func _show_menu() -> void:
	_swap(menu_scene.instantiate())
	_current.start_requested.connect(_on_start_requested)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_start_requested() -> void:
	GameSession.reset_collectibles()
	_swap(world_scene.instantiate())
	_current.return_to_menu_requested.connect(_on_return_to_menu)


func _on_return_to_menu() -> void:
	get_tree().paused = false
	if NetworkManager.is_online():
		await NetworkManager.disconnect_online(tr("NET_LEFT_WORLD"))
	_show_menu()


func _swap(scene: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = scene
	add_child(scene)

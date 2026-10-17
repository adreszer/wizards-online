extends Node
## Game root. Shows the main menu, then swaps in the world scene.
## Handles pause and returning to the menu. Lives at res://core/game.tscn.

@export var world_scene: PackedScene
@export var menu_scene: PackedScene

var _current: Node
## The main theme behind the menu; the world plays its own music.
var menu_music: MusicDirector


func _ready() -> void:
	menu_music = MusicDirector.new()
	menu_music.name = "MenuMusic"
	menu_music.fixed_track = &"main_theme"
	add_child(menu_music)
	_show_menu()


func _show_menu() -> void:
	if menu_music.current.is_empty():
		menu_music.start()
	_swap(menu_scene.instantiate())
	_current.start_requested.connect(_on_start_requested)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_start_requested() -> void:
	GameSession.reset_collectibles()
	menu_music.stop()
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

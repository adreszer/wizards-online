extends Node
## Game root. Shows the main menu, then the loading screen while the world scene is
## built, then the world. Handles pause, returning to the menu and a lost connection
## (a dialog with Retry). Lives at res://core/game.tscn.

@export var world_scene: PackedScene
@export var menu_scene: PackedScene

var _current: Node
## The main theme behind the menu; the world plays its own music.
var menu_music: MusicDirector
var _lost_dialog: UiDialog


func _ready() -> void:
	menu_music = MusicDirector.new()
	menu_music.name = "MenuMusic"
	menu_music.fixed_track = &"main_theme"
	add_child(menu_music)
	NetworkManager.status_changed.connect(_on_status_changed)
	_show_menu()


func _show_menu() -> void:
	if menu_music.current.is_empty():
		menu_music.start()
	_swap(menu_scene.instantiate())
	_current.start_requested.connect(_on_start_requested)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_start_requested() -> void:
	GameSession.reset_collectibles()
	var loading := LoadingScreen.new()
	add_child(loading)
	# The world builds in one blocking step: draw the loading screen first.
	for i in 3:
		await get_tree().process_frame
	menu_music.stop()
	_swap(world_scene.instantiate())
	_current.return_to_menu_requested.connect(_on_return_to_menu)
	for i in 20:
		await get_tree().process_frame
	loading.finish()


## The connection dropped in the castle and could not come back by itself: say so and
## offer Retry; Close keeps playing offline.
func _on_status_changed(status: int, message: String) -> void:
	if status != NetworkManager.Status.ERROR or GameSession.play_mode != GameSession.PlayMode.ONLINE:
		return
	if _current == null or not _current.has_signal("return_to_menu_requested") or is_instance_valid(_lost_dialog):
		return
	_lost_dialog = UiDialog.error(self, tr("NET_LOST_TITLE"), message)
	_lost_dialog.answered.connect(func(retry: bool) -> void:
		if retry:
			NetworkManager.connect_online(GameSession.display_name))


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

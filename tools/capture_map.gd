extends Node
## Dev tool: runs the real World (offline), then saves PNGs of the minimap and
## of the full map on several storeys and zoom levels (needs a window; not --headless).
##   godot --path . tools/capture_map.tscn -- --out=/absolute/dir

const WORLD := preload("res://core/world.tscn")

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(60)
	_save("01_minimap_outdoors")
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	player.global_position = Vector3(0, 0.2, 36)
	await _frames(90)
	_save("02_minimap_entrance_hall")
	var panel: MapPanel = world.get_node("MapPanel")
	panel.open()
	await _frames(10)
	_save("03_map_ground_floor")
	panel.change_storey(1)
	await _frames(5)
	_save("04_map_first_floor")
	panel.change_storey(-2)
	await _frames(5)
	_save("05_map_dungeons")
	panel.change_storey(1)
	var view: MapView = panel.get_node("%View")
	panel.zoom_at(0.15, view.size * 0.5)
	await _frames(5)
	_save("06_map_grounds")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

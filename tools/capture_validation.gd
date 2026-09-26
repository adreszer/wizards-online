extends Node
## Dev tool: renders the asset validation scene from fixed viewpoints and
## saves PNGs (needs a window; not --headless).
##   godot --path . tools/capture_validation.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")

## name, camera position, look-at target
const VIEWS := [
	["01_overview", Vector3(8, 7, -16), Vector3(6, 2, 0)],
	["02_single_wall_front", Vector3(-6, 2.2, -6.5), Vector3(-6, 2, 0)],
	["03_tiled_front", Vector3(6, 2.2, -9), Vector3(6, 2, 0)],
	["04_tiled_seam_close", Vector3(4, 2, -1.6), Vector3(4, 2, 0)],
	["05_tiled_grazing", Vector3(-1.5, 2.2, -1.2), Vector3(10, 2, 0)],
	["06_tiled_top_edge", Vector3(6, 6, -4), Vector3(6, 3.8, 0)],
	["07_tiled_back", Vector3(6, 2.2, 7), Vector3(6, 2, 0)],
	["08_corner_outer", Vector3(25, 3, -6), Vector3(20, 2, 0.5)],
	["09_corner_inner", Vector3(15, 2.5, 5.5), Vector3(19.5, 2, 0.5)],
	["10_corner_top", Vector3(23, 8, -3), Vector3(20, 3, 1)],
	["11_wall_end_cap", Vector3(-3, 2, -1.2), Vector3(-4, 2, 0)],
	["12_player_beside_wall", Vector3(1.5, 1.6, -5), Vector3(4, 1.4, -0.3)],
]

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var level := SCENE.instantiate()
	add_child(level)
	# Let the player spawn, then stand it beside the tiled wall for view 12.
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player != null:
		player.global_position = Vector3(4, 0.05, -1.0)
		player.rotation.y = 0.0
	await _frames(10)
	# The player's own third-person view first (what the user sees on launch).
	await _frames(30)
	_save("00_player_camera")
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	for view in VIEWS:
		cam.global_position = view[1]
		cam.look_at(view[2], Vector3.UP)
		await _frames(12)
		_save(view[0])
	print("Saved %d captures to %s" % [VIEWS.size() + 1, _out])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		push_error("Could not save %s (%d)" % [path, err])

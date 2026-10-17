extends Node
## Dev tool: both bodies in every house's trim, skin tone and robe colour, from the
## front (needs a window; not --headless).
##   godot --path . tools/capture_looks.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")
## name, look, house
const SHOTS := [
	["unsorted", {"skin": 0, "robe": 0}, 0],
	["house1", {"skin": 0, "robe": 0}, 1], ["house2", {"skin": 1, "robe": 0}, 2],
	["house3", {"skin": 2, "robe": 0}, 3], ["house4", {"skin": 3, "robe": 0}, 4],
	["skin5_black", {"skin": 4, "robe": 1}, 1], ["brown", {"skin": 1, "robe": 2}, 2],
	["navy", {"skin": 0, "robe": 3}, 3], ["moss", {"skin": 2, "robe": 4}, 4],
]

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var level := SCENE.instantiate()
	add_child(level)
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Player
	player.global_position = Vector3(4, 0.05, -3.0)
	player.rotation.y = 0.0
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	for body in ["apprentice_m", "apprentice_f"]:
		player.set_look({"body": body, "skin": 0, "robe": 0, "set": true})
		await _frames(10)
		for shot in SHOTS:
			var look: Dictionary = shot[1].duplicate()
			look["body"] = body
			player.house = shot[2]
			player.set_look(look)
			cam.global_position = player.global_position + Vector3(0.0, 1.35, -2.6)
			cam.look_at(player.global_position + Vector3(0, 1.0, 0), Vector3.UP)
			await _frames(4)
			_save("%s_%s" % [body, shot[0]])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out.path_join(file_name + ".png"))

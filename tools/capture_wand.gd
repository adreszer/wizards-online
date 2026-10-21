extends Node
## Dev tool: close-ups of the wand in the player's hand, idle and mid-cast, from three
## sides, for both bodies (needs a window; not --headless).
##   godot --path . tools/capture_wand.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")
const BODIES := ["apprentice_m", "apprentice_f"]
## name, camera direction from the hand in the player's frame (player faces -Z)
const VIEWS := [["front", Vector3(-0.3, 0.15, -1.0)], ["side", Vector3(-1.0, 0.2, -0.1)], ["shoulder", Vector3(0.9, 1.0, 2.4)]]
## state, seconds into the cast (-1 = idle)
const SHOTS := [["idle", -1.0], ["cast", 0.3]]

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
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Player
	player.global_position = Vector3(4, 0.05, -3.0)
	player.rotation.y = 0.0
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.02
	add_child(cam)
	cam.current = true
	for body: String in BODIES:
		var look := player.look.duplicate()
		look.body = body
		player.set_look(look)
		await _frames(20)
		var wand := player.visual.find_child("Wand", true, false) as Node3D
		var anim := player.animation_controller
		for shot in SHOTS:
			if float(shot[1]) >= 0.0 and anim != null:
				anim.play_cast()
				await get_tree().create_timer(float(shot[1])).timeout
			else:
				await get_tree().create_timer(1.0).timeout
			for view in VIEWS:
				# Aim at the palm: the hand bone runs from the wrist along the fingers (+Y).
				var hand := wand.global_transform * Vector3(0, 0.08, 0)
				cam.global_position = hand + player.global_basis * (view[1] as Vector3).normalized() * (1.1 if view[0] != "shoulder" else 2.6)
				cam.look_at(hand, Vector3.UP)
				await _frames(2)
				_save("%s_%s_%s" % [body, shot[0], view[0]])
			await get_tree().create_timer(1.0).timeout
	print("Saved captures to %s" % _out)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

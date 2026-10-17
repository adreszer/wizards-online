extends Node
## Dev tool: the player's social gestures and sitting on a bench and a chair, from
## the front and the side (needs a window; not --headless).
##   godot --path . tools/capture_gestures.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")
const BENCH := "res://objects/environment/props/student_bench.tscn"
const CHAIR := "res://objects/environment/placeholders/chair.tscn"
## name, camera offset from the player (player faces -Z), look-at height
const VIEWS := [
	["front", Vector3(0.6, 1.4, -3.0), 1.0],
	["side", Vector3(-3.0, 1.3, -0.3), 0.9],
]
## gesture, seconds into it when captured
const SHOTS := [["raise_hand", 1.0], ["wave", 0.9], ["bow", 0.8], ["clap", 0.7], ["point", 1.0],
	["shrug", 0.8], ["cheer", 0.7], ["notes", 1.0]]

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
	cam.fov = 45.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	await _frames(20)
	for shot in SHOTS:
		player.gestures.play(StringName(shot[0]))
		await get_tree().create_timer(float(shot[1])).timeout
		for view in VIEWS:
			_frame_camera(cam, player, view)
			await _frames(2)
			_save("%s_%s" % [shot[0], view[0]])
		player.gestures.stop()
		await get_tree().create_timer(0.6).timeout
	# Seats: a bench and a chair placed beside the player.
	for seat_kind in [[BENCH, "bench"], [CHAIR, "chair"]]:
		var prop: Node3D = (load(seat_kind[0]) as PackedScene).instantiate()
		var xform := Transform3D(Basis(Vector3.UP, 0.4), Vector3(9, 0, -9.5))
		level.add_child(prop)
		prop.global_transform = xform
		await _frames(5)
		player.global_position = Vector3(9, 0.05, -7.5)
		await _frames(3)
		var seat := Seats.facing_from(Seats.for_instance(seat_kind[0], xform)[0], player.global_position)
		player.gestures.sit_at(seat)
		await get_tree().create_timer(0.8).timeout
		for view in VIEWS:
			var offset: Vector3 = seat.basis * Vector3(view[1].x, view[1].y, view[1].z)
			cam.global_position = player.global_position + offset
			cam.look_at(player.global_position + Vector3(0, view[2] * 0.7, 0), Vector3.UP)
			await _frames(3)
			_save("sit_%s_%s" % [seat_kind[1], view[0]])
		player.gestures.stand()
		prop.queue_free()
		await _frames(5)
	print("Saved captures to %s" % _out)
	get_tree().quit(0)


func _frame_camera(cam: Camera3D, player: Node3D, view: Array) -> void:
	cam.global_position = player.global_position + player.global_basis * (view[1] as Vector3)
	cam.look_at(player.global_position + Vector3(0, view[2], 0), Vector3.UP)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

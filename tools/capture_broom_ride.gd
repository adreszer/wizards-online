extends Node
## Dev tool: seats the player on a broom in the asset validation scene and
## saves PNGs of the riding pose (hover, cruise, boost) from a few angles
## (needs a window; not --headless).
##   godot --path . tools/capture_broom_ride.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")

## name, camera offset from the player (player faces -Z), look-at height
const VIEWS := [
	["side", Vector3(-2.6, 1.0, 0.0), 0.9],
	["front", Vector3(-1.2, 1.3, -2.4), 0.9],
	["behind", Vector3(0.5, 1.7, 2.8), 1.0],
]
## name, speed, climb, turn
const STATES := [
	["hover", 0.0, 0.0, 0.0],
	["cruise", 0.47, 0.0, 0.0],
	["boost", 1.0, 0.0, 0.0],
	["turn", 0.6, 0.0, 0.8],
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
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player == null:
		push_error("No local player spawned")
		get_tree().quit(1)
		return
	player.global_position = Vector3(4, 0.05, -3.0)
	player.rotation.y = 0.0
	var inv: Inventory = player.get("inventory")
	inv.add(ItemRegistry.load_definition("broom"), 1)
	var rider: BroomRider = player.get("broom_rider")
	rider.toggle()
	await _frames(10)
	# Hold the body still in the air and drive the pose by hand.
	player.get("movement").set_physics_process(false)
	player.global_position = Vector3(4, 0.6, -3.0)
	rider.set_process(false)
	rider.pose = Transform3D.IDENTITY
	var ride := rider.ride_pose
	ride.active = true
	ride.influence = 1.0
	ride.mount = rider.mount_node
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	for state in STATES:
		ride.speed = state[1]
		ride.climb = state[2]
		ride.turn = state[3]
		for view in VIEWS:
			cam.global_position = player.global_position + view[1]
			cam.look_at(player.global_position + Vector3(0, view[2], 0), Vector3.UP)
			await _frames(12)
			_save("%s_%s" % [state[0], view[0]])
	print("Saved captures to %s" % _out)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))

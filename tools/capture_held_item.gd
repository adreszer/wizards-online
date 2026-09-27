extends Node
## Dev tool: spawns the player in the asset validation scene holding an item
## and saves close-up PNGs of it from a few angles (needs a window; not
## --headless).
##   godot --path . tools/capture_held_item.tscn -- --out=/absolute/dir [--item=torch]

const SCENE := preload("res://levels/dev/asset_validation.tscn")

## name, camera offset from the player (player faces -Z), look-at height
const VIEWS := [
	["01_front", Vector3(0.0, 1.4, -2.2), 1.1],
	["02_left_side", Vector3(-2.0, 1.3, -0.6), 1.1],
	["03_closeup", Vector3(-0.9, 1.35, -1.0), 1.05],
	["04_behind", Vector3(0.6, 1.6, 2.2), 1.1],
]

var _out: String = "user://captures"
var _item: String = "torch"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--item="):
			_item = arg.trim_prefix("--item=")
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
	if inv != null and not inv.hold_id(_item):
		inv.add(ItemRegistry.load_definition(_item), 1)
		inv.hold_id(_item)
	await _frames(40)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	for view in VIEWS:
		cam.global_position = player.global_position + view[1]
		cam.look_at(player.global_position + Vector3(0, view[2], 0), Vector3.UP)
		await _frames(30)
		_save(view[0])
	print("Saved %d captures to %s" % [VIEWS.size(), _out])
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

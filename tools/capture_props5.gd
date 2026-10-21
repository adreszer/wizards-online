extends Node
## Dev tool: each of the fifth props batch's scenes alone in the validation room, framed
## from three quarters (needs a window; not --headless). Also a dorm corner with every
## shelf decoration and a feast place setting.
##   godot --path . tools/capture_props5.tscn -- --out=/absolute/dir [--only=lever,plaque]

const SCENE := preload("res://levels/dev/asset_validation.tscn")
const PROPS := {
	"pressure_plate": "res://objects/puzzles/pressure_plate.tscn",
	"pushable_block": "res://objects/puzzles/pushable_block.tscn",
	"plaque": "res://objects/interactables/plaque.tscn",
	"goal_ring": "res://objects/environment/grounds/goal_ring.tscn",
	"practice_target": "res://objects/school/practice_target.tscn",
	"sorting_stone": "res://objects/school/sorting_stone.tscn",
	"lever": "res://objects/interactables/lever.tscn",
	"spell_tome": "res://objects/interactables/spell_tome.tscn",
	"lore_book": "res://objects/interactables/lore_book.tscn",
	"secret_wall": "res://objects/puzzles/secret_wall.tscn",
	"magic_door": "res://objects/puzzles/magic_door.tscn",
	"held_torch": "res://objects/items/held_torch.tscn",
	"lantern_post": "res://objects/environment/grounds/lantern_post.tscn",
	"checkpoint": "res://gameplay/checkpoints/checkpoint.tscn",
	"collectible": "res://gameplay/collectibles/collectible.tscn",
	"broom": "res://objects/items/broom.tscn",
	"house_tally": "res://objects/school/house_tally.tscn",
	"house_cup": "res://assets/models/school/house_cup.glb",
	"shop_counter": "res://assets/models/environment/props5/shop_counter.glb",
}
const SPOT := Vector3(4, 0.05, 1.0)

var _out: String = "user://captures"
var _only: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var level := SCENE.instantiate()
	add_child(level)
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	player.global_position = Vector3(-6, 0.05, 6)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	add_child(cam)
	cam.current = true
	for key: String in PROPS:
		if not _only.is_empty() and not _only.has(key):
			continue
		var node := (load(PROPS[key]) as PackedScene).instantiate() as Node3D
		level.add_child(node)
		node.global_position = SPOT
		# Face the open room (+Z): most props face -Z, plaques and walls face +Z already.
		node.rotation.y = 0.0 if key in ["plaque", "secret_wall"] else PI
		await _frames(10)
		_frame(cam, node)
		await _frames(3)
		_save(key)
		node.queue_free()
		await _frames(2)
	if _only.is_empty() or _only.has("dorm"):
		var corner := DormitoryCorners.build_corner(Transform3D(Basis(Vector3.UP, PI), SPOT + Vector3(0, 0, -0.5)), "Ola",
			["brass_lantern", "potted_moonpetal", "music_box"], 2)
		level.add_child(corner)
		var corner2 := DormitoryCorners.build_corner(Transform3D(Basis(Vector3.UP, PI), SPOT + Vector3(2.2, 0, -0.5)), "Ewa",
			["trophy_small", "game_set", "pennant"], 3)
		level.add_child(corner2)
		await _frames(10)
		cam.global_position = SPOT + Vector3(1.1, 2.3, 2.2)
		cam.look_at(SPOT + Vector3(1.1, 2.1, -0.5), Vector3.UP)
		await _frames(3)
		_save("dorm")
		corner.queue_free()
		corner2.queue_free()
	if _only.is_empty() or _only.has("feast"):
		var x := -0.6
		for dish in ["feast_plate", "feast_goblet", "feast_platter", "feast_bread", "feast_fruit"]:
			var d := (load("res://assets/models/feast/%s.glb" % dish) as PackedScene).instantiate() as Node3D
			level.add_child(d)
			d.global_position = SPOT + Vector3(x, 0, 0)
			x += 0.32
		await _frames(10)
		cam.global_position = SPOT + Vector3(0, 0.7, 1.0)
		cam.look_at(SPOT + Vector3(0, 0.03, 0), Vector3.UP)
		await _frames(3)
		_save("feast")
	print("Saved captures to %s" % _out)
	get_tree().quit(0)


## Three-quarter view framing the node's visible bounds.
func _frame(cam: Camera3D, node: Node3D) -> void:
	var box := AABB(node.global_position, Vector3.ZERO)
	for v in node.find_children("*", "VisualInstance3D", true, false):
		if v is GPUParticles3D or v is CPUParticles3D or v is Light3D:
			continue
		box = box.merge((v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb())
	var centre := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.15)
	var dir := Vector3(0.55, 0.35, 0.75).normalized()
	cam.global_position = centre + dir * radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.1
	cam.look_at(centre, Vector3.UP)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

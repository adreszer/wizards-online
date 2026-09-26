extends Node
## Headless check for the wall_plain wrapper: final world-space dimensions,
## pivot, collision box, and that the player cannot walk through it.
##   godot --headless --path . tests/validate_wall_plain.tscn

const WALL := preload("res://objects/environment/modular/wall_plain.tscn")
const PLAYER := preload("res://characters/player/player.tscn")
const TestHelpers := preload("res://tests/test_helpers.gd")

var t := TestHelpers.new()


func _ready() -> void:
	await _run()


func _run() -> void:
	t.section("wrapper dimensions")
	var wall := WALL.instantiate() as StaticBody3D
	add_child(wall)
	await get_tree().process_frame
	var aabb := _visual_aabb(wall)
	print("  visual AABB position %s size %s" % [aabb.position, aabb.size])
	t.check(absf(aabb.size.x - 4.0) < 0.001, "width 4.0 m (got %.4f)" % aabb.size.x)
	t.check(absf(aabb.size.y - 4.0) < 0.001, "height 4.0 m (got %.4f)" % aabb.size.y)
	t.check(absf(aabb.size.z - 0.35) < 0.001, "depth 0.35 m (got %.4f)" % aabb.size.z)
	t.check(absf(aabb.position.y) < 0.001, "bottom at y = 0 (got %.4f)" % aabb.position.y)
	t.check(absf(aabb.get_center().x) < 0.001 and absf(aabb.get_center().z) < 0.001,
		"centred on x/z (centre %s)" % aabb.get_center())
	var shape := (wall.get_node("Shape") as CollisionShape3D)
	var box := shape.shape as BoxShape3D
	t.check(box != null and box.size == Vector3(4, 4, 0.35), "collision is a 4 x 4 x 0.35 box")
	t.check(shape.position == Vector3(0, 2, 0), "collision box centred on the wall")
	t.check(wall.collision_layer == 1, "on physics layer 1 (world)")
	wall.queue_free()

	t.section("player cannot walk through")
	TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var w2 := WALL.instantiate() as StaticBody3D
	add_child(w2)
	w2.global_position = Vector3(0, 0, 0)
	var player := PLAYER.instantiate()
	player.is_local = true
	add_child(player)
	player.global_position = Vector3(0, 0.05, -3)
	await _wait(0.3)
	var movement: PlayerMovement = player.movement
	# Walk toward +Z into the wall for 2 seconds.
	_drive(movement, Vector3(0, 0, 1))
	await _wait(2.0)
	var z: float = player.global_position.z
	print("  player z after walking into wall: %.3f" % z)
	t.check(z < -0.175 - 0.3, "player stopped in front of the wall (z=%.3f, wall front at -0.175)" % z)
	t.check(z > -1.0, "player actually reached the wall (z=%.3f)" % z)
	# Walk sideways around the wall end: should be free.
	player.global_position = Vector3(3, 0.05, -1)
	_drive(movement, Vector3(0, 0, 1))
	await _wait(1.5)
	t.check(player.global_position.z > 1.0, "player walks freely past the wall end (z=%.3f)" % player.global_position.z)
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)


func _drive(movement: PlayerMovement, dir: Vector3) -> void:
	movement.set_external_move(dir, false)


func _wait(seconds: float) -> void:
	for i in range(int(ceil(seconds * Engine.physics_ticks_per_second))):
		await get_tree().physics_frame


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var box := mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var res: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		res.append(node)
	for c in node.get_children():
		res.append_array(_meshes(c))
	return res

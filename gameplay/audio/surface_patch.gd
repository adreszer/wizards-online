class_name SurfacePatch
extends Node3D
## A footprint that sets what footsteps sound like inside it, whatever the floor
## collider below: a rug (carpet) on a stone floor, a wooden stage or stair flight,
## an iron grate. A box of `size` centred on this node (rotated with it); the
## player's feet must be inside it. Drop one into a prop's wrapper scene or a room.
## Read by PlayerSounds.surface_at; the smallest patch holding the point wins.

const GROUP := &"surface_patches"

## One of PlayerSounds.SURFACES.
@export var surface: StringName = &"carpet"
@export var size: Vector3 = Vector3(2, 0.5, 2)


func _enter_tree() -> void:
	add_to_group(GROUP)


func contains(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	var half := size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


## The surface of the smallest patch holding `point`, or &"" when none does.
static func at(tree: SceneTree, point: Vector3) -> StringName:
	var best: SurfacePatch = null
	var best_volume := INF
	for node: Node in tree.get_nodes_in_group(GROUP):
		var patch := node as SurfacePatch
		if patch == null or not patch.is_inside_tree() or not patch.contains(point):
			continue
		var volume := patch.size.x * patch.size.y * patch.size.z
		if volume < best_volume:
			best = patch
			best_volume = volume
	return best.surface if best != null else &""

class_name Seats
extends RefCounted
## Where characters can sit. Benches, chairs, armchairs and sofas are batched into
## MultiMeshes (StaticBatch), so they have no nodes to interact with; instead the
## batch records a seat transform for every seat of every such instance it takes,
## and the player sits at the nearest free one (interact with nothing else in
## focus, or /sit). A seat transform has its origin on the seat surface and faces
## its -Z, the way the sitter looks.

## Scene path → seats of one instance: [x, surface height, z, yaw in degrees, both ways]
## in the scene's own frame. A bench has no back, so its seats work both ways: the
## sitter faces away from the side they came from (toward the desk in a classroom,
## toward the table at a feast). The placeholder chairs and sofas face +Z (their
## origin is the back, like every wall prop).
const BY_SCENE := {
	"res://objects/environment/props/student_bench.tscn": [[-0.45, 0.54, 0.0, 0.0, true], [0.45, 0.54, 0.0, 0.0, true]],
	"res://objects/environment/placeholders/chair.tscn": [[0.0, 0.48, 0.27, 180.0]],
	"res://objects/environment/placeholders/armchair.tscn": [[0.0, 0.45, 0.5, 180.0]],
	"res://objects/environment/placeholders/sofa.tscn": [[-0.5, 0.45, 0.5, 180.0], [0.5, 0.45, 0.5, 180.0]],
}
## How close (metres, feet to seat) a seat must be to sit on it.
const REACH := 1.8
## A seat with someone this close to it is taken.
const TAKEN_RADIUS := 0.35


## The seats of one instance of `scene_path` placed at `xform` (global):
## [{t: Transform3D, both: sits either way}].
static func for_instance(scene_path: String, xform: Transform3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Array in BY_SCENE.get(scene_path, []):
		var local := Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[3]))), Vector3(float(s[0]), float(s[1]), float(s[2])))
		out.append({"t": xform * local, "both": s.size() > 4 and s[4] == true})
	return out


## Every seat in the tree (all batches).
static func all(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for batch in tree.get_nodes_in_group(StaticBatch.GROUP):
		out.append_array((batch as StaticBatch).seats)
	return out


## `seat` turned for someone standing at `pos`: a two-way seat faces away from them.
static func facing_from(seat: Dictionary, pos: Vector3) -> Transform3D:
	var t: Transform3D = seat.t
	if seat.get("both", false):
		var facing := -t.basis.z
		if facing.dot(t.origin - pos) < 0.0:
			t.basis = t.basis.rotated(Vector3.UP, PI)
	return t


## The nearest free seat within REACH of `pos`, turned for someone standing there
## (a Transform3D), or null. `others` are positions of other characters (a seat next
## to one is taken).
static func nearest_free(tree: SceneTree, pos: Vector3, others: Array[Vector3] = []) -> Variant:
	var best: Variant = null
	var best_d := REACH
	for entry in all(tree):
		var s: Transform3D = entry.t
		var flat := Vector2(s.origin.x - pos.x, s.origin.z - pos.z).length()
		if flat >= best_d or absf(s.origin.y - pos.y) > 1.2:
			continue
		var taken := false
		for o in others:
			if Vector2(s.origin.x - o.x, s.origin.z - o.z).length() < TAKEN_RADIUS:
				taken = true
				break
		if not taken:
			best = facing_from(entry, pos)
			best_d = flat
	return best

class_name StaticBatch
extends Node3D
## Draws the castle's repeated static modules (wall stones, floor and ceiling tiles,
## pillars, doorway arches, furniture) as MultiMeshes, one per mesh per material per
## [member cell_size] cell per storey, with one compound StaticBody3D of their
## collision shapes per cell. Nothing about authoring changes: ModularWallRun and
## ModularFloor ask the castle's batch to take a module instead of instancing it, and
## direct instances of batchable scenes (pillars, furniture) are folded in on flush.
## Each module scene is read once (StaticBatch.prototype), so a castle of tens of
## thousands of modules costs a few hundred nodes.
##
## Only plain static scenes may be batched: no scripts, no interaction, no per-instance
## shader uniforms (wall windows and doors stay ordinary nodes).

const BATCHABLE := [
	"res://objects/environment/modular/wall_plain.tscn",
	"res://objects/environment/modular/floor_tile.tscn",
	"res://objects/environment/modular/floor_tile_2.tscn",
	"res://objects/environment/modular/ceiling_tile.tscn",
	"res://objects/environment/modular/pillar.tscn",
	"res://objects/environment/modular/doorway.tscn",
	"res://objects/environment/props/student_desk.tscn",
	"res://objects/environment/props/student_bench.tscn",
	"res://objects/environment/props/lectern.tscn",
	"res://objects/environment/props/professor_desk.tscn",
	"res://objects/environment/props/slate_board.tscn",
	"res://objects/environment/props/wall_board.tscn",
	"res://objects/environment/props/bookshelf_large.tscn",
	"res://objects/environment/props/feast_table.tscn",
	"res://objects/environment/props/bed.tscn",
	"res://objects/environment/props/hearth.tscn",
	"res://objects/environment/props/armchair.tscn",
	"res://objects/environment/props/sofa.tscn",
	"res://objects/environment/props/globe.tscn",
	"res://objects/environment/props/cauldron.tscn",
	"res://objects/environment/props/table.tscn",
	"res://objects/environment/props/chair.tscn",
	"res://objects/environment/props/candelabra.tscn",
	"res://objects/environment/props/cabinet.tscn",
	"res://objects/environment/props/barrel.tscn",
	"res://objects/environment/props/crate.tscn",
	"res://objects/environment/props/trunk.tscn",
	"res://objects/environment/props/chest.tscn",
	"res://objects/environment/props/plant_pot.tscn",
	"res://objects/environment/props/statue.tscn",
	"res://objects/environment/props/armour.tscn",
	"res://objects/environment/props/telescope.tscn",
]
## Group of every batch (Seats looks through them).
const GROUP := &"static_batch"
## Containers whose direct batchable instances are folded in on flush.
const CONTAINERS := ["Pillars", "Furniture"]

@export var cell_size: float = 8.0
@export var storey_height: float = 9.0
## Batched meshes are drawn up to this distance (the castle's far view takes over).
@export var visibility_end: float = 170.0

## Dev switch (tools/perf_castle.gd --no-batch): instance modules as plain nodes instead.
static var disabled := false
static var _prototypes: Dictionary = {}   # scene path -> {meshes: [[Mesh, Transform3D, Material]], shapes: [[Shape3D, Transform3D]]}

var _meshes: Dictionary = {}    # [cell, mesh, material] key -> {mesh, material, cell, xforms: Array[Transform3D]}
var _shapes: Dictionary = {}    # cell -> Array of [Shape3D, Transform3D]
var _flushed := false
var instance_count := 0
## Seats of the benches, chairs and sofas taken in ([{t, both}], see Seats).
var seats: Array[Dictionary] = []
## Where every wall board hangs (global transforms), for ClassroomBoards' writing.
var boards: Array[Transform3D] = []
## Where every feast table stands (global transforms), for FeastMeals.
var feast_tables: Array[Transform3D] = []
## Where every portrait hangs, for TalkingPortraits.
var portraits: Array[Transform3D] = []
## Where every bed stands, for DormitoryCorners.
var beds: Array[Transform3D] = []


func _enter_tree() -> void:
	add_to_group(GROUP)


## The batch that serves `node` (its castle's), or null when there is none (the editor,
## test fixtures, scenes outside the castle).
static func for_node(node: Node) -> StaticBatch:
	if Engine.is_editor_hint() or disabled:
		return null
	var owner_node := node.owner
	while owner_node != null:
		var b := owner_node.get_node_or_null("StaticBatch")
		if b is StaticBatch and not (b as StaticBatch)._flushed:
			return b
		owner_node = owner_node.owner
	return null


const PLACEHOLDERS := "res://objects/environment/placeholders/"


static func can_batch(scene: PackedScene) -> bool:
	return scene != null and can_batch_path(scene.resource_path)


static func can_batch_path(path: String) -> bool:
	return BATCHABLE.has(path) or path.begins_with(PLACEHOLDERS)


static func prototype(scene: PackedScene) -> Dictionary:
	var path := scene.resource_path
	if _prototypes.has(path):
		return _prototypes[path]
	var root: Node3D = scene.instantiate()
	var proto := {"meshes": [], "shapes": []}
	_collect(root, root, Transform3D.IDENTITY, proto)
	root.free()
	_prototypes[path] = proto
	return proto


static func _collect(root: Node3D, node: Node, xform: Transform3D, proto: Dictionary) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var t := xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).visible and (child as MeshInstance3D).mesh != null:
			var mi := child as MeshInstance3D
			var mat: Material = mi.material_override
			if mat == null and mi.mesh.get_surface_count() == 1:
				mat = mi.get_surface_override_material(0)
			proto["meshes"].append([mi.mesh, t, mat, mi.cast_shadow])
		elif child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			proto["shapes"].append([(child as CollisionShape3D).shape, t])
		_collect(root, child, t, proto)


## Take one instance of `scene` at `xform` (global). Returns false if it cannot be batched.
func add(scene: PackedScene, xform: Transform3D) -> bool:
	if _flushed or not can_batch(scene):
		return false
	if scene.resource_path == ClassroomBoards.WALL_BOARD:
		boards.append(xform)
	elif scene.resource_path == FeastMeals.FEAST_TABLE:
		feast_tables.append(xform)
	elif scene.resource_path == TalkingPortraits.PORTRAIT:
		portraits.append(xform)
	elif scene.resource_path == DormitoryCorners.BED:
		beds.append(xform)
	if Seats.BY_SCENE.has(scene.resource_path):
		seats.append_array(Seats.for_instance(scene.resource_path, xform))
	var proto := prototype(scene)
	var local := global_transform.affine_inverse() * xform
	var cell := Vector3i(floori(local.origin.x / cell_size), floori((local.origin.y + 0.5) / storey_height), floori(local.origin.z / cell_size))
	for m: Array in proto["meshes"]:
		var key := [cell, m[0], m[2], m[3]]
		if not _meshes.has(key):
			_meshes[key] = {"mesh": m[0], "material": m[2], "shadow": m[3], "cell": cell, "xforms": []}
		(_meshes[key]["xforms"] as Array).append(local * (m[1] as Transform3D))
	if not _shapes.has(cell):
		_shapes[cell] = []
	for s: Array in proto["shapes"]:
		(_shapes[cell] as Array).append([s[0], local * (s[1] as Transform3D)])
	instance_count += 1
	return true


## Add a mesh drawn with an arbitrary transform (wall-run backing slabs: a unit box scaled).
func add_mesh(mesh: Mesh, material: Material, xform: Transform3D) -> void:
	var local := global_transform.affine_inverse() * xform
	var cell := Vector3i(floori(local.origin.x / cell_size), floori((local.origin.y + 0.5) / storey_height), floori(local.origin.z / cell_size))
	var key := [cell, mesh, material, GeometryInstance3D.SHADOW_CASTING_SETTING_ON]
	if not _meshes.has(key):
		_meshes[key] = {"mesh": mesh, "material": material, "shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "cell": cell, "xforms": []}
	(_meshes[key]["xforms"] as Array).append(local)


## Fold direct instances in the castle's containers, then build every MultiMesh and body.
func flush() -> void:
	if _flushed:
		return
	var castle := get_parent()
	for c in CONTAINERS:
		var container := castle.get_node_or_null(c)
		if container == null:
			continue
		for child in container.get_children():
			if child is Node3D and can_batch_path((child as Node).scene_file_path) and child.get_script() == null:
				if add(load(child.scene_file_path), (child as Node3D).global_transform):
					container.remove_child(child)
					child.free()
	_flushed = true
	for key in _meshes:
		var entry: Dictionary = _meshes[key]
		var xforms: Array = entry["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if entry["material"] != null:
			mmi.material_override = entry["material"]
		mmi.cast_shadow = entry["shadow"]
		mmi.visibility_range_end = visibility_end
		mmi.visibility_range_end_margin = 10.0
		add_child(mmi)
	for cell in _shapes:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for s: Array in _shapes[cell]:
			var cs := CollisionShape3D.new()
			cs.shape = s[0]
			cs.transform = s[1]
			body.add_child(cs)
		add_child(body)
	_meshes.clear()
	_shapes.clear()

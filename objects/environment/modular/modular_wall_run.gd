@tool
class_name ModularWallRun
extends Node3D
## Tiles a wall module (default `wall_plain.tscn`) along local +X to cover
## [member length]. Modules are scaled evenly on X so the run ends exactly at
## `length` with no seam overlap (at most ±12 % stretch for a 4 m module).
## Children are generated at runtime/in-editor and never saved, so replacing
## the module scene updates every wall in every level.
##
## The stone model bevels inward at its borders (and has a few see-through
## slivers there), so tiled or stacked modules would show bright seams where
## light from the room behind leaks through. A continuous dark mortar slab just
## behind both stone faces closes every seam and reads as a mortar joint.

@export var length: float = 8.0:
	set(value):
		length = maxf(0.1, value)
		_rebuild()
@export var module_scene: PackedScene = preload("res://objects/environment/modular/wall_plain.tscn"):
	set(value):
		module_scene = value
		_rebuild()
@export var module_width: float = 4.0
@export var module_height: float = 4.0
## Adds a slightly shrunken box occluder covering the run so rooms behind the
## wall are culled (project setting rendering/occlusion_culling is on).
@export var occluder: bool = true
@export var module_depth: float = 0.35
## Mortar slab behind the stone faces. Its depth sits just inside the module's
## flat faces (±0.16 m for wall_plain) so only the bevelled borders reveal it.
@export var backing: bool = true
@export var backing_depth: float = 0.26

static var _backing_material: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or module_scene == null:
		return
	for child in get_children():
		if child.has_meta("wall_run_generated"):
			remove_child(child)
			child.queue_free()
	var count := maxi(1, int(round(length / module_width)))
	var scale_x := length / (count * module_width)
	for i in range(count):
		var module := module_scene.instantiate()
		module.set_meta("wall_run_generated", true)
		module.position = Vector3((i + 0.5) * module_width * scale_x, 0.0, 0.0)
		module.scale = Vector3(scale_x, 1.0, 1.0)
		add_child(module)
	if backing:
		var slab := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(length, module_height, backing_depth)
		box_mesh.material = _get_backing_material()
		slab.mesh = box_mesh
		slab.position = Vector3(length / 2.0, module_height / 2.0, 0.0)
		slab.set_meta("wall_run_generated", true)
		add_child(slab)
	if occluder and not Engine.is_editor_hint():
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = Vector3(length - 0.1, module_height - 0.1, module_depth * 0.6)
		occ.occluder = box
		occ.position = Vector3(length / 2.0, module_height / 2.0, 0.0)
		occ.set_meta("wall_run_generated", true)
		add_child(occ)


static func _get_backing_material() -> StandardMaterial3D:
	if _backing_material == null:
		_backing_material = StandardMaterial3D.new()
		_backing_material.albedo_color = Color(0.11, 0.1, 0.09)
		_backing_material.roughness = 1.0
	return _backing_material

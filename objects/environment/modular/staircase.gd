@tool
class_name Staircase
extends StaticBody3D
## Straight flight of stone steps generated from [member rise], [member run]
## and [member width]. Origin is the foot of the flight at floor level,
## centred on the width; the steps climb along local +X. Each step is a box
## [member slab_thickness] deep under its tread, so the flight reads as a
## stone stair with a stepped soffit from below and leaves headroom for a
## flight stacked beneath it. Children are generated at runtime/in-editor and
## never saved; replacing this scene with a modelled stair keeps every level
## unchanged.

@export var rise: float = 9.0:
	set(value):
		rise = maxf(0.1, value)
		_rebuild()
@export var run: float = 14.0:
	set(value):
		run = maxf(0.1, value)
		_rebuild()
@export var width: float = 3.6:
	set(value):
		width = maxf(0.1, value)
		_rebuild()
## Steps are never taller than this (PlayerMovement.step_height is 0.42).
@export var max_step_height: float = 0.36:
	set(value):
		max_step_height = maxf(0.05, value)
		_rebuild()
## Depth of stone under each tread (bounded by the flight base).
@export var slab_thickness: float = 1.0:
	set(value):
		slab_thickness = maxf(0.1, value)
		_rebuild()

const STONE_MATERIAL: StandardMaterial3D = preload("res://assets/materials/greybox_stone.tres")


func _ready() -> void:
	_rebuild()


func step_count() -> int:
	return maxi(1, int(ceil(rise / max_step_height - 0.0001)))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("stair_generated"):
			remove_child(child)
			child.queue_free()
	var n := step_count()
	var h := rise / n
	var d := run / n
	for i in range(n):
		var top := (i + 1) * h
		var bottom := maxf(0.0, top - slab_thickness)
		var size := Vector3(d, top - bottom, width)
		var centre := Vector3((i + 0.5) * d, (top + bottom) / 2.0, 0.0)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = STONE_MATERIAL
		mesh.position = centre
		mesh.set_meta("stair_generated", true)
		add_child(mesh)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = centre
		shape.set_meta("stair_generated", true)
		add_child(shape)

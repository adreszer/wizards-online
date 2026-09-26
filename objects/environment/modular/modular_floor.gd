@tool
class_name ModularFloor
extends Node3D
## Tiles a floor module (default `floor_tile.tscn`, 4 × 4 m, top-centre
## pivot) over a rectangle of [member size_x] × [member size_z] metres whose
## top-left corner is this node's origin (tiles extend along +X and +Z).
## Tiles are stretched evenly so the area is covered exactly with no overlap.

@export var size_x: float = 16.0:
	set(value):
		size_x = maxf(0.1, value)
		_rebuild()
@export var size_z: float = 16.0:
	set(value):
		size_z = maxf(0.1, value)
		_rebuild()
@export var module_scene: PackedScene = preload("res://objects/environment/modular/floor_tile.tscn"):
	set(value):
		module_scene = value
		_rebuild()
@export var module_size: float = 4.0


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or module_scene == null:
		return
	for child in get_children():
		if child.has_meta("floor_generated"):
			remove_child(child)
			child.queue_free()
	var nx := maxi(1, int(round(size_x / module_size)))
	var nz := maxi(1, int(round(size_z / module_size)))
	var sx := size_x / (nx * module_size)
	var sz := size_z / (nz * module_size)
	for ix in range(nx):
		for iz in range(nz):
			var tile := module_scene.instantiate()
			tile.set_meta("floor_generated", true)
			tile.position = Vector3((ix + 0.5) * module_size * sx, 0.0, (iz + 0.5) * module_size * sz)
			tile.scale = Vector3(sx, 1.0, sz)
			add_child(tile)

@tool
class_name ModularWallRun
extends Node3D
## Tiles a wall module (default `wall_plain.tscn`) along local +X to cover
## [member length]. Modules are scaled evenly on X so the run ends exactly at
## `length` with no seam overlap (at most ±12 % stretch for a 4 m module).
## Children are generated at runtime/in-editor and never saved, so replacing
## the module scene updates every wall in every level.

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

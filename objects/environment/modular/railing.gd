@tool
class_name Railing
extends StaticBody3D
## Stone balustrade [member height] tall running along local +X for [member length],
## its base rising by [member rise] over that length (0 for landings and hole edges, a
## flight's rise for the open side of a stair). Origin is the start of the base line,
## centred on the thickness. Drawn as the balustrade model in equal sections; on a
## flight each section is sheared to the slope, so the rail and plinth follow the
## stair while the balusters stay upright. The collider is the plain parapet.

@export var length: float = 4.0:
	set(value):
		length = maxf(0.05, value)
		_rebuild()
@export var rise: float = 0.0:
	set(value):
		rise = value
		_rebuild()
@export var height: float = 1.0:
	set(value):
		height = maxf(0.1, value)
		_rebuild()
@export var thickness: float = 0.25:
	set(value):
		thickness = maxf(0.05, value)
		_rebuild()

const BALUSTRADE: PackedScene = preload("res://assets/models/environment/modular/balustrade.glb")
## The model's own size: length along X, height, depth (tools/wrap_prop.py measured it).
const MODEL_SIZE := Vector3(2.88, 1.0, 0.56)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("railing_generated"):
			remove_child(child)
			child.queue_free()
	var t := thickness / 2.0
	# Bottom edge a little below the base so the parapet meets sloped treads without a gap.
	var sink := 0.3
	var corners := [
		Vector3(0, -sink, -t), Vector3(length, rise - sink, -t), Vector3(length, rise - sink, t), Vector3(0, -sink, t),
		Vector3(0, height, -t), Vector3(length, rise + height, -t), Vector3(length, rise + height, t), Vector3(0, height, t),
	]
	var sections := maxi(1, roundi(length / MODEL_SIZE.x))
	var run := length / sections
	var slope := rise / length
	for i in sections:
		var x := (i + 0.5) * run
		var section := BALUSTRADE.instantiate() as Node3D
		section.transform = Transform3D(
			Basis(Vector3(run / MODEL_SIZE.x, slope * run / MODEL_SIZE.x, 0.0), Vector3(0.0, height / MODEL_SIZE.y, 0.0),
				Vector3(0.0, 0.0, maxf(thickness, 0.3) / MODEL_SIZE.z)),
			Vector3(x, slope * x, 0.0))
		section.set_meta("railing_generated", true)
		add_child(section)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = PackedVector3Array(corners)
	shape.shape = convex
	shape.set_meta("railing_generated", true)
	add_child(shape)

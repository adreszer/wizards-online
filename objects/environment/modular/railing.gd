@tool
class_name Railing
extends StaticBody3D
## Stone balustrade: a solid parapet [member height] tall running along local
## +X for [member length], its base rising by [member rise] over that length
## (0 for landings and hole edges, a flight's rise for the open side of a
## stair). Origin is the start of the base line, centred on the thickness.

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

const STONE_MATERIAL: StandardMaterial3D = preload("res://assets/materials/greybox_stone.tres")

static var _two_sided: StandardMaterial3D


## The shared stone, drawn from both sides (generated faces, no winding to get wrong).
static func stone() -> StandardMaterial3D:
	if _two_sided == null:
		_two_sided = STONE_MATERIAL.duplicate()
		_two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _two_sided


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
	var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		for idx: int in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(corners[idx])
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = stone()
	mesh.set_meta("railing_generated", true)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = PackedVector3Array(corners)
	shape.shape = convex
	shape.set_meta("railing_generated", true)
	add_child(shape)

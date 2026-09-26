@tool
class_name GreyboxBlock
extends StaticBody3D
## Resizable greybox box with matching collision. The mesh/shape update when
## [member size] or [member color] change, in the editor and at runtime.

@export var size: Vector3 = Vector3(4, 1, 4):
	set(value):
		size = value
		_apply()
@export var color: Color = Color(0.55, 0.52, 0.6):
	set(value):
		color = value
		_apply()

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	_apply()


func _apply() -> void:
	if _mesh == null or _shape == null:
		return
	var box := _mesh.mesh as BoxMesh
	if box == null or box.resource_local_to_scene == false:
		box = BoxMesh.new()
		_mesh.mesh = box
	box.size = size
	var shape := _shape.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_shape.shape = shape
	shape.size = size
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.roughness = 0.9
		_mesh.material_override = mat
	mat.albedo_color = color

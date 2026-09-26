class_name MovingPlatform
extends AnimatableBody3D
## Reusable moving platform. Travels through [member points] (local offsets
## from its start position) at [member speed], optionally looping or
## ping-ponging, and can wait for [method activate]. `sync_to_physics` lets
## CharacterBody3D riders be carried by the physics engine.

enum LoopMode { PING_PONG, LOOP, ONCE }

signal reached_point(index: int)

## Waypoints relative to the platform's starting position. The start position is point 0 implicitly.
@export var points: Array[Vector3] = [Vector3(0, 0, 6)]
@export var speed: float = 2.5
@export var loop_mode: LoopMode = LoopMode.PING_PONG
@export var pause_at_points: float = 0.6
@export var active: bool = true
@export var size: Vector3 = Vector3(3, 0.4, 3):
	set(value):
		size = value
		_apply_size()

var _path: Array[Vector3] = []
var _index: int = 0
var _direction: int = 1
var _wait: float = 0.0
var _origin: Vector3

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	sync_to_physics = true
	_origin = global_position
	_path = [Vector3.ZERO]
	for p in points:
		_path.append(p)
	_apply_size()


func activate() -> void:
	active = true


func deactivate() -> void:
	active = false


func _physics_process(delta: float) -> void:
	if not active or _path.size() < 2:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var target := _origin + _path[_index]
	var to_target := target - global_position
	var step := speed * delta
	if to_target.length() <= step:
		global_position = target
		reached_point.emit(_index)
		_wait = pause_at_points
		_advance_index()
	else:
		global_position += to_target.normalized() * step


func _advance_index() -> void:
	match loop_mode:
		LoopMode.LOOP:
			_index = (_index + 1) % _path.size()
		LoopMode.ONCE:
			if _index < _path.size() - 1:
				_index += 1
			else:
				active = false
		_:
			if _index == _path.size() - 1:
				_direction = -1
			elif _index == 0:
				_direction = 1
			_index += _direction


func _apply_size() -> void:
	if _mesh == null:
		return
	var box := _mesh.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		_mesh.mesh = box
	box.size = size
	var shape := _shape.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_shape.shape = shape
	shape.size = size

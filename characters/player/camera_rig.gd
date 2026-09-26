class_name CameraRig
extends Node3D
## Third-person orbit camera for the LOCAL player only.
##
## Hierarchy: CameraRig (yaw, top-level) → Pitch → SpringArm3D → Camera3D.
## The SpringArm3D keeps the camera out of level geometry. Movement code asks
## [method get_yaw] for its reference frame; spell aiming asks [method get_aim_ray].
## Camera "zones"/cinematic constraints can later be layered on by driving
## [member yaw]/[member pitch]/[member distance] from an external controller
## and setting [member input_enabled] to false.

@export var target: Node3D
@export var target_height: float = 1.4
@export var distance: float = 4.6
@export var shoulder_offset: float = 0.45
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.14
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 65.0
@export var position_smoothing: float = 22.0
@export var initial_pitch_degrees: float = -14.0
@export var input_enabled: bool = true

var yaw: float = 0.0
var pitch: float = 0.0

@onready var _pitch_node: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	pitch = deg_to_rad(initial_pitch_degrees)
	_spring_arm.spring_length = distance
	_spring_arm.position.x = shoulder_offset
	if target != null:
		yaw = target.rotation.y + PI
		global_position = target.global_position + Vector3.UP * target_height
	_apply_rotation()


func activate() -> void:
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_camera() -> Camera3D:
	return _camera


func get_yaw() -> float:
	return yaw


## Ray from the centre of the screen. Returns {origin: Vector3, direction: Vector3}.
func get_aim_ray() -> Dictionary:
	return {
		"origin": _camera.global_position,
		"direction": -_camera.global_transform.basis.z,
	}


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw -= deg_to_rad(motion.relative.x * mouse_sensitivity)
		pitch -= deg_to_rad(motion.relative.y * mouse_sensitivity)
		pitch = clampf(pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
		_apply_rotation()


func _process(delta: float) -> void:
	if target == null:
		return
	var desired := target.global_position + Vector3.UP * target_height
	var t := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired, t)
	if _spring_arm.spring_length != distance:
		_spring_arm.spring_length = distance


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)

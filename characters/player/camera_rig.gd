class_name CameraRig
extends Node3D
## Third-person orbit camera for the LOCAL player only.
##
## Hierarchy: CameraRig (yaw, top-level) → Pitch → SpringArm3D → Camera3D.
## The SpringArm3D keeps the camera out of level geometry. Movement code asks
## [method get_yaw] for its reference frame; spell aiming asks [method get_aim_ray].
##
## Look input: classic mouse look. During gameplay the rig keeps the cursor
## captured and every mouse movement turns the camera; the mouse wheel zooms.
## The cursor is handed back whenever a UI panel captures input, the game is
## paused, the window loses focus (a click back into the window recaptures) or
## the player presses F1 to free it (F1 again resumes mouse look).
## Camera "zones"/cinematic constraints can later be layered on by driving
## [member yaw]/[member pitch]/[member distance] from an external controller
## and setting [member input_enabled] to false.

@export var target: Node3D
## Pivot height above the feet. Sits above the head so the character is a little
## below the screen centre and the centre-screen aim points higher.
@export var target_height: float = 1.85
@export var distance: float = 4.6
@export var min_distance: float = 1.6
@export var max_distance: float = 9.0
## Distance change per mouse-wheel notch.
@export var zoom_step: float = 0.6
@export var zoom_smoothing: float = 14.0
@export var shoulder_offset: float = 0.45
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.14
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 65.0
@export var position_smoothing: float = 22.0
@export var initial_pitch_degrees: float = -9.0
@export var input_enabled: bool = true
## World-space offset added to the follow point (the player sets it while easing a step-up).
var follow_offset: Vector3 = Vector3.ZERO

var yaw: float = 0.0
var pitch: float = 0.0
## Mouse look wanted by the player (F1 toggles it off to get a free cursor).
var mouse_look_enabled: bool = true

var _active: bool = false
## Set when the window lost focus; the next click into the window recaptures.
var _awaiting_click: bool = false
var _target_distance: float = 0.0

@onready var _pitch_node: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	pitch = deg_to_rad(initial_pitch_degrees)
	_target_distance = distance
	_spring_arm.spring_length = distance
	_spring_arm.position.x = shoulder_offset
	if target != null:
		yaw = target.rotation.y + PI
		global_position = target.global_position + Vector3.UP * target_height
	_apply_rotation()


func activate() -> void:
	_camera.current = true
	_active = true
	_sync_mouse_capture()


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
	if not _active:
		return
	if event.is_action_pressed("toggle_cursor") and _gameplay_has_mouse():
		mouse_look_enabled = not mouse_look_enabled
		_awaiting_click = false
		_sync_mouse_capture()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed and input_enabled and _gameplay_has_mouse():
				var direction := -1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				zoom_by(direction * zoom_step * maxf(button.factor, 0.1))
				get_viewport().set_input_as_handled()
			return
		# The click that brings focus back only recaptures; it must not cast.
		if button.pressed and _awaiting_click and _gameplay_has_mouse():
			_awaiting_click = false
			_sync_mouse_capture()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and is_mouse_looking():
		apply_look_delta((event as InputEventMouseMotion).relative)


## True while mouse movement turns the camera (the cursor is captured).
func is_mouse_looking() -> bool:
	return input_enabled and mouse_look_enabled and not _awaiting_click and _gameplay_has_mouse()


## No pause menu or UI panel currently needs the cursor.
func _gameplay_has_mouse() -> bool:
	return _active and not get_tree().paused and not GameSession.ui_input_captured


## Capture the cursor while mouse look is on, free it otherwise. Panels and the
## pause menu free the cursor themselves; this recaptures once they are gone.
func _sync_mouse_capture() -> void:
	if is_mouse_looking():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _active and mouse_look_enabled:
			_awaiting_click = true
			_sync_mouse_capture()
	elif what == NOTIFICATION_EXIT_TREE and _active:
		_active = false
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Move the camera closer (negative) or further (positive); smoothed in _process.
func zoom_by(amount: float) -> void:
	_target_distance = clampf(_target_distance + amount, min_distance, max_distance)


## Jump straight to a distance (tests / cinematic controllers).
func set_distance(value: float) -> void:
	_target_distance = clampf(value, min_distance, max_distance)
	distance = _target_distance
	_spring_arm.spring_length = distance


## Rotate by a mouse-style delta in pixels (also used by tests / future gamepad look).
func apply_look_delta(relative: Vector2) -> void:
	yaw -= deg_to_rad(relative.x * mouse_sensitivity)
	pitch -= deg_to_rad(relative.y * mouse_sensitivity)
	pitch = clampf(pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_apply_rotation()


func _process(delta: float) -> void:
	if _active:
		_sync_mouse_capture()
	if target == null:
		return
	var desired := target.global_position + follow_offset + Vector3.UP * target_height
	var t := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired, t)
	if not is_equal_approx(distance, _target_distance):
		distance = lerpf(distance, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
		if absf(distance - _target_distance) < 0.005:
			distance = _target_distance
	if _spring_arm.spring_length != distance:
		_spring_arm.spring_length = distance


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)

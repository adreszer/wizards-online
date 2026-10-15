class_name PlayerMovement
extends Node
## Arcade-flavoured third-person character movement for a CharacterBody3D.
##
## Reads intent from a [PlayerInput], moves relative to a yaw supplied by a
## frame provider (normally the camera rig), and reports a coarse movement
## state through signals so animation and networking stay decoupled.
## All tuning values are exported.

enum State { IDLE, WALK, RUN, JUMP, FALL, LAND, FLY }

const STATE_NAMES: PackedStringArray = ["idle", "walk", "run", "jump", "fall", "land", "fly"]

signal state_changed(new_state: State, old_state: State)
signal jumped()
signal landed(impact_speed: float)
## The body was moved onto another tread in one tick; `displacement` is the world-space
## jump. The body then stands still for `duration` seconds (the time it would have taken
## to walk that distance), so visuals subtract the jump and close it at constant speed.
signal stepped(displacement: Vector3, duration: float)
## Flight on a broom started or ended (see [method set_flying]).
signal flying_changed(is_flying: bool)

@export_group("Ground")
@export var walk_speed: float = 4.2
@export var run_speed: float = 7.5
@export var acceleration: float = 32.0
@export var deceleration: float = 40.0
@export var rotation_speed: float = 14.0
@export var max_slope_angle_degrees: float = 46.0
## Must exceed step_height so walking down a stair snaps to the lower tread instead of falling.
@export var floor_snap_length: float = 0.55
@export var step_height: float = 0.42
## A drop bigger than this in one grounded tick counts as a step down (slopes move far less).
@export var step_down_threshold: float = 0.12
## How far past the ledge edge the step probe lands (must exceed the capsule radius).
@export var step_forward_distance: float = 0.45

@export_group("Air")
@export var jump_velocity: float = 8.0
@export var gravity_multiplier: float = 2.2
@export var fall_gravity_multiplier: float = 2.9
@export var low_jump_gravity_multiplier: float = 3.4
@export var air_acceleration: float = 14.0
@export var air_drag: float = 1.5
@export var max_fall_speed: float = 40.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.14
@export var land_state_duration: float = 0.18
@export var hard_landing_speed: float = 12.0

@export_group("Flight")
## Cruising speed on a broom; Sprint boosts to fly_boost_speed.
@export var fly_speed: float = 14.0
@export var fly_boost_speed: float = 30.0
## Climb / sink rate from Jump / Descend, on top of the camera-pitch climb.
@export var fly_vertical_speed: float = 8.0
@export var fly_acceleration: float = 16.0
## Slows to a hover when nothing is pressed.
@export var fly_deceleration: float = 12.0
## Vertical response (climb, sink, stopping either).
@export var fly_vertical_acceleration: float = 30.0
## How fast the broom swings round to where the mouse (camera) points.
@export var fly_turn_speed: float = 10.0
## Camera pitch within this small band flies level; beyond it forward flight
## climbs or dives toward the crosshair.
@export var fly_pitch_deadzone_degrees: float = 3.0
## Upward pop when mounting on the ground.
@export var takeoff_speed: float = 6.0
## Nothing climbs above this height (world y); the grounds' sky has a lid.
@export var max_flight_height: float = 160.0
## Holding Descend this long while touching the floor lands and dismounts.
@export var land_hold_seconds: float = 0.35

var body: CharacterBody3D
var input: PlayerInput
## Called with no arguments, returns the yaw (radians) the movement is relative to.
var frame_yaw_provider: Callable
## Called with no arguments, returns the camera pitch (radians, negative = looking
## down); in flight, forward follows it.
var frame_pitch_provider: Callable
## True while riding a broom: no gravity, free 3D movement.
var is_flying: bool = false

var state: State = State.IDLE
var is_grounded: bool = false
var facing_yaw: float = 0.0
var last_move_direction: Vector3 = Vector3.ZERO

var debug_step: bool = false
var _base_gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _land_timer: float = 0.0
var _was_grounded: bool = false
var _peak_fall_speed: float = 0.0
var _jump_requested_externally: bool = false
var _external_jump_hold: float = 0.0
var _external_move: Vector3 = Vector3.ZERO
var _held: float = 0.0
var _external_sprint: bool = false
## Seconds the body still owes for the last step teleport (horizontal motion is held).
var _step_stall: float = 0.0
## Horizontal speed the body would have had during the stall (keeps the walk state alive).
var _stall_speed: float = 0.0
## Scripted climb (+1) / sink (-1) in flight (tests).
var _external_vertical: float = 0.0
var _land_hold: float = 0.0


func setup(p_body: CharacterBody3D, p_input: PlayerInput) -> void:
	body = p_body
	input = p_input
	body.floor_max_angle = deg_to_rad(max_slope_angle_degrees)
	body.floor_snap_length = maxf(floor_snap_length, step_height + 0.1)
	body.floor_stop_on_slope = true
	body.floor_constant_speed = true
	body.floor_block_on_wall = true
	body.wall_min_slide_angle = deg_to_rad(10.0)
	facing_yaw = body.rotation.y


## Scripted control (tests / cutscenes): world-space direction with length <= 1.
func set_external_move(direction: Vector3, sprint: bool = false) -> void:
	_external_move = direction
	_external_sprint = sprint


## Scripted jump; the button counts as held for `hold_seconds` (full-height jump).
## Keep the body from walking for `seconds` (a trick step gripping a foot); a jump frees it.
func hold(seconds: float) -> void:
	_held = maxf(_held, seconds)


func is_held() -> bool:
	return _held > 0.0


## Scripted climb (> 0) or sink (< 0) while flying, -1..1.
func set_external_vertical(value: float) -> void:
	_external_vertical = clampf(value, -1.0, 1.0)


## Starts or ends broom flight. Mounting on the ground pops the body up; ending
## it hands the body back to gravity (falling from a height is harmless).
func set_flying(value: bool) -> void:
	if value == is_flying:
		return
	is_flying = value
	_step_stall = 0.0
	_held = 0.0
	_land_hold = 0.0
	if body != null:
		if value and body.is_on_floor():
			body.velocity.y = takeoff_speed
		_peak_fall_speed = 0.0
	flying_changed.emit(value)
	if body != null:
		_update_state(false, false)


func request_jump(hold_seconds: float = 0.35) -> void:
	_jump_requested_externally = true
	_external_jump_hold = hold_seconds


func get_horizontal_speed() -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func get_state_name() -> String:
	return STATE_NAMES[state]


func _physics_process(delta: float) -> void:
	if body == null:
		return
	if is_flying:
		_physics_fly(delta)
		return
	var move_dir := _compute_move_direction()
	var sprint := (input != null and input.sprint_held) or _external_sprint
	var jump_pressed := (input != null and input.consume_jump()) or _jump_requested_externally
	var jump_held := (input != null and input.jump_held) or _external_jump_hold > 0.0
	_jump_requested_externally = false
	_external_jump_hold = maxf(0.0, _external_jump_hold - delta)
	if _held > 0.0:
		_held = 0.0 if jump_pressed else _held - delta
		if _held > 0.0:
			move_dir = Vector3.ZERO

	_was_grounded = is_grounded
	is_grounded = body.is_on_floor()

	# Timers -----------------------------------------------------------------
	if is_grounded:
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	_land_timer = maxf(0.0, _land_timer - delta)

	# Horizontal velocity ----------------------------------------------------
	var velocity := body.velocity
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_speed := run_speed if sprint else walk_speed
	var desired := move_dir * target_speed
	if _step_stall > 0.0:
		# Pay back the distance a step teleport gave for free: hold the body still.
		_step_stall -= delta
		horizontal = Vector3.ZERO
		if _step_stall <= 0.0:
			_step_stall = 0.0
			horizontal = move_dir * _stall_speed
	elif is_grounded:
		var accel := acceleration if move_dir.length_squared() > 0.0001 else deceleration
		horizontal = horizontal.move_toward(desired, accel * delta)
	else:
		if move_dir.length_squared() > 0.0001:
			horizontal = horizontal.move_toward(desired, air_acceleration * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, air_drag * delta)

	# Vertical velocity ------------------------------------------------------
	var gravity_scale := gravity_multiplier
	if velocity.y < 0.0:
		gravity_scale = fall_gravity_multiplier
	elif not jump_held and not is_grounded:
		gravity_scale = low_jump_gravity_multiplier
	if not is_grounded:
		velocity.y -= _base_gravity * gravity_scale * delta
		velocity.y = maxf(velocity.y, -max_fall_speed)
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var did_jump := false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		is_grounded = false
		did_jump = true

	body.velocity = Vector3(horizontal.x, velocity.y, horizontal.z)

	if not is_grounded:
		_peak_fall_speed = maxf(_peak_fall_speed, -body.velocity.y)

	# Facing ------------------------------------------------------------------
	if move_dir.length_squared() > 0.0001:
		last_move_direction = move_dir.normalized()
		var target_yaw := atan2(-last_move_direction.x, -last_move_direction.z)
		facing_yaw = lerp_angle(facing_yaw, target_yaw, minf(1.0, rotation_speed * delta))
		body.rotation.y = facing_yaw

	if is_grounded and not did_jump:
		if not _try_step_down(move_dir):
			_try_step_up(move_dir, delta)

	var y_before_move := body.global_position.y
	body.move_and_slide()

	# Landing detection after the move -----------------------------------------
	var grounded_now := body.is_on_floor()
	# Floor snap pulled us down a stair in one tick: let the visuals ease down too.
	if is_grounded and grounded_now and not did_jump:
		var drop := body.global_position.y - y_before_move
		if drop < -step_down_threshold:
			stepped.emit(Vector3(0.0, drop, 0.0), 0.1)
	if grounded_now and not _was_grounded and not did_jump:
		landed.emit(_peak_fall_speed)
		if _peak_fall_speed > 3.0:
			_land_timer = land_state_duration
		_peak_fall_speed = 0.0
	is_grounded = grounded_now
	if did_jump:
		jumped.emit()

	_update_state(sprint, did_jump)


func _compute_move_direction() -> Vector3:
	if _external_move.length_squared() > 0.0001:
		return _external_move.limit_length(1.0)
	if input == null:
		return Vector3.ZERO
	var axis := input.move_axis
	if axis.length_squared() < 0.0001:
		return Vector3.ZERO
	axis = axis.limit_length(1.0)
	var yaw := 0.0
	if frame_yaw_provider.is_valid():
		yaw = float(frame_yaw_provider.call())
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return (forward * axis.y + right * axis.x)


func _update_state(sprint: bool, did_jump: bool) -> void:
	var new_state := state
	if is_flying:
		new_state = State.FLY
	elif not is_grounded:
		new_state = State.JUMP if body.velocity.y > 0.5 or did_jump else State.FALL
	elif _land_timer > 0.0:
		new_state = State.LAND
	else:
		var speed := maxf(get_horizontal_speed(), _stall_speed if _step_stall > 0.0 else 0.0)
		if speed < 0.3:
			new_state = State.IDLE
		elif sprint and speed > walk_speed + 0.5:
			new_state = State.RUN
		else:
			new_state = State.WALK
	if new_state != state:
		var old := state
		state = new_state
		state_changed.emit(state, old)


## Broom flight steers with the mouse: forward is where the camera (the
## crosshair) points, yaw and pitch, and the broom always faces that way.
## Jump / Descend climb and sink, Sprint boosts; with nothing pressed
## the broom slows to a hover. Collisions still slide along walls. Holding
## Descend while touching the floor lands and ends the flight.
func _physics_fly(delta: float) -> void:
	var axis := Vector2.ZERO
	if _external_move.length_squared() > 0.0001:
		# Scripted world-space direction (tests): x/z only, like walking.
		var flat := _external_move.limit_length(1.0)
		axis = Vector2(flat.x, flat.z)
	elif input != null:
		axis = input.move_axis.limit_length(1.0)
	var boost := (input != null and input.sprint_held) or _external_sprint
	var up := (input != null and input.jump_held) or _external_vertical > 0.0
	var down := (input != null and input.descend_held) or _external_vertical < 0.0
	var desired := Vector3.ZERO
	if _external_move.length_squared() > 0.0001:
		desired = Vector3(axis.x, 0.0, axis.y)
	elif axis.length_squared() > 0.0001:
		var yaw := float(frame_yaw_provider.call()) if frame_yaw_provider.is_valid() else 0.0
		var pitch := float(frame_pitch_provider.call()) if frame_pitch_provider.is_valid() else 0.0
		var deadzone := deg_to_rad(fly_pitch_deadzone_degrees)
		var climb := signf(pitch) * maxf(0.0, absf(pitch) - deadzone)
		var forward := Vector3(-sin(yaw) * cos(climb), sin(climb), -cos(yaw) * cos(climb))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		desired = (forward * axis.y + right * axis.x).limit_length(1.0)
	desired *= fly_boost_speed if boost else fly_speed
	var vertical := (1.0 if up else 0.0) - (1.0 if down else 0.0)
	desired.y += vertical * fly_vertical_speed
	var accel := fly_acceleration if desired.length_squared() > 0.01 else fly_deceleration
	var velocity := body.velocity
	var vertical_velocity := velocity.y
	velocity = velocity.move_toward(desired, accel * delta)
	# Climb and sink answer the keys at once, even against the current motion.
	velocity.y = move_toward(vertical_velocity, desired.y, fly_vertical_acceleration * delta)
	if body.global_position.y >= max_flight_height and velocity.y > 0.0:
		velocity.y = 0.0
	body.velocity = velocity

	# Face the mouse: the camera's yaw (scripted moves: the direction of travel).
	var target_yaw := facing_yaw
	if _external_move.length_squared() > 0.0001:
		target_yaw = atan2(-_external_move.x, -_external_move.z)
	elif frame_yaw_provider.is_valid():
		target_yaw = float(frame_yaw_provider.call())
	facing_yaw = lerp_angle(facing_yaw, target_yaw, minf(1.0, fly_turn_speed * delta))
	body.rotation.y = facing_yaw
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horizontal.length_squared() > 1.0:
		last_move_direction = horizontal.normalized()

	body.move_and_slide()
	is_grounded = body.is_on_floor()
	if is_grounded and down:
		_land_hold += delta
		if _land_hold >= land_hold_seconds:
			set_flying(false)
			landed.emit(0.0)
			return
	else:
		_land_hold = 0.0
	_update_state(boost, false)


## Stair descent: a rounded capsule rolls over a tread edge and briefly "falls" to the
## next step. When the floor directly under the centre drops away by up to step_height,
## probe forward until the lowered capsule fits and place it on the lower tread instead.
## Returns true when the body was moved.
func _try_step_down(move_dir: Vector3) -> bool:
	if step_height <= 0.0 or move_dir.length_squared() < 0.0001 or body.velocity.y > 0.01:
		return false
	var space := body.get_world_3d().direct_space_state
	var from := body.global_transform
	var query := PhysicsRayQueryParameters3D.create(
		from.origin + Vector3.UP * 0.05, from.origin - Vector3.UP * (step_height + 0.2), body.collision_mask, [body.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false # Real ledge: fall.
	var drop: float = from.origin.y - float(hit["position"].y)
	if drop < step_down_threshold:
		return false # Still standing on this tread.
	if Vector3(hit["normal"]).angle_to(Vector3.UP) > body.floor_max_angle:
		return false
	var forward := move_dir.normalized()
	var down := -Vector3.UP * (drop + 0.1)
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	var d := 0.05
	while d <= step_forward_distance + 0.001:
		var probe := forward * d
		if body.test_move(from, probe):
			return false # Something ahead; let the wall/step-up logic deal with it.
		var ahead := from
		ahead.origin += probe
		params.from = ahead
		params.motion = down
		if PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
			var travel := result.get_travel()
			var walkable := result.get_collision_normal().angle_to(Vector3.UP) <= body.floor_max_angle
			# Landed on the lower tread (not caught on the riser or the edge we came from).
			if walkable and travel.y <= -(drop - 0.05):
				var destination := ahead.origin + travel + Vector3.UP * 0.01
				var displacement := destination - from.origin
				body.global_position = destination
				body.velocity.y = 0.0
				if debug_step: print("step down: OK ", displacement)
				_begin_step(displacement)
				return true
		d += 0.05
	if debug_step: print("step down: no fit")
	return false


## Forgiving stair handling: when walking into a low ledge, lift the body onto it.
func _try_step_up(move_dir: Vector3, delta: float) -> void:
	if step_height <= 0.0 or move_dir.length_squared() < 0.0001:
		return
	# Use the intended direction: velocity is already zeroed when we're pressed against the ledge.
	var forward := move_dir.normalized()
	var motion := forward * maxf(get_horizontal_speed(), walk_speed) * delta
	var from := body.global_transform
	# Must be blocked at current height...
	if not body.test_move(from, motion):
		if debug_step: print("step: not blocked")
		return
	var up := Vector3.UP * step_height
	if body.test_move(from, up):
		if debug_step: print("step: ceiling")
		return
	var raised := from
	raised.origin += up
	# ...and free at the raised height, far enough to land past the edge.
	var probe := forward * maxf(step_forward_distance, motion.length())
	if body.test_move(raised, probe):
		if debug_step: print("step: blocked when raised")
		return
	raised.origin += probe
	var params := PhysicsTestMotionParameters3D.new()
	params.from = raised
	params.motion = -up
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		if debug_step: print("step: no floor below")
		return
	var travel := result.get_travel()
	# Require an actual ledge (not just the floor we're already on) and a walkable surface.
	if travel.length() > step_height - 0.04:
		if debug_step: print("step: travel too long ", travel.length())
		return
	if result.get_collision_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		if debug_step: print("step: too steep ", result.get_collision_normal())
		return
	if debug_step: print("step: OK ", travel)
	var destination := raised.origin + travel + Vector3.UP * 0.01
	var displacement := destination - from.origin
	body.global_position = destination
	_begin_step(displacement)


## After a step teleport: stop the body for as long as walking the horizontal part
## would have taken, remember the speed for the animation state, and tell listeners.
func _begin_step(displacement: Vector3) -> void:
	var intended := maxf(get_horizontal_speed(), walk_speed)
	var flat := Vector3(displacement.x, 0.0, displacement.z).length()
	_stall_speed = intended
	_step_stall = flat / intended
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	stepped.emit(displacement, maxf(_step_stall, 0.05))

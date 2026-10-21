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
## The body went up or down a step in one tick (`rise` metres, negative going down);
## the body is only ever moved vertically, so visuals ease out just that jump.
signal stepped(rise: float)
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
@export var floor_snap_length: float = 0.5
## Tallest ledge walked up without jumping. The body's collision is a narrow, flat-bottomed
## foot under a full-width cylinder that starts at this height (player.tscn), so steps
## only ever meet the foot and anything taller meets the body like a wall.
@export var step_height: float = 0.42
## Smallest height change counted as a step (smaller ones are slopes and seams).
@export var min_step_rise: float = 0.03

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
## Metres a step travelled beyond the tick's own motion (to set the foot fully on a
## tread), along _step_debt_dir; paid back a little per tick so the pace never changes.
var _step_debt: float = 0.0
var _step_debt_dir: Vector3 = Vector3.ZERO
## Scripted climb (+1) / sink (-1) in flight (tests).
var _external_vertical: float = 0.0
var _land_hold: float = 0.0


func setup(p_body: CharacterBody3D, p_input: PlayerInput) -> void:
	body = p_body
	input = p_input
	body.floor_max_angle = deg_to_rad(max_slope_angle_degrees)
	body.floor_snap_length = maxf(floor_snap_length, step_height + 0.05)
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


## Where the body is ahead of its even pace because of a step's extra travel (world
## space, pointing back); the mesh adds it so it moves at the walking speed throughout.
func step_lag() -> Vector3:
	return -_step_debt_dir * _step_debt


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
	if is_grounded:
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

	var y_before_move := body.global_position.y
	var floor_angle := body.get_floor_angle() if is_grounded else 0.0
	if is_grounded and not did_jump and _try_step_up(move_dir, delta):
		# The step already moved the body this tick's distance: slide with no horizontal
		# motion (floor state, moving platforms) and keep the velocity for the next tick.
		var kept := body.velocity
		body.velocity = Vector3.ZERO
		body.move_and_slide()
		body.velocity = Vector3(kept.x, 0.0, kept.z)
	elif _step_debt > 0.0 and is_grounded and get_horizontal_speed() > 0.5 and move_dir.dot(_step_debt_dir) > 0.5:
		# Pay back a step's extra travel: this tick's move is a little shorter.
		var flat_speed := get_horizontal_speed()
		var repay := minf(_step_debt, minf(0.012, flat_speed * delta * 0.25))
		_step_debt -= repay
		var scale := 1.0 - repay / (flat_speed * delta)
		body.velocity.x *= scale
		body.velocity.z *= scale
		body.move_and_slide()
		body.velocity.x /= scale
		body.velocity.z /= scale
	else:
		# Stopped, turned or airborne: forget the debt, but let the mesh close the gap gently.
		_step_debt = maxf(0.0, _step_debt - 0.3 * delta)
		body.move_and_slide()
	var grounded_now := body.is_on_floor()
	if is_grounded and not grounded_now and not did_jump:
		grounded_now = _try_step_down()

	# Landing detection after the move -----------------------------------------
	# Floor snap pulled us down a stair in one tick: let the visuals ease down too.
	if is_grounded and grounded_now and not did_jump:
		var drop := body.global_position.y - y_before_move
		if drop < -min_step_rise - get_horizontal_speed() * delta * tan(floor_angle):
			stepped.emit(drop)
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
		var speed := get_horizontal_speed()
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


## Step-up, instead of the move: when this tick's own motion would run into a ledge no
## taller than step_height with a walkable top, the body goes up, travels this tick's
## motion (sliding along a wall it is hugging) and comes down on the ledge. It travels
## exactly what move_and_slide would have, so a step never changes the walking speed;
## only the rise is a jump, which the mesh eases out (see [signal stepped]).
## (Lifting the body and leaving the travel to move_and_slide does not work: pushed into
## a wall on the floor, move_and_slide cancels the move and snaps the body back down.)
## Returns true when the body was moved.
func _try_step_up(move_dir: Vector3, delta: float) -> bool:
	if step_height <= 0.0 or move_dir.length_squared() < 0.0001:
		return false
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var motion := horizontal * delta
	# Pressed against a ledge the velocity into it is already gone: probe with the intent,
	# and travel just far enough to stand on the ledge.
	var probe := motion
	var intent := move_dir.normalized()
	if probe.length() < walk_speed * 0.5 * delta:
		probe = intent * walk_speed * delta
	var along := motion.dot(intent)
	if along < 0.02:
		motion += intent * (0.02 - along)
	var from := body.global_transform
	var result := PhysicsTestMotionResult3D.new()
	if not _cast(from, probe, result, 4):
		return false
	# The sweep also reports the floor it slides on: look for a face the foot runs into.
	var blocked := false
	for k in result.get_collision_count():
		if result.get_collision_normal(k).angle_to(Vector3.UP) > body.floor_max_angle:
			blocked = true
	if not blocked:
		return false # A slope (or the floor): move_and_slide walks it.
	var raised := from
	_cast(from, Vector3.UP * step_height, result)
	var lift := result.get_travel().y
	if lift < min_step_rise:
		if debug_step: print("step: ceiling")
		return false
	raised.origin.y += lift
	var top := raised
	raised.origin += _slide_cast(top, motion)
	if not _cast(raised, Vector3.DOWN * (lift + 0.02), result):
		return false
	var extra := 0.0
	if not _sole_contact(result) and _edge_has_level_top(result, intent):
		# Only the foot's rounded rim reached the tread: go on until the flat sole is on it.
		extra = 0.03
		raised = top
		raised.origin += _slide_cast(top, motion + intent * extra)
		if not _cast(raised, Vector3.DOWN * (lift + 0.02), result):
			return false
	var rise := raised.origin.y + result.get_travel().y - from.origin.y
	# The foot has to land on it: the body cylinder's bottom resting on a taller block is no step.
	if result.get_collision_point().y > from.origin.y + rise + 0.05:
		if debug_step: print("step: landed on the body, not the foot")
		return false
	if rise < min_step_rise or rise > step_height:
		if debug_step: print("step: no ledge (rise %.3f, lift %.3f, moved %s)" % [rise, lift, raised.origin - top.origin])
		return false
	if not _sole_contact(result):
		if debug_step: print("step: not standing on it ", result.get_collision_normal())
		return false
	if debug_step: print("step up %.3f (extra %.2f)" % [rise, extra])
	_add_step_debt(intent * extra)
	body.global_position = raised.origin + result.get_travel() + Vector3.UP * 0.002
	stepped.emit(rise)
	return true


## Step-down fallback, after the move: walking off a tread the foot's rounded rim can
## catch on the edge for a tick, which floor snap reads as a wall. When a floor lies
## within step_height straight below, put the body on it instead of falling.
func _try_step_down() -> bool:
	if body.velocity.y > 0.01:
		return false
	var result := PhysicsTestMotionResult3D.new()
	var from := body.global_transform
	# Nudge 2 cm along the motion so the rim clears the edge it is resting on.
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var nudge := Vector3.ZERO
	if flat.length_squared() > 0.0001:
		nudge = flat.normalized() * 0.02
		from.origin += nudge
		if body.test_move(body.global_transform, nudge):
			from = body.global_transform
			nudge = Vector3.ZERO
	if not _cast(from, Vector3.DOWN * (step_height + 0.05), result):
		return false
	if not _walkable_contact(result):
		return false
	body.global_position = from.origin + result.get_travel()
	body.velocity.y = 0.0
	_add_step_debt(nudge)
	body.apply_floor_snap()
	if debug_step: print("step down fallback ", result.get_travel())
	return true


func _add_step_debt(extra: Vector3) -> void:
	if extra.length_squared() < 0.000001:
		return
	var total := _step_debt_dir * _step_debt + extra
	_step_debt = total.length()
	_step_debt_dir = total / _step_debt


## Whether a downward sweep came to rest on walkable ground.
func _walkable_contact(result: PhysicsTestMotionResult3D) -> bool:
	return result.get_collision_normal().angle_to(Vector3.UP) <= body.floor_max_angle


## Whether a step landing rests on the foot's flat sole: a ledge's top, or a slope of it,
## not the rounded rim on its edge (which leaves the body bobbing on the corner).
func _sole_contact(result: PhysicsTestMotionResult3D) -> bool:
	var normal := result.get_collision_normal()
	if normal.angle_to(Vector3.UP) <= deg_to_rad(20.0):
		return true
	if not _walkable_contact(result):
		return false
	# A sloped contact: fine on a real slope, not on an edge (the surface there is level).
	var point := result.get_collision_point()
	var query := PhysicsRayQueryParameters3D.create(point + normal * 0.05, point - normal * 0.05, body.collision_mask, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and Vector3(hit["normal"]).angle_to(normal) < deg_to_rad(8.0)


## A contact on the foot's rounded rim at a ledge's edge reports a slanted normal even
## when the ledge is level: a short ray just past the edge, along `toward`, tells.
func _edge_has_level_top(result: PhysicsTestMotionResult3D, toward: Vector3) -> bool:
	if toward.length_squared() < 0.000001:
		return false
	var point := result.get_collision_point() + toward.normalized() * 0.03
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.05, point - Vector3.UP * 0.05, body.collision_mask, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and Vector3(hit["normal"]).angle_to(Vector3.UP) <= body.floor_max_angle


## Sweeps the body from `from` by `motion`; true on a hit (result holds travel and normal).
func _cast(from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D, max_collisions: int = 1) -> bool:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	params.margin = body.safe_margin
	params.max_collisions = max_collisions
	return PhysicsServer3D.body_test_motion(body.get_rid(), params, result)


## The travel of `motion` from `from` sliding once along whatever it hits.
func _slide_cast(from: Transform3D, motion: Vector3) -> Vector3:
	var result := PhysicsTestMotionResult3D.new()
	if not _cast(from, motion, result):
		return motion
	var travel := result.get_travel()
	var normal := result.get_collision_normal()
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return travel
	var rest := (motion - travel).slide(normal.normalized())
	var moved := from
	moved.origin += travel
	if not _cast(moved, rest, result):
		return travel + rest
	return travel + result.get_travel()

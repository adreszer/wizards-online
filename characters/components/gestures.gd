class_name Gestures
extends Node
## A character's social gestures and sitting (Player component). One gesture at a
## time: one-shot gestures (wave, bow, clap, point, shrug, cheer) play for a moment;
## held ones (raise a hand, take notes, sit) last until cancelled. The local player
## cancels a held gesture by moving (sitting: by moving or jumping, which stands up);
## remote players follow their snapshots ("e" gesture, "h" seat height). SocialPose
## on the skeleton draws it. A raised hand is how a student asks to speak: the
## professor's lesson panel lists raised hands first.

signal changed(gesture: StringName)

## One-shot gestures and how long each plays (seconds). Sitting is its own state
## (`seated`), not a gesture; "eat" is held while seated at a feast during a meal.
const ONE_SHOT := {&"wave": 2.4, &"bow": 1.8, &"clap": 2.6, &"point": 2.4, &"shrug": 1.6, &"cheer": 2.4}
## Held gestures: they last until cancelled.
const HELD: Array[StringName] = [&"raise_hand", &"notes", &"eat"]
## Arm gestures that play while seated (on top of sitting).
const SEATED_OK: Array[StringName] = [&"raise_hand", &"notes", &"eat", &"wave", &"point", &"clap", &"shrug", &"cheer"]
## Every gesture id, in the emote menu's order (sit is chosen at a seat, not here).
const IDS: Array[StringName] = [&"raise_hand", &"wave", &"bow", &"clap", &"point", &"shrug", &"cheer", &"notes"]
const BLEND_SPEED := 6.0

var current: StringName = &""
## Sitting on a seat (arm gestures can play on top).
var seated := false
## Sitting: the seat surface above the feet (metres), and the seat (global transform:
## origin on the surface, -Z the way the sitter faces).
var seat_height: float = 0.0
var seat: Transform3D
var pose: SocialPose
var _player: Node3D
var _left: float = 0.0


func setup(player: Node3D, visual: Node) -> void:
	_player = player
	var skeleton: Skeleton3D = null
	for node in visual.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton != null:
		pose = SocialPose.new()
		pose.name = "SocialPose"
		pose.influence = 0.0
		pose.active = false
		skeleton.add_child(pose)


static func is_gesture(id: StringName) -> bool:
	return ONE_SHOT.has(id) or HELD.has(id)


func is_sitting() -> bool:
	return seated


## Starts gesture `id` (a held one toggles off when it is already showing). Seated,
## only arm gestures play (on top of sitting); a bow stands up first.
func play(id: StringName) -> bool:
	if not is_gesture(id) or id == &"sit":
		return false
	if id == current and HELD.has(id):
		_show(&"")
		return true
	if seated and not SEATED_OK.has(id):
		stand()
	_show(id)
	_left = float(ONE_SHOT.get(id, 0.0))
	return true


## Ends the gesture; seated with no gesture, stands up.
func stop() -> void:
	if current != &"":
		_show(&"")
	elif seated:
		stand()


## Sits on `p_seat` (origin on the seat surface, facing its -Z): the body moves to the
## seat, turns with it and stops colliding until it stands.
func sit_at(p_seat: Transform3D) -> void:
	seat = p_seat
	var body := _player as CharacterBody3D
	var floor_y := body.global_position.y
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(p_seat.origin + Vector3.UP * 0.2, p_seat.origin + Vector3.DOWN * 2.0, 1, [body.get_rid()]))
	# The ray first meets the seat itself; the floor is the next surface below it.
	if not hit.is_empty():
		var below := body.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create((hit["position"] as Vector3) + Vector3.DOWN * 0.05, p_seat.origin + Vector3.DOWN * 2.0, 1, [body.get_rid()]))
		if not below.is_empty():
			floor_y = (below["position"] as Vector3).y
	seat_height = maxf(0.2, p_seat.origin.y - floor_y)
	var facing := -p_seat.basis.z
	body.global_position = Vector3(p_seat.origin.x, floor_y, p_seat.origin.z)
	body.rotation.y = atan2(-facing.x, -facing.z)
	body.velocity = Vector3.ZERO
	body.collision_mask = 0
	var movement := body.get_node_or_null("Movement")
	if movement != null:
		movement.set_physics_process(false)
	seated = true
	if not SEATED_OK.has(current):
		current = &""
	_restart()


func stand() -> void:
	if not seated:
		return
	seated = false
	var body := _player as CharacterBody3D
	# Step off the seat toward where the sitter faced.
	body.global_position += -seat.basis.z * 0.55 + Vector3.UP * 0.05
	if body.get("is_local"):
		body.collision_mask = Player.LAYER_WORLD
		var movement := body.get_node_or_null("Movement")
		if movement != null:
			movement.set("facing_yaw", body.rotation.y)
			movement.set_physics_process(true)
	if current == &"eat":
		current = &""
	_restart()


## Remote players: the gesture and seat height (0 = standing) from their latest snapshot.
func set_remote(id: StringName, height: float) -> void:
	var clean: StringName = id if is_gesture(id) and id != &"sit" else &""
	var now_seated := height > 0.0
	seat_height = height
	if clean != current or now_seated != seated:
		current = clean
		seated = now_seated
		_restart()


func _show(id: StringName) -> void:
	current = id
	_restart()


func _restart() -> void:
	if pose != null:
		pose.elapsed = 0.0
	changed.emit(current)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0 and ONE_SHOT.has(current):
			_show(&"")
	if pose == null:
		return
	var showing := current != &"" or seated
	if showing:
		pose.gesture = current
		pose.seated = seated
		pose.seat_world_y = _player.global_position.y + seat_height
	pose.influence = move_toward(pose.influence, 1.0 if showing else 0.0, delta * BLEND_SPEED)
	pose.active = pose.influence > 0.0
	if pose.influence <= 0.0:
		pose.gesture = &""
		pose.seated = false

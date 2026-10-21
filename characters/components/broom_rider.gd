class_name BroomRider
extends Node
## Player component: riding a mount item (a broom). Local players mount and
## dismount through [method toggle] (the Mount action or the satchel); it
## checks the inventory and the area rules, then hands flight to
## PlayerMovement. Remote players get the ridden item id from their movement
## snapshots ([method set_remote_mount]). Either way the mount's scene sits
## under the character visual and [member pose] banks and pitches it with the
## flight, which Player applies to the visual each frame, while a
## BroomRidePose modifier on the skeleton seats the character astride the
## shaft (lean, grip, legs) and blends in and out with [member ride_blend].
##
## Flight is client-side like the rest of movement (the server relays it
## unvalidated); owning the broom is the only gate besides area rules.
##
## Everyone near hears a rider kick off, the wind (a gentle rush blending into a
## roar with speed) and the landing.

signal mount_changed(definition: ItemDefinition)

## AreaZone kinds in the open air, the only places brooms fly: everything else
## (rooms, corridors, classrooms, towers, shops…) is indoors. Outside every
## zone counts as open air too. Flying into an indoor zone lands the rider.
const FLY_KINDS: Array[String] = ["grounds", "outdoor"]
## Mounting also needs open sky: nothing solid this far overhead (a cottage or
## gatehouse inside an open-air zone still has a roof).
const SKY_CHECK_HEIGHT := 40.0
const LAYER_WORLD := 1 << 0
## Height of the broom's seat above the feet.
const SEAT_HEIGHT := 0.76
const TAKEOFF := preload("res://assets/audio/flying/broom_takeoff.wav")
const LAND := preload("res://assets/audio/flying/broom_land.wav")
const WIND_SLOW := preload("res://assets/audio/flying/broom_flight_slow_loop.wav")
const WIND_FAST := preload("res://assets/audio/flying/broom_flight_fast_loop.wav")
## Speeds (m/s) between which the wind blends from the gentle rush to the roar.
const WIND_CALM := 4.0
const WIND_ROAR := 30.0

## Ridden mount, null on foot.
var mount: ItemDefinition
var mount_node: Node3D
## Transform for the character visual (bank, pitch, hover bob) around the seat.
var pose: Transform3D = Transform3D.IDENTITY
## Riding pose on the character's skeleton (null when the rig has no Mixamo bones).
var ride_pose: BroomRidePose
## 0 on foot … 1 seated; eases over ~0.3 s on mounting and landing.
var ride_blend: float = 0.0

var _player: Node
var _movement: PlayerMovement
var _inventory: Inventory
var _attach: Node3D
## The wand's mesh: tucked away while both hands hold the shaft.
var _wand_mesh: Node3D
var _pitch: float = 0.0
var _roll: float = 0.0
var _bob_time: float = 0.0
var _last_yaw: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _wind_slow: AudioStreamPlayer3D
var _wind_fast: AudioStreamPlayer3D


func setup(player: Node, movement: PlayerMovement, inventory: Inventory, attach: Node3D) -> void:
	_player = player
	_movement = movement
	_inventory = inventory
	_attach = attach
	_last_yaw = (player as Node3D).rotation.y
	_last_position = (player as Node3D).global_position
	if _wind_slow == null:
		_wind_slow = Sfx.loop_player(player as Node3D, "WindSlow", WIND_SLOW, -10.0, 30.0)
		_wind_fast = Sfx.loop_player(player as Node3D, "WindFast", WIND_FAST, -60.0, 40.0)
	var skeleton := attach.find_child("Skeleton3D", true, false) as Skeleton3D if attach != null else null
	_wand_mesh = attach.find_child("WandMesh", true, false) as Node3D if attach != null else null
	if skeleton != null:
		ride_pose = BroomRidePose.new()
		ride_pose.name = "BroomRidePose"
		ride_pose.influence = 0.0
		ride_pose.active = false
		skeleton.add_child(ride_pose)


## Online the server checks where riders are (feature "flight"): told to land, we land.
func on_server_flight(kind: String, data: Dictionary) -> void:
	if kind == "flight" and data.get("land", false) and mount != null and _player != null and _player.get("is_local") == true:
		dismount()
		GameEvents.notify(tr("NOTIFY_NO_FLYING_HERE"), 4.0, ToastStack.Kind.WARNING)


## Local player: start riding the first mount item carried, or land.
## Returns true when the rider state changed.
func toggle() -> bool:
	if mount != null:
		dismount()
		return true
	return mount_item(_first_mount())


func is_riding() -> bool:
	return mount != null


## Local player: mount `definition` if it is an owned mount and flying is allowed here.
func mount_item(definition: ItemDefinition) -> bool:
	if definition == null or not definition.is_mount():
		GameEvents.notify(tr("NOTIFY_NO_BROOM"), 5.0, ToastStack.Kind.WARNING)
		return false
	if _inventory != null and not _inventory.has(definition.id):
		return false
	if not can_fly_here():
		GameEvents.notify(tr("NOTIFY_FLY_OUTDOORS_ONLY"), 4.0, ToastStack.Kind.WARNING)
		return false
	_movement.set_flying(true)
	_show(definition)
	return true


func dismount() -> void:
	if mount == null:
		return
	if _movement != null:
		_movement.set_flying(false)
	_show(null)


## True outdoors: in an open-air zone (or none) with open sky overhead.
func can_fly_here() -> bool:
	var tracker: AreaTracker = _player.get("area_tracker") if _player != null else null
	if tracker != null and not is_open_air_kind(tracker.current_kind()):
		return false
	return _open_sky()


static func is_open_air_kind(kind: String) -> bool:
	return kind.is_empty() or FLY_KINDS.has(kind)


func _open_sky() -> bool:
	var body := _player as Node3D
	if body == null or not body.is_inside_tree():
		return true
	var from := body.global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * SKY_CHECK_HEIGHT, LAYER_WORLD)
	query.exclude = [(body as CollisionObject3D).get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Local: the area changed under the rider.
func on_area_changed(zone: AreaZone) -> void:
	if mount != null and zone != null and not is_open_air_kind(zone.kind):
		dismount()
		GameEvents.notify(tr("NOTIFY_NO_FLYING_HERE"), 4.0, ToastStack.Kind.WARNING)


## Local: the inventory changed (the server may have taken the broom away).
func on_inventory_changed() -> void:
	if mount != null and _inventory != null and not _inventory.has(mount.id):
		dismount()


## Movement ended the flight itself (landing): drop the broom visual too.
func on_flying_changed(is_flying: bool) -> void:
	if not is_flying and mount != null:
		_show(null)


## Remote players: the mount id from the newest snapshot ("" = on foot).
func set_remote_mount(item_id: String) -> void:
	var definition := ItemRegistry.load_definition(item_id) if not item_id.is_empty() else null
	if definition != null and not definition.is_mount():
		definition = null
	_show(definition)


## A spell went off: the wand hand lets go of the shaft for the cast clip.
func on_cast() -> void:
	if ride_pose != null and mount != null:
		ride_pose.release_wand_hand()


func mount_id() -> String:
	return String(mount.id) if mount != null else ""


func _first_mount() -> ItemDefinition:
	if _inventory == null:
		return null
	for slot in _inventory.slots:
		var definition: ItemDefinition = slot["def"]
		if definition.is_mount():
			return definition
	return null


func _show(definition: ItemDefinition) -> void:
	if definition == mount:
		return
	if _player != null and (definition == null) != (mount == null):
		Sfx.play_at(_player as Node3D, TAKEOFF if definition != null else LAND, -2.0, 30.0)
		if definition == null and _wind_slow != null:
			_wind_slow.stop()
			_wind_fast.stop()
	if mount_node != null:
		mount_node.queue_free()
		mount_node = null
	mount = definition
	if definition != null and _attach != null:
		mount_node = definition.mount_scene.instantiate() as Node3D
		mount_node.position = Vector3(0.0, SEAT_HEIGHT, 0.0)
		_attach.add_child(mount_node)
	mount_changed.emit(definition)


func _process(delta: float) -> void:
	if _player == null:
		return
	var body := _player as Node3D
	# Local bodies know their velocity; remote ones are measured from the drawn
	# (interpolated) motion.
	var measured := (body as CharacterBody3D).velocity
	if not bool(_player.get("is_local")) and delta > 0.0:
		measured = (body.global_position - _last_position) / delta
	_velocity = _velocity.lerp(measured, 1.0 - exp(-10.0 * delta))
	_last_position = body.global_position
	var yaw_rate := angle_difference(_last_yaw, body.rotation.y) / maxf(delta, 0.0001)
	_last_yaw = body.rotation.y
	var target_pitch := 0.0
	var target_roll := 0.0
	var bob := 0.0
	if mount != null:
		var horizontal := Vector2(_velocity.x, _velocity.z).length()
		# Nose follows the climb; lean into speed; bank into turns.
		target_pitch = clampf(atan2(_velocity.y, maxf(horizontal, 4.0)) * 0.6, -0.45, 0.45) - clampf(horizontal / 60.0, 0.0, 0.18)
		target_roll = clampf(yaw_rate * 0.14 * clampf(horizontal / 8.0, 0.0, 1.0), -0.55, 0.55)
		_bob_time += delta
		bob = sin(_bob_time * 2.2) * 0.05 * (1.0 - clampf(horizontal / 10.0, 0.0, 1.0))
		_wind(_velocity.length())
		# Reduced motion (settings): no banking or bobbing, a calmer ride.
		if GameSettings.get_value("reduce_motion"):
			target_roll = 0.0
			target_pitch *= 0.3
			bob = 0.0
	var t := 1.0 - exp(-6.0 * delta)
	_pitch = lerpf(_pitch, target_pitch, t)
	_roll = lerpf(_roll, target_roll, t)
	_update_ride_pose(delta, yaw_rate)
	if mount == null and absf(_pitch) < 0.001 and absf(_roll) < 0.001:
		pose = Transform3D.IDENTITY
		return
	var pivot := Vector3(0.0, SEAT_HEIGHT, 0.0)
	var tilt := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)
	pose = Transform3D(Basis.IDENTITY, pivot + Vector3.UP * bob) * Transform3D(tilt, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


## The wind while riding at `speed`: the gentle rush fades as the roar rises.
func _wind(speed: float) -> void:
	if _wind_slow == null:
		return
	var k := clampf((speed - WIND_CALM) / (WIND_ROAR - WIND_CALM), 0.0, 1.0)
	_wind_slow.volume_db = linear_to_db(lerpf(0.55, 0.2, k))
	_wind_fast.volume_db = linear_to_db(maxf(k, 0.001))
	Sfx.start_loop(_wind_slow)
	Sfx.start_loop(_wind_fast)


func _update_ride_pose(delta: float, yaw_rate: float) -> void:
	ride_blend = move_toward(ride_blend, 1.0 if mount != null else 0.0, delta / 0.3)
	if ride_pose == null:
		return
	ride_pose.active = ride_blend > 0.0
	ride_pose.influence = ease(ride_blend, -1.8)
	if mount_node != null:
		ride_pose.mount = mount_node
	if _wand_mesh != null:
		_wand_mesh.visible = ride_blend < 0.5 or ride_pose.wand_grip < 0.5
	var top_speed: float = _movement.fly_boost_speed if _movement != null else 30.0
	var t := 1.0 - exp(-5.0 * delta)
	ride_pose.speed = lerpf(ride_pose.speed, clampf(_velocity.length() / top_speed, 0.0, 1.0), t)
	ride_pose.climb = lerpf(ride_pose.climb, clampf(_velocity.y / 12.0, -1.0, 1.0), t)
	ride_pose.turn = lerpf(ride_pose.turn, clampf(-yaw_rate / 2.5, -1.0, 1.0), t)

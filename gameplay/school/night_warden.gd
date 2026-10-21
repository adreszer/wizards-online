class_name NightWarden
extends Node3D
## The night warden: after curfew he walks the castle's ground-floor halls and
## corridors with a lantern. Which room he is in, and where in it, is a pure function
## of the shared time (`area_at`, `local_offset`), so every client and the server agree
## without anything being sent; the route is exported to the server
## (generated/warden.lua). A student who is out after curfew (not in their own house's
## rooms) and comes into his lantern's light (close, in front of him, in sight) is
## caught: the client reports it, the server checks the time and the room and deducts
## points once per night. castle.gd adds him; he only shows during curfew.

## The rooms he walks, in order (each for DWELL seconds, then the next; loops).
const ROUTE: Array[String] = ["entrance_hall", "corridor_w_0", "stair_hall", "corridor_e_0", "great_hall", "north_hall", "gallery", "portrait_gallery", "duelling_hall"]
const DWELL := 45.0
## Curfew in school hours (from CURFEW_START until CURFEW_END the next morning).
const CURFEW_START := 22.0
const CURFEW_END := 6.0
## How far and how wide his lantern sees.
const SIGHT := 9.0
const SIGHT_ANGLE := 55.0
const WALK_SPEED := 1.1

var _zones: Dictionary = {}
var _body: Player
var _lantern: OmniLight3D
var _caught_reported := false


static func is_curfew(hours: float) -> bool:
	var h := fposmod(hours, 24.0)
	return h >= CURFEW_START or h < CURFEW_END


## The route room he is in at `t` (server time, seconds).
static func area_at(t: float) -> String:
	return ROUTE[int(floor(t / DWELL)) % ROUTE.size()]


## Where along his pacing line he is at `t`: -1 … 1 (back and forth).
static func local_offset(t: float) -> float:
	var phase := fposmod(t, DWELL) / DWELL
	return sin(phase * TAU)


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		_zones[str((node as AreaZone).area_id)] = node
	_body = (preload("res://characters/player/player.tscn") as PackedScene).instantiate() as Player
	_body.is_local = false
	_body.character_id = "apprentice_m"
	_body.display_name = tr("WARDEN_NAME")
	add_child(_body)
	# Not a player: keep him out of rosters, lesson panels and seat checks.
	_body.remove_from_group("remote_players")
	_body.set_physics_process(false)
	_body.synchronizer.set_physics_process(false)
	_body.set_look({"body": "apprentice_m", "skin": 1, "robe": 1, "set": true})
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color(1.0, 0.8, 0.45)
	_lantern.light_energy = 2.2
	_lantern.omni_range = 7.0
	_lantern.position = Vector3(0.35, 1.2, -0.3)
	_body.add_child(_lantern)
	visible = false


func _process(_delta: float) -> void:
	var on := is_curfew(NetworkManager.school_hours())
	visible = on
	_body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		_caught_reported = false
		return
	var t := NetworkManager.server_time()
	var zone := _zones.get(area_at(t)) as AreaZone
	if zone == null:
		return
	var long_x := zone.size.x >= zone.size.z
	var half := (zone.size.x if long_x else zone.size.z) / 2.0 - 1.5
	var along := local_offset(t) * maxf(0.0, half)
	var base := zone.global_position - Vector3(0, zone.size.y / 2.0, 0)
	var pos := base + (Vector3(along, 0, 0) if long_x else Vector3(0, 0, along))
	var ahead := local_offset(t + 0.2) - local_offset(t)
	var dir := (Vector3(signf(ahead), 0, 0) if long_x else Vector3(0, 0, signf(ahead)))
	_body.global_position = pos
	if dir != Vector3.ZERO:
		_body.rotation.y = atan2(-dir.x, -dir.z)
	_body.animation_controller.set_movement_state_name("walk")
	_watch(zone)


## Reports the local student if they are out after curfew and in his light.
func _watch(zone: AreaZone) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or _caught_reported or CharacterProfile.is_staff(player.role) or player.role == CharacterProfile.ROLE_PREFECT:
		return
	if player.area_tracker.current_area_id() != zone.area_id:
		return
	if sees(_body.global_transform, player.global_position, player.get_world_3d()):
		_caught_reported = true
		NetworkManager.send_op(NetworkProtocol.OP_CAUGHT, {"area": String(zone.area_id)})
		GameEvents.notify(tr("WARDEN_CAUGHT"), 6.0, ToastStack.Kind.WARNING)


## Whether the warden standing at `warden` sees a point: close, in front, nothing between.
static func sees(warden: Transform3D, target: Vector3, world: World3D) -> bool:
	var eye := warden.origin + Vector3.UP * 1.6
	var to := target + Vector3.UP * 1.2 - eye
	if to.length() > SIGHT:
		return false
	var facing := -warden.basis.z
	if rad_to_deg(facing.angle_to(Vector3(to.x, 0, to.z))) > SIGHT_ANGLE:
		return false
	if world == null:
		return true
	var hit := world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + to * 0.95, 1))
	return hit.is_empty()

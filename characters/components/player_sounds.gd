class_name PlayerSounds
extends Node3D
## The sounds a player's body makes, heard in 3D by everyone nearby: footsteps by
## surface, jump, landing (soft or hard), being hit, reforming at a waypoint.
## Added by Player for local and remote players alike. Both read the animation
## state name (synced for remote players), so steps come from distance travelled
## while walking or running: one step per stride, which follows the speed without
## any animation data. The local player also hears jumps and landings from its
## own PlayerMovement; remote players get them from state changes.
##
## The surface under the feet: a floor collider (or its parent) with the meta
## `surface` wins (iron grates, rugs, wooden stages…); otherwise shallow lake
## water, then the area's kind (see KIND_SURFACES), then grass on open terrain
## and stone everywhere else.

const SURFACES: Array[StringName] = [&"stone", &"wood", &"carpet", &"grass", &"gravel", &"water", &"metal"]
## How many single-step files each surface has (assets/audio/player/footstep_<surface>_<n>.wav).
const STEP_COUNTS := {&"stone": 7, &"wood": 4, &"carpet": 10, &"grass": 5, &"gravel": 6, &"water": 8, &"metal": 2}
## AreaZone kind -> surface; kinds not listed are stone.
const KIND_SURFACES := {
	"grounds": &"grass", "station": &"gravel", "bridge": &"wood",
	"shop": &"wood", "inn": &"wood", "post_office": &"wood", "library": &"wood",
	"common_room": &"carpet", "dormitory": &"carpet",
}
const JUMP := preload("res://assets/audio/player/jump.wav")
const LAND_SOFT := preload("res://assets/audio/player/land_soft.wav")
const LAND_HARD := preload("res://assets/audio/player/land_hard.wav")
const HURT := preload("res://assets/audio/player/hurt.wav")
const RESPAWN := preload("res://assets/audio/player/respawn.wav")

## Metres travelled per footstep.
@export var walk_stride: float = 1.7
@export var run_stride: float = 2.4
## Remote players: seconds in the air before a landing counts as hard (the local
## player uses PlayerMovement.hard_landing_speed).
@export var hard_landing_air_time: float = 0.9

static var _step_streams := {}
static var _terrain: Terrain
static var _terrain_searched_msec := -100000

var player: Player
## The last footstep's surface and the number of steps so far, for tests.
var last_surface: StringName = &""
var steps_played := 0
var _steps: AudioStreamPlayer3D
var _body: AudioStreamPlayer3D
var _travelled := 0.0
var _last_position := Vector3.INF
var _state := "idle"
var _air_time := 0.0


func setup(p_player: Player) -> void:
	player = p_player
	_steps = _make_player("Steps", -9.0, 24.0)
	_body = _make_player("Body", -4.0, 30.0)
	player.health.damaged.connect(func(_amount: int, _source: Node) -> void: play_hurt())
	player.respawn_handler.respawned.connect(func(_t: Transform3D) -> void: _play(_body, RESPAWN))
	if player.is_local:
		player.movement.jumped.connect(func() -> void: _play(_body, JUMP))
		player.movement.landed.connect(func(impact_speed: float) -> void:
			_play(_body, LAND_HARD if impact_speed >= player.movement.hard_landing_speed else LAND_SOFT))


func play_hurt() -> void:
	_play(_body, HURT)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var state := player.animation_controller.current_state_name
	var airborne := state == "jump" or state == "fall"
	if not player.is_local:
		if state == "jump" and _state != "jump":
			_play(_body, JUMP)
		if airborne:
			_air_time += delta
		elif _state == "jump" or _state == "fall":
			_play(_body, LAND_HARD if _air_time >= hard_landing_air_time else LAND_SOFT)
			_air_time = 0.0
	_state = state
	var pos := player.global_position
	var moved := Vector2(pos.x - _last_position.x, pos.z - _last_position.z).length() if _last_position != Vector3.INF else 0.0
	_last_position = pos
	if state != "walk" and state != "run" or player.gestures.is_sitting():
		_travelled = 0.0
		return
	# A teleport (respawn, a door to another wing) is not a step.
	if moved > 3.0:
		return
	_travelled += moved
	var stride := run_stride if state == "run" else walk_stride
	if _travelled >= stride:
		_travelled -= stride
		step()


## Plays one footstep for the surface under the player now.
func step() -> void:
	last_surface = surface_at(player, player.global_position)
	steps_played += 1
	_steps.stream = step_stream(last_surface)
	_steps.play()


## A randomizer over the surface's single steps, slightly varied in pitch and volume.
static func step_stream(surface: StringName) -> AudioStreamRandomizer:
	if not _step_streams.has(surface):
		var r := AudioStreamRandomizer.new()
		r.random_pitch = 1.08
		r.random_volume_offset_db = 2.0
		for i in int(STEP_COUNTS.get(surface, 0)):
			r.add_stream(-1, load("res://assets/audio/player/footstep_%s_%d.wav" % [surface, i + 1]))
		_step_streams[surface] = r
	return _step_streams[surface]


## The surface at `pos` (the feet). `body` is excluded from the floor ray.
static func surface_at(body: Node3D, pos: Vector3) -> StringName:
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 0.6, Player.LAYER_WORLD)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var floor_node := hit.collider as Node
		for n: Node in [floor_node, floor_node.get_parent()]:
			if n != null and n.has_meta(&"surface"):
				return StringName(n.get_meta(&"surface"))
	var terrain := _find_terrain(body)
	if terrain != null and terrain.is_inside(pos.x, pos.z) and pos.y < terrain.water_level + 0.1 \
			and terrain.height_at(pos.x, pos.z) < terrain.water_level:
		return &"water"
	var zone := zone_at(body.get_tree(), pos + Vector3.UP)
	if zone != null:
		return KIND_SURFACES.get(zone.kind, &"stone")
	return &"grass" if terrain != null and terrain.is_inside(pos.x, pos.z) and absf(pos.y - terrain.height_at(pos.x, pos.z)) < 0.5 else &"stone"


## The smallest AreaZone holding `point` (as AreaTracker picks it), or null.
static func zone_at(tree: SceneTree, point: Vector3) -> AreaZone:
	var best: AreaZone = null
	for z: AreaZone in tree.get_nodes_in_group(AreaZone.GROUP):
		if AreaTracker.contains(z, point) and (best == null or z.size.x * z.size.y * z.size.z < best.size.x * best.size.y * best.size.z):
			best = z
	return best


static func _find_terrain(body: Node) -> Terrain:
	# Levels without terrain look again only every few seconds (a world may load later).
	if (_terrain == null or not is_instance_valid(_terrain) or not _terrain.is_inside_tree()) \
			and Time.get_ticks_msec() - _terrain_searched_msec > 5000:
		_terrain_searched_msec = Time.get_ticks_msec()
		_terrain = body.get_tree().root.find_child("Terrain", true, false) as Terrain
	if _terrain != null and not is_instance_valid(_terrain):
		_terrain = null
	return _terrain


func _make_player(node_name: String, volume_db: float, max_distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.volume_db = volume_db
	p.max_distance = max_distance
	add_child(p)
	return p


func _play(p: AudioStreamPlayer3D, stream: AudioStream) -> void:
	p.stream = stream
	p.play()

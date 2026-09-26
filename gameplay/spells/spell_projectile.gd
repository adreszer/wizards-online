class_name SpellProjectile
extends Node3D
## Generic spell projectile. Travels along [member direction], sweeps a ray each
## physics step (no tunnelling), delivers a [SpellEffect] to the first
## [SpellReceiver] hit and plays a burst. Cosmetic projectiles (remote players)
## fly and burst but never apply effects.
##
## The trail is laid manually: every physics step the segment just travelled is
## sampled every [member trail_spacing] metres and one particle is emitted at
## each sample, so the whole flight path glows evenly no matter how fast the
## projectile moves or how the frame rate compares to the physics rate.

signal hit(collider: Node, position: Vector3)
signal expired()

@export var collision_mask: int = 0b0000_1101  # world | remote_player | spell_target
@export var burst_lifetime: float = 0.5
## Distance between consecutive trail particles along the flight path.
@export var trail_spacing: float = 0.07
## Random sideways drift given to each trail particle (m/s).
@export var trail_scatter_speed: float = 0.35

var definition: SpellDefinition
var direction: Vector3 = Vector3.FORWARD
var speed: float = 25.0
var max_distance: float = 20.0
var caster: Node
var caster_id: String = ""
var cosmetic: bool = false
var exclude_rids: Array[RID] = []

var _travelled: float = 0.0
var _finished: bool = false
## Distance travelled since the last trail particle was laid.
var _trail_carry: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $OmniLight3D
@onready var _trail: GPUParticles3D = $Trail
@onready var _burst: CPUParticles3D = $Burst
@onready var _audio: AudioStreamPlayer3D = $ImpactAudio


func configure(def: SpellDefinition, p_direction: Vector3, p_caster: Node, p_caster_id: String, p_cosmetic: bool) -> void:
	definition = def
	direction = p_direction.normalized()
	speed = def.projectile_speed
	max_distance = def.range
	caster = p_caster
	caster_id = p_caster_id
	cosmetic = p_cosmetic


func _ready() -> void:
	if definition != null:
		var mat := _mesh.get_active_material(0) as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate()
			mat.albedo_color = definition.color
			mat.emission = definition.color
			_mesh.set_surface_override_material(0, mat)
		_light.light_color = definition.color
		_burst.color = definition.color
		var trail_mat := _trail.process_material.duplicate() as ParticleProcessMaterial
		if trail_mat != null:
			trail_mat.color = definition.color
			_trail.process_material = trail_mat
		if definition.impact_sound != null:
			_audio.stream = definition.impact_sound
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var step := speed * delta
	var from := global_position
	var to := from + direction * step
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude_rids)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := space.intersect_ray(query)
	if not result.is_empty():
		global_position = result["position"]
		_lay_trail(from, result["position"])
		_on_hit(result["collider"], result["position"], result["normal"])
		return
	_lay_trail(from, to)
	global_position = to
	_travelled += step
	if _travelled >= max_distance:
		_fizzle()


func _on_hit(collider: Node, position: Vector3, _normal: Vector3) -> void:
	if not cosmetic:
		var receiver := SpellReceiver.find_on(collider)
		if receiver != null:
			var effect := SpellEffect.create(definition, caster, caster_id, position, direction)
			receiver.receive(effect)
	hit.emit(collider, position)
	_finish(true)


## Emits trail particles evenly spaced along the segment [param from] -> [param to].
func _lay_trail(from: Vector3, to: Vector3) -> void:
	var segment := to - from
	var length := segment.length()
	if length <= 0.0 or trail_spacing <= 0.0:
		return
	var dir := segment / length
	var color := definition.color if definition != null else Color.WHITE
	var flags := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
	var d := trail_spacing - _trail_carry
	while d <= length:
		var pos := from + dir * d
		var scatter := Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0))
		scatter -= dir * scatter.dot(dir)  # keep the drift perpendicular to the flight path
		var velocity := scatter.normalized() * _rng.randf_range(0.2, 1.0) * trail_scatter_speed
		_trail.emit_particle(Transform3D(Basis.IDENTITY, pos), velocity, color, Color(), flags)
		d += trail_spacing
	_trail_carry = length - (d - trail_spacing)


func _fizzle() -> void:
	expired.emit()
	_finish(false)


func _finish(impact: bool) -> void:
	_finished = true
	_mesh.visible = false
	_light.visible = false
	if impact:
		_burst.emitting = true
		if _audio.stream != null:
			_audio.play()
	# Keep the node alive until both the burst and the last trail particles have faded.
	get_tree().create_timer(maxf(burst_lifetime, _trail.lifetime)).timeout.connect(queue_free)

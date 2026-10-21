class_name LightMote
extends Node3D
## Remains of a light spell: a small glowing orb that hovers where the spell
## ended, bobs gently and fades out after [member lifetime] seconds. Purely
## cosmetic, so every client spawns its own copy (see SpellProjectile). It hums
## softly while it hovers and twinkles away as it fades.

const HUM := preload("res://assets/audio/world/glowmote_loop.wav")
const FADE := preload("res://assets/audio/world/glowmote_fade.wav")

@export var lifetime: float = 40.0
@export var fade_seconds: float = 3.0
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 1.6

var _age: float = 0.0
var _base_y: float = 0.0
var _phase: float = randf() * TAU
var _base_energy: float = 0.0
var _hum: AudioStreamPlayer3D
var _fading := false

@onready var _light: OmniLight3D = $OmniLight3D
@onready var _orb: MeshInstance3D = $Orb


func _ready() -> void:
	_base_y = position.y
	_base_energy = _light.light_energy
	_hum = Sfx.loop_player(self, "Hum", HUM, -16.0, 8.0)
	Sfx.start_loop(_hum)


## Called by the projectile with the spell that produced this mote.
func configure_from_spell(definition: SpellDefinition) -> void:
	if not is_node_ready():
		await ready
	_light.light_color = definition.color
	var mat := _orb.get_active_material(0) as StandardMaterial3D
	if mat != null:
		mat = mat.duplicate()
		mat.albedo_color = definition.color
		mat.emission = definition.color
		_orb.set_surface_override_material(0, mat)


func _process(delta: float) -> void:
	_age += delta
	_phase += delta * bob_speed
	position.y = _base_y + sin(_phase) * bob_amplitude
	var remaining := lifetime - _age
	if remaining <= fade_seconds and not _fading:
		_fading = true
		_hum.stop()
		Sfx.play_at(self, FADE, -8.0, 10.0)
	if remaining <= 0.0:
		queue_free()
		return
	var fade := clampf(remaining / fade_seconds, 0.0, 1.0)
	var grow := clampf(_age / 0.4, 0.0, 1.0)
	_light.light_energy = _base_energy * fade * grow
	_orb.scale = Vector3.ONE * maxf(0.05, fade * grow)

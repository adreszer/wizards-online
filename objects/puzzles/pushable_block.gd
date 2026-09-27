class_name PushableBlock
extends RigidBody3D
## Loose object moved by spells via its SpellReceiver: force and wind shove it
## along the cast direction, levitate lifts it and lets it hover for a while.

@export var impulse_multiplier: float = 1.0
## Keep the push horizontal so blocks slide rather than hop.
@export var flatten_direction: bool = true
## How long a levitated block hangs in the air before gravity returns.
@export var float_seconds: float = 3.0

var is_floating: bool = false

@onready var _receiver: SpellReceiver = $SpellReceiver
var _float_timer: SceneTreeTimer


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)


func _on_spell_received(effect: SpellEffect) -> void:
	if effect.effect_type == &"levitate":
		_levitate(effect.strength)
		return
	var dir := effect.direction
	if flatten_direction:
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	apply_central_impulse(dir.normalized() * effect.strength * impulse_multiplier * mass)


func _levitate(strength: float) -> void:
	linear_velocity = Vector3(linear_velocity.x * 0.2, 0.0, linear_velocity.z * 0.2)
	apply_central_impulse(Vector3.UP * strength * mass)
	gravity_scale = 0.0
	linear_damp = 2.0
	can_sleep = false
	is_floating = true
	if _float_timer != null and _float_timer.timeout.is_connected(_land):
		_float_timer.timeout.disconnect(_land)
	_float_timer = get_tree().create_timer(float_seconds)
	_float_timer.timeout.connect(_land)


func _land() -> void:
	if not is_inside_tree():
		return
	gravity_scale = 1.0
	linear_damp = 0.0
	can_sleep = true
	sleeping = false
	is_floating = false

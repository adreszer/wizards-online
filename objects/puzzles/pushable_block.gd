class_name PushableBlock
extends RigidBody3D
## Loose object shoved by force-type spells via its SpellReceiver.

@export var impulse_multiplier: float = 1.0
## Keep the push horizontal so blocks slide rather than hop.
@export var flatten_direction: bool = true

@onready var _receiver: SpellReceiver = $SpellReceiver


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)


func _on_spell_received(effect: SpellEffect) -> void:
	var dir := effect.direction
	if flatten_direction:
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	apply_central_impulse(dir.normalized() * effect.strength * impulse_multiplier * mass)

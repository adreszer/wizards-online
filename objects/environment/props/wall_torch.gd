class_name WallTorch
extends Node3D
## Wall-mounted torch prop: model + flickering OmniLight at the flame.
## Origin is the wall-contact point; local +Z points into the room.

@export var base_energy: float = 2.2
@export var flicker_amount: float = 0.25
@export var flicker_speed: float = 9.0

@onready var _light: OmniLight3D = $Flame
var _phase: float = randf() * TAU


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)

class_name HeldTorch
extends Node3D
## Handheld torch: a stick with a glowing head and a flickering OmniLight that
## lights the area around the carrier. Instantiated by HeldItemMount under the
## character's off-hand attachment (local +Y runs along the fingers).

## Radius the torch lights up, in metres.
@export var light_radius: float = 9.0
@export var base_energy: float = 2.6
@export var flicker_amount: float = 0.18
@export var flicker_speed: float = 8.0

@onready var _light: OmniLight3D = $Flame
var _phase: float = randf() * TAU


func _ready() -> void:
	_light.omni_range = light_radius
	_light.light_energy = base_energy


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)

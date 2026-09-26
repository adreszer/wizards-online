class_name HeldTorch
extends Node3D
## Handheld torch: a stick with a glowing head and a flickering OmniLight that
## lights the area around the carrier. Instantiated by HeldItemMount under the
## character's off-hand attachment. The hand bone's axis follows the fingers
## (down at rest), so the torch keeps itself upright in world space each
## frame: it takes its position from the hand and always points +Y up.

## Radius the torch lights up, in metres.
@export var light_radius: float = 9.0
@export var base_energy: float = 2.6
@export var flicker_amount: float = 0.18
@export var flicker_speed: float = 8.0
## Keep the torch vertical regardless of the hand's rotation.
@export var keep_upright: bool = true

@onready var _light: OmniLight3D = $Flame
var _phase: float = randf() * TAU


func _ready() -> void:
	_light.omni_range = light_radius
	_light.light_energy = base_energy
	# Run after the animation/skeleton update so the hand position is current.
	process_priority = 100
	_align()


func _process(delta: float) -> void:
	_align()
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)


func _align() -> void:
	if not keep_upright or not is_inside_tree():
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	global_transform = Transform3D(Basis.IDENTITY, parent.global_position)

class_name Flame
extends MeshInstance3D
## A candle or torch flame: a small emissive tongue that sways sideways and
## breathes in height like a real flame. Each instance runs on its own random
## phase so neighbouring candles never move in step.

@export var sway: float = 0.012     # metres of sideways drift
@export var breathe: float = 0.28   # fraction of height the tongue stretches by
@export var speed: float = 7.0

var _phase: float = randf() * TAU
var _base_pos: Vector3
var _base_scale: Vector3


func _ready() -> void:
	_base_pos = position
	_base_scale = scale


func _process(delta: float) -> void:
	_phase += delta * speed
	var a := sin(_phase) * 0.5 + sin(_phase * 2.7 + 1.3) * 0.3 + sin(_phase * 6.1 + 0.7) * 0.2
	var b := sin(_phase * 1.9 + 2.1) * 0.6 + sin(_phase * 4.3) * 0.4
	position = _base_pos + Vector3(a * sway, 0.0, b * sway)
	scale = _base_scale * Vector3(1.0 - absf(a) * breathe * 0.3, 1.0 + a * breathe, 1.0 - absf(b) * breathe * 0.3)

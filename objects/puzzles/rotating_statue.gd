class_name RotatingStatue
extends StaticBody3D
## Statue that rotates 90° per force spell hit through [member state_count] states.

signal state_changed(state: int)

@export var state_count: int = 4
@export var initial_state: int = 0
@export var rotate_duration: float = 0.5

var state: int = 0
var _tween: Tween

@onready var _receiver: SpellReceiver = $SpellReceiver
@onready var _pivot: Node3D = $Pivot
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	state = initial_state % state_count
	_pivot.rotation.y = _angle_for(state)
	_receiver.spell_received.connect(_on_spell_received)


func _on_spell_received(_effect: SpellEffect) -> void:
	advance()


func advance() -> void:
	state = (state + 1) % state_count
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_pivot, "rotation:y", _pivot.rotation.y + TAU / state_count, rotate_duration)
	_audio.play()
	state_changed.emit(state)


func _angle_for(s: int) -> float:
	return TAU * float(s) / float(state_count)

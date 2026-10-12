class_name RotatingStatue
extends StaticBody3D
## Statue that rotates 90° per force spell hit through [member state_count] states.

signal state_changed(state: int)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "rotating_statue"

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

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


func _on_spell_received(effect: SpellEffect) -> void:
	if WorldObjectSync.request(self, "spell", effect):
		return
	advance()


func advance() -> void:
	set_state(state + 1)


## Turns to state `s` (wrapped), the short way round; `instant` snaps it.
func set_state(s: int, instant: bool = false) -> void:
	s = posmod(s, state_count)
	if s == state:
		return
	state = s
	if _tween != null:
		_tween.kill()
	var target := _pivot.rotation.y + wrapf(_angle_for(s) - _pivot.rotation.y, -PI + 0.001, PI + 0.001)
	if instant:
		_pivot.rotation.y = target
	else:
		_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_pivot, "rotation:y", target, rotate_duration)
		_audio.play()
	state_changed.emit(state)


## Server state: the statue's state index, null = its initial state.
func apply_world_state(value: Variant, instant: bool) -> void:
	set_state(int(value) if value != null else initial_state, instant)


func _angle_for(s: int) -> float:
	return TAU * float(s) / float(state_count)

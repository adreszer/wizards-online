class_name SecretWall
extends Node3D
## A suspicious wall ornament (SpellReceiver) that, when struck, slides the
## wall segment aside to reveal a hidden room.

signal revealed()

@export var slide_offset: Vector3 = Vector3(0, -3.4, 0)
@export var slide_duration: float = 1.6

var is_revealed: bool = false

@onready var _receiver: SpellReceiver = $Ornament/SpellReceiver
@onready var _wall: AnimatableBody3D = $Wall
@onready var _ornament: StaticBody3D = $Ornament
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)


func _on_spell_received(_effect: SpellEffect) -> void:
	reveal()


func reveal() -> void:
	if is_revealed:
		return
	is_revealed = true
	_receiver.enabled = false
	_audio.play()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_wall, "position", _wall.position + slide_offset, slide_duration)
	tween.parallel().tween_property(_ornament, "position", _ornament.position + slide_offset, slide_duration)
	revealed.emit()

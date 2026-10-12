class_name SecretWall
extends Node3D
## A suspicious wall ornament (SpellReceiver) that, when struck, slides the
## wall segment aside to reveal a hidden room.

signal revealed()

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "secret_wall"

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""
## Area on the ornament's side (the hidden room is the id's area); players
## act on the wall from either.
@export var approach_area: String = ""

@export var slide_offset: Vector3 = Vector3(0, -3.4, 0)
@export var slide_duration: float = 1.6

var is_revealed: bool = false

@onready var _receiver: SpellReceiver = $Ornament/SpellReceiver
@onready var _wall: AnimatableBody3D = $Wall
@onready var _ornament: StaticBody3D = $Ornament
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)


func _on_spell_received(effect: SpellEffect) -> void:
	if WorldObjectSync.request(self, "spell", effect):
		return
	reveal()


## Slides the wall aside. `instant` (a late joiner's snapshot) snaps it open
## without sound or the `revealed` signal.
func reveal(instant: bool = false) -> void:
	if is_revealed:
		return
	is_revealed = true
	_receiver.enabled = false
	if instant:
		_wall.position += slide_offset
		_ornament.position += slide_offset
		return
	_audio.play()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_wall, "position", _wall.position + slide_offset, slide_duration)
	tween.parallel().tween_property(_ornament, "position", _ornament.position + slide_offset, slide_duration)
	revealed.emit()


## Server state: "revealed", or null (closed again, e.g. after a server restart).
func apply_world_state(state: Variant, instant: bool) -> void:
	if state == "revealed":
		reveal(instant)
	elif is_revealed:
		is_revealed = false
		_receiver.enabled = true
		_wall.position -= slide_offset
		_ornament.position -= slide_offset

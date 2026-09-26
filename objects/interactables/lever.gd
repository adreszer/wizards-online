class_name Lever
extends StaticBody3D
## Non-spell interactable lever. Pull with Interact to toggle.

signal pulled()
signal toggled(is_on: bool)

@export var one_shot: bool = true

var is_on: bool = false

@onready var _interactable: Interactable = $Interactable
@onready var _handle: Node3D = $Handle
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_interactable.one_shot = one_shot
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	is_on = not is_on
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_handle, "rotation:x", deg_to_rad(-40.0 if is_on else 40.0), 0.35)
	_audio.play()
	_interactable.prompt_text = "INTERACT_PULL_LEVER_BACK" if is_on else "INTERACT_PULL_LEVER"
	toggled.emit(is_on)
	if is_on:
		pulled.emit()


## Snap back to the off position without emitting toggled (puzzle refusal).
func reset() -> void:
	if not is_on:
		return
	is_on = false
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_handle, "rotation:x", deg_to_rad(40.0), 0.35)
	_interactable.prompt_text = "INTERACT_PULL_LEVER"

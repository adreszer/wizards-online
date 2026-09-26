class_name MagicDoor
extends Node3D
## Door that opens/closes via external triggers (switch, lever, puzzle).
## The panel is an AnimatableBody3D so it never leaves the player stuck inside.

signal opened()
signal closed()

@export var open_height: float = 3.2
@export var open_duration: float = 1.2
@export var start_open: bool = false

var is_open: bool = false
var _tween: Tween

@onready var _panel: AnimatableBody3D = $Panel
@onready var _audio: AudioStreamPlayer3D = $Audio
var _closed_position: Vector3


func _ready() -> void:
	_closed_position = _panel.position
	if start_open:
		is_open = true
		_panel.position = _closed_position + Vector3.UP * open_height


func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


func toggle() -> void:
	set_open(not is_open)


func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	var target := _closed_position + (Vector3.UP * open_height if is_open else Vector3.ZERO)
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "position", target, open_duration)
	_audio.play()
	if is_open:
		opened.emit()
	else:
		closed.emit()

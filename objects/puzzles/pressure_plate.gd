class_name PressurePlate
extends Area3D
## Activates while any body (player or pushable block) rests on it.

signal activated()
signal deactivated()

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "pressure_plate"
const DOWN_SOUND := preload("res://assets/audio/world/pressure_plate_down.wav")
const UP_SOUND := preload("res://assets/audio/world/pressure_plate_up.wav")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var latch: bool = false

var is_active: bool = false
var _count: int = 0

@onready var _plate: Node3D = $Plate


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(_body: Node3D) -> void:
	_count += 1
	_update()


func _on_body_exited(_body: Node3D) -> void:
	_count = maxi(0, _count - 1)
	_update()


func _update() -> void:
	var active := _count > 0 or (latch and is_active)
	if active == is_active:
		return
	is_active = active
	# The slab (its base at the origin) sinks flush with the floor while pressed.
	_plate.position.y = -0.04 if is_active else 0.02
	Sfx.play_at(self, DOWN_SOUND if is_active else UP_SOUND, -4.0, 20.0)
	if is_active:
		activated.emit()
	else:
		deactivated.emit()

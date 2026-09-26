class_name PressurePlate
extends Area3D
## Activates while any body (player or pushable block) rests on it.

signal activated()
signal deactivated()

@export var latch: bool = false

var is_active: bool = false
var _count: int = 0

@onready var _plate: MeshInstance3D = $Plate


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
	_plate.position.y = 0.02 if is_active else 0.08
	if is_active:
		activated.emit()
	else:
		deactivated.emit()

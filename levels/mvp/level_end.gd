class_name LevelEnd
extends Area3D
## Reward room trigger. Emits GameEvents.level_completed once for the local player.

var _done: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _done or not body.is_in_group("local_player"):
		return
	_done = true
	GameEvents.level_completed.emit()

class_name Checkpoint
extends Area3D
## Stores a respawn transform on the local player's RespawnHandler when entered.
## Reusable: drop into any level and size the collision shape.

@export var respawn_point: Node3D
## Only the first activation shows feedback; re-entering silently refreshes.
var _activated: bool = false


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)


func get_respawn_transform() -> Transform3D:
	return respawn_point.global_transform if respawn_point != null else global_transform


func _on_body_entered(body: Node3D) -> void:
	var handler: RespawnHandler = body.get_meta("respawn_handler", null) as RespawnHandler if body.has_meta("respawn_handler") else null
	if handler == null:
		return
	handler.set_checkpoint(get_respawn_transform(), self)
	if not _activated:
		_activated = true
		GameEvents.checkpoint_activated.emit(self)

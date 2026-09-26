class_name KillZone
extends Area3D
## Instantly kills anything with a Health that enters (bottomless pits, void).


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var health: Health = body.get_meta("health", null) as Health if body.has_meta("health") else null
	if health != null:
		health.kill(self)

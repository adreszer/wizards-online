class_name AreaZone
extends Area3D
## A named region of the castle (a room, corridor, courtyard…). Emits
## [signal GameEvents.area_entered] when the local player walks in. Systems
## that key off "where am I" (HUD area name, later proximity chat, house
## access and classroom context) read the zone's metadata instead of
## hardcoding coordinates. The box is built from [member size] so the level
## generator can emit one node per room.

## Stable identifier used by gameplay/server logic (never shown to players).
@export var area_id: StringName = &""
## Translation key of the player-facing name.
@export var display_key: String = "AREA_UNKNOWN"
## Free-form category: hall, corridor, classroom, common_room, dormitory, tower, outdoor, secret…
@export var kind: String = "room"
## House placeholder (1–4) for common rooms and dormitories, 0 for shared areas.
@export var house: int = 0
## Full extent of the zone; the node origin is the box centre.
@export var size: Vector3 = Vector3(16, 9, 16)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func display_name() -> String:
	return tr(display_key)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("local_player"):
		GameEvents.area_entered.emit(area_id, self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("local_player"):
		GameEvents.area_exited.emit(area_id, self)

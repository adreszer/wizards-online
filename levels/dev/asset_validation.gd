extends Node3D
## Development-only asset validation scene. Spawns the regular player next to
## the wall test arrangement so an asset can be inspected at gameplay scale.
## Run directly:  godot --path . levels/dev/asset_validation.tscn
## Esc toggles the mouse, F3 the debug overlay (position readout).

@export var player_scene: PackedScene = preload("res://characters/player/player.tscn")

@onready var _start: Marker3D = $StartPoint


func _ready() -> void:
	var player := player_scene.instantiate()
	player.is_local = true
	player.display_name = "Inspector"
	player.character_id = GameSession.character_id
	player.name = "LocalPlayer"
	add_child(player)
	player.global_transform = _start.global_transform
	player.respawn_handler.set_checkpoint(_start.global_transform)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

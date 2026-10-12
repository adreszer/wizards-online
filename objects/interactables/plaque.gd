class_name Plaque
extends StaticBody3D
## Readable plaque: shows [member text] (a translation key) as a HUD notification
## when interacted.

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "plaque"

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var text: String = "PLAQUE_DEFAULT"
@export var display_seconds: float = 5.0

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.prompt_text = "INTERACT_READ"
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	GameEvents.notification_requested.emit(tr(text), display_seconds)

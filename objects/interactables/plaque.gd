class_name Plaque
extends StaticBody3D
## Readable plaque: shows [member text] (a translation key) as a HUD notification
## when interacted.

@export var text: String = "PLAQUE_DEFAULT"
@export var display_seconds: float = 5.0

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.prompt_text = "INTERACT_READ"
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	GameEvents.notification_requested.emit(tr(text), display_seconds)

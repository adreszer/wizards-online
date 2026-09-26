class_name Plaque
extends StaticBody3D
## Readable plaque: shows [member text] as a HUD notification when interacted.

@export_multiline var text: String = "An inscription."
@export var display_seconds: float = 5.0

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.prompt_text = "Read"
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(_interactor: Node) -> void:
	GameEvents.notification_requested.emit(text, display_seconds)

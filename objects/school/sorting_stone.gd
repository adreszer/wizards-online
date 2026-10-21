class_name SortingStone
extends StaticBody3D
## The Choosing Stone: the sorting ceremony's focus in the great hall.
## Interacting opens the sorting questionnaire (GameEvents.sorting_requested);
## characters that already belong to a house are told so instead.

signal ceremony_requested(interactor: Node)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "sorting_stone"
## The stone stirring as a newcomer steps up to it.
const WAKE := preload("res://assets/audio/school/sorting_stone_wake.wav")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@onready var _interactable: Interactable = $Interactable
@onready var _crystal: MeshInstance3D = $Crystal
@onready var _crystal_height: float = _crystal.position.y
var _phase: float = 0.0


func _ready() -> void:
	_interactable.prompt_text = "INTERACT_SORTING"
	_interactable.interacted.connect(_on_interacted)


func _process(delta: float) -> void:
	_phase += delta
	_crystal.rotation.y += delta * 0.6
	_crystal.position.y = _crystal_height + sin(_phase * 1.4) * 0.06


func _on_interacted(interactor: Node) -> void:
	if int(interactor.get("house")) != 0:
		GameEvents.notification_requested.emit(tr("NOTIFY_ALREADY_SORTED") % CharacterProfile.house_name(int(interactor.get("house"))), 4.0)
		return
	ceremony_requested.emit(interactor)
	Sfx.play_at(self, WAKE, 0.0, 30.0, Vector3(0, 1.5, 0))
	GameEvents.sorting_requested.emit()

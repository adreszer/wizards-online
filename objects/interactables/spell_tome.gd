class_name SpellTome
extends StaticBody3D
## Pedestal that teaches [member spell] to the interacting player's SpellCaster.

signal learned(by: Node)

@export var spell: SpellDefinition
@export var learn_sound: AudioStream

@onready var _interactable: Interactable = $Interactable
@onready var _book: Node3D = $Book
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_interactable.one_shot = true
	_interactable.prompt_text = "Study the tome"
	_interactable.interacted.connect(_on_interacted)
	if learn_sound != null:
		_audio.stream = learn_sound


func _process(delta: float) -> void:
	_book.rotation.y += delta * 0.8


func _on_interacted(interactor: Node) -> void:
	var caster: SpellCaster = interactor.get("spell_caster") as SpellCaster
	if caster == null or spell == null:
		return
	caster.learn_spell(spell)
	_audio.play()
	GameEvents.notification_requested.emit("Learned %s — aim with the centre of the screen and press Cast (LMB)." % spell.display_name, 6.0)
	learned.emit(interactor)
	set_process(false)

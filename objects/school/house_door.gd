class_name HouseDoor
extends Node3D
## Door into a house area (common room, dormitory, house landing). Members of
## [member house] open it by interacting; everyone else is turned away. The
## house comes from the character's server profile (Player.house), so the
## client only compares; like puzzle doors, the panel's state is local.

signal opened()
signal closed()
signal refused(interactor: Node)

@export_range(0, 4) var house: int = 1
@export var open_height: float = 3.2
@export var open_duration: float = 1.0
## How long the door stays open after a member passes.
@export var open_seconds: float = 6.0

var is_open: bool = false
var _tween: Tween
var _close_timer: SceneTreeTimer

@onready var _panel: AnimatableBody3D = $Panel
@onready var _interactable: Interactable = $Panel/Interactable
@onready var _audio: AudioStreamPlayer3D = $Audio
@onready var _crest: MeshInstance3D = $Panel/Crest
@onready var _light: OmniLight3D = $Panel/Crest/OmniLight3D
var _closed_position: Vector3


func _ready() -> void:
	_closed_position = _panel.position
	_interactable.prompt_text = "INTERACT_HOUSE_DOOR"
	_interactable.interacted.connect(_on_interacted)
	_apply_house_visual()


func _apply_house_visual() -> void:
	var color := CharacterProfile.house_color(house)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	_crest.material_override = mat
	_light.light_color = color


func admits(interactor: Node) -> bool:
	return interactor != null and int(interactor.get("house")) == house


func _on_interacted(interactor: Node) -> void:
	if admits(interactor):
		open()
	else:
		refused.emit(interactor)
		if interactor.is_in_group("local_player"):
			GameEvents.notification_requested.emit(tr("NOTIFY_HOUSE_DOOR_LOCKED") % CharacterProfile.house_name(house), 4.0)


func open() -> void:
	_set_open(true)
	if _close_timer != null and _close_timer.timeout.is_connected(_on_close_timeout):
		_close_timer.timeout.disconnect(_on_close_timeout)
	_close_timer = get_tree().create_timer(open_seconds)
	_close_timer.timeout.connect(_on_close_timeout)


func close() -> void:
	_set_open(false)


func _on_close_timeout() -> void:
	if is_inside_tree():
		close()


func _set_open(value: bool) -> void:
	if is_open == value or not is_inside_tree():
		return
	is_open = value
	var target := _closed_position + (Vector3.UP * open_height if is_open else Vector3.ZERO)
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "position", target, open_duration)
	_audio.play()
	if is_open:
		opened.emit()
	else:
		closed.emit()

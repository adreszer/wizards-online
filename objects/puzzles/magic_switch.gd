class_name MagicSwitch
extends StaticBody3D
## Spell-activated switch. Composition: a child SpellReceiver reports hits;
## this script flips state and emits signals the level wires to doors etc.

signal activated()
signal deactivated()
signal toggled(is_on: bool)

@export var toggleable: bool = false
@export var on_color: Color = Color(0.4, 1.0, 0.6)
@export var off_color: Color = Color(0.6, 0.3, 0.3)

var is_on: bool = false

@onready var _receiver: SpellReceiver = $SpellReceiver
@onready var _crystal: MeshInstance3D = $Crystal
@onready var _light: OmniLight3D = $OmniLight3D
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)
	_apply_visual()


func _on_spell_received(_effect: SpellEffect) -> void:
	if is_on and not toggleable:
		return
	set_on(not is_on)


func set_on(value: bool) -> void:
	if is_on == value:
		return
	is_on = value
	_apply_visual()
	_audio.play()
	toggled.emit(is_on)
	if is_on:
		activated.emit()
	else:
		deactivated.emit()


func _apply_visual() -> void:
	var mat := _crystal.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_crystal.material_override = mat
	var c := on_color if is_on else off_color
	mat.albedo_color = Color(c, 0.55 if is_on else 0.2)
	mat.emission = c
	mat.emission_energy_multiplier = 2.5 if is_on else 0.8
	_light.light_color = c
	_light.light_energy = 2.0 if is_on else 0.6

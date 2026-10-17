class_name PracticeTarget
extends StaticBody3D
## The classroom's practice target: a rune disc standing in a stone ring on a post,
## facing its +Z (into the room), turning slowly, that takes any spell. During a practical (the professor's lesson tools)
## each hit with the practised spell counts toward the student's task on the server;
## the disc flashes in the spell's colour for whoever cast it. It has no shared
## state of its own: the server counts hits per student (nakama/modules/world_match.lua).

const WORLD_KIND := "practice_target"
const SPIN_SPEED := 0.35
const FLASH_SECONDS := 0.6

## Stable id ("<area>/practice_target") set by the castle generator.
@export var object_id: String = ""

@onready var _receiver: SpellReceiver = $SpellReceiver
@onready var _disc: MeshInstance3D = $Disc
@onready var _light: OmniLight3D = $Light
var _flash := 0.0
var _base_energy := 0.6
## Hits seen locally (offline practice, tests).
var hits := 0


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)
	_base_energy = _light.light_energy


func _process(delta: float) -> void:
	_disc.rotate_object_local(Vector3.UP, delta * SPIN_SPEED)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_light.light_energy = _base_energy + 3.0 * (_flash / FLASH_SECONDS)


func _on_spell_received(effect: SpellEffect) -> void:
	hits += 1
	flash(effect.definition.color if effect.definition != null else Color(0.7, 0.8, 1.0))
	WorldObjectSync.request(self, "spell", effect)


func flash(color: Color) -> void:
	_flash = FLASH_SECONDS
	_light.light_color = color


## The server keeps no state for a target; nothing to apply.
func apply_world_state(_state: Variant, _instant: bool) -> void:
	pass

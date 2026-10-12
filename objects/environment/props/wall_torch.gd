class_name WallTorch
extends Node3D
## Wall-mounted torch prop: model + flickering OmniLight at the flame.
## Origin is the wall-contact point; local +Z points into the room.
##
## Spells reach it through the Target body's SpellReceiver: fire lights it,
## water, frost and dark put it out. A dark torch relights itself after
## [member relight_after] seconds (0 = stays out) so the castle never goes
## permanently black. In the shared world the server owns the lit state and
## the relight timer (see WorldObjectSync).

signal lit_changed(is_lit: bool)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "wall_torch"

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var base_energy: float = 2.6
@export var flicker_amount: float = 0.25
@export var flicker_speed: float = 9.0
@export var lit: bool = true
@export var relight_after: float = 45.0

@onready var _light: OmniLight3D = $Flame
@onready var _glow: MeshInstance3D = $Flame/FlameGlow
@onready var _receiver: SpellReceiver = $Target/SpellReceiver
var _phase: float = randf() * TAU
var _relight_timer: SceneTreeTimer
var _default_lit: bool = true


func _ready() -> void:
	_default_lit = lit
	_receiver.spell_received.connect(_on_spell_received)
	_apply_lit()


func _process(delta: float) -> void:
	if not lit:
		return
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)


func set_lit(value: bool) -> void:
	if lit == value:
		return
	lit = value
	_apply_lit()
	lit_changed.emit(lit)
	if not lit and relight_after > 0.0 and not WorldObjectSync.is_synced(self):
		_relight_timer = get_tree().create_timer(relight_after)
		_relight_timer.timeout.connect(_on_relight_timeout.bind(_relight_timer))


func _on_relight_timeout(timer: SceneTreeTimer) -> void:
	if is_inside_tree() and timer == _relight_timer:
		set_lit(true)


## Server state: true/false = lit, null = the scene's default.
func apply_world_state(state: Variant, _instant: bool) -> void:
	_relight_timer = null
	set_lit(state if state is bool else _default_lit)


func _on_spell_received(effect: SpellEffect) -> void:
	if WorldObjectSync.request(self, "spell", effect):
		return
	match effect.effect_type:
		&"fire":
			set_lit(true)
		&"water", &"frost", &"dark":
			set_lit(false)


func _apply_lit() -> void:
	_light.visible = lit
	_glow.visible = lit
	set_process(lit)

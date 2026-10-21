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
##
## Lighting catches with a whoomph, going out puffs (or hisses, when this client's
## own water spell did it); the Lamplighter's dusk and dawn rounds are silent, and
## the steady crackle comes from FireAmbience.

signal lit_changed(is_lit: bool)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "wall_torch"
const GROUP := &"wall_torches"
const IGNITE := preload("res://assets/audio/world/torch_ignite.wav")
const SNUFF := preload("res://assets/audio/world/torch_snuff.wav")
const DOUSED := preload("res://assets/audio/world/fire_doused.wav")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var base_energy: float = 2.6
@export var flicker_amount: float = 0.25
@export var flicker_speed: float = 9.0
@export var lit: bool = true
@export var relight_after: float = 45.0
## Daylight reaches this torch's room: the Lamplighter puts it out by day.
@export var daylit: bool = false

@onready var _light: OmniLight3D = $Flame
@onready var _glow: MeshInstance3D = $Flame/FlameGlow
@onready var _receiver: SpellReceiver = $Target/SpellReceiver
var _phase: float = randf() * TAU
var _relight_timer: SceneTreeTimer
var _default_lit: bool = true
## Lamplighter's part: false while a daylit torch is out for the day.
var lamp_on: bool = true
var lamp_stagger: float = 0.0
## The last spell this client aimed at it and when (ms): a douse sounds wet.
var _last_effect: StringName = &""
var _last_effect_msec := -100000


func _ready() -> void:
	_default_lit = lit
	add_to_group(GROUP)
	if daylit:
		lamp_stagger = Lamplighter.stagger_for(object_id if object_id != "" else str(name))
		add_to_group(Lamplighter.GROUP)
	_receiver.spell_received.connect(_on_spell_received)
	_apply_lit()


func _process(delta: float) -> void:
	if not burning():
		return
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)


## `quiet`: a late joiner's snapshot changes it without a sound.
func set_lit(value: bool, quiet: bool = false) -> void:
	if lit == value:
		return
	lit = value
	_apply_lit()
	lit_changed.emit(lit)
	if is_inside_tree() and lamp_on and not quiet:
		var wet := _last_effect == &"water" and Time.get_ticks_msec() - _last_effect_msec < 3000
		Sfx.play_at(_light, IGNITE if lit else (DOUSED if wet else SNUFF), -4.0, 20.0)
	if not lit and relight_after > 0.0 and not WorldObjectSync.is_synced(self):
		_relight_timer = get_tree().create_timer(relight_after)
		_relight_timer.timeout.connect(_on_relight_timeout.bind(_relight_timer))


## The Lamplighter lights (true) or snuffs (false) a daylit torch.
func set_lamp(on: bool) -> void:
	if lamp_on == on:
		return
	lamp_on = on
	_apply_lit()


## Whether the flame shows: lit (spells, the server) and not out for the day.
func burning() -> bool:
	return lit and lamp_on


func _on_relight_timeout(timer: SceneTreeTimer) -> void:
	if is_inside_tree() and timer == _relight_timer:
		set_lit(true)


## Server state: true/false = lit, null = the scene's default.
func apply_world_state(state: Variant, instant: bool) -> void:
	_relight_timer = null
	set_lit(state if state is bool else _default_lit, instant)


func _on_spell_received(effect: SpellEffect) -> void:
	_last_effect = effect.effect_type
	_last_effect_msec = Time.get_ticks_msec()
	if WorldObjectSync.request(self, "spell", effect):
		return
	match effect.effect_type:
		&"fire":
			set_lit(true)
		&"water", &"frost", &"dark":
			set_lit(false)


func _apply_lit() -> void:
	var on := burning()
	_light.visible = on
	_glow.visible = on
	set_process(on)

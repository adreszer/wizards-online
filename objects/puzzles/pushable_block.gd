class_name PushableBlock
extends RigidBody3D
## Loose object moved by spells via its SpellReceiver: force and wind shove it
## along the cast direction, levitate lifts it and lets it hover for a while.
## It hums while it floats, scrapes while it slides and thuds when it drops.

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "pushable_block"
const HOVER := preload("res://assets/audio/world/object_hover_loop.wav")
const SCRAPE := preload("res://assets/audio/world/block_push_loop.wav")
const DROP := preload("res://assets/audio/world/object_drop_wood.wav")
## Falling faster than this (m/s) and stopping is a drop worth a thud.
const DROP_SPEED := 1.5
## Sliding faster than this (m/s) on the floor scrapes.
const SCRAPE_SPEED := 0.25

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var impulse_multiplier: float = 1.0
## Keep the push horizontal so blocks slide rather than hop.
@export var flatten_direction: bool = true
## How long a levitated block hangs in the air before gravity returns.
@export var float_seconds: float = 3.0

var is_floating: bool = false

@onready var _receiver: SpellReceiver = $SpellReceiver
var _float_timer: SceneTreeTimer
var _hover: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _fall_speed := 0.0
## Drops heard so far, for tests.
var drops := 0


func _ready() -> void:
	_receiver.spell_received.connect(_on_spell_received)
	_hover = Sfx.loop_player(self, "Hover", HOVER, -10.0, 20.0)
	_scrape = Sfx.loop_player(self, "Scrape", SCRAPE, -8.0, 20.0)


func _physics_process(_delta: float) -> void:
	var v := linear_velocity
	if v.y < -DROP_SPEED:
		_fall_speed = -v.y
	elif _fall_speed > 0.0 and v.y > -0.3:
		drops += 1
		Sfx.play_at(self, DROP, linear_to_db(clampf(_fall_speed / 6.0, 0.3, 1.0)) - 2.0, 25.0)
		_fall_speed = 0.0
	var sliding := not is_floating and absf(v.y) < 0.3 and Vector2(v.x, v.z).length() > SCRAPE_SPEED
	if sliding:
		_scrape.volume_db = -8.0 + linear_to_db(clampf(Vector2(v.x, v.z).length() / 3.0, 0.25, 1.0))
		Sfx.start_loop(_scrape)
	elif _scrape.playing:
		_scrape.stop()


func _on_spell_received(effect: SpellEffect) -> void:
	if effect.effect_type == &"levitate":
		_levitate(effect.strength)
		return
	var dir := effect.direction
	if flatten_direction:
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	apply_central_impulse(dir.normalized() * effect.strength * impulse_multiplier * mass)


func _levitate(strength: float) -> void:
	linear_velocity = Vector3(linear_velocity.x * 0.2, 0.0, linear_velocity.z * 0.2)
	apply_central_impulse(Vector3.UP * strength * mass)
	gravity_scale = 0.0
	linear_damp = 2.0
	can_sleep = false
	is_floating = true
	Sfx.start_loop(_hover)
	if _float_timer != null and _float_timer.timeout.is_connected(_land):
		_float_timer.timeout.disconnect(_land)
	_float_timer = get_tree().create_timer(float_seconds)
	_float_timer.timeout.connect(_land)


func _land() -> void:
	if not is_inside_tree():
		return
	gravity_scale = 1.0
	linear_damp = 0.0
	can_sleep = true
	sleeping = false
	is_floating = false
	_hover.stop()

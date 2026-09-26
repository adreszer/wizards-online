class_name SpellDefinition
extends Resource
## Data describing a spell. Instances live in `res://resources/spells/`.
## Adding a new spell means adding a new .tres, not editing SpellCaster.

@export var id: StringName = &"spell"
## Translation keys; callers show tr(display_name) / tr(description).
@export var display_name: String = "SPELL_ARCANE_PULSE_NAME"
@export var description: String = ""
@export var icon: Texture2D
## Effect type that SpellReceivers filter on (e.g. &"force").
@export var effect_type: StringName = &"force"
@export var range: float = 18.0
@export var cooldown: float = 0.5
@export var projectile_speed: float = 28.0
@export var projectile_scene: PackedScene
## Generic magnitude passed to receivers (impulse for movable objects, etc).
@export var strength: float = 6.0
@export var aim_assist_angle_degrees: float = 7.0
@export var cast_sound: AudioStream
@export var impact_sound: AudioStream
@export var color: Color = Color(0.65, 0.5, 1.0)

class_name SpellEffect
extends RefCounted
## Payload delivered to a SpellReceiver when a spell connects.

var definition: SpellDefinition
var effect_type: StringName
## Node that cast the spell (may be null for cosmetic/remote casts).
var caster: Node
## Stable network identity of the caster ("" offline). Lets a future
## server-authoritative layer attribute effects to players.
var caster_id: String = ""
var hit_position: Vector3
var direction: Vector3
var strength: float = 0.0


static func create(def: SpellDefinition, p_caster: Node, p_caster_id: String, p_hit: Vector3, p_dir: Vector3) -> SpellEffect:
	var e := SpellEffect.new()
	e.definition = def
	e.effect_type = def.effect_type
	e.caster = p_caster
	e.caster_id = p_caster_id
	e.hit_position = p_hit
	e.direction = p_dir
	e.strength = def.strength
	return e

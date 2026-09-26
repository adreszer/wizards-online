class_name SpellReceiver
extends Node
## Composition component: makes its parent (a PhysicsBody3D/Area3D) react to spells.
##
## The receiver knows nothing about doors or statues; it only validates the
## effect type and emits [signal spell_received]. The owning object's script
## connects to that signal and decides what to do.

signal spell_received(effect: SpellEffect)

## Empty = accepts any effect type.
@export var accepted_effect_types: Array[StringName] = []
@export var enabled: bool = true
## Offset from the parent's origin used as the aim-assist target point.
@export var aim_point_offset: Vector3 = Vector3.ZERO
## Players will eventually be receivers too; this marks non-environment targets.
@export var is_character: bool = false

var _parent_3d: Node3D


func _ready() -> void:
	var parent := get_parent()
	parent.set_meta("spell_receiver", self)
	_parent_3d = parent as Node3D
	add_to_group("spell_receivers")


func can_receive(effect_type: StringName) -> bool:
	if not enabled:
		return false
	return accepted_effect_types.is_empty() or accepted_effect_types.has(effect_type)


## Returns true when the effect was accepted.
func receive(effect: SpellEffect) -> bool:
	if not can_receive(effect.effect_type):
		return false
	spell_received.emit(effect)
	return true


func get_aim_point() -> Vector3:
	if _parent_3d == null:
		return Vector3.ZERO
	return _parent_3d.global_transform * aim_point_offset


## Finds the receiver attached to a collider, or null.
static func find_on(node: Object) -> SpellReceiver:
	if node == null or not (node is Node):
		return null
	var n := node as Node
	if n.has_meta("spell_receiver"):
		return n.get_meta("spell_receiver") as SpellReceiver
	return null

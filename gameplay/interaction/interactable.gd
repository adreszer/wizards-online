class_name Interactable
extends Node
## Composition component: makes its parent (a CollisionObject3D on the
## "interactable" layer) usable via the Interact action.
##
## The object's own script connects to [signal interacted] to do the work
## (open a door, show plaque text, grant a spell...).

signal interacted(interactor: Node)
signal focus_changed(focused: bool)

## Translation key shown in the HUD prompt (the HUD calls tr() on it).
@export var prompt_text: String = "INTERACT_DEFAULT"
@export var enabled: bool = true
@export var one_shot: bool = false
@export var focus_point_offset: Vector3 = Vector3(0, 0.5, 0)

var is_focused: bool = false
var _parent_3d: Node3D
var _used: bool = false


func _ready() -> void:
	var parent := get_parent()
	parent.set_meta("interactable", self)
	_parent_3d = parent as Node3D
	add_to_group("interactables")


func can_interact() -> bool:
	return enabled and not (one_shot and _used)


func interact(interactor: Node) -> bool:
	if not can_interact():
		return false
	_used = true
	interacted.emit(interactor)
	return true


func set_focused(focused: bool) -> void:
	if is_focused == focused:
		return
	is_focused = focused
	focus_changed.emit(focused)


func get_focus_point() -> Vector3:
	if _parent_3d == null:
		return Vector3.ZERO
	return _parent_3d.global_transform * focus_point_offset


static func find_on(node: Object) -> Interactable:
	if node == null or not (node is Node):
		return null
	var n := node as Node
	if n.has_meta("interactable"):
		return n.get_meta("interactable") as Interactable
	return null

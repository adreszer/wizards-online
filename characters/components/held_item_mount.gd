class_name HeldItemMount
extends Node
## Player component that shows the held item in the character's off hand.
## Local players feed it from their Inventory, remote players from the
## replicated held-item id; either way only [method show_item] is called.
## Light sources carried by players are ordinary children of the held scene,
## so the lighting overhaul ("only light sources emit light") needs nothing
## beyond a scene with a light in it.

signal item_shown(definition: ItemDefinition)

## The hand node the held scene is parented to (an `OffHand` BoneAttachment3D
## or Marker3D inside the character visual).
var attachment: Node3D
var current_item: ItemDefinition
var current_node: Node3D


func setup(p_attachment: Node3D) -> void:
	attachment = p_attachment
	# Re-parent the visual if the body was swapped after we were set up.
	if current_item != null:
		var item := current_item
		current_item = null
		show_item(item)


## null clears the hand.
func show_item(definition: ItemDefinition) -> void:
	if definition == current_item:
		return
	if current_node != null:
		current_node.queue_free()
		current_node = null
	current_item = definition
	if definition != null and definition.held_scene != null and attachment != null:
		current_node = definition.held_scene.instantiate() as Node3D
		attachment.add_child(current_node)
	item_shown.emit(definition)


func is_holding() -> bool:
	return current_item != null

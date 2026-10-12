class_name WorldObjectSync
extends Node
## Keeps the level's world objects (group `world_objects`, keyed by
## `object_id`) in step with the server. While the local player is in the
## shared world, objects hand their triggers to [method request] instead of
## changing themselves; the server validates the event and every client,
## the sender included, applies the answer through the object's
## `apply_world_state(state, instant)`. Offline [method request] returns false
## and objects act on local triggers as before.
##
## Added by the level (see castle.gd). Physics objects (pushable blocks,
## pressure plates) and per-player checks (house doors) are not synced.

## object id → node with apply_world_state()
var _objects: Dictionary = {}


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(&"world_objects"):
		var oid := str(node.get(&"object_id"))
		if not oid.is_empty() and node.has_method(&"apply_world_state"):
			_objects[oid] = node
	NetworkManager.object_state_changed.connect(_on_object_state)
	NetworkManager.world_snapshot_received.connect(_on_snapshot)
	if NetworkManager.is_in_world():
		_on_snapshot(NetworkManager.get_world_object_states())


## Number of objects that follow the server.
func synced_count() -> int:
	return _objects.size()


## True when `obj` follows the server right now (it has an id and the local
## player is in the shared world).
static func is_synced(obj: Node) -> bool:
	return not str(obj.get(&"object_id")).is_empty() and NetworkManager.is_in_world()


## Called by an object when a local trigger fires. Online it sends the event
## to the server and returns true: the object must then wait for the server's
## state instead of changing itself. Offline (or without an id) returns false.
static func request(obj: Node, event: String, effect: SpellEffect = null) -> bool:
	if not is_synced(obj):
		return false
	var spell_id := ""
	if effect != null and effect.definition != null:
		spell_id = str(effect.definition.id)
	elif event == "spell":
		return true # nothing the server could validate; ignore the hit
	NetworkManager.send_world_event(str(obj.get(&"object_id")), event, spell_id)
	return true


## Tells the server about an event that also acts locally (reading a plaque):
## mysteries may count it, but nothing waits for an answer.
static func report(obj: Node, event: String) -> void:
	if is_synced(obj):
		NetworkManager.send_world_event(str(obj.get(&"object_id")), event)


func _on_object_state(object_id: String, state: Variant) -> void:
	var node: Node = _objects.get(object_id)
	if node != null and is_instance_valid(node):
		node.apply_world_state(state, false)


## A snapshot lists only objects off their default, so every other object is
## put back to its default (e.g. after a server restart).
func _on_snapshot(objects: Dictionary) -> void:
	for oid: String in _objects:
		var node: Node = _objects[oid]
		if is_instance_valid(node):
			node.apply_world_state(objects.get(oid), true)

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
##
## Offline it runs the public practice mysteries (OfflineMysteryEngine): the
## objects they drive (the secret walls) hand their triggers to the engine
## instead of opening on any hit; the real mysteries are server-only.

## The running offline engine, while a level plays offline.
static var _offline: OfflineMysteryEngine = null

## object id → node with apply_world_state()
var _objects: Dictionary = {}
var offline_engine: OfflineMysteryEngine


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(&"world_objects"):
		var oid := str(node.get(&"object_id"))
		if not oid.is_empty() and node.has_method(&"apply_world_state"):
			_objects[oid] = node
	NetworkManager.object_state_changed.connect(_on_object_state)
	NetworkManager.world_snapshot_received.connect(_on_snapshot)
	if NetworkManager.is_in_world():
		_on_snapshot(NetworkManager.get_world_object_states())
	else:
		offline_engine = OfflineMysteryEngine.new()
		offline_engine.name = "OfflineMysteries"
		add_child(offline_engine)
		offline_engine.setup(_objects)
		_offline = offline_engine


func _exit_tree() -> void:
	if _offline == offline_engine:
		_offline = null


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
		return _offline_request(obj, event, effect)
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
	else:
		_offline_request(obj, event, null)


## Offline: the practice engine hears every event of an object with an id and
## takes over the ones it drives (returns true for those).
static func _offline_request(obj: Node, event: String, effect: SpellEffect) -> bool:
	var oid := str(obj.get(&"object_id"))
	if _offline == null or not is_instance_valid(_offline) or oid.is_empty():
		return false
	_offline.report(oid, event, str(effect.effect_type) if effect != null else "")
	return _offline.drives(oid)


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

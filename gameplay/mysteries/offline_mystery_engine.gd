class_name OfflineMysteryEngine
extends Node
## Offline practice mysteries (content/offline_mysteries.json). With no server
## there are no real mysteries, which stay server-only (nakama/content/); this
## small public set keeps the castle's secret passages solvable offline with
## their own, simpler solutions. Same format as the server's mysteries for the
## step kinds that make sense alone: "spell" (object, effect_type?, state?),
## "interact" (object) and "enter" (area, holding?), with within_seconds and
## reset_on_wrong. Text keys are ordinary translation keys (OFFLINE_MYST_*).
##
## Objects named in an on_solved.set_state are driven by the engine: their
## local triggers come here instead of changing them (see WorldObjectSync).

const CONTENT_PATH := "res://content/offline_mysteries.json"
## Offline versions of the secrets generated with the castle (tools/castle/secrets.py).
const GENERATED_PATH := "res://content/castle/generated_offline_mysteries.json"

## object id → node, for applying states and reading a statue's state
var objects: Dictionary = {}
## object ids only the engine may change
var driven: Dictionary = {}
var _mysteries: Array = []
## mystery id → {step, at, solved}
var _progress: Dictionary = {}


func setup(p_objects: Dictionary, path: String = CONTENT_PATH) -> void:
	objects = p_objects
	_mysteries.clear()
	driven.clear()
	for p in [path, GENERATED_PATH] if path == CONTENT_PATH else [path]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if not data is Dictionary:
			continue
		for m: Dictionary in data.get("mysteries", []):
			_mysteries.append(m)
			for oid: String in m.get("on_solved", {}).get("set_state", {}):
				driven[oid] = true


func _ready() -> void:
	GameEvents.area_entered.connect(func(area_id: StringName, _zone: Node) -> void: on_event({"event": "enter", "area": str(area_id)}))


func mystery_count() -> int:
	return _mysteries.size()


func drives(object_id: String) -> bool:
	return driven.has(object_id)


## Spell hits and interactions arrive here; the object's state is read a frame
## later, after a non-driven object (a statue) has applied the hit itself.
func report(object_id: String, event: String, effect_type: String = "") -> void:
	_deferred_event.call_deferred({"event": event, "object": object_id, "effect_type": effect_type})


func _deferred_event(ev: Dictionary) -> void:
	var node: Node = objects.get(ev["object"])
	if node != null and "state" in node:
		ev["state"] = node.get("state")
	on_event(ev)


func on_event(ev: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	ev["held"] = _held_item()
	for m: Dictionary in _mysteries:
		var id := str(m.get("id", ""))
		var record: Dictionary = _progress.get(id, {"step": 0, "at": 0.0, "solved": false})
		_progress[id] = record
		if record["solved"]:
			continue
		var steps: Array = m.get("steps", [])
		if steps.is_empty():
			continue
		var step: Dictionary = steps[record["step"]]
		if record["step"] > 0 and step.has("within_seconds") and now - float(record["at"]) > float(step["within_seconds"]):
			record["step"] = 0
			step = steps[0]
		if _matches(step, ev):
			record["step"] += 1
			record["at"] = now
			if step.has("text"):
				if record["step"] < steps.size():
					GameEvents.mystery_cue.emit("clue")
				GameEvents.notification_requested.emit(tr(str(step["text"])), 6.0)
			if record["step"] >= steps.size():
				record["solved"] = true
				_solve(m)
		elif record["step"] > 0 and bool(m.get("reset_on_wrong", false)) and _touches(m, ev):
			record["step"] = 0


func _matches(step: Dictionary, ev: Dictionary) -> bool:
	match str(step.get("event", "")):
		"spell":
			return ev["event"] == "spell" and ev.get("object") == step.get("object") \
				and (not step.has("effect_type") or step["effect_type"] == ev.get("effect_type")) \
				and (not step.has("state") or int(step["state"]) == int(ev.get("state", -1)))
		"interact":
			return ev["event"] == "interact" and ev.get("object") == step.get("object")
		"enter":
			return ev["event"] == "enter" and ev.get("area") == step.get("area") \
				and (not step.has("holding") or step["holding"] == ev.get("held"))
	return false


func _touches(m: Dictionary, ev: Dictionary) -> bool:
	for step: Dictionary in m.get("steps", []):
		if (ev.has("object") and step.get("object") == ev["object"]) or (ev["event"] == "enter" and step.get("area") == ev.get("area")):
			return true
	return false


func _solve(m: Dictionary) -> void:
	GameEvents.mystery_cue.emit("solved")
	var solved: Dictionary = m.get("on_solved", {})
	for oid: String in solved.get("set_state", {}):
		var node: Node = objects.get(oid)
		if node != null and node.has_method(&"apply_world_state"):
			node.apply_world_state(solved["set_state"][oid], false)
	if solved.has("text"):
		GameEvents.notification_requested.emit(tr(str(solved["text"])), 6.0)


func _held_item() -> String:
	var player := get_tree().get_first_node_in_group(&"local_player") if is_inside_tree() else null
	if player == null or player.get("inventory") == null:
		return ""
	var held: ItemDefinition = player.inventory.held_item
	return str(held.id) if held != null else ""

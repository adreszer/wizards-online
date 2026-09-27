class_name AreaTracker
extends Node
## Local-player component: which named area (AreaZone) the player is in right
## now. Zones can nest (a greenhouse inside the grounds), so the innermost
## zone entered last wins and leaving it falls back to the enclosing one.
## Systems that need "where am I" (server area reports, lesson tools,
## proximity chat) read [member current_zone] or listen to [signal area_changed].

signal area_changed(zone: AreaZone)

var current_zone: AreaZone
var _stack: Array[AreaZone] = []


func _ready() -> void:
	GameEvents.area_entered.connect(_on_area_entered)
	GameEvents.area_exited.connect(_on_area_exited)


func current_area_id() -> StringName:
	return current_zone.area_id if current_zone != null else &""


func current_kind() -> String:
	return current_zone.kind if current_zone != null else ""


func _on_area_entered(_id: StringName, zone: Node) -> void:
	var z := zone as AreaZone
	if z == null:
		return
	_stack.erase(z)
	_stack.append(z)
	_update()


func _on_area_exited(_id: StringName, zone: Node) -> void:
	_stack.erase(zone as AreaZone)
	_update()


func _update() -> void:
	_stack = _stack.filter(func(z: AreaZone) -> bool: return is_instance_valid(z))
	var top: AreaZone = _stack.back() if not _stack.is_empty() else null
	if top == current_zone:
		return
	current_zone = top
	area_changed.emit(current_zone)

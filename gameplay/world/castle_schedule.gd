class_name CastleSchedule
extends Node
## The castle shifts on a schedule everyone shares: some doors follow the days and the
## night instead of the students. The globe room opens only on Wednesdays; by night the
## map room's door opens and the old cells' door shuts (the corridors swap their way
## through), by day the other way round. Online the server drives these doors (exported to
## generated/castle_schedule.lua, features/shifting.lua), so players cannot hold them; offline
## this node applies the same schedule. castle.gd adds it. Rotating stairs and trick steps
## (objects/setpieces) shift on their own timers.

## oid → {days: school weekdays it is open (0 = Monday)} | {night: true (open at night) | false (open by day)}
const DOORS := {
	"globe_room/door_1": {"days": [2]},
	"map_room/door_1": {"night": true},
	"old_cells/door_1": {"night": false},
}
const NIGHT_FROM := 20.0
const NIGHT_UNTIL := 6.0

var _timer := 0.0


static func is_night(hours: float) -> bool:
	var h := fposmod(hours, 24.0)
	return h >= NIGHT_FROM or h < NIGHT_UNTIL


## Whether scheduled door `oid` stands open on school weekday `weekday` at school `hours`.
static func open_at(oid: String, weekday: int, hours: float) -> bool:
	var rule: Dictionary = DOORS.get(oid, {})
	if rule.has("days"):
		return (rule.days as Array).has(weekday)
	if rule.has("night"):
		return is_night(hours) == bool(rule.night)
	return false


func _process(delta: float) -> void:
	if NetworkManager.is_in_world():
		return   # the server's states arrive as world object updates
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	var weekday: int = Time.get_datetime_dict_from_system().weekday
	weekday = posmod(weekday - 1, 7)   # Godot: 0 = Sunday; the school counts from Monday
	var hours := NetworkManager.school_hours()
	for node in get_tree().get_nodes_in_group(&"world_objects"):
		var oid := str(node.get(&"object_id"))
		if DOORS.has(oid) and node is CastleDoor:
			(node as CastleDoor).set_open(open_at(oid, weekday, hours))

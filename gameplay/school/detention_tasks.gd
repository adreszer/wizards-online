class_name DetentionTasks
extends Node
## Shows the local student's detention: the task's spots in its room (InteractSpot,
## one per chore), a HUD-style hint while they are in detention, and the request for
## each chore done. The server ("detention" feature) owns the task and counts the
## spots; this only draws and asks. castle.gd adds it.

const COLOR_TODO := Color(0.95, 0.75, 0.3)
const COLOR_DONE := Color(0.4, 0.85, 0.5)

var spots: Array[InteractSpot] = []
var _zones: Dictionary = {}
var _view: Dictionary = {}


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		_zones[str((node as AreaZone).area_id)] = node
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "detention":
			show_detention(data))
	show_detention(NetworkManager.feature("detention"))


## Where the `count` chores of a room go: a ring on the floor, inside the walls.
static func spot_positions(zone_center: Vector3, zone_size: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var floor_y := zone_center.y - zone_size.y / 2.0 + 0.9
	for i in count:
		var a := TAU * float(i) / float(maxi(1, count)) + 0.4
		out.append(Vector3(zone_center.x + cos(a) * zone_size.x * 0.3, floor_y, zone_center.z + sin(a) * zone_size.z * 0.3))
	return out


func show_detention(view: Dictionary) -> void:
	var same_task := str(view.get("task", "")) == str(_view.get("task", "")) and spots.size() == int(view.get("spots", 0))
	_view = view
	if not same_task:
		for s in spots:
			s.queue_free()
		spots.clear()
	var zone := _zones.get(str(view.get("area", ""))) as AreaZone
	if view.is_empty() or zone == null:
		return
	var done: Array = view.get("done", []) if view.get("done", []) is Array else []
	if spots.is_empty():
		var at := spot_positions(zone.global_position, zone.size, int(view.get("spots", 0)))
		for i in at.size():
			var spot := InteractSpot.create("INTERACT_DETENTION_" + str(view.task).to_upper(), COLOR_TODO)
			spot.name = "DetentionSpot%d" % (i + 1)
			add_child(spot)
			spot.global_position = at[i]
			var index := i + 1
			spot.used.connect(func(_who: Node) -> void: work(index))
			spots.append(spot)
	for i in spots.size():
		var finished := done.has(float(i + 1)) or done.has(i + 1)
		spots[i].set_state(COLOR_DONE if finished else COLOR_TODO, not finished)


## Asks the server to count chore `index`.
func work(index: int) -> void:
	var r: Dictionary = await NetworkManager.request("detention_step", {"spot": index})
	if not r.ok:
		GameEvents.notify(NetworkManager.refusal_text(r.reason), 3.0, ToastStack.Kind.WARNING)

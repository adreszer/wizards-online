class_name ClassroomBoards
extends Node
## Writes on the classroom boards. Every classroom has a wall board (batched, so it
## has no node of its own: StaticBatch records where each one hangs); this adds a
## chalk-coloured Label3D on each writing face. While a lesson runs, the board shows
## what the professor wrote (OP_BOARD, carried in the lesson state); otherwise it
## shows the room's subject and the next lesson there. castle.gd adds it.

const WALL_BOARD := "res://objects/environment/props/wall_board.tscn"
## The writing face sits this far in front of the board's origin (its back face), along -Z.
const FACE_DEPTH := 0.29
const CHALK := Color(0.93, 0.93, 0.88)
const CHALK_DIM := Color(0.75, 0.78, 0.72, 0.75)
## Refresh rate of the idle text (the next lesson's time).
const IDLE_REFRESH := 5.0

## area id → Label3D
var labels: Dictionary = {}
var _timer := 0.0


func _ready() -> void:
	var level := get_parent()
	var zones: Array[AreaZone] = []
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		if (node as AreaZone).kind == "classroom":
			zones.append(node as AreaZone)
	for batch in get_tree().get_nodes_in_group(StaticBatch.GROUP):
		for xform: Transform3D in (batch as StaticBatch).boards:
			var zone := _zone_at(zones, xform.origin)
			if zone == null or labels.has(str(zone.area_id)):
				continue
			labels[str(zone.area_id)] = _make_label(xform, level)
	NetworkManager.lessons_changed.connect(func(_l: Dictionary) -> void: refresh())
	NetworkManager.timetable_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = IDLE_REFRESH
		refresh()


## Rewrites every board from the lessons and the timetable.
func refresh() -> void:
	var lessons := NetworkManager.get_lessons()
	for area: String in labels:
		var label: Label3D = labels[area]
		var text := board_text_for(area, lessons, NetworkManager.timetable, NetworkManager.server_time())
		label.text = text
		label.modulate = CHALK if lessons.has(area) else CHALK_DIM


## What the board in `area` shows: the professor's text during a lesson (the subject
## when they have written nothing yet), otherwise the subject and the next lesson.
static func board_text_for(area: String, lessons: Dictionary, timetable: Timetable, now: float) -> String:
	var def := SubjectRegistry.for_area(area)
	var subject: String = TranslationServer.translate(def.display_name) if def != null else ""
	if lessons.has(area):
		var written := str(lessons[area].get("board", ""))
		return written if written != "" else subject
	var lines := PackedStringArray([subject])
	for e in timetable.upcoming(now):
		if str(e.area) == area:
			lines.append(TranslationServer.translate("BOARD_NEXT_LESSON") % [TranslationServer.translate(timetable.day_key(e.t0)), timetable.clock_text(e.t0)])
			break
	return "\n".join(lines)


func _make_label(board: Transform3D, level: Node) -> Label3D:
	var label := Label3D.new()
	label.name = "BoardText"
	label.font_size = 56
	label.pixel_size = 0.0022
	label.outline_size = 0
	label.width = 1050.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.shaded = false
	label.modulate = CHALK_DIM
	level.add_child(label)
	# A Label3D faces its +Z; the board writes on its -Z side.
	label.global_transform = board * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -FACE_DEPTH))
	return label


static func _zone_at(zones: Array[AreaZone], p: Vector3) -> AreaZone:
	for zone in zones:
		var local := zone.global_transform.affine_inverse() * p
		var half := zone.size / 2.0 + Vector3(0.6, 0.6, 0.6)   # the board hangs on the wall, at the zone's edge
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return zone
	return null

class_name NoticeBoard
extends StaticBody3D
## A notice board in the entrance hall and the common rooms: the coming lessons
## from the timetable (NetworkManager.timetable) chalked on a wall board, the
## running one marked. Interacting opens the full week (GameEvents.timetable_requested).
## Placed by the castle generator (content/placements.json, kind notice_board);
## the origin is the board's back face, centred, writing face toward +Z.

## Lines on the board below the title.
@export var max_lines: int = 7
## Seconds between redraws (a lesson starting or ending changes the board).
@export var refresh_interval: float = 15.0

@onready var _interactable: Interactable = $Interactable
@onready var _label: Label3D = $Text
var _timer := 0.0


func _ready() -> void:
	_interactable.prompt_text = "INTERACT_READ_TIMETABLE"
	_interactable.interacted.connect(func(_by: Node) -> void: GameEvents.timetable_requested.emit())
	NetworkManager.timetable_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = refresh_interval
		refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


func refresh() -> void:
	_label.text = board_text(NetworkManager.timetable, NetworkManager.server_time(), max_lines)


## The board's text: a title, then "Mon 18:00  Charms" lines (the running one marked).
static func board_text(timetable: Timetable, now: float, lines: int) -> String:
	var out := PackedStringArray([TranslationServer.translate("TIMETABLE_TITLE"), ""])
	if not timetable.received:
		out.append(TranslationServer.translate("TIMETABLE_OFFLINE"))
		return "\n".join(out)
	var cal := timetable.calendar_line()
	if cal != "":
		out.insert(1, cal)
	var coming := timetable.upcoming(now, lines)
	if coming.is_empty():
		out.append(TranslationServer.translate("TIMETABLE_EMPTY"))
	for e in coming:
		var when := "%s %s" % [TranslationServer.translate(timetable.day_key(e.t0)), timetable.clock_text(e.t0)]
		if e.t0 <= now:
			when = TranslationServer.translate("TIMETABLE_NOW")
		out.append("%s   %s" % [when, Timetable.title_of(e)])
	return "\n".join(out)

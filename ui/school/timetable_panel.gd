class_name TimetablePanel
extends CanvasLayer
## The school week (NetworkManager.timetable): one block per day in school time,
## each entry with its hours, subject, room and professor; the running entry and
## the next one stand out. Opens from a NoticeBoard (GameEvents.timetable_requested)
## or the /plan chat command; closes with Esc or the button.
## While open it captures keyboard input and frees the mouse, like the map.

signal toggled(open: bool)

@onready var _root: Control = %Root
@onready var _text: RichTextLabel = %Text
@onready var _footer: Label = %Footer

var is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	%CloseButton.pressed.connect(close)
	GameEvents.timetable_requested.connect(open)
	NetworkManager.timetable_changed.connect(func() -> void:
		if is_open:
			refresh())


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open:
		return
	is_open = true
	UiSounds.play(&"panel_open")
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	_root.visible = false
	GameSession.ui_input_captured = false
	toggled.emit(false)


func refresh() -> void:
	var tt := NetworkManager.timetable
	var now := NetworkManager.server_time()
	_text.text = week_bbcode(tt, now, get_tree())
	_footer.text = tr("TIMETABLE_FOOTER") % tt.clock_text(now) if tt.received else ""


## The week as BBCode, grouped by school day.
static func week_bbcode(tt: Timetable, now: float, tree: SceneTree) -> String:
	if not tt.received:
		return TranslationServer.translate("TIMETABLE_OFFLINE")
	var entries := tt.upcoming(now)
	var out := PackedStringArray()
	var cal := tt.calendar_line()
	if cal != "":
		out.append("[i]%s[/i]" % _escape(cal))
		out.append("")
	if entries.is_empty():
		out.append(TranslationServer.translate("TIMETABLE_EMPTY"))
		return "\n".join(out)
	var next := tt.next_after(now)
	var day := -999999
	for e in entries:
		var st := tt.school_time(e.t0)
		if st.day != day:
			day = st.day
			if not out.is_empty():
				out.append("")
			out.append("[color=#d8b46a][b]%s[/b][/color]" % TranslationServer.translate(tt.day_key(e.t0) + "_LONG"))
		var line := "%s–%s   [b]%s[/b]   %s" % [tt.clock_text(e.t0), tt.clock_text(e.t1), _escape(Timetable.title_of(e)),
			_escape(Timetable.room_name(tree, str(e.area)))]
		if str(e.professor) != "":
			line += "   · " + _escape(TranslationServer.translate("TIMETABLE_PROFESSOR") % str(e.professor))
		if e.get("exam", false):
			line += "   [color=#e08a6a](%s)[/color]" % TranslationServer.translate("TIMETABLE_EXAM")
		if e.t0 <= now:
			line = "[color=#9fe07a]%s  %s[/color]" % [TranslationServer.translate("TIMETABLE_NOW"), line]
		elif not next.is_empty() and e.id == next.id and e.t0 == next.t0:
			line = "[color=#f0e2b0]%s  %s[/color]" % [TranslationServer.translate("TIMETABLE_NEXT"), line]
		out.append(line)
	return "\n".join(out)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

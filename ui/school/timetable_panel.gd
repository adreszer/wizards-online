class_name TimetablePanel
extends CanvasLayer
## The school week (NetworkManager.timetable): one block per day in school time,
## each entry with its hours, subject, room and professor; the running entry and
## the next one stand out. Opens from a NoticeBoard (GameEvents.timetable_requested)
## or the /plan chat command; closes with Esc or the seal. A parchment sheet
## (UiWindow) with the school clock in its status line. While open it captures
## keyboard input and frees the mouse, like the map. The same text fills the journal's
## timetable pages, so its colours are inks for paper.

signal toggled(open: bool)

const HALF := Vector2(400, 290)
## Inks for the week (on parchment): day headings, the running lesson, the next one, exams.
const INK_DAY := "#8a2e1c"
const INK_NOW := "#3d6a26"
const INK_NEXT := "#7a5418"
const INK_EXAM := "#8a2e1c"

var is_open := false
var card: UiWindow
var _text: RichTextLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = UiWindow.new(UiWindow.Family.PARCHMENT, false)
	card.centre(HALF)
	card.title_label.text = tr("TIMETABLE_TITLE")
	card.close_requested.connect(close)
	card.visible = false
	add_child(card)
	_text = RichTextLabel.new()
	_text.theme_type_variation = &"BookRichText"
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(_text)
	GameEvents.timetable_requested.connect(open)
	NetworkManager.timetable_changed.connect(func() -> void:
		if is_open:
			refresh())


func open() -> void:
	if is_open:
		return
	is_open = true
	UiSounds.play(&"panel_open")
	card.show_window()
	UiRouter.opened(self)
	refresh()
	toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	card.hide_window()
	UiRouter.closed(self)
	toggled.emit(false)


func refresh() -> void:
	var tt := NetworkManager.timetable
	var now := NetworkManager.server_time()
	_text.text = week_bbcode(tt, now, get_tree())
	card.status_label.text = tr("TIMETABLE_FOOTER") % tt.clock_text(now) if tt.received else ""


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
			out.append("[color=%s][b]%s[/b][/color]" % [INK_DAY, TranslationServer.translate(tt.day_key(e.t0) + "_LONG")])
		var line := "%s–%s   [b]%s[/b]   %s" % [tt.clock_text(e.t0), tt.clock_text(e.t1), _escape(Timetable.title_of(e)),
			_escape(Timetable.room_name(tree, str(e.area)))]
		if str(e.professor) != "":
			line += "   · " + _escape(TranslationServer.translate("TIMETABLE_PROFESSOR") % str(e.professor))
		if e.get("exam", false):
			line += "   [color=%s](%s)[/color]" % [INK_EXAM, TranslationServer.translate("TIMETABLE_EXAM")]
		if e.t0 <= now:
			line = "[color=%s]%s  %s[/color]" % [INK_NOW, TranslationServer.translate("TIMETABLE_NOW"), line]
		elif not next.is_empty() and e.id == next.id and e.t0 == next.t0:
			line = "[color=%s]%s  %s[/color]" % [INK_NEXT, TranslationServer.translate("TIMETABLE_NEXT"), line]
		out.append(line)
	return "\n".join(out)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

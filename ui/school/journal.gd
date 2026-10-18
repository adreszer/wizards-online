class_name Journal
extends CanvasLayer
## The school journal (J): the character's year and house, then tabs for the week's
## timetable, the spellbook (mastery rank, points to the next, the spell's rune), the
## school record per subject (attendance, self-study, quiz answers, practicals; read
## from the server with the school_record RPC), and discoveries. Online only shows
## the record; offline the record tab says it lives in the online school.

var is_open := false
var record: Dictionary = {}
var _player: Player
var _root: PanelContainer
var _header: Label
var _tabs: TabContainer
var _pages: Dictionary = {}
## Your homework list from the server, and the hand-in row.
var homework: Array = []
var _hw_pick: OptionButton
var _hw_text: LineEdit
var _hand_in_row: HBoxContainer
var _open_ids: Array[String] = []


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.local_player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	GameEvents.local_player_removed.connect(func(_p: Node) -> void:
		close()
		_player = null)
	_build()


func _build() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -430
	_root.offset_right = 430
	_root.offset_top = -300
	_root.offset_bottom = 300
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.13, 0.09, 0.96)   # leather
	style.border_color = Color(0.72, 0.56, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	_root.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_root.add_child(box)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 22)
	_header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	box.add_child(_header)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for key in ["JOURNAL_TAB_TIMETABLE", "JOURNAL_TAB_SPELLS", "JOURNAL_TAB_RECORD", "JOURNAL_TAB_HOMEWORK", "JOURNAL_TAB_HOUSE", "JOURNAL_TAB_CALENDAR", "JOURNAL_TAB_POST", "JOURNAL_TAB_DISCOVERIES"]:
		var page := RichTextLabel.new()
		page.name = tr(key)
		page.bbcode_enabled = true
		page.scroll_active = true
		page.add_theme_color_override("default_color", Color(0.93, 0.9, 0.82))
		_tabs.add_child(page)
		_pages[key] = page
	# Handing homework in: pick an open assignment, write, send.
	var hand_in := HBoxContainer.new()
	_hw_pick = OptionButton.new()
	_hw_pick.custom_minimum_size = Vector2(220, 0)
	hand_in.add_child(_hw_pick)
	_hw_text = LineEdit.new()
	_hw_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hw_text.placeholder_text = "HOMEWORK_ANSWER_PLACEHOLDER"
	_hw_text.max_length = 600
	hand_in.add_child(_hw_text)
	var send := Button.new()
	send.text = "HOMEWORK_HAND_IN"
	send.pressed.connect(_hand_in)
	hand_in.add_child(send)
	box.add_child(hand_in)
	_hand_in_row = hand_in
	var foot := Label.new()
	foot.text = "JOURNAL_FOOTER"
	foot.add_theme_font_size_override("font_size", 13)
	box.add_child(foot)
	_root.visible = false
	add_child(_root)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed("journal") and not GameSession.ui_input_captured and _player != null and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("journal")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	if NetworkManager.is_online():
		var answer: Dictionary = await NetworkManager.school_record()
		record = answer.get("record", {}) if answer.get("record", {}) is Dictionary else {}
		var hw: Dictionary = await NetworkManager.homework_list()
		homework = hw.get("homework", []) if hw.get("homework", []) is Array else []
		if is_open:
			refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameSession.ui_input_captured = false


func refresh() -> void:
	var profile := NetworkManager.get_local_profile()
	_header.text = header_text(profile, _player.house if _player != null else 0)
	(_pages["JOURNAL_TAB_TIMETABLE"] as RichTextLabel).text = TimetablePanel.week_bbcode(NetworkManager.timetable, NetworkManager.server_time(), get_tree())
	(_pages["JOURNAL_TAB_SPELLS"] as RichTextLabel).text = spells_bbcode(_player.spell_caster if _player != null else null)
	(_pages["JOURNAL_TAB_RECORD"] as RichTextLabel).text = record_bbcode(record) if NetworkManager.is_online() else tr("JOURNAL_RECORD_OFFLINE")
	(_pages["JOURNAL_TAB_DISCOVERIES"] as RichTextLabel).text = discoveries_bbcode(profile.get("discoveries", []))
	(_pages["JOURNAL_TAB_POST"] as RichTextLabel).text = post_bbcode(NetworkManager.dm_history)
	(_pages["JOURNAL_TAB_CALENDAR"] as RichTextLabel).text = EventReminders.calendar_bbcode(NetworkManager.timetable, NetworkManager.feature("events"),
		NetworkManager.feature("clubs"), NetworkManager.server_time()) if NetworkManager.is_online() else tr("JOURNAL_RECORD_OFFLINE")
	(_pages["JOURNAL_TAB_HOUSE"] as RichTextLabel).text = house_bbcode(NetworkManager.house_quests, NetworkManager.get_house_totals(), _player.house if _player != null else 0) + board_bbcode(NetworkManager.feature("house_board")) + wing_bbcode(NetworkManager.feature("wing")) if NetworkManager.is_online() else tr("JOURNAL_RECORD_OFFLINE")
	var now := NetworkManager.server_time()
	(_pages["JOURNAL_TAB_HOMEWORK"] as RichTextLabel).text = homework_bbcode(homework, now) if NetworkManager.is_online() else tr("JOURNAL_RECORD_OFFLINE")
	_hw_pick.clear()
	_open_ids.clear()
	for h: Dictionary in homework:
		var answer: Variant = h.get("answer")
		if float(h.get("due", 0)) > now and not (answer is Dictionary and answer.has("grade")):
			var def := SubjectRegistry.load_definition(str(h.get("subject", "")))
			_hw_pick.add_item(tr(def.display_name) if def != null else "?")
			_open_ids.append(str(h.get("id", "")))
	_hand_in_row.visible = not _open_ids.is_empty()


func _hand_in() -> void:
	if _hw_pick.selected < 0 or _hw_pick.selected >= _open_ids.size() or _hw_text.text.strip_edges() == "":
		return
	var answer: Dictionary = await NetworkManager.homework_submit(_open_ids[_hw_pick.selected], _hw_text.text.strip_edges())
	GameEvents.notification_requested.emit(tr("HOMEWORK_HANDED_IN") if not answer.has("error") else tr("HOMEWORK_REFUSED") % str(answer.error), 4.0)
	if not answer.has("error"):
		_hw_text.text = ""
		var hw: Dictionary = await NetworkManager.homework_list()
		homework = hw.get("homework", []) if hw.get("homework", []) is Array else []
		if is_open:
			refresh()


## The house page: this week's quests with every house's progress (ours first), and the tally.
static func house_bbcode(quests: Dictionary, totals: PackedInt32Array, house: int) -> String:
	var out := PackedStringArray()
	var list: Array = quests.get("quests", []) if quests.get("quests", []) is Array else []
	if list.is_empty():
		out.append(TranslationServer.translate("QUEST_NONE"))
	for q: Dictionary in list:
		out.append("[b]%s[/b]  (+%d)" % [TranslationServer.translate(str(q.get("name_key", ""))) % int(q.get("target", 0)), int(q.get("points", 0))])
		var order: Array = [house] if house > 0 else []
		for h in range(1, 5):
			if h != house:
				order.append(h)
		for h: int in order:
			var progress := int((q.get("progress", []) as Array)[h - 1]) if (q.get("progress", []) as Array).size() >= h else 0
			var done: bool = (q.get("done", []) as Array).size() >= h and q.done[h - 1] == true
			var line := "   %s: %d / %d%s" % [CharacterProfile.house_name(h), mini(progress, int(q.get("target", 0))), int(q.get("target", 0)), "  ✓" if done else ""]
			out.append("[b]%s[/b]" % line if h == house else line)
	if totals.size() == 4:
		out.append("")
		out.append(TranslationServer.translate("QUEST_TALLY") % [totals[0], totals[1], totals[2], totals[3]])
	return "\n".join(out)


## Each assignment: subject, the task, due date, your answer and grade.
## The post: direct messages (paper birds) this session, newest first.
static func post_bbcode(lines: Array) -> String:
	if lines.is_empty():
		return TranslationServer.translate("JOURNAL_POST_EMPTY")
	var out := PackedStringArray()
	for l: Variant in lines:
		var d: Dictionary = l
		var who := (TranslationServer.translate("JOURNAL_POST_TO") % str(d.get("to_name", ""))) if d.get("self", false) else str(d.get("name", ""))
		out.append("[b]%s[/b]%s: %s" % [who, " ✉" if d.get("mail", false) else "", str(d.get("text", ""))])
	return "\n".join(out)


## The Unfinished Wing's shared progress (the whole school opens it together).
static func wing_bbcode(wing: Dictionary) -> String:
	if wing.is_empty():
		return ""
	return "\n\n[b]%s[/b]\n%s" % [TranslationServer.translate("JOURNAL_WING"), TranslationServer.translate("WING_STATE_LINE") % [int(wing.get("opened", 0)),
		int(wing.get("doors", 0)), int(wing.get("points", 0)), int(wing.get("next", 0))]]


## The house board: the head of house's and prefects' posts, newest first.
static func board_bbcode(board: Dictionary) -> String:
	var posts: Variant = board.get("posts", [])
	var out := "\n\n[b]%s[/b]" % TranslationServer.translate("HOUSE_BOARD_TITLE")
	if str(board.get("head", "")) != "":
		out += "  " + TranslationServer.translate("HOUSE_BOARD_HEAD") % str(board.head)
	if not posts is Array or (posts as Array).is_empty():
		return out + "\n" + TranslationServer.translate("HOUSE_BOARD_EMPTY")
	for p: Dictionary in posts:
		out += "\n• %s [i]— %s[/i]" % [str(p.get("text", "")), str(p.get("by", ""))]
	return out


static func homework_bbcode(list: Array, now: float) -> String:
	if list.is_empty():
		return TranslationServer.translate("HOMEWORK_NONE")
	var out := PackedStringArray()
	for h: Dictionary in list:
		var def := SubjectRegistry.load_definition(str(h.get("subject", "")))
		var due := Time.get_datetime_dict_from_unix_time(int(h.get("due", 0)))
		var head := "[b]%s[/b] (%s) — %s" % [TranslationServer.translate(def.display_name) if def != null else "?", str(h.get("by_name", "")),
			TranslationServer.translate("HOMEWORK_DUE") % "%d.%02d" % [due.day, due.month]]
		var answer: Variant = h.get("answer")
		var state := TranslationServer.translate("HOMEWORK_TODO") if float(h.get("due", 0)) > now else TranslationServer.translate("HOMEWORK_MISSED")
		if answer is Dictionary:
			state = TranslationServer.translate("HOMEWORK_HANDED") if not answer.has("grade") else TranslationServer.translate("HOMEWORK_GRADED") % [int(answer.grade), str(answer.get("comment", ""))]
		out.append("%s\n   %s\n   [i]%s[/i]" % [head, str(h.get("text", "")).replace("[", "[lb]"), state])
	return "\n".join(out)


## "Second Circle · Phoenara" (year and house).
static func header_text(profile: Dictionary, house: int) -> String:
	var year := clampi(int(profile.get("year", 1)), 1, CharacterProfile.MAX_YEAR)
	var line := TranslationServer.translate("YEAR_%d" % year)
	if house > 0:
		line += " · " + CharacterProfile.house_name(house)
	return line


static func spells_bbcode(caster: SpellCaster) -> String:
	if caster == null or caster.known_spells.is_empty():
		return TranslationServer.translate("JOURNAL_NO_SPELLS")
	var out := PackedStringArray()
	for def: SpellDefinition in caster.known_spells:
		var points := int(caster.mastery.get(String(def.id), 0))
		var next := SpellMastery.to_next(points)
		var line := "[b]%s[/b] — %s" % [TranslationServer.translate(def.display_name), TranslationServer.translate(SpellMastery.level_key(points))]
		if next > 0:
			line += "  " + TranslationServer.translate("JOURNAL_MASTERY_NEXT") % next
		var rune := str(RuneTracer.RUNES.get(String(def.id), ""))
		if rune != "":
			line += "\n   " + TranslationServer.translate("JOURNAL_RUNE") % rune_arrows(rune)
		out.append(line)
	return "\n".join(out)


static func rune_arrows(rune: String) -> String:
	return rune.replace("U", "↑").replace("D", "↓").replace("L", "←").replace("R", "→")


## One line per subject with any record: attended, self-study, quiz answers right of
## total, practicals done.
static func record_bbcode(rec: Dictionary) -> String:
	var subjects: Dictionary = rec.get("subjects", {}) if rec.get("subjects", {}) is Dictionary else {}
	if subjects.is_empty():
		return TranslationServer.translate("JOURNAL_RECORD_EMPTY")
	var out := PackedStringArray()
	for id: String in subjects:
		var s: Dictionary = subjects[id]
		var def := SubjectRegistry.load_definition(id)
		var grade := SchoolGrades.grade(s)
		var grade_text: String = TranslationServer.translate("JOURNAL_GRADE") % grade if grade > 0 else TranslationServer.translate("JOURNAL_NO_GRADE")
		out.append("[b]%s[/b]  %s\n   %s" % [TranslationServer.translate(def.display_name) if def != null else id, grade_text,
			TranslationServer.translate("JOURNAL_RECORD_LINE") % [int(s.get("attended", 0)), int(s.get("self_study", 0)),
				int(s.get("quiz_right", 0)), int(s.get("quiz_total", 0)), int(s.get("practicals", 0))]
			+ (("\n   " + TranslationServer.translate("JOURNAL_HOMEWORK_LINE") % [int(s.homework_count), float(s.homework_points) / float(s.homework_count)]) if int(s.get("homework_count", 0)) > 0 else "")
			+ (("\n   " + TranslationServer.translate("JOURNAL_EXAM_LINE") % [int(s.exam_right), int(s.exam_total)]) if int(s.get("exam_total", 0)) > 0 else "")])
	return "\n".join(out)


static func discoveries_bbcode(list: Variant) -> String:
	var found: Array = (list as Array).filter(func(d: Variant) -> bool: return not str(d).begins_with("map:")) if list is Array else []
	var rooms: int = (list as Array).size() - found.size() if list is Array else 0
	if found.is_empty() and rooms == 0:
		return TranslationServer.translate("JOURNAL_NO_DISCOVERIES")
	return TranslationServer.translate("JOURNAL_DISCOVERIES") % [found.size(), rooms]

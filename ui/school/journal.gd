class_name Journal
extends CanvasLayer
## The school journal (J) as an open book (UiBook): the left page heads with the house
## crest, the year and house, and the chosen section's name; ribbon bookmarks pick the
## section (timetable, spellbook, school record, homework, house, calendar, post,
## discoveries), whose entries run over both pages (split_entries). The spellbook draws
## each spell as its roundel with mastery pips beside its rank and rune. The school
## record is read from the server (school_record RPC); offline, the online-only
## sections say they live in the online school. Homework is handed in from the foot of
## the right page.

const HALF := Vector2(540, 320)
const SECTIONS := ["JOURNAL_TAB_TIMETABLE", "JOURNAL_TAB_SPELLS", "JOURNAL_TAB_RECORD", "JOURNAL_TAB_HOMEWORK",
	"JOURNAL_TAB_HOUSE", "JOURNAL_TAB_CALENDAR", "JOURNAL_TAB_POST", "JOURNAL_TAB_DISCOVERIES"]

var is_open := false
var record: Dictionary = {}
## The section shown (index into SECTIONS).
var section := 0
var book: UiBook
var _player: Player
var _badge: HouseBadge
var _header: Label
var _section_title: Label
var _texts: Array[RichTextLabel] = []
var _spells: Array[VBoxContainer] = []
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
	book = UiBook.new()
	book.centre(HALF)
	book.close_requested.connect(close)
	book.tab_selected.connect(show_section)
	book.visible = false
	add_child(book)
	for key: String in SECTIONS:
		book.add_tab(tr(key))
	var head := UiBox.h(UiTokens.SPACE_3)
	_badge = HouseBadge.new(0, HouseBadge.Size.MEDIUM, false)
	head.add_child(_badge)
	_header = Label.new()
	_header.theme_type_variation = &"BookLabel"
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_header)
	book.left.add_child(head)
	_section_title = Label.new()
	_section_title.theme_type_variation = &"TitleLabel"
	book.left.add_child(_section_title)
	book.left.add_child(HSeparator.new())
	for column: VBoxContainer in [book.left, book.right]:
		var text := RichTextLabel.new()
		text.theme_type_variation = &"BookRichText"
		text.bbcode_enabled = true
		text.scroll_active = true
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(text)
		_texts.append(text)
		var spells := UiBox.v(UiTokens.SPACE_2)
		spells.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(spells)
		_spells.append(spells)
	# Handing homework in: pick an open assignment, write, send.
	_hand_in_row = UiBox.h(UiTokens.SPACE_2)
	_hw_pick = OptionButton.new()
	_hw_pick.custom_minimum_size = Vector2(150, 0)
	_hand_in_row.add_child(_hw_pick)
	_hw_text = LineEdit.new()
	_hw_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hw_text.placeholder_text = "HOMEWORK_ANSWER_PLACEHOLDER"
	_hw_text.max_length = 600
	_hand_in_row.add_child(_hw_text)
	var send := Button.new()
	send.text = "HOMEWORK_HAND_IN"
	send.pressed.connect(_hand_in)
	_hand_in_row.add_child(send)
	book.right.add_child(_hand_in_row)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed("journal") and not GameSession.ui_input_captured and _player != null and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("journal"):
		close()
	elif event.is_action_pressed("ui_page_down") or (event.is_action_pressed("ui_right") and not _hw_text.has_focus()):
		show_section(posmod(section + 1, SECTIONS.size()))
	elif event.is_action_pressed("ui_page_up") or (event.is_action_pressed("ui_left") and not _hw_text.has_focus()):
		show_section(posmod(section - 1, SECTIONS.size()))
	else:
		return
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	UiSounds.play(&"panel_open")
	book.show_book()
	UiRouter.opened(self)
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
	UiSounds.play(&"panel_close")
	book.hide_book()
	UiRouter.closed(self)


## Turns to section `index` (a bookmark, the arrow keys or PgUp/PgDn).
func show_section(index: int) -> void:
	if index == section:
		return
	var step := 1 if index > section else -1
	section = index
	book.select_tab(index)
	book.turn(step)
	refresh()


func refresh() -> void:
	var profile := NetworkManager.get_local_profile()
	var house := _player.house if _player != null else 0
	_badge.house = house
	_header.text = header_text(profile, house)
	var key: String = SECTIONS[section]
	_section_title.text = tr(key)
	var spellbook := key == "JOURNAL_TAB_SPELLS"
	for i in 2:
		_texts[i].visible = not spellbook
		_spells[i].visible = spellbook
	if spellbook:
		_fill_spellbook(_player.spell_caster if _player != null else null)
	else:
		var halves := split_entries(section_bbcode(key, profile, house))
		_texts[0].text = halves[0]
		_texts[1].text = halves[1]
	book.set_folios(section * 2 + 1, section * 2 + 2)
	var now := NetworkManager.server_time()
	_hw_pick.clear()
	_open_ids.clear()
	for h: Dictionary in homework:
		var answer: Variant = h.get("answer")
		if float(h.get("due", 0)) > now and not (answer is Dictionary and answer.has("grade")):
			var def := SubjectRegistry.load_definition(str(h.get("subject", "")))
			_hw_pick.add_item(tr(def.display_name) if def != null else "?")
			_open_ids.append(str(h.get("id", "")))
	_hand_in_row.visible = key == "JOURNAL_TAB_HOMEWORK" and not _open_ids.is_empty()


## The text of one section (all but the spellbook).
func section_bbcode(key: String, profile: Dictionary, house: int) -> String:
	var online := NetworkManager.is_online()
	match key:
		"JOURNAL_TAB_TIMETABLE":
			return TimetablePanel.week_bbcode(NetworkManager.timetable, NetworkManager.server_time(), get_tree())
		"JOURNAL_TAB_RECORD":
			return record_bbcode(record) if online else tr("JOURNAL_RECORD_OFFLINE")
		"JOURNAL_TAB_HOMEWORK":
			return homework_bbcode(homework, NetworkManager.server_time()) if online else tr("JOURNAL_RECORD_OFFLINE")
		"JOURNAL_TAB_HOUSE":
			return house_bbcode(NetworkManager.house_quests, NetworkManager.get_house_totals(), house) + board_bbcode(NetworkManager.feature("house_board")) \
				+ wing_bbcode(NetworkManager.feature("wing")) if online else tr("JOURNAL_RECORD_OFFLINE")
		"JOURNAL_TAB_CALENDAR":
			return EventReminders.calendar_bbcode(NetworkManager.timetable, NetworkManager.feature("events"),
				NetworkManager.feature("clubs"), NetworkManager.server_time()) if online else tr("JOURNAL_RECORD_OFFLINE")
		"JOURNAL_TAB_POST":
			return post_bbcode(NetworkManager.dm_history)
		"JOURNAL_TAB_DISCOVERIES":
			return discoveries_bbcode(profile.get("discoveries", []))
	return ""


## The spellbook: each known spell as its roundel (colour, icon, mastery pips) beside
## its name, rank and rune, half on each page.
func _fill_spellbook(caster: SpellCaster) -> void:
	for column in _spells:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	if caster == null or caster.known_spells.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"BookLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = tr("JOURNAL_NO_SPELLS")
		_spells[0].add_child(none)
		return
	var half := ceili(caster.known_spells.size() / 2.0)
	for i in caster.known_spells.size():
		var def: SpellDefinition = caster.known_spells[i]
		var points := int(caster.mastery.get(String(def.id), 0))
		var row := UiBox.h(UiTokens.SPACE_3)
		var slot := SpellSlot.new()
		slot.set_spell(def)
		slot.mastery = SpellMastery.level_of(points)
		slot.mastery_max = SpellMastery.THRESHOLDS.size() - 1
		slot.key_chip.visible = false
		slot.custom_minimum_size = Vector2(SpellSlot.SIZE, SpellSlot.SIZE)
		row.add_child(slot)
		var words := Label.new()
		words.theme_type_variation = &"BookLabel"
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.text = spell_line(def, points)
		row.add_child(words)
		_spells[0 if i < half else 1].add_child(row)


## "Name — rank (n to the next)" and the rune on a second line.
static func spell_line(def: SpellDefinition, points: int) -> String:
	var line := "%s — %s" % [TranslationServer.translate(def.display_name), TranslationServer.translate(SpellMastery.level_key(points))]
	var next := SpellMastery.to_next(points)
	if next > 0:
		line += "  " + TranslationServer.translate("JOURNAL_MASTERY_NEXT") % next
	var rune := str(RuneTracer.RUNES.get(String(def.id), ""))
	if rune != "":
		line += "\n" + TranslationServer.translate("JOURNAL_RUNE") % rune_arrows(rune)
	return line


## A section's text over the two pages: the entries (lines that start a new entry, not
## an indented continuation) split as evenly by lines as whole entries allow.
static func split_entries(text: String) -> PackedStringArray:
	var lines := text.split("\n")
	if lines.size() < 6:
		return PackedStringArray([text, ""])
	var best := 0
	var best_gap := lines.size()
	for i in range(1, lines.size()):
		if lines[i].begins_with(" ") or lines[i].strip_edges() == "" and i + 1 < lines.size() and lines[i + 1].begins_with(" "):
			continue
		var gap := absi(lines.size() - 2 * i)
		if gap < best_gap:
			best_gap = gap
			best = i
	if best == 0:
		return PackedStringArray([text, ""])
	return PackedStringArray(["\n".join(lines.slice(0, best)), "\n".join(lines.slice(best)).strip_edges(true, false)])


func _hand_in() -> void:
	if _hw_pick.selected < 0 or _hw_pick.selected >= _open_ids.size() or _hw_text.text.strip_edges() == "":
		return
	var answer: Dictionary = await NetworkManager.homework_submit(_open_ids[_hw_pick.selected], _hw_text.text.strip_edges())
	GameEvents.notify(tr("HOMEWORK_HANDED_IN") if not answer.has("error") else tr("HOMEWORK_REFUSED") % str(answer.error), 4.0, ToastStack.Kind.INFO, "homework")
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

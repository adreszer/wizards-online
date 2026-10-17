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
	for key in ["JOURNAL_TAB_TIMETABLE", "JOURNAL_TAB_SPELLS", "JOURNAL_TAB_RECORD", "JOURNAL_TAB_DISCOVERIES"]:
		var page := RichTextLabel.new()
		page.name = tr(key)
		page.bbcode_enabled = true
		page.scroll_active = true
		page.add_theme_color_override("default_color", Color(0.93, 0.9, 0.82))
		_tabs.add_child(page)
		_pages[key] = page
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
		out.append("[b]%s[/b]\n   %s" % [TranslationServer.translate(def.display_name) if def != null else id,
			TranslationServer.translate("JOURNAL_RECORD_LINE") % [int(s.get("attended", 0)), int(s.get("self_study", 0)),
				int(s.get("quiz_right", 0)), int(s.get("quiz_total", 0)), int(s.get("practicals", 0))]])
	return "\n".join(out)


static func discoveries_bbcode(list: Variant) -> String:
	var found: Array = (list as Array).filter(func(d: Variant) -> bool: return not str(d).begins_with("map:")) if list is Array else []
	var rooms: int = (list as Array).size() - found.size() if list is Array else 0
	if found.is_empty() and rooms == 0:
		return TranslationServer.translate("JOURNAL_NO_DISCOVERIES")
	return TranslationServer.translate("JOURNAL_DISCOVERIES") % [found.size(), rooms]

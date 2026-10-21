extends Node
## UI checks: every character the game can show (translations, server strings and
## non-ASCII literals in scripts) is drawn by the interface font, and every letter of
## the translations by the display and text fonts; and no screen under ui/ styles
## itself (style boxes, theme overrides, colour literals) outside ui/theme/ and
## ui/components/, except the files still waiting for their migration; and every
## translation key written as a literal in a script or scene exists. Run:
##   godot --headless --path . tests/check_ui.tscn

## Symbols only ever drawn in the interface font (bullets, arrows, marks); the display
## and text faces need not have them.
const UI_ONLY_SYMBOLS := "✕✓✗•●○◆◇▲▼◀▶←→↑↓★☆♪⌛⏳"

## Lines that style a control by hand, per file, still allowed while the screens move
## to the theme and the components (docs/ui.md, Milestone 65 onward). The list only
## shrinks: a file that gains one fails, a file that loses one must lower its entry.
const STYLE_ALLOWLIST := {
	"res://ui/chat/chat_panel.tscn": 3,
	"res://ui/common/feature_panel.gd": 1,
	"res://ui/debug/debug_overlay.gd": 3,
	"res://ui/debug/debug_overlay.tscn": 4,
	"res://ui/hud/hud.gd": 14,
	"res://ui/hud/hud.tscn": 18,
	"res://ui/inventory/inventory_panel.gd": 1,
	"res://ui/inventory/inventory_panel.tscn": 6,
	"res://ui/map/map_panel.tscn": 10,
	"res://ui/map/map_view.gd": 28,
	"res://ui/map/minimap.tscn": 5,
	"res://ui/menus/main_menu.tscn": 8,
	"res://ui/menus/pause_menu.tscn": 2,
	"res://ui/school/book_panel.gd": 7,
	"res://ui/school/character_creator.gd": 13,
	"res://ui/school/duel_hud.gd": 3,
	"res://ui/school/journal.gd": 7,
	"res://ui/school/professor_panel.tscn": 12,
	"res://ui/school/quiz_panel.gd": 8,
	"res://ui/school/sorting_panel.tscn": 9,
	"res://ui/school/timetable_panel.tscn": 7,
	"res://ui/social/clubs_panel.gd": 3,
	"res://ui/social/emote_menu.gd": 5,
	"res://ui/social/game_panel.gd": 3,
}
const STYLE_PATTERN := "add_theme_[a-z_]+_override|StyleBox(Flat|Texture|Line|Empty)\\.new\\(\\)|theme_override_|\\[sub_resource type=\"StyleBox|Color\\("

var _failures: int = 0


func _ready() -> void:
	var translated := _translation_chars()
	var everything := translated.duplicate()
	_add_text(everything, _server_strings())
	for path in _scripts("res://"):
		_add_text(everything, _non_ascii(FileAccess.get_file_as_string(path)))
	for path: String in [UiFonts.UI, UiFonts.UI_ITALIC, UiFonts.UI_MEDIUM, UiFonts.UI_BOLD]:
		_check(path, everything)
	var letters := {}
	for c: int in translated:
		if not UI_ONLY_SYMBOLS.contains(String.chr(c)):
			letters[c] = true
	for path: String in [UiFonts.DISPLAY, UiFonts.DISPLAY_BOLD, UiFonts.TEXT, UiFonts.TEXT_ITALIC, UiFonts.TEXT_BOLD]:
		_check(path, letters)
	_check_styles()
	_check_keys()
	if _failures == 0:
		print("UI_CHECK_OK: %d characters covered" % everything.size())
		get_tree().quit(0)
	else:
		print("UI_CHECK_FAILED: %d problems" % _failures)
		get_tree().quit(1)


func _check(path: String, chars: Dictionary) -> void:
	var font: Font = load(path)
	var missing := PackedStringArray()
	for c: int in chars:
		if c > 32 and not font.has_char(c):
			missing.append("%s (U+%04X)" % [String.chr(c), c])
	if not missing.is_empty():
		push_error("%s misses: %s" % [path, ", ".join(missing)])
		_failures += 1


## Every string literal shaped like a key (WORD_WORD…) in the game's scripts and scenes
## is a row of a translation table, so no screen can show a raw key. Keys built at run
## time ("ACTION_" + action) are checked by tests/run_tests.gd.
func _check_keys() -> void:
	var keys := {}
	for file in DirAccess.get_files_at("res://localization"):
		if file.ends_with(".csv"):
			var f := FileAccess.open("res://localization".path_join(file), FileAccess.READ)
			while not f.eof_reached():
				var row := f.get_csv_line()
				if not row.is_empty():
					keys[row[0]] = true
	var pattern := RegEx.create_from_string("\"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\"")
	var missing := {}
	for path in _scripts("res://"):
		if path.begins_with("res://tests/") or path.begins_with("res://tools/") or path.begins_with("res://nakama/"):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for m in pattern.search_all(lines[i]):
				if not keys.has(m.get_string(1)):
					missing[m.get_string(1)] = "%s:%d" % [path, i + 1]
	for key: String in missing:
		push_error("translation key %s (%s) is in no table under localization/" % [key, missing[key]])
	if not missing.is_empty():
		_failures += 1


func _check_styles() -> void:
	var pattern := RegEx.create_from_string(STYLE_PATTERN)
	for path in _scripts("res://ui"):
		if path.begins_with("res://ui/theme/") or path.begins_with("res://ui/components/"):
			continue
		var lines := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if pattern.search(line) != null:
				lines += 1
		var allowed: int = STYLE_ALLOWLIST.get(path, 0)
		if lines > allowed:
			push_error("%s styles controls by hand on %d lines (allowed %d): use the theme or a component" % [path, lines, allowed])
			_failures += 1
		elif lines < allowed:
			push_error("%s now has %d hand-styled lines: lower its STYLE_ALLOWLIST entry from %d" % [path, lines, allowed])
			_failures += 1
	for path: String in STYLE_ALLOWLIST:
		if not FileAccess.file_exists(path):
			push_error("STYLE_ALLOWLIST names a missing file: " + path)
			_failures += 1


func _translation_chars() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://localization/translations.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		for i in range(1, row.size()):
			_add_text(out, row[i])
	return out


func _server_strings() -> String:
	var text := ""
	var dir := DirAccess.open("res://nakama/content")
	for file in dir.get_files():
		if file.ends_with(".json"):
			text += FileAccess.get_file_as_string("res://nakama/content".path_join(file))
	return _non_ascii(text)


func _non_ascii(text: String) -> String:
	var out := ""
	for i in text.length():
		if text.unicode_at(i) > 127:
			out += text[i]
	return out


func _add_text(out: Dictionary, text: String) -> void:
	for i in text.length():
		out[text.unicode_at(i)] = true


func _scripts(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(path)
	for d in dir.get_directories():
		if not d.begins_with(".") and d != "addons" and d != "assets":
			out.append_array(_scripts(path.path_join(d)))
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(path.path_join(file))
	return out

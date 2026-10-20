extends Node
## UI checks: every character the game can show (translations, server strings and
## non-ASCII literals in scripts) is drawn by the interface font, and every letter of
## the translations by the display and text fonts. Run:
##   godot --headless --path . tests/check_ui.tscn

## Symbols only ever drawn in the interface font (bullets, arrows, marks); the display
## and text faces need not have them.
const UI_ONLY_SYMBOLS := "✕✓✗•●○◆◇▲▼◀▶←→↑↓★☆♪⌛⏳"

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
	if _failures == 0:
		print("UI_CHECK_OK: %d characters covered" % everything.size())
		get_tree().quit(0)
	else:
		print("UI_CHECK_FAILED: %d fonts miss characters" % _failures)
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

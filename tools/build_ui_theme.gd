extends SceneTree
## Writes the UI's font resources (ui/theme/fonts/*.tres, from UiFonts.SOURCES) and the
## project theme ui/theme/arcanum_theme.tres (set as gui/theme/custom). Run from the
## project root after changing fonts or theme values, and commit the output:
##   godot --headless --path . -s tools/build_ui_theme.gd

const THEME_PATH := "res://ui/theme/arcanum_theme.tres"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/theme/fonts"))
	for path: String in UiFonts.SOURCES:
		_save(_font(UiFonts.SOURCES[path]), path)
	_save(_theme(), THEME_PATH)
	quit(0)


func _font(source: Array) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(source[0])
	var fallbacks: Array[Font] = []
	for path: String in UiFonts.SYMBOL_FALLBACKS:
		fallbacks.append(load(path))
	f.fallbacks = fallbacks
	if int(source[1]) > 0:
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): int(source[1])}
	return f


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = load(UiFonts.UI)
	t.default_font_size = 16
	# Fira Sans already has generous line metrics; Godot's default adds 3 px more.
	t.set_constant("line_spacing", "Label", 0)
	t.set_constant("line_separation", "RichTextLabel", 0)
	t.set_font("bold_font", "RichTextLabel", load(UiFonts.UI_BOLD))
	t.set_font("italics_font", "RichTextLabel", load(UiFonts.UI_ITALIC))
	t.set_font("bold_italics_font", "RichTextLabel", load(UiFonts.UI_BOLD))
	# Display face: window titles, menu headings, area banners.
	_variation(t, "TitleLabel", "Label", {"font": UiFonts.DISPLAY}, {"font_size": 30})
	_variation(t, "BannerLabel", "Label", {"font": UiFonts.DISPLAY}, {"font_size": 64})
	# Reading face: books, the journal, lecture text, quiz questions.
	_variation(t, "BookLabel", "Label", {"font": UiFonts.TEXT}, {"font_size": 19})
	_variation(t, "BookRichText", "RichTextLabel", {"normal_font": UiFonts.TEXT, "italics_font": UiFonts.TEXT_ITALIC,
		"bold_font": UiFonts.TEXT_BOLD, "bold_italics_font": UiFonts.TEXT_BOLD},
		{"normal_font_size": 19, "italics_font_size": 19, "bold_font_size": 19, "bold_italics_font_size": 19})
	return t


func _variation(t: Theme, name: String, base: String, fonts: Dictionary, sizes: Dictionary) -> void:
	t.set_type_variation(name, base)
	for key: String in fonts:
		t.set_font(key, name, load(fonts[key]))
	for key: String in sizes:
		t.set_font_size(key, name, sizes[key])


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		quit(1)
	print("wrote ", path)

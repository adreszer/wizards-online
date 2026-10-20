extends SceneTree
## Writes the UI's font resources (ui/theme/fonts/*.tres, from UiFonts.SOURCES) and the
## two themes, both built from UiTokens:
## - ui/theme/arcanum_theme.tres: the project theme (gui/theme/custom), oak and brass;
## - ui/theme/parchment_theme.tres: set on a parchment surface's root control, it turns
##   everything inside into ink on paper (labels, buttons, fields, lists, tabs).
## Run from the project root after changing fonts or tokens, and commit the output:
##   godot --headless --path . -s tools/build_ui_theme.gd

const T := preload("res://ui/theme/ui_tokens.gd")
const THEME_PATH := "res://ui/theme/arcanum_theme.tres"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/theme/fonts"))
	for path: String in UiFonts.SOURCES:
		_save(_font(UiFonts.SOURCES[path]), path)
	_save(_oak_theme(), THEME_PATH)
	_save(_parchment_theme(), T.PARCHMENT_THEME)
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


# --- Oak & brass (project theme) ---

func _oak_theme() -> Theme:
	var t := Theme.new()
	t.default_font = load(UiFonts.UI)
	t.default_font_size = T.SIZE_BODY
	_fonts(t)
	_text_colors(t, T.CANDLE, T.CANDLE_SOFT)
	var focus := _focus(T.BRASS_BRIGHT)

	# Buttons and everything that looks like one.
	var normal := _box(T.OAK_RAISED, T.OAK_LINE, 1, T.RADIUS_SMALL, Vector2(14, 6))
	var hover := _box(T.OAK_HOVER, T.BRASS_DIM, 1, T.RADIUS_SMALL, Vector2(14, 6))
	var pressed := _box(T.OAK_PRESSED, T.BRASS, 1, T.RADIUS_SMALL, Vector2(14, 6))
	var disabled := _box(Color(T.OAK_RAISED, 0.5), Color(T.OAK_LINE, 0.5), 1, T.RADIUS_SMALL, Vector2(14, 6))
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button_styles(t, type, normal, hover, pressed, disabled, focus)
		_button_colors(t, type, T.CANDLE, T.BRASS_BRIGHT, T.BRASS_BRIGHT, T.CANDLE_DIM)
	for type in ["CheckBox", "CheckButton"]:
		var bare := _empty(Vector2(4, 4))
		var lit := _box(Color(T.OAK_HOVER, 0.6), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(4, 4))
		_button_styles(t, type, bare, lit, bare, bare, focus)
		_button_colors(t, type, T.CANDLE, T.BRASS_BRIGHT, T.CANDLE, T.CANDLE_DIM)
	t.set_color("font_color", "LinkButton", T.BRASS)
	t.set_color("font_hover_color", "LinkButton", T.BRASS_BRIGHT)
	t.set_color("font_pressed_color", "LinkButton", T.BRASS_BRIGHT)

	# Text fields.
	var field := _box(T.OAK_INSET, T.OAK_LINE, 1, T.RADIUS_SMALL, Vector2(8, 5))
	var field_focus := _box(T.OAK_INSET, T.BRASS, 1, T.RADIUS_SMALL, Vector2(8, 5))
	var field_read_only := _box(Color(T.OAK_INSET, 0.5), Color(T.OAK_LINE, 0.5), 1, T.RADIUS_SMALL, Vector2(8, 5))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field_read_only)
		_field_colors(t, type, T.CANDLE, T.CANDLE_SOFT, T.BRASS_BRIGHT, Color(T.BRASS, 0.35), T.CANDLE_DIM)

	# Panels, popups, tooltips.
	t.set_stylebox("panel", "Panel", _box(T.OAK, T.OAK_LINE, 1, T.RADIUS, Vector2.ZERO))
	t.set_stylebox("panel", "PanelContainer", _box(T.OAK, T.OAK_LINE, 1, T.RADIUS, Vector2.ZERO))
	var popup := _box(T.OAK_SOLID, T.BRASS_DIM, 1, T.RADIUS, Vector2(6, 6))
	popup.shadow_color = T.SHADOW
	popup.shadow_size = 8
	_popup(t, popup, _box(T.OAK_HOVER, Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(8, 4)), T.CANDLE, T.BRASS_BRIGHT, T.CANDLE_DIM, T.OAK_LINE)
	var tip := _box(T.OAK_SOLID, T.BRASS_DIM, 1, T.RADIUS_SMALL, Vector2(10, 6))
	tip.shadow_color = T.SHADOW
	tip.shadow_size = 6
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", T.CANDLE)
	t.set_font_size("font_size", "TooltipLabel", T.SIZE_HINT)

	# Tabs.
	_tabs(t, _box(T.OAK_RAISED, T.BRASS, 0, T.RADIUS_SMALL, Vector2(12, 5), [0, 2, 0, 0]),
		_box(Color(T.OAK_SOLID, 0.7), T.OAK_LINE, 0, T.RADIUS_SMALL, Vector2(12, 5)),
		_box(T.OAK_HOVER, T.BRASS_DIM, 0, T.RADIUS_SMALL, Vector2(12, 5), [0, 1, 0, 0]),
		_box(Color(T.OAK_SOLID, 0.6), T.OAK_LINE, 1, T.RADIUS, Vector2(8, 8)),
		T.BRASS_BRIGHT, T.CANDLE_SOFT, T.CANDLE, T.CANDLE_DIM, focus)

	# Lists and trees.
	_lists(t, _box(T.OAK_INSET, T.OAK_LINE, 1, T.RADIUS_SMALL, Vector2(4, 4)),
		_box(Color(T.BRASS, 0.22), T.BRASS_DIM, 1, T.RADIUS_SMALL, Vector2(4, 2)),
		_box(Color(T.OAK_HOVER, 0.8), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(4, 2)),
		T.CANDLE, T.BRASS_BRIGHT, T.OAK_LINE, focus)

	# Scroll bars, sliders, progress bars, separators.
	_scroll(t, Color(0, 0, 0, 0.25), T.BRASS_DIM, T.BRASS, T.BRASS_BRIGHT)
	_sliders(t, T.OAK_LINE, T.BRASS, T.BRASS_BRIGHT, focus)
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.35), T.OAK_LINE, 1, T.RADIUS_SMALL, Vector2(0, 4)))
	t.set_stylebox("fill", "ProgressBar", _box(T.BRASS, Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(0, 4)))
	t.set_color("font_color", "ProgressBar", T.CANDLE)
	t.set_color("font_outline_color", "ProgressBar", T.OAK_SOLID)
	t.set_constant("outline_size", "ProgressBar", 3)
	_separators(t, T.OAK_LINE)
	_windows(t, "ChromeWindow", T.OAK_SOLID, T.BRASS_DIM, T.CANDLE_SOFT, T.BRASS_BRIGHT, T.DANGER)
	return t


# --- Parchment & ink (sub-theme for paper surfaces) ---

func _parchment_theme() -> Theme:
	var t := Theme.new()
	_text_colors(t, T.INK, T.INK_SOFT)
	var focus := _focus(T.RUBRIC)
	var normal := _box(Color(T.INK, 0.06), Color(T.INK_SOFT, 0.55), 1, T.RADIUS_SMALL, Vector2(14, 6))
	var hover := _box(Color(T.INK, 0.12), T.INK_SOFT, 1, T.RADIUS_SMALL, Vector2(14, 6))
	var pressed := _box(Color(T.INK, 0.2), T.INK, 1, T.RADIUS_SMALL, Vector2(14, 6))
	var disabled := _box(Color(T.INK, 0.03), Color(T.INK_SOFT, 0.25), 1, T.RADIUS_SMALL, Vector2(14, 6))
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button_styles(t, type, normal, hover, pressed, disabled, focus)
		_button_colors(t, type, T.INK, T.RUBRIC, T.RUBRIC, Color(T.INK_SOFT, 0.55))
	for type in ["CheckBox", "CheckButton"]:
		var bare := _empty(Vector2(4, 4))
		var lit := _box(Color(T.INK, 0.07), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(4, 4))
		_button_styles(t, type, bare, lit, bare, bare, focus)
		_button_colors(t, type, T.INK, T.RUBRIC, T.INK, Color(T.INK_SOFT, 0.55))
		# The default box icons are drawn in white; tint them to ink.
		t.set_color("checkbox_checked_color", type, T.INK)
		t.set_color("checkbox_unchecked_color", type, T.INK_SOFT)
	t.set_color("font_color", "LinkButton", T.RUBRIC)
	t.set_color("font_hover_color", "LinkButton", T.INK)
	var field := _box(Color(T.PARCHMENT_EDGE, 0.12), Color(T.INK_SOFT, 0.45), 1, T.RADIUS_SMALL, Vector2(8, 5), [0, 0, 0, 2])
	var field_focus := _box(Color(T.PARCHMENT_EDGE, 0.16), T.RUBRIC, 1, T.RADIUS_SMALL, Vector2(8, 5), [0, 0, 0, 2])
	var field_read_only := _box(Color(T.PARCHMENT_EDGE, 0.06), Color(T.INK_SOFT, 0.25), 1, T.RADIUS_SMALL, Vector2(8, 5))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field_read_only)
		_field_colors(t, type, T.INK, Color(T.INK_SOFT, 0.75), T.RUBRIC, Color(T.RUBRIC, 0.25), Color(T.INK_SOFT, 0.6))
	var popup := _box(T.PARCHMENT, T.PARCHMENT_EDGE, 1, T.RADIUS, Vector2(6, 6))
	popup.shadow_color = Color(0, 0, 0, 0.35)
	popup.shadow_size = 8
	_popup(t, popup, _box(Color(T.INK, 0.1), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(8, 4)), T.INK, T.RUBRIC, Color(T.INK_SOFT, 0.55), Color(T.INK_SOFT, 0.35))
	_tabs(t, _box(Color(T.INK, 0.1), T.RUBRIC, 0, T.RADIUS_SMALL, Vector2(12, 5), [0, 2, 0, 0]),
		_box(Color(T.INK, 0.03), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(12, 5)),
		_box(Color(T.INK, 0.07), T.INK_SOFT, 0, T.RADIUS_SMALL, Vector2(12, 5), [0, 1, 0, 0]),
		_box(Color(T.INK, 0.04), Color(T.INK_SOFT, 0.3), 1, T.RADIUS, Vector2(8, 8)),
		T.RUBRIC, T.INK_SOFT, T.INK, Color(T.INK_SOFT, 0.5), focus)
	_lists(t, _box(Color(T.PARCHMENT_EDGE, 0.08), Color(T.INK_SOFT, 0.35), 1, T.RADIUS_SMALL, Vector2(4, 4)),
		_box(Color(T.RUBRIC, 0.14), Color(T.RUBRIC, 0.6), 1, T.RADIUS_SMALL, Vector2(4, 2)),
		_box(Color(T.INK, 0.07), Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(4, 2)),
		T.INK, T.RUBRIC, Color(T.INK_SOFT, 0.35), focus)
	_scroll(t, Color(T.INK, 0.08), Color(T.INK_SOFT, 0.5), T.INK_SOFT, T.INK)
	_sliders(t, Color(T.INK_SOFT, 0.35), T.RUBRIC, T.INK, focus)
	t.set_stylebox("background", "ProgressBar", _box(Color(T.INK, 0.08), Color(T.INK_SOFT, 0.4), 1, T.RADIUS_SMALL, Vector2(0, 4)))
	t.set_stylebox("fill", "ProgressBar", _box(T.RUBRIC, Color(0, 0, 0, 0), 0, T.RADIUS_SMALL, Vector2(0, 4)))
	t.set_color("font_color", "ProgressBar", T.INK)
	t.set_constant("outline_size", "ProgressBar", 0)
	_separators(t, Color(T.INK_SOFT, 0.35))
	_windows(t, "ParchmentWindow", T.PARCHMENT, T.PARCHMENT_EDGE, T.INK_SOFT, T.RUBRIC, T.RUBRIC)
	return t


# --- Shared pieces ---

## The UiWindow frame (`window`, a PanelContainer variation) and its parts, defined in
## both themes so a window and everything in it resolve from the theme it carries:
## WindowClose (the close control), WindowStatus (the line under the body, for answers
## and refusals) and WindowFooter (key hints).
func _windows(t: Theme, window: String, bg: Color, edge: Color, soft: Color, lit: Color, status: Color) -> void:
	t.set_type_variation(window, "PanelContainer")
	var frame := _box(bg, edge, 3, T.RADIUS, Vector2(T.SPACE_5, T.SPACE_4))
	frame.shadow_color = T.SHADOW
	frame.shadow_size = 14
	frame.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", window, frame)
	t.set_type_variation("WindowClose", "Button")
	var bare := _empty(Vector2(T.SPACE_2, T.SPACE_1))
	_button_styles(t, "WindowClose", bare, bare, bare, bare, _focus(lit))
	_button_colors(t, "WindowClose", soft, lit, lit, Color(soft, 0.4))
	t.set_font_size("font_size", "WindowClose", T.SIZE_LARGE)
	t.set_type_variation("WindowStatus", "Label")
	t.set_color("font_color", "WindowStatus", status)
	t.set_type_variation("WindowFooter", "Label")
	t.set_color("font_color", "WindowFooter", soft)
	t.set_font_size("font_size", "WindowFooter", T.SIZE_HINT)

func _fonts(t: Theme) -> void:
	t.set_font("bold_font", "RichTextLabel", load(UiFonts.UI_BOLD))
	t.set_font("italics_font", "RichTextLabel", load(UiFonts.UI_ITALIC))
	t.set_font("bold_italics_font", "RichTextLabel", load(UiFonts.UI_BOLD))
	# Fira Sans already has generous line metrics; Godot's default adds 3 px more.
	t.set_constant("line_spacing", "Label", 0)
	t.set_constant("line_separation", "RichTextLabel", 0)
	# Display face: window titles, menu headings, area banners.
	_variation(t, "TitleLabel", "Label", {"font": UiFonts.DISPLAY}, {"font_size": T.SIZE_TITLE})
	_variation(t, "BannerLabel", "Label", {"font": UiFonts.DISPLAY}, {"font_size": T.SIZE_BANNER})
	# Reading face: books, the journal, lecture text, quiz questions.
	_variation(t, "BookLabel", "Label", {"font": UiFonts.TEXT}, {"font_size": T.SIZE_READING})
	_variation(t, "BookRichText", "RichTextLabel", {"normal_font": UiFonts.TEXT, "italics_font": UiFonts.TEXT_ITALIC,
		"bold_font": UiFonts.TEXT_BOLD, "bold_italics_font": UiFonts.TEXT_BOLD},
		{"normal_font_size": T.SIZE_READING, "italics_font_size": T.SIZE_READING, "bold_font_size": T.SIZE_READING, "bold_italics_font_size": T.SIZE_READING})
	# Small grey hint lines ("Esc closes", key lists).
	_variation(t, "HintLabel", "Label", {}, {"font_size": T.SIZE_HINT})


func _text_colors(t: Theme, main: Color, soft: Color) -> void:
	t.set_color("font_color", "Label", main)
	t.set_color("default_color", "RichTextLabel", main)
	t.set_color("font_color", "HintLabel", soft)
	t.set_color("font_color", "TitleLabel", main)
	t.set_color("font_color", "BannerLabel", main)
	t.set_color("font_color", "BookLabel", main)
	t.set_color("default_color", "BookRichText", main)


func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)


func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_focus_color", type, normal)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, pressed)
	t.set_color("icon_hover_pressed_color", type, pressed)
	t.set_color("icon_focus_color", type, normal)
	t.set_color("icon_disabled_color", type, disabled)


func _field_colors(t: Theme, type: String, text: Color, placeholder: Color, caret: Color, selection: Color, read_only: Color) -> void:
	t.set_color("font_color", type, text)
	t.set_color("font_placeholder_color", type, placeholder)
	t.set_color("font_selected_color", type, text)
	t.set_color("font_readonly_color", type, read_only)
	t.set_color("caret_color", type, caret)
	t.set_color("selection_color", type, selection)
	t.set_color("clear_button_color", type, placeholder)
	t.set_color("clear_button_color_pressed", type, caret)


func _popup(t: Theme, panel: StyleBox, hover: StyleBox, text: Color, lit: Color, disabled: Color, line: Color) -> void:
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", lit)
	t.set_color("font_accelerator_color", "PopupMenu", disabled)
	t.set_color("font_disabled_color", "PopupMenu", disabled)
	t.set_color("font_separator_color", "PopupMenu", disabled)
	var sep := StyleBoxLine.new()
	sep.color = line
	sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", sep)


func _tabs(t: Theme, selected: StyleBox, unselected: StyleBox, hovered: StyleBox, panel: StyleBox, font_selected: Color, font_unselected: Color, font_hovered: Color, font_disabled: Color, focus: StyleBox) -> void:
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, selected)
		t.set_stylebox("tab_unselected", type, unselected)
		t.set_stylebox("tab_hovered", type, hovered)
		t.set_stylebox("tab_disabled", type, unselected)
		t.set_stylebox("tab_focus", type, focus)
		t.set_color("font_selected_color", type, font_selected)
		t.set_color("font_unselected_color", type, font_unselected)
		t.set_color("font_hovered_color", type, font_hovered)
		t.set_color("font_disabled_color", type, font_disabled)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_stylebox("tabbar_background", "TabContainer", _empty(Vector2.ZERO))


func _lists(t: Theme, panel: StyleBox, selected: StyleBox, hovered: StyleBox, text: Color, lit: Color, guide: Color, focus: StyleBox) -> void:
	for type in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, panel)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("selected", type, selected)
		t.set_stylebox("selected_focus", type, selected)
		t.set_stylebox("hovered", type, hovered)
		t.set_stylebox("cursor", type, _empty(Vector2.ZERO))
		t.set_stylebox("cursor_unfocused", type, _empty(Vector2.ZERO))
		t.set_color("font_color", type, text)
		t.set_color("font_selected_color", type, lit)
		t.set_color("font_hovered_color", type, lit)
		t.set_color("guide_color", type, guide)
	t.set_color("title_button_color", "Tree", text)
	t.set_color("relationship_line_color", "Tree", guide)


func _scroll(t: Theme, track: Color, grab: Color, grab_hover: Color, grab_pressed: Color) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var vertical: bool = type == "VScrollBar"
		var m := Vector2(4, 2) if vertical else Vector2(2, 4)
		t.set_stylebox("scroll", type, _box(track, Color(0, 0, 0, 0), 0, 4, m))
		t.set_stylebox("scroll_focus", type, _box(track, Color(0, 0, 0, 0), 0, 4, m))
		t.set_stylebox("grabber", type, _box(grab, Color(0, 0, 0, 0), 0, 4, m))
		t.set_stylebox("grabber_highlight", type, _box(grab_hover, Color(0, 0, 0, 0), 0, 4, m))
		t.set_stylebox("grabber_pressed", type, _box(grab_pressed, Color(0, 0, 0, 0), 0, 4, m))


func _sliders(t: Theme, track: Color, fill: Color, fill_hover: Color, focus: StyleBox) -> void:
	for type in ["HSlider", "VSlider"]:
		var m := Vector2(0, 3) if type == "HSlider" else Vector2(3, 0)
		t.set_stylebox("slider", type, _box(track, Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("grabber_area", type, _box(fill, Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("grabber_area_highlight", type, _box(fill_hover, Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("focus", type, focus)


func _separators(t: Theme, color: Color) -> void:
	for type in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = color
		line.thickness = 1
		line.vertical = type == "VSeparator"
		t.set_stylebox("separator", type, line)


func _variation(t: Theme, name: String, base: String, fonts: Dictionary, sizes: Dictionary) -> void:
	t.set_type_variation(name, base)
	for key: String in fonts:
		t.set_font(key, name, load(fonts[key]))
	for key: String in sizes:
		t.set_font_size(key, name, sizes[key])


## A flat box; `margin` is the content margin (x left/right, y top/bottom); `widths`
## overrides the border per side as [left, top, right, bottom].
func _box(bg: Color, border: Color, width: int, radius: int, margin: Vector2, widths: Array = []) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	if widths.is_empty():
		s.set_border_width_all(width)
	else:
		s.border_width_left = widths[0]
		s.border_width_top = widths[1]
		s.border_width_right = widths[2]
		s.border_width_bottom = widths[3]
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	s.anti_aliasing = true
	return s


func _empty(margin: Vector2) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s


## The keyboard/gamepad focus ring: an outline just outside the control.
func _focus(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(T.RADIUS)
	s.set_expand_margin_all(2)
	return s


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		quit(1)
	print("wrote ", path)

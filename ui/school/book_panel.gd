class_name BookPanel
extends CanvasLayer
## Reads a book (GameEvents.book_requested): the title, one page at a time, with page
## turning (buttons, A/D or the arrow keys). Esc closes.

var is_open := false
var pages: PackedStringArray = []
var page := 0
var _root: PanelContainer
var _title: Label
var _text: RichTextLabel
var _footer: Label


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.book_requested.connect(open)
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -360
	_root.offset_right = 360
	_root.offset_top = -260
	_root.offset_bottom = 260
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.85, 0.72, 0.98)   # parchment
	style.border_color = Color(0.45, 0.3, 0.16)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(26)
	_root.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_root.add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_color_override("font_color", Color(0.3, 0.18, 0.08))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_text = RichTextLabel.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", Color(0.18, 0.12, 0.07))
	_text.theme_type_variation = &"BookRichText"
	box.add_child(_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(func() -> void: turn(-1))
	row.add_child(prev)
	_footer = Label.new()
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.add_theme_color_override("font_color", Color(0.35, 0.25, 0.15))
	row.add_child(_footer)
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(func() -> void: turn(1))
	row.add_child(next)
	_root.visible = false
	add_child(_root)


func open(title_key: String, page_keys: PackedStringArray) -> void:
	pages = page_keys
	page = 0
	_title.text = tr(title_key)
	is_open = true
	UiSounds.play(&"panel_open")
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_page()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	_root.visible = false
	GameSession.ui_input_captured = false


func turn(step: int) -> void:
	page = clampi(page + step, 0, maxi(0, pages.size() - 1))
	_show_page()


func _show_page() -> void:
	_text.text = tr(pages[page]) if page < pages.size() else ""
	_footer.text = tr("BOOK_PAGE") % [page + 1, maxi(1, pages.size())]


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause"):
		close()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		turn(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		turn(-1)
	else:
		return
	get_viewport().set_input_as_handled()

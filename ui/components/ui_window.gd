class_name UiWindow
extends PanelContainer
## The one window frame every panel uses (docs/ui.md, "Components"): a framed card in
## one of the two families (parchment for reading surfaces and small school panels,
## chrome for menus and tools), a title row with the close control, a body the owner
## fills, a status line for answers and refusals, and a footer row for key hints.
## The look comes from the theme (ParchmentWindow / ChromeWindow and the Window*
## variations, written by tools/build_ui_theme.gd); this script only builds the layout
## and the open animation. Closing is the owner's job: the close control emits
## close_requested.

signal close_requested

enum Family { PARCHMENT, CHROME }

const SCALE_FROM := UiTokens.OPEN_SCALE_FROM

var family: Family = Family.PARCHMENT
var title_label: Label
var close_button: Button
## The owner's content goes here.
var body: VBoxContainer
var status_label: Label
## Key hints along the bottom; hidden while empty.
var footer: HBoxContainer
var _tween: Tween
var _closing := false
var _half := Vector2.ZERO


## `scrolls`: the body sits in a vertical scroll container (long lists); without it the
## body sizes the window.
func _init(window_family: Family = Family.PARCHMENT, scrolls: bool = true) -> void:
	family = window_family
	name = "Window"
	theme_type_variation = &"ChromeWindow" if family == Family.CHROME else &"ParchmentWindow"
	if family == Family.PARCHMENT:
		theme = load(UiTokens.PARCHMENT_THEME)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTokens.SPACE_2)
	add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.theme_type_variation = &"TitleLabel"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title_label)
	close_button = Button.new()
	close_button.name = "Close"
	# A wax seal (the theme's WindowClose styles); no text.
	close_button.theme_type_variation = &"WindowClose"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "UI_CLOSE"
	close_button.set_meta(&"ui_sound", &"")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close_button)
	outer.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scrolls:
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.add_child(body)
		outer.add_child(scroll)
	else:
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(body)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"WindowStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(status_label)
	footer = HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", UiTokens.SPACE_4)
	footer.visible = false
	outer.add_child(footer)


## Centres the window on screen at twice `half_size`, never larger than the screen
## less a margin (a small window or a large interface scale shrinks it; the body
## scrolls), and keeps it so when the screen changes.
func centre(half_size: Vector2) -> void:
	_half = half_size
	set_anchors_preset(Control.PRESET_CENTER)
	_fit()


func _fit() -> void:
	if _half == Vector2.ZERO:
		return
	var h := _half
	if is_inside_tree():
		h = h.min(get_viewport_rect().size / 2.0 - Vector2(UiTokens.SPACE_3, UiTokens.SPACE_3))
	offset_left = -h.x
	offset_right = h.x
	offset_top = -h.y
	offset_bottom = h.y


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		if not get_viewport().size_changed.is_connected(_fit):
			get_viewport().size_changed.connect(_fit)
		_fit()
	elif what == NOTIFICATION_EXIT_TREE and get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.disconnect(_fit)


## Adds a hint ("Esc  close") to the footer.
func add_hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"WindowFooter"
	footer.add_child(l)
	footer.visible = true
	return l


## Adds a key hint to the footer: the action's key chip and what it does ("[Esc] close").
func add_key_hint(action: StringName, verb: String) -> HBoxContainer:
	var row := KeyChip.hint_row(action, verb, &"WindowFooter")
	footer.add_child(row)
	footer.visible = true
	return row


## Shows the window with a short fade and settle (instant under reduced motion).
func show_window() -> void:
	if _tween != null:
		_tween.kill()
	_closing = false
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_tween = UiMotion.pop_in(self, UiTokens.NORMAL)


## Hides the window with a quick fade and shrink (instant under reduced motion); it
## stops taking input at once.
func hide_window() -> void:
	if _tween != null:
		_tween.kill()
	_closing = true
	# Nothing inside takes a click while it fades.
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_tween = UiMotion.pop_out(self, UiTokens.FAST)


## True while the window is open (false from the moment it starts closing).
func is_shown() -> bool:
	return visible and not _closing

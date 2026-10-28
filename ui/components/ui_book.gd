class_name UiBook
extends Control
## An open book (docs/ui.md, Milestone 69): the reading surface for the journal and the
## books found in the castle. A leather binding holds two parchment pages, `left` and
## `right` (the owner fills them), with a page number at the foot of each; ribbon
## bookmarks stick out past the right page when the owner adds tabs; a wax seal
## closes it. turn() plays the page turn: the sound, and the right page folding over
## from the spine (instant under reduced motion). Show and hide like a UiWindow.
## The look comes from the theme (BookCover, BookPageLeft/Right, BookTab).

signal close_requested
## A bookmark was chosen (index of add_tab).
signal tab_selected(index: int)

const SCALE_FROM := 0.97
const TURN_SECONDS := 0.22

var cover: PanelContainer
var left_page: PanelContainer
var right_page: PanelContainer
## The owners' content.
var left: VBoxContainer
var right: VBoxContainer
var left_folio: Label
var right_folio: Label
var close_button: Button
var tabs: VBoxContainer
var _frame: Control
var _group := ButtonGroup.new()
var _tween: Tween
var _turn_tween: Tween


func _init() -> void:
	name = "Book"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Control.new()
	_frame.name = "Frame"
	add_child(_frame)
	# The bookmarks first, so their roots tuck under the binding.
	tabs = UiBox.v(UiTokens.SPACE_1)
	tabs.name = "Tabs"
	tabs.anchor_left = 1.0
	tabs.anchor_right = 1.0
	tabs.offset_left = -UiTokens.SPACE_7
	tabs.offset_top = UiTokens.SPACE_7 + UiTokens.SPACE_4
	tabs.visible = false
	_frame.add_child(tabs)
	cover = PanelContainer.new()
	cover.name = "Cover"
	cover.theme_type_variation = &"BookCover"
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(cover)
	var spread := UiBox.h(0)
	spread.name = "Spread"
	cover.add_child(spread)
	var pair := _page(&"BookPageLeft")
	left_page = pair[0]
	left = pair[1]
	left_folio = pair[2]
	spread.add_child(left_page)
	pair = _page(&"BookPageRight")
	right_page = pair[0]
	right = pair[1]
	right_folio = pair[2]
	spread.add_child(right_page)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.theme_type_variation = &"WindowClose"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "UI_CLOSE"
	close_button.set_meta(&"ui_sound", &"")
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	close_button.position = Vector2(-UiTokens.SPACE_3, -UiTokens.SPACE_3)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	_frame.add_child(close_button)


## A page: the paper (in the parchment theme), its content column and its folio.
func _page(variation: StringName) -> Array:
	var paper := PanelContainer.new()
	paper.name = String(variation).trim_prefix("Book")
	paper.theme_type_variation = variation
	paper.theme = load(UiTokens.PARCHMENT_THEME)
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_stretch_ratio = 1.0
	paper.clip_contents = true
	var column := UiBox.v(UiTokens.SPACE_2)
	paper.add_child(column)
	var content := UiBox.v(UiTokens.SPACE_3)
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	var folio := Label.new()
	folio.name = "Folio"
	folio.theme_type_variation = &"HintLabel"
	folio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(folio)
	return [paper, content, folio]


## Centres the book on screen at twice `half_size` (the binding's outer size).
func centre(half_size: Vector2) -> void:
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -half_size.x
	_frame.offset_right = half_size.x
	_frame.offset_top = -half_size.y
	_frame.offset_bottom = half_size.y
	tabs.offset_right = tabs.offset_left + 190


## Adds a ribbon bookmark; the first one added starts selected. Returns its index.
func add_tab(text: String) -> int:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"BookTab"
	b.toggle_mode = true
	b.button_group = _group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.set_meta(&"ui_sound", &"")   # the page turns instead of a click
	var index := tabs.get_child_count()
	b.button_pressed = index == 0
	b.pressed.connect(func() -> void: tab_selected.emit(index))
	tabs.add_child(b)
	tabs.visible = true
	return index


## Marks bookmark `index` as chosen without emitting tab_selected.
func select_tab(index: int) -> void:
	# set_pressed_no_signal skips the button group, so the others are let go by hand.
	for i in tabs.get_child_count():
		(tabs.get_child(i) as Button).set_pressed_no_signal(i == index)


func tab_count() -> int:
	return tabs.get_child_count()


## "— 3 —" under each page; 0 hides a folio.
func set_folios(left_number: int, right_number: int) -> void:
	left_folio.text = "— %d —" % left_number if left_number > 0 else ""
	right_folio.text = "— %d —" % right_number if right_number > 0 else ""


## The page turn: its sound, and the right page folding in from the spine (`step` > 0
## forward, < 0 back: the left page folds instead).
func turn(step: int) -> void:
	UiSounds.play(&"book_page_turn")
	if GameSettings.get_value("reduce_motion") or not is_visible_in_tree():
		return
	if _turn_tween != null:
		_turn_tween.kill()
	var page := right_page if step >= 0 else left_page
	left_page.scale = Vector2.ONE
	right_page.scale = Vector2.ONE
	left_page.modulate.a = 1.0
	right_page.modulate.a = 1.0
	page.pivot_offset = Vector2(0.0 if page == right_page else page.size.x, page.size.y / 2.0)
	page.scale = Vector2(0.15, 1.0)
	page.modulate.a = 0.4
	_turn_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_property(page, "scale", Vector2.ONE, TURN_SECONDS)
	_turn_tween.tween_property(page, "modulate:a", 1.0, TURN_SECONDS * 0.8)


## Shows the book with a short fade and settle (instant under reduced motion).
func show_book() -> void:
	visible = true
	if _tween != null:
		_tween.kill()
	_frame.pivot_offset_ratio = Vector2(0.5, 0.5)
	if GameSettings.get_value("reduce_motion"):
		_frame.modulate.a = 1.0
		_frame.scale = Vector2.ONE
		return
	_frame.modulate.a = 0.0
	_frame.scale = Vector2(SCALE_FROM, SCALE_FROM)
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_frame, "modulate:a", 1.0, UiTokens.NORMAL)
	_tween.tween_property(_frame, "scale", Vector2.ONE, UiTokens.NORMAL)


func hide_book() -> void:
	if _tween != null:
		_tween.kill()
	_frame.modulate.a = 1.0
	_frame.scale = Vector2.ONE
	visible = false


## Empties both pages.
func clear_pages() -> void:
	for column: VBoxContainer in [left, right]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()

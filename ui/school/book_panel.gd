class_name BookPanel
extends CanvasLayer
## Reads a book (GameEvents.book_requested) as an open book (UiBook): the title heads
## the left page, two pages to a spread, the spread turned with A/D, the arrow keys or
## the page corners. Esc or the seal closes.

const HALF := Vector2(500, 300)

var is_open := false
var pages: PackedStringArray = []
## The left page of the open spread (0, 2, 4…).
var page := 0
var book: UiBook
var _title: Label
var _texts: Array[RichTextLabel] = []
var _prev: Button
var _next: Button


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.book_requested.connect(open)
	book = UiBook.new()
	book.centre(HALF)
	book.close_requested.connect(close)
	book.visible = false
	add_child(book)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	book.left.add_child(_title)
	for column: VBoxContainer in [book.left, book.right]:
		var text := RichTextLabel.new()
		text.theme_type_variation = &"BookRichText"
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.scroll_active = true
		column.add_child(text)
		_texts.append(text)
	# Turning by the page corners: a quiet arrow at the foot of each page.
	_prev = _corner("◀", -1, book.left)
	_next = _corner("▶", 1, book.right)


func _corner(glyph: String, step: int, column: VBoxContainer) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta(&"ui_sound", &"")   # the page turns instead of a click
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if step < 0 else Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void: turn(step))
	column.add_child(b)
	return b


func open(title_key: String, page_keys: PackedStringArray) -> void:
	pages = page_keys
	page = 0
	_title.text = tr(title_key)
	is_open = true
	UiSounds.play(&"panel_open")
	book.show_book()
	UiRouter.opened(self)
	_show_spread()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	book.hide_book()
	UiRouter.closed(self)


## Turns `step` spreads (two pages each) forward or back.
func turn(step: int) -> void:
	var before := page
	page = clampi(page + 2 * step, 0, maxi(0, (pages.size() - 1) / 2 * 2))
	if page != before:
		book.turn(step)
	_show_spread()


func _show_spread() -> void:
	_title.visible = page == 0
	for i in 2:
		var at := page + i
		_texts[i].text = tr(pages[at]) if at < pages.size() else ""
	book.set_folios(page + 1, page + 2 if page + 1 < pages.size() else 0)
	_prev.disabled = page == 0
	_next.disabled = page + 2 >= pages.size()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		turn(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		turn(-1)
	else:
		return
	get_viewport().set_input_as_handled()

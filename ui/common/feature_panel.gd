class_name FeaturePanel
extends CanvasLayer
## Base for the small school-life panels (riddle door, profile card, friends, clubs, shop,
## cauldron, board game, admin…): a parchment UiWindow in the middle of the screen with a
## title, a body the subclass fills (`body`) and a close button; Esc closes; while open
## it holds the keyboard and frees the mouse. Subclasses build their content in
## _build() and refill it in refresh().

var is_open := false
var card: UiWindow
var title_label: Label
var body: VBoxContainer
var status_label: Label
## Half the card's size in pixels.
var half_size := Vector2(330, 240)
## Parchment for school life; chrome (oak) for system screens such as settings.
var family := UiWindow.Family.PARCHMENT
## False when the subclass scrolls its own content (tabs with a page each).
var scrolls := true

const INK := UiTokens.INK


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = UiWindow.new(family, scrolls)
	card.centre(half_size)
	card.close_requested.connect(close)
	title_label = card.title_label
	body = card.body
	status_label = card.status_label
	card.visible = false
	add_child(card)
	_build()


## Subclasses: build the panel's controls into `body`.
func _build() -> void:
	pass


## Subclasses: refill the controls from the current state.
func refresh() -> void:
	pass


func open_panel() -> void:
	is_open = true
	UiSounds.play(&"panel_open")
	card.show_window()
	status_label.text = ""
	UiRouter.opened(self)
	refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	card.hide_window()
	UiRouter.closed(self)


## Shows the answer to a request in the status line (the refusal, or `ok_key`).
func show_result(r: Dictionary, ok_key: String = "") -> void:
	status_label.text = (tr(ok_key) if ok_key != "" else "") if r.get("ok", false) else NetworkManager.refusal_text(str(r.get("reason", "")))
	if not r.get("ok", false):
		UiSounds.play(&"error")


## Helpers for subclasses.
func label(text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label has no width of its own; in a row it would shrink to one letter.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if size != UiTokens.SIZE_BODY:
		l.add_theme_font_size_override("font_size", size)
	return l


func button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


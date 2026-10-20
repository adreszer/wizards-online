class_name FeaturePanel
extends CanvasLayer
## Base for the small school-life panels (riddle door, profile card, friends, clubs, shop,
## cauldron, board game, admin…): a parchment card in the middle of the screen with a
## title, a body the subclass fills (`body`) and a close button; Esc closes; while open
## it holds the keyboard and frees the mouse. Subclasses build their content in
## _build() and refill it in refresh().

var is_open := false
var card: PanelContainer
var title_label: Label
var body: VBoxContainer
var status_label: Label
## Half the card's size in pixels.
var half_size := Vector2(330, 240)

const INK := Color(0.2, 0.13, 0.07)


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -half_size.x
	card.offset_right = half_size.x
	card.offset_top = -half_size.y
	card.offset_bottom = half_size.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.85, 0.72, 0.98)
	style.border_color = Color(0.45, 0.3, 0.16)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	card.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.theme_type_variation = &"TitleLabel"
	title_label.add_theme_color_override("font_color", INK)
	head.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.set_meta(&"ui_sound", &"")
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(0.45, 0.2, 0.1))
	outer.add_child(status_label)
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
	card.visible = true
	status_label.text = ""
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	card.visible = false
	GameSession.ui_input_captured = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
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


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

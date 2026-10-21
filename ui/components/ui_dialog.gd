class_name UiDialog
extends Control
## A modal question (docs/ui.md, "Components"): a chrome window with a message and two
## buttons, over the dimmed screen, on the UiRouter stack (Esc and the seal answer no).
## confirm() asks yes or no; error() reports a failure with Retry and Close. The dialog
## frees itself once answered.

signal answered(yes: bool)

const HALF := Vector2(260, 110)

var card: UiWindow
var message_label: Label
var yes_button: Button
var no_button: Button
var _layer: CanvasLayer


## A yes/no question; `yes`/`no` are translation keys for the buttons.
static func confirm(parent: Node, title: String, text: String, yes := "UI_YES", no := "UI_NO") -> UiDialog:
	return _open(parent, title, text, yes, no)


## A failure (lost connection, refused join); answered(true) means Retry. Without
## `retry` there is only Close.
static func error(parent: Node, title: String, text: String, retry := true) -> UiDialog:
	var d := _open(parent, title, text, "UI_RETRY" if retry else "", "UI_CLOSE")
	d.message_label.theme_type_variation = &"WindowStatus"
	return d


static func _open(parent: Node, title: String, text: String, yes: String, no: String) -> UiDialog:
	var d := UiDialog.new()
	d._layer = CanvasLayer.new()
	d._layer.layer = 60
	d._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(d._layer)
	d._build(title, text, yes, no)
	d._layer.add_child(d)
	d.card.show_window()
	UiRouter.opened(d)
	var first := d.yes_button if d.yes_button.visible else d.no_button
	first.grab_focus.call_deferred()
	return d


func _build(title: String, text: String, yes: String, no: String) -> void:
	name = "UiDialog"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = UiWindow.new(UiWindow.Family.CHROME, false)
	card.centre(HALF)
	card.close_requested.connect(_answer.bind(false))
	card.title_label.text = title
	add_child(card)
	message_label = Label.new()
	message_label.text = text
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(message_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.body.add_child(row)
	no_button = Button.new()
	no_button.text = no
	no_button.pressed.connect(_answer.bind(false))
	row.add_child(no_button)
	yes_button = Button.new()
	yes_button.text = yes
	yes_button.visible = yes != ""
	yes_button.pressed.connect(_answer.bind(true))
	row.add_child(yes_button)


func ui_back() -> void:
	_answer(false)


func _answer(yes: bool) -> void:
	if is_queued_for_deletion():
		return
	UiRouter.closed(self)
	answered.emit(yes)
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

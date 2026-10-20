extends Node
## Autoload: the one stack of open panels (docs/ui.md, "Components"). A panel calls
## UiRouter.opened(self) when it shows and UiRouter.closed(self) when it hides; the
## router does the rest for every panel alike:
## - GameSession.ui_input_captured is true exactly while something is open (the player,
##   camera and spell tracer read it), and the cursor is freed on open (the camera
##   recaptures it once the stack is empty);
## - Esc goes to the top panel: its ui_back() if it has one (a panel that must do more
##   than close, like the character creator undoing a preview), else its close();
## - behind the top modal panel the world dims (a backdrop added as that panel's first
##   child, so it sits under the panel and over every lower layer) and the HUD fades;
## - when the last input came from a gamepad, the panel's first focusable control takes
##   focus.
## Panels keep their own open()/close() (content, sounds); they no longer touch input
## capture, the mouse or Esc themselves.

signal changed

const DIM := Color(0, 0, 0, 0.45)
## How visible the HUD stays behind a modal window.
const HUD_BEHIND := 0.25

var _stack: Array[Node] = []
var _modal: Dictionary = {}
## panel -> its backdrop (freed with the panel if the panel goes first).
var _backdrops: Dictionary = {}
var _pad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## `modal`: the panel takes the screen (dim behind it, HUD faded); chat and the
## gesture wheel are not modal.
func opened(panel: Node, modal: bool = true) -> void:
	if not _stack.has(panel):
		_stack.append(panel)
	var on_exit := closed.bind(panel)
	if not panel.tree_exiting.is_connected(on_exit):
		panel.tree_exiting.connect(on_exit)
	_modal[panel] = modal
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _pad:
		_focus_first.call_deferred(panel)
	_update()


func closed(panel: Node) -> void:
	if not _stack.has(panel):
		return
	_stack.erase(panel)
	_modal.erase(panel)
	var backdrop: Node = _backdrops.get(panel)
	_backdrops.erase(panel)
	if is_instance_valid(backdrop):
		backdrop.queue_free()
	_update()


func is_open(panel: Node) -> bool:
	return _stack.has(panel)


func top() -> Node:
	return _stack.back() if not _stack.is_empty() else null


func open_count() -> int:
	return _stack.size()


## True while a modal panel is open (the HUD fades, the world dims).
func has_modal() -> bool:
	return _top_modal() != null


## Closes everything (leaving the world, tests).
func close_all() -> void:
	for panel in _stack.duplicate():
		_back(panel)
	for panel in _stack.duplicate():
		closed(panel)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad = false
	if not _stack.is_empty() and event.is_action_pressed("pause"):
		_back(top())
		get_viewport().set_input_as_handled()


func _back(panel: Node) -> void:
	if not is_instance_valid(panel):
		closed(panel)
	elif panel.has_method("ui_back"):
		panel.ui_back()
	elif panel.has_method("close"):
		panel.close()
	# A panel whose close() does not report back still leaves the stack.
	closed(panel)


func _top_modal() -> Node:
	for i in range(_stack.size() - 1, -1, -1):
		if _modal.get(_stack[i], false):
			return _stack[i]
	return null


func _update() -> void:
	GameSession.ui_input_captured = not _stack.is_empty()
	var modal := _top_modal()
	for panel: Node in _modal:
		if not _modal[panel] or not is_instance_valid(panel):
			continue
		var backdrop: ColorRect = _backdrops.get(panel)
		if not is_instance_valid(backdrop):
			backdrop = _make_backdrop()
			panel.add_child(backdrop)
			panel.move_child(backdrop, 0)
			_backdrops[panel] = backdrop
		var was_shown := backdrop.visible
		backdrop.visible = panel == modal
		if backdrop.visible and not was_shown and not GameSettings.get_value("reduce_motion"):
			backdrop.modulate.a = 0.0
			backdrop.create_tween().tween_property(backdrop, "modulate:a", 1.0, UiTokens.NORMAL)
	changed.emit()


func _make_backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.name = "UiBackdrop"
	r.color = DIM
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.visible = false
	return r


func _focus_first(panel: Node) -> void:
	if not is_instance_valid(panel) or not _stack.has(panel):
		return
	var control := _first_focusable(panel)
	if control != null:
		control.grab_focus()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and not (child as Control).is_visible_in_tree():
			continue
		if child is Control and (child as Control).focus_mode == Control.FOCUS_ALL:
			return child
		var found := _first_focusable(child)
		if found != null:
			return found
	return null

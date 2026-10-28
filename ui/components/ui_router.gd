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
## capture, the mouse or Esc themselves. The pause menu joins the stack while open
## (Esc resumes), so it dims and fades the HUD like any window.

signal changed
## The last input switched between gamepad and keyboard/mouse (key hints follow it).
signal device_changed(pad: bool)

const DIM := Color(0, 0, 0, 0.45)
const BLUR := preload("res://ui/theme/backdrop_blur.gdshader")
## Meta on a panel that shows the world itself (the character creator's preview): it
## stays modal, but nothing dims or blurs behind it.
const SEE_WORLD := &"ui_see_world"
## How visible the HUD stays behind a modal window.
const HUD_BEHIND := 0.25

var _stack: Array[Node] = []
var _modal: Dictionary = {}
## panel -> its backdrop (freed with the panel if the panel goes first).
var _backdrops: Dictionary = {}
var _pad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


## `modal`: the panel takes the screen (dim behind it, HUD faded); chat and the
## gesture wheel are not modal.
func opened(panel: Node, modal: bool = true) -> void:
	if not _stack.has(panel):
		_stack.append(panel)
	var on_exit := closed.bind(panel)
	if not panel.tree_exiting.is_connected(on_exit):
		panel.tree_exiting.connect(on_exit)
	var fresh := not _modal.has(panel)
	_modal[panel] = modal
	# Every window opens with a sound; a panel that played its own this instant
	# (map, satchel) keeps it.
	if modal and fresh:
		UiSounds.play_unless_recent(&"panel_open")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _pad:
		_focus_first.call_deferred(panel)
	_update()


func closed(panel: Node) -> void:
	if not _stack.has(panel):
		return
	_stack.erase(panel)
	if _modal.get(panel, false):
		UiSounds.play_unless_recent(&"panel_close")
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
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_pad(false)
	if _stack.is_empty():
		return
	# Esc, or B on a pad, goes back from the top panel (a text field keeps B for itself
	# only on the keyboard: a pad has no other way out).
	if event.is_action_pressed("pause") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		_back(top())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_LEFT_SHOULDER or b == JOY_BUTTON_RIGHT_SHOULDER:
			if page(top(), -1 if b == JOY_BUTTON_LEFT_SHOULDER else 1):
				get_viewport().set_input_as_handled()
			return
		# A pad press with nothing focused finds the panel's first control.
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not focused.is_visible_in_tree():
			_focus_first(top())


## True when the last input came from a gamepad.
func using_pad() -> bool:
	return _pad


## Gives the first control focus again after a panel rebuilt its content (a new quiz
## question), when a pad is in use.
func refocus(panel: Node) -> void:
	if _pad:
		_focus_first.call_deferred(panel)


## LB / RB on a pad: the panel's own page turn (`ui_page(step)` or a book's `turn`),
## else the next or previous tab of its first visible tab strip. True if something moved.
func page(panel: Node, step: int) -> bool:
	if not is_instance_valid(panel):
		return false
	if panel.has_method("ui_page"):
		panel.ui_page(step)
		return true
	if panel.has_method("turn"):
		panel.turn(step)
		return true
	var tabs := _first_tabs(panel)
	if tabs is TabContainer:
		var tc := tabs as TabContainer
		if tc.get_tab_count() > 1:
			tc.current_tab = posmod(tc.current_tab + step, tc.get_tab_count())
			UiSounds.play(&"click")
			refocus(panel)
			return true
	elif tabs is TabBar:
		var tb := tabs as TabBar
		if tb.tab_count > 1:
			tb.current_tab = posmod(tb.current_tab + step, tb.tab_count)
			UiSounds.play(&"click")
			return true
	return false


func _first_tabs(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and not (child as Control).is_visible_in_tree():
			continue
		if child is TabContainer or child is TabBar:
			return child
		var found := _first_tabs(child)
		if found != null:
			return found
	return null


## Hover and pad focus brighten every button a little (UiMotion.hover), the same way
## everywhere; meta `ui_no_hover` opts a button out.
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.get_meta(&"ui_no_hover", false):
		return
	var on := func() -> void:
		if not button.disabled:
			UiMotion.hover(button, true)
	var off := func() -> void:
		if not button.has_focus() or not _pad:
			UiMotion.hover(button, false)
	button.mouse_entered.connect(on)
	button.mouse_exited.connect(off)
	button.focus_entered.connect(func() -> void:
		if _pad:
			on.call())
	button.focus_exited.connect(func() -> void: UiMotion.hover(button, false))


func _set_pad(pad: bool) -> void:
	if pad != _pad:
		_pad = pad
		device_changed.emit(pad)


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
		backdrop.visible = panel == modal and not panel.get_meta(SEE_WORLD, false)
		if backdrop.visible and not was_shown and not UiMotion.reduced():
			backdrop.modulate.a = 0.0
			UiMotion.fade(backdrop, 1.0, UiTokens.NORMAL)
	changed.emit()


func _make_backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.name = "UiBackdrop"
	r.color = DIM
	# The world behind blurred as well as dimmed, so the window reads first.
	var blur := ShaderMaterial.new()
	blur.shader = BLUR
	blur.set_shader_parameter("dim", DIM)
	r.material = blur
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

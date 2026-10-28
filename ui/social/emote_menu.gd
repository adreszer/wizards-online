class_name EmoteMenu
extends CanvasLayer
## The gesture menu (G): eight gestures in a row of buttons, chosen with 1–8 or a
## click; G or Esc closes it. H raises a hand without opening it. The chosen gesture
## goes to the local player's input (PlayerInput.request_gesture), like a key.

var is_open := false
var _root: PanelContainer
var _player: Player


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.local_player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	GameEvents.local_player_removed.connect(func(_p: Node) -> void:
		close()
		_player = null)
	_build()


func _build() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -430
	_root.offset_right = 430
	_root.offset_top = -250
	_root.offset_bottom = -150
	_root.theme_type_variation = &"ChromePanel"
	var box := VBoxContainer.new()
	_root.add_child(box)
	var title := Label.new()
	title.text = "EMOTE_MENU_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in Gestures.IDS.size():
		var id: StringName = Gestures.IDS[i]
		var button := Button.new()
		button.name = String(id)
		button.text = "%d  %s" % [i + 1, tr("GESTURE_" + String(id).to_upper())]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(choose.bind(id))
		row.add_child(button)
	var footer := Label.new()
	footer.text = "EMOTE_MENU_FOOTER"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.theme_type_variation = &"HintLabel"
	box.add_child(footer)
	_root.visible = false
	add_child(_root)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or is_open:
		return
	if event.is_action_pressed("emote_menu") and not GameSession.ui_input_captured and _player != null:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("emote_menu"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var n := (event as InputEventKey).physical_keycode - KEY_1
		if n >= 0 and n < Gestures.IDS.size():
			choose(Gestures.IDS[n])
			get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_root.visible = true
	UiRouter.opened(self, false)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	UiRouter.closed(self)


## Closes the menu, then asks for the gesture (after the keyboard is released).
func choose(id: StringName) -> void:
	close()
	if _player != null and is_instance_valid(_player):
		_player.player_input.request_gesture(id)

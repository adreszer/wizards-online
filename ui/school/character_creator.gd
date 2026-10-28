class_name CharacterCreator
extends CanvasLayer
## The character creator: body, skin tone and robe colour, previewed live on the
## player (the house colour on the trim comes from the sorting). The options stand in a
## chrome window on the right; the left of the screen is a turntable: the player, framed
## by a camera of its own, turns with a drag there or with the arrow buttons. Opens on
## the first join of a character without a chosen look, and with /look (/wyglad). "Done"
## stores the choice: online in the profile (everyone sees it), offline in the settings.

const HALF := Vector2(210, 250)
## Margin from the right edge to the window.
const MARGIN := 48
## Degrees the turntable turns per pixel dragged, and per arrow press.
const DRAG_TURN := 0.4
const STEP_TURN := 30.0

var is_open := false
var _player: Player
var _look: Dictionary = {}
var _before: Dictionary = {}
var card: UiWindow
var _turntable: Control
var _body: OptionButton
var _skin_row: HBoxContainer
var _robe_row: HBoxContainer
var _camera: Camera3D
## The turntable's angle in degrees (0: facing the camera).
var yaw := 0.0
var _dragging := false


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The preview is the player in the world: nothing may blur it.
	set_meta(UiRouter.SEE_WORLD, true)
	GameEvents.local_player_spawned.connect(func(p: Node) -> void: _player = p as Player)
	GameEvents.local_player_removed.connect(func(_p: Node) -> void:
		close(false)
		_player = null)
	GameEvents.character_creator_requested.connect(func() -> void:
		# Headless runs (tests, servers) have nobody to choose.
		if DisplayServer.get_name() != "headless":
			open())
	_build()


func _build() -> void:
	# The turntable: everything left of the window catches drags.
	_turntable = Control.new()
	_turntable.name = "Turntable"
	_turntable.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turntable.offset_right = -(HALF.x * 2.0 + MARGIN)
	_turntable.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_turntable.gui_input.connect(_on_turntable_input)
	_turntable.visible = false
	add_child(_turntable)
	card = UiWindow.new(UiWindow.Family.CHROME, false)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -(HALF.x * 2.0 + MARGIN)
	card.offset_right = -MARGIN
	card.offset_top = -HALF.y
	card.offset_bottom = HALF.y
	card.title_label.text = tr("CREATOR_TITLE")
	card.close_requested.connect(close.bind(false))
	card.visible = false
	add_child(card)
	var box := card.body
	var intro := Label.new()
	intro.text = "CREATOR_INTRO"
	intro.theme_type_variation = &"HintLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	box.add_child(_caption("CREATOR_BODY"))
	_body = OptionButton.new()
	for id in CharacterRegistry.ids():
		if id != "placeholder":
			_body.add_item(tr(CharacterRegistry.name_key(id)))
			_body.set_item_metadata(_body.item_count - 1, id)
	_body.item_selected.connect(func(i: int) -> void: _change("body", str(_body.get_item_metadata(i))))
	box.add_child(_body)
	box.add_child(_caption("CREATOR_SKIN"))
	_skin_row = _swatches(CharacterLook.SKIN_TONES.map(func(c: Color) -> Color: return CharacterLook.SKIN_BASE * c), CharacterLook.SKIN_KEYS, "skin")
	box.add_child(_skin_row)
	box.add_child(_caption("CREATOR_ROBE"))
	_robe_row = _swatches(CharacterLook.ROBE_COLORS, CharacterLook.ROBE_KEYS, "robe")
	box.add_child(_robe_row)
	box.add_child(_caption("CREATOR_TURN"))
	var turn := UiBox.h(UiTokens.SPACE_2)
	for step: float in [-STEP_TURN, STEP_TURN]:
		var b := Button.new()
		b.text = "◀" if step < 0 else "▶"
		b.pressed.connect(func() -> void: rotate_preview(step))
		turn.add_child(b)
	box.add_child(turn)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var buttons := UiBox.h(UiTokens.SPACE_2, BoxContainer.ALIGNMENT_END)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "CREATOR_CANCEL"
	cancel.pressed.connect(func() -> void: close(false))
	buttons.add_child(cancel)
	var done := Button.new()
	done.text = "CREATOR_DONE"
	done.pressed.connect(func() -> void: close(true))
	buttons.add_child(done)


func _caption(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = &"BookLabel"
	return l


func _swatches(colors: Array, keys: Array[String], field: String) -> HBoxContainer:
	var row := UiBox.h(UiTokens.SPACE_1)
	for i in colors.size():
		var b := ColorSwatch.new(colors[i])
		b.tooltip_text = keys[i]
		b.pressed.connect(_change.bind(field, i))
		row.add_child(b)
	return row


## Turns the preview by `degrees` (the turntable).
func rotate_preview(degrees: float) -> void:
	yaw = wrapf(yaw + degrees, -180.0, 180.0)
	if is_open:
		_frame_player()


func _on_turntable_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		rotate_preview((event as InputEventMouseMotion).relative.x * DRAG_TURN)


func open() -> void:
	if is_open or _player == null:
		return
	is_open = true
	_look = _player.look.duplicate()
	_before = _look.duplicate()
	for i in _body.item_count:
		if str(_body.get_item_metadata(i)) == str(_look.body):
			_body.select(i)
	_refresh_swatches()
	yaw = 0.0
	card.show_window()
	_turntable.visible = true
	UiRouter.opened(self)
	_frame_player()


## Closes; `keep` stores the look, otherwise the player goes back to how they were.
func close(keep: bool) -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	card.hide_window()
	_turntable.visible = false
	UiRouter.closed(self)
	if _camera != null:
		_camera.queue_free()
		_camera = null
	if _player == null or not is_instance_valid(_player):
		return
	if keep:
		NetworkManager.save_look(_look)
		_player.set_look(CharacterLook.sanitize(_look))
		GameEvents.notify(tr("CREATOR_SAVED"), 4.0, ToastStack.Kind.INFO, "check")
	else:
		_player.set_look(_before)


func _change(field: String, value: Variant) -> void:
	_look[field] = value
	_player.set_look(_look)
	_refresh_swatches()
	_frame_player()


func _refresh_swatches() -> void:
	for i in _skin_row.get_child_count():
		(_skin_row.get_child(i) as Button).set_pressed_no_signal(i == int(_look.get("skin", 0)))
		_skin_row.get_child(i).queue_redraw()
	for i in _robe_row.get_child_count():
		(_robe_row.get_child(i) as Button).set_pressed_no_signal(i == int(_look.get("robe", 0)))
		_robe_row.get_child(i).queue_redraw()


## A camera of its own while the creator is open (the player's own camera looks at
## their back): it orbits the player by the turntable's angle and keeps them in the
## left part of the screen, clear of the window.
func _frame_player() -> void:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = 38.0
		_player.get_parent().add_child(_camera)
	var out := (-_player.global_basis.z).rotated(Vector3.UP, deg_to_rad(yaw))
	var right := (-out).cross(Vector3.UP).normalized()
	var shift := right * 0.75
	_camera.global_position = _player.global_position + out * 2.8 + Vector3.UP * 1.3 + shift
	_camera.look_at(_player.global_position + Vector3.UP * 1.0 + shift, Vector3.UP)
	_camera.current = true


## Esc (UiRouter) drops the preview.
func ui_back() -> void:
	close(false)

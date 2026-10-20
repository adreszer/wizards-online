class_name CharacterCreator
extends CanvasLayer
## The character creator: body, skin tone and robe colour, previewed live on the
## player (the house colour on the trim comes from the sorting). Opens on the first
## join of a character without a chosen look, and with /look (/wyglad). "Done" stores
## the choice: online in the profile (everyone sees it), offline in the settings.

var is_open := false
var _player: Player
var _look: Dictionary = {}
var _before: Dictionary = {}
var _root: PanelContainer
var _body: OptionButton
var _skin_row: HBoxContainer
var _robe_row: HBoxContainer
var _camera: Camera3D


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_root = PanelContainer.new()
	_root.anchor_left = 0.0
	_root.anchor_top = 0.5
	_root.anchor_bottom = 0.5
	_root.offset_left = 30
	_root.offset_right = 420
	_root.offset_top = -200
	_root.offset_bottom = 200
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.92)
	style.border_color = Color(0.85, 0.7, 0.4, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_root.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_root.add_child(box)
	var title := Label.new()
	title.text = "CREATOR_TITLE"
	title.theme_type_variation = &"TitleLabel"
	box.add_child(title)
	var intro := Label.new()
	intro.text = "CREATOR_INTRO"
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
	_skin_row = _swatches(CharacterLook.SKIN_TONES.map(func(c: Color) -> Color: return Color(0.95, 0.76, 0.62) * c), CharacterLook.SKIN_KEYS, "skin")
	box.add_child(_skin_row)
	box.add_child(_caption("CREATOR_ROBE"))
	_robe_row = _swatches(CharacterLook.ROBE_COLORS, CharacterLook.ROBE_KEYS, "robe")
	box.add_child(_robe_row)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var done := Button.new()
	done.text = "CREATOR_DONE"
	done.pressed.connect(func() -> void: close(true))
	buttons.add_child(done)
	var cancel := Button.new()
	cancel.text = "CREATOR_CANCEL"
	cancel.pressed.connect(func() -> void: close(false))
	buttons.add_child(cancel)
	_root.visible = false
	add_child(_root)


func _caption(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.add_theme_color_override("font_color", Color(0.94, 0.82, 0.55))
	return l


func _swatches(colors: Array, keys: Array[String], field: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 34)
		b.tooltip_text = keys[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i]
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.2, 0.2, 0.2)
		b.add_theme_stylebox_override("normal", sb)
		var sel := sb.duplicate() as StyleBoxFlat
		sel.border_color = Color(1, 0.9, 0.5)
		b.add_theme_stylebox_override("hover", sel)
		b.add_theme_stylebox_override("pressed", sel)
		b.toggle_mode = true
		b.pressed.connect(_change.bind(field, i))
		row.add_child(b)
	return row


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
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame_player()


## Closes; `keep` stores the look, otherwise the player goes back to how they were.
func close(keep: bool) -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameSession.ui_input_captured = false
	if _camera != null:
		_camera.queue_free()
		_camera = null
	if _player == null or not is_instance_valid(_player):
		return
	if keep:
		NetworkManager.save_look(_look)
		_player.set_look(CharacterLook.sanitize(_look))
		GameEvents.notification_requested.emit(tr("CREATOR_SAVED"), 4.0)
	else:
		_player.set_look(_before)


func _change(field: String, value: Variant) -> void:
	_look[field] = value
	_player.set_look(_look)
	_refresh_swatches()
	_frame_player()


func _refresh_swatches() -> void:
	for i in _skin_row.get_child_count():
		(_skin_row.get_child(i) as Button).button_pressed = i == int(_look.get("skin", 0))
	for i in _robe_row.get_child_count():
		(_robe_row.get_child(i) as Button).button_pressed = i == int(_look.get("robe", 0))


## A camera in front of the player while the creator is open (the player's own
## camera looks at their back).
func _frame_player() -> void:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = 38.0
		_player.get_parent().add_child(_camera)
	var front := -_player.global_basis.z
	_camera.global_position = _player.global_position + front * 2.6 + Vector3.UP * 1.35 + _player.global_basis.x * 0.9
	_camera.look_at(_player.global_position + Vector3.UP * 1.0 + _player.global_basis.x * 0.5, Vector3.UP)
	_camera.current = true


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close(false)
		get_viewport().set_input_as_handled()

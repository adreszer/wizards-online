class_name MapPanel
extends CanvasLayer
## The full castle map. Opens with the `map` action (M), closes with `map` or
## `pause` (Esc). While open it captures keyboard input and frees the mouse,
## like the satchel. Drag to pan, wheel to zoom about the cursor, PageUp /
## PageDown or the arrow buttons change storey, "Find me" recentres on the
## local player. Hovering a room names it in the footer.

signal toggled(open: bool)

const MIN_ZOOM := 0.25
const MAX_ZOOM := 8.0
const OPEN_ZOOM := 3.0

@onready var _root: Control = %Root
@onready var _view: MapView = %View
@onready var _storey_label: Label = %StoreyLabel
@onready var _footer: Label = %Footer
@onready var _up: Button = %UpButton
@onready var _down: Button = %DownButton

var is_open: bool = false
var castle_map: CastleMap
var _dragging := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_view.gui_input.connect(_on_view_input)
	_view.mouse_exited.connect(func() -> void: _set_hover({}))
	_up.pressed.connect(change_storey.bind(1))
	_down.pressed.connect(change_storey.bind(-1))
	%FindButton.pressed.connect(centre_on_player)
	%CloseButton.pressed.connect(close)


func set_map(map: CastleMap) -> void:
	castle_map = map
	_view.castle_map = map


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("map") and not GameSession.ui_input_captured:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("map"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_PAGEUP:
			change_storey(1)
			get_viewport().set_input_as_handled()
		elif key == KEY_PAGEDOWN:
			change_storey(-1)
			get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or castle_map == null or castle_map.rooms.is_empty():
		return
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_view.pixels_per_metre = OPEN_ZOOM
	centre_on_player()
	toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	_root.visible = false
	GameSession.ui_input_captured = false
	toggled.emit(false)


func centre_on_player() -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me != null:
		_view.centre = Vector2(me.global_position.x, me.global_position.z)
		_view.storey = castle_map.view_storey_at(me.global_position)
	else:
		_view.centre = castle_map.castle_bounds.get_center()
	_update_storey()


func change_storey(step: int) -> void:
	if castle_map == null:
		return
	_view.storey = clampi(_view.storey + step, castle_map.min_storey, castle_map.max_storey)
	_set_hover({})
	_update_storey()


func zoom_at(factor: float, screen_point: Vector2) -> void:
	var anchor := _view.screen_to_world(screen_point)
	_view.pixels_per_metre = clampf(_view.pixels_per_metre * factor, MIN_ZOOM, MAX_ZOOM)
	# Keep the world point under the cursor where it was.
	_view.centre += anchor - _view.screen_to_world(screen_point)
	_view.refresh()


func _process(_delta: float) -> void:
	if is_open:
		_view.refresh()


func _update_storey() -> void:
	_storey_label.text = MapView.storey_name(_view.storey)
	_up.disabled = _view.storey >= castle_map.max_storey
	_down.disabled = _view.storey <= castle_map.min_storey
	_view.refresh()


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(1.0 / 1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		_view.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_view.centre -= mm.relative / _view.pixels_per_metre
			_view.refresh()
		_set_hover(castle_map.room_at_point(_view.screen_to_world(mm.position), _view.storey))


func _set_hover(room: Dictionary) -> void:
	_view.hover_room = room
	_footer.text = tr(room["key"]) if not room.is_empty() else tr("MAP_HINT")
	_view.refresh()

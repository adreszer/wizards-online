class_name MapPanel
extends CanvasLayer
## The full castle map on a parchment sheet (UiWindow): the map in an inset, a tab per
## storey along the top, "Find me" beside them, the legend down the right (what each
## room colour means, you) and a compass rose drawn on the map. Opens with the
## `map` action (M), closes with `map`, Esc or the seal. While open it captures
## keyboard input and frees the mouse, like the satchel. Drag to pan, wheel to zoom
## about the cursor, PageUp / PageDown or the tabs change storey. Hovering a room
## names it in the status line.

signal toggled(open: bool)

const MIN_ZOOM := 0.25
const MAX_ZOOM := 8.0
const OPEN_ZOOM := 3.0
## Margin from the screen edge to the sheet.
const MARGIN := 40
## Room kinds the legend explains, in order (MAP_KIND_<KIND> names each).
const LEGEND := ["hall", "classroom", "library", "corridor", "tower", "stair_turret", "outdoor", "secret"]

var is_open: bool = false
var castle_map: CastleMap
var card: UiWindow
var _view: MapView
var _floors: TabBar
var _footer: Label
var _legend: VBoxContainer
var _dragging := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = UiWindow.new(UiWindow.Family.PARCHMENT, false)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_left = MARGIN
	card.offset_top = MARGIN
	card.offset_right = -MARGIN
	card.offset_bottom = -MARGIN
	card.title_label.text = tr("MAP_TITLE")
	card.close_requested.connect(close)
	card.visible = false
	add_child(card)
	var top := UiBox.h(UiTokens.SPACE_3)
	_floors = TabBar.new()
	_floors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floors.clip_tabs = false
	_floors.tab_changed.connect(func(index: int) -> void:
		if castle_map != null:
			show_storey(castle_map.min_storey + index))
	top.add_child(_floors)
	var find := Button.new()
	find.text = tr("MAP_FIND_ME")
	find.pressed.connect(centre_on_player)
	top.add_child(find)
	card.body.add_child(top)
	var row := UiBox.h(UiTokens.SPACE_4)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(row)
	var inset := PanelContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inset)
	_view = MapView.new()
	_view.name = "View"
	_view.label_font_size = 13
	_view.show_rose = true
	_view.clip_contents = true
	inset.add_child(_view)
	_legend = UiBox.v(UiTokens.SPACE_2)
	_legend.custom_minimum_size = Vector2(170, 0)
	row.add_child(_legend)
	_build_legend()
	_footer = card.status_label
	card.add_key_hint(&"map", tr("UI_CLOSE"))
	_view.gui_input.connect(_on_view_input)
	_view.mouse_exited.connect(func() -> void: _set_hover({}))


## The legend: a swatch per room kind in the map's own colours, the houses' rooms, and you.
func _build_legend() -> void:
	var title := Label.new()
	title.text = tr("MAP_LEGEND")
	title.theme_type_variation = &"BookLabel"
	_legend.add_child(title)
	for kind: String in LEGEND:
		_legend.add_child(_legend_row(MapView.KIND_COLORS.get(kind, MapView.PAPER), tr("MAP_KIND_" + kind.to_upper())))
	_legend.add_child(_legend_row(MapView.PAPER.lerp(CharacterProfile.HOUSE_COLORS[1], 0.4), tr("MAP_KIND_HOUSE")))
	var you := UiBox.h(UiTokens.SPACE_2)
	var mark := TextureRect.new()
	mark.texture = UiIcons.icon("person", 18)
	mark.modulate = MapView.INK
	you.add_child(mark)
	you.add_child(_legend_text(tr("MAP_LEGEND_YOU")))
	_legend.add_child(you)


func _legend_row(colour: Color, text: String) -> HBoxContainer:
	var row := UiBox.h(UiTokens.SPACE_2)
	var swatch := ColorRect.new()
	swatch.color = colour
	swatch.custom_minimum_size = Vector2(18, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	row.add_child(_legend_text(text))
	return row


func _legend_text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HintLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func set_map(map: CastleMap) -> void:
	castle_map = map
	_view.castle_map = map
	_build_floors()
	if castle_map != null and not castle_map.rebuilt.is_connected(_build_floors):
		castle_map.rebuilt.connect(_build_floors)


## A tab per storey, the lowest dungeon first.
func _build_floors() -> void:
	_floors.clear_tabs()
	if castle_map == null:
		return
	for storey in range(castle_map.min_storey, castle_map.max_storey + 1):
		_floors.add_tab(MapView.storey_name(storey))


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("map") and not GameSession.ui_input_captured:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("map"):
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
	UiSounds.play(&"map_open")
	card.show_window()
	UiRouter.opened(self)
	_view.pixels_per_metre = OPEN_ZOOM
	centre_on_player()
	toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	_dragging = false
	card.hide_window()
	UiRouter.closed(self)
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
	show_storey(_view.storey + step)


func show_storey(storey: int) -> void:
	_view.storey = clampi(storey, castle_map.min_storey, castle_map.max_storey)
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
	var index := _view.storey - castle_map.min_storey
	if index >= 0 and index < _floors.tab_count and _floors.current_tab != index:
		_floors.set_current_tab(index)
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

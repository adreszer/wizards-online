extends CanvasLayer
## Inventory ("satchel") UI. Opens with the `inventory` action, closes with
## `inventory` or `pause` (Esc). While open it captures keyboard input
## (GameSession.ui_input_captured) and frees the mouse, like the chat panel.
## Clicking an item holds it in the off hand or puts it away; the panel only
## asks the player's Inventory, which is the single source of truth.

@onready var _root: Control = %Root
@onready var _slots: VBoxContainer = %Slots
@onready var _empty_label: Label = %EmptyLabel
@onready var _description: Label = %Description
@onready var _held_label: Label = %HeldLabel

var is_open: bool = false
var _inventory: Inventory
var _selected: ItemDefinition


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.local_player_removed.connect(_unbind_player)


func _bind_player(player: Node) -> void:
	_inventory = player.inventory
	_inventory.changed.connect(_refresh)
	_refresh()


func _unbind_player(_player: Node) -> void:
	close()
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = null


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("inventory") and not GameSession.ui_input_captured and _inventory != null:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or _inventory == null:
		return
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameSession.ui_input_captured = false
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	if _inventory == null:
		return
	_empty_label.visible = _inventory.is_empty()
	for slot in _inventory.slots:
		var def: ItemDefinition = slot["def"]
		var button := Button.new()
		button.text = _slot_text(def, int(slot["count"]))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_slot_pressed.bind(def))
		if def == _inventory.held_item:
			button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		_slots.add_child(button)
	if _selected != null and not _inventory.has(_selected.id):
		_selected = null
	_update_details()


func _slot_text(def: ItemDefinition, count: int) -> String:
	var text := tr(def.display_name)
	if count > 1:
		text += " ×%d" % count
	if def == _inventory.held_item:
		text += "  " + tr("INVENTORY_HELD_MARK")
	return text


func _on_slot_pressed(def: ItemDefinition) -> void:
	_selected = def
	if def.holdable:
		_inventory.toggle_hold(def)
	else:
		_update_details()


func _update_details() -> void:
	if _inventory.held_item != null:
		_held_label.text = tr("HUD_HELD") % tr(_inventory.held_item.display_name)
	else:
		_held_label.text = tr("HUD_HELD_NONE")
	if _selected == null:
		_description.text = tr("INVENTORY_HINT")
	else:
		var text := tr(_selected.description) if not _selected.description.is_empty() else ""
		if _selected.holdable:
			text += ("\n" if not text.is_empty() else "") + tr("INVENTORY_CLICK_TO_HOLD")
		_description.text = text


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _inventory != null:
		_refresh()

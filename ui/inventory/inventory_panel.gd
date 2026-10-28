extends CanvasLayer
## The satchel (`inventory` action): a chrome window with the items as a grid of
## satchel squares (ItemSlot, icon and count, empty squares to fill the bag) and, beside
## it, the chosen item: its icon, name, what it is for and the one thing to do with it
## (take in hand, put away, mount, land). A double click does that at once. The foot
## shows what is in hand and the purse. Closes with `inventory`, Esc or the seal; while
## open it holds the keyboard and frees the mouse (UiRouter), like every panel. The
## panel only asks the player's Inventory and BroomRider, which own the state.

const HALF := Vector2(390, 230)
const COLUMNS := 5
## The bag always shows at least this many squares.
const MIN_SQUARES := 15
## Item id or category → UiIcons id, until items get painted icons of their own.
const ICONS := {
	"torch": "candle", "brass_lantern": "lantern", "broom": "broom", "permission_slip": "book",
	"star_chart": "map", "wayfinder_chart": "compass", "trophy_small": "house_points",
	"potion": "cauldron", "seed": "spell_growth", "herb": "spell_growth", "ingredient": "cauldron",
	"familiar": "person", "decor": "discovery", "tool": "wand",
}

var is_open: bool = false
var card: UiWindow
## One button per square, in order; the first ones hold the items.
var squares: Array[Button] = []
var _grid: GridContainer
var _icon: TextureRect
var _name: Label
var _description: Label
var _action: Button
var _held_label: Label
var _purse_label: Label
var _inventory: Inventory
var _rider: BroomRider
var _selected: ItemDefinition


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = UiWindow.new(UiWindow.Family.CHROME, false)
	card.centre(HALF)
	card.title_label.text = tr("INVENTORY_TITLE")
	card.close_requested.connect(close)
	card.visible = false
	add_child(card)
	var row := UiBox.h(UiTokens.SPACE_5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(row)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	row.add_child(_grid)
	var details := UiBox.v(UiTokens.SPACE_2)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var head := UiBox.h(UiTokens.SPACE_3)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.modulate = UiTokens.BRASS_BRIGHT
	head.add_child(_icon)
	_name = Label.new()
	_name.theme_type_variation = &"TitleLabel"
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_name)
	details.add_child(head)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_description)
	_action = Button.new()
	_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_action.pressed.connect(func() -> void: use(_selected))
	details.add_child(_action)
	details.add_child(HSeparator.new())
	_held_label = Label.new()
	_held_label.theme_type_variation = &"HintLabel"
	details.add_child(_held_label)
	_purse_label = Label.new()
	_purse_label.theme_type_variation = &"HintLabel"
	details.add_child(_purse_label)
	card.add_key_hint(&"inventory", tr("UI_CLOSE"))
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.local_player_removed.connect(_unbind_player)


func _bind_player(player: Node) -> void:
	_inventory = player.inventory
	_rider = player.broom_rider
	_inventory.changed.connect(_refresh)
	_refresh()


func _unbind_player(_player: Node) -> void:
	close()
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = null
	_rider = null


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("inventory") and not GameSession.ui_input_captured and _inventory != null:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or _inventory == null:
		return
	is_open = true
	UiSounds.play(&"inventory_open")
	card.show_window()
	UiRouter.opened(self)
	_refresh()
	_focus_first.call_deferred()


## Keyboard and gamepad start on the first square (the grid may have been rebuilt
## since open() asked).
func _focus_first() -> void:
	if is_open and not squares.is_empty() and squares[0].is_inside_tree():
		squares[0].grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	card.hide_window()
	UiRouter.closed(self)


## The UiIcons id for an item: by its id, else its category, else the satchel.
static func icon_id_for(def: ItemDefinition) -> String:
	return str(ICONS.get(String(def.id), ICONS.get(def.category, "satchel")))


## The icon texture for an item: its own when it has one.
static func icon_for(def: ItemDefinition, px: int) -> Texture2D:
	return def.icon if def.icon != null else UiIcons.icon(icon_id_for(def), px)


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	squares.clear()
	if _inventory == null:
		return
	if _selected != null and not _inventory.has(_selected.id):
		_selected = null
	var items: Array = _inventory.slots
	var count := maxi(MIN_SQUARES, ceili(items.size() / float(COLUMNS)) * COLUMNS)
	for i in count:
		var button := Button.new()
		button.flat = true
		button.custom_minimum_size = Vector2(ItemSlot.SIZE, ItemSlot.SIZE)
		var slot := ItemSlot.new()
		slot.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(slot)
		if i < items.size():
			var def: ItemDefinition = items[i]["def"]
			var in_use := def == _inventory.held_item or (_rider != null and def == _rider.mount)
			if def.icon != null:
				slot.set_texture(def.icon, int(items[i]["count"]))
			else:
				slot.set_item(icon_id_for(def), int(items[i]["count"]))
			slot.selected = def == _selected or (_selected == null and in_use)
			button.tooltip_text = tr(def.display_name)
			button.pressed.connect(select.bind(def))
			button.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
					use(def))
		else:
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
		_grid.add_child(button)
		squares.append(button)
	_update_details()


## Shows an item's details (a click on its square).
func select(def: ItemDefinition) -> void:
	_selected = def
	_refresh()


## Does the item's one action: a broom mounts (or lands) and closes the satchel, a
## holdable item goes into the hand or back into the bag.
func use(def: ItemDefinition) -> void:
	if def == null or _inventory == null:
		return
	_selected = def
	if def.is_mount() and _rider != null:
		close()
		if _rider.mount == def:
			_rider.dismount()
		else:
			_rider.mount_item(def)
	elif def.holdable:
		_inventory.toggle_hold(def)
	_refresh()


## The action button's text for an item ("" when it has none).
func action_text(def: ItemDefinition) -> String:
	if def.is_mount():
		return tr("INVENTORY_LAND") if _rider != null and _rider.mount == def else tr("INVENTORY_MOUNT")
	if def.holdable:
		return tr("INVENTORY_PUT_AWAY") if def == _inventory.held_item else tr("INVENTORY_HOLD")
	return ""


func _update_details() -> void:
	_held_label.text = tr("HUD_HELD") % tr(_inventory.held_item.display_name) if _inventory.held_item != null else tr("HUD_HELD_NONE")
	_purse_label.text = tr("HUD_COINS") % Currency.format(NetworkManager.get_coins())
	if _selected == null:
		_icon.texture = UiIcons.icon("satchel", 56)
		_name.text = tr("INVENTORY_TITLE")
		_description.text = tr("INVENTORY_EMPTY") if _inventory.is_empty() else tr("INVENTORY_HINT")
		_action.visible = false
		return
	_icon.texture = icon_for(_selected, 56)
	_name.text = tr(_selected.display_name)
	_description.text = tr(_selected.description) if not _selected.description.is_empty() else ""
	_action.text = action_text(_selected)
	_action.visible = _action.text != ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _inventory != null:
		_refresh()

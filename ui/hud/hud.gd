extends CanvasLayer
## The in-game HUD (docs/ui.md, Milestone 67), built from the UI components. Top left:
## who you are (crest, name, house and year), the health vial only while hurt or in a
## duel, the lesson-tools key for staff. Top right: the day dial with the time and the
## next lesson, the house crystals. Centre: the crosshair and the interaction prompt as
## a key chip and a verb. Bottom: the spell roundels with the held item beside them.
## Notifications are toasts at the top, area names and lesson starts a banner. The
## minimap is its own layer (ui/map/minimap.gd). Behind a window the HUD fades out;
## toggle_hud hides all of it for screenshots. Reads player components via the
## local_player_spawned event; never drives gameplay.

const SATCHEL := preload("res://ui/inventory/inventory_panel.gd")
const FRAGMENT_ID := &"arcane_fragment"
## How visible the HUD stays behind an open window (UiRouter).
const BEHIND_WINDOW := 0.0
## Seconds before walking back into the same area shows its banner again.
const AREA_REPEAT := 30.0
## Seconds the health vial stays after healing back to full.
const HEALTH_LINGER := 3.0
## Below this share of health the vial pulses.
const HEALTH_LOW := 0.3

## Everything but the toasts, faded behind windows.
var hud_root: Control
var plate: PlayerPlate
var health_vial: ProgressVial
var staff_hint: HBoxContainer
var dial: DayDial
var clock_label: Label
var lesson_label: Label
var status_label: Label
var house_tally: HouseCrystals
var crosshair: HudCrosshair
var prompt_row: HBoxContainer
var prompt_label: Label
var banner: AreaBanner
var hotbar_root: VBoxContainer
var hotbar: HBoxContainer
var spell_label: Label
var held_slot: ItemSlot
var toasts: ToastStack
## False while the player has hidden the interface (toggle_hud).
var shown := true

var _toast_layer: CanvasLayer
var _slots: Array[SpellSlot] = []
var _player: Node
var _caster: SpellCaster
var _inventory: Inventory
var _health: Health
var _clock_timer := 0.0
var _health_full_for := 0.0
var _in_duel := false
var _focused: Interactable
var _status: int = NetworkManager.Status.OFFLINE
var _status_message := ""
var _last_area := ""
var _last_area_at := -1000.0


func _ready() -> void:
	_build()
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.collectible_collected.connect(_on_collectible_collected)
	GameEvents.notification_requested.connect(show_notification)
	GameEvents.spell_learned.connect(_on_spell_learned)
	GameEvents.area_entered.connect(_on_area_entered)
	GameEvents.school_bell_rang.connect(_on_bell)
	GameEvents.house_changed.connect(func(_h: int) -> void: _refresh_plate())
	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.profile_received.connect(func(_p: Dictionary) -> void: _refresh_plate())
	NetworkManager.house_totals_changed.connect(set_house_totals)
	NetworkManager.wallet_changed.connect(_on_wallet_changed)
	NetworkManager.server_message.connect(_on_server_message)
	UiRouter.changed.connect(_on_windows_changed)
	_on_status_changed(NetworkManager.status, "")
	_on_spell_learned(null)
	_on_held_item_changed(null)
	_refresh_plate()
	set_house_totals(NetworkManager.get_house_totals())
	_refresh_clock()
	_on_windows_changed()


func _build() -> void:
	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)
	# Top left: who you are.
	var top_left := UiBox.v()
	top_left.name = "TopLeft"
	top_left.position = Vector2(UiTokens.SPACE_5, UiTokens.SPACE_4)
	hud_root.add_child(top_left)
	plate = PlayerPlate.new()
	top_left.add_child(plate)
	health_vial = ProgressVial.new()
	health_vial.custom_minimum_size = Vector2(200, 18)
	health_vial.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	health_vial.low = HEALTH_LOW
	health_vial.show_value = true
	health_vial.visible = false
	top_left.add_child(health_vial)
	staff_hint = KeyChip.hint_row(&"lesson_tools", tr("HUD_LESSON_HINT"), &"HudMeta")
	staff_hint.visible = false
	top_left.add_child(staff_hint)
	# Top right: the time of day and the houses.
	var top_right := UiBox.v()
	top_right.name = "TopRight"
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -UiTokens.SPACE_5
	top_right.offset_top = UiTokens.SPACE_4
	hud_root.add_child(top_right)
	var time_row := UiBox.h(UiTokens.SPACE_3, BoxContainer.ALIGNMENT_END)
	top_right.add_child(time_row)
	var time_lines := UiBox.v(-2)
	time_lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(time_lines)
	clock_label = _label(&"HudClock", HORIZONTAL_ALIGNMENT_RIGHT)
	time_lines.add_child(clock_label)
	lesson_label = _label(&"HudLesson", HORIZONTAL_ALIGNMENT_RIGHT)
	time_lines.add_child(lesson_label)
	status_label = _label(&"HudStatus", HORIZONTAL_ALIGNMENT_RIGHT)
	status_label.visible = false
	time_lines.add_child(status_label)
	dial = DayDial.new()
	time_row.add_child(dial)
	house_tally = HouseCrystals.new()
	house_tally.size_flags_horizontal = Control.SIZE_SHRINK_END
	house_tally.visible = false
	top_right.add_child(house_tally)
	# Centre: the aim and what you can do with what is in front of you.
	crosshair = HudCrosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = -crosshair.custom_minimum_size / 2.0
	crosshair.visible = false
	hud_root.add_child(crosshair)
	prompt_row = KeyChip.hint_row(&"interact", "", &"HudPrompt")
	prompt_row.name = "Prompt"
	prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_row.set_anchors_preset(Control.PRESET_CENTER)
	prompt_row.offset_left = -360
	prompt_row.offset_right = 360
	prompt_row.offset_top = 36
	prompt_row.offset_bottom = 70
	prompt_row.visible = false
	prompt_label = prompt_row.get_child(1)
	hud_root.add_child(prompt_row)
	# Upper middle: area names and lesson starts.
	banner = AreaBanner.new()
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	# Below where four toasts reach.
	banner.anchor_top = 0.34
	banner.anchor_bottom = 0.34
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_root.add_child(banner)
	# Bottom: the spell roundels and the item in hand.
	hotbar_root = UiBox.v(UiTokens.SPACE_1)
	hotbar_root.name = "HotbarRoot"
	hotbar_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar_root.offset_bottom = -UiTokens.SPACE_3
	hud_root.add_child(hotbar_root)
	spell_label = _label(&"HudSpell", HORIZONTAL_ALIGNMENT_CENTER)
	hotbar_root.add_child(spell_label)
	var bottom := UiBox.h(UiTokens.SPACE_4, BoxContainer.ALIGNMENT_CENTER)
	hotbar_root.add_child(bottom)
	hotbar = UiBox.h(0)
	hotbar.name = "Hotbar"
	bottom.add_child(hotbar)
	for i in SpellCaster.QUICK_SLOT_COUNT:
		var slot := SpellSlot.new()
		slot.key_chip.action = StringName("spell_slot_%d" % (i + 1))
		hotbar.add_child(slot)
		_slots.append(slot)
	held_slot = ItemSlot.new()
	held_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	held_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_slot.visible = false
	bottom.add_child(held_slot)
	hotbar.visible = false
	# Toasts on their own layer, above windows, so a "saved" or a refusal still reads.
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "Toasts"
	_toast_layer.layer = 70
	add_child(_toast_layer)
	toasts = ToastStack.new()
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = UiTokens.SPACE_4
	_toast_layer.add_child(toasts)


func _label(variation: StringName, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		set_shown(not shown)
		get_viewport().set_input_as_handled()


## Hides or shows the whole interface (the minimap listens to hud_toggled).
func set_shown(value: bool) -> void:
	shown = value
	visible = value
	_toast_layer.visible = value
	GameEvents.hud_toggled.emit(value)


## Fades out while a window is open, so the window and the dimmed world read first.
func _on_windows_changed() -> void:
	var alpha := BEHIND_WINDOW if UiRouter.has_modal() else 1.0
	if GameSettings.get_value("reduce_motion") or not is_inside_tree():
		hud_root.modulate.a = alpha
	else:
		# Runs while the game is paused too (the pause menu is a window).
		hud_root.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(hud_root, "modulate:a", alpha, UiTokens.NORMAL)


func _process(delta: float) -> void:
	_update_cooldowns()
	if _health_full_for > 0.0:
		_health_full_for -= delta
		if _health_full_for <= 0.0:
			_refresh_health_visibility()
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = 0.5
		_refresh_clock()
		_refresh_seat_prompt()


## The time, the lesson running or next (else the part of the day) and the dial.
func _refresh_clock() -> void:
	var hours := NetworkManager.school_hours()
	clock_label.text = SchoolClock.format(hours)
	var line := NetworkManager.timetable.status_line(NetworkManager.server_time())
	lesson_label.text = line if line != "" else tr(SchoolClock.phase_key(SchoolClock.phase_of(hours)))
	dial.hours = hours


func _bind_player(player: Node) -> void:
	_player = player
	_health = player.health
	_health.health_changed.connect(_on_health_changed)
	_on_health_changed(_health.current, _health.max_health)
	_caster = player.spell_caster
	_caster.spell_changed.connect(_on_spell_learned)
	_caster.spells_changed.connect(_refresh_hotbar)
	_on_spell_learned(_caster.equipped_spell)
	var interaction: InteractionController = player.interaction_controller
	interaction.focus_changed.connect(_on_focus_changed)
	_inventory = player.inventory
	_inventory.held_item_changed.connect(_on_held_item_changed)
	_on_held_item_changed(_inventory.held_item)
	_refresh_plate()


# --- Who you are -------------------------------------------------------------------------

func _refresh_plate() -> void:
	var house: int = int(_player.get("house")) if _player != null else 0
	var profile := NetworkManager.get_local_profile()
	var role := NetworkManager.get_local_role()
	plate.show_player(GameSession.display_name, house, int(profile.get("year", 1)), role)
	staff_hint.visible = CharacterProfile.is_staff(role)


func _on_health_changed(current: int, maximum: int) -> void:
	health_vial.max_value = maximum
	health_vial.value = current
	if current >= maximum and health_vial.visible:
		_health_full_for = HEALTH_LINGER
	_refresh_health_visibility()


## The vial shows while hurt, a little after healing and all through a duel.
func _refresh_health_visibility() -> void:
	var hurt := health_vial.value < health_vial.max_value
	health_vial.visible = hurt or _in_duel or _health_full_for > 0.0


func _on_server_message(op: int, payload: Dictionary) -> void:
	if op != NetworkProtocol.OP_DUEL_STATE:
		return
	var me := NetworkManager.world_session.self_session_id
	var state := str(payload.get("state", ""))
	_in_duel = (state == "countdown" or state == "fighting") and me in [payload.get("a", ""), payload.get("b", "")]
	_refresh_health_visibility()


# --- Spells and the hand ------------------------------------------------------------------

func _on_spell_learned(definition: Resource) -> void:
	var def := definition as SpellDefinition
	crosshair.visible = def != null
	if def == null:
		spell_label.text = ""
	elif def.incantation.is_empty():
		spell_label.text = tr(def.display_name)
	else:
		spell_label.text = tr("HUD_SPELL_LINE") % [tr(def.display_name), tr(def.incantation)]
	_refresh_hotbar()


## Ten fixed roundels (keys 1–0), refreshed from the caster's quick_slots. Display
## only: selection happens through PlayerInput → SpellCaster.
func _refresh_hotbar() -> void:
	if _caster == null:
		return
	var any := false
	var selected := _caster.equipped_slot()
	for i in _slots.size():
		var def: SpellDefinition = _caster.quick_slots[i] if i < _caster.quick_slots.size() else null
		var slot := _slots[i]
		slot.set_spell(def)
		slot.selected = i == selected and def != null
		slot.mastery_max = SpellMastery.THRESHOLDS.size() - 1 if def != null else 0
		slot.mastery = _caster.mastery_level(def) if def != null else 0
		any = any or def != null
	hotbar.visible = any
	spell_label.visible = any


func _update_cooldowns() -> void:
	if _caster == null or not hotbar.visible:
		return
	for i in _slots.size():
		var def: SpellDefinition = _caster.quick_slots[i] if i < _caster.quick_slots.size() else null
		if def != null:
			_slots[i].cooldown = _caster.get_cooldown_remaining(def) / def.cooldown if def.cooldown > 0.0 else 0.0


## Slot index shown as selected (tests, debug); -1 when nothing is equipped.
func hotbar_selected_index() -> int:
	for i in _slots.size():
		if _slots[i].selected:
			return i
	return -1


func _on_held_item_changed(definition: ItemDefinition) -> void:
	held_slot.visible = definition != null
	if definition != null:
		if definition.icon != null:
			held_slot.set_texture(definition.icon)
		else:
			held_slot.set_item(SATCHEL.icon_id_for(definition))
		held_slot.tooltip_text = tr(definition.display_name)


# --- The world around you ---------------------------------------------------------------

## With nothing in focus, interacting sits down at a nearby seat (or stands up).
func _refresh_seat_prompt() -> void:
	if _focused != null or _player == null or not is_instance_valid(_player):
		return
	var verb := ""
	if _player.gestures.is_sitting():
		verb = "PROMPT_STAND"
	elif _player.seat_nearby():
		verb = "PROMPT_SIT"
	_show_prompt(verb)


func _on_focus_changed(interactable: Interactable) -> void:
	_focused = interactable
	_show_prompt(interactable.prompt_text if interactable != null else "")


## The prompt under the crosshair: the interact key and `verb` (a translation key).
func _show_prompt(verb: String) -> void:
	prompt_label.text = tr(verb) if verb != "" else ""
	prompt_row.visible = verb != ""


## The area's name as a banner when the player walks into a named part of the castle.
func _on_area_entered(_area_id: StringName, zone: Node) -> void:
	if not zone.has_method("display_name"):
		return
	var title: String = zone.display_name()
	var now := Time.get_ticks_msec() / 1000.0
	if title == "" or (title == _last_area and now - _last_area_at < AREA_REPEAT):
		return
	_last_area = title
	_last_area_at = now
	banner.show_area(title)


## A lesson starting rings in a banner: the subject and the room.
func _on_bell(event: String, entry: Dictionary) -> void:
	if event == "start":
		banner.show_area(Timetable.title_of(entry), Timetable.room_name(get_tree(), str(entry.get("area", ""))), 4.0)


# --- Notices -----------------------------------------------------------------------------

## Shows a toast; GameEvents.notify() sets its kind and icon while it is sent.
func show_notification(text: String, duration: float = 3.0) -> void:
	toasts.push(text, GameEvents.notice_kind as ToastStack.Kind, GameEvents.notice_icon, maxf(duration, ToastStack.hold_for(text)))


func _on_collectible_collected(definition: Resource, _total: int, _max_total: int) -> void:
	if definition != null and definition.get("id") == FRAGMENT_ID:
		GameEvents.notify(tr("HUD_FRAGMENTS") % [GameSession.get_collected(FRAGMENT_ID), GameSession.get_total(FRAGMENT_ID)], 3.0,
			ToastStack.Kind.REWARD, "fragment")


## A gain or loss of coins shows as a toast.
func _on_wallet_changed(_coins: int, delta: int, source: String, detail: String) -> void:
	var line := Currency.change_line(delta, source, detail)
	if line != "":
		GameEvents.notify(line, 5.0, ToastStack.Kind.REWARD if delta > 0 else ToastStack.Kind.INFO, "coins")


## House points (index 0 = house 1) in the crystals; hidden while there are none (offline).
func set_house_totals(totals: PackedInt32Array) -> void:
	house_tally.visible = totals.size() >= CharacterProfile.MAX_HOUSE
	house_tally.set_totals(totals)


## Text of the tally, for tests.
func house_tally_text() -> String:
	return house_tally.text()


## Only trouble with the connection shows; online and offline play need no line.
func _on_status_changed(status: int, message: String) -> void:
	_status = status
	_status_message = message
	match status:
		NetworkManager.Status.CONNECTING:
			status_label.text = message if not message.is_empty() else tr("HUD_STATUS_CONNECTING")
		NetworkManager.Status.ERROR:
			status_label.text = tr("HUD_STATUS_OFFLINE_REASON") % message
		_:
			status_label.text = ""
	status_label.visible = status_label.text != ""


## Re-render the code-formatted labels when the language changes at runtime.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and hud_root != null:
		_on_spell_learned(_caster.equipped_spell if _caster != null else null)
		_refresh_plate()
		_refresh_clock()
		_on_held_item_changed(_inventory.held_item if _inventory != null else null)
		_show_prompt(_focused.prompt_text if is_instance_valid(_focused) else "")
		set_house_totals(NetworkManager.get_house_totals())
		_on_status_changed(_status, _status_message)

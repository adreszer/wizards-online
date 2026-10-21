extends CanvasLayer
## Minimal in-game HUD: health, collectibles, equipped spell, interaction
## prompt, notifications, connection status. Reads player components via the
## local_player_spawned event; never drives gameplay.

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _fragments_label: Label = %FragmentsLabel
@onready var _spell_label: Label = %SpellLabel
@onready var _cooldown_bar: ProgressBar = %CooldownBar
@onready var _held_label: Label = %HeldLabel
@onready var _role_label: Label = %RoleLabel
@onready var _house_label: Label = %HouseLabel
@onready var _house_crest: TextureRect = %HouseCrest
@onready var _coins_label: Label = %CoinsLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _notification_label: Label = %NotificationLabel
@onready var _status_label: Label = %StatusLabel
@onready var _clock_label: Label = %ClockLabel
@onready var _schedule_label: Label = %ScheduleLabel
@onready var _crosshair: Control = %Crosshair
@onready var _hotbar_root: Control = %HotbarRoot
@onready var _hotbar: HBoxContainer = %Hotbar
@onready var _house_tally: HBoxContainer = %HouseTally

const SLOT_KEY_LABELS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

var _slot_style: StyleBox
var _slot_selected_style: StyleBox
## One entry per quick slot: {panel, key, name, cooldown}.
var _slot_views: Array[Dictionary] = []

const FRAGMENT_ID := &"arcane_fragment"
## How visible the HUD panels stay behind an open window (UiRouter); the crosshair and
## the prompt go entirely.
const BEHIND_WINDOW := 0.25

var _player: Node
var _caster: SpellCaster
var _inventory: Inventory
var _notification_timer: float = 0.0
var _clock_timer: float = 0.0
var _focused: Interactable
var _status: int = NetworkManager.Status.OFFLINE
var _status_message: String = ""


func _ready() -> void:
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.collectible_collected.connect(_on_collectible_collected)
	GameEvents.collectible_total_changed.connect(_on_total_changed)
	GameEvents.notification_requested.connect(show_notification)
	GameEvents.spell_learned.connect(_on_spell_learned)
	GameEvents.area_entered.connect(_on_area_entered)
	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.profile_received.connect(_on_profile_received)
	NetworkManager.house_totals_changed.connect(set_house_totals)
	NetworkManager.wallet_changed.connect(_on_wallet_changed)
	GameEvents.house_changed.connect(func(_h: int) -> void: _refresh_house())
	_prompt_label.visible = false
	_notification_label.visible = false
	_build_hotbar()
	_update_fragments()
	_on_status_changed(NetworkManager.status, "")
	_on_spell_learned(null)
	_on_held_item_changed(null)
	_refresh_role()
	_refresh_house()
	set_house_totals(NetworkManager.get_house_totals())
	_refresh_coins()
	UiRouter.changed.connect(_on_windows_changed)
	_on_windows_changed()


## Steps back while a window is open, so the window and the dimmed world read first.
func _on_windows_changed() -> void:
	var behind := UiRouter.has_modal()
	var instant: bool = GameSettings.get_value("reduce_motion")
	for node: CanvasItem in [$TopLeft, $TopRight, _hotbar_root, _crosshair, _prompt_label]:
		var alpha := 1.0
		if behind:
			alpha = 0.0 if node == _crosshair or node == _prompt_label else BEHIND_WINDOW
		if instant or not is_inside_tree():
			node.modulate.a = alpha
		else:
			# Runs while the game is paused too (the pause menu is a window).
			node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(node, "modulate:a", alpha, UiTokens.NORMAL)


func _process(delta: float) -> void:
	if _caster != null and _caster.equipped_spell != null:
		var cd := _caster.equipped_spell.cooldown
		_cooldown_bar.value = 1.0 - (_caster.cooldown_remaining / cd if cd > 0.0 else 0.0)
	_update_hotbar_cooldowns()
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = 0.5
		_refresh_clock()
		_refresh_seat_prompt()
	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			_notification_label.visible = false


## School time and phase, e.g. "14:05 · day".
func _refresh_clock() -> void:
	var hours := NetworkManager.school_hours()
	_clock_label.text = tr("HUD_CLOCK") % [SchoolClock.format(hours), tr(SchoolClock.phase_key(SchoolClock.phase_of(hours)))]
	var line := NetworkManager.timetable.status_line(NetworkManager.server_time())
	_schedule_label.text = line
	_schedule_label.visible = line != ""



func _bind_player(player: Node) -> void:
	_player = player
	var health: Health = player.health
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current, health.max_health)
	_caster = player.spell_caster
	_caster.spell_changed.connect(_on_spell_learned)
	_caster.spells_changed.connect(_refresh_hotbar)
	_on_spell_learned(_caster.equipped_spell)
	_refresh_hotbar()
	var interaction: InteractionController = player.interaction_controller
	interaction.focus_changed.connect(_on_focus_changed)
	_inventory = player.inventory
	_inventory.held_item_changed.connect(_on_held_item_changed)
	_on_held_item_changed(_inventory.held_item)
	_refresh_house()


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func _on_collectible_collected(_definition: Resource, _total: int, _max_total: int) -> void:
	_update_fragments()


func _on_total_changed(_id: StringName, _max_total: int) -> void:
	_update_fragments()


func _update_fragments() -> void:
	_fragments_label.text = tr("HUD_FRAGMENTS") % [GameSession.get_collected(FRAGMENT_ID), GameSession.get_total(FRAGMENT_ID)]


func _on_spell_learned(definition: Resource) -> void:
	if definition == null:
		_spell_label.text = tr("HUD_SPELL_NONE")
		_cooldown_bar.visible = false
		_crosshair.visible = false
	else:
		var incantation := (definition as SpellDefinition).incantation if definition is SpellDefinition else ""
		if incantation.is_empty():
			_spell_label.text = tr("HUD_SPELL") % tr(definition.display_name)
		else:
			_spell_label.text = tr("HUD_SPELL_INCANTATION") % [tr(definition.display_name), tr(incantation)]
		_cooldown_bar.visible = true
		_crosshair.visible = true
	_refresh_hotbar()


# --- Hotbar ---------------------------------------------------------------------------

## Ten fixed slots (keys 1–0). Built once; refreshed from the caster's quick_slots.
## Purely display: selection happens through PlayerInput → SpellCaster so the
## HUD never swallows mouse clicks meant for casting.
func _build_hotbar() -> void:
	_slot_style = _make_slot_style(false)
	_slot_selected_style = _make_slot_style(true)
	for i in SpellCaster.QUICK_SLOT_COUNT:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(68, 56)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _slot_style)
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 0)
		panel.add_child(vbox)
		var key := Label.new()
		key.text = SLOT_KEY_LABELS[i]
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(0.75, 0.72, 0.8))
		vbox.add_child(key)
		var name_label := Label.new()
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(name_label)
		var cooldown := ProgressBar.new()
		cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cooldown.custom_minimum_size = Vector2(0, 4)
		cooldown.max_value = 1.0
		cooldown.value = 1.0
		cooldown.show_percentage = false
		vbox.add_child(cooldown)
		_hotbar.add_child(panel)
		_slot_views.append({"panel": panel, "key": key, "name": name_label, "cooldown": cooldown})
	_hotbar_root.visible = false


func _make_slot_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.18, 0.4, 0.75) if selected else Color(0, 0, 0, 0.5)
	style.set_border_width_all(2 if selected else 1)
	style.border_color = Color(1, 0.85, 0.5) if selected else Color(0.45, 0.4, 0.5, 0.7)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _refresh_hotbar() -> void:
	if _caster == null or _slot_views.is_empty():
		return
	var any := false
	var selected := _caster.equipped_slot()
	for i in _slot_views.size():
		var view := _slot_views[i]
		var def: SpellDefinition = _caster.quick_slots[i] if i < _caster.quick_slots.size() else null
		var name_label: Label = view["name"]
		var key: Label = view["key"]
		var panel: PanelContainer = view["panel"]
		if def == null:
			name_label.text = ""
			key.modulate = Color(1, 1, 1, 0.5)
		else:
			any = true
			name_label.text = tr(def.display_name)
			name_label.add_theme_color_override("font_color", def.color.lightened(0.35))
			key.modulate = Color.WHITE
		panel.add_theme_stylebox_override("panel", _slot_selected_style if i == selected else _slot_style)
		(view["cooldown"] as ProgressBar).visible = def != null
	_hotbar_root.visible = any


func _update_hotbar_cooldowns() -> void:
	if _caster == null or not _hotbar_root.visible:
		return
	for i in _slot_views.size():
		var def: SpellDefinition = _caster.quick_slots[i] if i < _caster.quick_slots.size() else null
		if def == null:
			continue
		var bar: ProgressBar = _slot_views[i]["cooldown"]
		var remaining := _caster.get_cooldown_remaining(def)
		bar.value = 1.0 - (remaining / def.cooldown if def.cooldown > 0.0 else 0.0)


## Slot index shown as selected (tests, debug); -1 when nothing is equipped.
func hotbar_selected_index() -> int:
	return _caster.equipped_slot() if _caster != null else -1


func _on_held_item_changed(definition: ItemDefinition) -> void:
	if definition == null:
		_held_label.text = tr("HUD_HELD_NONE")
	else:
		_held_label.text = tr("HUD_HELD") % tr(definition.display_name)


func _on_profile_received(_profile: Dictionary) -> void:
	_refresh_role()


## House points tally (index 0 = house 1): each house's crest in its colour
## and its points; hidden while there is none (offline).
func set_house_totals(totals: PackedInt32Array) -> void:
	for child in _house_tally.get_children():
		child.queue_free()
	_house_tally.visible = totals.size() >= CharacterProfile.MAX_HOUSE
	if not _house_tally.visible:
		return
	for h in range(1, CharacterProfile.MAX_HOUSE + 1):
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 3)
		entry.tooltip_text = tr("HUD_HOUSE_POINTS") % [CharacterProfile.house_name(h), totals[h - 1]]
		var crest := _crest_icon(h)
		crest.custom_minimum_size = Vector2(20, 20)
		entry.add_child(crest)
		var label := Label.new()
		label.text = str(totals[h - 1])
		label.add_theme_color_override("font_color", CharacterProfile.HOUSE_COLORS[h])
		entry.add_child(label)
		_house_tally.add_child(entry)


## Text of the tally labels, for tests.
func house_tally_text() -> String:
	var parts := PackedStringArray()
	for entry in _house_tally.get_children():
		if entry.is_queued_for_deletion():
			continue
		for child in entry.get_children():
			if child is Label:
				parts.append((child as Label).text)
	return " ".join(parts)


## A house's crest as a small glyph in the house colour.
static func _crest_icon(house: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = CharacterProfile.crest(house, CharacterProfile.CREST_ICON)
	icon.modulate = CharacterProfile.house_color(house)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## The purse line; a gain or loss also shows as a notification.
func _on_wallet_changed(_coins: int, delta: int, source: String, detail: String) -> void:
	_refresh_coins()
	var line := Currency.change_line(delta, source, detail)
	if line != "":
		GameEvents.notification_requested.emit(line, 5.0)


func _refresh_coins() -> void:
	_coins_label.text = tr("HUD_COINS") % Currency.format(NetworkManager.get_coins())


func _refresh_house() -> void:
	var house: int = int(_player.get("house")) if _player != null else 0
	if house == 0:
		_house_label.text = tr("HUD_HOUSE_NONE")
		_house_label.remove_theme_color_override("font_color")
		_house_crest.visible = false
	else:
		_house_label.text = tr("HUD_HOUSE") % CharacterProfile.house_name(house)
		_house_label.add_theme_color_override("font_color", CharacterProfile.house_color(house))
		_house_crest.texture = CharacterProfile.crest(house, CharacterProfile.CREST_ICON)
		_house_crest.modulate = CharacterProfile.house_color(house)
		_house_crest.visible = true


## Students see nothing; staff see their role and the lesson-tools key.
func _refresh_role() -> void:
	var role := NetworkManager.get_local_role()
	match role:
		CharacterProfile.ROLE_PROFESSOR:
			_role_label.text = tr("HUD_ROLE_PROFESSOR") + "  " + tr("HUD_LESSON_HINT")
		CharacterProfile.ROLE_ADMIN:
			_role_label.text = tr("HUD_ROLE_ADMIN") + "  " + tr("HUD_LESSON_HINT")
	_role_label.visible = CharacterProfile.is_staff(role)


## With nothing in focus, interacting sits down at a nearby seat (or stands up).
func _refresh_seat_prompt() -> void:
	if _focused != null or _player == null or not is_instance_valid(_player):
		return
	var text := ""
	if _player.gestures.is_sitting():
		text = tr("HUD_PROMPT") % tr("PROMPT_STAND")
	elif _player.seat_nearby():
		text = tr("HUD_PROMPT") % tr("PROMPT_SIT")
	_prompt_label.text = text
	_prompt_label.visible = text != ""


func _on_focus_changed(interactable: Interactable) -> void:
	_focused = interactable
	if interactable == null:
		_prompt_label.visible = false
	else:
		_prompt_label.text = tr("HUD_PROMPT") % tr(interactable.prompt_text)
		_prompt_label.visible = true


## Area name toast when the player walks into a named part of the castle.
func _on_area_entered(_area_id: StringName, zone: Node) -> void:
	if zone.has_method("display_name"):
		show_notification(zone.display_name(), 2.5)


func show_notification(text: String, duration: float = 3.0) -> void:
	_notification_label.text = text
	_notification_label.visible = true
	_notification_timer = duration


func _on_status_changed(status: int, message: String) -> void:
	_status = status
	_status_message = message
	match status:
		NetworkManager.Status.ONLINE:
			_status_label.text = tr("HUD_STATUS_ONLINE") % GameSession.display_name
		NetworkManager.Status.CONNECTING:
			_status_label.text = message if not message.is_empty() else tr("HUD_STATUS_CONNECTING")
		NetworkManager.Status.ERROR:
			_status_label.text = tr("HUD_STATUS_OFFLINE_REASON") % message
		_:
			_status_label.text = tr("HUD_STATUS_OFFLINE")


## Re-render the code-formatted labels when the language changes at runtime.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_fragments()
		_on_spell_learned(_caster.equipped_spell if _caster != null else null)
		_refresh_hotbar()
		_refresh_role()
		_refresh_house()
		_on_held_item_changed(_inventory.held_item if _inventory != null else null)
		if is_instance_valid(_focused):
			_on_focus_changed(_focused)
		_on_status_changed(_status, _status_message)

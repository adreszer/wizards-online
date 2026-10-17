extends Node
## In-game root: level + player spawner + UI layers. Created by Game after the
## menu; frees everything on return.

signal return_to_menu_requested()

@onready var _spawner: PlayerSpawner = $PlayerSpawner
@onready var _level: Node = $Level
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _minimap: Minimap = $Minimap
@onready var _map_panel: MapPanel = $MapPanel


func _ready() -> void:
	_pause_menu.return_to_menu_requested.connect(return_to_menu_requested.emit)
	_spawner.spawn_point = _level.get_node("StartPoint")
	_build_map()
	var emotes := EmoteMenu.new()
	emotes.name = "EmoteMenu"
	add_child(emotes)
	var player: Node = _spawner.spawn_local(GameSession.display_name, NetworkManager.local_user_id)
	GameEvents.level_completed.connect(_on_level_completed)
	_show_satchel_hint(player)
	_show_sorting_hint(player)
	# Playtest shortcut: `-- --all-spells` fills the hotbar without touring the tomes.
	if OS.get_cmdline_user_args().has("--all-spells"):
		for definition in SpellRegistry.all():
			if NetworkManager.is_online():
				NetworkManager.send_study_tome(String(definition.id))
			else:
				player.spell_caster.learn_spell(definition)


## The map is read from the level as it stands, so a regenerated castle maps itself.
func _build_map() -> void:
	var castle_map := CastleMap.new()
	castle_map.name = "CastleMap"
	add_child(castle_map)
	castle_map.build(_level)
	_minimap.set_map(castle_map)
	_map_panel.set_map(castle_map)
	_map_panel.toggled.connect(func(open: bool) -> void: _minimap.visible = not open)


## First-time nudge toward the torch (the server inventory may arrive a moment
## after the spawn, hence the short delay).
func _show_satchel_hint(player: Node) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(player) or not is_inside_tree():
		return
	var inventory: Inventory = player.inventory
	if inventory.held_item == null and not inventory.is_empty():
		GameEvents.notification_requested.emit(tr("NOTIFY_INVENTORY_HINT"), 8.0)


## Unsorted characters are pointed at the ceremony (online: once the profile is in).
func _show_sorting_hint(player: Node) -> void:
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(player) or not is_inside_tree():
		return
	if int(player.get("house")) == 0:
		GameEvents.notification_requested.emit(tr("NOTIFY_SORTING_HINT"), 8.0)


func _on_level_completed() -> void:
	GameEvents.notification_requested.emit(tr("NOTIFY_SLICE_COMPLETE") % [
		GameSession.get_collected(&"arcane_fragment"), GameSession.get_total(&"arcane_fragment")], 8.0)

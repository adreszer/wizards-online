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
	var quiz := QuizPanel.new()
	quiz.name = "QuizPanel"
	add_child(quiz)
	var duel := DuelHud.new()
	duel.name = "DuelHud"
	add_child(duel)
	var book := BookPanel.new()
	book.name = "BookPanel"
	add_child(book)
	var journal := Journal.new()
	journal.name = "Journal"
	add_child(journal)
	for panel: FeaturePanel in [RiddlePanel.new(), DecorPanel.new(), FriendsPanel.new(), ClubsPanel.new(), GamePanel.new(), ProfileCard.new(),
			CauldronPanel.new(), ShopPanel.new(), AdminPanel.new(), SettingsPanel.new()]:
		panel.name = panel.get_script().get_global_name()
		add_child(panel)
	var effects := PotionEffects.new()
	effects.name = "PotionEffects"
	add_child(effects)
	var fires := FireAmbience.new()
	fires.name = "FireAmbience"
	add_child(fires)
	var reminders := EventReminders.new()
	reminders.name = "EventReminders"
	add_child(reminders)
	var birds := PaperBirds.new()
	birds.name = "PaperBirds"
	add_child(birds)
	var creator := CharacterCreator.new()
	creator.name = "CharacterCreator"
	add_child(creator)
	GameSettings.apply(get_tree())
	var player: Node = _spawner.spawn_local(GameSession.display_name, NetworkManager.local_user_id)
	GameEvents.level_completed.connect(_on_level_completed)
	_show_satchel_hint(player)
	_arrive(player)
	# Offline, a first game opens the character creator (online the profile decides).
	if not NetworkManager.is_online() and not GameSession.look.get("set", false):
		GameEvents.character_creator_requested.emit.call_deferred()
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


## A character's first time in the shared world starts at the railway station (feature
## "arrival"); a returning character starts where they left, when that place is still
## safe to stand in (see resume_point); headless runs (tests, servers) stay at the start point.
func _arrive(player: Node) -> void:
	if not NetworkManager.is_in_world() or DisplayServer.get_name() == "headless":
		return
	var ok := await _wait_for_arrival()
	if not ok or not is_instance_valid(player):
		return
	var arrival := NetworkManager.feature("arrival")
	if not arrival.get("first", false):
		var back: Variant = resume_point(_level, arrival, int(NetworkManager.get_local_profile().get("house", 0)))
		if back != null:
			(player as Node3D).global_position = back
		return
	var at: Variant = ChatCommands.place_position(player as Node3D, "@station")
	if at != null:
		(player as Node3D).global_position = at
		GameEvents.notification_requested.emit(tr("ARRIVAL_WELCOME"), 10.0)


## Where a returning character should stand: the position the server kept when they left
## ({pos: [x, y, z], area}), dropped onto the floor below it, or null for the start point.
## Refused: no saved place, an area the level does not have, a hidden room (its wall may have
## closed again), another house's rooms (a guest pass runs out), a room behind a door the
## castle's schedule shuts (CastleSchedule), a position outside its area, or no floor under it.
static func resume_point(level: Node, data: Dictionary, house: int) -> Variant:
	var p: Variant = data.get("pos")
	if not (p is Array) or (p as Array).size() != 3 or level == null or not (level is Node3D):
		return null
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var area := str(data.get("area", ""))
	if area.is_empty():
		return null
	for oid: String in CastleSchedule.DOORS:
		if oid.get_slice("/", 0) == area:
			return null
	var zone: AreaZone = null
	for z in level.find_children("*", "AreaZone", true, false):
		if str((z as AreaZone).area_id) == area:
			zone = z
			break
	if zone == null or zone.kind == "secret" or (zone.house != 0 and zone.house != house):
		return null
	var half := zone.size * 0.5 + Vector3(0.5, 2.0, 0.5)
	var d := (pos - zone.global_position).abs()
	if d.x > half.x or d.y > half.y or d.z > half.z:
		return null
	var space := (level as Node3D).get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 40.0, 1))
	if not hit.is_empty():
		return (hit["position"] as Vector3) + Vector3.UP * 0.1
	# Open ground far from the start point has no collision streamed in yet: use the heights.
	var terrain := level.get_node_or_null("Grounds/Terrain") as Terrain
	if terrain != null and terrain.is_inside(pos.x, pos.z) and terrain.has_ground(pos.x, pos.z):
		var ground := terrain.height_at(pos.x, pos.z)
		if pos.y > ground - 1.0 and pos.y < ground + 40.0:
			return Vector3(pos.x, ground + 0.2, pos.z)
	return null


func _wait_for_arrival() -> bool:
	for i in 300:
		if not NetworkManager.feature("arrival").is_empty():
			return true
		await get_tree().process_frame
	return false


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

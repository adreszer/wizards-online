class_name PlayerSpawner
extends Node
## Lives in the world scene. Spawns the local player at the level's start and
## creates/removes remote player instances from NetworkManager roster events.

signal local_player_spawned(player: Node)
signal remote_player_spawned(player: Node)
signal remote_player_removed(player: Node)

@export var player_scene: PackedScene
@export var spawn_point: Node3D
@export var players_root: Node

var local_player: Node
## sid -> Player
var remote_players: Dictionary = {}


func _ready() -> void:
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.player_state_received.connect(_on_player_state)
	NetworkManager.spell_cast_received.connect(_on_spell_cast)
	NetworkManager.held_item_received.connect(_on_held_item)
	NetworkManager.inventory_received.connect(_on_inventory)
	NetworkManager.profile_received.connect(_on_profile)
	NetworkManager.player_profile_changed.connect(_on_player_profile_changed)
	NetworkManager.spell_granted.connect(_on_spell_granted)
	NetworkManager.disconnected.connect(_on_disconnected)
	NetworkManager.chat_line_received.connect(_on_chat_line)
	NetworkManager.server_message.connect(_on_server_message)
	NetworkManager.practical_changed.connect(_on_practical)
	NetworkManager.player_look_changed.connect(_on_player_look_changed)
	NetworkManager.house_cup_changed.connect(func(_cup: Dictionary) -> void:
		for p: Node in [local_player] + remote_players.values():
			if p is Player and is_instance_valid(p):
				(p as Player).set_look((p as Player).look))


func _exit_tree() -> void:
	NetworkManager.player_look_changed.disconnect(_on_player_look_changed)
	NetworkManager.practical_changed.disconnect(_on_practical)
	NetworkManager.chat_line_received.disconnect(_on_chat_line)
	NetworkManager.server_message.disconnect(_on_server_message)
	NetworkManager.player_joined.disconnect(_on_player_joined)
	NetworkManager.player_left.disconnect(_on_player_left)
	NetworkManager.player_state_received.disconnect(_on_player_state)
	NetworkManager.spell_cast_received.disconnect(_on_spell_cast)
	NetworkManager.held_item_received.disconnect(_on_held_item)
	NetworkManager.inventory_received.disconnect(_on_inventory)
	NetworkManager.profile_received.disconnect(_on_profile)
	NetworkManager.player_profile_changed.disconnect(_on_player_profile_changed)
	NetworkManager.spell_granted.disconnect(_on_spell_granted)
	NetworkManager.disconnected.disconnect(_on_disconnected)


## The creator opens once per session for a character without a chosen look.
var _creator_offered := false


func _apply_remote_look(player: Node, entry: Dictionary) -> void:
	var look: Dictionary = entry.get("look", {}).duplicate() if entry.get("look", {}) is Dictionary else {}
	look["body"] = str(entry.get("char", player.character_id))
	player.set_look(look)


func _on_player_look_changed(sid: String) -> void:
	var player: Node = remote_players.get(sid)
	if player != null:
		_apply_remote_look(player, NetworkManager.get_players().get(sid, {}))


## The spell a practical lets the local player cast for practice (not in their spellbook).
var _practice_spell: StringName = &""

## A practical in our classroom: its spell joins the hotbar for practice while it runs
## (the server allows the casts), and leaves again unless it was granted.
func _on_practical(view: Dictionary) -> void:
	if local_player == null:
		return
	var caster: SpellCaster = local_player.spell_caster
	var spell := StringName(str(view.get("spell", "")))
	var known_on_server: Array = NetworkManager.get_local_profile().get("spells", {}).get("known", [])
	if spell == &"":
		if _practice_spell != &"" and not known_on_server.has(String(_practice_spell)):
			caster.forget_spell(_practice_spell)
			GameEvents.notification_requested.emit(tr("PRACTICAL_OVER"), 4.0)
		_practice_spell = &""
		return
	var def := SpellRegistry.load_definition(String(spell))
	if def == null:
		return
	if not caster.knows(spell):
		caster.learn_spell(def)
		caster.equip(def)
		_practice_spell = spell
		GameEvents.notification_requested.emit(tr("PRACTICAL_STARTED") % [tr(def.display_name), int(view.get("hits", 1))], 7.0)
	if view.get("done", false):
		# A granted spell is ours now (its own notification names the professor).
		if view.get("granted", false):
			_practice_spell = &""
		GameEvents.notification_requested.emit(tr("PRACTICAL_DONE"), 6.0)
	elif int(view.get("progress", 0)) > 0:
		GameEvents.notification_requested.emit(tr("PRACTICAL_PROGRESS") % [int(view.progress), int(view.get("hits", 1))], 2.0)


## The speaker of a chat line (remote or local) shows it over their head.
func _on_chat_line(line: Dictionary) -> void:
	if line.get("kind", "") != "chat":
		return
	var speaker: Node = local_player if line.get("self", false) else remote_players.get(str(line.get("sid", "")))
	if speaker is Player and is_instance_valid(speaker):
		(speaker as Player).say(str(line.get("text", "")), str(line.get("mode", "say")))


func _on_server_message(op_code: int, payload: Dictionary) -> void:
	if op_code == NetworkProtocol.OP_MASTERY and local_player != null:
		var caster := local_player.spell_caster as SpellCaster
		var id := str(payload.get("spell", ""))
		var before := int(caster.mastery.get(id, 0))
		var points := maxi(0, int(payload.get("points", 0)))
		caster.mastery[id] = points
		var def := SpellRegistry.load_definition(id)
		if def != null and SpellMastery.level_of(points) > SpellMastery.level_of(before):
			GameEvents.notification_requested.emit(tr("MASTERY_LEVEL_UP") % [tr(def.display_name), tr(SpellMastery.level_key(points))], 6.0)
	if op_code == NetworkProtocol.OP_LECTURE_TEXT:
		var sid := str(payload.get("sid", ""))
		var speaker: Node = remote_players.get(sid, local_player if sid == NetworkManager.world_session.self_session_id else null)
		if speaker is Player and is_instance_valid(speaker):
			(speaker as Player).say(NetworkProtocol.sanitize_chat(str(payload.get("text", ""))), "lecture")


func spawn_local(display_name: String, peer_id: String) -> Node:
	var player := player_scene.instantiate()
	player.is_local = true
	player.display_name = display_name
	player.peer_id = peer_id
	player.character_id = GameSession.character_id
	player.name = "LocalPlayer"
	_get_root().add_child(player)
	if spawn_point != null:
		player.global_transform = spawn_point.global_transform
		player.respawn_handler.set_checkpoint(spawn_point.global_transform)
	local_player = player
	player.set_look(GameSession.look)
	_apply_local_inventory()
	_apply_local_profile()
	local_player_spawned.emit(player)
	# Players already in the world before we spawned.
	for sid in NetworkManager.get_players().keys():
		_on_player_joined(sid, NetworkManager.get_players()[sid]["name"])
	return player


func _get_root() -> Node:
	return players_root if players_root != null else self


func _on_player_joined(sid: String, display_name: String) -> void:
	if remote_players.has(sid):
		return
	var player := player_scene.instantiate()
	player.is_local = false
	player.display_name = display_name
	player.peer_id = sid
	player.character_id = CharacterRegistry.sanitize(str(NetworkManager.get_players().get(sid, {}).get("char", "")))
	player.name = "Remote_%s" % sid.validate_node_name()
	_get_root().add_child(player)
	if spawn_point != null:
		player.global_transform = spawn_point.global_transform
	remote_players[sid] = player
	var entry: Dictionary = NetworkManager.get_players().get(sid, {})
	_apply_remote_look(player, entry)
	var held := str(entry.get("held", ""))
	if not held.is_empty():
		player.set_remote_held_item(held)
	player.set_profile(str(entry.get("role", "")), int(entry.get("house", 0)))
	remote_player_spawned.emit(player)


func _on_player_left(sid: String, _display_name: String) -> void:
	var player: Node = remote_players.get(sid)
	if player == null:
		return
	remote_players.erase(sid)
	remote_player_removed.emit(player)
	player.queue_free()


func _on_player_state(sid: String, state: Dictionary) -> void:
	var player: Node = remote_players.get(sid)
	if player != null:
		player.synchronizer.receive_state(state)


func _on_spell_cast(sid: String, cast: Dictionary) -> void:
	var player: Node = remote_players.get(sid)
	if player == null:
		return
	var definition := SpellRegistry.load_definition(str(cast.get("id", "")))
	if definition == null:
		return
	player.synchronizer.receive_spell_cast(definition,
		NetworkProtocol.array_to_vec3(cast.get("o")), NetworkProtocol.array_to_vec3(cast.get("d")), clampi(int(cast.get("l", 0)), 0, SpellMastery.THRESHOLDS.size() - 1))


func _on_held_item(sid: String, item_id: String) -> void:
	var player: Node = remote_players.get(sid)
	if player != null:
		player.synchronizer.receive_held_item(item_id)


## Online: the server's copy is authoritative and arrives right after joining
## (usually before the world exists; on reconnect, after). Offline: the
## starting kit.
func _on_inventory(_state: Dictionary) -> void:
	_apply_local_inventory()


func _apply_local_inventory() -> void:
	if local_player == null:
		return
	var inventory: Inventory = local_player.inventory
	if NetworkManager.is_online():
		var state := NetworkManager.get_local_inventory()
		if not state.is_empty():
			inventory.load_state(state)
	else:
		inventory.load_state(ItemRegistry.default_state())


## Online: the server's profile (role, house, spellbook) is authoritative and
## arrives right after joining, again on reconnect and after every change.
## Offline there is no profile: the character is a student and learns from tomes.
func _on_profile(_profile: Dictionary) -> void:
	_apply_local_profile()


func _apply_local_profile() -> void:
	if local_player == null or not NetworkManager.is_online():
		return
	var profile := NetworkManager.get_local_profile()
	if profile.is_empty():
		return
	local_player.set_profile(str(profile.get("role", "")), int(profile.get("house", 0)))
	var look: Dictionary = profile.get("appearance", {})
	local_player.set_look(look)
	local_player.synchronizer.apply_server_spellbook(profile.get("spells", {}))
	(local_player.spell_caster as SpellCaster).mastery = profile.get("mastery", {}).duplicate()
	if not look.get("set", false) and not _creator_offered:
		_creator_offered = true
		GameEvents.character_creator_requested.emit.call_deferred()


func _on_player_profile_changed(sid: String, role: String, house: int) -> void:
	var player: Node = remote_players.get(sid)
	if player != null:
		player.set_profile(role, house)


func _on_spell_granted(spell_id: String, by_name: String) -> void:
	var definition := SpellRegistry.load_definition(spell_id)
	if definition == null:
		return
	if by_name.is_empty():
		GameEvents.notification_requested.emit(tr("NOTIFY_SPELL_LEARNED") % tr(definition.display_name), 6.0)
	else:
		GameEvents.notification_requested.emit(tr("NOTIFY_SPELL_TAUGHT") % [by_name, tr(definition.display_name)], 6.0)


func _on_disconnected(_reason: String) -> void:
	for sid in remote_players.keys():
		_on_player_left(sid, "")

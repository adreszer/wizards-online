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


func _exit_tree() -> void:
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
		NetworkProtocol.array_to_vec3(cast.get("o")), NetworkProtocol.array_to_vec3(cast.get("d")))


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
	local_player.synchronizer.apply_server_spellbook(profile.get("spells", {}))


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

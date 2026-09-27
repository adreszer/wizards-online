extends Node
## Networking boundary. Autoload: `NetworkManager`.
##
## The ONLY place gameplay may go to talk to the network. Composed of
## NakamaAuthentication, WorldSession, StateSynchronizer and ChatManager.
## Everything degrades gracefully: when offline or the backend is down, all
## send_* calls are no-ops and status/error signals carry a readable reason.

enum Status { OFFLINE, CONNECTING, ONLINE, ERROR }

signal status_changed(status: Status, message: String)
signal connected()
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal player_joined(sid: String, display_name: String)
signal player_left(sid: String, display_name: String)
signal player_state_received(sid: String, state: Dictionary)
signal spell_cast_received(sid: String, cast: Dictionary)
## A remote player took an item into their hand ("" = put it away). Validated by the server.
signal held_item_received(sid: String, item_id: String)
## The server sent the local player's inventory (on join and reconnect).
signal inventory_received(state: Dictionary)
## The server sent the local player's character profile {house, role, spells} (join, reconnect, changes).
signal profile_received(profile: Dictionary)
## A remote player's role/house changed.
signal player_profile_changed(sid: String, role: String, house: int)
## A professor (or a practice tome) taught the local player a spell.
signal spell_granted(spell_id: String, by_name: String)
## Outcome of a grant the local player requested as a professor.
signal grant_result_received(ok: bool, sid: String, spell_id: String, reason: String)
signal chat_message_received(sender_name: String, text: String, is_self: bool)
signal system_message(text: String)

const CONNECT_TIMEOUT_SECONDS := 5

var status: Status = Status.OFFLINE
var last_error: String = ""
var local_user_id: String = ""
var local_display_name: String = ""

@onready var authentication: NakamaAuthentication = $Authentication
@onready var world_session: WorldSession = $WorldSession
@onready var state_synchronizer: StateSynchronizer = $StateSynchronizer
@onready var chat_manager: ChatManager = $ChatManager

var _reconnect_attempts: int = 0
var _reconnecting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	state_synchronizer.bind(world_session)
	state_synchronizer.player_joined.connect(_on_player_joined)
	state_synchronizer.player_left.connect(_on_player_left)
	state_synchronizer.player_state_received.connect(player_state_received.emit)
	state_synchronizer.spell_cast_received.connect(spell_cast_received.emit)
	state_synchronizer.held_item_received.connect(held_item_received.emit)
	state_synchronizer.inventory_received.connect(inventory_received.emit)
	state_synchronizer.profile_received.connect(profile_received.emit)
	state_synchronizer.player_profile_changed.connect(player_profile_changed.emit)
	state_synchronizer.spell_granted.connect(spell_granted.emit)
	state_synchronizer.grant_result_received.connect(grant_result_received.emit)
	chat_manager.message_received.connect(chat_message_received.emit)
	world_session.socket_closed.connect(_on_socket_closed)


func is_online() -> bool:
	return status == Status.ONLINE


func get_ping_ms() -> int:
	return state_synchronizer.ping_ms if is_online() else -1


func get_player_count() -> int:
	return (state_synchronizer.players.size() + 1) if is_online() else 0


func get_players() -> Dictionary:
	return state_synchronizer.players


## The local player's server-side inventory ({items, held}); empty when offline
## or not received yet.
func get_local_inventory() -> Dictionary:
	return state_synchronizer.local_inventory if is_online() else {}


## The local player's server-side character profile ({house, role, spells});
## empty when offline or not received yet.
func get_local_profile() -> Dictionary:
	return state_synchronizer.local_profile if is_online() else {}


## Role of the local character: "student" offline or before the profile arrives.
func get_local_role() -> String:
	return str(get_local_profile().get("role", CharacterProfile.ROLE_STUDENT))


func is_local_staff() -> bool:
	return CharacterProfile.is_staff(get_local_role())


## Full connect flow: authenticate → socket → join world match → join chat.
## Returns "" on success, otherwise a human-readable error (also emitted).
func connect_online(display_name: String) -> String:
	if status == Status.CONNECTING:
		return tr("NET_ALREADY_CONNECTING")
	if status == Status.ONLINE:
		return ""
	local_display_name = display_name
	_set_status(Status.CONNECTING, tr("NET_CONNECTING_TO") % [GameSession.nakama_host, GameSession.nakama_port])
	authentication.create_client(
		GameSession.nakama_host, GameSession.nakama_port,
		str(ProjectSettings.get_setting("game/network/scheme", "http")),
		str(ProjectSettings.get_setting("game/network/server_key", "defaultkey")),
		CONNECT_TIMEOUT_SECONDS)
	var err: String = await authentication.authenticate(display_name)
	if err.is_empty():
		local_user_id = authentication.user_id
		err = await world_session.connect_socket(authentication.client, authentication.session)
	if err.is_empty():
		err = await world_session.join_world(authentication.client, authentication.session, display_name, GameSession.character_id)
	if err.is_empty():
		err = await chat_manager.join(world_session.socket, local_user_id, display_name, state_synchronizer.get_display_name_for_user)
	if not err.is_empty():
		await _teardown()
		_set_status(Status.ERROR, err)
		connection_failed.emit(err)
		return err
	_reconnect_attempts = 0
	_set_status(Status.ONLINE, tr("NET_ONLINE_AS") % display_name)
	connected.emit()
	return ""


## `reason` is shown to the player; defaults to the localized "Disconnected".
func disconnect_online(reason: String = "") -> void:
	if status == Status.OFFLINE:
		return
	if reason.is_empty():
		reason = tr("NET_DISCONNECTED")
	await _teardown()
	_set_status(Status.OFFLINE, reason)
	disconnected.emit(reason)


func send_player_state(state: Dictionary) -> void:
	if is_online():
		state_synchronizer.send_state(state)


func send_spell_cast(cast: Dictionary) -> void:
	if is_online():
		state_synchronizer.send_spell_cast(cast)


func send_held_item(item_id: String) -> void:
	if is_online():
		state_synchronizer.send_held_item(item_id)


## Tells the server which named area the local player is in ("" = none).
func send_area(area_id: String) -> void:
	if is_online():
		state_synchronizer.send_area(area_id)


## Professor/admin: teach `spell_id` to the player with session `sid`. The
## server answers with grant_result_received.
func send_grant_spell(sid: String, spell_id: String) -> void:
	if is_online():
		state_synchronizer.send_grant_spell(sid, spell_id)


## Persist the local hotbar layout.
func send_spellbook(slots: Array, equipped: String) -> void:
	if is_online():
		state_synchronizer.send_spellbook(slots, equipped)


## Ask the server for a practice tome's spell (it arrives via profile_received).
func send_study_tome(spell_id: String) -> void:
	if is_online():
		state_synchronizer.send_study_tome(spell_id)


## Admin RPC: change a player's role and/or house by user id or display name.
## With `http_key` set the call is server-to-server (dev tooling, tests);
## otherwise the local session must be an admin. Returns the server's answer
## or {"error": message}.
func admin_set_profile(request: Dictionary, http_key: String = "") -> Dictionary:
	if authentication.client == null:
		return {"error": tr("HUD_STATUS_OFFLINE")}
	var rpc: NakamaAPI.ApiRpc
	if not http_key.is_empty():
		rpc = await authentication.client.rpc_async_with_key(http_key, NetworkProtocol.RPC_ADMIN_SET_PROFILE, NetworkProtocol.encode(request))
	elif authentication.session != null:
		rpc = await authentication.client.rpc_async(authentication.session, NetworkProtocol.RPC_ADMIN_SET_PROFILE, NetworkProtocol.encode(request))
	else:
		return {"error": tr("HUD_STATUS_OFFLINE")}
	if rpc.is_exception():
		return {"error": rpc.get_exception().message}
	return NetworkProtocol.decode(rpc.payload)


func send_chat(text: String) -> bool:
	if not is_online():
		system_message.emit(tr("CHAT_OFFLINE"))
		return false
	return chat_manager.send(text)


func _teardown() -> void:
	chat_manager.leave()
	await world_session.leave()
	state_synchronizer.reset()


func _set_status(new_status: Status, message: String) -> void:
	status = new_status
	if new_status == Status.ERROR:
		last_error = message
	status_changed.emit(new_status, message)


func _on_player_joined(sid: String, display_name: String) -> void:
	player_joined.emit(sid, display_name)
	system_message.emit(tr("CHAT_PLAYER_JOINED") % display_name)


func _on_player_left(sid: String, display_name: String) -> void:
	player_left.emit(sid, display_name)
	system_message.emit(tr("CHAT_PLAYER_LEFT") % display_name)


## Abrupt socket loss: drop remote players and try to reconnect a few times.
func _on_socket_closed() -> void:
	if status != Status.ONLINE or _reconnecting:
		return
	_reconnecting = true
	for sid in state_synchronizer.players.keys():
		player_left.emit(sid, state_synchronizer.get_display_name(sid))
	state_synchronizer.reset()
	chat_manager.leave()
	_set_status(Status.CONNECTING, tr("NET_CONNECTION_LOST"))
	system_message.emit(tr("CHAT_CONNECTION_LOST"))
	var name := local_display_name
	while _reconnect_attempts < 3:
		_reconnect_attempts += 1
		await get_tree().create_timer(2.0 * _reconnect_attempts).timeout
		status = Status.OFFLINE
		var err: String = await connect_online(name)
		if err.is_empty():
			system_message.emit(tr("CHAT_RECONNECTED"))
			_reconnecting = false
			return
	_reconnecting = false
	_set_status(Status.ERROR, tr("NET_RECONNECT_FAILED_OFFLINE"))
	disconnected.emit(tr("NET_RECONNECT_FAILED"))
	system_message.emit(tr("CHAT_RECONNECT_FAILED"))

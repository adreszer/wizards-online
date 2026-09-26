class_name WorldSession
extends Node
## Owns the realtime socket and membership of the shared "world" match.
## Raw Nakama match events are decoded here and re-emitted as plain signals.

signal socket_closed()
signal roster_received(players: Array, self_sid: String)
signal player_joined(sid: String, uid: String, display_name: String, character_id: String)
signal player_left(sid: String, uid: String, display_name: String)
signal state_received(sid: String, state: Dictionary)
signal spell_cast_received(sid: String, cast: Dictionary)
signal held_item_received(sid: String, item_id: String)
## The local player's own inventory as stored on the server.
signal inventory_received(state: Dictionary)
signal pong_received(sent_ms: int)

var socket: NakamaSocket
var match_id: String = ""
var self_session_id: String = ""
var _closing: bool = false


## Returns "" on success, otherwise an error string.
func connect_socket(client: NakamaClient, session: NakamaSession) -> String:
	socket = Nakama.create_socket_from(client)
	socket.received_match_state.connect(_on_match_state)
	socket.received_match_presence.connect(_on_match_presence)
	socket.closed.connect(_on_closed)
	var result: NakamaAsyncResult = await socket.connect_async(session, true)
	if result.is_exception():
		return tr("NET_SOCKET_FAILED") % result.get_exception().message
	return ""


## Asks the server module for the shared world match and joins it.
func join_world(client: NakamaClient, session: NakamaSession, display_name: String, character_id: String = "") -> String:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "join_world", "{}")
	if rpc.is_exception():
		return tr("NET_JOIN_RPC_FAILED") % rpc.get_exception().message
	var payload := NetworkProtocol.decode(rpc.payload)
	match_id = str(payload.get("match_id", ""))
	if match_id.is_empty():
		return tr("NET_JOIN_NO_MATCH")
	var joined: NakamaRTAPI.Match = await socket.join_match_async(match_id, {"display_name": display_name, "character": character_id})
	if joined.is_exception():
		return tr("NET_JOIN_FAILED") % joined.get_exception().message
	if joined.self_user != null:
		self_session_id = joined.self_user.session_id
	return ""


func leave() -> void:
	_closing = true
	if socket != null:
		if not match_id.is_empty() and socket.is_connected_to_host():
			await socket.leave_match_async(match_id)
		socket.close()
	match_id = ""
	socket = null
	_closing = false


func is_active() -> bool:
	return socket != null and socket.is_connected_to_host() and not match_id.is_empty()


func send(op_code: int, data: Dictionary) -> void:
	if not is_active():
		return
	socket.send_match_state_async(match_id, op_code, NetworkProtocol.encode(data))


func _on_match_state(data: NakamaRTAPI.MatchData) -> void:
	if data.match_id != match_id:
		return
	var payload := NetworkProtocol.decode(data.data)
	var sender_sid := data.presence.session_id if data.presence != null else ""
	match data.op_code:
		NetworkProtocol.OP_STATE:
			state_received.emit(sender_sid, payload)
		NetworkProtocol.OP_SPELL_CAST:
			spell_cast_received.emit(sender_sid, payload)
		NetworkProtocol.OP_HELD_ITEM:
			held_item_received.emit(str(payload.get("sid", sender_sid)), str(payload.get("id", "")))
		NetworkProtocol.OP_INVENTORY:
			inventory_received.emit(payload)
		NetworkProtocol.OP_ROSTER:
			self_session_id = str(payload.get("self_sid", self_session_id))
			roster_received.emit(payload.get("players", []), self_session_id)
		NetworkProtocol.OP_PLAYER_JOINED:
			player_joined.emit(str(payload.get("sid", "")), str(payload.get("uid", "")), str(payload.get("name", "")), str(payload.get("char", "")))
		NetworkProtocol.OP_PLAYER_LEFT:
			player_left.emit(str(payload.get("sid", "")), str(payload.get("uid", "")), str(payload.get("name", "")))
		NetworkProtocol.OP_PING:
			pong_received.emit(int(payload.get("t", 0)))


## The server module is the source of truth for the roster, so raw presence
## events are only used as a fallback for leaves (e.g. abrupt disconnects).
func _on_match_presence(event: NakamaRTAPI.MatchPresenceEvent) -> void:
	if event.match_id != match_id:
		return
	for presence in event.leaves:
		player_left.emit(presence.session_id, presence.user_id, presence.username)


func _on_closed() -> void:
	if _closing:
		return
	match_id = ""
	socket_closed.emit()

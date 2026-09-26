class_name StateSynchronizer
extends Node
## Routes gameplay state between local components and the WorldSession.
## Keeps the roster (session id → display name) and the latency estimate.

signal player_joined(sid: String, display_name: String)
signal player_left(sid: String, display_name: String)
signal player_state_received(sid: String, state: Dictionary)
signal spell_cast_received(sid: String, cast: Dictionary)
signal held_item_received(sid: String, item_id: String)
signal inventory_received(state: Dictionary)

@export var ping_interval: float = 2.0

var session: WorldSession
## sid -> {uid, name, char, held}
var players: Dictionary = {}
## The local player's server-side inventory ({items, held}); empty until received.
var local_inventory: Dictionary = {}
var ping_ms: int = -1
var _ping_timer: float = 0.0


func bind(p_session: WorldSession) -> void:
	session = p_session
	session.roster_received.connect(_on_roster)
	session.player_joined.connect(_on_player_joined)
	session.player_left.connect(_on_player_left)
	session.state_received.connect(_on_state)
	session.spell_cast_received.connect(_on_spell_cast)
	session.held_item_received.connect(_on_held_item)
	session.inventory_received.connect(_on_inventory)
	session.pong_received.connect(_on_pong)


func reset() -> void:
	players.clear()
	local_inventory = {}
	ping_ms = -1


func send_state(state: Dictionary) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_STATE, state)


func send_spell_cast(cast: Dictionary) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_SPELL_CAST, cast)


func send_held_item(item_id: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_HELD_ITEM, {"id": item_id})


func get_held_item(sid: String) -> String:
	var entry: Dictionary = players.get(sid, {})
	return str(entry.get("held", ""))


func get_display_name(sid: String) -> String:
	var entry: Dictionary = players.get(sid, {})
	return str(entry.get("name", ""))


func get_display_name_for_user(uid: String) -> String:
	for entry in players.values():
		if entry.get("uid", "") == uid:
			return str(entry.get("name", ""))
	return ""


func _process(delta: float) -> void:
	if session == null or not session.is_active():
		return
	_ping_timer += delta
	if _ping_timer >= ping_interval:
		_ping_timer = 0.0
		session.send(NetworkProtocol.OP_PING, {"t": Time.get_ticks_msec()})


func _on_roster(roster: Array, self_sid: String) -> void:
	for entry in roster:
		var sid := str(entry.get("sid", ""))
		if sid.is_empty() or sid == self_sid:
			continue
		if not players.has(sid):
			players[sid] = {"uid": str(entry.get("uid", "")), "name": str(entry.get("name", "?")), "char": str(entry.get("char", "")), "held": ItemRegistry.sanitize(str(entry.get("held", "")))}
			player_joined.emit(sid, players[sid]["name"])


func _on_player_joined(sid: String, uid: String, display_name: String, character_id: String = "") -> void:
	if sid.is_empty() or sid == session.self_session_id or players.has(sid):
		return
	players[sid] = {"uid": uid, "name": display_name, "char": character_id, "held": ""}
	player_joined.emit(sid, display_name)


func _on_player_left(sid: String, _uid: String, display_name: String) -> void:
	if not players.has(sid):
		return
	var known_name: String = players[sid]["name"]
	players.erase(sid)
	player_left.emit(sid, known_name if not known_name.is_empty() else display_name)


func _on_state(sid: String, state: Dictionary) -> void:
	if players.has(sid):
		player_state_received.emit(sid, state)


func _on_spell_cast(sid: String, cast: Dictionary) -> void:
	if players.has(sid):
		spell_cast_received.emit(sid, cast)


func _on_held_item(sid: String, item_id: String) -> void:
	if not players.has(sid):
		return
	var clean := ItemRegistry.sanitize(item_id)
	players[sid]["held"] = clean
	held_item_received.emit(sid, clean)


func _on_inventory(state: Dictionary) -> void:
	local_inventory = state
	inventory_received.emit(state)


func _on_pong(sent_ms: int) -> void:
	ping_ms = maxi(0, Time.get_ticks_msec() - sent_ms)

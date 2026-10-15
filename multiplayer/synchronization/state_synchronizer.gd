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
signal profile_received(profile: Dictionary)
## A remote player's role/house changed (also fired for roster entries on join).
signal player_profile_changed(sid: String, role: String, house: int)
signal spell_granted(spell_id: String, by_name: String)
signal grant_result_received(ok: bool, sid: String, spell_id: String, reason: String)
signal sort_result_received(ok: bool, house: int, reason: String)
## A world object's server state changed (null = default).
signal object_state_changed(object_id: String, state: Variant)
## A full snapshot of world object states arrived (join / reconnect).
signal world_snapshot_received(objects: Dictionary)
signal server_text_received(text: String, seconds: float)
signal lessons_changed(lessons: Dictionary)
signal lesson_result_received(ok: bool, action: String, reason: String)
signal house_totals_changed(totals: PackedInt32Array)
signal house_points_result_received(ok: bool, house: int, delta: int, reason: String)
signal lecture_received(by_name: String, text: String)
signal cheat_result_received(ok: bool, item_id: String, reason: String)

@export var ping_interval: float = 2.0

var session: WorldSession
## sid -> {uid, name, char, held, role, house}
var players: Dictionary = {}
## The local player's server-side inventory ({items, held}); empty until received.
var local_inventory: Dictionary = {}
## The local player's server-side character profile ({house, role, spells}); empty until received.
var local_profile: Dictionary = {}
## Server state of world objects that are not in their default state: object id → state.
var world_objects: Dictionary = {}
## Open lessons: area id → {subject, by, sid}.
var lessons: Dictionary = {}
## House points, index 0 = house 1; empty until received.
var house_totals: PackedInt32Array = PackedInt32Array()
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
	session.profile_received.connect(_on_profile)
	session.roster_update_received.connect(_on_roster_update)
	session.spell_granted.connect(spell_granted.emit)
	session.grant_result_received.connect(grant_result_received.emit)
	session.sort_result_received.connect(sort_result_received.emit)
	session.pong_received.connect(_on_pong)
	session.object_state_received.connect(_on_object_state)
	session.world_snapshot_received.connect(_on_world_snapshot)
	session.server_text_received.connect(server_text_received.emit)
	session.lessons_received.connect(_on_lessons)
	session.lesson_result_received.connect(lesson_result_received.emit)
	session.house_totals_received.connect(_on_house_totals)
	session.house_points_result_received.connect(house_points_result_received.emit)
	session.lecture_received.connect(lecture_received.emit)
	session.cheat_result_received.connect(cheat_result_received.emit)


func reset() -> void:
	players.clear()
	local_inventory = {}
	local_profile = {}
	world_objects = {}
	lessons = {}
	house_totals = PackedInt32Array()
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


func send_area(area_id: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_AREA, {"id": area_id})


func send_grant_spell(sid: String, spell_id: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_GRANT_SPELL, {"sid": sid, "id": spell_id})


func send_spellbook(slots: Array, equipped: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_SPELLBOOK, {"slots": slots, "equipped": equipped})


func send_study_tome(spell_id: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_STUDY_TOME, {"id": spell_id})


func send_sort(answers: Array) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_SORT, {"answers": answers})


func send_world_event(object_id: String, event: String, spell_id: String = "") -> void:
	if session != null:
		var data := {"o": object_id, "e": event}
		if not spell_id.is_empty():
			data["spell"] = spell_id
		session.send(NetworkProtocol.OP_WORLD_EVENT, data)


func send_lesson(action: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_LESSON, {"action": action})


func send_house_points(house: int, delta: int, reason: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_HOUSE_POINTS, {"house": house, "delta": delta, "reason": reason})


func send_cheat_give(item_id: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_CHEAT, {"give": item_id})


func send_lecture(text: String) -> void:
	if session != null:
		session.send(NetworkProtocol.OP_LECTURE, {"text": text})


func get_role(sid: String) -> String:
	var entry: Dictionary = players.get(sid, {})
	return str(entry.get("role", CharacterProfile.ROLE_STUDENT))


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
			players[sid] = {"uid": str(entry.get("uid", "")), "name": str(entry.get("name", "?")), "char": str(entry.get("char", "")), "held": ItemRegistry.sanitize(str(entry.get("held", ""))),
				"role": CharacterProfile.sanitize_role(str(entry.get("role", ""))), "house": CharacterProfile.sanitize_house(int(entry.get("house", 0)))}
			player_joined.emit(sid, players[sid]["name"])


func _on_player_joined(sid: String, uid: String, display_name: String, character_id: String = "", role: String = "", house: int = 0) -> void:
	if sid.is_empty() or sid == session.self_session_id or players.has(sid):
		return
	players[sid] = {"uid": uid, "name": display_name, "char": character_id, "held": "", "role": CharacterProfile.sanitize_role(role), "house": CharacterProfile.sanitize_house(house)}
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


func _on_profile(profile: Dictionary) -> void:
	local_profile = CharacterProfile.sanitize(profile)
	profile_received.emit(local_profile)


func _on_roster_update(sid: String, role: String, house: int) -> void:
	if not players.has(sid):
		return
	players[sid]["role"] = CharacterProfile.sanitize_role(role)
	players[sid]["house"] = CharacterProfile.sanitize_house(house)
	player_profile_changed.emit(sid, players[sid]["role"], players[sid]["house"])


func _on_pong(sent_ms: int) -> void:
	ping_ms = maxi(0, Time.get_ticks_msec() - sent_ms)


func _on_object_state(object_id: String, state: Variant) -> void:
	if object_id.is_empty():
		return
	if state == null:
		world_objects.erase(object_id)
	else:
		world_objects[object_id] = state
	object_state_changed.emit(object_id, state)


func _on_world_snapshot(objects: Dictionary) -> void:
	world_objects = objects.duplicate()
	world_snapshot_received.emit(world_objects)


func _on_lessons(p_lessons: Dictionary) -> void:
	lessons = p_lessons.duplicate(true)
	lessons_changed.emit(lessons)


func _on_house_totals(totals: Array) -> void:
	var clean := PackedInt32Array()
	for h in CharacterProfile.MAX_HOUSE:
		clean.append(int(totals[h]) if h < totals.size() else 0)
	house_totals = clean
	house_totals_changed.emit(house_totals)

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
## Outcome of the local player's sorting ceremony (the profile arrives separately).
signal sort_result_received(ok: bool, house: int, reason: String)
## A world object's server-side state changed (null = default). See WorldObjectSync.
signal object_state_changed(object_id: String, state: Variant)
## The server's world object states arrived in full (join and reconnect).
signal world_snapshot_received(objects: Dictionary)
## Server-only text (a mystery's clue or reward) in the player's language; also
## shown as a HUD notification.
signal server_text_received(text: String, seconds: float)
## The set of open lessons changed (area id → {subject, by, sid}).
signal lessons_changed(lessons: Dictionary)
## Outcome of the local professor's lesson open/close request.
signal lesson_result_received(ok: bool, action: String, reason: String)
## The house points tally changed (index 0 = house 1).
signal house_totals_changed(totals: PackedInt32Array)
## Outcome of the local professor's award/deduction.
signal house_points_result_received(ok: bool, house: int, delta: int, reason: String)
## A professor spoke to the local player's classroom (also shown in chat).
signal lecture_received(by_name: String, text: String)
## Outcome of a cheat the local player sent (see ChatCommands).
signal cheat_result_received(ok: bool, item_id: String, reason: String)
## The local player's purse changed: the new balance and what changed it (delta 0 on
## join; source "lesson" | "mystery" | "admin" | "shop", detail: subject, mystery or reason).
signal wallet_changed(coins: int, delta: int, source: String, detail: String)
## The school clock changed (server OP_CLOCK, or /time offline); `by_name` is who
## moved it ("" for the join snapshot).
signal school_clock_changed(by_name: String)
## The server sent the timetable (on join, each new school day, after a reload).
signal timetable_changed()
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

var clock := ServerClock.new()
## Time of day (see school_hours()); the server's settings online, defaults offline.
var school_clock := SchoolClock.new()
## The school week in real time (empty offline; see Timetable).
var timetable := Timetable.new()
## Offline practice purse (the /coins cheat); never saved, the real one is the server's wallet.
var offline_coins: int = 0
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
	state_synchronizer.sort_result_received.connect(sort_result_received.emit)
	state_synchronizer.object_state_changed.connect(object_state_changed.emit)
	state_synchronizer.world_snapshot_received.connect(world_snapshot_received.emit)
	state_synchronizer.server_text_received.connect(_on_server_text)
	state_synchronizer.lessons_changed.connect(lessons_changed.emit)
	state_synchronizer.lesson_result_received.connect(lesson_result_received.emit)
	state_synchronizer.house_totals_changed.connect(house_totals_changed.emit)
	state_synchronizer.house_points_result_received.connect(house_points_result_received.emit)
	state_synchronizer.lecture_received.connect(_on_lecture)
	state_synchronizer.cheat_result_received.connect(cheat_result_received.emit)
	state_synchronizer.wallet_changed.connect(wallet_changed.emit)
	state_synchronizer.clock_received.connect(func(payload: Dictionary) -> void:
		school_clock.apply(payload)
		school_clock_changed.emit(str(payload.get("by", ""))))
	state_synchronizer.timetable_received.connect(func(payload: Dictionary) -> void:
		timetable.apply(payload)
		timetable_changed.emit())
	chat_manager.message_received.connect(chat_message_received.emit)
	world_session.socket_closed.connect(_on_socket_closed)
	world_session.server_clock_received.connect(func(server_ms: float, sent_ms: int) -> void:
		clock.add_sample(server_ms, Time.get_ticks_msec() - sent_ms if sent_ms >= 0 else -1))


func is_online() -> bool:
	return status == Status.ONLINE


## True while the local player is in the shared world match: world objects then
## follow the server instead of local triggers.
func is_in_world() -> bool:
	return is_online() and world_session.is_active()


## Server state of world objects not in their default state (object id → state);
## empty offline.
func get_world_object_states() -> Dictionary:
	return state_synchronizer.world_objects if is_online() else {}


## The world's shared time in seconds (the server's clock when online, the local system
## clock offline). Scheduled movers (shifting stairs, clockwork) take their pose from it,
## so every client sees the same castle at the same moment.
func server_time() -> float:
	return clock.now() if is_online() else ServerClock.local_seconds()


## The school's time of day in hours (0 ≤ h < 24), the same on every client.
func school_hours() -> float:
	return school_clock.hours_at(server_time())


## Move the school clock to `hours`: online a cheat request (the server answers with
## OP_CLOCK for everyone), offline the local clock moves at once.
func set_school_hours(hours: float) -> void:
	if is_in_world():
		state_synchronizer.send_cheat_time(hours)
	else:
		school_clock.offset = school_clock.offset_for(server_time(), hours)
		school_clock_changed.emit("")


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


## Ask the server to apply an event to a world object ("spell" with the spell id,
## or "interact"). The new state arrives through object_state_changed.
func send_world_event(object_id: String, event: String, spell_id: String = "") -> void:
	if is_online():
		state_synchronizer.send_world_event(object_id, event, spell_id)


## Cheat: ask the server for an item (answer: cheat_result_received, then the inventory).
func send_cheat_give(item_id: String) -> void:
	if is_online():
		state_synchronizer.send_cheat_give(item_id)


## Professor/admin: open or close the lesson in the current classroom.
func send_lesson(action: String) -> void:
	if is_online():
		state_synchronizer.send_lesson(action)


## Professor/admin: award (delta > 0) or deduct house points, with a reason.
func send_house_points(house: int, delta: int, reason: String) -> void:
	if is_online():
		state_synchronizer.send_house_points(house, delta, reason)


## Professor running a lesson: one line of lecture text for the room.
func send_lecture(text: String) -> void:
	if is_online():
		state_synchronizer.send_lecture(text)


## Open lessons (area id → {subject, by, sid}); empty offline.
func get_lessons() -> Dictionary:
	return state_synchronizer.lessons if is_online() else {}


## The local player's coins: the server's wallet online (0 before it arrives), a
## practice purse offline (dev cheat only; it is not saved).
func get_coins() -> int:
	return maxi(0, state_synchronizer.coins) if is_online() else offline_coins


## Dev cheat /coins: online the server changes the purse (answered by wallet_changed),
## offline the practice purse changes at once.
func cheat_coins(amount: int) -> void:
	if is_in_world():
		state_synchronizer.send_cheat_coins(amount)
	else:
		var before := offline_coins
		offline_coins = maxi(0, offline_coins + amount)
		wallet_changed.emit(offline_coins, offline_coins - before, "admin", "cheat")


## The purse and its history, newest first: {coins, entries: [{delta, source, reason,
## by_name, subject, area, at}]}; admins may pass `user_id`.
func wallet_ledger(limit: int = 50, user_id: String = "", http_key: String = "") -> Dictionary:
	var request := {"limit": limit}
	if not user_id.is_empty():
		request["user_id"] = user_id
	return await _admin_rpc(NetworkProtocol.RPC_WALLET_LEDGER, request, http_key)


## Admin RPC: add (amount > 0) or take coins from a player by user id or display name, with a reason.
func admin_grant_coins(request: Dictionary, http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_ADMIN_GRANT_COINS, request, http_key)


## House points tally (index 0 = house 1); empty offline or before it arrives.
func get_house_totals() -> PackedInt32Array:
	return state_synchronizer.house_totals if is_online() else PackedInt32Array()


## Staff RPC: the local professor's lesson plans [{id, title, lines}].
func list_lesson_plans() -> Array:
	var answer := await _session_rpc(NetworkProtocol.RPC_LESSON_PLAN_LIST, {})
	var plans: Variant = answer.get("plans", [])
	return plans if plans is Array else []


## Staff RPC: store a lesson plan (new when `id` is empty). Returns {id} or {error}.
func save_lesson_plan(id: String, title: String, lines: PackedStringArray) -> Dictionary:
	var request := {"title": title, "lines": Array(lines)}
	if not id.is_empty():
		request["id"] = id
	return await _session_rpc(NetworkProtocol.RPC_LESSON_PLAN_SAVE, request)


## A student's school record (attendance and quizzes per subject, recent lessons):
## your own, or (staff) anyone's by user id. {user_id, record} or {error}.
func school_record(user_id: String = "", http_key: String = "") -> Dictionary:
	var request := {}
	if not user_id.is_empty():
		request["user_id"] = user_id
	return await _admin_rpc(NetworkProtocol.RPC_SCHOOL_RECORD, request, http_key)


## Admin RPC: the lesson log (held lessons with attendance, timetabled ones not held).
func lesson_log(limit: int = 50, http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_LESSON_LOG, {"limit": limit}, http_key)


## Admin RPC: recent house points records, newest first.
func house_points_ledger(limit: int = 50, http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_HOUSE_POINTS_LEDGER, {"limit": limit}, http_key)


## Sorting ceremony: the server tallies the answers and assigns the house.
func send_sort(answers: Array) -> void:
	if is_online():
		state_synchronizer.send_sort(answers)


## House of the local character: 0 until sorted (or offline before the local ceremony).
func get_local_house() -> int:
	return int(get_local_profile().get("house", 0))


## Admin RPC: change a player's role and/or house by user id or display name.
## With `http_key` set the call is server-to-server (dev tooling, tests);
## otherwise the local session must be an admin. Returns the server's answer
## or {"error": message}.
func admin_set_profile(request: Dictionary, http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_ADMIN_SET_PROFILE, request, http_key)


## Admin RPC: every world object back to its default, shared mysteries unsolved
## (dev tooling and tests). Same access rules as admin_set_profile.
func admin_reset_world(http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_ADMIN_RESET_WORLD, {}, http_key)


## Re-reads nakama/content/timetable.json on the server and resends it to everyone.
func admin_reload_timetable(http_key: String = "") -> Dictionary:
	return await _admin_rpc(NetworkProtocol.RPC_ADMIN_RELOAD_TIMETABLE, {}, http_key)


func _session_rpc(rpc_id: String, request: Dictionary) -> Dictionary:
	return await _admin_rpc(rpc_id, request, "")


func _admin_rpc(rpc_id: String, request: Dictionary, http_key: String) -> Dictionary:
	if authentication.client == null:
		return {"error": tr("HUD_STATUS_OFFLINE")}
	var rpc: NakamaAPI.ApiRpc
	if not http_key.is_empty():
		rpc = await authentication.client.rpc_async_with_key(http_key, rpc_id, NetworkProtocol.encode(request))
	elif authentication.session != null:
		rpc = await authentication.client.rpc_async(authentication.session, rpc_id, NetworkProtocol.encode(request))
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


func _on_server_text(text: String, seconds: float) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	server_text_received.emit(clean, seconds)
	GameEvents.notification_requested.emit(clean, clampf(seconds, 1.0, 15.0))


func _on_lecture(by_name: String, text: String) -> void:
	var clean := NetworkProtocol.sanitize_chat(text)
	if clean.is_empty():
		return
	lecture_received.emit(by_name, clean)
	chat_message_received.emit(tr("LECTURE_SENDER") % by_name, clean, by_name == local_display_name)


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

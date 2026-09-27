extends Node
## Two-client multiplayer test against a running Nakama (docker compose up -d).
## Client A (observer):  godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=1 --name=ClientA
## Client B (actor):     godot --headless --path . tests/run_multiplayer_test.tscn -- --instance=2 --name=ClientB --role=b
## Start A first, then B within ~20 s. Each prints a summary and exits non-zero on failure.

const WORLD_SCENE := preload("res://core/world.tscn")
const ARCANE_PULSE := preload("res://resources/spells/arcane_pulse.tres")
const TestHelpers := preload("res://tests/test_helpers.gd")

var t := TestHelpers.new()
var role: String = "a"
var world: Node
var chat_lines: Array[String] = []
var system_lines: Array[String] = []
var casts_seen: int = 0
var joins: Array[String] = []
var leaves: Array[String] = []
var notifications: Array[String] = []
var grant_results: Array = []
var sort_results: Array = []

const HTTP_KEY := "defaulthttpkey"
const CLASSROOM := &"class_sigilcraft"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	NetworkManager.chat_message_received.connect(func(n: String, text: String, _s: bool) -> void: chat_lines.append("[%s] %s" % [n, text]))
	NetworkManager.system_message.connect(func(text: String) -> void: system_lines.append(text))
	NetworkManager.spell_cast_received.connect(func(_sid: String, _c: Dictionary) -> void: casts_seen += 1)
	NetworkManager.player_joined.connect(func(_sid: String, n: String) -> void: joins.append(n))
	NetworkManager.player_left.connect(func(_sid: String, n: String) -> void: leaves.append(n))
	NetworkManager.grant_result_received.connect(func(ok: bool, sid: String, id: String, reason: String) -> void: grant_results.append({"ok": ok, "sid": sid, "id": id, "reason": reason}))
	GameEvents.notification_requested.connect(func(text: String, _d: float) -> void: notifications.append(text))
	NetworkManager.sort_result_received.connect(func(ok: bool, house: int, reason: String) -> void: sort_results.append({"ok": ok, "house": house, "reason": reason}))
	await _run()


func _run() -> void:
	t.section("Connect (%s)" % role)
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	var err: String = await NetworkManager.connect_online(GameSession.display_name)
	if not t.check(err.is_empty(), "connect_online succeeds (%s)" % err):
		_finish()
		return
	t.check(NetworkManager.is_online(), "status is ONLINE")
	t.check(not NetworkManager.local_user_id.is_empty(), "has a Nakama user id")
	world = WORLD_SCENE.instantiate()
	add_child(world)
	await _wait(0.5)
	var spawner: PlayerSpawner = world.get_node("PlayerSpawner")
	t.check(spawner.local_player != null and spawner.local_player.is_local, "local player spawned")
	var inv: Inventory = spawner.local_player.inventory
	t.check(not NetworkManager.get_local_inventory().is_empty(), "server sent the inventory on join")
	t.check(inv.has(&"torch"), "local inventory holds the server-issued torch")
	var got_profile := await _wait_until(func() -> bool: return not NetworkManager.get_local_profile().is_empty(), 10.0)
	t.check(got_profile, "server sent the character profile on join")
	# Accounts persist between runs: start from a fresh student record (dev tooling path).
	var reset: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "role": "student", "house": 0, "forget_spells": true}, HTTP_KEY)
	t.check(reset.get("ok", false) == true, "test account reset to a fresh student (%s)" % str(reset))
	got_profile = await _wait_until(func() -> bool: return NetworkManager.get_local_role() == "student" and NetworkManager.get_local_house() == 0 and _known_spells().is_empty(), 10.0)
	t.check(got_profile and spawner.local_player.spell_caster.known_spells.is_empty(), "reset profile applied to the player")
	if role == "b":
		await _run_actor(spawner)
	else:
		await _run_observer(spawner)
	_finish()


func _finish() -> void:
	print(t.summary())
	await NetworkManager.disconnect_online("test done")
	get_tree().quit(1 if t.failed > 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Polls `predicate` until true or timeout. Returns whether it became true.
func _wait_until(predicate: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if predicate.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return predicate.call()


func _remote(spawner: PlayerSpawner) -> Node:
	if spawner.remote_players.is_empty():
		return null
	return spawner.remote_players.values()[0]


func _classroom_zone() -> AreaZone:
	for zone in world.get_node("Level").get_zones():
		if zone.area_id == CLASSROOM:
			return zone
	return null


## Teleports the local player onto the classroom floor (server learns the area from the zone event).
func _enter_classroom(spawner: PlayerSpawner, offset: Vector3) -> void:
	var zone := _classroom_zone()
	var floor_y := zone.global_position.y - zone.size.y / 2.0
	spawner.local_player.global_position = Vector3(zone.global_position.x, floor_y + 0.2, zone.global_position.z) + offset


func _known_spells() -> Array:
	return NetworkManager.get_local_profile().get("spells", {}).get("known", [])


# --- Observer (client A) ------------------------------------------------------------

func _run_observer(spawner: PlayerSpawner) -> void:
	t.section("Observer")
	# Become a professor through the admin RPC (server-to-server key, as dev tooling would).
	t.check(NetworkManager.get_local_role() == "student", "a fresh character is a student")
	var answer: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "role": "professor"}, HTTP_KEY)
	t.check(answer.get("ok", false) == true and answer.get("role", "") == "professor", "admin_set_profile promotes by user id (%s)" % str(answer))
	var ok := await _wait_until(func() -> bool: return NetworkManager.get_local_role() == "professor", 10.0)
	t.check(ok and spawner.local_player.role == "professor", "the live match pushed the new role to the player")
	var by_name: Dictionary = await NetworkManager.admin_set_profile({"name": "ClientA", "house": 2}, HTTP_KEY)
	t.check(by_name.get("ok", false) == true and int(by_name.get("house", 0)) == 2, "admin_set_profile finds an online player by display name (%s)" % str(by_name))
	var bad: Dictionary = await NetworkManager.admin_set_profile({"name": "Nobody", "role": "professor"}, HTTP_KEY)
	t.check(bad.has("error"), "promoting an unknown name is an error (%s)" % str(bad))
	ok = await _wait_until(func() -> bool: return _remote(spawner) != null, 40.0)
	if not t.check(ok, "remote player spawns when B joins"):
		return
	var remote := _remote(spawner)
	t.check(not remote.is_local and remote.display_name == "ClientB", "remote player is not local and has B's name (%s)" % remote.display_name)
	t.check(remote.get_node_or_null("LocalPlayer") == null, "remote player has no LocalPlayer subtree (no camera/input)")
	t.check(joins.has("ClientB"), "join event received for ClientB")
	var joined_line: String = tr("CHAT_PLAYER_JOINED") % "ClientB"
	t.check(system_lines.has(joined_line), "join system message shown (%s)" % joined_line)
	t.check(NetworkManager.get_player_count() == 2, "player count is 2")

	var start_pos: Vector3 = remote.global_position
	var states_seen: Dictionary = {}
	var max_y := start_pos.y
	var samples: Array[Vector3] = []
	var moved := false
	var elapsed := 0.0
	while elapsed < 20.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not is_instance_valid(remote):
			break
		states_seen[remote.animation_controller.current_state_name] = true
		max_y = maxf(max_y, remote.global_position.y)
		samples.append(remote.global_position)
		if remote.global_position.distance_to(start_pos) > 2.0:
			moved = true
		if moved and (states_seen.has("jump") or states_seen.has("fall")) and chat_lines.size() > 0:
			break
	t.check(moved, "remote player moves across the network")
	# Smoothness: no single-frame jump larger than a plausible interpolated step.
	var max_step := 0.0
	for i in range(1, samples.size()):
		max_step = maxf(max_step, samples[i].distance_to(samples[i - 1]))
	t.check(max_step < 1.0, "remote movement is interpolated, largest per-frame step %.2f m" % max_step)
	t.check(states_seen.has("walk") or states_seen.has("run"), "remote animation state shows walking/running (%s)" % str(states_seen.keys()))
	t.check(states_seen.has("jump") or states_seen.has("fall") or max_y > start_pos.y + 0.5, "remote jump replicates (max y %.2f)" % max_y)
	t.check(remote.role == "student" and remote.nameplate.text == "ClientB", "remote student has a plain nameplate")
	ok = await _wait_until(func() -> bool: return is_instance_valid(remote) and remote.held_item_mount.is_holding(), 10.0)
	t.check(ok, "remote player's torch shows up when B holds it")
	t.check(NetworkManager.get_players().values().any(func(e: Dictionary) -> bool: return e.get("held", "") == "torch"), "roster tracks B's held item")
	t.check(chat_lines.any(func(l: String) -> bool: return l == "[ClientB] hello from B"), "chat message from B received: %s" % str(chat_lines))
	NetworkManager.send_chat("hello from A")
	t.check(NetworkManager.get_ping_ms() >= 0, "ping measured (%d ms)" % NetworkManager.get_ping_ms())

	# Lesson: both walk into the Sigilcraft classroom; A teaches B.
	t.section("Lesson (professor)")
	_enter_classroom(spawner, Vector3(-2, 0, 0))
	ok = await _wait_until(func() -> bool: return spawner.local_player.area_tracker.current_area_id() == CLASSROOM, 5.0)
	t.check(ok, "professor is in the classroom")
	var panel: Node = world.get_node("ProfessorPanel")
	t.check(panel.can_open(), "lesson tools are available to a professor")
	ok = await _wait_until(func() -> bool: return panel.students_present().size() == 1, 30.0)
	t.check(ok, "the student shows up in the classroom")
	ok = await _wait_until(func() -> bool: return is_instance_valid(remote) and remote.house == 3, 10.0)
	t.check(ok and NetworkManager.get_players().get(remote.peer_id, {}).get("house", 0) == 3, "the roster update carries the student's new house")
	t.check(casts_seen == 0, "a cast of an unlearned spell was dropped by the server")
	var b_sid: String = remote.peer_id
	NetworkManager.send_grant_spell("nobody", "arcane_pulse")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 1, 10.0)
	t.check(ok and grant_results[0]["ok"] == false and grant_results[0]["reason"] == "no_such_player", "grant to an unknown session is refused (%s)" % str(grant_results))
	NetworkManager.send_grant_spell(b_sid, "bogus")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 2, 10.0)
	t.check(ok and grant_results[1]["ok"] == false and grant_results[1]["reason"] == "unknown_spell", "grant of an unknown spell is refused")
	await _wait(1.0)  # give B's area report time to land
	NetworkManager.send_grant_spell(b_sid, "arcane_pulse")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 3, 10.0)
	t.check(ok and grant_results[2]["ok"] == true and grant_results[2]["sid"] == b_sid, "teaching a student in the same classroom succeeds (%s)" % str(grant_results))
	NetworkManager.send_grant_spell(b_sid, "arcane_pulse")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 4, 10.0)
	t.check(ok and grant_results[3]["ok"] == false and grant_results[3]["reason"] == "already_known", "teaching the same spell twice is refused")
	panel.open()
	panel.get_node("%Spells").select(SpellRegistry.SPELL_IDS.find("uplift"))
	panel.refresh()
	panel.get_node("%GrantSelfButton").pressed.emit()
	panel.close()
	ok = await _wait_until(func() -> bool: return _known_spells().has("uplift"), 10.0)
	t.check(ok and spawner.local_player.spell_caster.knows(&"uplift"), "a professor can teach themselves through the panel")
	ok = await _wait_until(func() -> bool: return casts_seen > 0, 20.0)
	t.check(ok, "remote spell cast event received once the student knows the spell")

	ok = await _wait_until(func() -> bool: return _remote(spawner) == null, 30.0)
	t.check(ok, "remote player removed when B disconnects")
	t.check(leaves.has("ClientB"), "leave event received for ClientB")
	ok = await _wait_until(func() -> bool: return _remote(spawner) != null, 30.0)
	t.check(ok, "remote player re-appears when B reconnects")
	await _wait(1.0)


# --- Actor (client B) ------------------------------------------------------------------

func _run_actor(spawner: PlayerSpawner) -> void:
	t.section("Actor")
	var player: Player = spawner.local_player
	var ok := await _wait_until(func() -> bool: return _remote(spawner) != null, 20.0)
	t.check(ok, "sees ClientA already in the world")
	if ok:
		t.check(_remote(spawner).display_name == "ClientA", "remote player named ClientA")
	t.check(player.inventory.hold_id(&"torch"), "holds the torch (sent to the server)")
	t.check(_remote(spawner) != null and _remote(spawner).role == "professor" and _remote(spawner).nameplate.text.begins_with(tr("ROLE_PROFESSOR_TITLE")), "ClientA arrives as a professor in the roster")
	var denied: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "role": "admin"})
	t.check(denied.has("error"), "a student cannot promote themselves (%s)" % str(denied))
	player.movement.set_external_move(Vector3(0, 0, -1), true)
	await _wait(1.5)
	player.movement.request_jump()
	await _wait(0.4)
	player.movement.request_jump()
	await _wait(1.5)
	player.movement.set_external_move(Vector3.ZERO)
	# A locally learned spell is not known to the server: the cast is relayed to nobody.
	player.spell_caster.learn_spell(ARCANE_PULSE)
	t.check(player.spell_caster.try_cast(), "local cast fires (server will drop it)")
	t.check(NetworkManager.send_chat("hello from B"), "chat send accepted")
	ok = await _wait_until(func() -> bool: return chat_lines.any(func(l: String) -> bool: return l == "[ClientA] hello from A"), 20.0)
	t.check(ok, "chat message from A received: %s" % str(chat_lines))
	t.check(chat_lines.any(func(l: String) -> bool: return l == "[ClientB] hello from B"), "own chat message echoed with own name")
	await _wait(1.0)

	t.section("Sorting (student)")
	var answers_for_3: Array = []
	for q in HouseSorting.QUESTIONS:
		for i in q["answers"].size():
			if q["answers"][i]["house"] == 3:
				answers_for_3.append(i + 1)
				break
	NetworkManager.send_sort([1, 2])
	ok = await _wait_until(func() -> bool: return sort_results.size() >= 1, 10.0)
	t.check(ok and sort_results[0]["ok"] == false and sort_results[0]["reason"] == "bad_answers", "malformed answers are refused (%s)" % str(sort_results))
	NetworkManager.send_sort(answers_for_3)
	ok = await _wait_until(func() -> bool: return sort_results.size() >= 2, 10.0)
	t.check(ok and sort_results[1]["ok"] == true and sort_results[1]["house"] == 3, "the server sorts the student into house 3 (%s)" % str(sort_results))
	ok = await _wait_until(func() -> bool: return NetworkManager.get_local_house() == 3 and player.house == 3, 10.0)
	t.check(ok and player.nameplate.text.ends_with(tr("HOUSE_3_NAME")), "the profile and nameplate carry the new house")
	NetworkManager.send_sort(answers_for_3)
	ok = await _wait_until(func() -> bool: return sort_results.size() >= 3, 10.0)
	t.check(ok and sort_results[2]["ok"] == false and sort_results[2]["reason"] == "already_sorted", "a second ceremony is refused")

	t.section("Lesson (student)")
	_enter_classroom(spawner, Vector3(2, 0, 0))
	ok = await _wait_until(func() -> bool: return player.area_tracker.current_area_id() == CLASSROOM, 5.0)
	t.check(ok, "student is in the classroom")
	ok = await _wait_until(func() -> bool: return _known_spells().has("arcane_pulse"), 40.0)
	t.check(ok, "the professor's grant arrived in the server profile")
	t.check(player.spell_caster.knows(&"arcane_pulse") and player.spell_caster.equipped_spell == ARCANE_PULSE, "the spellbook applied the granted spell")
	var taught: String = tr("NOTIFY_SPELL_TAUGHT") % ["ClientA", tr(ARCANE_PULSE.display_name)]
	t.check(notifications.has(taught), "taught notification names the professor (%s)" % str(notifications))
	t.check(player.spell_caster.try_cast(), "student casts the granted spell")
	await _wait(0.6)
	player.spell_caster.try_cast()
	NetworkManager.send_study_tome("glowmote")
	ok = await _wait_until(func() -> bool: return _known_spells().has("glowmote"), 10.0)
	t.check(ok and player.spell_caster.knows(&"glowmote"), "a practice tome request is granted by the server")
	var glow := SpellRegistry.load_definition("glowmote")
	player.spell_caster.assign_slot(5, glow)
	player.spell_caster.equip(ARCANE_PULSE)
	await _wait(1.0)
	await NetworkManager.disconnect_online("test disconnect")
	t.check(not NetworkManager.is_online(), "disconnect sets offline")
	ok = await _wait_until(func() -> bool: return _remote(spawner) == null, 5.0)
	t.check(ok, "remote players cleared after disconnect")
	await _wait(2.0)
	var err: String = await NetworkManager.connect_online(GameSession.display_name)
	t.check(err.is_empty(), "reconnect succeeds (%s)" % err)
	ok = await _wait_until(func() -> bool: return _remote(spawner) != null, 20.0)
	t.check(ok, "sees ClientA again after reconnect")
	ok = await _wait_until(func() -> bool: return _known_spells().has("glowmote"), 10.0)
	var profile := NetworkManager.get_local_profile()
	t.check(ok and _known_spells().has("arcane_pulse"), "learned spells persist across reconnect (%s)" % str(_known_spells()))
	t.check(profile.get("spells", {}).get("slots", [])[5] == "glowmote" and player.spell_caster.quick_slots[5] == glow and player.spell_caster.equipped_spell == ARCANE_PULSE, "hotbar layout persists across reconnect")
	t.check(int(profile.get("house", 0)) == 3 and player.house == 3, "house persists across reconnect")
	await _wait(2.0)

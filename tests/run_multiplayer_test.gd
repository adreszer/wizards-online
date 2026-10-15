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
## [object id, state] for every OP_OBJECT_STATE received
var object_events: Array = []
var server_texts: Array[String] = []
var lesson_results: Array = []
var points_results: Array = []
var lectures: Array[String] = []
var cheat_results: Array = []
## Who moved the school clock, per OP_CLOCK ("" = the join snapshot)
var clock_changes: Array[String] = []

const HTTP_KEY := "defaulthttpkey"
const CLASSROOM := &"class_sigilcraft"
## A toggleable switch in the classroom: flips on every valid spell event, so
## the test works whatever state earlier runs left it in.
const SWITCH := "class_sigilcraft/practice_switch"
## Two-player mystery: both clients in the gallery, then a force spell on the wall.
const LOFT_WALL := "loft/secret_wall"
## Player-scoped mystery: these plaques read in order.
const TALE := [["great_hall", "great_hall/plaque_great_hall"], ["library", "library/plaque_library"], ["stair_hall", "stair_hall/plaque_stair_hall"]]


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
	NetworkManager.object_state_changed.connect(func(oid: String, s: Variant) -> void: object_events.append([oid, s]))
	NetworkManager.server_text_received.connect(func(text: String, _s: float) -> void: server_texts.append(text))
	NetworkManager.lesson_result_received.connect(func(ok: bool, action: String, reason: String) -> void: lesson_results.append({"ok": ok, "action": action, "reason": reason}))
	NetworkManager.house_points_result_received.connect(func(ok: bool, house: int, delta: int, reason: String) -> void: points_results.append({"ok": ok, "house": house, "delta": delta, "reason": reason}))
	NetworkManager.lecture_received.connect(func(by: String, text: String) -> void: lectures.append("%s: %s" % [by, text]))
	NetworkManager.school_clock_changed.connect(func(by: String) -> void: clock_changes.append(by))
	NetworkManager.cheat_result_received.connect(func(ok: bool, id: String, reason: String) -> void: cheat_results.append({"ok": ok, "id": id, "reason": reason}))
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
	var reset: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "role": "student", "house": 0, "forget_spells": true, "forget_mysteries": true}, HTTP_KEY)
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
	await _enter_zone(spawner, CLASSROOM, offset)


func _zone(area_id: StringName) -> AreaZone:
	for zone in world.get_node("Level").get_zones():
		if zone.area_id == area_id:
			return zone
	return null


## Teleports the local player into an area and waits until the tracker (and so
## the server, via OP_AREA) knows it. Returns whether it got there.
func _enter_zone(spawner: PlayerSpawner, area_id: StringName, offset: Vector3 = Vector3.ZERO) -> bool:
	var zone := _zone(area_id)
	var floor_y := zone.global_position.y - zone.size.y / 2.0
	spawner.local_player.global_position = Vector3(zone.global_position.x, floor_y + 0.2, zone.global_position.z) + offset
	return await _wait_until(func() -> bool: return spawner.local_player.area_tracker.current_area_id() == area_id, 5.0)


func _inside(node: Node3D, area_id: StringName) -> bool:
	var zone := _zone(area_id)
	var local := node.global_position - zone.global_position
	# Feet rest on the zone's bottom face, so allow a little slack vertically.
	return absf(local.x) < zone.size.x / 2.0 and absf(local.y) <= zone.size.y / 2.0 + 0.5 and absf(local.z) < zone.size.z / 2.0


func _world_object(oid: String) -> Node:
	for node in get_tree().get_nodes_in_group(&"world_objects"):
		if str(node.get(&"object_id")) == oid:
			return node
	return null


func _known_spells() -> Array:
	return NetworkManager.get_local_profile().get("spells", {}).get("known", [])


# --- Observer (client A) ------------------------------------------------------------

func _run_observer(spawner: PlayerSpawner) -> void:
	t.section("Observer")
	var reset_world: Dictionary = await NetworkManager.admin_reset_world(HTTP_KEY)
	t.check(reset_world.get("ok", false) == true, "world objects and shared mysteries reset for the test (%s)" % str(reset_world))
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

	# Lesson: both walk into the Charms classroom; A teaches B.
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
	t.check(ok and grant_results[2]["reason"] == "no_lesson", "teaching without an open lesson is refused (%s)" % str(grant_results.back()))
	panel.refresh()
	t.check(panel.current_subject() == "sigilcraft" and panel.spell_index("galewind") == -1 and panel.spell_index("uplift") >= 0, "the panel lists only the classroom subject's spells")
	NetworkManager.send_lesson("open")
	ok = await _wait_until(func() -> bool: return lesson_results.size() >= 1 and NetworkManager.get_lessons().has(str(CLASSROOM)), 10.0)
	t.check(ok and lesson_results[0]["ok"] == true and NetworkManager.get_lessons()[str(CLASSROOM)]["subject"] == "sigilcraft", "the professor opens a Charms lesson (%s)" % str(lesson_results))
	NetworkManager.send_lesson("open")
	ok = await _wait_until(func() -> bool: return lesson_results.size() >= 2, 10.0)
	t.check(ok and lesson_results[1]["reason"] == "already_open", "a second lesson in the same room is refused")
	NetworkManager.send_grant_spell(b_sid, "galewind")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 4, 10.0)
	t.check(ok and grant_results[3]["reason"] == "not_in_subject", "a spell of another subject cannot be taught here (%s)" % str(grant_results.back()))
	NetworkManager.send_grant_spell(b_sid, "arcane_pulse")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 5, 10.0)
	t.check(ok and grant_results[4]["ok"] == true and grant_results[4]["sid"] == b_sid, "teaching a student in the same classroom succeeds (%s)" % str(grant_results))
	NetworkManager.send_grant_spell(b_sid, "arcane_pulse")
	ok = await _wait_until(func() -> bool: return grant_results.size() >= 6, 10.0)
	t.check(ok and grant_results[5]["ok"] == false and grant_results[5]["reason"] == "already_known", "teaching the same spell twice is refused")
	NetworkManager.send_lecture("Today we draw the first sigil.")
	# House points: an award with a reason lands in the ledger and the tally.
	var totals_before := NetworkManager.get_house_totals()
	t.check(totals_before.size() == 4, "the house points tally arrived on join (%s)" % str(totals_before))
	NetworkManager.send_house_points(3, 99, "too many")
	NetworkManager.send_house_points(3, 5, "  ")
	NetworkManager.send_house_points(3, 5, "a clean first sigil")
	ok = await _wait_until(func() -> bool: return points_results.size() >= 3, 10.0)
	t.check(ok and points_results[0]["reason"] == "bad_amount" and points_results[1]["reason"] == "no_reason" and points_results[2]["ok"] == true, "awards are checked: amount cap, a reason, then accepted (%s)" % str(points_results))
	ok = await _wait_until(func() -> bool: return NetworkManager.get_house_totals().size() == 4 and NetworkManager.get_house_totals()[2] == totals_before[2] + 5, 10.0)
	t.check(ok, "the tally shows the award (%s → %s)" % [str(totals_before), str(NetworkManager.get_house_totals())])
	NetworkManager.send_house_points(3, -1, "talking in class")
	ok = await _wait_until(func() -> bool: return points_results.size() >= 4, 10.0)
	t.check(ok and points_results[3]["reason"] == "too_soon", "a second change right away waits for the cooldown")
	var ledger: Dictionary = await NetworkManager.house_points_ledger(500, HTTP_KEY)
	var records: Array = ledger.get("records", [])
	var sums := [0, 0, 0, 0]
	for r: Dictionary in records:
		sums[int(r["house"]) - 1] += int(r["delta"])
	var totals_now: Array = ledger.get("totals", []).map(func(v: Variant) -> int: return int(v))
	t.check(not records.is_empty() and records[0]["reason"] == "a clean first sigil" and records[0]["by_name"] == "ClientA" and records[0]["subject"] == "sigilcraft", "the newest ledger record explains the award (%s)" % str(records.slice(0, 1)))
	t.check(records.size() < 500 and sums == totals_now, "every house total equals the sum of its ledger records (%s vs %s)" % [str(sums), str(totals_now)])
	var saved: Dictionary = await NetworkManager.save_lesson_plan("", "Sigils, week one", PackedStringArray(["Welcome.", "Draw the first sigil."]))
	var plans: Array = await NetworkManager.list_lesson_plans()
	t.check(saved.has("id") and plans.any(func(pl: Dictionary) -> bool: return pl.get("id") == saved["id"] and pl.get("lines", []).size() == 2), "a lesson plan is stored for the professor (%s)" % str(saved))
	panel.open()
	panel.get_node("%Spells").select(panel.spell_index("uplift"))
	panel.refresh()
	panel.get_node("%GrantSelfButton").pressed.emit()
	panel.close()
	ok = await _wait_until(func() -> bool: return _known_spells().has("uplift"), 10.0)
	t.check(ok and spawner.local_player.spell_caster.knows(&"uplift"), "a professor can teach themselves through the panel")
	ok = await _wait_until(func() -> bool: return casts_seen > 0, 20.0)
	t.check(ok, "remote spell cast event received once the student knows the spell")
	NetworkManager.send_lesson("close")
	ok = await _wait_until(func() -> bool: return not NetworkManager.get_lessons().has(str(CLASSROOM)), 10.0)
	t.check(ok, "the professor ends the lesson")
	ok = await _wait_until(func() -> bool: return object_events.any(func(e: Array) -> bool: return e[0] == SWITCH), 30.0)
	var switch_node: Node = _world_object(SWITCH)
	t.check(ok and switch_node is MagicSwitch and switch_node.is_on == (NetworkManager.get_world_object_states().get(SWITCH, false) == true), "the student's switch change reaches the professor's castle")

	t.section("Mystery (professor)")
	t.check(await _enter_zone(spawner, &"gallery", Vector3(-2, 0, 0)), "the professor waits in the gallery")
	var loft: Node = _world_object(LOFT_WALL)
	ok = await _wait_until(func() -> bool: return loft is SecretWall and loft.is_revealed, 90.0)
	t.check(ok, "the two-player mystery opens the loft for the professor too")
	ok = await _wait_until(func() -> bool: return NetworkManager.get_local_profile().get("discoveries", []).has("loft"), 10.0)
	t.check(ok, "both players of a cooperative mystery get the discovery")

	# Meanwhile B fetches a broom and flies: the snapshots carry it here.
	var saw_broom := [false]
	ok = await _wait_until(func() -> bool:
		var r := _remote(spawner)
		if r != null and (r as Player).broom_rider.mount != null:
			saw_broom[0] = true
		return r == null, 60.0)
	t.check(saw_broom[0], "B's broom shows on the remote player while B flies")
	t.check(clock_changes.has("") and clock_changes.has("ClientB"), "the school clock comes with the join, and B's /time reaches A (%s)" % str(clock_changes))
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
	for q in HouseSorting.questions():
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
	var my_house_points := NetworkManager.get_house_totals()[2] if NetworkManager.get_house_totals().size() == 4 else 0
	_enter_classroom(spawner, Vector3(2, 0, 0))
	ok = await _wait_until(func() -> bool: return player.area_tracker.current_area_id() == CLASSROOM, 5.0)
	t.check(ok, "student is in the classroom")
	ok = await _wait_until(func() -> bool: return _known_spells().has("arcane_pulse"), 40.0)
	t.check(ok, "the professor's grant arrived in the server profile")
	t.check(player.spell_caster.knows(&"arcane_pulse") and player.spell_caster.equipped_spell == ARCANE_PULSE, "the spellbook applied the granted spell")
	var taught: String = tr("NOTIFY_SPELL_TAUGHT") % ["ClientA", tr(ARCANE_PULSE.display_name)]
	t.check(notifications.has(taught), "taught notification names the professor (%s)" % str(notifications))
	t.check(NetworkManager.get_lessons().get(str(CLASSROOM), {}).get("by", "") == "ClientA", "the student sees the professor's open lesson")
	ok = await _wait_until(func() -> bool: return lectures.has("ClientA: Today we draw the first sigil."), 15.0)
	t.check(ok, "the professor's lecture reaches the student in the room (%s)" % str(lectures))
	t.check(player.spell_caster.try_cast(), "student casts the granted spell")
	await _wait(0.6)
	player.spell_caster.try_cast()
	NetworkManager.send_study_tome("glowmote")
	ok = await _wait_until(func() -> bool: return _known_spells().has("glowmote"), 10.0)
	t.check(ok and player.spell_caster.knows(&"glowmote"), "a practice tome request is granted by the server")
	t.section("World objects (student)")
	var switch_node: Node = _world_object(SWITCH)
	t.check(switch_node is MagicSwitch, "the classroom switch is a synced world object")
	var before: bool = NetworkManager.get_world_object_states().get(SWITCH, false) == true
	t.check(switch_node.is_on == before, "the join snapshot set the switch (%s)" % str(before))
	var hidden_before: Variant = NetworkManager.get_world_object_states().get("undercroft/secret_wall")
	NetworkManager.send_world_event("undercroft/secret_wall", "spell", "arcane_pulse")
	NetworkManager.send_world_event("nowhere/nothing", "interact")
	NetworkManager.send_world_event(SWITCH, "spell", "frostbind")
	# The real trigger path: a spell hit on the switch becomes a request, not a local change.
	switch_node._on_spell_received(SpellEffect.create(ARCANE_PULSE, player, "", switch_node.global_position, Vector3.FORWARD))
	t.check(switch_node.is_on == before, "online, a hit does not change the switch locally")
	ok = await _wait_until(func() -> bool: return object_events.any(func(e: Array) -> bool: return e[0] == SWITCH), 10.0)
	t.check(ok and switch_node.is_on == (not before), "the server flips the switch for everyone (now %s)" % str(switch_node.is_on))
	await _wait(1.0)
	t.check(object_events.size() == 1, "events from the wrong area, for unknown objects or with an unknown spell are dropped (%s)" % str(object_events))
	t.check(NetworkManager.get_world_object_states().get("undercroft/secret_wall") == hidden_before, "the out-of-reach secret wall did not change")

	t.section("Mysteries (student)")
	# Player scope: three plaques in order; the server answers each with a clue.
	for i in TALE.size():
		var area: StringName = StringName(TALE[i][0])
		t.check(await _enter_zone(spawner, area), "reached %s" % area)
		await _wait(0.5)
		var plaque: Node = _world_object(TALE[i][1])
		var texts_before := server_texts.size()
		plaque._on_interacted(player)
		ok = await _wait_until(func() -> bool: return server_texts.size() > texts_before, 10.0)
		t.check(ok, "reading %s earns a server text (%s)" % [TALE[i][1], str(server_texts.slice(texts_before))])
	ok = await _wait_until(func() -> bool: return NetworkManager.get_local_profile().get("discoveries", []).has("founders_tale"), 10.0)
	t.check(ok, "solving a mystery records a discovery on the profile")
	t.check(server_texts.size() >= 3 and not server_texts.any(func(x: String) -> bool: return x.begins_with("MYST_")), "clues arrive as resolved text, not keys (%s)" % str(server_texts))
	# World scope, two players: the loft opens only with someone else in the gallery.
	var loft: Node = _world_object(LOFT_WALL)
	t.check(loft is SecretWall and not loft.is_revealed, "the loft is closed after the reset")
	loft._on_spell_received(SpellEffect.create(ARCANE_PULSE, player, "", loft.global_position, Vector3.FORWARD))
	await _wait(1.0)
	t.check(not loft.is_revealed, "a mystery-driven wall ignores a direct spell")
	t.check(await _enter_zone(spawner, &"gallery", Vector3(2, 0, 0)), "the student reaches the gallery")
	ok = await _wait_until(func() -> bool: return _remote(spawner) != null and _inside(_remote(spawner), &"gallery"), 60.0)
	t.check(ok, "the professor is in the gallery too")
	await _wait(1.0)
	loft._on_spell_received(SpellEffect.create(ARCANE_PULSE, player, "", loft.global_position, Vector3.FORWARD))
	ok = await _wait_until(func() -> bool: return loft.is_revealed, 10.0)
	t.check(ok, "with two players present the spell solves the mystery and opens the loft")
	ok = await _wait_until(func() -> bool: return NetworkManager.get_local_profile().get("discoveries", []).has("loft"), 10.0)
	t.check(ok, "the solver gets the loft discovery")
	await _enter_classroom(spawner, Vector3(2, 0, 0))
	ok = await _wait_until(func() -> bool: return NetworkManager.get_house_totals().size() == 4 and NetworkManager.get_house_totals()[2] >= my_house_points + 5, 20.0)
	t.check(ok, "the student's house tally shows the professor's award (%d → %s)" % [my_house_points, str(NetworkManager.get_house_totals())])
	var hud := world.get_node_or_null("HUD")
	t.check(hud == null or hud.house_tally_text().contains(str(NetworkManager.get_house_totals()[2])), "the HUD tally shows the totals")

	t.section("Brooms (student)")
	var reset_inv: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "reset_inventory": true}, HTTP_KEY)
	ok = await _wait_until(func() -> bool: return not player.inventory.has(&"broom") and player.inventory.has(&"torch"), 10.0)
	t.check(reset_inv.get("ok", false) == true and ok, "admin reset the inventory to the starting kit")
	t.check(not player.broom_rider.toggle(), "no broom, no flight")
	t.check(await _enter_zone(spawner, &"grounds"), "the student reaches the grounds")
	var rack: Node = _world_object("grounds/broom_rack")
	t.check(rack is BroomRack, "the grounds broom rack is a synced world object")
	rack._on_interacted(player)
	ok = await _wait_until(func() -> bool: return player.inventory.has(&"broom"), 10.0)
	t.check(ok and NetworkManager.get_local_inventory().get("items", []).any(func(e: Dictionary) -> bool: return e.get("id", "") == "broom"), "the rack's broom comes from the server inventory")
	NetworkManager.send_cheat_give("broom")
	NetworkManager.send_cheat_give("dragon")
	ok = await _wait_until(func() -> bool: return cheat_results.size() >= 2, 10.0)
	t.check(ok and cheat_results[0]["reason"] == "already_owned" and cheat_results[1]["reason"] == "unknown_item", "cheats: an owned broom and an unknown item are refused (%s)" % str(cheat_results))
	t.check(player.inventory.count_of(&"broom") == 1, "still exactly one broom")
	t.check(clock_changes.has(""), "the join brings the school clock")
	var hours_before := NetworkManager.school_hours()
	NetworkManager.set_school_hours(15.5)
	ok = await _wait_until(func() -> bool: return clock_changes.has("ClientB"), 10.0)
	t.check(ok and absf(NetworkManager.school_hours() - 15.5) < 0.05, "/time moves the server's clock (%.2f h)" % NetworkManager.school_hours())
	NetworkManager.set_school_hours(hours_before)   # leave the dev server's clock where it was
	await _wait_until(func() -> bool: return clock_changes.count("ClientB") >= 2, 10.0)
	t.check(player.broom_rider.toggle() and player.movement.is_flying, "the student mounts the broom")
	player.movement.set_external_vertical(1.0)
	await _wait(1.5)
	player.movement.set_external_vertical(0.0)
	await _wait(2.0)
	player.broom_rider.dismount()
	await _wait(1.0)
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
	t.check(NetworkManager.get_world_object_states().get(SWITCH, false) == (not before) and switch_node.is_on == (not before), "the rejoin snapshot carries the switch state")
	t.check(NetworkManager.get_world_object_states().get(LOFT_WALL) == "revealed" and _world_object(LOFT_WALL).is_revealed, "the solved mystery's wall is still open after rejoining")
	await _wait(2.0)

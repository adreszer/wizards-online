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


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	NetworkManager.chat_message_received.connect(func(n: String, text: String, _s: bool) -> void: chat_lines.append("[%s] %s" % [n, text]))
	NetworkManager.system_message.connect(func(text: String) -> void: system_lines.append(text))
	NetworkManager.spell_cast_received.connect(func(_sid: String, _c: Dictionary) -> void: casts_seen += 1)
	NetworkManager.player_joined.connect(func(_sid: String, n: String) -> void: joins.append(n))
	NetworkManager.player_left.connect(func(_sid: String, n: String) -> void: leaves.append(n))
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


# --- Observer (client A) ------------------------------------------------------------

func _run_observer(spawner: PlayerSpawner) -> void:
	t.section("Observer")
	var ok := await _wait_until(func() -> bool: return _remote(spawner) != null, 40.0)
	if not t.check(ok, "remote player spawns when B joins"):
		return
	var remote := _remote(spawner)
	t.check(not remote.is_local and remote.display_name == "ClientB", "remote player is not local and has B's name (%s)" % remote.display_name)
	t.check(remote.get_node_or_null("LocalPlayer") == null, "remote player has no LocalPlayer subtree (no camera/input)")
	t.check(joins.has("ClientB"), "join event received for ClientB")
	t.check(system_lines.any(func(l: String) -> bool: return l.begins_with("ClientB joined")), "join system message shown")
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
		if moved and (states_seen.has("jump") or states_seen.has("fall")) and casts_seen > 0 and chat_lines.size() > 0:
			break
	t.check(moved, "remote player moves across the network")
	# Smoothness: no single-frame jump larger than a plausible interpolated step.
	var max_step := 0.0
	for i in range(1, samples.size()):
		max_step = maxf(max_step, samples[i].distance_to(samples[i - 1]))
	t.check(max_step < 1.0, "remote movement is interpolated, largest per-frame step %.2f m" % max_step)
	t.check(states_seen.has("walk") or states_seen.has("run"), "remote animation state shows walking/running (%s)" % str(states_seen.keys()))
	t.check(states_seen.has("jump") or states_seen.has("fall") or max_y > start_pos.y + 0.5, "remote jump replicates (max y %.2f)" % max_y)
	t.check(casts_seen > 0, "remote spell cast event received")
	t.check(chat_lines.any(func(l: String) -> bool: return l == "[ClientB] hello from B"), "chat message from B received: %s" % str(chat_lines))
	NetworkManager.send_chat("hello from A")
	t.check(NetworkManager.get_ping_ms() >= 0, "ping measured (%d ms)" % NetworkManager.get_ping_ms())

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
	player.movement.set_external_move(Vector3(0, 0, -1), true)
	await _wait(1.5)
	player.movement.request_jump()
	await _wait(0.4)
	player.movement.request_jump()
	await _wait(1.5)
	player.movement.set_external_move(Vector3.ZERO)
	player.spell_caster.learn_spell(ARCANE_PULSE)
	t.check(player.spell_caster.try_cast(), "local cast succeeds")
	await _wait(0.6)
	player.spell_caster.try_cast()
	t.check(NetworkManager.send_chat("hello from B"), "chat send accepted")
	ok = await _wait_until(func() -> bool: return chat_lines.any(func(l: String) -> bool: return l == "[ClientA] hello from A"), 20.0)
	t.check(ok, "chat message from A received: %s" % str(chat_lines))
	t.check(chat_lines.any(func(l: String) -> bool: return l == "[ClientB] hello from B"), "own chat message echoed with own name")
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
	await _wait(2.0)

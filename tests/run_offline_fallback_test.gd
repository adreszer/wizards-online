extends Node
## Run with the backend STOPPED (docker compose stop). Verifies that ONLINE
## fails with a readable error and the game still boots offline.

const TestHelpers := preload("res://tests/test_helpers.gd")
const WORLD_SCENE := preload("res://core/world.tscn")
var t := TestHelpers.new()


func _ready() -> void:
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	var err: String = await NetworkManager.connect_online("Nobody")
	t.check(not err.is_empty(), "connect_online reports an error when the backend is down: %s" % err)
	t.check(NetworkManager.status == NetworkManager.Status.ERROR, "status is ERROR")
	t.check(not NetworkManager.is_online(), "not online")
	GameSession.play_mode = GameSession.PlayMode.OFFLINE
	var world := WORLD_SCENE.instantiate()
	add_child(world)
	await get_tree().create_timer(1.0).timeout
	var spawner: PlayerSpawner = world.get_node("PlayerSpawner")
	t.check(spawner.local_player != null, "offline world spawns the local player")
	NetworkManager.send_player_state({})
	NetworkManager.send_spell_cast({})
	t.check(not NetworkManager.send_chat("x"), "send_* are safe no-ops offline")
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)

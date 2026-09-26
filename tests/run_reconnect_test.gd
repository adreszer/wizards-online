extends Node
## Connects online, then waits up to 60 s for the connection to drop and come
## back (restart Nakama meanwhile: `docker compose restart nakama`).
## Passes when a "Reconnected." system message arrives.

const TestHelpers := preload("res://tests/test_helpers.gd")
var t := TestHelpers.new()
var messages: Array[String] = []


func _ready() -> void:
	NetworkManager.system_message.connect(func(m: String) -> void: messages.append(m); print("SYS: " + m))
	NetworkManager.status_changed.connect(func(s: int, m: String) -> void: print("STATUS: %s %s" % [NetworkManager.Status.keys()[s], m]))
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	var err: String = await NetworkManager.connect_online("Reconnector")
	t.check(err.is_empty(), "initial connect (%s)" % err)
	print("CONNECTED - restart nakama now")
	var elapsed := 0.0
	while elapsed < 75.0 and not messages.has("Reconnected."):
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	t.check(messages.any(func(m: String) -> bool: return m.begins_with("Connection lost")), "connection loss detected")
	t.check(messages.has("Reconnected."), "reconnected automatically")
	t.check(NetworkManager.is_online(), "online after reconnect")
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)

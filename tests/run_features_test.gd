extends Node
## Two-client test of the server's feature modules (nakama/modules/features/) against a
## running Nakama. Client A is made an admin (staff), client B a student of house 3; they keep in
## step through direct messages ("step N"), so each section can wait for the other.
## A:  godot --headless --path . tests/run_features_test.tscn -- --instance=1 --name=ClientA
## B:  godot --headless --path . tests/run_features_test.tscn -- --instance=2 --name=ClientB --role=b
## Start A first, then B within ~20 s. Each prints a summary and exits non-zero on failure.

const WORLD_SCENE := preload("res://core/world.tscn")
const TestHelpers := preload("res://tests/test_helpers.gd")
const HTTP_KEY := "defaulthttpkey"

var t := TestHelpers.new()
var role: String = "a"
var world: Node
var spawner: PlayerSpawner
var other_name := ""
var steps_seen: Dictionary = {}
var notices: Array[String] = []
var pushes: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	other_name = "ClientA" if role == "b" else "ClientB"
	NetworkManager.chat_line_received.connect(func(line: Dictionary) -> void:
		var text := str(line.get("text", ""))
		if line.get("kind", "") == "dm" and not line.get("self", false) and text.begins_with("step "):
			steps_seen[int(text.trim_prefix("step "))] = true)
	GameEvents.notification_requested.connect(func(text: String, _d: float) -> void: notices.append(text))
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void: pushes.append([kind, data]))
	await _run()


func _run() -> void:
	t.section("Connect (%s)" % role)
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	var err: String = await NetworkManager.connect_online(GameSession.display_name)
	if not t.check(err.is_empty(), "connect_online succeeds (%s)" % err):
		_finish()
		return
	world = WORLD_SCENE.instantiate()
	add_child(world)
	await _wait(0.5)
	spawner = world.get_node("PlayerSpawner")
	var reset: Dictionary = await NetworkManager.admin_set_profile({"user_id": NetworkManager.local_user_id, "role": "admin" if role == "a" else "student",
		"house": 1 if role == "a" else 3, "reset_purse": true}, HTTP_KEY)
	t.check(reset.get("ok", false) == true, "test account set up (%s)" % str(reset))
	var ok := await _wait_until(func() -> bool: return NetworkManager.get_local_role() == ("admin" if role == "a" else "student"), 10.0)
	t.check(ok, "role applied")
	ok = await _wait_until(func() -> bool: return not spawner.remote_players.is_empty(), 60.0)
	t.check(ok, "the other client is in the castle")
	if role == "b":
		await _run_b()
	else:
		await _run_a()
	_finish()


# --- Client A (professor) ------------------------------------------------------------

func _run_a() -> void:
	t.section("Detention (professor)")
	var r: Dictionary = await NetworkManager.request("detention_assign", {"name": "Nobody 42"})
	t.check(not r.ok and r.reason == "no_such_player", "an unknown name is refused (%s)" % str(r))
	r = await NetworkManager.request("detention_assign", {"name": other_name, "task": "polish_trophies"})
	t.check(r.ok or r.reason == "already_in_detention", "a professor gives a student a detention (%s)" % str(r))
	await _step(1)
	await _await_step(2)

	t.section("Heads of house and riddles (admin)")
	r = await NetworkManager.request("house_head_set", {"name": NetworkManager.local_display_name, "house": 3})
	t.check(r.ok, "an admin names a head of house (%s)" % str(r))
	r = await NetworkManager.request("house_board_post", {"text": "Welcome back, Phoenara!", "house": 3})
	t.check(r.ok, "the head posts to the house board (%s)" % str(r))
	r = await NetworkManager.request("house_stats", {"house": 3})
	t.check(r.ok and int(r.data.get("house", 0)) == 3 and r.data.has("by_source"), "and sees the house's numbers (%s)" % str(r).left(200))
	t.check(RequestText.describe("house_stats", r).contains(CharacterProfile.house_name(3)), "the numbers read as a line in chat")
	r = await NetworkManager.request("riddle_reset", {"name": other_name})
	t.check(r.ok, "an admin can make a student answer the riddle again (%s)" % str(r))
	await _step(3)
	await _await_step(4)


# --- Client B (student) --------------------------------------------------------------

func _run_b() -> void:
	t.section("Detention (student)")
	var r: Dictionary = await NetworkManager.request("detention_assign", {"name": other_name})
	t.check(not r.ok and r.reason == "not_allowed", "a student cannot give detentions (%s)" % str(r))
	await _await_step(1)
	var ok := await _wait_until(func() -> bool: return str(NetworkManager.feature("detention").get("task", "")) == "polish_trophies", 10.0)
	t.check(ok, "the detention arrives (%s)" % str(NetworkManager.feature("detention")))
	r = await NetworkManager.request("detention_step", {"spot": 1})
	t.check(not r.ok and r.reason == "wrong_room", "chores count only in the task's room (%s)" % str(r))
	t.check(await _enter_zone(&"trophy_room"), "the student walks into the trophy room")
	await _wait(0.6)
	var dt := world.get_node("Level").get_node_or_null("DetentionTasks") as DetentionTasks
	t.check(dt != null and dt.spots.size() == 5, "the chores show in the room (%d)" % (dt.spots.size() if dt else -1))
	var done_count := _arr(NetworkManager.feature("detention").get("done")).size()
	var last: Dictionary = {}
	for i in range(1, 6):
		if _arr(NetworkManager.feature("detention").get("done")).has(float(i)):
			continue
		last = await NetworkManager.request("detention_step", {"spot": i})
		if i == 1 and done_count == 0:
			var again: Dictionary = await NetworkManager.request("detention_step", {"spot": 2})
			t.check(not again.ok and again.reason == "too_fast", "chores take their time (%s)" % str(again))
		await _wait(2.1)
	t.check(last.get("ok", false) and last.data.get("done", false) == true, "the last chore ends the detention (%s)" % str(last))
	ok = await _wait_until(func() -> bool: return NetworkManager.feature("detention").is_empty() and notices.any(func(n: String) -> bool: return n == tr("DETENTION_SECRET_TROPHIES")), 10.0)
	t.check(ok, "served, and the trophy room lets a secret slip")
	await _step(2)

	t.section("Heads of house and riddles (student)")
	await _await_step(3)
	ok = await _wait_until(func() -> bool:
		var posts: Array = _arr(NetworkManager.feature("house_board").get("posts"))
		return not posts.is_empty() and posts[0].get("text", "") == "Welcome back, Phoenara!", 10.0)
	t.check(ok, "the house board post reaches the house (%s)" % str(NetworkManager.feature("house_board")).left(160))
	r = await NetworkManager.request("house_stats", {})
	t.check(not r.ok and r.reason == "not_a_head", "only heads see the house numbers (%s)" % str(r))
	r = await NetworkManager.request("house_board_post", {"text": "hello"})
	t.check(not r.ok and r.reason == "not_allowed", "students do not post to the house board (%s)" % str(r))
	ok = await _wait_until(func() -> bool: return NetworkManager.feature("riddle").get("solved", true) == false and NetworkManager.feature("riddle").get("question") is Dictionary, 10.0)
	t.check(ok, "this week's riddle waits on the common-room door (%s)" % str(NetworkManager.feature("riddle")).left(160))
	var door: HouseDoor = null
	for node in world.get_node("Level").find_children("*", "HouseDoor", true, false):
		if (node as HouseDoor).house == 3:
			door = node
	var panel := world.get_node_or_null("RiddlePanel") as RiddlePanel
	t.check(door != null and panel != null, "a house door and the riddle panel exist")
	if door != null and panel != null:
		door._on_interacted(spawner.local_player)
		await _wait(0.2)
		t.check(panel.is_open and not door.is_open, "the door asks the riddle before it opens")
		panel.close()
		r = await NetworkManager.request("riddle_answer", {"answer": "a teapot"})
		t.check(not r.ok and r.reason == "wrong_answer", "a wrong answer keeps it shut (%s)" % str(r))
		await _wait(3.1)
		r = await NetworkManager.request("riddle_answer", {"answer": _riddle_answer()})
		t.check(r.ok, "the right answer is accepted (%s)" % str(r))
		ok = await _wait_until(func() -> bool: return NetworkManager.feature("riddle").get("solved", false) == true, 10.0)
		door._on_interacted(spawner.local_player)
		await _wait(0.2)
		t.check(ok and door.is_open and not panel.is_open, "then the door opens for the rest of the week")
	await _step(4)


# --- Helpers --------------------------------------------------------------------------

## The first accepted answer of the riddle now on our door (from nakama/content/riddles.json).
func _riddle_answer() -> String:
	var q: Dictionary = NetworkManager.feature("riddle").get("question", {})
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/riddles.json"))
	for r: Dictionary in data.riddles:
		if r.q.get("pl", "") == q.get("pl", ""):
			return str(r.a[0])
	return ""


## A list from a payload (an empty Lua table arrives as {}).
static func _arr(v: Variant) -> Array:
	return v if v is Array else []


## Tells the other client this one reached step `n`.
func _step(n: int) -> void:
	NetworkManager.send_dm(other_name, "step %d" % n)
	await _wait(1.1)   # the DM cooldown


## Waits until the other client reached step `n`.
func _await_step(n: int, timeout: float = 120.0) -> bool:
	var ok := await _wait_until(func() -> bool: return steps_seen.has(n), timeout)
	t.check(ok, "the other client reached step %d" % n)
	return ok


func _zone(area_id: StringName) -> AreaZone:
	for zone in world.get_node("Level").get_zones():
		if zone.area_id == area_id:
			return zone
	return null


func _enter_zone(area_id: StringName, offset: Vector3 = Vector3.ZERO) -> bool:
	var zone := _zone(area_id)
	if zone == null:
		return false
	var floor_y := zone.global_position.y - zone.size.y / 2.0
	spawner.local_player.global_position = Vector3(zone.global_position.x, floor_y + 0.2, zone.global_position.z) + offset
	return await _wait_until(func() -> bool: return spawner.local_player.area_tracker.current_area_id() == area_id, 5.0)


func _finish() -> void:
	print(t.summary())
	await NetworkManager.disconnect_online("test done")
	get_tree().quit(1 if t.failed > 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if predicate.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return predicate.call()

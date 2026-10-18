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
var system_lines: Array[String] = []
var dm_texts: Array[String] = []


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
	NetworkManager.system_message.connect(func(text: String) -> void: system_lines.append(text))
	NetworkManager.chat_line_received.connect(func(line: Dictionary) -> void:
		if line.get("kind", "") == "dm" and not line.get("self", false):
			dm_texts.append(str(line.get("text", ""))))
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
		"house": 1 if role == "a" else 3, "reset_purse": true, "reset_inventory": role == "b"}, HTTP_KEY)
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

	t.section("Echoes, the wing, the chart (admin)")
	r = await NetworkManager.request("echo_reset", {"name": other_name})
	t.check(r.ok, "an admin can restart a student's Echo stories (%s)" % str(r))
	r = await NetworkManager.request("permission_slip", {"name": other_name})
	t.check(r.ok, "a professor grants a permission slip for the sealed stacks (%s)" % str(r))
	r = await NetworkManager.request("wing_state", {})
	var before := int(r.data.get("points", -1))
	t.check(r.ok and int(r.data.get("doors", 0)) >= 3, "the Unfinished Wing has sealed doors to open (%s)" % str(r))
	r = await NetworkManager.request("wing_contribute", {"points": 1})
	t.check(r.ok and int(r.data.get("points", 0)) >= before + 1, "admins add to the school's shared progress (%s)" % str(r))
	await _step(5)
	await _await_step(6)

	t.section("Friends, Star Stones, profiles (admin)")
	await _enter_zone(&"great_hall", Vector3(-2, 0, 0))
	await _await_step(7)
	var asked := await _wait_until(func() -> bool: return _arr(NetworkManager.feature("friends").get("incoming")).has(other_name), 10.0)
	t.check(asked, "a friend request arrives (%s)" % str(NetworkManager.feature("friends")))
	r = await NetworkManager.request("friend_accept", {"name": other_name})
	t.check(r.ok, "and is accepted (%s)" % str(r))
	var listed := await _wait_until(func() -> bool:
		return _arr(NetworkManager.feature("friends").get("friends")).any(func(f: Dictionary) -> bool: return f.get("name", "") == other_name and f.get("online", false)), 10.0)
	t.check(listed, "friends see each other online")
	var invited := await _wait_until(func() -> bool: return NetworkManager.feature("game").get("state", "") == "invited", 15.0)
	t.check(invited and (world.get_node("GamePanel") as GamePanel).is_open, "a Star Stones invitation opens the board")
	r = await NetworkManager.request("game_answer", {"accept": true})
	t.check(r.ok, "the invitation is accepted (%s)" % str(r))
	# B plays column 1 four times, A column 2: B wins on the fourth stone.
	for i in 3:
		var my_turn := await _wait_until(func() -> bool: return int(NetworkManager.feature("game").get("turn", 0)) == 2, 15.0)
		r = await NetworkManager.request("game_move", {"col": 2})
		t.check(my_turn and r.ok, "A drops a stone in column 2 (%s)" % str(r))
	var over := await _wait_until(func() -> bool: return NetworkManager.feature("game").get("state", "") == "over", 15.0)
	t.check(over and int(NetworkManager.feature("game").get("winner", 0)) == 1, "four in a column wins (%s)" % str(NetworkManager.feature("game")).left(160))
	await _step(8)

	t.section("Clubs and events (admin)")
	await _await_step(9)
	var club_name := "Stargazers %d" % (Time.get_unix_time_from_system() as int % 100000)
	r = await NetworkManager.request("club_create", {"name": club_name, "colour": 1, "symbol": 1})
	t.check(r.ok, "a club is founded (%s)" % str(r))
	var club_id := str(r.data.get("id", ""))
	r = await NetworkManager.request("club_create", {"name": club_name})
	t.check(not r.ok and r.reason == "name_taken", "club names are unique (%s)" % str(r))
	r = await NetworkManager.request("event_schedule", {"kind": "feast", "title": "Test feast", "at": 3, "minutes": 60, "area": "great_hall"})
	t.check(r.ok, "an admin schedules a feast (%s)" % str(r))
	var event_id := str(r.data.get("id", ""))
	NetworkManager.send_dm(other_name, "club " + club_id)
	await _wait(1.1)
	await _step(10)
	await _await_step(11)
	r = await NetworkManager.request("club_book", {"id": club_id, "area": "library", "at": int(NetworkManager.server_time()) + 3600 + 600, "minutes": 30})
	t.check(not r.ok and (r.reason == "room_taken" or r.reason == "not_member"), "a booked room cannot be booked twice (%s)" % str(r))
	r = await NetworkManager.request("event_cancel", {"id": event_id})
	t.check(r.ok, "and the event can be cancelled (%s)" % str(r))
	r = await NetworkManager.request("club_close", {"id": club_id})
	t.check(r.ok, "the founder closes the club (%s)" % str(r))
	await _step(12)

	t.section("Flying and Lantern Chase (admin)")
	r = await NetworkManager.request("flying_revoke", {"name": other_name})
	t.check(r.ok, "an admin can take a licence away (%s)" % str(r))
	await _enter_zone(&"class_skyriding", Vector3(-2, 0, 0))
	await _step(13)
	await _await_step(14)
	r = await NetworkManager.request("flying_licence", {"name": other_name})
	t.check(r.ok, "a professor passes the student's flying lesson (%s)" % str(r))
	await _step(15)
	await _await_step(16)
	t.check(await _enter_zone(&"pitch", Vector3(-30, 0, 0)), "onto the pitch")
	r = await NetworkManager.request("chase_join", {"team": "a"})
	t.check(r.ok, "A joins team a (%s)" % str(r))
	await _step(17)
	await _await_step(18)
	r = await NetworkManager.request("chase_leave", {})
	t.check(r.ok, "and leaves the match (%s)" % str(r))
	await _step(19)

	t.section("Classroom controls and admin tools (admin)")
	await _enter_zone(&"class_sigilcraft", Vector3(-2, 0, 0))
	NetworkManager.send_lesson("open")
	var open := await _wait_until(func() -> bool: return NetworkManager.get_lessons().has("class_sigilcraft"), 10.0)
	t.check(open, "a lesson opens in the classroom")
	r = await NetworkManager.request("classroom_mute", {"on": true})
	t.check(r.ok and r.data.get("muted", false) == true, "the professor quiets the room (%s)" % str(r))
	await _step(20)
	await _await_step(21)
	r = await NetworkManager.request("classroom_bell", {})
	t.check(r.ok and int(r.data.get("heard", 0)) >= 1, "the hand bell rings for the room (%s)" % str(r))
	r = await NetworkManager.request("classroom_lock", {"on": true})
	t.check(r.ok and int(r.data.get("doors", 0)) >= 1, "and the doors lock for an exam (%s)" % str(r))
	r = await NetworkManager.request("classroom_lock", {"on": false})
	t.check(r.ok, "and unlock (%s)" % str(r))
	await _step(22)
	await _await_step(23)
	NetworkManager.send_lesson("close")
	r = await NetworkManager.request("admin_who", {})
	var names := _arr(r.data.get("players")).map(func(p: Dictionary) -> String: return str(p.get("name", "")))
	t.check(r.ok and names.has(other_name) and names.has(NetworkManager.local_display_name), "who is online, and where (%s)" % str(names))
	r = await NetworkManager.request("admin_set", {"name": other_name, "year": 2})
	t.check(r.ok and int(r.data.get("year", 0)) == 2, "an admin sets a student's year from the panel (%s)" % str(r))
	r = await NetworkManager.request("admin_set", {"name": other_name, "year": 1})
	r = await NetworkManager.request("admin_broadcast", {"text": "The great hall closes early tonight."})
	t.check(r.ok, "a broadcast goes to the whole castle (%s)" % str(r))
	r = await NetworkManager.request("admin_timetable_set", {"id": "test_slot", "day": "sat", "start": "10:00", "minutes": 45, "kind": "lesson", "subject": "sigilcraft"})
	t.check(r.ok, "the timetable takes a slot added in the game (%s)" % str(r))
	r = await NetworkManager.request("admin_timetable", {})
	t.check(r.ok and _arr(r.data.get("slots")).any(func(s: Dictionary) -> bool: return s.get("id", "") == "test_slot"), "and lists it")
	r = await NetworkManager.request("admin_timetable_set", {"id": "bad_slot", "day": "someday", "start": "25:00", "minutes": 45})
	t.check(not r.ok and r.reason == "bad_slot", "a broken slot is refused (%s)" % str(r))
	r = await NetworkManager.request("admin_timetable_remove", {"id": "test_slot"})
	r = await NetworkManager.request("admin_timetable_reset", {})
	t.check(r.ok, "and the in-game changes can be undone (%s)" % str(r))
	r = await NetworkManager.request("admin_chat_log", {"name": other_name})
	t.check(r.ok and _arr(r.data.get("lines")).size() >= 1, "the chat log keeps the student's lines (%d)" % _arr(r.data.get("lines")).size())
	r = await NetworkManager.request("admin_analytics", {})
	t.check(r.ok and (r.data.get("areas", {}) as Dictionary).has("great_hall"), "anonymous daily counts of where people go (%s)" % str(r.data.get("areas", {})).left(120))
	var saved: Dictionary = await NetworkManager.save_lesson_plan("", "Test plan", PackedStringArray(["Sigils are drawn from the wrist.", "# Board line", "? A question"]))
	r = await NetworkManager.request("plan_share", {"id": str(saved.get("id", "")), "subject": "sigilcraft"})
	t.check(r.ok, "a professor shares a plan with the staff room (%s)" % str(r))
	r = await NetworkManager.request("plan_approve", {"id": str(saved.get("id", "")), "on": true})
	t.check(r.ok and r.data.get("approved", false) == true, "an admin approves it for self-study (%s)" % str(r))
	r = await NetworkManager.request("plan_approve", {"id": str(saved.get("id", "")), "on": false})
	r = await NetworkManager.request("plan_unshare", {"id": str(saved.get("id", ""))})
	t.check(r.ok, "and the plan can be withdrawn (%s)" % str(r))
	await _step(24)
	await _await_step(25)


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

	t.section("Dormitory, Echoes, the chart (student)")
	await _await_step(5)
	var level := world.get_node("Level")
	t.check(await _enter_zone(&"house3_dorm"), "the student walks into the house dormitory")
	ok = await _wait_until(func() -> bool: return _my_bed() != "", 10.0)
	t.check(ok, "and gets a bed (%s)" % str(NetworkManager.feature("dorm")).left(200))
	NetworkManager.send_cheat_give("pennant")
	ok = await _wait_until(func() -> bool: return spawner.local_player.inventory.has(&"pennant"), 10.0)
	t.check(ok, "a pennant to hang (dev give)")
	r = await NetworkManager.request("dorm_decorate", {"decor": ["torch"]})
	t.check(not r.ok and r.reason == "not_decor", "a torch is not a decoration (%s)" % str(r))
	r = await NetworkManager.request("dorm_decorate", {"decor": ["star_chart"]})
	t.check(not r.ok and r.reason == "not_owned", "only what you own (%s)" % str(r))
	r = await NetworkManager.request("dorm_decorate", {"decor": ["pennant"]})
	t.check(r.ok, "the pennant goes up over the bed (%s)" % str(r))
	var corners := level.get_node_or_null("DormitoryCorners") as DormitoryCorners
	ok = await _wait_until(func() -> bool:
		return corners != null and corners.find_child("Corner_" + NetworkManager.local_display_name, true, false) != null \
			and corners.find_child("Corner_" + NetworkManager.local_display_name, true, false).find_child("pennant", true, false) != null, 10.0)
	t.check(ok, "the corner shows the name plate and the pennant")

	var coins_before := NetworkManager.get_coins()
	t.check(await _enter_zone(&"library"), "the student walks into the library")
	var echoes := level.get_node_or_null("EchoResidents") as EchoResidents
	ok = await _wait_until(func() -> bool: return echoes != null and echoes.figures.has("ilsa") and int(_arr_d(NetworkManager.feature("echoes").get("ilsa")).get("step", -1)) == 0, 10.0)
	t.check(ok, "an Echo stands in the library, its story not begun (%s)" % str(NetworkManager.feature("echoes").get("ilsa")))
	r = await NetworkManager.request("echo_talk", {"echo": "ilsa"})
	t.check(r.ok and r.data.get("line", "") == "ECHO_ILSA_1", "the Echo tells the first part of her story (%s)" % str(r))
	r = await NetworkManager.request("echo_talk", {"echo": "ilsa"})
	t.check(r.ok and r.data.get("waiting", false) == true, "and waits until her request is done (%s)" % str(r))
	t.check(await _enter_zone(&"restricted_stacks"), "into the restricted stacks")
	ok = await _wait_until(func() -> bool: return _arr_d(NetworkManager.feature("echoes").get("ilsa")).get("met", false) == true, 10.0)
	t.check(ok, "the goal counts when it happens")
	r = await NetworkManager.request("echo_talk", {"echo": "ilsa"})
	t.check(not r.ok and r.reason == "wrong_room", "Echoes speak only in their own place (%s)" % str(r))
	await _enter_zone(&"library")
	r = await NetworkManager.request("echo_talk", {"echo": "ilsa"})
	t.check(r.ok and r.data.get("line", "") == "ECHO_ILSA_2", "back in the library: the next part (%s)" % str(r))
	await _enter_zone(&"bindery")
	await _wait(0.6)
	await _enter_zone(&"library")
	r = await NetworkManager.request("echo_talk", {"echo": "ilsa"})
	t.check(r.ok and r.data.get("done", false) == true and r.data.get("line", "") == "ECHO_ILSA_3", "the story ends (%s)" % str(r))
	ok = await _wait_until(func() -> bool: return NetworkManager.get_local_profile().get("discoveries", []).has("echo_ilsa") and NetworkManager.get_coins() >= coins_before, 10.0)
	t.check(ok, "with a discovery on the profile and the reward (%d → %d coins)" % [coins_before, NetworkManager.get_coins()])

	ok = await _wait_until(func() -> bool: return _arr(NetworkManager.feature("explored").get("areas")).size() > 0 or (world.get_node("Level") != null), 5.0)
	var map := CastleMap.new()
	add_child(map)
	map.build(level)
	var stacks: Dictionary = {}
	for room in map.rooms:
		if room["id"] == "bindery":
			stacks = room
	t.check(not stacks.is_empty() and map.explored.has("bindery"), "the server remembers where the student has been")
	var known_without := map.is_known(stacks)
	NetworkManager.send_cheat_give("wayfinder_chart")
	ok = await _wait_until(func() -> bool: return CastleMap.has_chart(), 10.0)
	t.check(ok and not known_without and map.is_known(stacks), "the plain plan leaves the bindery out; the Wayfinder's Chart draws it once explored")
	r = await NetworkManager.request("chart_share", {"share": true})
	t.check(r.ok and r.data.get("share", false) == true, "sharing one's room with house-mates is a choice (%s)" % str(r))
	map.queue_free()
	await _step(6)

	t.section("Friends, Star Stones, profiles (student)")
	await _enter_zone(&"great_hall", Vector3(2, 0, 0))
	await _wait_until(func() -> bool: return _remote_named(other_name) != null and _inside(_remote_named(other_name), &"great_hall"), 15.0)
	await NetworkManager.request("friend_remove", {"name": other_name})
	r = await NetworkManager.request("friend_add", {"name": "Nobody 42"})
	t.check(not r.ok and r.reason == "no_such_player", "unknown names cannot be friended (%s)" % str(r))
	r = await NetworkManager.request("friend_add", {"name": other_name})
	t.check(r.ok, "a friend request is sent (%s)" % str(r))
	r = await NetworkManager.request("profile_card", {"name": other_name})
	t.check(r.ok and r.data.get("name", "") == other_name and r.data.has("clubs") and r.data.has("games"), "a player's card (%s)" % str(r).left(200))
	t.check(ProfileCard.card_bbcode(r.data).contains(tr("PROFILE_DISCOVERIES") % int(r.data.get("discoveries", 0))), "reads as a card")
	var remote := _remote_named(other_name)
	t.check(remote != null and remote.get_node_or_null("ProfileTarget") != null, "looking at a player offers their card")
	await _step(7)
	var friended := await _wait_until(func() -> bool:
		return _arr(NetworkManager.feature("friends").get("friends")).any(func(f: Dictionary) -> bool: return f.get("name", "") == other_name), 15.0)
	t.check(friended, "the request was accepted")
	r = await NetworkManager.request("game_invite", {"name": other_name})
	t.check(r.ok, "a Star Stones invitation (%s)" % str(r))
	for i in 4:
		var my_turn := await _wait_until(func() -> bool: return NetworkManager.feature("game").get("state", "") == "playing" and int(NetworkManager.feature("game").get("turn", 0)) == 1, 15.0)
		if i == 0:
			var early: Dictionary = await NetworkManager.request("game_move", {"col": 9})
			t.check(not early.ok and early.reason == "bad_move", "moves outside the frame are refused (%s)" % str(early))
		r = await NetworkManager.request("game_move", {"col": 1})
		t.check(my_turn and r.ok, "B drops a stone in column 1 (%s)" % str(r))
	var won := await _wait_until(func() -> bool: return NetworkManager.feature("game").get("state", "") == "over" and int(NetworkManager.feature("game").get("winner", 0)) == 1, 10.0)
	t.check(won, "and wins with four in a column")
	r = await NetworkManager.request("profile_card", {"name": NetworkManager.local_display_name})
	t.check(r.ok and int(r.data.get("games", {}).get("wins", 0)) >= 1, "the win is on the card (%s)" % str(r.data.get("games", {})))
	await _step(8)

	t.section("Clubs and events (student)")
	await _step(9)
	await _await_step(10)
	var club_id := ""
	var got_id := await _wait_until(func() -> bool: return dm_texts.any(func(x: String) -> bool: return x.begins_with("club ")), 10.0)
	for x in dm_texts:
		if x.begins_with("club "):
			club_id = x.trim_prefix("club ")
	t.check(got_id and club_id != "", "the club's id arrives")
	r = await NetworkManager.request("club_join", {"id": club_id})
	t.check(r.ok, "the student joins the club (%s)" % str(r))
	r = await NetworkManager.request("club_post", {"id": club_id, "text": "Meet on the tower at midnight"})
	t.check(r.ok and _arr(r.data.get("posts")).size() >= 1, "members post on the club board (%s)" % str(r).left(120))
	r = await NetworkManager.request("club_book", {"id": club_id, "area": "class_sigilcraft", "at": int(NetworkManager.server_time()) + 7200, "minutes": 300})
	t.check(not r.ok and r.reason == "bad_length", "meetings last at most two hours (%s)" % str(r))
	r = await NetworkManager.request("club_book", {"id": club_id, "area": "house3_common", "at": int(NetworkManager.server_time()) + 7200, "minutes": 60})
	t.check(not r.ok and r.reason == "not_bookable", "house rooms cannot be booked (%s)" % str(r))
	r = await NetworkManager.request("club_book", {"id": club_id, "area": "library", "at": int(NetworkManager.server_time()) + 3600, "minutes": 60})
	t.check(r.ok, "a member books the library for a meeting (%s)" % str(r))
	var calendar := await _wait_until(func() -> bool:
		return _arr(NetworkManager.feature("events").get("events")).any(func(e: Dictionary) -> bool: return e.get("title", "") == "Test feast"), 15.0)
	t.check(calendar, "the scheduled feast is in everyone's calendar")
	var text := EventReminders.calendar_bbcode(NetworkManager.timetable, NetworkManager.feature("events"), NetworkManager.feature("clubs"), NetworkManager.server_time())
	t.check(text.contains("Test feast"), "and on the journal's calendar page")
	t.check(EventReminders.due(NetworkManager.feature("events"), NetworkManager.feature("clubs"), NetworkManager.local_display_name, NetworkManager.server_time()).any(
		func(d: Dictionary) -> bool: return d.title == "Test feast"), "with a reminder five minutes before")
	await _step(11)
	await _await_step(12)

	t.section("Flying and Lantern Chase (student)")
	await _await_step(13)
	notices.clear()
	t.check(await _enter_zone(&"class_skyriding", Vector3(2, 0, 0)), "into the flying classroom")
	NetworkManager.send_world_event("class_skyriding/broom_rack", "interact")
	var refused := await _wait_until(func() -> bool: return notices.has(tr("REFUSED_NO_LICENCE")), 10.0)
	t.check(refused, "without a licence the broom rack stays shut (%s)" % str(notices))
	r = await NetworkManager.request("shop_buy", {"item": "broom"})
	t.check(not r.ok and (r.reason == "wrong_shop" or r.reason == "no_licence"), "and the workshop will not sell one (%s)" % str(r))
	await _step(14)
	await _await_step(15)
	var licensed := await _wait_until(func() -> bool: return NetworkManager.feature("licence").get("broom", false) == true and spawner.local_player.inventory.has(&"broom"), 10.0)
	t.check(licensed, "the licence and a broom arrive")
	# Flying indoors: the server tells the rider to land.
	NetworkManager.send_op(NetworkProtocol.OP_STATE, {"p": NetworkProtocol.vec3_to_array(spawner.local_player.global_position), "y": 0.0, "v": [0, 0, 0], "s": "fly", "g": false, "m": "broom"})
	var land := await _wait_until(func() -> bool: return NetworkManager.feature("flight").get("land", false) == true, 10.0)
	t.check(land, "flying indoors is refused by the server")
	await _step(16)
	var pitch := _zone(&"pitch")
	var layout := LanternChase.layout_for(pitch.global_position, pitch.size)
	t.check(await _enter_zone(&"pitch", Vector3(30, 0, 0)), "onto the pitch")
	await _await_step(17)
	r = await NetworkManager.request("chase_start", {})
	t.check(not r.ok and r.reason == "not_playing", "only players start a match (%s)" % str(r))
	r = await NetworkManager.request("chase_join", {"team": "b"})
	t.check(r.ok, "B joins team b (%s)" % str(r))
	r = await NetworkManager.request("chase_start", {})
	t.check(r.ok, "the match starts (%s)" % str(r))
	var home: Vector3 = layout.homes["b"]
	spawner.local_player.global_position = Vector3(home.x + 1.0, _ground_y(home, pitch) + 0.2, home.z)
	await _wait(0.6)
	r = await NetworkManager.request("chase_take", {})
	t.check(r.ok, "B takes the team's lantern at its home (%s)" % str(r))
	r = await NetworkManager.request("chase_ring", {})
	t.check(not r.ok and r.reason == "too_far", "scoring needs the far ring (%s)" % str(r))
	var ring: Vector3 = layout.rings["b"]
	# Ride up to the ring (the pitch is open sky); the server reads where the rider's own state says.
	spawner.local_player.global_position = Vector3(ring.x, _ground_y(ring, pitch) + 0.2, ring.z)
	await _wait(0.4)
	spawner.local_player.broom_rider.mount_item(ItemRegistry.load_definition("broom"))
	await _wait(0.6)
	r = await NetworkManager.request("chase_ring", {})
	t.check(r.ok and int((r.data.get("scores", {}) as Dictionary).get("b", 0)) == 1, "through the ring: a point (%s)" % str(r))
	var hud := await _wait_until(func() -> bool: return int((NetworkManager.feature("lantern_chase").get("scores", {}) as Dictionary).get("b", 0)) == 1, 10.0)
	t.check(hud, "the match state reaches the players")
	await _step(18)
	await _await_step(19)

	t.section("Guardians, garden, potions, creatures, shops (student)")
	r = await NetworkManager.request("guardian_hit", {"id": "cellars_guardian_east", "spell": "arcane_pulse"})
	t.check(not r.ok and r.reason == "out_of_reach", "guardians are fought where they stand (%s)" % str(r))
	t.check(NetworkManager.feature("guardians").has("cellars_guardian_east"), "the guardians' shared state arrives")
	var granted: Dictionary = await NetworkManager.admin_grant_coins({"name": NetworkManager.local_display_name, "amount": 60, "reason": "test shopping"}, HTTP_KEY)
	t.check(granted.get("ok", false) == true, "pocket money for the village (%s)" % str(granted))
	t.check(await _enter_zone(&"apothecary"), "into the apothecary")
	r = await NetworkManager.request("shop_buy", {"item": "pennant"})
	t.check(not r.ok and r.reason == "wrong_shop", "each shop sells its own goods (%s)" % str(r))
	var purse := NetworkManager.get_coins()
	r = await NetworkManager.request("shop_buy", {"item": "seed_glowcap"})
	t.check(r.ok, "seeds bought at the apothecary (%s)" % str(r))
	await _wait_until(func() -> bool: return NetworkManager.get_coins() == purse - 3, 5.0)
	t.check(NetworkManager.get_coins() == purse - 3, "for their price (%d → %d)" % [purse, NetworkManager.get_coins()])
	r = await NetworkManager.request("shop_buy", {"item": "crystal_dust"})
	t.check(r.ok, "and crystal dust")
	NetworkManager.send_cheat_give("glowcap")
	await _wait_until(func() -> bool: return spawner.local_player.inventory.has(&"glowcap"), 5.0)
	NetworkManager.send_cheat_give("glowcap")
	await _wait(0.5)
	r = await NetworkManager.request("shop_sell", {"item": "glowcap"})
	t.check(r.ok, "the apothecary buys herbs (%s)" % str(r))
	t.check(await _enter_zone(&"greenhouse"), "into the greenhouse")
	var garden := world.get_node("Level").get_node_or_null("GardenBeds") as GardenBeds
	t.check(garden != null and garden.beds.size() == GardenBeds.PLOTS, "the greenhouse has its beds")
	var plot := 0
	for n in range(1, GardenBeds.PLOTS + 1):
		if garden != null and garden.plot(n).is_empty() and plot == 0:
			plot = n
	r = await NetworkManager.request("garden_plant", {"plot": plot, "seed": "seed_glowcap"})
	t.check(r.ok, "a seed planted in a free bed (%s)" % str(r))
	r = await NetworkManager.request("garden_harvest", {"plot": plot})
	t.check(not r.ok and r.reason == "not_ripe", "not ripe yet (%s)" % str(r))
	r = await NetworkManager.request("garden_spell", {"plot": plot, "spell": "quicksprout"})
	t.check(not r.ok and (r.reason == "wrong_spell" or r.reason == "needs_water"), "Quicksprout needs the spell and a watered plant (%s)" % str(r))
	r = await NetworkManager.request("garden_water", {"plot": plot})
	t.check(r.ok, "watered: it starts to grow (%s)" % str(r))
	var growing := await _wait_until(func() -> bool: return garden.plot(plot).get("watered", false) == true, 10.0)
	t.check(growing, "everyone sees the bed growing")
	t.check(await _enter_zone(&"class_elixirs"), "into the Potions classroom")
	var steps := [["brew_add", {"item": "glowcap"}], ["brew_add", {"item": "crystal_dust"}], ["brew_stir", {}], ["brew_stir", {}], ["brew_stir", {}], ["brew_heat", {"level": "high"}]]
	var brewed := true
	for s: Array in steps:
		r = await NetworkManager.request(s[0], s[1])
		brewed = brewed and r.ok
		await _wait(0.45)
	t.check(brewed, "ingredients in, stirred three times, high heat")
	r = await NetworkManager.request("brew_bottle", {})
	t.check(not r.ok and r.reason == "not_ready", "bottled too soon it is not ready (%s)" % str(r))
	await _wait(10.5)
	r = await NetworkManager.request("brew_bottle", {})
	t.check(r.ok and r.data.get("potion", "") == "potion_glow" and int(r.data.get("quality", 0)) == 6, "a Glowing Draught of the best quality (%s)" % str(r))
	await _wait_until(func() -> bool: return spawner.local_player.inventory.has(&"potion_glow"), 5.0)
	r = await NetworkManager.request("potion_drink", {"item": "potion_glow"})
	t.check(r.ok and r.data.get("effect", "") == "glow", "drunk: the student glows (%s)" % str(r))
	var glowing := await _wait_until(func() -> bool: return (NetworkManager.feature("effects").get(NetworkManager.local_display_name, {}) as Dictionary).get("effect", "") == "glow", 10.0)
	t.check(glowing, "for everyone to see")
	NetworkManager.send_cheat_give("creature_treat")
	await _wait_until(func() -> bool: return spawner.local_player.inventory.has(&"creature_treat"), 5.0)
	t.check(await _enter_zone(&"paddock"), "into the paddock")
	r = await NetworkManager.request("creature_feed", {"kind": "mossling"})
	t.check((r.ok and int(r.data.get("bond", 0)) >= 2) or r.reason == "too_soon", "a mossling fed: the bond grows (%s)" % str(r))
	r = await NetworkManager.request("creature_pet", {"kind": "mossling"})
	t.check(not r.ok and r.reason == "too_soon", "care takes its time (%s)" % str(r))
	r = await NetworkManager.request("creature_adopt", {"kind": "glimmerwing"})
	t.check(not r.ok and r.reason == "bond_too_weak", "a familiar needs trust first (%s)" % str(r))
	await _step(19)

	t.section("Classroom controls and admin tools (student)")
	t.check(await _enter_zone(&"class_sigilcraft", Vector3(2, 0, 0)), "into the classroom")
	await _await_step(20)
	var refusals := system_lines.size()
	NetworkManager.send_chat("psst")
	var quiet := await _wait_until(func() -> bool: return system_lines.size() > refusals and system_lines.back() == tr("REFUSED_ROOM_QUIET"), 10.0)
	t.check(quiet, "a quieted room refuses a student's line (%s)" % str(system_lines.slice(refusals)))
	NetworkManager.send_chat("only a whisper", NetworkProtocol.CHAT_WHISPER)
	await _wait(0.8)
	t.check(system_lines.back() != tr("REFUSED_ROOM_QUIET") or system_lines.size() == refusals + 1, "whispers still pass")
	notices.clear()
	await _step(21)
	var bell := await _wait_until(func() -> bool: return notices.any(func(n: String) -> bool: return n == tr("CLASSROOM_BELL") % other_name), 10.0)
	t.check(bell, "the bell asks the room for attention")
	await _await_step(22)
	await _step(23)
	var broadcast := await _wait_until(func() -> bool: return notices.any(func(n: String) -> bool: return n.contains("The great hall closes early tonight.")), 15.0)
	t.check(broadcast, "the admin's broadcast reaches the student")
	await _await_step(24)
	await _step(25)


# --- Helpers --------------------------------------------------------------------------

## The first accepted answer of the riddle now on our door (from nakama/content/riddles.json).
func _riddle_answer() -> String:
	var q: Dictionary = NetworkManager.feature("riddle").get("question", {})
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/riddles.json"))
	for r: Dictionary in data.riddles:
		if r.q.get("pl", "") == q.get("pl", ""):
			return str(r.a[0])
	return ""


func _ground_y(at: Vector3, zone: AreaZone) -> float:
	var top := zone.global_position.y + zone.size.y / 2.0 + 50.0
	var hit: Dictionary = spawner.local_player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, top - 400.0, at.z), 1))
	return (hit.position as Vector3).y if not hit.is_empty() else at.y


func _remote_named(n: String) -> Node3D:
	for p in spawner.remote_players.values():
		if str(p.get("display_name")) == n:
			return p as Node3D
	return null


func _inside(node: Node3D, area_id: StringName) -> bool:
	var zone := _zone(area_id)
	var local := node.global_position - zone.global_position
	return absf(local.x) < zone.size.x / 2.0 and absf(local.y) <= zone.size.y / 2.0 + 0.5 and absf(local.z) < zone.size.z / 2.0


## The local student's bed number in the dormitory feed ("" without one).
func _my_bed() -> String:
	var houses: Variant = NetworkManager.feature("dorm").get("houses", {})
	var beds: Variant = (houses as Dictionary).get(str(NetworkManager.get_local_house()), {}) if houses is Dictionary else {}
	for n: String in (beds if beds is Dictionary else {}):
		if str((beds[n] as Dictionary).get("name", "")) == NetworkManager.local_display_name:
			return n
	return ""


static func _arr_d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


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
	var at := Vector3(zone.global_position.x, floor_y + 0.2, zone.global_position.z) + offset
	# Outdoors the ground is terrain, often above the zone box's floor: stand on it.
	if zone.kind == "grounds" or zone.kind == "outdoor":
		at.y = _ground_y(at, zone) + 0.2
	spawner.local_player.global_position = at
	var ok := await _wait_until(func() -> bool: return spawner.local_player.area_tracker.current_area_id() == area_id, 5.0)
	# The server takes the area once the player's next state report puts them there.
	await _wait(0.4)
	return ok


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

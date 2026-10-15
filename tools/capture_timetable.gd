extends Node
## Dev tool: runs the real World (offline) with a sample week in the timetable and
## saves PNGs in front of every notice board, plus the timetable panel and HUD line
## (needs a window; not --headless).
##   godot --path . tools/capture_timetable.tscn -- --out=/absolute/dir

const WORLD := preload("res://core/world.tscn")

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	NetworkManager.timetable.apply(sample_week(NetworkManager.server_time()))
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(60)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	var game_camera := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	add_child(camera)
	var boards := world.find_children("*", "NoticeBoard", true, false)
	for i in boards.size():
		var board := boards[i] as Node3D
		var front := board.global_transform * Vector3(0, -1.9, 3.2)
		player.global_position = front
		await _frames(20)
		camera.global_position = board.global_transform * Vector3(0, 0.1, 3.0)
		camera.look_at(board.global_position + Vector3(0, 0.1, 0))
		camera.make_current()
		await _frames(5)
		_save("board_%d_%s" % [i, board.name])
		game_camera.make_current()
	GameEvents.timetable_requested.emit()
	await _frames(10)
	_save("panel")
	get_tree().quit()


## A week from now: the running lesson, one in 4 minutes, then one per day.
static func sample_week(now: float) -> Dictionary:
	var subjects := ["sigilcraft", "elixirs", "warding", "herblore", "chronicles", "skyriding", "stargazing"]
	var slots := [{"id": "now", "k": "lesson", "s": "shapeshaping", "a": "class_shapeshaping", "p": "Vexley", "t0": now - 600.0, "t1": now + 2100.0},
		{"id": "soon", "k": "lesson", "s": "glyphs", "a": "class_glyphs", "p": "", "t0": now + 240.0, "t1": now + 2940.0}]
	for d in subjects.size():
		slots.append({"id": "d%d" % d, "k": "lesson", "s": subjects[d], "a": SubjectRegistry.load_definition(subjects[d]).classrooms[0],
			"p": "", "t0": now + (d + 1) * 86400.0, "t1": now + (d + 1) * 86400.0 + 2700.0})
	slots.append({"id": "study", "k": "study", "s": "", "a": "library", "p": "", "t0": now + 2 * 86400.0 + 7200.0, "t1": now + 2 * 86400.0 + 12600.0})
	return {"tz": 120, "slots": slots}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

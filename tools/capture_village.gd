extends Node
## Dev tool: runs the real World (offline) and saves PNGs of the village and the station
## from fixed cameras, by day and by night (needs a window; not --headless).
##   godot --path . tools/capture_village.tscn -- --out=/absolute/dir [--hours=12,0]

const WORLD := preload("res://core/world.tscn")

var _out: String = "user://captures"
var _hours: Array[float] = [12.0, 0.0]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--hours="):
			_hours.clear()
			for h in arg.trim_prefix("--hours=").split(","):
				_hours.append(float(h))
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(60)
	var cycle := get_tree().root.find_child("DayNightCycle", true, false) as DayNightCycle
	var village := get_tree().root.find_child("Village", true, false) as Village
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	var y: float = village.data["floor"]
	var shop := village.building("sweet_shop")
	var inside := Village.door_point(shop, -2.0)
	var inn := village.building("inn")
	var views := [
		["street_east", Vector3(-120, y + 2.2, 752), Vector3(-40, y + 3.0, 748)],
		["street_west", Vector3(60, y + 2.2, 748), Vector3(-20, y + 3.5, 752)],
		["square", Vector3(18, y + 3.0, 768), Vector3(-6, y + 3.0, 716)],
		["gate_road", Vector3(4, -6.0, 676), Vector3(0, -4.0, 740)],
		["shop_inside", inside + Vector3(0, 1.8, 0), inside + (inside - Village.door_point(shop, 1.0)).normalized() * 6.0 + Vector3(0, 1.2, 0)],
		["inn_inside", Village.door_point(inn, -1.5) + Vector3(0, 1.8, 0), Village.door_point(inn, -9.0) + Vector3(-3, 1.0, 0)],
		["platform", Vector3(-246, y + 2.0, 852), Vector3(-238, y + 2.5, 800)],
		["portal", Vector3(-241, y + 2.0, 866), Vector3(-236, y + 1.0, 892)],
		["aerial", Vector3(-60, 60, 860), Vector3(-60, 0, 745)],
	]
	for view: Array in views:
		player.global_position = (view[1] as Vector3) + Vector3(0, 30, 0)
		cam.global_position = view[1]
		cam.look_at(view[2])
		cam.make_current()
		await _frames(20)
		for h: float in _hours:
			cycle.time_override = h
			cycle.refresh()
			await _frames(12)
			_save("%s_%02d" % [view[0], int(h)])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

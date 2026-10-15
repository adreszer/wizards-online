extends Node
## Dev tool: performance of the castle scene (needs a window; not --headless).
##   godot --path . tools/perf_castle.tscn -- [--copies=5] [--out=/abs/report.json]
## Loads the castle (with --copies=N, N castles 220 m apart: the stress fixture for the
## target scale; only the first keeps its grounds), then for each viewpoint waits for the
## streaming to settle and averages frame time, draw calls, objects and primitives over
## 120 frames. Prints a report and writes it as JSON with --out.

const CASTLE := "res://levels/castle/castle.tscn"
const VIEWS := [
	["entrance_hall", Vector3(0, 1.7, 44), Vector3(0, 3, 20)],
	["great_hall", Vector3(28, 1.7, 44), Vector3(28, 4, 10)],
	["corridor_w_0", Vector3(-16, 1.7, 20), Vector3(-16, 2, -30)],
	["stair_hall_top", Vector3(-30, 19.7, 44), Vector3(-20, 9, 30)],
	["forecourt", Vector3(0, 1.7, 90), Vector3(0, 8, 20)],
	["approach_far", Vector3(0, 20, 320), Vector3(0, 10, 0)],
	["aerial", Vector3(-300, 200, 400), Vector3(0, 0, 0)],
]

var copies := 1
var out_path := ""


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # measure frames, not the display
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--copies="):
			copies = int(arg.trim_prefix("--copies="))
		elif arg == "--no-batch":
			StaticBatch.disabled = true
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	await _run()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(CASTLE)
	var load_ms := Time.get_ticks_msec() - t0
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	cam.global_position = VIEWS[0][1]
	t0 = Time.get_ticks_msec()
	for i in range(copies):
		var c: Node3D = packed.instantiate()
		c.position = Vector3(_offset(i).x, 0, _offset(i).y)
		if i > 0:
			var g := c.get_node_or_null("Grounds")
			if g != null:
				c.remove_child(g)
				g.free()
		add_child(c)
	await get_tree().process_frame
	var instance_ms := Time.get_ticks_msec() - t0
	var report := {"copies": copies, "load_ms": load_ms, "instance_ms": instance_ms,
		"nodes": get_tree().get_node_count(), "mesh_instances": find_children("*", "MeshInstance3D", true, false).size(),
		"multimesh_instances": find_children("*", "MultiMeshInstance3D", true, false).size(),
		"static_bodies": find_children("*", "StaticBody3D", true, false).size(),
		"lights": find_children("*", "OmniLight3D", true, false).size(), "views": {}}
	for v: Array in VIEWS:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in range(90):
			await get_tree().process_frame
		var total := 0.0
		var worst := 0.0
		var draws := 0
		var objects := 0
		var prims := 0
		var n := 120
		for i in range(n):
			var t := Time.get_ticks_usec()
			await get_tree().process_frame
			var dt := (Time.get_ticks_usec() - t) / 1000.0
			total += dt
			worst = maxf(worst, dt)
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		report["views"][v[0]] = {"frame_ms": snappedf(total / n, 0.01), "worst_ms": snappedf(worst, 0.01),
			"draw_calls": draws / n, "objects": objects / n, "primitives": prims / n}
	print(JSON.stringify(report, "  "))
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
	get_tree().quit(0)


func _offset(i: int) -> Vector2:
	if i == 0:
		return Vector2.ZERO
	var ring := [Vector2(220, 0), Vector2(-220, 0), Vector2(0, -220), Vector2(220, -220), Vector2(-220, -220),
		Vector2(440, 0), Vector2(-440, 0), Vector2(0, -440)]
	return ring[(i - 1) % ring.size()]

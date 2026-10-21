extends Node
## Dev tool: runs the real World (offline) at noon and saves PNGs of the grounds' flora:
## for each kind the nearest instance to the spawn, close up and from further back, and
## a wide view over the grounds (needs a window; not --headless).
##   godot --path . tools/capture_flora.tscn -- --out=/absolute/dir [--season=summer]

const WORLD := preload("res://core/world.tscn")
## kind, camera distance in instance-heights, look-at height share
const SHOTS := [["conifer", 1.4, 0.5], ["broadleaf", 1.6, 0.5], ["bush", 3.5, 0.4], ["rock", 3.0, 0.3]]

var _out: String = "user://captures"
var _season := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--season="):
			_season = arg.trim_prefix("--season=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(60)
	var cycle := get_tree().root.find_child("DayNightCycle", true, false) as DayNightCycle
	cycle.time_override = 12.0
	cycle.refresh()
	if _season != "":
		var seasons := get_tree().root.find_child("Seasons", true, false)
		if seasons != null:
			seasons.set_season(_season)
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	var spawn := player.global_position
	for shot in SHOTS:
		var at := _nearest(str(shot[0]), spawn + Vector3(0, 0, 60))
		if at == Transform3D():
			print("no ", shot[0])
			continue
		var size: float = maxf(at.basis.get_scale().x, 0.3) * (10.0 if shot[0] in ["conifer", "broadleaf"] else 1.6)
		player.global_position = at.origin + Vector3(3, 2, 3)
		await _frames(30)
		for side in [["near", 1.0], ["far", 2.5]]:
			var dir := Vector3(0.8, 0.25, 0.55).normalized()
			cam.global_position = at.origin + dir * size * float(shot[1]) * float(side[1]) + Vector3.UP * size * 0.2
			cam.look_at(at.origin + Vector3.UP * size * float(shot[2]), Vector3.UP)
			cam.current = true
			cycle.time_override = 12.0
			cycle.refresh()
			await _frames(20)
			_save("%s_%s%s" % [shot[0], side[0], "_" + _season if _season != "" else ""])
	# A wide view: high over the spawn, looking across the grounds.
	cam.global_position = spawn + Vector3(0, 30, -20)
	cam.look_at(spawn + Vector3(0, 0, 120), Vector3.UP)
	await _frames(20)
	_save("wide%s" % ("_" + _season if _season != "" else ""))
	get_tree().quit()


## The flora instance of `kind` nearest to `point` (world transform), from the terrain's
## MultiMesh cells.
func _nearest(kind: String, point: Vector3) -> Transform3D:
	var best := Transform3D()
	var best_d := INF
	for mmi in get_tree().root.find_children("Flora_%s_*" % kind, "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var t := (mmi as MultiMeshInstance3D).global_transform * mm.get_instance_transform(i)
			var d := t.origin.distance_to(point)
			if d < best_d:
				best_d = d
				best = t
	return best


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

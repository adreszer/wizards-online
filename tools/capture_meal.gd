extends Node
## Dev tool: the great hall at lunch, with a player seated at a feast bench eating
## (needs a window; not --headless).
##   godot --path . tools/capture_meal.tscn -- --out=/absolute/dir

const WORLD := preload("res://core/world.tscn")

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(40)
	var cycle := get_tree().root.find_child("DayNightCycle", true, false) as DayNightCycle
	cycle.time_override = 12.5
	cycle.refresh()
	var meals := get_tree().root.find_child("FeastMeals", true, false) as FeastMeals
	meals.update(false)
	var player := get_tree().get_first_node_in_group("local_player") as Player
	var table: Transform3D = meals.tables[5]
	player.global_position = table * Vector3(0.5, 0.05, -1.6)
	await _frames(10)
	player.try_sit()
	await _frames(30)
	meals.update(false)
	await get_tree().create_timer(1.2).timeout
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	var hips := player.global_position
	cam.global_position = hips + table.basis * Vector3(1.8, 1.6, -2.4)
	cam.look_at(hips + Vector3(0, 0.9, 0), Vector3.UP)
	await _frames(10)
	get_viewport().get_texture().get_image().save_png(_out.path_join("meal_close.png"))
	cam.global_position = table * Vector3(-6.0, 4.0, -6.0)
	cam.look_at(table * Vector3(4.0, 0.8, 0.0), Vector3.UP)
	await _frames(10)
	get_viewport().get_texture().get_image().save_png(_out.path_join("meal_hall.png"))
	print("seated=%s gesture=%s serving=%s" % [player.gestures.is_sitting(), player.gestures.current, meals.serving])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

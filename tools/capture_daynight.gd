extends Node
## Dev tool: runs the real World (offline) and saves PNGs of the same views at
## several school hours, to judge the day/night looks (needs a window; not --headless).
##   godot --path . tools/capture_daynight.tscn -- --out=/absolute/dir

const WORLD := preload("res://core/world.tscn")
const HOURS := [0.0, 5.6, 6.5, 9.0, 12.0, 18.5, 19.6, 21.0]

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(60)
	var cycle := get_tree().root.find_child("DayNightCycle", true, false) as DayNightCycle
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	for view in [["grounds", player.global_position], ["hall", Vector3(0, 0.2, 36)], ["dungeon", Vector3(-16, -8.8, 15)]]:
		player.global_position = view[1]
		await _frames(30)
		for h: float in HOURS:
			cycle.time_override = h
			cycle.refresh()
			await _frames(20)
			_save("%s_%s" % [view[0], SchoolClock.format(h).replace(":", "")])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

extends Node
## Dev tool: the paddock creatures standing, mid-stride (walking in a circle), and a
## mossling perched on a student's shoulder as a familiar (needs a window; not --headless).
##   godot --path . tools/capture_creatures.tscn -- --out=/absolute/dir

const SCENE := preload("res://levels/dev/asset_validation.tscn")
const KINDS := ["mossling", "emberkit", "glimmerwing"]

var _out: String = "user://captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _run() -> void:
	var level := SCENE.instantiate()
	add_child(level)
	await _frames(20)
	var player := get_tree().get_first_node_in_group("local_player") as Player
	player.global_position = Vector3(8, 0.05, -3.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var origin := Vector3(4, 0.05, 1.0)
	var creatures: Array[Creature] = []
	for i in KINDS.size():
		var c := GroundsLife.build_creature(KINDS[i], Color.WHITE) as Creature
		level.add_child(c)
		c.global_position = origin + Vector3(i * 0.9 - 0.9, 0.3 if KINDS[i] == "glimmerwing" else 0.0, 0)
		c.rotation.y = PI   # facing the camera (+Z); there is a wall behind it
		creatures.append(c)
	await _frames(30)
	for view in [["front", Vector3(0, 0.6, 2.4)], ["side", Vector3(2.0, 0.5, 1.4)]]:
		cam.global_position = origin + (view[1] as Vector3)
		cam.look_at(origin + Vector3(0, 0.25, 0), Vector3.UP)
		await _frames(3)
		_save("rest_" + str(view[0]))
	# Walking in a circle: grab a few moments of the gait from the side.
	var t := 0.0
	var shot := 0
	while shot < 3:
		t += get_process_delta_time()
		for i in creatures.size():
			var a := t * 0.9 + i * 2.1
			var at := origin + Vector3(cos(a) * 1.2, 0.3 if KINDS[i] == "glimmerwing" else 0.0, sin(a) * 1.2)
			creatures[i].look_at(Vector3(at.x, creatures[i].global_position.y, at.z), Vector3.UP) if at.distance_to(creatures[i].global_position) > 0.01 else null
			creatures[i].global_position = at
		cam.global_position = origin + Vector3(0, 1.6, 3.2)
		cam.look_at(origin + Vector3(0, 0.2, 0), Vector3.UP)
		await get_tree().process_frame
		if t > 1.0 + shot * 0.43:
			_save("walk_%d" % shot)
			shot += 1
	# A familiar on the shoulder.
	var pet := GroundsLife.build_creature("mossling", Color.WHITE) as Creature
	pet.get_node("Care").queue_free()
	pet.scale = Vector3.ONE * 0.55
	pet.perched = true
	player.add_child(pet)
	for i in 20:
		pet.global_position = PotionEffects.shoulder_of(player)
		pet.global_rotation.y = player.global_rotation.y
		await get_tree().process_frame
	cam.global_position = player.global_position + Vector3(-1.0, 1.8, -1.6)
	cam.look_at(player.global_position + Vector3(0.2, 1.5, 0), Vector3.UP)
	await _frames(3)
	_save("familiar")
	print("Saved captures to %s" % _out)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

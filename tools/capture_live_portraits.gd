extends Node
## Dev tool: each sitter's painted portrait beside its live one (LivePortrait), under
## the same light, plus a wave, to check that the live canvas matches the painting
## (needs a window; not --headless).
##   godot --path . tools/capture_live_portraits.tscn -- --out=/absolute/dir [--sitters=1,2]

const PORTRAIT := "res://objects/environment/props/portraits/portrait_%02d.tscn"

var _out: String = "user://captures"
var _sitters: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--sitters="):
			_sitters.clear()
			for s in arg.trim_prefix("--sitters=").split(","):
				_sitters.append(s.to_int())
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.08, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.48, 0.45)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	add_child(sun)
	sun.look_at_from_position(Vector3(1, 3, 4), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.0, 2.2, 2.3), Vector3(0.0, 2.2, 0.0))
	for id in _sitters:
		var painted: Node3D = (load(PORTRAIT % id) as PackedScene).instantiate()
		painted.position.x = -0.45
		add_child(painted)
		var live := LivePortrait.new()
		add_child(live)
		live.position.x = 0.45
		live.setup(id)
		var frame: Node3D = (load(PORTRAIT % id) as PackedScene).instantiate()
		frame.get_node("Canvas").visible = false
		live.add_child(frame)
		live.look_toward(Vector3(0.45, 1.6, 2.0))
		await get_tree().create_timer(LivePortrait.FADE_SECONDS + 0.4).timeout
		await _save("live_%02d_rest.png" % id)
		# The sitter's own view, before the varnish (to register it against the painting).
		live.get_child(0).get_texture().get_image().save_png(_out.path_join("raw_%02d.png" % id))
		if live.gesture(&"wave"):
			await get_tree().create_timer(0.9).timeout
			await _save("live_%02d_wave.png" % id)
		painted.queue_free()
		live.queue_free()
		await _frames(2)
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## Dev tool: renders one model (.glb) or wrapper scene (.tscn) on a floor tile
## from fixed angles and saves PNGs (needs a window; not --headless). Used to
## check a new prop's orientation and scale before it is placed in a level.
##   godot --path . tools/capture_model.tscn -- --scene=res://path/to/model.glb --out=/absolute/dir [--dist=3.5]
## With --eye=x,y,z --target=x,y,z a full scene (.tscn, no extra floor/lights) is
## rendered once from that viewpoint instead, e.g. to look into a castle room.

const FLOOR := preload("res://objects/environment/modular/floor_tile.tscn")

## name, camera direction (unit-ish, scaled by --dist), look-at height factor
const VIEWS := [
	["01_front_-z", Vector3(0.0, 0.5, -1.0)],
	["02_back_+z", Vector3(0.0, 0.5, 1.0)],
	["03_side_+x", Vector3(1.0, 0.5, 0.0)],
	["04_iso", Vector3(0.8, 0.9, -0.8)],
	["05_top", Vector3(0.05, 1.6, -0.3)],
]

var _out: String = "user://captures"
var _scene: String = ""
var _dist: float = 3.5
var _eye := Vector3.INF
var _double_sided := false
var _target := Vector3.INF


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			_scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--dist="):
			_dist = float(arg.trim_prefix("--dist="))
		elif arg == "--double-sided":
			_double_sided = true
		elif arg.begins_with("--eye="):
			_eye = _vec(arg.trim_prefix("--eye="))
		elif arg.begins_with("--target="):
			_target = _vec(arg.trim_prefix("--target="))
	if _scene.is_empty():
		push_error("--scene=res://... is required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()


func _vec(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _run() -> void:
	var custom := _eye != Vector3.INF and _target != Vector3.INF
	var packed := load(_scene) as PackedScene
	if packed == null:
		push_error("Could not load %s" % _scene)
		get_tree().quit(1)
		return
	if custom:
		add_child(packed.instantiate())
		await _frames(30)
		var cam := Camera3D.new()
		cam.fov = 60.0
		cam.near = 0.05
		add_child(cam)
		cam.current = true
		cam.global_position = _eye
		cam.look_at(_target, Vector3.UP)
		await _frames(20)
		_save("custom")
		print("Saved 1 capture of %s to %s" % [_scene, _out])
		get_tree().quit(0)
		return
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.68, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_tile := FLOOR.instantiate()
	add_child(floor_tile)
	var model := packed.instantiate() as Node3D
	add_child(model)
	if _double_sided:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in range((mi as MeshInstance3D).mesh.get_surface_count()):
				var mat := (mi as MeshInstance3D).mesh.surface_get_material(i) as BaseMaterial3D
				if mat != null:
					mat = mat.duplicate()
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					(mi as MeshInstance3D).set_surface_override_material(i, mat)
	# Axis gizmo: red +X, blue +Z, so the captures show the model's own frame.
	_axis(Vector3(1, 0, 0), Color.RED)
	_axis(Vector3(0, 0, 1), Color.BLUE)
	await _frames(20)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	var target := Vector3(0, 0.45, 0)
	for view in VIEWS:
		cam.global_position = target + (view[1] as Vector3).normalized() * _dist
		cam.look_at(target, Vector3.UP)
		await _frames(12)
		_save(view[0])
	print("Saved %d captures of %s to %s" % [VIEWS.size(), _scene, _out])
	get_tree().quit(0)


func _axis(dir: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 0.04) + dir.abs() * 1.5
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = dir * 0.77 + Vector3(0, 0.02, 0)
	add_child(mi)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		push_error("Could not save %s (%d)" % [path, err])

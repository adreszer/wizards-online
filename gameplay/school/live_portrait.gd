class_name LivePortrait
extends Node3D
## One portrait come to life: the sitter's model in its own small world, framed and lit
## like the portrait studio (tools/render_portrait.py: 85 mm lens, warm key, cool fill,
## rim light, dark warm backdrop), drawn onto a canvas laid over the painted one through
## the paintings' oil varnish (live_portrait.gdshader), cross-fading from the painting. Rigged sitters breathe, follow
## the player with their head (SitterPose) and gesture (SocialPose); busts sway.
## LivePortraits creates these at the portrait's transform and frees them again.

const MODEL := "res://assets/models/portraits/sitter_%02d.glb"
const PAINTING := "res://assets/textures/portraits/portrait_%02d.jpg"
const SHADER := preload("res://gameplay/school/live_portrait.gdshader")
## The canvas in a portrait scene (objects/environment/props/portraits/portrait_XX.tscn),
## just in front of the painted one.
const CANVAS_SIZE := Vector2(0.7057, 0.8992)
const CANVAS_AT := Vector3(0.0035, 2.2025, 0.0294)
const RESOLUTION := Vector2i(384, 490)
## Sitters generated in a T-pose (painted with their hands folded) and the busts.
const RELAXED := [2, 3, 4]
const BUSTS := [8, 9, 10]
const FADE_SECONDS := 0.8
## Per sitter: how much closer the camera comes (x) and how far it moves up, as a
## fraction of the view's height (y), to line the live view up with the painting.
## Measured by registering each live frame against its painting (edge correlation);
## the older paintings (01, 05-10) came from the full-detail models.
const FRAMING := {
	1: Vector2(0.94, -0.148), 2: Vector2(0.86, -0.172), 3: Vector2(0.88, -0.172), 4: Vector2(0.88, -0.172),
	5: Vector2(0.98, -0.148), 6: Vector2(0.96, -0.148), 7: Vector2(0.96, -0.148),
	8: Vector2(1.42, 0.008), 9: Vector2(1.40, -0.008), 10: Vector2(1.38, 0.0),
}

var sitter := 0
## Fading out before LivePortraits frees it.
var leaving := false

var _viewport: SubViewport
var _model: Node3D
var _material: ShaderMaterial
var _sitter_pose: SitterPose
var _social: SocialPose
var _gesture_left := 0.0
var _fade := 0.0
var _time := 0.0
var _look := Vector2.ZERO


static func has_model(id: int) -> bool:
	return id > 0 and ResourceLoader.exists(MODEL % id)


static func is_rigged(id: int) -> bool:
	return has_model(id) and not BUSTS.has(id)


func setup(id: int) -> void:
	sitter = id
	_time = float(id) * 1.7
	_viewport = SubViewport.new()
	_viewport.size = RESOLUTION
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_model = (load(MODEL % id) as PackedScene).instantiate()
	_viewport.add_child(_model)
	var skeleton: Skeleton3D = null
	for node in _model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	if skeleton != null and not BUSTS.has(id):
		_sitter_pose = SitterPose.new()
		_sitter_pose.relaxed = RELAXED.has(id)
		_sitter_pose.phase = _time
		skeleton.add_child(_sitter_pose)
		_social = SocialPose.new()
		_social.influence = 0.0
		_social.active = false
		skeleton.add_child(_social)
	_frame(BUSTS.has(id))
	var canvas := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = CANVAS_SIZE
	canvas.mesh = quad
	canvas.position = CANVAS_AT
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("sitter", _viewport.get_texture())
	_material.set_shader_parameter("painting", load(PAINTING % id))
	_material.set_shader_parameter("fade", 0.0)
	canvas.material_override = _material
	add_child(canvas)


## The studio camera and lights around the sitter: full figures framed from the head
## to the belt, busts whole (as the paintings were rendered).
func _frame(bust: bool) -> void:
	var box := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = (_model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var top := box.end.y
	var h := box.size.y
	var span := h * 1.08 if bust else h * 0.42
	var target := Vector3(box.get_center().x, box.get_center().y if bust else top - span * 0.47, box.get_center().z)
	var camera := Camera3D.new()
	camera.fov = rad_to_deg(2.0 * atan(12.0 / 85.0))
	var fit: Vector2 = FRAMING.get(sitter, Vector2.ONE)
	var distance := span * 3.53 * 1.38 / fit.x
	camera.position = target + Vector3(0.0, span * 0.05, distance)
	var view_height := 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	target.y += fit.y * view_height
	camera.position.y += fit.y * view_height
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.03, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.03, 0.025, 0.02)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	camera.environment = env
	_viewport.add_child(camera)
	camera.look_at_from_position(camera.position, target)
	# Directions toward each light from the sitter (Godot axes: +Z toward the viewer).
	for l: Array in [[Vector3(-1.3, 1.0, 1.6), Color(1.0, 0.86, 0.68), 2.2],
			[Vector3(1.6, 0.2, 1.4), Color(0.75, 0.82, 1.0), 0.3],
			[Vector3(1.0, 0.9, -1.4), Color(1.0, 0.8, 0.6), 1.6]]:
		var light := DirectionalLight3D.new()
		light.light_color = l[1]
		light.light_energy = l[2]
		_viewport.add_child(light)
		light.look_at_from_position(target + (l[0] as Vector3), target)


## Head (and busts' sway) toward a point in the world, e.g. the player's head.
func look_toward(world_point: Vector3) -> void:
	var local := global_transform.affine_inverse() * world_point - CANVAS_AT
	var yaw := clampf(atan2(local.x, maxf(local.z, 0.1)), -0.6, 0.6)
	var pitch := clampf(atan2(-local.y, maxf(Vector2(local.x, local.z).length(), 0.1)), -0.25, 0.35)
	_look = Vector2(yaw, pitch)
	if _sitter_pose != null:
		_sitter_pose.look = _look


## Plays a one-shot gesture (Gestures.ONE_SHOT) if this sitter is rigged.
func gesture(id: StringName) -> bool:
	if _social == null or not Gestures.ONE_SHOT.has(id) or _gesture_left > 0.0:
		return false
	_social.gesture = id
	_social.elapsed = 0.0
	_gesture_left = Gestures.ONE_SHOT[id]
	return true


func is_gesturing() -> bool:
	return _gesture_left > 0.0


func _process(delta: float) -> void:
	_time += delta
	_fade = move_toward(_fade, 0.0 if leaving else 1.0, delta / FADE_SECONDS)
	_material.set_shader_parameter("fade", _fade)
	if leaving and _fade <= 0.0:
		queue_free()
		return
	if _social != null:
		_gesture_left = maxf(0.0, _gesture_left - delta)
		_social.influence = move_toward(_social.influence, 1.0 if _gesture_left > 0.0 else 0.0, delta * Gestures.BLEND_SPEED)
		_social.active = _social.influence > 0.0
		if not _social.active:
			_social.gesture = &""
	elif _model != null:
		# Busts: a slow sway and breath, turned a little toward the viewer.
		_model.rotation.y = lerpf(_model.rotation.y, _look.x * 0.35 + sin(_time * 0.45) * 0.03, minf(1.0, delta * 2.0))
		_model.rotation.x = sin(_time * 0.31) * 0.012
		_model.scale = Vector3(1.0, 1.0 + sin(_time * TAU / 4.2) * 0.006, 1.0)

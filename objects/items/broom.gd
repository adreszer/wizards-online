@tool
class_name BroomModel
extends Node3D
## Procedural flying broom: a tapered wooden shaft with a carved knob, brass
## bindings and a flared bundle of twigs. The origin is the seat (where the
## rider sits); the shaft points forward (-Z) and the twigs trail behind (+Z).
## A placeholder until a modelled broom is dropped into assets/: swap the
## ItemDefinition's mount_scene and nothing else changes.
##
## [member trail] adds drifting sparks behind the twigs (on while ridden, off
## on a rack).

@export var trail: bool = true:
	set(value):
		trail = value
		if _trail != null:
			_trail.emitting = value
			_trail.visible = value

const SHAFT_FRONT := 1.05
const SHAFT_BACK := 0.45
const TWIG_LENGTH := 0.68

var _trail: GPUParticles3D


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		if child.has_meta(&"generated"):
			child.free()
	var wood := _wood_material()
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.56, 0.28)
	brass.metallic = 0.9
	brass.roughness = 0.32
	var straw := _straw_material()

	# Shaft: slightly thicker at the bindings, thinning toward the knob.
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.021
	shaft.bottom_radius = 0.028
	shaft.height = SHAFT_FRONT + SHAFT_BACK
	shaft.radial_segments = 14
	shaft.rings = 1
	_add(shaft, wood, _along_z(-(SHAFT_FRONT - SHAFT_BACK) / 2.0, true))
	var knob := SphereMesh.new()
	knob.radius = 0.034
	knob.height = 0.062
	knob.radial_segments = 14
	knob.rings = 7
	_add(knob, wood, Transform3D(Basis.IDENTITY, Vector3(0, 0, -SHAFT_FRONT)))

	# Twig bundle: a flared core and a few splayed strands for a ragged outline.
	var core := CylinderMesh.new()
	core.top_radius = 0.045
	core.bottom_radius = 0.15
	core.height = TWIG_LENGTH
	core.radial_segments = 20
	core.rings = 2
	# Narrow (top) end tied to the shaft, flaring out behind.
	_add(core, straw, _along_z(SHAFT_BACK - 0.08 + TWIG_LENGTH / 2.0, true))
	var strand := CylinderMesh.new()
	strand.top_radius = 0.006
	strand.bottom_radius = 0.012
	strand.height = TWIG_LENGTH * 0.92
	strand.radial_segments = 5
	strand.rings = 1
	var count := 14
	for i in count:
		var angle := TAU * float(i) / count + 0.3 * sin(i * 2.7)
		var spread := 0.16 + 0.04 * sin(i * 1.9)
		var start := Vector3(cos(angle) * 0.035, sin(angle) * 0.035, SHAFT_BACK - 0.05)
		var tip := Vector3(cos(angle) * spread, sin(angle) * spread, SHAFT_BACK - 0.05 + TWIG_LENGTH * (0.95 + 0.06 * sin(i * 3.3)))
		_add(strand, straw, _between(start, tip))

	# Brass bindings where the twigs are tied on, and a grip ring at the seat.
	for z in [SHAFT_BACK - 0.12, SHAFT_BACK - 0.02]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.05 if z > SHAFT_BACK - 0.08 else 0.026
		ring.outer_radius = ring.inner_radius + 0.016
		ring.rings = 16
		ring.ring_segments = 8
		_add(ring, brass, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, z)))
	var grip := TorusMesh.new()
	grip.inner_radius = 0.022
	grip.outer_radius = 0.036
	grip.rings = 16
	grip.ring_segments = 6
	_add(grip, brass, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -0.62)))

	_trail = _make_trail()
	_trail.position = Vector3(0, 0, SHAFT_BACK + TWIG_LENGTH)
	_trail.emitting = trail
	_trail.visible = trail
	_mark(_trail)


func _add(mesh: Mesh, material: Material, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xform
	_mark(mi)
	return mi


func _mark(node: Node) -> void:
	node.set_meta(&"generated", true)
	add_child(node)


## A Y-up primitive laid along Z, centred at z. `top_forward`: its top (+Y) end points -Z.
func _along_z(z: float, top_forward: bool) -> Transform3D:
	var basis := Basis(Vector3.RIGHT, -PI / 2.0 if top_forward else PI / 2.0)
	return Transform3D(basis, Vector3(0, 0, z))


## A Y-up primitive spanning from `a` (bottom) to `b` (top).
func _between(a: Vector3, b: Vector3) -> Transform3D:
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	return Transform3D(basis, (a + b) / 2.0)


func _wood_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.width = 64
	tex.height = 256
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.24, 0.13, 0.07))
	ramp.set_color(1, Color(0.47, 0.29, 0.15))
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	# Stretch the noise along the shaft so it reads as grain.
	mat.uv1_scale = Vector3(1.0, 6.0, 1.0)
	mat.roughness = 0.55
	return mat


func _straw_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 32
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.37, 0.18))
	ramp.set_color(1, Color(0.86, 0.71, 0.42))
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(4.0, 1.0, 1.0)
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_trail() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 28
	particles.lifetime = 0.9
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3(0, 0.3, 1)
	process.spread = 25.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0, 0.25, 0)
	process.scale_min = 0.5
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
	fade.set_color(1, Color(0.7, 0.6, 1.0, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	process.color_ramp = fade_tex
	particles.process_material = process
	var mote := SphereMesh.new()
	mote.radius = 0.018
	mote.height = 0.036
	mote.radial_segments = 6
	mote.rings = 3
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1, 1, 1)
	mote.material = glow
	particles.draw_pass_1 = mote
	return particles

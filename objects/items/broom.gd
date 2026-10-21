@tool
class_name BroomModel
extends Node3D
## The flying broom (assets/models/items/broom.glb, Meshy: a polished shaft with a
## carved tip, brass bands and a full birch-twig bundle). The origin is the seat
## (where the rider sits); the shaft points forward (-Z) and the twigs trail
## behind (+Z).
##
## [member trail] adds drifting sparks behind the twigs (on while ridden, off
## on a rack).

@export var trail: bool = true:
	set(value):
		trail = value
		if _trail != null:
			_trail.emitting = value
			_trail.visible = value

const MODEL := preload("res://assets/models/items/broom.glb")
## How far the shaft reaches ahead of the seat, where the twigs are tied on behind it,
## and how long the twigs trail from there.
const SHAFT_FRONT := 0.92
const SHAFT_BACK := 0.2
const TWIG_LENGTH := 1.07
## Where the model's origin goes so the seat is SHAFT_FRONT behind its tip (1.773 m ahead of its origin).
const SEAT := 1.773 - SHAFT_FRONT

var _trail: GPUParticles3D


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		if child.has_meta(&"generated"):
			child.free()
	var model := (MODEL as PackedScene).instantiate() as Node3D
	# The model lies along -Z (tip forward), its shaft 0.244 m above its base; the seat
	# sits SEAT behind the tip.
	model.position = Vector3(0, -0.244, SEAT)
	_mark(model)
	_trail = _make_trail()
	_trail.position = Vector3(0, 0, SHAFT_BACK + TWIG_LENGTH)
	_trail.emitting = trail
	_trail.visible = trail
	_mark(_trail)


func _mark(node: Node) -> void:
	node.set_meta(&"generated", true)
	add_child(node)


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

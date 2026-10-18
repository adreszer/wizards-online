class_name InteractSpot
extends StaticBody3D
## A small glowing spot the local player can use (Interact): a detention task's next
## chore, a garden plot, a cauldron, a creature's pen… built entirely in code so feature
## nodes can scatter them at runtime. It sits on the interactable layer only, so it
## never blocks movement. [signal used] fires on interaction; the owner decides what
## happens (usually a server request) and recolours it with [method set_state].

signal used(interactor: Node)

const LAYER_INTERACTABLE := 16

var interactable: Interactable
var label: Label3D
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _light: OmniLight3D


## A spot at `at` (global) with the HUD prompt `prompt` (a translation key) and a glow `color`.
static func create(prompt: String, color: Color, radius: float = 0.35) -> InteractSpot:
	var spot := InteractSpot.new()
	spot.collision_layer = LAYER_INTERACTABLE
	spot.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius + 0.15
	shape.shape = sphere
	spot.add_child(shape)
	spot._mesh = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.45
	mesh.height = radius * 0.9
	spot._mesh.mesh = mesh
	spot._material = StandardMaterial3D.new()
	spot._material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spot._material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spot._mesh.material_override = spot._material
	spot._mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.add_child(spot._mesh)
	spot._light = OmniLight3D.new()
	spot._light.omni_range = 2.2
	spot._light.light_energy = 0.6
	spot._light.shadow_enabled = false
	spot.add_child(spot._light)
	spot.label = Label3D.new()
	spot.label.position = Vector3(0, radius + 0.35, 0)
	spot.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spot.label.font_size = 28
	spot.label.pixel_size = 0.003
	spot.label.outline_size = 8
	spot.label.no_depth_test = false
	spot.add_child(spot.label)
	spot.interactable = Interactable.new()
	spot.interactable.prompt_text = prompt
	spot.interactable.focus_point_offset = Vector3.ZERO
	spot.add_child(spot.interactable)
	spot.interactable.interacted.connect(func(who: Node) -> void: spot.used.emit(who))
	spot.set_state(color, true)
	return spot


## Recolours the spot; a disabled spot dims and stops taking interactions.
func set_state(color: Color, enabled: bool = true, text: String = "") -> void:
	_material.albedo_color = Color(color.r, color.g, color.b, 0.85 if enabled else 0.25)
	_light.light_color = color
	_light.visible = enabled
	interactable.enabled = enabled
	label.text = text
	label.visible = text != ""


func _process(_delta: float) -> void:
	if interactable.enabled:
		var t := Time.get_ticks_msec() / 1000.0
		_mesh.position.y = sin(t * 2.0 + position.x) * 0.06

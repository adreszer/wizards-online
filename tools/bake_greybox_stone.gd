extends SceneTree
## Bakes the tileable textures behind assets/materials/greybox_stone.tres by
## rendering the front face of wall_plain.glb orthographically: one pass writes
## the stone albedo, one the geometric normal as an OpenGL-style normal map.
## The model's own textures are UV atlases (stone islands on black), so they
## can't be tiled or projected onto other geometry directly.
##
## Run: godot --path . --resolution 1024x1024 -s tools/bake_greybox_stone.gd

const MODULE := "res://objects/environment/modular/wall_plain.tscn"
const WALL_MATERIAL := "res://objects/environment/modular/wall_stone.tres"
const OUT_ALBEDO := "res://assets/materials/greybox_stone_albedo.png"
const OUT_NORMAL := "res://assets/materials/greybox_stone_normal.png"
## Colour behind the bevelled stone borders; matches ModularWallRun's mortar.
const MORTAR := Color(0.11, 0.1, 0.09)

const BAKE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool normal_pass = false;
varying vec3 world_normal;
void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
	if (normal_pass) {
		// Face looks along +Z: tangent +X, bitangent +Y. The viewport writes sRGB,
		// so undo that to keep the encoded vector exact.
		ALBEDO = to_linear(normalize(world_normal) * 0.5 + 0.5);
	} else {
		ALBEDO = texture(albedo_texture, UV).rgb;
	}
}
"""

var _frame := 0
var _material: ShaderMaterial
var _backdrop: StandardMaterial3D
var _env: Environment


func _initialize() -> void:
	var scene := Node3D.new()
	get_root().add_child(scene)

	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BAKE_SHADER
	_material.shader = shader
	var wall_mat: ShaderMaterial = load(WALL_MATERIAL)
	_material.set_shader_parameter("albedo_texture", wall_mat.get_shader_parameter("albedo_texture"))

	var module: Node3D = load(MODULE).instantiate()
	scene.add_child(module)
	for mi in module.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _material

	# Mortar backdrop seen through the bevelled borders.
	var plane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 6)
	plane.mesh = quad
	plane.position = Vector3(0, 2, -0.1)
	_backdrop = StandardMaterial3D.new()
	_backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_backdrop.albedo_color = MORTAR
	plane.material_override = _backdrop
	scene.add_child(plane)

	var env := WorldEnvironment.new()
	_env = Environment.new()
	env.environment = _env
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = MORTAR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	scene.add_child(env)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.position = Vector3(0, 2, 5)
	scene.add_child(cam)
	cam.current = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 10:
		_save(OUT_ALBEDO)
		_material.set_shader_parameter("normal_pass", true)
		# Flat backdrop facing the camera: straight-on normal (0.5, 0.5, 1.0).
		_backdrop.albedo_color = Color(0.5, 0.5, 1.0)
		_env.background_color = _backdrop.albedo_color
	elif _frame == 20:
		_save(OUT_NORMAL)
		return true
	return false


func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(ProjectSettings.globalize_path(path))
	print("baked ", path, " ", img.get_size())

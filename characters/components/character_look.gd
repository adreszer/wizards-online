class_name CharacterLook
extends RefCounted
## A character's chosen look: body, skin tone and robe colour, plus the house colour
## on the trim. Stored in the server profile (`appearance`) online and in the local
## settings offline; applied to a character visual by swapping its imported
## materials for character_look.gdshader with the same textures.

const SHADER := preload("res://characters/visuals/character_look.gdshader")
## Skin tones: multipliers on the painted skin (0 = as painted).
const SKIN_TONES: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.92, 0.86), Color(0.86, 0.7, 0.58), Color(0.66, 0.5, 0.4), Color(0.45, 0.32, 0.26)]
## Robe colours (0 = the painted charcoal, untouched).
const ROBE_COLORS: Array[Color] = [Color(0.2, 0.2, 0.2), Color(0.06, 0.06, 0.07), Color(0.32, 0.22, 0.15), Color(0.18, 0.2, 0.33), Color(0.22, 0.27, 0.17)]
const ROBE_KEYS: Array[String] = ["ROBE_CHARCOAL", "ROBE_BLACK", "ROBE_BROWN", "ROBE_NAVY", "ROBE_MOSS"]
const SKIN_KEYS: Array[String] = ["SKIN_1", "SKIN_2", "SKIN_3", "SKIN_4", "SKIN_5"]


## {body, skin, robe, set} with every value in range; `set` is true once the player chose.
static func sanitize(raw: Variant) -> Dictionary:
	var d: Dictionary = raw if raw is Dictionary else {}
	return {
		"body": CharacterRegistry.sanitize(str(d.get("body", CharacterRegistry.DEFAULT))),
		"skin": clampi(int(d.get("skin", 0)), 0, SKIN_TONES.size() - 1),
		"robe": clampi(int(d.get("robe", 0)), 0, ROBE_COLORS.size() - 1),
		"set": d.get("set", false) == true,
	}


## Applies `look` and `house` to every mesh under `visual` (materials become the look
## shader once; later calls only update its parameters).
static func apply(visual: Node, look: Dictionary, house: int) -> void:
	if visual == null:
		return
	var clean := sanitize(look)
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.get_parent() is BoneAttachment3D or mi.name in ["WandMesh", "Glow"]:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := _look_material(mi, s)
			if mat == null:
				continue
			mat.set_shader_parameter("house_amount", 1.0 if house > 0 else 0.0)
			mat.set_shader_parameter("house_color", CharacterProfile.house_color(house))
			mat.set_shader_parameter("skin_tint", SKIN_TONES[clean.skin])
			mat.set_shader_parameter("robe_color", ROBE_COLORS[clean.robe])
			mat.set_shader_parameter("robe_amount", 0.0 if clean.robe == 0 else 0.85)


## The look ShaderMaterial on surface `s` of `mi`, made from its imported material on first use.
static func _look_material(mi: MeshInstance3D, s: int) -> ShaderMaterial:
	var current := mi.get_surface_override_material(s)
	if current is ShaderMaterial and (current as ShaderMaterial).shader == SHADER:
		return current
	var source := mi.mesh.surface_get_material(s) as StandardMaterial3D
	if source == null or source.albedo_texture == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_texture", source.albedo_texture)
	mat.set_shader_parameter("albedo_color", source.albedo_color)
	if source.normal_enabled and source.normal_texture != null:
		mat.set_shader_parameter("normal_texture", source.normal_texture)
		mat.set_shader_parameter("has_normal", true)
	if source.metallic_texture != null:
		mat.set_shader_parameter("orm_texture", source.metallic_texture)
		mat.set_shader_parameter("has_orm", true)
	mi.set_surface_override_material(s, mat)
	return mat

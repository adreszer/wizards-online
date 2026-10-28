class_name CharacterLook
extends RefCounted
## A character's chosen look: body, skin tone and robe colour, plus the house colour
## on the trim and the house crest sewn on the left breast (a decal on the chest bone). Stored in the server profile (`appearance`) online and in the local
## settings offline; applied to a character visual by swapping its imported
## materials for character_look.gdshader with the same textures.

const SHADER := preload("res://characters/visuals/character_look.gdshader")
## Skin tones: multipliers on the painted skin (0 = as painted).
const SKIN_TONES: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.92, 0.86), Color(0.86, 0.7, 0.58), Color(0.66, 0.5, 0.4), Color(0.45, 0.32, 0.26)]
## Robe colours (0 = the painted charcoal, untouched).
const ROBE_COLORS: Array[Color] = [Color(0.2, 0.2, 0.2), Color(0.06, 0.06, 0.07), Color(0.32, 0.22, 0.15), Color(0.18, 0.2, 0.33), Color(0.22, 0.27, 0.17)]
const ROBE_KEYS: Array[String] = ["ROBE_CHARCOAL", "ROBE_BLACK", "ROBE_BROWN", "ROBE_NAVY", "ROBE_MOSS"]
## About the skin of the bodies' textures, so a tone's swatch shows the skin it gives.
const SKIN_BASE := Color(0.95, 0.76, 0.62)
const SKIN_KEYS: Array[String] = ["SKIN_1", "SKIN_2", "SKIN_3", "SKIN_4", "SKIN_5"]
## The robe crest: on the upper-spine bone, offset in the character's frame
## (it faces -Z): up, toward the wearer's left, and out to the chest.
const CREST_BONE := "mixamorig_Spine2"
const CREST_OFFSET := Vector3(-0.09, 0.07, -0.1)
## Patch width and how deep the projection reaches (from behind the robe front to in front of it).
const CREST_SIZE := 0.11
const CREST_DEPTH := 0.3


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
			# The cup holders' trim shines brighter for the term (their reward).
			var color := CharacterProfile.house_color(house)
			if house > 0 and int(NetworkManager.house_cup.get("winner", 0)) == house:
				color = color.lightened(0.35)
			mat.set_shader_parameter("house_color", color)
			mat.set_shader_parameter("skin_tint", SKIN_TONES[clean.skin])
			mat.set_shader_parameter("robe_color", ROBE_COLORS[clean.robe])
			mat.set_shader_parameter("robe_amount", 0.0 if clean.robe == 0 else 0.85)
	_apply_crest(visual, house)


## Shows `house`'s crest on the robe (hidden for the unsorted). The decal hangs from
## a BoneAttachment3D on CREST_BONE (a child of the skeleton) so it moves with the
## chest. The animated pose turns that bone well away from its rest pose, so the
## patch is placed from the posed bone once the character is in the tree.
static func _apply_crest(visual: Node, house: int) -> void:
	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not visual is Node3D:
		return
	var skeleton := skeletons[0] as Skeleton3D
	var mount := skeleton.get_node_or_null("CrestMount") as BoneAttachment3D
	if mount == null:
		if skeleton.find_bone(CREST_BONE) < 0:
			return
		mount = BoneAttachment3D.new()
		mount.name = "CrestMount"
		mount.bone_name = CREST_BONE
		skeleton.add_child(mount)
		var decal := Decal.new()
		decal.name = "Crest"
		decal.size = Vector3(CREST_SIZE, CREST_DEPTH, CREST_SIZE)
		decal.normal_fade = 0.4
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.visible = false
		mount.add_child(decal)
		_place_crest(visual as Node3D, mount, decal, house > 0)
	var crest := mount.get_node("Crest") as Decal
	crest.texture_albedo = CharacterProfile.crest(house, CharacterProfile.CREST_CARD)
	if crest.has_meta(&"placed"):
		crest.visible = crest.texture_albedo != null


## Puts the patch on the chest of the posed character: on the centre line,
## CREST_OFFSET from the bone in the character's frame (facing -Z), then lets it
## follow the bone.
static func _place_crest(visual: Node3D, mount: BoneAttachment3D, decal: Decal, show: bool) -> void:
	if not mount.is_inside_tree():
		await mount.tree_entered
	for i in 2:
		await mount.get_tree().process_frame
		if not is_instance_valid(decal):
			return
	var frame := visual.global_transform.orthonormalized()
	var at := frame.affine_inverse() * mount.global_position
	at = Vector3(0.0, at.y, at.z) + CREST_OFFSET
	decal.global_transform = Transform3D(frame.basis * Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN), frame * at)
	decal.set_meta(&"placed", true)
	decal.visible = decal.texture_albedo != null


## `node`'s transform in `ancestor`'s space, from local transforms only.
static func _relative(node: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


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

extends SceneTree
## Builds a playable character visual from a Meshy/Mixamo-rigged GLB.
## Run from the project root:
##   godot --headless --path . -s tools/build_character.gd -- apprentice_m
## Reads assets/models/characters/<id>/<id>.glb, sets loop modes in its .import,
## finds jump take-off / landing offsets from the hips curve and writes
## characters/visuals/<id>.tscn (Model + AnimationTree + AnimationController + wand
## bone attachment). Re-run after re-exporting the GLB.

const CLIP_MAP := {
	"idle": ["Idle", "Idle_4", "Standing_Idle"],
	"walk": ["Walking", "Walk"],
	"run": ["Running", "Run", "Jog"],
	"jump": ["Regular_Jump", "Jump"],
	"fall": ["Fall2", "Falling", "Falling_Idle", "Fall"],
	"cast": ["mage_soell_cast_7", "Spell_Cast", "Magic_Attack", "Cast"],
}
const LOOPING := ["idle", "walk", "run", "fall"]
const UPPER_BODY_BONES := ["Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftHandMiddle4",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandMiddle4"]


func _init() -> void:
	var id := "apprentice_m"
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			id = a
	var glb := "res://assets/models/characters/%s/%s.glb" % [id, id]
	var packed := load(glb) as PackedScene
	if packed == null:
		push_error("Cannot load %s (run `godot --headless --path . --import` first)" % glb)
		quit(1)
		return
	var root: Node = packed.instantiate()
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var available := ap.get_animation_list()
	var clips := {}
	for state in CLIP_MAP:
		for candidate in CLIP_MAP[state]:
			if candidate in available:
				clips[state] = candidate
				break
		if not clips.has(state):
			push_error("No clip for state '%s' in %s (have %s)" % [state, glb, available])
			quit(1)
			return
	# Landing = tail of the jump clip, take-off = crouch bottom before the peak.
	var jump: Animation = ap.get_animation(clips["jump"])
	var offsets := _jump_offsets(jump, skeleton)
	clips["land"] = clips["jump"]
	print("clips: ", clips, " jump take-off at %.2f s, landing at %.2f s" % [offsets[0], offsets[1]])

	_patch_import_loops(glb.replace("res://", "") + ".import", clips)
	var skeleton_path := str(root.get_path_to(skeleton))
	var scene_text := _scene_text(id, glb, clips, offsets, skeleton_path)
	var out := "res://characters/visuals/%s.tscn" % id
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(scene_text)
	f.close()
	print("wrote ", out, " (re-import so loop settings apply: godot --headless --path . --import)")
	quit(0)


func _jump_offsets(jump: Animation, skeleton: Skeleton3D) -> Array:
	var track := -1
	for t in range(jump.get_track_count()):
		if str(jump.track_get_path(t)).ends_with("Hips") and jump.track_get_type(t) == Animation.TYPE_POSITION_3D:
			track = t
	if track < 0:
		return [0.0, maxf(0.0, jump.length - 0.5)]
	var rest_y := skeleton.get_bone_rest(skeleton.find_bone("mixamorig_Hips")).origin.y
	var step := 0.02
	var peak_t := 0.0
	var peak_y := -INF
	var t := 0.0
	while t <= jump.length:
		var y: float = jump.position_track_interpolate(track, t).y
		if y > peak_y:
			peak_y = y
			peak_t = t
		t += step
	# take-off: lowest hips before the peak
	var takeoff_t := 0.0
	var min_y := INF
	t = 0.0
	while t < peak_t:
		var y: float = jump.position_track_interpolate(track, t).y
		if y < min_y:
			min_y = y
			takeoff_t = t
		t += step
	# landing: first time after the peak the hips come back down to rest height
	var land_t := jump.length
	t = peak_t
	while t <= jump.length:
		if jump.position_track_interpolate(track, t).y <= rest_y + 0.02:
			land_t = t
			break
		t += step
	return [takeoff_t, land_t]


func _patch_import_loops(import_path: String, clips: Dictionary) -> void:
	var f := FileAccess.open(import_path, FileAccess.READ)
	if f == null:
		push_warning("No .import at %s" % import_path)
		return
	var text := f.get_as_text()
	f.close()
	var anims := {}
	for state in LOOPING:
		anims[clips[state]] = {"settings/loop_mode": 1}
	var sub := {"animations": anims}
	var replacement := "_subresources=" + JSON.stringify(sub)
	var lines := text.split("\n")
	var patched_lines: PackedStringArray = []
	var done := false
	for line in lines:
		if line.begins_with("_subresources="):
			if not done:
				patched_lines.append(replacement)
				done = true
			continue
		patched_lines.append(line)
	if not done:
		patched_lines.append(replacement)
	var patched := "\n".join(patched_lines)
	f = FileAccess.open(import_path, FileAccess.WRITE)
	f.store_string(patched)
	f.close()


func _scene_text(id: String, glb: String, clips: Dictionary, offsets: Array, skeleton_path: String) -> String:
	var states := ["idle", "walk", "run", "jump", "fall", "land"]
	var s := ""
	s += '[gd_scene format=3]\n\n'
	s += '[ext_resource type="PackedScene" path="%s" id="1"]\n' % glb
	s += '[ext_resource type="Script" path="res://characters/components/animation_controller.gd" id="2"]\n\n'
	for st in states + ["cast"]:
		s += '[sub_resource type="AnimationNodeAnimation" id="ANA_%s"]\nanimation = &"%s"\n' % [st, clips[st]]
		if st == "jump":
			s += 'start_offset = %.3f\n' % offsets[0]
		elif st == "land":
			s += 'start_offset = %.3f\n' % offsets[1]
		s += '\n'
	s += '[sub_resource type="AnimationNodeTransition" id="ANT_Movement"]\nxfade_time = 0.18\ninput_count = 6\n'
	for i in range(states.size()):
		s += 'input_%d/name = &"%s"\ninput_%d/auto_advance = false\ninput_%d/break_loop_at_end = false\ninput_%d/reset = true\n' % [i, states[i], i, i, i]
	s += '\n'
	var filters := []
	for b in UPPER_BODY_BONES:
		filters.append('NodePath("%s:mixamorig_%s")' % [skeleton_path, b])
	s += '[sub_resource type="AnimationNodeOneShot" id="ANO_Cast"]\nfilter_enabled = true\nfilters = [%s]\nfadein_time = 0.08\nfadeout_time = 0.2\n\n' % ", ".join(filters)
	s += '[sub_resource type="AnimationNodeBlendTree" id="ANBT_Root"]\n'
	var conns := []
	for i in range(states.size()):
		var node: String = states[i].capitalize()
		s += 'nodes/%s/node = SubResource("ANA_%s")\nnodes/%s/position = Vector2(-500, %d)\n' % [node, states[i], node, i * 120]
		conns.append('&"Movement", %d, &"%s"' % [i, node])
	s += 'nodes/CastAnim/node = SubResource("ANA_cast")\nnodes/CastAnim/position = Vector2(-200, 300)\n'
	s += 'nodes/Movement/node = SubResource("ANT_Movement")\nnodes/Movement/position = Vector2(-200, 0)\n'
	s += 'nodes/Cast/node = SubResource("ANO_Cast")\nnodes/Cast/position = Vector2(100, 0)\n'
	s += 'nodes/output/position = Vector2(350, 0)\n'
	conns += ['&"Cast", 0, &"Movement"', '&"Cast", 1, &"CastAnim"', '&"output", 0, &"Cast"']
	s += 'node_connections = [%s]\n\n' % ", ".join(conns)
	s += '[sub_resource type="StandardMaterial3D" id="Mat_Wand"]\nalbedo_color = Color(0.35, 0.22, 0.12, 1)\n\n'
	s += '[sub_resource type="StandardMaterial3D" id="Mat_Glow"]\nalbedo_color = Color(0.7, 0.55, 1, 1)\nemission_enabled = true\nemission = Color(0.6, 0.45, 1, 1)\nemission_energy_multiplier = 3.0\n\n'
	s += '[sub_resource type="BoxMesh" id="Mesh_Wand"]\nsize = Vector3(0.035, 0.42, 0.035)\n\n'
	s += '[sub_resource type="SphereMesh" id="Mesh_Glow"]\nradius = 0.07\nheight = 0.14\n\n'
	s += '[node name="CharacterVisual" type="Node3D"]\n\n'
	s += '[node name="Model" parent="." instance=ExtResource("1")]\ntransform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)\n\n'
	s += '[node name="AnimationTree" type="AnimationTree" parent="."]\nroot_node = NodePath("../Model")\ntree_root = SubResource("ANBT_Root")\nanim_player = NodePath("../Model/AnimationPlayer")\n'
	s += 'parameters/Movement/current_state = "idle"\nparameters/Movement/transition_request = ""\nparameters/Movement/current_index = 0\nparameters/Cast/active = false\nparameters/Cast/internal_active = false\nparameters/Cast/request = 0\n\n'
	s += '[node name="AnimationController" type="Node" parent="." node_paths=PackedStringArray("animation_tree")]\nscript = ExtResource("2")\nanimation_tree = NodePath("../AnimationTree")\n\n'
	s += '[node name="Wand" type="BoneAttachment3D" parent="."]\nbone_name = "mixamorig_RightHand"\nuse_external_skeleton = true\nexternal_skeleton = NodePath("../Model/%s")\n\n' % skeleton_path
	s += '[node name="WandMesh" type="MeshInstance3D" parent="Wand"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.22, 0.03)\nmesh = SubResource("Mesh_Wand")\nsurface_material_override/0 = SubResource("Mat_Wand")\n\n'
	s += '[node name="Glow" type="MeshInstance3D" parent="Wand"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.44, 0.03)\nvisible = false\nmesh = SubResource("Mesh_Glow")\nsurface_material_override/0 = SubResource("Mat_Glow")\n\n'
	s += '[node name="CastOrigin" type="Marker3D" parent="Wand"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.46, 0.03)\n\n'
	# Off-hand socket for held items (torch…); see HeldItemMount.
	s += '[node name="OffHand" type="BoneAttachment3D" parent="."]\nbone_name = "mixamorig_LeftHand"\nuse_external_skeleton = true\nexternal_skeleton = NodePath("../Model/%s")\n' % skeleton_path
	return s

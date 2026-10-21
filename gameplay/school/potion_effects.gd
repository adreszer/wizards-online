class_name PotionEffects
extends Node3D
## What potions do, for everyone to see (server feature "effects": {name: {effect, until}}),
## and familiars walking with their owners ("familiars": {name: kind}). Glow lights the
## drinker; featherfall slows the local player's falls; a squeaky voice shrinks their
## speech bubbles and raises their spoken incantations (PlayerSounds); robe-dye changes
## their robe colour; confetti bursts once. world.gd adds it.

const GROUP := &"potion_effects"

var effects: Dictionary = {}
var familiars: Dictionary = {}
var _lights: Dictionary = {}
var _pets: Dictionary = {}
var _dyed: Dictionary = {}
var _feather_saved: Array = []


func _ready() -> void:
	add_to_group(GROUP)
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "effects":
			_on_effects(data)
		elif kind == "familiars":
			familiars = data)


func _on_effects(data: Dictionary) -> void:
	for n: String in data:
		var e: Dictionary = data[n]
		if str(e.get("effect", "")) == "confetti" and not effects.has(n):
			var body := _player_named(n)
			if body != null:
				add_child(confetti_burst(body.global_position + Vector3.UP * 2.0))
	effects = data


func _player_named(n: String) -> Node3D:
	if n == NetworkManager.local_display_name:
		return get_tree().get_first_node_in_group(&"local_player") as Node3D
	for p in get_tree().get_nodes_in_group(&"remote_players"):
		if str(p.get("display_name")) == n:
			return p as Node3D
	return null


func effect_of(n: String) -> String:
	var e: Variant = effects.get(n)
	if not e is Dictionary or float((e as Dictionary).get("until", 0)) <= NetworkManager.server_time():
		return ""
	return str((e as Dictionary).get("effect", ""))


static func confetti_burst(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Confetti"
	p.one_shot = true
	p.amount = 80
	p.lifetime = 2.0
	p.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 70.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -4, 0)
	mat.color = Color(1, 0.8, 0.3)
	mat.hue_variation_min = -1.0
	mat.hue_variation_max = 1.0
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	p.draw_pass_1 = quad
	p.position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _process(_delta: float) -> void:
	var players: Array[Node3D] = []
	var me := get_tree().get_first_node_in_group(&"local_player") as Node3D
	if me != null:
		players.append(me)
	for p in get_tree().get_nodes_in_group(&"remote_players"):
		players.append(p as Node3D)
	for body in players:
		var n := str(body.get("display_name"))
		var fx := effect_of(n)
		_glow(body, n, fx == "glow")
		_dye(body, n, fx == "colour")
		if fx == "voice":
			var bubble: SpeechBubble = body.get("speech_bubble")
			if bubble != null and bubble.visible:
				bubble.font_size = 26
				bubble.modulate = Color(1.0, 0.75, 0.95)
		if body == me:
			_featherfall(body, fx == "featherfall")
		_familiar(body, n, str(familiars.get(n, "")))


func _glow(body: Node3D, n: String, on: bool) -> void:
	if on and not _lights.has(n):
		var light := OmniLight3D.new()
		light.name = "PotionGlow"
		light.light_color = Color(0.7, 1.0, 0.75)
		light.light_energy = 1.4
		light.omni_range = 7.0
		light.position = Vector3(0, 1.4, 0)
		body.add_child(light)
		_lights[n] = light
	elif not on and _lights.has(n):
		if is_instance_valid(_lights[n]):
			(_lights[n] as Node).queue_free()
		_lights.erase(n)


func _dye(body: Node3D, n: String, on: bool) -> void:
	if not body.has_method("set_look"):
		return
	if on and not _dyed.has(n):
		var look: Dictionary = (body.get("look") as Dictionary).duplicate()
		_dyed[n] = look.duplicate()
		look.robe = (int(look.get("robe", 0)) + 2) % CharacterLook.ROBE_COLORS.size()
		body.call("set_look", look)
	elif not on and _dyed.has(n):
		body.call("set_look", _dyed[n])
		_dyed.erase(n)


func _featherfall(body: Node3D, on: bool) -> void:
	var movement: PlayerMovement = body.get("movement")
	if movement == null:
		return
	if on and _feather_saved.is_empty():
		_feather_saved = [movement.fall_gravity_multiplier, movement.max_fall_speed]
		movement.fall_gravity_multiplier = 0.25
		movement.max_fall_speed = 3.0
	elif not on and not _feather_saved.is_empty():
		movement.fall_gravity_multiplier = _feather_saved[0]
		movement.max_fall_speed = _feather_saved[1]
		_feather_saved = []


func _familiar(body: Node3D, n: String, kind: String) -> void:
	var pet: Node3D = _pets.get(n)
	if kind == "":
		if pet != null:
			if is_instance_valid(pet):
				pet.queue_free()
			_pets.erase(n)
		return
	if pet == null or not is_instance_valid(pet) or pet.name != "Familiar_" + kind:
		if pet != null and is_instance_valid(pet):
			pet.queue_free()
		pet = GroundsLife.build_creature(kind, GroundsLife.CREATURES.get(kind, Color.WHITE))
		pet.name = "Familiar_" + kind
		pet.get_node("Care").queue_free()
		pet.scale = Vector3.ONE * 0.55
		if pet is Creature:
			(pet as Creature).perched = kind != "glimmerwing"
			(pet as Creature).face_motion = kind == "glimmerwing"
		body.add_child(pet)
		_pets[n] = pet
	var t := Time.get_ticks_msec() / 1000.0
	if kind == "glimmerwing":
		pet.position = Vector3(cos(t) * 0.6, 2.1 + sin(t * 3.0) * 0.1, sin(t) * 0.6)
		return
	# Walkers sit on the left shoulder (the wand hand is the right), riding its animation.
	var shoulder := shoulder_of(body)
	if shoulder != Vector3.INF:
		pet.global_position = shoulder
		pet.global_rotation.y = body.global_rotation.y
	else:
		pet.position = Vector3(0.2, 1.5, 0.0)


## Where a familiar sits on `body`: the top of its left shoulder (just above the upper
## arm's joint), or INF if the body has no such bone.
static func shoulder_of(body: Node3D) -> Vector3:
	var sk := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return Vector3.INF
	var bone := sk.find_bone("mixamorig_LeftArm")
	if bone < 0:
		return Vector3.INF
	var at := sk.global_transform * sk.get_bone_global_pose(bone).origin
	return at + Vector3.UP * 0.06 - (at - body.global_position) * Vector3(0.25, 0.0, 0.25)

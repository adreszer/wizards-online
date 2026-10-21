class_name Creature
extends Node3D
## A magical creature of the paddock (GroundsLife) or a student's familiar (PotionEffects):
## its model (assets/models/creatures/<kind>.glb, from tools/prep_creature.py) moved by
## code, since the models carry no rig. It reads its own motion from how its node moves:
## a mossling hops with a squash on landing, an emberkit bounds, nose dipping; at rest
## they breathe and glance about. A glimmerwing beats its wings (the model's wing_l and
## wing_r turn on their hinges) and bobs. A perched familiar only breathes and glances.

const MODELS := "res://assets/models/creatures/%s.glb"
const FLYING := ["glimmerwing"]
## Hops (or bounds) per second while moving, and how high (m).
const GAIT := {"mossling": [2.6, 0.12], "emberkit": [3.4, 0.07]}

var kind := ""
## On a shoulder: no gait, only breathing and glances.
var perched := false
## Turn to face the way it moves (a familiar circling its owner; the paddock turns its
## creatures itself).
var face_motion := false
## 0..1, how much it is moving now (eased).
var moving := 0.0

var _model: Node3D
var _wings: Array[Node3D] = []
var _last := Vector3.ZERO
var _phase := 0.0
var _time := 0.0
var _glance := 0.0
var _glance_to := 0.0
var _glance_at := 0.0


static func has_model(p_kind: String) -> bool:
	return ResourceLoader.exists(MODELS % p_kind)


## A creature of `kind`, or null when there is no model for it.
static func create(p_kind: String) -> Creature:
	if not has_model(p_kind):
		return null
	var c := Creature.new()
	c.kind = p_kind
	c.name = "Creature_" + p_kind
	var model := (load(MODELS % p_kind) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	# Meshy faces +Z; Godot looks along -Z.
	model.rotation.y = PI
	c.add_child(model)
	c._model = model
	for w in ["wing_l", "wing_r"]:
		var n := model.find_child(w, true, false) as Node3D
		if n != null:
			c._wings.append(n)
	return c


func _ready() -> void:
	_last = global_position
	_glance_at = randf_range(1.0, 4.0)


func _process(delta: float) -> void:
	if _model == null:
		return
	_time += delta
	var step := global_position - _last
	_last = global_position
	var speed := Vector2(step.x, step.z).length() / maxf(delta, 0.0001)
	moving = move_toward(moving, 1.0 if speed > 0.15 and not perched else 0.0, delta * 4.0)
	if face_motion and speed > 0.15:
		var yaw := atan2(-step.x, -step.z)
		global_rotation.y = lerp_angle(global_rotation.y, yaw, 1.0 - exp(-delta * 8.0))
	_glances(delta)
	if kind in FLYING:
		_fly(delta)
	else:
		_walk(delta)


func _walk(delta: float) -> void:
	var gait: Array = GAIT.get(kind, [3.0, 0.08])
	_phase += delta * float(gait[0]) * moving
	var arc := absf(sin(_phase * PI))
	var lift := arc * float(gait[1]) * moving
	# Squash at the bottom of each hop, a little stretch in the air; slow breathing at rest.
	var squash := (1.0 - arc) * 0.14 * moving
	var breath := sin(_time * 2.2) * 0.025 * (1.0 - moving)
	_model.position = Vector3(0, lift, 0)
	_model.scale = Vector3(1.0 + squash * 0.6, 1.0 - squash + breath + arc * 0.05 * moving, 1.0 + squash * 0.6)
	# The emberkit's nose dips and rises with each bound.
	var pitch := sin(_phase * TAU) * 0.12 * moving if kind == "emberkit" else 0.0
	_model.rotation = Vector3(pitch, PI + _glance * (1.0 - moving), 0)


func _fly(_delta: float) -> void:
	var beat := sin(_time * (15.0 if moving > 0.5 else 9.0))
	for w in _wings:
		var side := signf(w.position.x)
		w.rotation = Vector3(0, 0, side * (beat * 0.75 + 0.15))
	_model.position = Vector3(0, sin(_time * 3.0) * 0.03, 0)
	_model.rotation = Vector3(0.08 * moving, PI + _glance * 0.5, sin(_time * 1.3) * 0.06)


## Now and then it turns its head (the whole body, these are small) to look around.
func _glances(delta: float) -> void:
	_glance_at -= delta
	if _glance_at <= 0.0:
		_glance_to = randf_range(-0.6, 0.6) if randf() < 0.7 else 0.0
		_glance_at = randf_range(1.5, 4.5)
	_glance = lerpf(_glance, _glance_to, 1.0 - exp(-delta * 3.0))

class_name Enemy
extends CharacterBody3D
## A basic melee enemy: waits at its post, notices a nearby player, chases,
## strikes, and walks back when the player gets away. Spells damage it through
## its [SpellReceiver]; it dies, shatters and comes back after a while.
##
## Animation is driven straight from the model's AnimationPlayer (one clip per
## state, cross-faded); the clip names are data on this node so another rigged
## model only needs a different mapping. Enemies are local to each client for
## now (like puzzle state); the state machine keeps its inputs (target,
## damage) in one place so a server-driven variant can feed them later.

signal target_acquired(target: Node3D)
signal attacked(target: Node3D, hit: bool)
signal died()
signal respawned()

enum State { IDLE, ALERT, CHASE, ATTACK, RETURN, DEAD }
const STATE_NAMES := ["idle", "alert", "chase", "attack", "return", "dead"]

const LAYER_WORLD := 1 << 0
const LAYER_PLAYER := 1 << 1

@export var name_key: String = "ENEMY_CRYSTAL_GUARDIAN_NAME"
## Players closer than this (with line of sight) wake the enemy up.
@export var detection_range: float = 10.0
## Beyond this distance from its post the enemy gives up and walks back.
@export var leash_range: float = 22.0
## Distance (body to body) at which it stops and swings.
@export var attack_range: float = 2.1
## Half-angle in front of the enemy in which a swing connects.
@export var attack_arc_degrees: float = 60.0
@export var walk_speed: float = 1.8
@export var run_speed: float = 4.2
@export var turn_speed: float = 6.0
@export var attack_damage: int = 20
## Seconds into the attack clip at which the blow lands.
@export var attack_hit_time: float = 1.3
## Seconds the whole swing takes before the next decision.
@export var attack_duration: float = 2.4
## Time spent on the alert reaction before chasing.
@export var alert_duration: float = 1.2
@export var respawn_delay: float = 20.0
## Force spells shove the enemy back a little; everything else just hurts.
@export var knockback_per_strength: float = 0.35
## Damage per spell effect type; types not listed use [member default_spell_damage].
@export var spell_damage: Dictionary = {
	&"force": 20, &"fire": 25, &"frost": 20, &"wind": 15, &"water": 15, &"dark": 15, &"light": 5, &"levitate": 5,
}
@export var default_spell_damage: int = 10
## State name -> clip name in the model's AnimationPlayer.
@export var clips: Dictionary = {
	"idle": "Idle_7", "alert": "Alert", "chase": "Running", "attack": "Attack", "return": "Walking",
}
@export var looping_clips: Array[String] = ["idle", "chase", "return"]
@export var blend_time: float = 0.2

@export var model: Node3D
@export var health: Health
@export var spell_receiver: SpellReceiver
@export var nameplate: Label3D
@export var health_label: Label3D

var state: State = State.IDLE
var target: Node3D
var home_transform: Transform3D
var _home_set: bool = false
var _animation_player: AnimationPlayer
var _state_time: float = 0.0
var _hit_applied: bool = false
var _knockback: Vector3 = Vector3.ZERO
var _flash_tween: Tween
var _mesh_materials: Array[StandardMaterial3D] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	set_meta("health", health)
	set_meta("enemy", self)
	add_to_group("enemies")
	collision_layer = LAYER_WORLD | (1 << 3)  # world (blocks players, camera) + spell target
	collision_mask = LAYER_WORLD | LAYER_PLAYER
	if model != null:
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_animation_player = players[0] as AnimationPlayer
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			for i in range(mi.get_surface_override_material_count()):
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, copy)
					_mesh_materials.append(copy)
	_ensure_loops()
	if health != null:
		health.died.connect(_on_died)
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, health.max_health)
	if spell_receiver != null:
		spell_receiver.spell_received.connect(_on_spell_received)
	if nameplate != null:
		nameplate.text = tr(name_key)
	_enter(State.IDLE)


## The post the enemy guards and returns to. Taken from the transform on the first
## physics tick (so spawners may position the node after adding it) unless set here.
func set_home(xform: Transform3D) -> void:
	home_transform = xform
	_home_set = true


func _ensure_loops() -> void:
	if _animation_player == null:
		return
	for state_name in looping_clips:
		var clip := str(clips.get(state_name, ""))
		if _animation_player.has_animation(clip):
			_animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func state_name() -> String:
	return STATE_NAMES[state]


func _physics_process(delta: float) -> void:
	if not _home_set:
		set_home(global_transform)
	_state_time += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var planar := Vector3.ZERO
	match state:
		State.IDLE:
			_look_for_target()
		State.ALERT:
			_face(target.global_position if is_instance_valid(target) else global_position, delta)
			if _state_time >= alert_duration:
				_enter(State.CHASE)
		State.CHASE:
			planar = _chase(delta)
		State.ATTACK:
			planar = _attack(delta)
		State.RETURN:
			planar = _return(delta)
		State.DEAD:
			pass
	planar += _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	move_and_slide()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_hit_applied = false
	var clip := str(clips.get(state_name(), ""))
	if _animation_player != null and _animation_player.has_animation(clip):
		_animation_player.play(clip, blend_time)


# --- perception ---------------------------------------------------------------------

func _look_for_target() -> void:
	var found := find_target()
	if found != null:
		target = found
		target_acquired.emit(target)
		_enter(State.ALERT)


## Nearest local player within detection range that the enemy can see.
func find_target() -> Node3D:
	var best: Node3D = null
	var best_d := detection_range
	for node in get_tree().get_nodes_in_group("local_player"):
		var body := node as Node3D
		if body == null or not _is_alive(body):
			continue
		var d := global_position.distance_to(body.global_position)
		if d < best_d and _can_see(body):
			best_d = d
			best = body
	return best


func _is_alive(body: Node) -> bool:
	if not body.has_meta("health"):
		return false
	var h := body.get_meta("health") as Health
	return h != null and not h.is_dead


func _can_see(body: Node3D) -> bool:
	var from := global_position + Vector3.UP * 1.5
	var to := body.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD, [get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result["collider"] == body


func _target_lost() -> bool:
	return not is_instance_valid(target) or not _is_alive(target) \
		or home_transform.origin.distance_to(global_position) > leash_range \
		or global_position.distance_to(target.global_position) > leash_range


# --- behaviour ----------------------------------------------------------------------

func _chase(delta: float) -> Vector3:
	if _target_lost():
		target = null
		_enter(State.RETURN)
		return Vector3.ZERO
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= attack_range:
		_enter(State.ATTACK)
		return Vector3.ZERO
	_face(target.global_position, delta)
	return to_target.normalized() * run_speed


func _attack(delta: float) -> Vector3:
	if is_instance_valid(target):
		_face(target.global_position, delta)
	if not _hit_applied and _state_time >= attack_hit_time:
		_hit_applied = true
		var hit := _try_hit()
		attacked.emit(target, hit)
	if _state_time >= attack_duration:
		if _target_lost():
			target = null
			_enter(State.RETURN)
		elif global_position.distance_to(target.global_position) <= attack_range * 1.25:
			_enter(State.ATTACK)
		else:
			_enter(State.CHASE)
	return Vector3.ZERO


func _try_hit() -> bool:
	if not is_instance_valid(target) or not _is_alive(target):
		return false
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > attack_range * 1.25:
		return false
	var forward := -global_basis.z
	if to_target.length() > 0.01 and forward.angle_to(to_target.normalized()) > deg_to_rad(attack_arc_degrees):
		return false
	(target.get_meta("health") as Health).apply_damage(attack_damage, self)
	return true


func _return(delta: float) -> Vector3:
	var found := find_target()
	if found != null and home_transform.origin.distance_to(found.global_position) <= leash_range:
		target = found
		_enter(State.CHASE)
		return Vector3.ZERO
	var to_home := home_transform.origin - global_position
	to_home.y = 0.0
	if to_home.length() < 0.3:
		global_basis = global_basis.slerp(home_transform.basis, 0.2)
		_enter(State.IDLE)
		return Vector3.ZERO
	_face(home_transform.origin, delta)
	return to_home.normalized() * walk_speed


func _face(point: Vector3, delta: float) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, turn_speed * delta))


# --- damage, death, respawn ---------------------------------------------------------

func _on_spell_received(effect: SpellEffect) -> void:
	if state == State.DEAD or health == null:
		return
	var amount := int(spell_damage.get(effect.effect_type, default_spell_damage))
	health.apply_damage(amount, effect.caster)
	if effect.effect_type == &"force" or effect.effect_type == &"wind":
		var shove := effect.direction
		shove.y = 0.0
		_knockback += shove.normalized() * effect.strength * knockback_per_strength
	_flash()
	# Being hit wakes the enemy up even if the caster stood out of detection range.
	if state == State.IDLE or state == State.RETURN:
		var caster := effect.caster as Node3D
		if caster != null and caster.is_in_group("local_player") and _is_alive(caster):
			target = caster
			target_acquired.emit(target)
			_enter(State.ALERT)


func _flash() -> void:
	if _mesh_materials.is_empty():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	for mat in _mesh_materials:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.9, 0.8)
		mat.emission_energy_multiplier = 2.5
		_flash_tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.35)


func _on_health_changed(current: int, maximum: int) -> void:
	if health_label != null:
		health_label.text = "%d / %d" % [current, maximum]


func _on_died(_source: Node) -> void:
	target = null
	_enter(State.DEAD)
	died.emit()
	collision_layer = 0
	collision_mask = 0
	if spell_receiver != null:
		spell_receiver.enabled = false
	if _animation_player != null:
		_animation_player.pause()
	GameEvents.notification_requested.emit(tr("NOTIFY_ENEMY_DEFEATED") % tr(name_key), 3.0)
	var tween := create_tween()
	if model != null:
		tween.tween_property(model, "scale", Vector3(0.05, 0.05, 0.05), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: visible = false)
	if respawn_delay > 0.0:
		tween.tween_interval(respawn_delay)
		tween.tween_callback(respawn)


func respawn() -> void:
	global_transform = home_transform
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	if model != null:
		model.scale = Vector3.ONE
	visible = true
	collision_layer = LAYER_WORLD | (1 << 3)
	collision_mask = LAYER_WORLD | LAYER_PLAYER
	if spell_receiver != null:
		spell_receiver.enabled = true
	if health != null:
		health.restore_full()
	_enter(State.IDLE)
	respawned.emit()

class_name SpellCaster
extends Node3D
## Player component that turns a "cast" intent into a spell projectile.
##
## Aiming uses the centre of the screen (a ray supplied by [member aim_source],
## normally the CameraRig) with a light cone-based aim assist toward nearby
## SpellReceivers. Spell data comes entirely from [SpellDefinition], so new
## spells are new resources rather than new caster code.

signal spell_cast(definition: SpellDefinition, origin: Vector3, direction: Vector3)
signal spell_changed(definition: SpellDefinition)
signal cooldown_started(duration: float)
signal cast_failed(reason: String)

## Node exposing `get_aim_ray() -> {origin, direction}`. Null = aim from this node's forward.
@export var aim_source: Node
## Where projectiles spawn (wand tip). Null = this node.
@export var cast_origin: Node3D
@export var equipped_spell: SpellDefinition
@export var raycast_mask: int = 0b0000_1101  # world | remote_player | spell_target
@export var debug_draw: bool = false

var caster_id: String = ""
var exclude_rids: Array[RID] = []
var cooldown_remaining: float = 0.0
## Diagnostics for the debug overlay.
var current_target: Node
var last_aim_point: Vector3
var last_cast_origin: Vector3
var last_cast_direction: Vector3

var _projectile_parent: Node


func setup(p_exclude_body: CollisionObject3D, p_caster_id: String, p_aim_source: Node, p_cast_origin: Node3D) -> void:
	exclude_rids = [p_exclude_body.get_rid()]
	caster_id = p_caster_id
	aim_source = p_aim_source
	cast_origin = p_cast_origin


func has_spell() -> bool:
	return equipped_spell != null


func learn_spell(definition: SpellDefinition) -> void:
	equipped_spell = definition
	spell_changed.emit(definition)
	GameEvents.spell_learned.emit(definition)


func can_cast() -> bool:
	return equipped_spell != null and cooldown_remaining <= 0.0


func _process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if aim_source != null and equipped_spell != null and is_inside_tree():
		_update_aim()


## Local cast. Returns true when a projectile was launched.
func try_cast() -> bool:
	if equipped_spell == null:
		cast_failed.emit("no_spell")
		return false
	if cooldown_remaining > 0.0:
		cast_failed.emit("cooldown")
		return false
	var aim := _update_aim()
	var origin: Vector3 = _get_cast_origin()
	var direction: Vector3 = (aim["point"] - origin)
	if direction.length_squared() < 0.0001:
		direction = aim["direction"]
	direction = direction.normalized()
	_spawn_projectile(equipped_spell, origin, direction, false)
	cooldown_remaining = equipped_spell.cooldown
	cooldown_started.emit(equipped_spell.cooldown)
	last_cast_origin = origin
	last_cast_direction = direction
	spell_cast.emit(equipped_spell, origin, direction)
	return true


## Cosmetic replay of another player's cast (never affects local puzzle state).
func cast_remote(definition: SpellDefinition, origin: Vector3, direction: Vector3) -> void:
	_spawn_projectile(definition, origin, direction.normalized(), true)
	spell_cast.emit(definition, origin, direction)


func _get_cast_origin() -> Vector3:
	return cast_origin.global_position if cast_origin != null else global_position


## Resolves where the player is aiming. Returns {point, direction, target}.
func _update_aim() -> Dictionary:
	var ray: Dictionary
	if aim_source != null and aim_source.has_method("get_aim_ray"):
		ray = aim_source.get_aim_ray()
	else:
		ray = {"origin": global_position, "direction": -global_transform.basis.z}
	var origin: Vector3 = ray["origin"]
	var dir: Vector3 = (ray["direction"] as Vector3).normalized()
	var spell_range: float = equipped_spell.range if equipped_spell != null else 20.0
	# The camera sits behind the player, so extend the screen ray a bit past the range.
	var ray_length := spell_range + origin.distance_to(_get_cast_origin()) + 1.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * ray_length, raycast_mask, exclude_rids)
	query.collide_with_areas = true
	var result := space.intersect_ray(query)
	var point: Vector3 = origin + dir * ray_length
	var target: Node = null
	if not result.is_empty():
		point = result["position"]
		target = result["collider"]
	# Aim assist: prefer a receiver inside a small cone around the screen ray.
	var assist := _find_assist_target(origin, dir, spell_range)
	if assist != null:
		var assist_point := assist.get_aim_point()
		# Only override if the assisted target is actually reachable from the wand.
		if _has_line_of_sight(_get_cast_origin(), assist_point, assist.get_parent()):
			point = assist_point
			target = assist.get_parent()
	current_target = target
	last_aim_point = point
	return {"point": point, "direction": dir, "target": target}


func _find_assist_target(origin: Vector3, dir: Vector3, spell_range: float) -> SpellReceiver:
	if equipped_spell == null:
		return null
	var max_angle := deg_to_rad(equipped_spell.aim_assist_angle_degrees)
	var best: SpellReceiver = null
	var best_angle := max_angle
	var cast_from := _get_cast_origin()
	for node in get_tree().get_nodes_in_group("spell_receivers"):
		var receiver := node as SpellReceiver
		if receiver == null or not receiver.can_receive(equipped_spell.effect_type):
			continue
		if receiver.get_parent() == get_parent():
			continue
		var p := receiver.get_aim_point()
		if cast_from.distance_to(p) > spell_range:
			continue
		var to_target := p - origin
		if to_target.dot(dir) <= 0.0:
			continue
		var angle := dir.angle_to(to_target)
		if angle < best_angle:
			best_angle = angle
			best = receiver
	return best


func _has_line_of_sight(from: Vector3, to: Vector3, expected: Node) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, raycast_mask, exclude_rids)
	query.collide_with_areas = true
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result["collider"] == expected


func _spawn_projectile(definition: SpellDefinition, origin: Vector3, direction: Vector3, cosmetic: bool) -> void:
	var scene := definition.projectile_scene
	if scene == null:
		push_warning("SpellDefinition %s has no projectile scene" % definition.id)
		return
	var projectile := scene.instantiate() as SpellProjectile
	projectile.configure(definition, direction, get_parent(), caster_id, cosmetic)
	projectile.exclude_rids = exclude_rids
	var parent := _projectile_parent if _projectile_parent != null else get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(projectile)
	projectile.global_position = origin
	if definition.cast_sound != null:
		var player := AudioStreamPlayer3D.new()
		player.stream = definition.cast_sound
		player.unit_size = 6.0
		parent.add_child(player)
		player.global_position = origin
		player.finished.connect(player.queue_free)
		player.play()

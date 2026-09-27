class_name SpellCaster
extends Node3D
## Player component that turns a "cast" intent into a spell projectile.
##
## Aiming uses the centre of the screen (a ray supplied by [member aim_source],
## normally the CameraRig) with a light cone-based aim assist toward nearby
## SpellReceivers. Spell data comes entirely from [SpellDefinition], so new
## spells are new resources rather than new caster code.
##
## The caster is also the character's spellbook: [member known_spells] is
## everything learned so far, [member quick_slots] the ten hotbar slots the
## player switches between with the number keys / cycle actions, and
## [member equipped_spell] the one that fires. Cooldowns are tracked per spell
## with a short global lock so switching spells never dodges a cooldown but
## can never be slower than [constant GLOBAL_COOLDOWN] either.

signal spell_cast(definition: SpellDefinition, origin: Vector3, direction: Vector3)
## The equipped spell changed (learned, selected or cleared).
signal spell_changed(definition: SpellDefinition)
## known_spells or quick_slots changed.
signal spells_changed()
signal cooldown_started(duration: float)
signal cast_failed(reason: String)

const QUICK_SLOT_COUNT := 10
## Minimum time between any two casts, whatever the spells.
const GLOBAL_COOLDOWN := 0.25

## Node exposing `get_aim_ray() -> {origin, direction}`. Null = aim from this node's forward.
@export var aim_source: Node
## Where projectiles spawn (wand tip). Null = this node.
@export var cast_origin: Node3D
@export var equipped_spell: SpellDefinition
@export var raycast_mask: int = 0b0000_1101  # world | remote_player | spell_target
@export var debug_draw: bool = false

var caster_id: String = ""
var exclude_rids: Array[RID] = []
## Every spell this character has learned, in learning order.
var known_spells: Array[SpellDefinition] = []
## Hotbar: index → spell or null. Filled with the first free slot on learning.
var quick_slots: Array[SpellDefinition] = []
## Remaining cooldown of the equipped spell (HUD, debug overlay).
var cooldown_remaining: float:
	get:
		return get_cooldown_remaining(equipped_spell)
## Diagnostics for the debug overlay.
var current_target: Node
var last_aim_point: Vector3
var last_cast_origin: Vector3
var last_cast_direction: Vector3

var _projectile_parent: Node
## spell id → seconds left.
var _cooldowns: Dictionary = {}
var _global_cooldown: float = 0.0


func _init() -> void:
	quick_slots.resize(QUICK_SLOT_COUNT)


func setup(p_exclude_body: CollisionObject3D, p_caster_id: String, p_aim_source: Node, p_cast_origin: Node3D) -> void:
	exclude_rids = [p_exclude_body.get_rid()]
	caster_id = p_caster_id
	aim_source = p_aim_source
	cast_origin = p_cast_origin


func has_spell() -> bool:
	return equipped_spell != null


func knows(id: StringName) -> bool:
	return find_known(id) != null


func find_known(id: StringName) -> SpellDefinition:
	for def in known_spells:
		if def.id == id:
			return def
	return null


## Adds the spell to the spellbook (first free quick slot) and equips it.
## Learning an already known spell just equips it.
func learn_spell(definition: SpellDefinition) -> void:
	if definition == null:
		return
	var known := find_known(definition.id)
	if known == null:
		known_spells.append(definition)
		var slot := quick_slots.find(null)
		if slot >= 0:
			quick_slots[slot] = definition
		spells_changed.emit()
		GameEvents.spell_learned.emit(definition)
	equip(definition)


## Removes a spell (server revoked it, debugging). Clears its slot and, if
## it was equipped, equips the next known spell.
func forget_spell(id: StringName) -> void:
	var def := find_known(id)
	if def == null:
		return
	known_spells.erase(def)
	for i in quick_slots.size():
		if quick_slots[i] == def:
			quick_slots[i] = null
	_cooldowns.erase(String(id))
	spells_changed.emit()
	if equipped_spell == def:
		equip(known_spells.front() if not known_spells.is_empty() else null)


## Makes [param definition] the spell that fires. Must be known (or null).
func equip(definition: SpellDefinition) -> bool:
	if definition != null and find_known(definition.id) == null:
		return false
	if equipped_spell == definition:
		return true
	equipped_spell = definition
	spell_changed.emit(definition)
	return true


## Hotbar selection: slot index 0..QUICK_SLOT_COUNT-1. Empty slots are ignored.
func select_slot(index: int) -> bool:
	if index < 0 or index >= quick_slots.size() or quick_slots[index] == null:
		return false
	return equip(quick_slots[index])


## Index of the equipped spell in the hotbar, -1 if it is not on it.
func equipped_slot() -> int:
	return quick_slots.find(equipped_spell) if equipped_spell != null else -1


## Steps to the next (+1) / previous (-1) occupied slot, wrapping around.
func cycle(step: int) -> bool:
	if step == 0:
		return false
	var occupied: Array[int] = []
	for i in quick_slots.size():
		if quick_slots[i] != null:
			occupied.append(i)
	if occupied.is_empty():
		return false
	var current := occupied.find(equipped_slot())
	var next: int
	if current < 0:
		next = occupied[0] if step > 0 else occupied[-1]
	else:
		next = occupied[posmod(current + signi(step), occupied.size())]
	return select_slot(next)


## Puts a known spell into a slot (null clears it); a spell sits in one slot only.
func assign_slot(index: int, definition: SpellDefinition) -> bool:
	if index < 0 or index >= quick_slots.size():
		return false
	if definition != null and find_known(definition.id) == null:
		return false
	if definition != null:
		var previous := quick_slots.find(definition)
		if previous >= 0:
			quick_slots[previous] = quick_slots[index]
	quick_slots[index] = definition
	spells_changed.emit()
	return true


## Serializable spellbook: {known: [ids], slots: [ids or ""], equipped: id}.
## This is the shape a server-side character record will carry.
func to_state() -> Dictionary:
	var known: Array = []
	for def in known_spells:
		known.append(String(def.id))
	var slots: Array = []
	for def in quick_slots:
		slots.append(String(def.id) if def != null else "")
	return {"known": known, "slots": slots, "equipped": String(equipped_spell.id) if equipped_spell != null else ""}


## Restores a spellbook; unknown ids are dropped (a client only ever holds
## spells that exist locally).
func load_state(state: Dictionary) -> void:
	known_spells.clear()
	quick_slots.fill(null)
	for raw in state.get("known", []):
		var def := SpellRegistry.load_definition(str(raw))
		if def != null and find_known(def.id) == null:
			known_spells.append(def)
	var slots: Array = state.get("slots", [])
	for i in mini(slots.size(), quick_slots.size()):
		var def := find_known(StringName(str(slots[i])))
		if def != null and not quick_slots.has(def):
			quick_slots[i] = def
	# Anything known but not slotted takes the first free slot.
	for def in known_spells:
		if not quick_slots.has(def):
			var free := quick_slots.find(null)
			if free >= 0:
				quick_slots[free] = def
	spells_changed.emit()
	var equipped := find_known(StringName(str(state.get("equipped", ""))))
	if equipped == null and not known_spells.is_empty():
		equipped = known_spells.front()
	equipped_spell = null
	equip(equipped)
	if equipped == null:
		spell_changed.emit(null)


func get_cooldown_remaining(definition: SpellDefinition) -> float:
	if definition == null:
		return 0.0
	return maxf(_global_cooldown, float(_cooldowns.get(String(definition.id), 0.0)))


func can_cast() -> bool:
	return equipped_spell != null and get_cooldown_remaining(equipped_spell) <= 0.0


func _process(delta: float) -> void:
	if _global_cooldown > 0.0:
		_global_cooldown = maxf(0.0, _global_cooldown - delta)
	for id in _cooldowns.keys():
		var left: float = _cooldowns[id] - delta
		if left <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left
	if aim_source != null and equipped_spell != null and is_inside_tree():
		_update_aim()


## Local cast. Returns true when a projectile was launched.
func try_cast() -> bool:
	if equipped_spell == null:
		cast_failed.emit("no_spell")
		return false
	if get_cooldown_remaining(equipped_spell) > 0.0:
		cast_failed.emit("cooldown")
		return false
	var aim := _update_aim()
	var origin: Vector3 = _get_cast_origin()
	var direction: Vector3 = (aim["point"] - origin)
	if direction.length_squared() < 0.0001:
		direction = aim["direction"]
	direction = direction.normalized()
	_spawn_projectile(equipped_spell, origin, direction, false)
	_cooldowns[String(equipped_spell.id)] = equipped_spell.cooldown
	_global_cooldown = GLOBAL_COOLDOWN
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

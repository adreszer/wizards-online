class_name GuardianSync
extends Node
## Online, the dungeon guardians are shared (server feature "guardians"): this reports
## the local player's spell hits on them and applies the server's health, deaths,
## respawns and which guardians are awake (night-only ones stand only during curfew).
## Offline it does nothing and each guardian fights on its own. castle.gd adds this.

const PREFIX := "CrystalGuardian_"

## guardian id -> Enemy
var enemies: Dictionary = {}


func _ready() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		_register(e as Enemy)
	if enemies.is_empty():
		for e in get_parent().find_children(PREFIX + "*", "Enemy", true, false):
			_register(e as Enemy)
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "guardians":
			apply(data))
	apply(NetworkManager.feature("guardians"))


func _register(e: Enemy) -> void:
	if e == null or not str(e.name).begins_with(PREFIX):
		return
	var id := str(e.name).trim_prefix(PREFIX)
	enemies[id] = e
	if e.spell_receiver != null:
		e.spell_receiver.spell_received.connect(func(effect: SpellEffect) -> void: _on_hit(id, effect))


func _on_hit(id: String, effect: SpellEffect) -> void:
	if not NetworkManager.is_in_world() or effect.caster == null or not effect.caster.is_in_group(&"local_player") or effect.definition == null:
		return
	NetworkManager.request("guardian_hit", {"id": id, "spell": str(effect.definition.id)})


## The server's word on every guardian: {id: {hp, max, dead, active}}.
func apply(data: Dictionary) -> void:
	if not NetworkManager.is_in_world():
		return
	for id: String in data:
		var e: Enemy = enemies.get(id)
		var s: Variant = data[id]
		if e == null or not s is Dictionary:
			continue
		e.respawn_delay = 0.0   # the server wakes it
		var active: bool = s.get("active", true)
		e.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if not active:
			e.visible = false
			continue
		if e.state != Enemy.State.DEAD:
			e.visible = true
		var dead: bool = s.get("dead", false)
		if dead and e.state != Enemy.State.DEAD:
			e.health.kill()
		elif not dead and e.state == Enemy.State.DEAD:
			e.respawn()
		elif not dead and e.health != null:
			var hp := int(s.get("hp", e.health.current))
			if hp < e.health.current:
				e.health.apply_damage(e.health.current - hp)
			elif hp > e.health.current:
				e.health.heal(hp - e.health.current)

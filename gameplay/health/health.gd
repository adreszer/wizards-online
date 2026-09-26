class_name Health
extends Node
## Minimal health component. Attach to any node that can be damaged.
##
## Future combat/duel systems talk to this API only; who is allowed to deal
## damage (and server validation) is a concern of the caller.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int, source: Node)
signal died(source: Node)
signal revived()

@export var max_health: int = 100
@export var invulnerable: bool = false

var current: int = 0
var is_dead: bool = false


func _ready() -> void:
	current = max_health
	health_changed.emit(current, max_health)


func apply_damage(amount: int, source: Node = null) -> void:
	if is_dead or invulnerable or amount <= 0:
		return
	current = maxi(0, current - amount)
	damaged.emit(amount, source)
	health_changed.emit(current, max_health)
	if current == 0:
		is_dead = true
		died.emit(source)


func heal(amount: int, source: Node = null) -> void:
	if is_dead or amount <= 0:
		return
	current = mini(max_health, current + amount)
	healed.emit(amount, source)
	health_changed.emit(current, max_health)


func restore_full() -> void:
	var was_dead := is_dead
	is_dead = false
	current = max_health
	health_changed.emit(current, max_health)
	if was_dead:
		revived.emit()


func kill(source: Node = null) -> void:
	if is_dead:
		return
	current = 0
	is_dead = true
	health_changed.emit(current, max_health)
	died.emit(source)

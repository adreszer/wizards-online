class_name DamageZone
extends Area3D
## Deals damage on entry and then periodically while a body stays inside.

@export var damage_on_enter: int = 25
@export var damage_per_tick: int = 15
@export var tick_interval: float = 0.7

var _inside: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if _inside.is_empty():
		return
	_timer += delta
	if _timer >= tick_interval:
		_timer = 0.0
		for health in _inside.values():
			(health as Health).apply_damage(damage_per_tick, self)


func _on_body_entered(body: Node3D) -> void:
	var health: Health = body.get_meta("health", null) as Health if body.has_meta("health") else null
	if health == null:
		return
	_inside[body] = health
	_timer = 0.0
	health.apply_damage(damage_on_enter, self)


func _on_body_exited(body: Node3D) -> void:
	_inside.erase(body)

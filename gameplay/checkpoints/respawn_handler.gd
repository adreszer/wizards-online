class_name RespawnHandler
extends Node
## Player component: remembers the latest checkpoint and respawns the body
## when [Health] reports death or the body falls below [member kill_height].

signal respawned(transform: Transform3D)

@export var body: CharacterBody3D
@export var health: Health
@export var kill_height: float = -20.0
@export var respawn_delay: float = 0.6

var checkpoint_transform: Transform3D
var last_checkpoint: Node
var _respawning: bool = false


func setup(p_body: CharacterBody3D, p_health: Health) -> void:
	body = p_body
	health = p_health
	checkpoint_transform = body.global_transform
	body.set_meta("respawn_handler", self)
	if health != null:
		health.died.connect(_on_died)


func set_checkpoint(xform: Transform3D, checkpoint: Node = null) -> void:
	checkpoint_transform = xform
	last_checkpoint = checkpoint


func _physics_process(_delta: float) -> void:
	if body == null or _respawning:
		return
	if body.global_position.y < kill_height:
		if health != null and not health.is_dead:
			health.kill(self)
		else:
			respawn()


func _on_died(_source: Node) -> void:
	if _respawning:
		return
	_respawning = true
	if respawn_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(respawn_delay).timeout
	respawn()


func respawn() -> void:
	_respawning = false
	if body == null:
		return
	body.velocity = Vector3.ZERO
	body.global_transform = checkpoint_transform
	if health != null:
		health.restore_full()
	respawned.emit(checkpoint_transform)
	GameEvents.player_respawned.emit(body)

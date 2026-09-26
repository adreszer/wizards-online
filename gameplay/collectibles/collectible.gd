class_name Collectible
extends Area3D
## Generic pickup. Registers itself with GameSession for "x / N" totals,
## spins/bobs, and collects on contact with the LOCAL player exactly once.

signal collected(definition: CollectibleDefinition)

@export var definition: CollectibleDefinition
## Stable identifier; empty = derived from the scene path.
@export var instance_key: String = ""
@export var spin_speed: float = 1.6
@export var bob_height: float = 0.15
@export var bob_speed: float = 2.0

var is_collected: bool = false
var _base_y: float = 0.0
var _time: float = randf() * TAU

@onready var _visual: Node3D = $Visual
@onready var _burst: CPUParticles3D = $Burst
@onready var _audio: AudioStreamPlayer3D = $PickupAudio


func _ready() -> void:
	if definition == null:
		push_warning("Collectible without definition at %s" % get_path())
		return
	if instance_key.is_empty():
		instance_key = str(get_path())
	_base_y = _visual.position.y
	_apply_definition()
	GameSession.register_collectible(definition.id)
	body_entered.connect(_on_body_entered)


func _apply_definition() -> void:
	var mesh := _visual.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate()
			mat.albedo_color = definition.color
			mat.emission = definition.color
			mesh.set_surface_override_material(0, mat)
	_burst.color = definition.color
	if definition.pickup_sound != null:
		_audio.stream = definition.pickup_sound


func _process(delta: float) -> void:
	if is_collected:
		return
	_time += delta
	_visual.rotation.y += spin_speed * delta
	_visual.position.y = _base_y + sin(_time * bob_speed) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if is_collected or not body.is_in_group("local_player"):
		return
	try_collect()


func try_collect() -> bool:
	if is_collected:
		return false
	if not GameSession.collect(definition, instance_key):
		return false
	is_collected = true
	set_deferred("monitoring", false)
	_visual.visible = false
	_burst.emitting = true
	if _audio.stream != null:
		_audio.play()
	collected.emit(definition)
	get_tree().create_timer(1.0).timeout.connect(queue_free)
	return true

class_name Collectible
extends Area3D
## Generic pickup. Registers itself with GameSession for "x / N" totals,
## spins/bobs, and collects on contact with the LOCAL player exactly once.
## Online, a castle pickup (with an object_id) is reported to the server
## (fragment_collect, features/fragments.lua), which keeps it on the character;
## the server's "fragments" push on join hides the ones already taken.

signal collected(definition: CollectibleDefinition)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "collectible"

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export var definition: CollectibleDefinition
## Stable identifier; empty = the object id, else derived from the scene path.
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
	# The shards spin every frame: no shadow, or every shadowed light near them re-renders.
	for node in _visual.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if definition == null:
		push_warning("Collectible without definition at %s" % get_path())
		return
	if instance_key.is_empty():
		instance_key = object_id if not object_id.is_empty() else str(get_path())
	_base_y = _visual.position.y
	_apply_definition()
	GameSession.register_collectible(definition.id)
	body_entered.connect(_on_body_entered)
	if not object_id.is_empty():
		NetworkManager.pushed.connect(_on_pushed)
		_on_pushed("fragments", NetworkManager.feature("fragments"))


func _on_pushed(kind: String, data: Dictionary) -> void:
	if kind == "fragments" and object_id in (data.get("ids", []) as Array):
		restore()


## Marks this pickup as taken earlier (by the server's record): counted, gone, silent.
func restore() -> void:
	if is_collected or not GameSession.collect(definition, instance_key, true):
		return
	is_collected = true
	set_deferred("monitoring", false)
	queue_free()


func _apply_definition() -> void:
	# The crystal shards glow in the definition's colour.
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat != null:
				mat = mat.duplicate()
				mat.albedo_color = definition.color
				mat.emission_enabled = true
				mat.emission = definition.color
				mat.emission_energy_multiplier = 1.6
				mesh.set_surface_override_material(i, mat)
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
	if not object_id.is_empty() and NetworkManager.is_in_world():
		NetworkManager.request("fragment_collect", {"o": object_id})
	get_tree().create_timer(1.0).timeout.connect(queue_free)
	return true

class_name BroomRack
extends StaticBody3D
## Wooden stand of school brooms. Interact takes one (a character owns at most
## one of [member item_id]); the stand never runs out. Online the server owns
## the inventory: the request goes up as a world event on this object, the
## server checks the player stands here and sends the new inventory back.

signal taken(by: Node)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "item_rack"
const BROOM_SCENE := preload("res://objects/items/broom.tscn")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""
## ItemRegistry id handed out (exported to the server as the rack's rule setting).
@export var item_id: String = "broom"

@onready var _interactable: Interactable = $Interactable
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	_interactable.prompt_text = "INTERACT_TAKE_BROOM"
	_interactable.interacted.connect(_on_interacted)
	_build_stand()


func _on_interacted(interactor: Node) -> void:
	var inventory := Inventory.find_on(interactor)
	var definition := ItemRegistry.load_definition(item_id)
	if inventory == null or definition == null:
		return
	if inventory.has(definition.id):
		GameEvents.notification_requested.emit(tr("NOTIFY_ALREADY_HAVE_ITEM") % tr(definition.display_name), 4.0)
		return
	if NetworkManager.is_in_world() and not object_id.is_empty():
		# The server adds the item and sends the inventory back (PlayerSpawner applies it).
		NetworkManager.send_world_event(object_id, "interact")
	else:
		inventory.add(definition)
	GameEvents.notification_requested.emit(tr("NOTIFY_BROOM_TAKEN"), 8.0)
	_audio.play()
	taken.emit(interactor)


func _build_stand() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.19, 0.11)
	wood.roughness = 0.7
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 2.0, 0.1)
	var bar := BoxMesh.new()
	bar.size = Vector3(2.0, 0.08, 0.1)
	var base := BoxMesh.new()
	base.size = Vector3(2.0, 0.08, 0.5)
	for x in [-0.95, 0.95]:
		_add_mesh(post, wood, Vector3(x, 1.0, -0.12))
	_add_mesh(bar, wood, Vector3(0, 1.85, -0.12))
	_add_mesh(base, wood, Vector3(0, 0.04, 0))
	# Brooms stand on their twigs, shafts leaning back against the bar.
	for i in 3:
		var broom := BROOM_SCENE.instantiate() as BroomModel
		broom.trail = false
		var upright := Basis(Vector3.RIGHT, PI / 2.0 - 0.1)
		broom.transform = Transform3D(upright, Vector3(-0.6 + 0.6 * i, 1.17, 0.0))
		add_child(broom)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	add_child(mi)

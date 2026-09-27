class_name Player
extends CharacterBody3D
## Composition root for a player character (local or remote).
##
## This script only wires components together. Behaviour lives in:
## PlayerInput, PlayerMovement, CameraRig, AnimationController, SpellCaster,
## InteractionController, Health, RespawnHandler, NetworkSynchronizer, Nameplate,
## Inventory, HeldItemMount.
## Everything under `LocalPlayer` exists only for the locally controlled
## instance and is freed for remote players.

const LAYER_PLAYER := 1 << 1
const LAYER_REMOTE_PLAYER := 1 << 2
const LAYER_WORLD := 1 << 0

## Set BEFORE adding to the tree. Remote players get their transforms from the network.
@export var is_local: bool = true
@export var peer_id: String = ""
@export var display_name: String = "Apprentice"
## CharacterRegistry id. Empty = keep the visual already in the scene.
@export var character_id: String = ""

@onready var movement: PlayerMovement = $Movement
@onready var visual: Node3D = $CharacterVisual
@onready var animation_controller: AnimationController = $CharacterVisual/AnimationController
@onready var spell_caster: SpellCaster = $SpellCaster
@onready var health: Health = $Health
@onready var respawn_handler: RespawnHandler = $RespawnHandler
@onready var synchronizer: NetworkSynchronizer = $NetworkSynchronizer
@onready var nameplate: Nameplate = $Nameplate
@onready var inventory: Inventory = $Inventory
@onready var held_item_mount: HeldItemMount = $HeldItemMount
@onready var local_root: Node = $LocalPlayer
@onready var player_input: PlayerInput = $LocalPlayer/PlayerInput
@onready var camera_rig: CameraRig = $LocalPlayer/CameraRig
@onready var interaction_controller: InteractionController = $LocalPlayer/InteractionController

## Mesh catch-up speed after a step is set per step (distance / stall time); this is the floor.
@export var min_step_catchup_speed: float = 2.0

var cast_origin: Node3D
## World-space offset applied to the mesh so a one-tick step-up reads as a smooth climb.
var _visual_offset: Vector3 = Vector3.ZERO
var _visual_catchup_speed: float = 0.0
## Off-hand socket the held item (torch…) is parented to.
var off_hand: Node3D


func _ready() -> void:
	set_meta("health", health)
	set_meta("player", self)
	_apply_character()
	cast_origin = visual.find_child("CastOrigin", true, false) as Node3D
	off_hand = _find_off_hand()
	held_item_mount.setup(off_hand)
	inventory.held_item_changed.connect(held_item_mount.show_item)
	nameplate.set_display_name(display_name)
	if is_local:
		_setup_local()
	else:
		_setup_remote()


## Replaces the CharacterVisual subtree with the registry scene for character_id.
func _apply_character() -> void:
	if character_id.is_empty() or not CharacterRegistry.is_valid(character_id):
		return
	var scene := CharacterRegistry.load_scene(character_id)
	if scene == null or visual.scene_file_path == scene.resource_path:
		return
	var new_visual := scene.instantiate() as Node3D
	new_visual.name = "CharacterVisual"
	var old := visual
	old.name = "CharacterVisual_old"
	add_child(new_visual)
	move_child(new_visual, old.get_index())
	old.queue_free()
	visual = new_visual
	animation_controller = new_visual.get_node("AnimationController") as AnimationController


func _setup_local() -> void:
	add_to_group("local_player")
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	nameplate.visible = false
	camera_rig.target = self
	movement.setup(self, player_input)
	movement.frame_yaw_provider = camera_rig.get_yaw
	movement.state_changed.connect(animation_controller.set_movement_state)
	movement.stepped.connect(_on_stepped)
	spell_caster.setup(self, peer_id, camera_rig, cast_origin)
	spell_caster.spell_cast.connect(_on_spell_cast)
	interaction_controller.setup(self, camera_rig)
	respawn_handler.setup(self, health)
	synchronizer.setup_local(self)
	camera_rig.activate()
	GameEvents.local_player_spawned.emit(self)


## Every registered body ships an `OffHand` socket; a body without one gets a
## marker at hip height so held items never silently disappear.
func _find_off_hand() -> Node3D:
	var socket := visual.find_child("OffHand", true, false) as Node3D
	if socket == null:
		socket = Marker3D.new()
		socket.name = "OffHand"
		visual.add_child(socket)
		socket.position = Vector3(-0.35, 1.1, -0.1)
	return socket


## Remote players: the held item id arrives from the server, already validated.
func set_remote_held_item(item_id: String) -> void:
	held_item_mount.show_item(ItemRegistry.load_definition(item_id))


func _setup_remote() -> void:
	add_to_group("remote_players")
	collision_layer = LAYER_REMOTE_PLAYER
	collision_mask = 0
	local_root.queue_free()
	movement.set_physics_process(false)
	respawn_handler.set_physics_process(false)
	spell_caster.set_process(false)
	spell_caster.setup(self, peer_id, null, cast_origin)
	spell_caster.spell_cast.connect(_on_spell_cast)
	synchronizer.setup_remote(self)
	synchronizer.movement_state_received.connect(animation_controller.set_movement_state_name)


func _on_stepped(displacement: Vector3, duration: float) -> void:
	_visual_offset -= displacement
	# Constant speed so the mesh walks a straight diagonal onto the tread at walking pace.
	_visual_catchup_speed = maxf(_visual_offset.length() / maxf(duration, 0.01), min_step_catchup_speed)


func _process(delta: float) -> void:
	if not is_local:
		return
	if _visual_offset == Vector3.ZERO:
		return
	_visual_offset = _visual_offset.move_toward(Vector3.ZERO, _visual_catchup_speed * delta)
	# The body yaws with facing, so convert the world offset into its local frame.
	visual.position = global_basis.inverse() * _visual_offset
	camera_rig.follow_offset = _visual_offset
	nameplate.position = Vector3(0.0, 2.25, 0.0) + visual.position


func _physics_process(_delta: float) -> void:
	if not is_local:
		return
	if player_input.consume_cast():
		spell_caster.try_cast()
	if player_input.consume_interact():
		interaction_controller.try_interact()


func _on_spell_cast(_definition: SpellDefinition, _origin: Vector3, _direction: Vector3) -> void:
	animation_controller.play_cast()


func _exit_tree() -> void:
	if is_local:
		GameEvents.local_player_removed.emit(self)

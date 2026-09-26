class_name Player
extends CharacterBody3D
## Composition root for a player character (local or remote).
##
## This script only wires components together. Behaviour lives in:
## PlayerInput, PlayerMovement, CameraRig, AnimationController, SpellCaster,
## InteractionController, Health, RespawnHandler, NetworkSynchronizer, Nameplate.
## Everything under `LocalPlayer` exists only for the locally controlled
## instance and is freed for remote players.

const LAYER_PLAYER := 1 << 1
const LAYER_REMOTE_PLAYER := 1 << 2
const LAYER_WORLD := 1 << 0

## Set BEFORE adding to the tree. Remote players get their transforms from the network.
@export var is_local: bool = true
@export var peer_id: String = ""
@export var display_name: String = "Apprentice"

@onready var movement: PlayerMovement = $Movement
@onready var visual: Node3D = $CharacterVisual
@onready var animation_controller: AnimationController = $CharacterVisual/AnimationController
@onready var spell_caster: SpellCaster = $SpellCaster
@onready var health: Health = $Health
@onready var respawn_handler: RespawnHandler = $RespawnHandler
@onready var synchronizer: NetworkSynchronizer = $NetworkSynchronizer
@onready var nameplate: Nameplate = $Nameplate
@onready var local_root: Node = $LocalPlayer
@onready var player_input: PlayerInput = $LocalPlayer/PlayerInput
@onready var camera_rig: CameraRig = $LocalPlayer/CameraRig
@onready var interaction_controller: InteractionController = $LocalPlayer/InteractionController

var cast_origin: Node3D


func _ready() -> void:
	set_meta("health", health)
	set_meta("player", self)
	cast_origin = visual.get_node_or_null("Arm/Wand/CastOrigin") as Node3D
	nameplate.set_display_name(display_name)
	if is_local:
		_setup_local()
	else:
		_setup_remote()


func _setup_local() -> void:
	add_to_group("local_player")
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	nameplate.visible = false
	camera_rig.target = self
	movement.setup(self, player_input)
	movement.frame_yaw_provider = camera_rig.get_yaw
	movement.state_changed.connect(animation_controller.set_movement_state)
	spell_caster.setup(self, peer_id, camera_rig, cast_origin)
	spell_caster.spell_cast.connect(_on_spell_cast)
	interaction_controller.setup(self, camera_rig)
	respawn_handler.setup(self, health)
	synchronizer.setup_local(self)
	camera_rig.activate()
	GameEvents.local_player_spawned.emit(self)


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

class_name Player
extends CharacterBody3D
## Composition root for a player character (local or remote).
##
## This script only wires components together. Behaviour lives in:
## PlayerInput, PlayerMovement, CameraRig, AnimationController, SpellCaster,
## InteractionController, Health, RespawnHandler, NetworkSynchronizer, Nameplate,
## Inventory, HeldItemMount, BroomRider.
## Everything under `LocalPlayer` exists only for the locally controlled
## instance and is freed for remote players.

const LAYER_PLAYER := 1 << 1
const LAYER_REMOTE_PLAYER := 1 << 2
const LAYER_WORLD := 1 << 0
## Visual (render) layer for character bodies. Lights a character carries leave
## it out of their shadow caster mask: a body 30 cm from its own torch would
## otherwise throw a giant shadow across the room.
const RENDER_LAYER_CHARACTER := 1 << 1

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
@onready var broom_rider: BroomRider = $BroomRider
@onready var local_root: Node = $LocalPlayer
@onready var player_input: PlayerInput = $LocalPlayer/PlayerInput
@onready var camera_rig: CameraRig = $LocalPlayer/CameraRig
@onready var interaction_controller: InteractionController = $LocalPlayer/InteractionController
@onready var area_tracker: AreaTracker = $LocalPlayer/AreaTracker

## Mesh catch-up speed after a step is set per step (distance / stall time); this is the floor.
@export var min_step_catchup_speed: float = 2.0
## A body jump longer than this in one tick is a teleport (respawn, spawn): drawn without interpolation.
@export var teleport_distance: float = 2.0

var cast_origin: Node3D
## Server-decided role (CharacterProfile.ROLE_*); students by default.
var role: String = CharacterProfile.ROLE_STUDENT
var house: int = 0
## World-space offset applied to the mesh so a one-tick step-up reads as a smooth climb.
var _visual_offset: Vector3 = Vector3.ZERO
var _visual_catchup_speed: float = 0.0
## Body transform at the start of the current physics tick. Physics runs at a fixed
## 60 Hz while frames render at the display rate, so between ticks the mesh and the
## camera are drawn at the position interpolated from here to the body's current
## one; without it the body visibly judders whenever it moves across the screen.
var _tick_start: Transform3D
## The mesh's own transform under the body (the interpolation offset is added to it).
var _visual_base: Transform3D
## Off-hand socket the held item (torch…) is parented to.
var off_hand: Node3D
## What this character last said (chat, lectures), over the nameplate.
var speech_bubble: SpeechBubble
## Social gestures and sitting (raise a hand, wave, bow…).
var gestures: Gestures


func _ready() -> void:
	set_meta("health", health)
	set_meta("player", self)
	_apply_character()
	_set_render_layer(visual)
	cast_origin = visual.find_child("CastOrigin", true, false) as Node3D
	off_hand = _find_off_hand()
	held_item_mount.setup(off_hand)
	inventory.held_item_changed.connect(held_item_mount.show_item)
	broom_rider.setup(self, movement, inventory, visual)
	_visual_base = visual.transform
	nameplate.set_display_name(display_name)
	speech_bubble = SpeechBubble.new()
	speech_bubble.name = "SpeechBubble"
	speech_bubble.position = Vector3(0.0, 2.75, 0.0)
	add_child(speech_bubble)
	gestures = Gestures.new()
	gestures.name = "Gestures"
	add_child(gestures)
	gestures.setup(self, visual)
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


func _set_render_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = RENDER_LAYER_CHARACTER
	for child in node.get_children():
		_set_render_layer(child)


func _setup_local() -> void:
	add_to_group("local_player")
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	nameplate.visible = false
	camera_rig.target = self
	movement.setup(self, player_input)
	_tick_start = global_transform
	movement.frame_yaw_provider = camera_rig.get_yaw
	movement.frame_pitch_provider = camera_rig.get_pitch
	movement.state_changed.connect(animation_controller.set_movement_state)
	movement.flying_changed.connect(broom_rider.on_flying_changed)
	movement.flying_changed.connect(_on_flying_changed)
	area_tracker.area_changed.connect(broom_rider.on_area_changed)
	inventory.changed.connect(broom_rider.on_inventory_changed)
	movement.stepped.connect(_on_stepped)
	spell_caster.setup(self, peer_id, camera_rig, cast_origin)
	spell_caster.spell_cast.connect(_on_spell_cast)
	interaction_controller.setup(self, camera_rig)
	respawn_handler.setup(self, health)
	respawn_handler.respawned.connect(func(_at: Transform3D) -> void: broom_rider.dismount())
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


## Sits on the nearest free bench, chair or sofa within reach; false when there is none.
func try_sit() -> bool:
	if not is_local or movement.is_flying or gestures.is_sitting():
		return false
	var others: Array[Vector3] = []
	for other in get_tree().get_nodes_in_group("remote_players"):
		others.append((other as Node3D).global_position)
	var seat: Variant = Seats.nearest_free(get_tree(), global_position, others)
	if seat == null:
		return false
	gestures.sit_at(seat)
	return true


## Whether a free seat is within reach (the HUD offers "[E] Sit").
func seat_nearby() -> bool:
	if not is_local or movement.is_flying or gestures.is_sitting():
		return false
	return Seats.nearest_free(get_tree(), global_position) != null


## Shows a line this character said (mode: say, whisper, shout, lecture) over their head.
func say(text: String, mode: String = "say") -> void:
	speech_bubble.show_line(text, mode)


## Role and house come from the server (own profile or roster); the nameplate
## shows the title.
func set_profile(p_role: String, p_house: int) -> void:
	var previous_house := house
	role = CharacterProfile.sanitize_role(p_role)
	house = CharacterProfile.sanitize_house(p_house)
	nameplate.set_role(role)
	nameplate.set_house(house)
	if is_local and house != previous_house:
		GameEvents.house_changed.emit(house)


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
	synchronizer.mount_received.connect(broom_rider.set_remote_mount)


func _on_stepped(displacement: Vector3, duration: float) -> void:
	_visual_offset -= displacement
	# The step offset already eases the mesh across the jump; don't interpolate it as well.
	_tick_start.origin += displacement
	# Constant speed so the mesh walks a straight diagonal onto the tread at walking pace.
	_visual_catchup_speed = maxf(_visual_offset.length() / maxf(duration, 0.01), min_step_catchup_speed)


func _process(delta: float) -> void:
	if not is_local:
		visual.transform = broom_rider.pose * _visual_base
		return
	if _visual_offset != Vector3.ZERO:
		_visual_offset = _visual_offset.move_toward(Vector3.ZERO, _visual_catchup_speed * delta)
	var fraction := Engine.get_physics_interpolation_fraction()
	var lag := Vector3.ZERO
	var yaw_lag := 0.0
	if _tick_start.origin.distance_to(global_position) < teleport_distance:
		lag = _tick_start.origin.lerp(global_position, fraction) - global_position
		var start_yaw := _tick_start.basis.get_euler().y
		yaw_lag = angle_difference(rotation.y, lerp_angle(start_yaw, rotation.y, fraction))
	var offset := _visual_offset + lag
	# The body yaws with facing, so convert the world offset into its local frame.
	visual.transform = Transform3D(Basis(Vector3.UP, yaw_lag), global_basis.inverse() * offset) * broom_rider.pose * _visual_base
	camera_rig.follow_offset = offset
	camera_rig.speed_ratio = velocity.length() / movement.fly_boost_speed if movement.is_flying else 0.0
	nameplate.position = Vector3(0.0, 2.25, 0.0) + visual.position


func _physics_process(_delta: float) -> void:
	if not is_local:
		return
	# Runs before the Movement child, so this is where the body starts the tick.
	_tick_start = global_transform
	var slot := player_input.consume_spell_slot()
	if slot >= 0:
		spell_caster.select_slot(slot)
	var cycle := player_input.consume_spell_cycle()
	if cycle != 0:
		spell_caster.cycle(cycle)
	if player_input.consume_cast():
		spell_caster.try_cast()
	if gestures.is_sitting():
		# Moving or jumping stands up.
		if player_input.move_axis.length() > 0.3 or player_input.consume_jump():
			gestures.stand()
	elif gestures.current == &"notes" and player_input.move_axis.length() > 0.3:
		gestures.stop()
	var gesture := player_input.consume_gesture()
	if gesture != &"":
		gestures.play(gesture)
	if player_input.consume_interact():
		if gestures.is_sitting():
			gestures.stand()
		elif not interaction_controller.try_interact():
			try_sit()
	if player_input.consume_mount():
		broom_rider.toggle()


func _on_flying_changed(is_flying: bool) -> void:
	camera_rig.set_flight_mode(is_flying)
	if is_flying:
		GameEvents.notification_requested.emit(tr("NOTIFY_FLIGHT_CONTROLS"), 7.0)


func _on_spell_cast(_definition: SpellDefinition, _origin: Vector3, _direction: Vector3) -> void:
	animation_controller.play_cast()
	broom_rider.on_cast()


func _exit_tree() -> void:
	if is_local:
		GameEvents.local_player_removed.emit(self)

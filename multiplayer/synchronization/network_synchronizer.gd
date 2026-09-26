class_name NetworkSynchronizer
extends Node
## Player component bridging a Player and the NetworkManager.
##
## Local: samples the body at [member send_rate] Hz and hands snapshots +
## spell casts to NetworkManager. Remote: buffers received snapshots and
## interpolates the body toward them (never teleports between updates).
## Gameplay code never touches Nakama; this node is the only bridge.

signal movement_state_received(state_name: String)

@export var send_rate: float = float(ProjectSettings.get_setting("game/network/state_send_rate", 12.0))
## How far behind the newest snapshot remote bodies are rendered (seconds).
@export var interpolation_delay: float = 0.12
## If a remote snapshot is farther than this, snap instead of gliding (respawn/teleport).
@export var snap_distance: float = 6.0

var player: Node
var is_local: bool = false
var _send_accumulator: float = 0.0
var _last_sent_state: String = ""
var _buffer: Array[Dictionary] = []
var _remote_state_name: String = "idle"
var _last_received_time: float = 0.0


func setup_local(p_player: Node) -> void:
	player = p_player
	is_local = true
	if not NetworkManager.is_online():
		set_physics_process(false)
		return
	var caster: SpellCaster = player.spell_caster
	caster.spell_cast.connect(_on_local_spell_cast)
	var inventory: Inventory = player.inventory
	inventory.held_item_changed.connect(_on_local_held_item_changed)


func setup_remote(p_player: Node) -> void:
	player = p_player
	is_local = false


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if is_local:
		_tick_local(delta)
	else:
		_tick_remote(delta)


# --- Local ---------------------------------------------------------------------

func _tick_local(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	_send_accumulator += delta
	if _send_accumulator < 1.0 / send_rate:
		return
	_send_accumulator = 0.0
	var body := player as CharacterBody3D
	var movement: PlayerMovement = player.movement
	NetworkManager.send_player_state({
		"p": [snappedf(body.global_position.x, 0.001), snappedf(body.global_position.y, 0.001), snappedf(body.global_position.z, 0.001)],
		"y": snappedf(body.rotation.y, 0.001),
		"v": [snappedf(body.velocity.x, 0.01), snappedf(body.velocity.y, 0.01), snappedf(body.velocity.z, 0.01)],
		"s": movement.get_state_name(),
		"g": movement.is_grounded,
	})


func _on_local_spell_cast(definition: SpellDefinition, origin: Vector3, direction: Vector3) -> void:
	NetworkManager.send_spell_cast({
		"id": String(definition.id),
		"o": [origin.x, origin.y, origin.z],
		"d": [direction.x, direction.y, direction.z],
	})


func _on_local_held_item_changed(definition: ItemDefinition) -> void:
	NetworkManager.send_held_item(String(definition.id) if definition != null else "")


# --- Remote --------------------------------------------------------------------

## Called by the PlayerSpawner when a state message arrives for this player.
func receive_state(state: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var p: Array = state.get("p", [0, 0, 0])
	var v: Array = state.get("v", [0, 0, 0])
	var snapshot := {
		"t": now,
		"pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
		"yaw": float(state.get("y", 0.0)),
		"vel": Vector3(float(v[0]), float(v[1]), float(v[2])),
		"state": str(state.get("s", "idle")),
	}
	_buffer.append(snapshot)
	_last_received_time = now
	while _buffer.size() > 20:
		_buffer.pop_front()
	var body := player as Node3D
	# First snapshot or a large jump (respawn): snap immediately.
	if _buffer.size() == 1 or body.global_position.distance_to(snapshot["pos"]) > snap_distance:
		body.global_position = snapshot["pos"]
		body.rotation.y = snapshot["yaw"]
	if snapshot["state"] != _remote_state_name:
		_remote_state_name = snapshot["state"]
		movement_state_received.emit(_remote_state_name)


func receive_spell_cast(definition: SpellDefinition, origin: Vector3, direction: Vector3) -> void:
	var caster: SpellCaster = player.spell_caster
	caster.cast_remote(definition, origin, direction)


func receive_held_item(item_id: String) -> void:
	player.set_remote_held_item(item_id)


func _tick_remote(delta: float) -> void:
	if _buffer.is_empty():
		return
	var body := player as Node3D
	var render_time := Time.get_ticks_msec() / 1000.0 - interpolation_delay
	# Find the two snapshots surrounding render_time.
	var older: Dictionary = {}
	var newer: Dictionary = {}
	for i in range(_buffer.size() - 1, -1, -1):
		if _buffer[i]["t"] <= render_time:
			older = _buffer[i]
			if i + 1 < _buffer.size():
				newer = _buffer[i + 1]
			break
	var target_pos: Vector3
	var target_yaw: float
	if older.is_empty():
		# We're behind the oldest snapshot: ease toward it.
		target_pos = _buffer[0]["pos"]
		target_yaw = _buffer[0]["yaw"]
	elif newer.is_empty():
		# Beyond the newest snapshot: extrapolate briefly using velocity, then hold.
		var age: float = clampf(render_time - older["t"], 0.0, 0.25)
		target_pos = older["pos"] + older["vel"] * age
		target_yaw = older["yaw"]
	else:
		var span: float = maxf(0.0001, newer["t"] - older["t"])
		var f: float = clampf((render_time - older["t"]) / span, 0.0, 1.0)
		target_pos = (older["pos"] as Vector3).lerp(newer["pos"], f)
		target_yaw = lerp_angle(older["yaw"], newer["yaw"], f)
	var t := 1.0 - exp(-18.0 * delta)
	body.global_position = body.global_position.lerp(target_pos, t)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, t)
	# Drop snapshots that are no longer needed.
	while _buffer.size() > 2 and _buffer[1]["t"] < render_time:
		_buffer.pop_front()

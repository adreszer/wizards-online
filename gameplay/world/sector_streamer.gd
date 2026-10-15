class_name SectorStreamer
extends Node
## Keeps the castle's per-frame work local. Everything that animates every frame
## (candle and torch flames, chandelier and torch flicker, tomes, collectibles…) is
## bucketed into [member cell_size] cells; cells farther than [member active_radius]
## from the camera have their nodes' processing paused, nearer cells run normally.
## Drawing is handled elsewhere (StaticBatch cells, CastleExterior's far view and
## detail ranges, occlusion culling), so a paused cell is also one nobody can see up
## close. Server-driven changes (a torch relit, a door opened) still apply while paused:
## they are method calls, not processing.

const CONTAINERS := ["Torches", "Lights", "Tomes", "Collectibles", "Props", "Puzzles", "Checkpoints"]

@export var cell_size: float = 32.0
@export var active_radius: float = 90.0
@export var interval: float = 0.25

var _cells: Dictionary = {}     # Vector3i -> Array[Node]
var _active: Dictionary = {}    # Vector3i -> bool
var _timer := 0.0
var cells_active := 0


func _ready() -> void:
	_index.call_deferred()


func _index() -> void:
	var castle := get_parent()
	for c in CONTAINERS:
		var container := castle.get_node_or_null(c)
		if container == null:
			continue
		for child in container.get_children():
			if child is Node3D:
				var p := (child as Node3D).global_position
				var key := Vector3i(floori(p.x / cell_size), floori(p.y / cell_size), floori(p.z / cell_size))
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(child)
	for key in _cells:
		_active[key] = true
	_update(true)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	_update(false)


func _update(force: bool) -> void:
	var focus := _focus()
	if focus == Vector3.INF:
		return
	var n := 0
	for key: Vector3i in _cells:
		var centre := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * cell_size
		var want := centre.distance_to(focus) < active_radius + cell_size * 0.87
		if want:
			n += 1
		if force or want != _active[key]:
			_active[key] = want
			for node in _cells[key]:
				# Picked-up collectibles and spent objects are freed: skip them.
				if is_instance_valid(node):
					(node as Node).process_mode = Node.PROCESS_MODE_INHERIT if want else Node.PROCESS_MODE_DISABLED
	cells_active = n


func _focus() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		return cam.global_position
	var players := get_tree().get_nodes_in_group("local_player")
	return (players[0] as Node3D).global_position if not players.is_empty() else Vector3.INF

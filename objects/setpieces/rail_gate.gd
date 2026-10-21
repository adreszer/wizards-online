class_name RailGate
extends Node3D
## A length of landing parapet that sinks out of the way while a shifting stair rests
## against it (stop `open_stop` of the stair at `stair`), and rises again before the
## stair swings away, so nobody walks off into the shaft. Iron grinds as it moves.

const MOVE_SOUND := preload("res://assets/audio/world/rail_gate_move.wav")

@export var stair: NodePath
@export var open_stop: int = 0
@export var length: float = 4.0

var _rail: Railing
var _stair: ShiftingStair
var is_open := false
## The first frame takes the state the world is already in, silently.
var _first := true


func _ready() -> void:
	_rail = Railing.new()
	_rail.length = length
	add_child(_rail)
	_stair = get_node_or_null(stair) as ShiftingStair


func _physics_process(_delta: float) -> void:
	if _stair == null:
		return
	var want := _stair.stop_at(_stair.now()) == open_stop
	if want != is_open:
		is_open = want
		if not _first:
			Sfx.play_at(self, MOVE_SOUND, -4.0, 25.0, Vector3(0, 0.5, 0))
		_rail.position.y = -1.4 if want else 0.0
		_rail.process_mode = Node.PROCESS_MODE_INHERIT
		for c in _rail.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = want
	_first = false

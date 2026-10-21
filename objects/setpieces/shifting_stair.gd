class_name ShiftingStair
extends ScheduledMover
## A flight of stone steps hinged at its foot (the origin) that swings between landings on
## the world's schedule. Each entry of `stops` is a heading (yaw degrees) at which its top
## step meets a landing a storey up; rail gates on those landings open only while it rests
## there (RailGate). Built from the same steps as Staircase. The stone grinds while it
## swings and booms as it locks against a landing.

const SWING_SOUND := preload("res://assets/audio/world/shifting_stair_move_loop.wav")
const SETTLE_SOUND := preload("res://assets/audio/world/shifting_stair_settle.wav")

@export var rise: float = 9.0
@export var run: float = 12.0
@export var width: float = 3.2

var _swing: AudioStreamPlayer3D


func _ready() -> void:
	Staircase.build_steps(self, rise, run, width, 0.36, 1.0, "stair_generated")
	# Iron cheeks along both sides so nobody steps off mid-swing.
	for side in [-1.0, 1.0]:
		var cheek := Railing.new()
		cheek.length = run
		cheek.rise = rise
		cheek.height = 1.0
		cheek.thickness = 0.2
		cheek.position = Vector3(0, 0, side * (width / 2.0 + 0.1))
		add_child(cheek)
	_swing = Sfx.loop_player(self, "Swing", SWING_SOUND, 0.0, 50.0)
	_swing.position = Vector3(run / 2.0, rise / 2.0, 0)
	swing_started.connect(func() -> void: Sfx.start_loop(_swing))
	stop_reached.connect(func(_index: int) -> void:
		if _swing.playing:
			_swing.stop()
			Sfx.play_at(self, SETTLE_SOUND, 0.0, 50.0, Vector3(run, rise, 0)))
	super._ready()

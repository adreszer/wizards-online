class_name ShiftingStair
extends ScheduledMover
## A flight of stone steps hinged at its foot (the origin) that swings between landings on
## the world's schedule. Each entry of `stops` is a heading (yaw degrees) at which its top
## step meets a landing a storey up; rail gates on those landings open only while it rests
## there (RailGate). Built from the same steps as Staircase.

@export var rise: float = 9.0
@export var run: float = 12.0
@export var width: float = 3.2


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
	super._ready()

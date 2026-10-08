class_name Chandelier
extends Node3D
## Ceiling chandelier: model hung from the node origin (the ceiling attachment)
## plus a gently flickering OmniLight at the candles. Lights have a deliberate
## radius: a room is lit by a few pools of candlelight, not evenly.

@export var base_energy: float = 4.0
@export var flicker_amount: float = 0.12
@export var flicker_speed: float = 6.0
## Length of the iron rod from the ceiling to the chandelier's hook; tall halls use a
## longer drop so the candles still hang about 4 m above the floor.
@export var drop: float = 2.0

@onready var _light: OmniLight3D = $Candles
var _phase: float = randf() * TAU


func _ready() -> void:
	var rod: MeshInstance3D = $Rod
	var rod_mesh: CylinderMesh = rod.mesh.duplicate()
	rod_mesh.height = drop
	rod.mesh = rod_mesh
	rod.position.y = -drop / 2.0
	$Model.position.y = -(drop + 0.95)
	_light.position.y = -(drop + 1.3)   # at candle height


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)

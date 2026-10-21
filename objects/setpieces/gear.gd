class_name Gear
extends ScheduledMover
## A spinning clockwork platform (a toothed bronze disc) to jump across. Its teeth
## creak and tick as it turns.

const TURN_SOUND := preload("res://assets/audio/world/gear_loop.wav")

@export var radius: float = 1.8


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.35
	cyl.radial_segments = 24
	mesh.mesh = cyl
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.62, 0.45, 0.22)
	bronze.metallic = 0.8
	bronze.roughness = 0.35
	mesh.material_override = bronze
	add_child(mesh)
	for i in range(12):
		var tooth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.3, 0.4)
		tooth.mesh = box
		tooth.material_override = bronze
		var a := TAU * i / 12.0
		tooth.position = Vector3(cos(a), 0, sin(a)) * (radius + 0.2)
		tooth.rotation.y = -a
		add_child(tooth)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.35
	cs.shape = shape
	add_child(cs)
	Sfx.start_loop(Sfx.loop_player(self, "Turning", TURN_SOUND, -8.0, 18.0))
	super._ready()

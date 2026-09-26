extends Node3D
## The castle world. Geometry comes from tools/generate_castle.py; this script
## only wires generic reactions (secrets, checkpoints). Rooms are AreaZones
## (see gameplay/world/area_zone.gd) that other systems key off.


func _ready() -> void:
	for wall in get_tree().get_nodes_in_group("secret_walls"):
		if wall is SecretWall:
			(wall as SecretWall).revealed.connect(func() -> void: GameEvents.notification_requested.emit(tr("NOTIFY_SECRET_PASSAGE"), 4.0))
	GameEvents.checkpoint_activated.connect(func(_c: Node) -> void: GameEvents.notification_requested.emit(tr("NOTIFY_CHECKPOINT"), 2.0))


## All named areas of the castle, for tests, tooling and future server-side maps.
func get_zones() -> Array[AreaZone]:
	var out: Array[AreaZone] = []
	for child in $Zones.get_children():
		if child is AreaZone:
			out.append(child)
	return out

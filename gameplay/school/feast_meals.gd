class_name FeastMeals
extends Node
## Meals in the great hall. Breakfast, lunch and dinner follow the school clock
## (SchoolClock hours, the same on every client, so nothing is sent): while a meal is
## served the feast tables carry plates, goblets, platters, bread and fruit, the castle
## is told dinner is served, and anyone seated at a feast bench eats (the "eat" arm
## gesture, seen by everyone through the movement snapshot). Feast tables are batched,
## so StaticBatch records where they stand. castle.gd adds it.

const FEAST_TABLE := "res://objects/environment/props/feast_table.tscn"
## [start hour, end hour, translation key] in school time.
const MEALS := [[7.0, 8.5, "MEAL_BREAKFAST"], [12.0, 13.5, "MEAL_LUNCH"], [18.5, 20.0, "MEAL_DINNER"]]
const TABLE_LENGTH := 5.7
const TABLE_TOP := 0.79
const SEAT_PITCH := 0.95
## A seated player this close (metres, flat) to a table's centre line eats.
const EAT_REACH := 1.2

## The meal being served ("" = none): its translation key.
var serving: String = ""
var tables: Array[Transform3D] = []
var _dishes: Array[MultiMeshInstance3D] = []
var _timer := 0.0


static func meal_at(hours: float) -> String:
	var h := fposmod(hours, 24.0)
	for m: Array in MEALS:
		if h >= float(m[0]) and h < float(m[1]):
			return str(m[2])
	return ""


func _ready() -> void:
	for batch in get_tree().get_nodes_in_group(StaticBatch.GROUP):
		tables.append_array((batch as StaticBatch).feast_tables)
	if not tables.is_empty():
		_build_dishes()
	update(true)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		update(false)


## Serves or clears the tables for the current school hour; seats the eaters.
func update(quiet: bool) -> void:
	# The day/night cycle's hour (it honours time_override in tools and tests).
	var cycle := get_parent().get_node_or_null("DayNightCycle") as DayNightCycle
	var meal := meal_at(cycle.hours if cycle != null else NetworkManager.school_hours())
	if meal != serving:
		serving = meal
		for mm in _dishes:
			mm.visible = serving != ""
		if serving != "" and not quiet and not tables.is_empty():
			GameEvents.notification_requested.emit(tr("MEAL_SERVED") % tr(serving), 5.0)
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player != null:
		_feed(player)


## A local player seated at a feast table eats while a meal is served, and stops after.
func _feed(player: Player) -> void:
	var g := player.gestures
	var at_table := g.is_sitting() and near_table(player.global_position)
	if serving != "" and at_table and g.current == &"":
		g.play(&"eat")
	elif g.current == &"eat" and (serving == "" or not at_table):
		g.play(&"eat")   # toggles it off


func near_table(p: Vector3) -> bool:
	for t in tables:
		var local := t.affine_inverse() * p
		if absf(local.x) <= TABLE_LENGTH / 2.0 + 0.3 and absf(local.z) <= EAT_REACH and absf(local.y) < 1.5:
			return true
	return false


## One MultiMesh per dish kind over every table: plates and goblets at each place on both
## long sides, and down the middle platters, bread and fruit bowls.
func _build_dishes() -> void:
	var places: Array[Transform3D] = []
	var middles: Array[Transform3D] = []
	for t in tables:
		var n := int(TABLE_LENGTH / SEAT_PITCH)
		for i in n:
			var x := -TABLE_LENGTH / 2.0 + SEAT_PITCH * (i + 0.5)
			for side in [-1.0, 1.0]:
				places.append(t * Transform3D(Basis(Vector3.UP, side * PI / 2.0 + PI / 2.0), Vector3(x, TABLE_TOP, side * 0.22)))
			if i % 2 == 0:
				middles.append(t * Transform3D(Basis(Vector3.UP, float(i) * 0.7), Vector3(x + SEAT_PITCH * 0.5, TABLE_TOP, 0.0)))
	var plate := _cylinder(0.12, 0.015)
	_add("Plates", plate, Color(0.86, 0.84, 0.78), places, Vector3.ZERO)
	_add("Food", _dome(0.07, 0.04), Color(0.62, 0.36, 0.18), places, Vector3(0, 0.015, 0))
	_add("Goblets", _cylinder(0.035, 0.12), Color(0.75, 0.6, 0.28), places, Vector3(0.16, 0.0, -0.08), 0.6)
	_add("Platters", _cylinder(0.2, 0.03), Color(0.7, 0.68, 0.64), middles, Vector3.ZERO, 0.4)
	_add("Roasts", _dome(0.14, 0.1), Color(0.55, 0.28, 0.12), middles, Vector3(0, 0.03, 0))
	_add("Bread", _dome(0.09, 0.07), Color(0.82, 0.6, 0.32), middles, Vector3(0.32, 0.0, 0.05))
	_add("Fruit", _dome(0.08, 0.08), Color(0.78, 0.2, 0.15), middles, Vector3(-0.32, 0.0, -0.04))


func _add(node_name: String, mesh: Mesh, color: Color, xforms: Array[Transform3D], offset: Vector3, metal: float = 0.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = metal
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] * Transform3D(Basis.IDENTITY, offset))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_end = 60.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	_dishes.append(mmi)


static func _cylinder(radius: float, height: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius * 0.9
	m.height = height
	m.radial_segments = 16
	m.rings = 1
	var arr := ArrayMesh.new()
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _lifted(m.get_mesh_arrays(), height / 2.0))
	return arr


static func _dome(radius: float, height: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height * 2.0
	m.is_hemisphere = true
	m.radial_segments = 14
	m.rings = 5
	var arr := ArrayMesh.new()
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.get_mesh_arrays())
	return arr


## Mesh arrays moved up so the shape stands on y = 0.
static func _lifted(arrays: Array, dy: float) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += dy
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays

@tool
class_name SpiralStaircase
extends StaticBody3D
## Newel stair for a square stair turret: wedge steps wind around a central
## column and reach out to the turret's walls (no gaps to fall through in the
## corners). Origin is the column's foot at floor level. Each turn climbs
## [member rise_per_turn] (one storey) over [member steps_per_turn] sectors, so
## every storey's doorway sits at the same angle: the last [member landing_steps]
## sectors of each turn are one level landing in front of that storey's doorway
## (no doorway opens straight onto a step), and the first step up starts at
## [member start_angle_degrees].
## Angles are measured in the XZ plane from +X toward +Z. Children are generated
## and never saved; tools/castle (circulation.py) computes the same geometry.

@export var turns: float = 1.0:
	set(value):
		turns = maxf(0.05, value)
		_rebuild()
@export var rise_per_turn: float = 9.0:
	set(value):
		rise_per_turn = maxf(0.5, value)
		_rebuild()
@export var steps_per_turn: int = 25:
	set(value):
		steps_per_turn = maxi(4, value)
		_rebuild()
## Sectors of each turn spent on the level landing before the doorway (0: none).
@export var landing_steps: int = 0:
	set(value):
		landing_steps = maxi(0, value)
		_rebuild()
## Half the inner width of the square turret: steps reach out to this square.
@export var half_size: float = 3.8:
	set(value):
		half_size = maxf(0.5, value)
		_rebuild()
@export var column_radius: float = 0.5:
	set(value):
		column_radius = maxf(0.05, value)
		_rebuild()
@export var start_angle_degrees: float = 0.0:
	set(value):
		start_angle_degrees = value
		_rebuild()
## A lantern on the newel every turn, halfway up (stair turrets get no torches).
@export var lanterns: bool = true:
	set(value):
		lanterns = value
		_rebuild()
## Depth of stone under each tread.
@export var slab_thickness: float = 0.6:
	set(value):
		slab_thickness = maxf(0.05, value)
		_rebuild()

const STONE_MATERIAL: StandardMaterial3D = preload("res://assets/materials/greybox_stone.tres")

static var _two_sided: StandardMaterial3D


## The shared stone, drawn from both sides (generated faces, no winding to get wrong).
static func stone() -> StandardMaterial3D:
	if _two_sided == null:
		_two_sided = STONE_MATERIAL.duplicate()
		_two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _two_sided


func _ready() -> void:
	_rebuild()


func step_count() -> int:
	return int(round(turns * steps_per_turn))


func rising_steps() -> int:
	return maxi(1, steps_per_turn - landing_steps)


func riser() -> float:
	return rise_per_turn / rising_steps()


## Top of sector `step_index` counted from the first step up (landings included); used by
## tests to walk the stair.
func tread_height_at(step_index: int) -> float:
	var turn := floori(float(step_index) / steps_per_turn)
	var k := step_index % steps_per_turn
	return turn * rise_per_turn + minf(k + 1, rising_steps()) * riser()


## The angle (radians) in the middle of the doorway landings.
func landing_angle() -> float:
	return deg_to_rad(start_angle_degrees) - landing_steps * TAU / steps_per_turn / 2.0


func _ray_to_square(angle: float) -> Vector2:
	var d := Vector2(cos(angle), sin(angle))
	var t := half_size / maxf(absf(d.x), absf(d.y))
	return d * t


func _step_outline(a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(cos(a0), sin(a0)) * column_radius)
	pts.append(_ray_to_square(a0))
	# Square corners strictly inside the step's angle range.
	for k in range(8):
		var corner_angle := PI / 4.0 + k * PI / 2.0 - TAU * 2.0
		while corner_angle < a0:
			corner_angle += TAU
		if corner_angle < a1:
			pts.append(Vector2(cos(corner_angle), sin(corner_angle)) * half_size * sqrt(2.0))
			break
	pts.append(_ray_to_square(a1))
	pts.append(Vector2(cos(a1), sin(a1)) * column_radius)
	return pts


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("stair_generated"):
			remove_child(child)
			child.queue_free()
	var n := step_count()
	var da := TAU / steps_per_turn
	var a_start := deg_to_rad(start_angle_degrees)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var k := i % steps_per_turn
		if k > rising_steps():
			continue   # drawn as one piece with the landing's first sector
		var a0 := a_start + i * da
		var a1 := a0 + da * (landing_steps if k == rising_steps() else 1)
		var outline := _step_outline(a0, a1)
		if k == rising_steps() and landing_steps * da > PI / 2.0:
			# A landing wider than a quarter turn: split so each outline stays convex.
			_add_tread(st, _step_outline(a0, (a0 + a1) / 2.0), tread_height_at(i))
			outline = _step_outline((a0 + a1) / 2.0, a1)
		_add_tread(st, outline, tread_height_at(i))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = stone()
	mesh.set_meta("stair_generated", true)
	add_child(mesh)
	# The newel: a column through the whole flight.
	var total := turns * rise_per_turn + 1.0
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = column_radius
	cyl.bottom_radius = column_radius
	cyl.height = total
	column.mesh = cyl
	column.material_override = STONE_MATERIAL
	column.position = Vector3(0, total / 2.0, 0)
	column.set_meta("stair_generated", true)
	add_child(column)
	var column_shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = column_radius
	cyl_shape.height = total
	column_shape.shape = cyl_shape
	column_shape.position = column.position
	column_shape.set_meta("stair_generated", true)
	add_child(column_shape)
	if lanterns:
		for k in range(int(ceil(turns))):
			_add_lantern(k * rise_per_turn + rise_per_turn * 0.55, a_start + PI + k * 0.0)


func _add_tread(st: SurfaceTool, outline: PackedVector2Array, top: float) -> void:
	var bottom := maxf(0.0, top - slab_thickness)
	var points := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x, top, p.y))
	for p in outline:
		points.append(Vector3(p.x, bottom, p.y))
	_add_prism(st, outline, top, bottom)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	shape.set_meta("stair_generated", true)
	add_child(shape)


func _add_lantern(height: float, angle: float) -> void:
	var lamp := Node3D.new()
	lamp.position = Vector3(cos(angle), 0, sin(angle)) * (column_radius + 0.12) + Vector3(0, height + 2.2, 0)
	lamp.set_meta("stair_generated", true)
	add_child(lamp)
	var glass := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.32, 0.22)
	glass.mesh = box
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.75, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.7, 0.35)
	glow.emission_energy_multiplier = 3.0
	glass.material_override = glow
	lamp.add_child(glass)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 1.6
	light.omni_range = 7.5
	light.shadow_enabled = false
	light.position = Vector3(0, -0.1, 0)
	lamp.add_child(light)


func _add_prism(st: SurfaceTool, outline: PackedVector2Array, top: float, bottom: float) -> void:
	var m := outline.size()
	# Top and bottom faces (fans; the outline is convex).
	for k in range(1, m - 1):
		st.add_vertex(Vector3(outline[0].x, top, outline[0].y))
		st.add_vertex(Vector3(outline[k + 1].x, top, outline[k + 1].y))
		st.add_vertex(Vector3(outline[k].x, top, outline[k].y))
		st.add_vertex(Vector3(outline[0].x, bottom, outline[0].y))
		st.add_vertex(Vector3(outline[k].x, bottom, outline[k].y))
		st.add_vertex(Vector3(outline[k + 1].x, bottom, outline[k + 1].y))
	# Sides.
	for k in range(m):
		var a := outline[k]
		var b := outline[(k + 1) % m]
		st.add_vertex(Vector3(a.x, top, a.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(b.x, bottom, b.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))

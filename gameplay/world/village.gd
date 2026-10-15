class_name Village
extends Node3D
## The village beyond the estate's outer gate and its railway station, built at load
## from levels/grounds/village.json (tools/grounds/village.py) the way CastleExterior
## builds the castle's shell: everything merged into a few meshes per material per
## 64 m cell, plus one static body of boxes.
##
## Buildings: a stone plinth, a ground storey (stone or plaster), jettied upper storeys
## with timber framing, a steep gabled slate roof, chimneys, windows that glow at night.
## Shops, inns, the post office and the station hall can be walked into: real door
## openings, furnished interiors by trade, a warm lamp, a name board over the door.
## Interiors sit on render layer 1 only (the moon and the sun never reach them), the
## outside on layers 1 and 11 like the rest of the grounds.
##
## The station: a platform with a canopy, benches and name boards, a track from the
## buffer stop into a tunnel portal in the hillside, and a train standing at the
## platform (where new players will arrive: Grounds/Village/StationArrival).

const OUTDOOR_LAYER := 1 << 10
const CELL := 64.0
const WALL := 0.45
const DOOR_HEIGHT := 3.0
const ROOF_PITCH := deg_to_rad(52.0)
const NIGHT_GLOW := Color(1.0, 0.72, 0.38)
const DAY_GLOW := Color(0.2, 0.22, 0.26)
const PANE_DAY := Color(0.78, 0.86, 0.95)
const PANE_NIGHT := Color(0.05, 0.07, 0.14)

const PLASTER := [Color(0.86, 0.82, 0.72), Color(0.82, 0.7, 0.48), Color(0.84, 0.7, 0.66),
	Color(0.66, 0.72, 0.6), Color(0.68, 0.74, 0.78), Color(0.9, 0.89, 0.85)]
const SLATE := [Color(0.24, 0.27, 0.33), Color(0.17, 0.18, 0.2), Color(0.27, 0.3, 0.25)]
const DOORS := [Color(0.16, 0.3, 0.2), Color(0.45, 0.12, 0.1), Color(0.14, 0.2, 0.36), Color(0.1, 0.09, 0.08)]
const TIMBER := Color(0.25, 0.16, 0.1)
const OAK := Color(0.42, 0.29, 0.18)
const PLANK := Color(0.36, 0.25, 0.16)
const STONE := Color(1.0, 1.0, 1.0)
const STONE_DARK := Color(0.72, 0.7, 0.68)
const IRON := Color(0.13, 0.13, 0.14)
const BRASS := Color(0.75, 0.58, 0.25)
const CREAM := Color(0.93, 0.88, 0.74)
const SIGN := {"shop": Color(0.16, 0.24, 0.18), "inn": Color(0.32, 0.12, 0.1), "post_office": Color(0.12, 0.18, 0.34),
	"station": Color(0.14, 0.26, 0.2)}
const GOODS := {
	"sweets": [Color(0.95, 0.4, 0.55), Color(0.98, 0.8, 0.3), Color(0.5, 0.85, 0.6), Color(0.6, 0.5, 0.95), Color(0.95, 0.6, 0.3)],
	"paper": [Color(0.93, 0.9, 0.8), Color(0.85, 0.78, 0.6), Color(0.95, 0.95, 0.92), Color(0.3, 0.2, 0.5)],
	"bottles": [Color(0.2, 0.5, 0.3), Color(0.25, 0.35, 0.6), Color(0.6, 0.4, 0.15), Color(0.5, 0.2, 0.4)],
	"books": [Color(0.5, 0.15, 0.12), Color(0.15, 0.3, 0.2), Color(0.18, 0.22, 0.42), Color(0.45, 0.35, 0.2), Color(0.3, 0.12, 0.3)],
	"brass": [BRASS, Color(0.6, 0.45, 0.2), Color(0.55, 0.6, 0.62), Color(0.3, 0.2, 0.12)],
	"toys": [Color(0.95, 0.3, 0.25), Color(0.2, 0.6, 0.95), Color(0.98, 0.85, 0.2), Color(0.4, 0.85, 0.35), Color(0.8, 0.4, 0.9)],
	"cloth": [Color(0.15, 0.15, 0.3), Color(0.45, 0.1, 0.12), Color(0.12, 0.3, 0.18), Color(0.55, 0.5, 0.45), Color(0.2, 0.2, 0.2)],
	"general": [OAK, Color(0.6, 0.55, 0.4), Color(0.3, 0.4, 0.3), Color(0.7, 0.6, 0.45)],
	"brooms": [OAK, Color(0.55, 0.42, 0.25), Color(0.75, 0.62, 0.35)],
	"tavern": [Color(0.2, 0.4, 0.25), Color(0.45, 0.25, 0.12), Color(0.6, 0.5, 0.2)],
	"tea": [Color(0.95, 0.92, 0.88), Color(0.8, 0.5, 0.55), Color(0.6, 0.75, 0.85)],
	"parcels": [Color(0.7, 0.55, 0.35), Color(0.93, 0.9, 0.8), Color(0.6, 0.45, 0.3)],
	"station": [OAK],
}

@export var data_path: String = "res://levels/grounds/village.json"
## The village's outside is drawn up to this distance (m); it reads from the castle's towers.
@export var exterior_range: float = 1500.0
## Shop interiors, furniture, goods and name boards are drawn within this distance (m).
@export var interior_range: float = 90.0

var data: Dictionary = {}
## The buildings as generated ({id, kind, rect, front, door, floor, enterable…}).
var buildings: Array = []

var _mats: Dictionary = {}
var _surfaces: Dictionary = {}
var _cell := Vector2i.ZERO
var _xf := Transform3D.IDENTITY
var _body: StaticBody3D
var _glow: StandardMaterial3D
var _pane: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not FileAccess.file_exists(data_path):
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	buildings = data.get("buildings", [])
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)
	for b: Dictionary in buildings:
		_building(b)
	_square()
	_station(data["station"])
	_commit_all()


## 0 = night (warm windows, dark panes inside), 1 = day.
func set_daylight(amount: float) -> void:
	var t := clampf(amount, 0.0, 1.0)
	if _glow != null:
		_glow.albedo_color = NIGHT_GLOW.lerp(DAY_GLOW, t)
	if _pane != null:
		_pane.albedo_color = PANE_NIGHT.lerp(PANE_DAY, t)


## The generated building with this id, or {}.
func building(id: String) -> Dictionary:
	for b: Dictionary in buildings:
		if b["id"] == id:
			return b
	return {}


## World position a step outside (out > 0) or inside (out < 0) a building's front door, on its floor.
static func door_point(b: Dictionary, out: float) -> Vector3:
	var r: Array = b["rect"]
	var d: float = b["door"]
	var y: float = b["floor"]
	match str(b["front"]):
		"s": return Vector3(d, y, r[3] + out)
		"n": return Vector3(d, y, r[2] - out)
		"e": return Vector3(r[1] + out, y, d)
		_: return Vector3(r[0] - out, y, d)


# --- materials and surfaces -----------------------------------------------------------------

func _make_materials() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load("res://assets/materials/greybox_stone_albedo.png")
	stone.albedo_color = Color(0.8, 0.76, 0.7)
	stone.vertex_color_use_as_albedo = true
	stone.uv1_triplanar = true
	stone.uv1_world_triplanar = true
	stone.uv1_scale = Vector3(0.3, 0.3, 0.3)
	stone.roughness = 0.95
	_mats["stone"] = stone
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.88
	_mats["paint"] = paint
	var slate := StandardMaterial3D.new()
	slate.vertex_color_use_as_albedo = true
	slate.roughness = 0.55
	slate.metallic = 0.15
	_mats["slate"] = slate
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.roughness = 0.4
	metal.metallic = 0.7
	_mats["metal"] = metal
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = NIGHT_GLOW
	_mats["glow"] = _glow
	_pane = StandardMaterial3D.new()
	_pane.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pane.albedo_color = PANE_DAY
	_mats["pane"] = _pane
	var ember := StandardMaterial3D.new()
	ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember.vertex_color_use_as_albedo = true
	_mats["ember"] = ember
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.2, 0.34, 0.4, 0.82)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.metallic = 0.3
	_mats["water"] = water
	for m: StandardMaterial3D in _mats.values():
		m.cull_mode = BaseMaterial3D.CULL_DISABLED


## Picks the cell (by a world point) that the next shapes are merged into.
func _begin(world: Vector3, xf: Transform3D) -> void:
	_cell = Vector2i(floori(world.x / CELL), floori(world.z / CELL))
	_xf = xf


## Outside surface of a material in the current cell.
func _e(mat: String, color: Color) -> SurfaceTool:
	return _st("e", mat, color)


## Inside surface (interiors: layer 1 only, drawn near).
func _i(mat: String, color: Color) -> SurfaceTool:
	return _st("i", mat, color)


func _st(side: String, mat: String, color: Color) -> SurfaceTool:
	var key := "%d,%d|%s|%s" % [_cell.x, _cell.y, side, mat]
	var st: SurfaceTool = _surfaces.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		_surfaces[key] = st
	st.set_color(color)
	return st


func _commit_all() -> void:
	var keys := _surfaces.keys()
	keys.sort()
	for key: String in keys:
		var parts := key.split("|")
		var st: SurfaceTool = _surfaces[key]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = ("Outside_" if parts[1] == "e" else "Inside_") + parts[2] + "_" + parts[0].replace(",", "_").replace("-", "m")
		mi.mesh = st.commit()
		mi.material_override = _mats[parts[2]]
		if parts[1] == "e":
			mi.layers = 1 | OUTDOOR_LAYER
			mi.visibility_range_end = exterior_range
		else:
			mi.layers = 1
			mi.visibility_range_end = interior_range
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_surfaces.clear()


# --- primitive shapes (local to _xf) ------------------------------------------------------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var pa := _xf * a
	var pb := _xf * b
	var pc := _xf * c
	var pd := _xf * d
	st.add_vertex(pa); st.add_vertex(pb); st.add_vertex(pc)
	st.add_vertex(pa); st.add_vertex(pc); st.add_vertex(pd)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(_xf * a); st.add_vertex(_xf * b); st.add_vertex(_xf * c)


func _box(st: SurfaceTool, centre: Vector3, size: Vector3, basis := Basis(), skip_bottom := false) -> void:
	var h := size / 2.0
	var p: Array[Vector3] = []
	for z in [-h.z, h.z]:
		for y in [-h.y, h.y]:
			for x in [-h.x, h.x]:
				p.append(centre + basis * Vector3(x, y, z))
	_quad(st, p[0], p[1], p[3], p[2])
	_quad(st, p[4], p[6], p[7], p[5])
	_quad(st, p[0], p[2], p[6], p[4])
	_quad(st, p[1], p[5], p[7], p[3])
	_quad(st, p[2], p[3], p[7], p[6])
	if not skip_bottom:
		_quad(st, p[0], p[4], p[5], p[1])


## A box from corner to corner (local), no rotation.
func _span(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	_box(st, (lo + hi) / 2.0, hi - lo)


## A prism (cylinder stand-in) from a to b.
func _prism(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, sides: int = 10) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in range(sides):
		var ang := TAU * i / sides
		var off := (u * cos(ang) + v * sin(ang)) * radius
		ring_a.append(a + off)
		ring_b.append(b + off)
	for i in range(sides):
		var j := (i + 1) % sides
		_quad(st, ring_a[i], ring_a[j], ring_b[j], ring_b[i])
		_tri(st, a, ring_a[j], ring_a[i])
		_tri(st, b, ring_b[i], ring_b[j])


func _collide(centre: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = _xf * Transform3D(basis, centre)
	_body.add_child(cs)


func _solid(st: SurfaceTool, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	_box(st, centre, size, basis)
	_collide(centre, size, basis)


func _label(key: String, local: Vector3, facing_yaw: float, font_size: int, color: Color) -> void:
	var l := Label3D.new()
	l.text = key
	l.font_size = font_size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.04, 0.03)
	l.double_sided = false
	l.layers = 1 | OUTDOOR_LAYER
	l.visibility_range_end = interior_range
	l.transform = _xf * Transform3D(Basis(Vector3.UP, facing_yaw), local)
	add_child(l)


func _light(local: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.position = _xf * local
	add_child(light)


# --- buildings -------------------------------------------------------------------------------

static func _yaw_of(front: String) -> float:
	match front:
		"s": return 0.0
		"n": return PI
		"e": return PI / 2.0
		_: return -PI / 2.0


static func _world_side(dir: Vector3) -> String:
	if absf(dir.x) > absf(dir.z):
		return "e" if dir.x > 0.0 else "w"
	return "s" if dir.z > 0.0 else "n"


func _building(b: Dictionary) -> void:
	var r: Array = b["rect"]
	var centre := Vector3((r[0] + r[1]) / 2.0, 0.0, (r[2] + r[3]) / 2.0)
	var front := str(b["front"])
	var basis := Basis(Vector3.UP, _yaw_of(front))
	var along_x := front == "n" or front == "s"
	var w: float = (r[1] - r[0]) if along_x else (r[3] - r[2])
	var d: float = (r[3] - r[2]) if along_x else (r[1] - r[0])
	var xf := Transform3D(basis, centre)
	_begin(centre, xf)
	_rng.seed = hash(str(b["id"]))
	var kind := str(b["kind"])
	var enter: bool = b["enterable"]
	var floor_y: float = b["floor"]
	var ground: float = b["ground"]
	var g_h: float = data["ground_storey"]
	var u_h: float = data["upper_storey"]
	var storeys: int = int(b["storeys"])
	var top := floor_y + g_h + (storeys - 1) * u_h
	var plaster: Color = PLASTER[int(b["plaster"]) % PLASTER.size()]
	var stone_ground := kind in ["station", "inn", "post_office"] or int(b["plaster"]) % 2 == 0
	var all_stone := kind == "station"
	var timbered := not all_stone and int(b["plaster"]) % 3 != 2
	var jetty: float = 0.35 if b["jetty"] else 0.0
	var door_world := Vector3(b["door"], 0.0, centre.z) if along_x else Vector3(centre.x, 0.0, b["door"])
	var door_x := basis.x.dot(door_world - centre)
	# The back wall's frame runs against the building's x.
	var back_x := NAN
	if b.has("back_door"):
		var back_world := Vector3(b["back_door"], 0.0, centre.z) if along_x else Vector3(centre.x, 0.0, b["back_door"])
		back_x = -basis.x.dot(back_world - centre)
	var attached: Array = b.get("attached", [])
	var exposed := func(local_dir: Vector3) -> bool: return not attached.has(_world_side(basis * local_dir))

	# Plinth and door step.
	_solid(_e("stone", STONE_DARK), Vector3(0, (ground - 0.6 + floor_y) / 2.0, 0), Vector3(w + 0.3, floor_y - ground + 0.6, d + 0.3))
	var sill: float = b["sill"]
	if floor_y - sill > 0.3:
		_solid(_e("stone", STONE_DARK), Vector3(door_x, (sill - 0.4 + floor_y - 0.25) / 2.0, d / 2.0 + 0.5),
			Vector3(data["door_width"] + 1.0, floor_y - 0.25 - sill + 0.4, 0.7))

	# Ground storey.
	var g_mat := "stone" if stone_ground else "paint"
	var g_col := STONE if stone_ground else plaster
	if enter:
		_ground_walls(b, w, d, floor_y, g_h, door_x, back_x, g_mat, g_col)
		_interior(b, w, d, floor_y, g_h)
	else:
		_solid(_e(g_mat, g_col), Vector3(0, floor_y + g_h / 2.0, 0), Vector3(w, g_h, d))
	_ground_dressing(b, w, d, floor_y, g_h, door_x, back_x, enter, exposed)

	# Upper storeys: one solid block, jettied front and back, framed in timber.
	var up_d := d + 2.0 * jetty
	if storeys > 1:
		var u_mat := "stone" if all_stone else "paint"
		var u_col := STONE if all_stone else plaster
		var base := floor_y + g_h
		_box(_e(u_mat, u_col), Vector3(0, (base + top) / 2.0, 0), Vector3(w, top - base, up_d))
		_collide(Vector3(0, (base + top) / 2.0, 0), Vector3(w, top - base, up_d))
		if jetty > 0.0:
			# Joist ends under the overhang.
			var n := int(w / 0.8)
			for i in range(n):
				var x := -w / 2.0 + 0.4 + i * (w - 0.8) / maxf(1.0, n - 1)
				for side in [-1.0, 1.0]:
					_box(_e("paint", TIMBER), Vector3(x, base - 0.12, side * (d / 2.0 + jetty / 2.0)), Vector3(0.16, 0.24, jetty + 0.1))
		for s in range(storeys - 1):
			var y0 := base + s * u_h
			_upper_storey(b, w, up_d, y0, u_h, timbered, exposed)
	# Roof, gables, chimney.
	_roof(b, w, up_d, top, plaster if not all_stone else STONE, all_stone, timbered)
	if enter:
		_light(Vector3(0, floor_y + g_h - 0.7, 0), Color(1.0, 0.8, 0.56), 1.3, maxf(w, d) * 0.8)


## Walls of a walk-in ground storey: outer faces outside, inner faces inside, the front
## door (and the station's back door) open.
func _ground_walls(b: Dictionary, w: float, d: float, y0: float, h: float, door_x: float, back_x: float, mat: String, col: Color) -> void:
	var dw: float = data["door_width"]
	var front_open: Array[Rect2] = [Rect2(door_x - dw / 2.0, y0, dw, DOOR_HEIGHT)]
	var back_open: Array[Rect2] = []
	if not is_nan(back_x):
		back_open.append(Rect2(back_x - dw / 2.0, y0, dw, DOOR_HEIGHT))
	var none: Array[Rect2] = []
	var inner_base: Color = PLASTER[(int(b["plaster"]) + 3) % PLASTER.size()]
	var inner := inner_base.lerp(Color(0.95, 0.92, 0.85), 0.5)
	var base := _xf
	var walls := [
		[Basis(), Vector3(0, 0, d / 2.0), w / 2.0, front_open],
		[Basis(Vector3.UP, PI), Vector3(0, 0, -d / 2.0), w / 2.0, back_open],
		[Basis(Vector3.UP, PI / 2.0), Vector3(w / 2.0, 0, 0), d / 2.0 - WALL, none],
		[Basis(Vector3.UP, -PI / 2.0), Vector3(-w / 2.0, 0, 0), d / 2.0 - WALL, none],
	]
	for wall: Array in walls:
		_xf = base * Transform3D(wall[0], wall[1])
		_wall(_e(mat, col), _i("paint", inner), -float(wall[2]), float(wall[2]), y0, y0 + h, wall[3])
	_xf = base
	# Floor boards and the ceiling with its beams.
	var fx := w / 2.0 - WALL
	var fz := d / 2.0 - WALL
	_quad(_i("paint", PLANK), Vector3(-fx, y0 + 0.01, -fz), Vector3(fx, y0 + 0.01, -fz), Vector3(fx, y0 + 0.01, fz), Vector3(-fx, y0 + 0.01, fz))
	var ceil_y := y0 + h - 0.01
	_quad(_i("paint", inner), Vector3(-fx, ceil_y, -fz), Vector3(-fx, ceil_y, fz), Vector3(fx, ceil_y, fz), Vector3(fx, ceil_y, -fz))
	var n := int(w / 2.4)
	for i in range(n):
		var x := -fx + (i + 0.5) * (2.0 * fx) / n
		_box(_i("paint", TIMBER), Vector3(x, ceil_y - 0.15, 0), Vector3(0.24, 0.3, 2.0 * fz))


## One wall in the current frame: runs along x from x0 to x1, outer face at z = 0 facing +z,
## WALL thick; openings are Rect2(x, y, w, h). Outer faces to `out`, inner faces to `inn`.
func _wall(out: SurfaceTool, inn: SurfaceTool, x0: float, x1: float, y0: float, y1: float, openings: Array[Rect2]) -> void:
	var cuts: Array[float] = [x0, x1]
	for o in openings:
		cuts.append(clampf(o.position.x, x0, x1))
		cuts.append(clampf(o.end.x, x0, x1))
	cuts.sort()
	for i in range(cuts.size() - 1):
		var a := cuts[i]
		var b := cuts[i + 1]
		if b - a < 0.001:
			continue
		var hole: Rect2 = Rect2()
		for o in openings:
			if o.position.x <= a + 0.001 and o.end.x >= b - 0.001:
				hole = o
		var spans: Array[Vector2] = []
		if hole.size == Vector2.ZERO:
			spans.append(Vector2(y0, y1))
		else:
			if hole.position.y > y0 + 0.001:
				spans.append(Vector2(y0, hole.position.y))
			if hole.end.y < y1 - 0.001:
				spans.append(Vector2(hole.end.y, y1))
		for s in spans:
			_quad(out, Vector3(a, s.x, 0), Vector3(b, s.x, 0), Vector3(b, s.y, 0), Vector3(a, s.y, 0))
			_quad(inn, Vector3(b, s.x, -WALL), Vector3(a, s.x, -WALL), Vector3(a, s.y, -WALL), Vector3(b, s.y, -WALL))
			_collide(Vector3((a + b) / 2.0, (s.x + s.y) / 2.0, -WALL / 2.0), Vector3(b - a, s.y - s.x, WALL))
	# Reveals around each opening and the wall's end caps.
	for o in openings:
		var l := o.position.x
		var r := o.end.x
		var top := o.end.y
		_quad(out, Vector3(l, o.position.y, 0), Vector3(l, top, 0), Vector3(l, top, -WALL), Vector3(l, o.position.y, -WALL))
		_quad(out, Vector3(r, o.position.y, -WALL), Vector3(r, top, -WALL), Vector3(r, top, 0), Vector3(r, o.position.y, 0))
		_quad(out, Vector3(l, top, 0), Vector3(r, top, 0), Vector3(r, top, -WALL), Vector3(l, top, -WALL))
	for x in [x0, x1]:
		_quad(out, Vector3(x, y0, 0), Vector3(x, y1, 0), Vector3(x, y1, -WALL), Vector3(x, y0, -WALL))


## Door, windows, shop fronts, sign and lamp on the ground storey's outside.
func _ground_dressing(b: Dictionary, w: float, d: float, y0: float, h: float, door_x: float, back_x: float, enter: bool, exposed: Callable) -> void:
	var kind := str(b["kind"])
	var dw: float = data["door_width"]
	var base := _xf
	# Front (frame: outer face z = 0 facing +z).
	_xf = base * Transform3D(Basis(), Vector3(0, 0, d / 2.0))
	_door(door_x, y0, dw, enter, DOORS[_rng.randi() % DOORS.size()])
	var free := func(x: float, half: float) -> bool:
		return absf(x - door_x) > dw / 2.0 + half + 0.5 and absf(x) < w / 2.0 - half - 0.5
	if kind == "shop":
		for side in [-1.0, 1.0]:
			var x0: float = door_x + side * (dw / 2.0 + 0.5)
			var x1: float = side * (w / 2.0 - 0.7)
			var bw := absf(x1 - x0)
			if bw >= 2.0:
				_shop_window((x0 + x1) / 2.0, minf(bw, 4.4), y0, enter)
	else:
		var big := kind != "house"
		var step := 3.2 if big else 2.8
		var k := 1
		while k < 6:
			for side in [-1.0, 1.0]:
				var x: float = door_x + side * (dw / 2.0 + step * (k - 0.35))
				if free.call(x, 0.8 if big else 0.6):
					_window(x, y0 + (1.0 if big else 1.1), 1.6 if big else 1.1, 2.0 if big else 1.6, enter)
			k += 1
	if enter:
		var board_w := minf(w - 1.4, 7.0)
		var sx := door_x if absf(door_x) + board_w / 2.0 < w / 2.0 else 0.0
		_box(_e("paint", SIGN.get(kind, SIGN["shop"])), Vector3(sx, y0 + h - 0.62, 0.08), Vector3(board_w, 0.72, 0.12))
		_label(str(b["name_key"]), Vector3(sx, y0 + h - 0.62, 0.16), 0.0, 44, Color(0.98, 0.88, 0.6))
		if kind == "inn":
			_hanging_sign(str(b["name_key"]), door_x + dw / 2.0 + 1.6, y0 + h - 1.0)
		if kind == "station":
			_clock(Vector3(door_x, y0 + h + 1.9, 0.06))
	# Wall lantern beside the door.
	if enter or _rng.randf() < 0.5:
		var lx := door_x - dw / 2.0 - 0.6
		_box(_e("metal", IRON), Vector3(lx, y0 + 2.55, 0.18), Vector3(0.08, 0.4, 0.36))
		_box(_e("glow", Color.WHITE), Vector3(lx, y0 + 2.45, 0.32), Vector3(0.24, 0.3, 0.24))
	# Back and exposed sides: plain windows.
	_xf = base * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d / 2.0))
	if not is_nan(back_x):
		var bx := back_x
		_door(bx, y0, dw, true, DOORS[0])
		_box(_e("paint", SIGN["station"]), Vector3(bx, y0 + h - 0.62, 0.08), Vector3(minf(w - 1.4, 7.0), 0.72, 0.12))
		_label("AREA_STATION", Vector3(bx, y0 + h - 0.62, 0.16), 0.0, 44, Color(0.98, 0.88, 0.6))
	else:
		for x in [-w / 4.0, w / 4.0]:
			_window(x, y0 + 1.1, 1.1, 1.6, enter)
	for side in [1.0, -1.0]:
		if not exposed.call(Vector3(side, 0, 0)):
			continue
		_xf = base * Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3(side * w / 2.0, 0, 0))
		if d >= 10.0:
			_window(0.0, y0 + 1.1, 1.1, 1.6, enter)
	_xf = base


func _door(x: float, y0: float, dw: float, open: bool, colour: Color) -> void:
	var st := _e("paint", TIMBER)
	_box(st, Vector3(x - dw / 2.0 - 0.1, y0 + DOOR_HEIGHT / 2.0, 0.06), Vector3(0.2, DOOR_HEIGHT + 0.1, 0.16))
	_box(st, Vector3(x + dw / 2.0 + 0.1, y0 + DOOR_HEIGHT / 2.0, 0.06), Vector3(0.2, DOOR_HEIGHT + 0.1, 0.16))
	_box(st, Vector3(x, y0 + DOOR_HEIGHT + 0.12, 0.06), Vector3(dw + 0.6, 0.24, 0.2))
	if open:
		# The leaf stands open against the inside wall.
		_box(_i("paint", colour), Vector3(x - dw / 2.0 + 0.06, y0 + DOOR_HEIGHT / 2.0, -WALL - dw / 2.0 + 0.05), Vector3(0.08, DOOR_HEIGHT - 0.05, dw - 0.1))
	else:
		_box(_e("paint", colour), Vector3(x, y0 + DOOR_HEIGHT / 2.0, 0.03), Vector3(dw - 0.05, DOOR_HEIGHT - 0.05, 0.06))
		_box(_e("metal", BRASS), Vector3(x + dw / 2.0 - 0.3, y0 + 1.15, 0.09), Vector3(0.08, 0.08, 0.08))


## A plain window on the current wall frame: glowing pane, frame, mullions, sill; inside
## a daylight pane when the room behind it can be entered.
func _window(x: float, y: float, w: float, h: float, inside: bool) -> void:
	_quad(_e("glow", Color.WHITE), Vector3(x - w / 2.0, y, 0.04), Vector3(x + w / 2.0, y, 0.04), Vector3(x + w / 2.0, y + h, 0.04), Vector3(x - w / 2.0, y + h, 0.04))
	var st := _e("paint", TIMBER)
	_box(st, Vector3(x - w / 2.0 - 0.06, y + h / 2.0, 0.07), Vector3(0.12, h + 0.24, 0.1))
	_box(st, Vector3(x + w / 2.0 + 0.06, y + h / 2.0, 0.07), Vector3(0.12, h + 0.24, 0.1))
	_box(st, Vector3(x, y + h + 0.06, 0.07), Vector3(w + 0.24, 0.12, 0.1))
	_box(st, Vector3(x, y + h * 0.55, 0.06), Vector3(w, 0.06, 0.06))
	_box(st, Vector3(x, y + h / 2.0, 0.06), Vector3(0.06, h, 0.06))
	_box(_e("stone", STONE_DARK), Vector3(x, y - 0.06, 0.12), Vector3(w + 0.36, 0.12, 0.26))
	if inside:
		_quad(_i("pane", Color.WHITE), Vector3(x + w / 2.0, y, -WALL - 0.02), Vector3(x - w / 2.0, y, -WALL - 0.02), Vector3(x - w / 2.0, y + h, -WALL - 0.02), Vector3(x + w / 2.0, y + h, -WALL - 0.02))


## A shop's bay window: a low stone stall, a projecting frame of small panes, a little roof.
func _shop_window(x: float, w: float, y0: float, inside: bool) -> void:
	var proud := 0.45
	var sill := y0 + 0.75
	var top := y0 + 3.0
	_box(_e("stone", STONE_DARK), Vector3(x, (y0 + sill) / 2.0, proud / 2.0), Vector3(w + 0.2, sill - y0, proud + 0.05))
	_quad(_e("glow", Color.WHITE), Vector3(x - w / 2.0, sill, proud), Vector3(x + w / 2.0, sill, proud), Vector3(x + w / 2.0, top, proud), Vector3(x - w / 2.0, top, proud))
	var st := _e("paint", TIMBER)
	for k in range(int(w / 0.75) + 1):
		var px := x - w / 2.0 + k * w / int(w / 0.75)
		_box(st, Vector3(px, (sill + top) / 2.0, proud), Vector3(0.07, top - sill, 0.08))
	for yy in [sill, sill + (top - sill) * 0.5, top]:
		_box(st, Vector3(x, yy, proud), Vector3(w + 0.1, 0.1, 0.1))
	for side in [-1.0, 1.0]:
		_quad(_e("glow", Color.WHITE), Vector3(x + side * w / 2.0, sill, 0.02), Vector3(x + side * w / 2.0, sill, proud), Vector3(x + side * w / 2.0, top, proud), Vector3(x + side * w / 2.0, top, 0.02))
	_box(_e("slate", SLATE[1]), Vector3(x, top + 0.18, proud / 2.0 + 0.05), Vector3(w + 0.4, 0.14, proud + 0.4), Basis(Vector3.RIGHT, 0.25))
	_collide(Vector3(x, (y0 + top) / 2.0, proud / 2.0), Vector3(w + 0.2, top - y0, proud + 0.05))
	if inside:
		_quad(_i("pane", Color.WHITE), Vector3(x + w / 2.0, sill, -WALL - 0.02), Vector3(x - w / 2.0, sill, -WALL - 0.02), Vector3(x - w / 2.0, top, -WALL - 0.02), Vector3(x + w / 2.0, top, -WALL - 0.02))


func _hanging_sign(key: String, x: float, y: float) -> void:
	var st := _e("metal", IRON)
	_box(st, Vector3(x, y + 0.6, 0.85), Vector3(0.08, 0.08, 1.7))
	_box(st, Vector3(x, y + 0.35, 0.12), Vector3(0.08, 0.5, 0.08))
	_box(_e("paint", SIGN["inn"]), Vector3(x, y, 1.15), Vector3(0.1, 0.9, 1.3))
	_label(key, Vector3(x + 0.07, y, 1.15), PI / 2.0, 28, Color(0.98, 0.88, 0.6))
	_label(key, Vector3(x - 0.07, y, 1.15), -PI / 2.0, 28, Color(0.98, 0.88, 0.6))


func _clock(at: Vector3) -> void:
	_prism(_e("paint", CREAM), at, at + Vector3(0, 0, 0.12), 0.9, 16)
	_prism(_e("metal", BRASS), at + Vector3(0, 0, -0.02), at + Vector3(0, 0, 0.08), 1.02, 16)
	var st := _e("metal", IRON)
	_box(st, at + Vector3(0, 0.28, 0.16), Vector3(0.06, 0.56, 0.03))
	_box(st, at + Vector3(0.2, 0.0, 0.17), Vector3(0.4, 0.06, 0.03), Basis(Vector3.BACK, 0.4))


## One upper storey of the solid block (frame: building local): windows, timber framing.
func _upper_storey(b: Dictionary, w: float, d: float, y0: float, h: float, timbered: bool, exposed: Callable) -> void:
	var base := _xf
	var faces := [[Basis(), Vector3(0, 0, d / 2.0), w], [Basis(Vector3.UP, PI), Vector3(0, 0, -d / 2.0), w]]
	for side in [1.0, -1.0]:
		if exposed.call(Vector3(side, 0, 0)):
			faces.append([Basis(Vector3.UP, side * PI / 2.0), Vector3(side * w / 2.0, 0, 0), d])
	for f: Array in faces:
		_xf = base * Transform3D(f[0], f[1])
		var length: float = f[2]
		var n := maxi(1, int((length - 1.0) / 3.0)) if f[0] == Basis() or f[1].z < 0.0 else 1
		var xs: Array[float] = []
		for i in range(n):
			xs.append(-length / 2.0 + (i + 0.5) * length / n)
		for x in xs:
			_window(x, y0 + 0.9, 1.0, 1.4, false)
		if timbered:
			var st := _e("paint", TIMBER)
			_box(st, Vector3(0, y0 + 0.12, 0.04), Vector3(length, 0.24, 0.08))
			_box(st, Vector3(0, y0 + h - 0.1, 0.04), Vector3(length, 0.2, 0.08))
			var posts: Array[float] = [-length / 2.0 + 0.1, length / 2.0 - 0.1]
			for i in range(xs.size() - 1):
				posts.append((xs[i] + xs[i + 1]) / 2.0)
			for x in xs:
				posts.append(x - 0.75)
				posts.append(x + 0.75)
			for x in posts:
				_box(st, Vector3(x, y0 + h / 2.0, 0.04), Vector3(0.18, h, 0.08))
			# Braces from the corners.
			var ang := atan2(h - 0.4, 1.2)
			var brace := sqrt(1.44 + pow(h - 0.4, 2))
			_box(st, Vector3(-length / 2.0 + 0.7, y0 + h / 2.0, 0.04), Vector3(brace, 0.16, 0.07), Basis(Vector3.BACK, ang))
			_box(st, Vector3(length / 2.0 - 0.7, y0 + h / 2.0, 0.04), Vector3(brace, 0.16, 0.07), Basis(Vector3.BACK, -ang))
	_xf = base


## A steep gabled slate roof over the walls (w along local x, d along z) from height y0.
func _roof(b: Dictionary, w: float, d: float, y0: float, gable_col: Color, stone: bool, timbered: bool) -> void:
	var base := _xf
	var front_gable := str(b["roof"]) == "front"
	# Roof frame: the ridge runs along its x.
	var length := d if front_gable else w
	var span := w if front_gable else d
	_xf = base * Transform3D(Basis(Vector3.UP, PI / 2.0) if front_gable else Basis(), Vector3.ZERO)
	var half := span / 2.0
	var rise := minf(half * tan(ROOF_PITCH), 8.5)
	var ang := atan2(rise, half)
	var eave := 0.5
	var over := 0.35
	var slab := Vector2(half + eave, rise + eave * tan(ang)).length()
	var colour: Color = SLATE[int(b["slate"]) % SLATE.size()]
	for side in [1.0, -1.0]:
		var mid := Vector3(0, y0 + rise / 2.0 - eave * tan(ang) / 2.0 + 0.15, side * (half + eave) / 2.0)
		var basis := Basis(Vector3.RIGHT, side * ang)
		_box(_e("slate", colour), mid, Vector3(length + 2.0 * over, 0.28, slab), basis)
		_collide(mid, Vector3(length + 2.0 * over, 0.28, slab), basis)
	_box(_e("slate", colour.darkened(0.3)), Vector3(0, y0 + rise + 0.2, 0), Vector3(length + 2.0 * over + 0.1, 0.3, 0.45))
	# Gable ends.
	var gmat := "stone" if stone else "paint"
	for side in [-1.0, 1.0]:
		var x: float = side * length / 2.0
		var st := _e(gmat, gable_col)
		_tri(st, Vector3(x, y0, -half), Vector3(x, y0, half), Vector3(x, y0 + rise, 0))
		_tri(st, Vector3(x - side * 0.3, y0, half), Vector3(x - side * 0.3, y0, -half), Vector3(x - side * 0.3, y0 + rise, 0))
		if timbered:
			var tb := _e("paint", TIMBER)
			_box(tb, Vector3(x + side * 0.03, y0 + rise * 0.45, 0), Vector3(0.08, rise * 0.9, 0.18))
			_box(tb, Vector3(x + side * 0.03, y0 + rise * 0.35, 0), Vector3(0.08, 0.16, span * 0.65))
		if front_gable or _rng.randf() < 0.5:
			_window_on_gable(x, side, y0 + rise * 0.3)
	# Chimney through the back slope near one end.
	var cx: float = float(b["chimney"]) * (length / 2.0 - 1.4)
	var cz := -minf(1.4, half * 0.5)
	var c_top := y0 + rise + 1.4
	var c_bot := y0 + rise * (1.0 - absf(cz) / half) - 0.6
	_solid(_e("stone", STONE_DARK), Vector3(cx, (c_bot + c_top) / 2.0, cz), Vector3(1.1, c_top - c_bot, 0.9))
	_box(_e("stone", STONE_DARK), Vector3(cx, c_top + 0.1, cz), Vector3(1.35, 0.2, 1.15))
	for k in [-0.25, 0.25]:
		_prism(_e("paint", Color(0.55, 0.3, 0.2)), Vector3(cx + k, c_top + 0.2, cz), Vector3(cx + k, c_top + 0.75, cz), 0.13, 8)
	_xf = base


func _window_on_gable(x: float, side: float, y: float) -> void:
	var base := _xf
	_xf = base * Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3(x, 0, 0))
	_window(0.0, y, 0.9, 1.2, false)
	_xf = base


# --- interiors --------------------------------------------------------------------------------

## Furniture and goods by trade (frame: building local, front +z).
func _interior(b: Dictionary, w: float, d: float, y0: float, h: float) -> void:
	var kind := str(b["kind"])
	var goods := str(b.get("goods", kind))
	var palette: Array = GOODS.get(goods, GOODS["general"])
	var xl := -w / 2.0 + WALL
	var xr := w / 2.0 - WALL
	var zb := -d / 2.0 + WALL
	var zf := d / 2.0 - WALL
	match kind:
		"shop":
			_counter(Vector3(xl + 1.2, y0, zb + 3.0), Vector3(xr - 2.4, y0, zb + 3.0), 0.8)
			_shelves(Vector3(xl + 0.3, y0, zb), Vector3(xr - 0.3, y0, zb), goods, palette)
			if goods == "brooms":
				_broom_rack(Vector3(xl, y0, zb + 4.6), Vector3(xl, y0, zf - 2.0), palette)
			else:
				_shelves(Vector3(xl, y0, zf - 2.0), Vector3(xl, y0, zb + 4.6), goods, palette)
			_display_table(Vector3(xr * 0.35, y0, (zb + 3.0 + zf) / 2.0 + 0.6), goods, palette)
			if goods == "general":
				for k in range(3):
					_barrel(Vector3(xr - 0.6, y0, zf - 1.4 - k * 1.1))
		"inn":
			if goods == "tavern":
				_counter(Vector3(xl + 2.2, y0, zb + 1.6), Vector3(xl + 2.2, y0, minf(zb + 9.5, zf - 3.0)), 0.8)
				_shelves(Vector3(xl, y0, minf(zb + 9.5, zf - 3.0)), Vector3(xl, y0, zb + 0.6), "bottles", GOODS["bottles"])
				_hearth(Vector3(xr, y0, (zb + zf) / 2.0), -PI / 2.0)
				for gx in [0.0, 3.6]:
					for gz in [zb + 3.5, zb + 7.5, zb + 11.5]:
						if gz < zf - 2.5:
							_table(Vector3(xl + 5.4 + gx, y0, gz), 1.4, 4)
			else:
				_counter(Vector3(xl + 1.0, y0, zb + 2.6), Vector3(xr - 2.2, y0, zb + 2.6), 0.7)
				_shelves(Vector3(xl + 0.3, y0, zb), Vector3(xr - 0.3, y0, zb), "tea", palette)
				_hearth(Vector3(xl, y0, (zb + zf) / 2.0 + 1.0), PI / 2.0)
				for gx in [-2.2, 1.8]:
					for gz in [zb + 5.6, zb + 8.8, zb + 12.0]:
						if gz < zf - 1.8:
							_table(Vector3(gx, y0, gz), 0.9, 2)
		"post_office":
			_counter(Vector3(xl + 1.2, y0, zb + 3.4), Vector3(xr - 2.2, y0, zb + 3.4), 0.8)
			for k in range(int((xr - xl - 3.4) / 0.5)):
				_box(_i("metal", IRON), Vector3(xl + 1.4 + k * 0.5, y0 + 1.65, zb + 3.4), Vector3(0.04, 1.2, 0.04))
			_pigeonholes(Vector3(xl + 0.4, y0, zb), Vector3(xr - 0.4, y0, zb))
			for k in range(4):
				_crate(Vector3(xr - 0.8, y0, zf - 1.2 - k * 1.0), 0.6 + 0.1 * (k % 2), palette[k % palette.size()])
			# Perches for the messenger birds.
			_box(_i("paint", OAK), Vector3(xl + 0.6, y0 + 2.0, (zb + zf) / 2.0 + 1.0), Vector3(0.08, 0.08, 4.0))
			for dz in [-1.8, 1.8]:
				_box(_i("paint", OAK), Vector3(xl + 0.6, y0 + 1.0, (zb + zf) / 2.0 + 1.0 + dz), Vector3(0.1, 2.0, 0.1))
		"station":
			_counter(Vector3(xl + 2.0, y0, zb + 2.4), Vector3(xl + 10.0, y0, zb + 2.4), 0.8)
			for k in range(2):
				var x := xl + 3.5 + k * 4.0
				_box(_i("metal", IRON), Vector3(x, y0 + 1.7, zb + 2.4), Vector3(1.6, 1.2, 0.05))
			_box(_i("paint", Color(0.1, 0.12, 0.1)), Vector3(xr - 0.05, y0 + 2.6, (zb + zf) / 2.0), Vector3(0.1, 1.6, 4.4))
			for x in [-7.0, 7.0]:
				_bench(Vector3(x, y0, 1.0), PI / 2.0)
				_bench(Vector3(x, y0, -2.2), PI / 2.0)


func _counter(a: Vector3, b: Vector3, depth: float) -> void:
	var length := a.distance_to(b)
	var mid := (a + b) / 2.0
	var basis := Basis(Vector3.UP, atan2(-(b.z - a.z), b.x - a.x))
	_box(_i("paint", Color(0.3, 0.2, 0.12)), mid + Vector3(0, 0.5, 0), Vector3(length, 1.0, depth), basis)
	_box(_i("paint", OAK), mid + Vector3(0, 1.03, 0), Vector3(length + 0.1, 0.06, depth + 0.12), basis)
	_collide(mid + Vector3(0, 0.53, 0), Vector3(length, 1.06, depth), basis)


## A shelf unit with its back against a wall, from a to b (both on the wall line).
func _shelves(a: Vector3, b: Vector3, goods: String, palette: Array) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var inward := Vector3(-dir.z, 0, dir.x)
	if inward.dot(-a) < 0.0:
		inward = -inward
	var depth := 0.45
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var mid := (a + b) / 2.0 + inward * depth / 2.0
	var wood := Color(0.3, 0.2, 0.12)
	var h := 3.0
	_box(_i("paint", wood), mid + Vector3(0, h / 2.0, 0) - inward * (depth / 2.0 - 0.03), Vector3(length, h, 0.06), basis)
	var uprights := int(length / 1.8) + 1
	for k in range(uprights + 1):
		var p := a + dir * (length * k / uprights) + inward * depth / 2.0
		_box(_i("paint", wood), p + Vector3(0, h / 2.0, 0), Vector3(0.06, h, depth), basis)
	for level in [0.15, 0.85, 1.55, 2.25, 2.95]:
		_box(_i("paint", wood), mid + Vector3(0, level, 0), Vector3(length, 0.05, depth), basis)
		if level > 2.9:
			continue
		var x := 0.2
		while x < length - 0.2:
			var size := _goods_size(goods)
			var c: Color = palette[_rng.randi() % palette.size()]
			var p2 := a + dir * x + inward * (depth / 2.0) + Vector3(0, level + 0.025 + size.y / 2.0, 0)
			_box(_i("paint", c), p2, size, basis)
			x += size.x + (0.02 if goods == "books" else 0.08 + _rng.randf() * 0.12)
	_collide(mid + Vector3(0, h / 2.0, 0), Vector3(length, h, depth), basis)


func _goods_size(goods: String) -> Vector3:
	match goods:
		"books": return Vector3(0.06 + _rng.randf() * 0.05, 0.28 + _rng.randf() * 0.14, 0.26)
		"bottles": return Vector3(0.1, 0.24 + _rng.randf() * 0.12, 0.1)
		"sweets": return Vector3(0.2, 0.28, 0.2)
		"paper": return Vector3(0.34, 0.06 + _rng.randf() * 0.2, 0.26)
		"cloth": return Vector3(0.36, 0.3, 0.38)
		"tea": return Vector3(0.18, 0.18 + _rng.randf() * 0.08, 0.18)
		"toys": return Vector3(0.2 + _rng.randf() * 0.25, 0.15 + _rng.randf() * 0.3, 0.22)
		"brass": return Vector3(0.18 + _rng.randf() * 0.2, 0.12 + _rng.randf() * 0.35, 0.2)
	return Vector3(0.3 + _rng.randf() * 0.2, 0.25 + _rng.randf() * 0.25, 0.3)


func _display_table(at: Vector3, goods: String, palette: Array) -> void:
	_box(_i("paint", OAK), at + Vector3(0, 0.82, 0), Vector3(2.2, 0.08, 1.0))
	_box(_i("paint", Color(0.3, 0.2, 0.12)), at + Vector3(0, 0.4, 0), Vector3(2.0, 0.78, 0.85))
	_collide(at + Vector3(0, 0.43, 0), Vector3(2.2, 0.86, 1.0))
	for k in range(5):
		var size := _goods_size(goods)
		var c: Color = palette[_rng.randi() % palette.size()]
		_box(_i("paint", c), at + Vector3(-0.85 + k * 0.42, 0.86 + size.y / 2.0, (_rng.randf() - 0.5) * 0.4), size)


func _broom_rack(a: Vector3, b: Vector3, palette: Array) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	_box(_i("paint", Color(0.3, 0.2, 0.12)), (a + b) / 2.0 + Vector3(0.12, 2.3, 0), Vector3(0.1, 0.12, length))
	var n := int(length / 0.45)
	for k in range(n):
		var p := a + dir * (0.3 + k * 0.45) + Vector3(0.3, 0, 0)
		var c: Color = palette[_rng.randi() % palette.size()]
		_box(_i("paint", c), p + Vector3(0, 1.45, 0), Vector3(0.05, 1.9, 0.05), Basis(Vector3.BACK, -0.08))
		_box(_i("paint", Color(0.7, 0.58, 0.3)), p + Vector3(0.03, 0.3, 0), Vector3(0.24, 0.6, 0.24))
	_collide((a + b) / 2.0 + Vector3(0.3, 1.2, 0), Vector3(0.5, 2.4, length))


func _hearth(wall_point: Vector3, facing: float) -> void:
	var base := _xf
	_xf = base * Transform3D(Basis(Vector3.UP, facing), wall_point)
	_solid(_i("stone", STONE_DARK), Vector3(0, 1.2, 0.4), Vector3(2.8, 2.4, 0.8))
	_box(_i("ember", Color(1.0, 0.45, 0.12)), Vector3(0, 0.45, 0.82), Vector3(1.4, 0.7, 0.04))
	_box(_i("stone", STONE_DARK), Vector3(0, 2.45, 0.55), Vector3(3.1, 0.2, 1.1))
	_light(Vector3(0, 1.0, 1.4), Color(1.0, 0.55, 0.25), 1.4, 6.0)
	_xf = base


func _table(at: Vector3, size: float, seats: int) -> void:
	_box(_i("paint", OAK), at + Vector3(0, 0.76, 0), Vector3(size, 0.08, size))
	_box(_i("paint", Color(0.3, 0.2, 0.12)), at + Vector3(0, 0.37, 0), Vector3(0.18, 0.72, 0.18))
	_collide(at + Vector3(0, 0.4, 0), Vector3(size, 0.8, size))
	var offs := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	for k in range(seats):
		var p: Vector3 = at + offs[k] * (size / 2.0 + 0.45)
		_box(_i("paint", OAK), p + Vector3(0, 0.45, 0), Vector3(0.42, 0.06, 0.42))
		_box(_i("paint", Color(0.3, 0.2, 0.12)), p + Vector3(0, 0.22, 0), Vector3(0.3, 0.44, 0.3))


func _pigeonholes(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	_box(_i("paint", Color(0.3, 0.2, 0.12)), (a + b) / 2.0 + Vector3(0, 1.6, 0.2), Vector3(length, 2.4, 0.4))
	var cols := int(length / 0.4)
	for r in range(6):
		for c in range(cols):
			var p := a + Vector3(0.2 + c * 0.4, 0.55 + r * 0.4, 0.41)
			_box(_i("paint", Color(0.16, 0.1, 0.06)), p, Vector3(0.34, 0.34, 0.02))
			if _rng.randf() < 0.45:
				_box(_i("paint", CREAM), p + Vector3(0, -0.08, 0.02), Vector3(0.24, 0.14, 0.02))
	_collide((a + b) / 2.0 + Vector3(0, 1.6, 0.2), Vector3(length, 2.4, 0.4))


func _crate(at: Vector3, s: float, colour: Color) -> void:
	_solid(_i("paint", colour), at + Vector3(0, s / 2.0, 0), Vector3(s, s, s))


func _barrel(at: Vector3) -> void:
	_prism(_i("paint", OAK), at, at + Vector3(0, 0.95, 0), 0.4, 10)
	_prism(_i("metal", IRON), at + Vector3(0, 0.2, 0), at + Vector3(0, 0.26, 0), 0.42, 10)
	_prism(_i("metal", IRON), at + Vector3(0, 0.7, 0), at + Vector3(0, 0.76, 0), 0.42, 10)
	_collide(at + Vector3(0, 0.48, 0), Vector3(0.8, 0.95, 0.8))


## A bench (outside or in), seat along local x after turning by yaw.
func _bench(at: Vector3, yaw: float, outside := false) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var seat := _e("paint", OAK) if outside else _i("paint", OAK)
	var legs := _e("metal", IRON) if outside else _i("metal", IRON)
	_box(seat, at + basis * Vector3(0, 0.46, 0), Vector3(2.0, 0.07, 0.5), basis)
	_box(seat, at + basis * Vector3(0, 0.85, -0.24), Vector3(2.0, 0.4, 0.06), basis)
	for x in [-0.85, 0.85]:
		_box(legs, at + basis * Vector3(x, 0.23, 0), Vector3(0.07, 0.46, 0.48), basis)
	_collide(at + basis * Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 0.55), basis)


# --- the square ----------------------------------------------------------------------------------

func _square() -> void:
	var f: Dictionary = data["fountain"]
	var c := Vector3(f["at"][0], f["y"], f["at"][1])
	_begin(c, Transform3D.IDENTITY)
	var r: float = f["radius"]
	var sides := 8
	for i in range(sides):
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var mid := (a0 + a1) / 2.0
		var length := 2.0 * r * sin(PI / sides) + 0.2
		var p := c + Vector3(cos(mid), 0, sin(mid)) * r * cos(PI / sides)
		var basis := Basis(Vector3.UP, -mid + PI / 2.0)
		_solid(_e("stone", STONE), p + Vector3(0, 0.35, 0), Vector3(length, 1.1, 0.55), basis)
		_box(_e("stone", STONE_DARK), p + Vector3(0, 0.95, 0), Vector3(length + 0.1, 0.12, 0.75), basis)
	var water := _e("water", Color.WHITE)
	for i in range(sides):
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		_tri(water, c + Vector3(0, 0.62, 0), c + Vector3(cos(a1), 0, sin(a1)) * r * 0.95 + Vector3(0, 0.62, 0), c + Vector3(cos(a0), 0, sin(a0)) * r * 0.95 + Vector3(0, 0.62, 0))
	_prism(_e("stone", STONE), c, c + Vector3(0, 2.4, 0), 0.45, 8)
	_prism(_e("stone", STONE_DARK), c + Vector3(0, 1.5, 0), c + Vector3(0, 1.75, 0), 1.3, 8)
	_prism(_e("stone", STONE), c + Vector3(0, 2.4, 0), c + Vector3(0, 2.7, 0), 0.7, 8)
	_prism(_e("metal", BRASS), c + Vector3(0, 2.7, 0), c + Vector3(0, 3.6, 0), 0.18, 8)
	_box(_e("metal", BRASS), c + Vector3(0, 3.85, 0), Vector3(0.5, 0.5, 0.5), Basis(Vector3(1, 0, 1).normalized(), 0.7))
	_collide(c + Vector3(0, 1.4, 0), Vector3(0.9, 2.8, 0.9))
	for bench: Array in data.get("benches", []):
		var p := Vector3(bench[0], f["y"], bench[1])
		_begin(p, Transform3D.IDENTITY)
		_bench(p, deg_to_rad(float(bench[2])), true)


# --- the railway ---------------------------------------------------------------------------------

func _station(st: Dictionary) -> void:
	var tx: float = st["track_x"]
	var bed: float = st["bed"]
	var p: Array = st["platform"]
	var top: float = st["platform_top"]
	var z0: float = st["buffer_z"]
	var z1: float = st["portal_z"]
	_begin(Vector3(tx, bed, (z0 + z1) / 2.0), Transform3D.IDENTITY)
	# Platform: stone with a pale coping along the edge and a railing along the back.
	_solid(_e("stone", STONE_DARK), Vector3((p[0] + p[1]) / 2.0, (bed - 0.4 + top) / 2.0, (p[2] + p[3]) / 2.0),
		Vector3(p[1] - p[0], top - bed + 0.4, p[3] - p[2]))
	_box(_e("stone", Color(1.15, 1.12, 1.05)), Vector3(p[1] - 0.35, top + 0.02, (p[2] + p[3]) / 2.0), Vector3(0.7, 0.06, p[3] - p[2]))
	_box(_e("stone", STONE_DARK), Vector3((p[0] + p[1]) / 2.0, top - 0.3, p[3] + 0.6), Vector3(p[1] - p[0], 0.6, 1.2), Basis(Vector3.RIGHT, -0.5))
	var fence := _e("metal", IRON)
	var z := float(p[2]) + 0.5
	while z <= float(p[3]):
		_box(fence, Vector3(p[0] + 0.1, top + 0.6, z), Vector3(0.06, 1.2, 0.06))
		z += 2.0
	for y in [top + 0.5, top + 1.15]:
		_box(fence, Vector3(p[0] + 0.1, y, (p[2] + p[3]) / 2.0), Vector3(0.05, 0.05, p[3] - p[2]))
	_collide(Vector3(p[0] + 0.1, top + 0.7, (p[2] + p[3]) / 2.0), Vector3(0.2, 1.4, p[3] - p[2]))
	# Canopy over the platform's first stretch.
	var c: Array = st["canopy"]
	var c_mid := (float(c[2]) + float(c[3])) / 2.0
	var c_len := float(c[3]) - float(c[2])
	var post_top := top + 4.4
	var zz := float(c[2]) + 4.0
	while zz < float(c[3]):
		for x in [float(p[0]) + 2.0, float(p[1]) - 2.6]:
			_prism(_e("metal", Color(0.16, 0.26, 0.2)), Vector3(x, top, zz), Vector3(x, post_top, zz), 0.14, 8)
			_collide(Vector3(x, top + 2.2, zz), Vector3(0.3, 4.4, 0.3))
		zz += 8.0
	var width := float(p[1]) - float(p[0]) + 1.6
	for side in [-1.0, 1.0]:
		var mid := Vector3((p[0] + p[1]) / 2.0 + side * width / 4.0, post_top + 0.45, c_mid)
		var basis := Basis(Vector3.BACK, side * -0.22)
		_box(_e("slate", SLATE[0]), mid, Vector3(width / 2.0 + 0.2, 0.2, c_len), basis)
		_collide(mid, Vector3(width / 2.0 + 0.2, 0.2, c_len), basis)
	for x in [float(p[0]) - 0.8, float(p[1]) + 0.8]:
		_box(_e("paint", Color(0.85, 0.82, 0.7)), Vector3(x, post_top, c_mid), Vector3(0.06, 0.5, c_len))
	for bench: Array in st.get("benches", []):
		_bench(Vector3(bench[0], top, bench[1]), deg_to_rad(float(bench[2])), true)
	for sign: Dictionary in st.get("signs", []):
		var at := Vector3(sign["at"][0], sign["at"][1], sign["at"][2])
		_box(_e("metal", IRON), at + Vector3(0, 1.4, -1.5), Vector3(0.1, 2.8, 0.1))
		_box(_e("metal", IRON), at + Vector3(0, 1.4, 1.5), Vector3(0.1, 2.8, 0.1))
		_box(_e("paint", SIGN["station"]), at + Vector3(0, 2.6, 0), Vector3(0.1, 0.8, 3.4))
		_box(_e("paint", CREAM), at + Vector3(0, 2.6, 0), Vector3(0.06, 0.9, 3.5))
		_label(str(sign["key"]), at + Vector3(0.07, 2.6, 0), PI / 2.0, 52, CREAM)
		_label(str(sign["key"]), at + Vector3(-0.07, 2.6, 0), -PI / 2.0, 52, CREAM)
	# Track: ballast, sleepers, rails, from the buffer stop into the tunnel.
	_solid(_e("stone", Color(0.55, 0.52, 0.5)), Vector3(tx, bed + 0.1, (z0 - 1.0 + z1 + 2.0) / 2.0), Vector3(3.6, 0.3, z1 + 3.0 - z0))
	var sleepers := _e("paint", Color(0.22, 0.16, 0.11))
	z = z0 - 0.4
	while z < z1 + 2.0:
		_box(sleepers, Vector3(tx, bed + 0.31, z), Vector3(2.6, 0.13, 0.26))
		z += 0.7
	var g: float = st["gauge"]
	for side in [-1.0, 1.0]:
		_box(_e("metal", Color(0.35, 0.33, 0.32)), Vector3(tx + side * g / 2.0, bed + 0.45, (z0 - 0.5 + z1 + 2.0) / 2.0), Vector3(0.08, 0.16, z1 + 2.5 - z0))
	# Buffer stop.
	_solid(_e("paint", Color(0.3, 0.2, 0.12)), Vector3(tx, bed + 0.8, z0 - 0.6), Vector3(2.8, 1.3, 0.5))
	for side in [-1.0, 1.0]:
		_prism(_e("metal", IRON), Vector3(tx + side * 0.9, bed + 1.05, z0 - 0.35), Vector3(tx + side * 0.9, bed + 1.05, z0 + 0.15), 0.22, 8)
	_box(_e("ember", Color(0.9, 0.12, 0.08)), Vector3(tx, bed + 1.6, z0 - 0.6), Vector3(0.3, 0.3, 0.3))
	_portal(st, tx, bed, z1)
	_train(st, tx, bed)


func _portal(st: Dictionary, tx: float, bed: float, z1: float) -> void:
	var top: float = st["portal_top"]
	# Wide enough to close the cutting, which widens toward the top.
	var half := 9.0 + (top - bed) * 0.5
	var open_half := 3.0
	var spring := bed + 4.6
	var depth := 3.0
	var face := _e("stone", STONE)
	var zc := z1 + depth / 2.0
	_solid(face, Vector3(tx - (half + open_half) / 2.0, (bed + top) / 2.0, zc), Vector3(half - open_half, top - bed, depth))
	_solid(face, Vector3(tx + (half + open_half) / 2.0, (bed + top) / 2.0, zc), Vector3(half - open_half, top - bed, depth))
	# Arch: stacked courses whose inner edge follows a half circle.
	var crown := spring + open_half
	var steps := 6
	for k in range(steps):
		var ya := spring + open_half * k / steps
		var yb := spring + open_half * (k + 1) / steps
		var gap := open_half * sqrt(maxf(0.0, 1.0 - pow((ya + yb) / 2.0 - spring, 2) / (open_half * open_half)))
		for side in [-1.0, 1.0]:
			var w := open_half - gap
			if w > 0.01:
				_solid(face, Vector3(tx + side * (open_half - w / 2.0), (ya + yb) / 2.0, zc), Vector3(w, yb - ya, depth))
	_solid(face, Vector3(tx, (crown + top) / 2.0, zc), Vector3(2.0 * open_half, top - crown, depth))
	_box(_e("stone", STONE_DARK), Vector3(tx, top + 0.2, zc - 0.2), Vector3(2.0 * half + 0.6, 0.4, depth + 0.5))
	_box(_e("stone", STONE_DARK), Vector3(tx, crown + 0.25, z1 - 0.05), Vector3(2.0 * open_half + 0.9, 0.5, 0.2))
	# The dark of the tunnel (blocks the way in).
	_solid(_e("paint", Color(0.01, 0.01, 0.012)), Vector3(tx, (bed + crown) / 2.0, z1 + depth + 0.2), Vector3(2.0 * open_half, crown - bed, 0.4))


func _train(st: Dictionary, tx: float, bed: float) -> void:
	var green := Color(0.1, 0.3, 0.2)
	var deep := Color(0.07, 0.2, 0.14)
	var black := Color(0.06, 0.06, 0.07)
	var wheel_red := Color(0.4, 0.1, 0.08)
	var rail_top := bed + 0.53
	for v: Dictionary in st["train"]:
		var za: float = v["z"][0]
		var zb: float = v["z"][1]
		var mid := (za + zb) / 2.0
		_begin(Vector3(tx, bed, mid), Transform3D.IDENTITY)
		match str(v["kind"]):
			"engine":
				_box(_e("paint", black), Vector3(tx, rail_top + 1.15, mid), Vector3(2.5, 0.45, zb - za))
				_box(_e("paint", wheel_red), Vector3(tx, rail_top + 1.15, za + 0.15), Vector3(2.8, 0.6, 0.3))
				_prism(_e("paint", green), Vector3(tx, rail_top + 2.45, za + 1.6), Vector3(tx, rail_top + 2.45, za + 9.0), 1.05, 16)
				_prism(_e("paint", black), Vector3(tx, rail_top + 2.45, za + 0.4), Vector3(tx, rail_top + 2.45, za + 1.7), 1.12, 16)
				for zz in [za + 3.6, za + 6.2, za + 8.9]:
					_prism(_e("metal", BRASS), Vector3(tx, rail_top + 2.45, zz), Vector3(tx, rail_top + 2.45, zz + 0.12), 1.08, 16)
				_prism(_e("paint", black), Vector3(tx, rail_top + 3.3, za + 1.1), Vector3(tx, rail_top + 4.6, za + 1.1), 0.34, 10)
				_prism(_e("metal", BRASS), Vector3(tx, rail_top + 3.3, za + 5.0), Vector3(tx, rail_top + 3.95, za + 5.0), 0.42, 10)
				_box(_e("paint", green), Vector3(tx, rail_top + 2.75, za + 10.9), Vector3(2.8, 2.7, 3.4))
				_box(_e("slate", black), Vector3(tx, rail_top + 4.2, za + 10.9), Vector3(3.0, 0.2, 3.8))
				for side in [-1.0, 1.0]:
					_quad(_e("glow", Color.WHITE), Vector3(tx + side * 1.41, rail_top + 2.9, za + 9.8), Vector3(tx + side * 1.41, rail_top + 2.9, za + 10.8),
						Vector3(tx + side * 1.41, rail_top + 3.7, za + 10.8), Vector3(tx + side * 1.41, rail_top + 3.7, za + 9.8))
					for k in range(3):
						var wz := za + 4.8 + k * 2.1
						_prism(_e("paint", wheel_red), Vector3(tx + side * 0.82, rail_top + 0.95, wz), Vector3(tx + side * 1.02, rail_top + 0.95, wz), 0.95, 14)
					for wz in [za + 1.4, za + 2.8]:
						_prism(_e("paint", black), Vector3(tx + side * 0.82, rail_top + 0.5, wz), Vector3(tx + side * 1.0, rail_top + 0.5, wz), 0.5, 10)
					_prism(_e("metal", IRON), Vector3(tx + side * 0.9, rail_top + 1.15, za - 0.4), Vector3(tx + side * 0.9, rail_top + 1.15, za + 0.05), 0.2, 8)
					_box(_e("glow", Color.WHITE), Vector3(tx + side * 0.7, rail_top + 1.75, za + 0.1), Vector3(0.3, 0.3, 0.2))
				_collide(Vector3(tx, rail_top + 2.3, mid), Vector3(2.9, 4.6, zb - za))
			"tender":
				_box(_e("paint", black), Vector3(tx, rail_top + 1.0, mid), Vector3(2.5, 0.4, zb - za))
				_box(_e("paint", green), Vector3(tx, rail_top + 2.3, mid), Vector3(2.8, 2.2, zb - za - 0.2))
				_box(_e("stone", Color(0.12, 0.12, 0.13)), Vector3(tx, rail_top + 3.45, mid + 0.6), Vector3(2.4, 0.3, zb - za - 2.4), Basis(Vector3.RIGHT, 0.08))
				for side in [-1.0, 1.0]:
					for wz in [za + 1.2, mid, zb - 1.2]:
						_prism(_e("paint", black), Vector3(tx + side * 0.82, rail_top + 0.55, wz), Vector3(tx + side * 1.0, rail_top + 0.55, wz), 0.55, 10)
				_collide(Vector3(tx, rail_top + 1.9, mid), Vector3(2.9, 3.8, zb - za))
			_:
				var length := zb - za
				_box(_e("paint", black), Vector3(tx, rail_top + 1.0, mid), Vector3(2.4, 0.35, length))
				_box(_e("paint", deep), Vector3(tx, rail_top + 1.75, mid), Vector3(2.9, 1.3, length))
				_box(_e("paint", CREAM), Vector3(tx, rail_top + 3.05, mid), Vector3(2.9, 1.3, length))
				_box(_e("slate", Color(0.2, 0.2, 0.22)), Vector3(tx, rail_top + 3.85, mid), Vector3(2.8, 0.3, length + 0.1))
				_box(_e("slate", Color(0.2, 0.2, 0.22)), Vector3(tx, rail_top + 4.05, mid), Vector3(2.0, 0.2, length + 0.1))
				for side in [-1.0, 1.0]:
					var n := int(length / 2.0)
					for k in range(n):
						var wz := za + 1.2 + k * (length - 2.4) / maxf(1.0, n - 1)
						_quad(_e("glow", Color.WHITE), Vector3(tx + side * 1.46, rail_top + 2.6, wz - 0.55), Vector3(tx + side * 1.46, rail_top + 2.6, wz + 0.55),
							Vector3(tx + side * 1.46, rail_top + 3.4, wz + 0.55), Vector3(tx + side * 1.46, rail_top + 3.4, wz - 0.55))
					_box(_e("metal", BRASS), Vector3(tx + side * 1.46, rail_top + 2.42, mid), Vector3(0.03, 0.06, length - 0.4))
					for wz in [za + 1.6, za + 3.4, zb - 3.4, zb - 1.6]:
						_prism(_e("paint", black), Vector3(tx + side * 0.82, rail_top + 0.45, wz), Vector3(tx + side * 1.0, rail_top + 0.45, wz), 0.45, 10)
				_box(_e("paint", black), Vector3(tx, rail_top + 2.4, zb + 0.4), Vector3(1.6, 2.6, 0.9))
				_collide(Vector3(tx, rail_top + 2.2, mid), Vector3(2.95, 4.0, length))

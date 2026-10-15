class_name CastleExterior
extends Node3D
## The castle's exterior shell, built at runtime from levels/castle/exterior.json
## (tools/castle/exterior.py): roofs, spires, battlements, buttresses, chimneys,
## bartizans, corbels, foundations, slabs over exposed underground rooms, the outward
## stone facade, and the far-view stand-in (HLOD) with glowing windows.
##
## Everything is merged into a few meshes per material. The shell sits on render
## layers 1 and 11, so the moon lights it. Beyond [member detail_range] from the camera
## the castle's interior detail (walls, floors, furniture, lights…) is hidden and the
## HLOD boxes and window glows take over; the shell itself is always drawn.
## DayNightCycle dims the window glows by day (set_daylight).

const OUTDOOR_LAYER := 1 << 10
const DETAIL_CONTAINERS := ["Geometry", "Floors", "Walls", "Pillars", "Ceilings", "Stairs", "Torches", "Lights",
	"Furniture", "Doors", "Props", "Tomes", "Puzzles", "Collectibles", "Checkpoints"]

const NIGHT_GLOW := Color(1.0, 0.72, 0.38)
const DAY_GLOW := Color(0.2, 0.22, 0.26)

@export var data_path: String = "res://levels/castle/exterior.json"
## Interior detail is drawn up to this distance (m); the HLOD from a little before it.
@export var detail_range: float = 170.0
## Interior lights fade out from this distance (m) over 30 m.
@export var light_fade_begin: float = 90.0
## Interior lights stop casting shadows beyond this distance (m): near lights keep the
## shadows that stop them leaking through walls, far ones stop re-rendering shadow maps.
@export var shadow_fade: float = 32.0

var data: Dictionary = {}
var _stone: StandardMaterial3D
var _slate: StandardMaterial3D
var _glow: StandardMaterial3D
var _shapes: StaticBody3D


func _ready() -> void:
	if not FileAccess.file_exists(data_path):
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	_make_materials()
	_shapes = StaticBody3D.new()
	_shapes.name = "ShellCollision"
	add_child(_shapes)
	var stone := _surface()
	var slate := _surface()
	for r: Dictionary in data.get("roofs", []):
		_hip_roof(slate, r["rect"], r["base"], r["height"])
	for s: Dictionary in data.get("spires", []):
		_spire(slate, Vector3(s["centre"][0], s["base"], s["centre"][1]), s["half"], s["height"], 8)
		_box(stone, Vector3(s["centre"][0], s["base"] + 0.4, s["centre"][1]), Vector3(s["half"] * 2 + 0.6, 0.8, s["half"] * 2 + 0.6))
	for m: Array in data.get("merlons", []):
		_merlons(stone, m)
	for b: Dictionary in data.get("buttresses", []):
		_buttress(stone, b)
	for c: Array in data.get("chimneys", []):
		_box(stone, Vector3(c[0], c[1] + c[3] / 2.0, c[2]), Vector3(1.6, c[3], 2.4))
		_box(stone, Vector3(c[0], c[1] + c[3] + 0.2, c[2]), Vector3(2.0, 0.4, 2.8))
	for b: Array in data.get("bartizans", []):
		_bartizan(stone, slate, Vector3(b[0], b[1], b[2]))
	for c: Dictionary in data.get("corbels", []):
		_corbel(stone, c)
	for f: Array in data.get("foundations", []):
		_solid(stone, f)
	for c: Array in data.get("covers", []):
		_solid(stone, c)
	for q: Array in data.get("facade", []):
		_facade(stone, q)
	_commit(stone, _stone, "Stone")
	_commit(slate, _slate, "Roofs")
	_build_hlod()
	_apply_detail_ranges.call_deferred()


func _make_materials() -> void:
	_stone = StandardMaterial3D.new()
	_stone.albedo_texture = load("res://assets/materials/greybox_stone_albedo.png")
	_stone.albedo_color = Color(0.78, 0.74, 0.7)
	_stone.uv1_triplanar = true
	_stone.uv1_world_triplanar = true
	_stone.uv1_scale = Vector3(0.22, 0.22, 0.22)
	_stone.roughness = 0.95
	_stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	_slate = StandardMaterial3D.new()
	_slate.albedo_color = Color(0.17, 0.19, 0.24)
	_slate.roughness = 0.55
	_slate.metallic = 0.15
	_slate.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = NIGHT_GLOW
	_glow.cull_mode = BaseMaterial3D.CULL_DISABLED


## 0 = night (windows glow with candlelight), 1 = full day (dark panes against the sun).
func set_daylight(amount: float) -> void:
	if _glow != null:
		_glow.albedo_color = NIGHT_GLOW.lerp(DAY_GLOW, clampf(amount, 0.0, 1.0))


## A flat-shaded surface (every face keeps its own normal: crisp roof planes and stone edges).
func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


func _commit(st: SurfaceTool, material: Material, node_name: String) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = material
	mi.layers = 1 | OUTDOOR_LAYER
	add_child(mi)
	return mi


# --- shapes -------------------------------------------------------------------------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


func _box(st: SurfaceTool, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	var h := size / 2.0
	var p := []
	for z in [-h.z, h.z]:
		for y in [-h.y, h.y]:
			for x in [-h.x, h.x]:
				p.append(centre + basis * Vector3(x, y, z))
	# p index = x + 2y + 4z
	_quad(st, p[0], p[1], p[3], p[2])
	_quad(st, p[4], p[6], p[7], p[5])
	_quad(st, p[0], p[2], p[6], p[4])
	_quad(st, p[1], p[5], p[7], p[3])
	_quad(st, p[2], p[3], p[7], p[6])
	_quad(st, p[0], p[4], p[5], p[1])


func _solid(st: SurfaceTool, f: Array) -> void:
	var centre := Vector3((f[0] + f[1]) / 2.0, (f[4] + f[5]) / 2.0, (f[2] + f[3]) / 2.0)
	var size := Vector3(f[1] - f[0], f[5] - f[4], f[3] - f[2])
	_box(st, centre, size)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = centre
	_shapes.add_child(cs)


func _hip_roof(st: SurfaceTool, rect: Array, base: float, height: float) -> void:
	var x0: float = rect[0]
	var x1: float = rect[1]
	var z0: float = rect[2]
	var z1: float = rect[3]
	var w := x1 - x0
	var d := z1 - z0
	var top := base + height
	var a := Vector3(x0, base, z0)
	var b := Vector3(x1, base, z0)
	var c := Vector3(x1, base, z1)
	var e := Vector3(x0, base, z1)
	if w >= d:
		var r0 := Vector3(x0 + d / 2.0, top, (z0 + z1) / 2.0)
		var r1 := Vector3(x1 - d / 2.0, top, (z0 + z1) / 2.0)
		_quad(st, a, b, r1, r0)
		_quad(st, c, e, r0, r1)
		_tri(st, e, a, r0)
		_tri(st, b, c, r1)
	else:
		var r0 := Vector3((x0 + x1) / 2.0, top, z0 + w / 2.0)
		var r1 := Vector3((x0 + x1) / 2.0, top, z1 - w / 2.0)
		_quad(st, b, c, r1, r0)
		_quad(st, e, a, r0, r1)
		_tri(st, a, b, r0)
		_tri(st, c, e, r1)
	# Soffit under the eaves so the roof never shows its inside from below.
	_quad(st, a, e, c, b)


func _spire(st: SurfaceTool, base: Vector3, half: float, height: float, sides: int) -> void:
	var tip := base + Vector3(0, height, 0)
	var ring: Array[Vector3] = []
	for i in range(sides):
		var ang := TAU * i / sides + PI / sides
		ring.append(base + Vector3(cos(ang), 0, sin(ang)) * half * 1.08)
	for i in range(sides):
		_tri(st, ring[i], ring[(i + 1) % sides], tip)
		_tri(st, ring[(i + 1) % sides], ring[i], base)


func _merlons(st: SurfaceTool, m: Array) -> void:
	var a := Vector3(m[0], m[4], m[1])
	var b := Vector3(m[2], m[4], m[3])
	var dir := (b - a)
	var length := dir.length()
	if length < 0.5:
		return
	dir /= length
	var side: String = m[5]
	var outward := Vector3.ZERO
	match side:
		"w": outward = Vector3(-1, 0, 0)
		"e": outward = Vector3(1, 0, 0)
		"n": outward = Vector3(0, 0, -1)
		_: outward = Vector3(0, 0, 1)
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var mid := (a + b) / 2.0
	# Parapet wall on the wall line, merlons on top.
	_box(st, mid + Vector3(0, 0.55, 0), Vector3(length, 1.1, 0.5), basis)
	var n := int(length / 1.8)
	for i in range(n):
		var t := (i + 0.5) * length / n
		_box(st, a + dir * t + Vector3(0, 1.1 + 0.6, 0), Vector3(1.0, 1.2, 0.5), basis)
	# Machicolation-ish band just outside the wall top.
	_box(st, mid + outward * 0.35 + Vector3(0, -0.25, 0), Vector3(length, 0.5, 0.3), basis)


func _buttress(st: SurfaceTool, b: Dictionary) -> void:
	var p := Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
	var n := Vector3(b["normal"][0], 0, b["normal"][1])
	var h: float = b["height"]
	var along := Vector3(n.z, 0, -n.x)
	var basis := Basis(along, Vector3.UP, n)
	_box(st, p + n * 1.1 + Vector3(0, h * 0.3, 0), Vector3(1.5, h * 0.6, 2.2), basis)
	_box(st, p + n * 0.75 + Vector3(0, h * 0.75, 0), Vector3(1.2, h * 0.5, 1.5), basis)
	_box(st, p + n * 0.5 + Vector3(0, h + 0.4, 0), Vector3(0.9, 0.8, 1.0), basis)


func _bartizan(st: SurfaceTool, slate: SurfaceTool, p: Vector3) -> void:
	var r := 1.5
	var sides := 10
	var y0 := p.y - 3.5
	var y1 := p.y + 2.5
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in range(sides):
		var a := TAU * i / sides
		var o := Vector3(cos(a), 0, sin(a)) * r
		ring0.append(Vector3(p.x, y0, p.z) + o)
		ring1.append(Vector3(p.x, y1, p.z) + o)
	var foot := Vector3(p.x, y0 - 2.0, p.z)
	for i in range(sides):
		var j := (i + 1) % sides
		_quad(st, ring0[i], ring0[j], ring1[j], ring1[i])
		_tri(st, ring0[j], ring0[i], foot)
	_spire(slate, Vector3(p.x, y1, p.z), r, 5.0, sides)


func _corbel(st: SurfaceTool, c: Dictionary) -> void:
	var p := Vector3(c["pos"][0], c["pos"][1], c["pos"][2])
	var n := Vector3(c["normal"][0], 0, c["normal"][1])
	var along := Vector3(n.z, 0, -n.x)
	var basis := Basis(along, Vector3.UP, n)
	for k in range(3):
		_box(st, p - n * (0.2 + k * 0.35) + Vector3(0, -0.5 - k * 0.9, 0), Vector3(0.8, 0.9, 1.2 - k * 0.35), basis)


func _facade(st: SurfaceTool, q: Array) -> void:
	var axis: String = q[0]
	var c: float = q[1]
	var lo: float = q[2]
	var hi: float = q[3]
	var y0: float = q[4]
	var y1: float = q[5]
	if axis == "z":
		_quad(st, Vector3(c, y0, lo), Vector3(c, y0, hi), Vector3(c, y1, hi), Vector3(c, y1, lo))
	else:
		_quad(st, Vector3(lo, y0, c), Vector3(hi, y0, c), Vector3(hi, y1, c), Vector3(lo, y1, c))


# --- far view -----------------------------------------------------------------------------

func _build_hlod() -> void:
	var boxes := _surface()
	for h: Array in data.get("hlod", []):
		_box(boxes, Vector3((h[0] + h[1]) / 2.0, (h[4] + h[5]) / 2.0, (h[2] + h[3]) / 2.0),
			Vector3(h[1] - h[0] - 0.1, h[5] - h[4], h[3] - h[2] - 0.1))
	var glows := _surface()
	for w: Array in data.get("windows", []):
		if w.size() > 5 and not w[5]:
			continue
		var c: float = w[1]
		var m: float = w[2]
		var y: float = w[3]
		if w[0] == "z":
			_quad(glows, Vector3(c, y - 1.3, m - 0.8), Vector3(c, y - 1.3, m + 0.8), Vector3(c, y + 1.3, m + 0.8), Vector3(c, y + 1.3, m - 0.8))
		else:
			_quad(glows, Vector3(m - 0.8, y - 1.3, c), Vector3(m + 0.8, y - 1.3, c), Vector3(m + 0.8, y + 1.3, c), Vector3(m - 0.8, y + 1.3, c))
	for pair in [[boxes, _stone, "Hlod"], [glows, _glow, "HlodWindows"]]:
		var mi := _commit(pair[0], pair[1], pair[2])
		mi.visibility_range_begin = detail_range - 10.0
		mi.visibility_range_begin_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _apply_detail_ranges() -> void:
	var castle := get_parent()
	for c in DETAIL_CONTAINERS:
		var node := castle.get_node_or_null(c)
		if node != null:
			_detail_range(node)


func _detail_range(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			var g := child as GeometryInstance3D
			if g.visibility_range_end == 0.0:
				g.visibility_range_end = detail_range
				g.visibility_range_end_margin = 10.0
		elif child is OmniLight3D or child is SpotLight3D:
			var l := child as Light3D
			l.distance_fade_enabled = true
			l.distance_fade_begin = light_fade_begin
			l.distance_fade_length = 30.0
			l.distance_fade_shadow = shadow_fade
		_detail_range(child)

class_name Terrain
extends Node3D
## The grounds' terrain, water and flora, built at runtime from the data that
## tools/grounds writes to levels/grounds/ (terrain.json, height.bin, splat.png,
## scatter.bin). Nothing here is hand-authored: regenerate the castle to change it.
##
## Rendering: the map is cut into chunks of [member chunk_cells] cells. Every chunk
## has a coarse mesh (one vertex per [member far_step] cells); chunks within
## [member detail_radius] of the local player swap to a full-resolution mesh. Skirts
## along chunk borders hide the cracks between the two. Collision (HeightMapShape3D)
## and tree trunks only exist within [member collision_radius] of a local player:
## remote players are interpolated and need none. Flora is drawn with one
## MultiMesh per kind per flora cell, each with a visibility range.
##
## Everything here sits on render layer 11 ("outdoor"), the only layer the moon lights.
## The node also guards local players: below the water it carries them back to the
## last dry ground they stood on, and it lowers their kill height to the terrain floor.

const OUTDOOR_LAYER := 1 << 10
const SHADER := preload("res://gameplay/world/terrain.gdshader")
const WATER_SHADER := preload("res://gameplay/world/water.gdshader")

@export var data_path: String = ""
@export var chunk_cells: int = 32
@export var far_step: int = 4
@export var detail_radius: float = 240.0
@export var collision_radius: float = 120.0
@export var flora_cell: float = 128.0
## Metres of water above the feet before the guard carries a player back to the shore.
@export var deep_water: float = 1.3
## Chunks rebuilt per physics frame while streaming.
@export var builds_per_frame: int = 2

var origin := Vector2.ZERO
var spacing: float = 2.0
var size_x: int = 0
var size_z: int = 0
var h_min: float = 0.0
var h_scale: float = 1.0
var water_level: float = -1000.0
var meta: Dictionary = {}

var _q: PackedInt32Array
var _holes: PackedByteArray         # per cell (size_x - 1) x (size_z - 1): 1 = no ground (a castle floor is there)
var _material: ShaderMaterial
var _chunks: Dictionary = {}        # Vector2i -> {far: MeshInstance3D, near: MeshInstance3D, body: StaticBody3D}
var _chunks_x: int = 0
var _chunks_z: int = 0
var _flora_cells: Dictionary = {}   # Vector2i -> {trees: PackedVector3Array (x, z, radius) , body: StaticBody3D}
var _safe: Dictionary = {}          # player instance id -> last dry, grounded position
var _queue: Array[Vector2i] = []
var _focus := Vector3(INF, 0, INF)


func _ready() -> void:
	if data_path.is_empty() or not FileAccess.file_exists(data_path):
		push_warning("Terrain: no data at %s" % data_path)
		return
	meta = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	origin = Vector2(meta["origin"][0], meta["origin"][1])
	spacing = meta["spacing"]
	size_x = int(meta["size"][0])
	size_z = int(meta["size"][1])
	h_min = meta["height_range"][0]
	h_scale = (float(meta["height_range"][1]) - h_min) / 65535.0
	water_level = meta["water_level"]
	_load_heights(meta["height"])
	if meta.has("holes"):
		_holes = FileAccess.get_file_as_bytes(meta["holes"]).decompress(int(meta["holes_bytes"]), FileAccess.COMPRESSION_GZIP)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var splat: Texture2D = load(meta["splat"])
	_material.set_shader_parameter("splat", splat)
	_material.set_shader_parameter("splat_origin", origin)
	_material.set_shader_parameter("splat_size", Vector2(splat.get_width(), splat.get_height()) * float(meta["splat_spacing"]))
	_material.set_shader_parameter("rock_albedo", load("res://assets/materials/greybox_stone_albedo.png"))
	_chunks_x = int(ceil(float(size_x - 1) / chunk_cells))
	_chunks_z = int(ceil(float(size_z - 1) / chunk_cells))
	for cz in range(_chunks_z):
		for cx in range(_chunks_x):
			var key := Vector2i(cx, cz)
			var far := _make_mesh_instance(_chunk_mesh(key, far_step), "Far_%d_%d" % [cx, cz])
			_chunks[key] = {"far": far, "near": null, "body": null}
	_build_water()
	_build_flora()
	_apply_outdoor_layer(get_parent().get_node_or_null("Landmarks"))


# --- sampling -----------------------------------------------------------------------------

func _load_heights(path: String) -> void:
	# Quantised heights as gzip-compressed little-endian int32 (tools/grounds/export.py).
	var packed := FileAccess.get_file_as_bytes(path)
	_q = packed.decompress(int(meta["height_bytes"]), FileAccess.COMPRESSION_GZIP).to_int32_array()


func sample(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, size_x - 1)
	iz = clampi(iz, 0, size_z - 1)
	return h_min + _q[iz * size_x + ix] * h_scale


## Terrain height under world (x, z), bilinear.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / spacing, 0.0, size_x - 1.001)
	var fz := clampf((z - origin.y) / spacing, 0.0, size_z - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(sample(ix, iz), sample(ix + 1, iz), tx)
	var b := lerpf(sample(ix, iz + 1), sample(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)


## The quantised height grid as an RGBA8 image (R low byte, G high byte of each
## sample; metres = h_min + q * h_scale), for the map's relief. Null without data.
func height_image() -> Image:
	if _q.size() != size_x * size_z or _q.is_empty():
		return null
	return Image.create_from_data(size_x, size_z, false, Image.FORMAT_RGBA8, _q.to_byte_array())


## XZ extent covered by the height grid.
func extent() -> Rect2:
	return Rect2(origin, Vector2(size_x - 1, size_z - 1) * spacing)


func is_hole(ix: int, iz: int) -> bool:
	if _holes.is_empty() or ix < 0 or iz < 0 or ix >= size_x - 1 or iz >= size_z - 1:
		return false
	return _holes[iz * (size_x - 1) + ix] != 0


## Is there terrain at world (x, z)? False where a castle floor replaces the ground.
func has_ground(x: float, z: float) -> bool:
	return not is_hole(int((x - origin.x) / spacing), int((z - origin.y) / spacing))


func _block_is_hole(ix0: int, iz0: int, step: int) -> bool:
	for j in range(step):
		for i in range(step):
			if not is_hole(ix0 + i, iz0 + j):
				return false
	return true


func _chunk_has_holes(key: Vector2i) -> bool:
	return not _block_free(key.x * chunk_cells, key.y * chunk_cells, chunk_cells)


func _block_free(ix0: int, iz0: int, n: int) -> bool:
	if _holes.is_empty():
		return true
	for j in range(n):
		var row := (iz0 + j) * (size_x - 1)
		for i in range(n):
			var ix := ix0 + i
			if iz0 + j < size_z - 1 and ix < size_x - 1 and _holes[row + ix] != 0:
				return false
	return true


func is_inside(x: float, z: float) -> bool:
	return x >= origin.x and z >= origin.y and x <= origin.x + (size_x - 1) * spacing and z <= origin.y + (size_z - 1) * spacing


# --- meshes -------------------------------------------------------------------------------

func _chunk_mesh(key: Vector2i, step: int) -> ArrayMesh:
	var ix0 := key.x * chunk_cells
	var iz0 := key.y * chunk_cells
	var cells := chunk_cells / step
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var row := cells + 1
	for j in range(row):
		for i in range(row):
			var gx := ix0 + i * step
			var gz := iz0 + j * step
			var h := sample(gx, gz)
			verts.append(Vector3(origin.x + gx * spacing, h, origin.y + gz * spacing))
			var dx := sample(gx + step, gz) - sample(gx - step, gz)
			var dz := sample(gx, gz + step) - sample(gx, gz - step)
			normals.append(Vector3(-dx, 2.0 * step * spacing, -dz).normalized())
	for j in range(cells):
		for i in range(cells):
			if _block_is_hole(ix0 + i * step, iz0 + j * step, step):
				continue
			var a := j * row + i
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	# Skirts: hang the border down so neighbours at another resolution never show a crack,
	# only as deep as that crack can be (skirt_depth) and never along holes: a deeper skirt
	# hung through the cellars under the castle as a dark curtain across their corridors.
	var border: Array[int] = []
	for i in range(row):
		border.append(i)
	for j in range(1, row):
		border.append(j * row + cells)
	for i in range(cells - 1, -1, -1):
		border.append(cells * row + i)
	for j in range(cells - 1, 0, -1):
		border.append(j * row)
	border.append(0)
	for k in range(border.size() - 1):
		var t0 := border[k]
		var t1 := border[k + 1]
		var i0 := t0 % row
		var j0 := t0 / row
		var i1 := t1 % row
		var j1 := t1 / row
		var bi := mini(mini(i0, i1), cells - 1)
		var bj := mini(mini(j0, j1), cells - 1)
		if _block_is_hole(ix0 + bi * step, iz0 + bj * step, step):
			continue
		var depth := skirt_depth(ix0 + i0 * step, iz0 + j0 * step, ix0 + i1 * step, iz0 + j1 * step)
		var b0 := verts.size()
		verts.append(verts[t0] - Vector3(0, depth, 0))
		verts.append(verts[t1] - Vector3(0, depth, 0))
		normals.append(normals[t0])
		normals.append(normals[t1])
		indices.append_array([t0, b0, t1, t1, b0, b0 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## How far a skirt hangs below the border edge from grid point (gx0, gz0) to (gx1, gz1):
## the widest crack possible there, i.e. how far the full-resolution heights stray from
## the coarse mesh's straight edge over the coarse segment holding it, plus a margin.
## Both neighbours compute the same depth for their shared edge.
func skirt_depth(gx0: int, gz0: int, gx1: int, gz1: int) -> float:
	var along_x := gz0 == gz1
	var lo := mini(gx0, gx1) if along_x else mini(gz0, gz1)
	var c0 := floori(float(lo) / far_step) * far_step
	var h0 := sample(c0, gz0) if along_x else sample(gx0, c0)
	var h1 := sample(c0 + far_step, gz0) if along_x else sample(gx0, c0 + far_step)
	var gap := 0.0
	for s in range(1, far_step):
		var h := sample(c0 + s, gz0) if along_x else sample(gx0, c0 + s)
		gap = maxf(gap, absf(h - lerpf(h0, h1, float(s) / far_step)))
	return gap + 0.3


func _make_mesh_instance(mesh: Mesh, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _material
	mi.layers = OUTDOOR_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _chunk_centre(key: Vector2i) -> Vector3:
	var half := chunk_cells * spacing * 0.5
	return Vector3(origin.x + key.x * chunk_cells * spacing + half, 0, origin.y + key.y * chunk_cells * spacing + half)


func _make_collision(key: Vector2i) -> StaticBody3D:
	var ix0 := key.x * chunk_cells
	var iz0 := key.y * chunk_cells
	var row := chunk_cells + 1
	if _chunk_has_holes(key):
		return _make_hole_collision(key)
	var data := PackedFloat32Array()
	data.resize(row * row)
	for j in range(row):
		for i in range(row):
			data[j * row + i] = sample(ix0 + i, iz0 + j)
	var shape := HeightMapShape3D.new()
	shape.map_width = row
	shape.map_depth = row
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(spacing, 1, spacing)
	body.add_child(cs)
	var centre := _chunk_centre(key)
	body.position = Vector3(centre.x, 0, centre.z)
	add_child(body)
	return body


## Chunks under the castle's edge: triangle collision without the holes.
func _make_hole_collision(key: Vector2i) -> StaticBody3D:
	var ix0 := key.x * chunk_cells
	var iz0 := key.y * chunk_cells
	var faces := PackedVector3Array()
	for j in range(chunk_cells):
		for i in range(chunk_cells):
			var gx := ix0 + i
			var gz := iz0 + j
			if is_hole(gx, gz):
				continue
			var p00 := Vector3(origin.x + gx * spacing, sample(gx, gz), origin.y + gz * spacing)
			var p10 := Vector3(origin.x + (gx + 1) * spacing, sample(gx + 1, gz), origin.y + gz * spacing)
			var p01 := Vector3(origin.x + gx * spacing, sample(gx, gz + 1), origin.y + (gz + 1) * spacing)
			var p11 := Vector3(origin.x + (gx + 1) * spacing, sample(gx + 1, gz + 1), origin.y + (gz + 1) * spacing)
			faces.append_array([p00, p10, p01, p10, p11, p01])
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 0
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	add_child(body)
	return body


# --- streaming ----------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _q.is_empty():
		return
	var players := get_tree().get_nodes_in_group("local_player")
	if players.is_empty():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_stream(cam.global_position)
		return
	for p in players:
		if p is CharacterBody3D:
			_guard(p as CharacterBody3D)
	_stream((players[0] as Node3D).global_position)


## Bring detail and collision to `focus` (also used by tests and tools).
func focus_on(focus: Vector3, immediate: bool = false) -> void:
	_focus = Vector3(INF, 0, INF)
	_stream(focus)
	if immediate:
		while not _queue.is_empty():
			_build_next()


func _stream(focus: Vector3) -> void:
	if not _queue.is_empty():
		for i in range(builds_per_frame):
			_build_next()
	if focus.distance_to(_focus) < 16.0:
		return
	_focus = focus
	for key: Vector2i in _chunks:
		var c: Dictionary = _chunks[key]
		var d := Vector2(focus.x, focus.z).distance_to(Vector2(_chunk_centre(key).x, _chunk_centre(key).z))
		var want_near := d < detail_radius
		var want_body := d < collision_radius + chunk_cells * spacing
		if (want_near and c["near"] == null) or (want_body and c["body"] == null):
			if not _queue.has(key):
				_queue.append(key)
		if not want_near and c["near"] != null:
			(c["near"] as Node).queue_free()
			c["near"] = null
			(c["far"] as MeshInstance3D).visible = true
		if not want_body and c["body"] != null:
			(c["body"] as Node).queue_free()
			c["body"] = null
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(focus.x, focus.z).distance_squared_to(Vector2(_chunk_centre(a).x, _chunk_centre(a).z)) \
			< Vector2(focus.x, focus.z).distance_squared_to(Vector2(_chunk_centre(b).x, _chunk_centre(b).z)))
	for cell: Vector2i in _flora_cells:
		var f: Dictionary = _flora_cells[cell]
		var centre: Vector2 = f["centre"]
		var near_flora := Vector2(focus.x, focus.z).distance_to(centre) < collision_radius + flora_cell
		if near_flora and f["body"] == null:
			f["body"] = _make_trunks(f["trees"])
		elif not near_flora and f["body"] != null:
			(f["body"] as Node).queue_free()
			f["body"] = null


func _build_next() -> void:
	if _queue.is_empty():
		return
	var key: Vector2i = _queue.pop_front()
	var c: Dictionary = _chunks[key]
	var d := Vector2(_focus.x, _focus.z).distance_to(Vector2(_chunk_centre(key).x, _chunk_centre(key).z))
	if c["near"] == null and d < detail_radius:
		c["near"] = _make_mesh_instance(_chunk_mesh(key, 1), "Near_%d_%d" % [key.x, key.y])
		(c["far"] as MeshInstance3D).visible = false
	if c["body"] == null and d < collision_radius + chunk_cells * spacing:
		c["body"] = _make_collision(key)


## The water guard and the kill height for one local player.
func _guard(body: CharacterBody3D) -> void:
	var handler: RespawnHandler = body.get_meta("respawn_handler") if body.has_meta("respawn_handler") else null
	if handler != null:
		handler.kill_height = minf(handler.kill_height, h_min - 15.0)
	var pos := body.global_position
	if not is_inside(pos.x, pos.z):
		return
	var ground := height_at(pos.x, pos.z)
	var id := body.get_instance_id()
	var in_water := pos.y < water_level - deep_water and ground < water_level - deep_water
	if body.is_on_floor() and pos.y > water_level + 0.2 and absf(pos.y - ground) < 1.5:
		_safe[id] = pos
	elif in_water and _safe.has(id):
		body.velocity = Vector3.ZERO
		body.global_position = _safe[id] + Vector3(0, 0.3, 0)
		GameEvents.notify(tr("NOTIFY_DEEP_WATER"), 3.0, ToastStack.Kind.WARNING)


# --- water --------------------------------------------------------------------------------

func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	return m


func _build_water() -> void:
	var w := (size_x - 1) * spacing
	var d := (size_z - 1) * spacing
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, d)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	var lake := MeshInstance3D.new()
	lake.name = "Water"
	lake.mesh = plane
	lake.material_override = _water_material()
	lake.position = Vector3(origin.x + w / 2, water_level, origin.y + d / 2)
	lake.layers = OUTDOOR_LAYER
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	for river: Dictionary in meta.get("rivers", []):
		var pts: Array = river["points"]
		if pts.size() < 2:
			continue
		var half: float = river["width"] * 0.5
		var verts := PackedVector3Array()
		var indices := PackedInt32Array()
		for k in range(pts.size()):
			var p := Vector3(pts[k][0], pts[k][1], pts[k][2])
			var q := Vector3(pts[mini(k + 1, pts.size() - 1)][0], 0, pts[mini(k + 1, pts.size() - 1)][2])
			var r := Vector3(pts[maxi(k - 1, 0)][0], 0, pts[maxi(k - 1, 0)][2])
			var dir := (q - r)
			dir.y = 0
			dir = dir.normalized()
			var side := Vector3(-dir.z, 0, dir.x) * half
			verts.append(p - side)
			verts.append(p + side)
			if k > 0:
				var a := (k - 1) * 2
				indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = indices
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "River_%s" % river["id"]
		mi.mesh = mesh
		mi.material_override = _water_material()
		mi.layers = OUTDOOR_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- flora --------------------------------------------------------------------------------

const FLORA_RANGE := {"conifer": 700.0, "broadleaf": 650.0, "bush": 160.0, "rock": 320.0}
const TRUNK_RADIUS := {"conifer": 0.35, "broadleaf": 0.45}


func _build_flora() -> void:
	if not meta.has("scatter"):
		return
	var floats := FileAccess.get_file_as_bytes(meta["scatter"]).to_float32_array()
	var kinds: Dictionary = meta["scatter_kinds"]
	for kind: String in kinds:
		var start: int = kinds[kind][0]
		var count: int = kinds[kind][1]
		var mesh := FloraMeshes.mesh_for(kind)
		var groups: Dictionary = {}
		for i in range(count):
			var o := start + i * 5
			var cell := Vector2i(int(floor(floats[o] / flora_cell)), int(floor(floats[o + 2] / flora_cell)))
			if not groups.has(cell):
				groups[cell] = []   # Array, not a packed array: packed arrays are copied on read
			(groups[cell] as Array).append(o)
		for cell: Vector2i in groups:
			var offs: Array = groups[cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = offs.size()
			for k in range(offs.size()):
				var o: int = offs[k]
				var s := floats[o + 4]
				var basis := Basis(Vector3.UP, floats[o + 3]).scaled(Vector3(s, s, s))
				mm.set_instance_transform(k, Transform3D(basis, Vector3(floats[o], floats[o + 1] - 0.15, floats[o + 2])))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Flora_%s_%d_%d" % [kind, cell.x, cell.y]
			mmi.multimesh = mm
			mmi.layers = OUTDOOR_LAYER
			mmi.visibility_range_end = FLORA_RANGE.get(kind, 300.0)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			if TRUNK_RADIUS.has(kind):
				if not _flora_cells.has(cell):
					_flora_cells[cell] = {"trees": PackedVector4Array(), "body": null,
						"centre": Vector2((cell.x + 0.5) * flora_cell, (cell.y + 0.5) * flora_cell)}
				var trees: PackedVector4Array = _flora_cells[cell]["trees"]
				for o in offs:
					trees.append(Vector4(floats[o], floats[o + 1], floats[o + 2], TRUNK_RADIUS[kind] * floats[o + 4]))
				_flora_cells[cell]["trees"] = trees


func _make_trunks(trees: PackedVector4Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for t in trees:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(0.25, t.w)
		cyl.height = 6.0
		cs.shape = cyl
		cs.position = Vector3(t.x, t.y + 2.8, t.z)
		body.add_child(cs)
	add_child(body)
	return body


func _apply_outdoor_layer(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is VisualInstance3D:
			(child as VisualInstance3D).layers |= OUTDOOR_LAYER
		_apply_outdoor_layer(child)

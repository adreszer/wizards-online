@tool
class_name WallWindow
extends StaticBody3D
## A 4 × 4 m wall module (the wall_plain stone) with a window set into it. The
## window scene's WindowFrame outline drives everything: the stone shader cuts
## the opening (wall_stone_opening.gdshader, per-instance uniforms), a stone
## reveal lines the cut through the wall's thickness, and the window sits on
## the wall's centre plane, so from either side it reads as set into the stone.
## The window's +Z face looks toward the module's +Z side; the generator turns
## the module so that side faces the room.
##
## Windows whose model has open lights (`WindowFrame.glass`) get a glass pane
## filling the opening on the wall's centre plane. Generated children are
## rebuilt on ready and never saved. The glass is opaque, so the module keeps a
## full occluder and full collision like a plain wall.
##
## Glazed windows also get a fake light shaft in the game (not in the editor): the
## open sides of a prism from the opening into the room, slanted along the sun's (or
## the moon's) direction in the shader, drawn additive with one shared shader material.
## Only windows the light shines into show a shaft. No real light and no shadow, so it
## costs one transparent draw per SHAFT_CELL cell within SHAFT_RANGE (the shafts of a
## level are batched into MultiMeshes) and nothing of the light budget.
## set_daylight makes it warm daylight by day and a faint blue moonbeam at night;
## set_shaft_light (DayNightCycle) aims it.

@export var window_scene: PackedScene = preload("res://objects/environment/windows/window_gothic_iron.tscn"):
	set(value):
		window_scene = value
		_rebuild()
## Height of the window's bottom above the module's bottom.
@export var sill_height: float = 1.0:
	set(value):
		sill_height = value
		_rebuild()
@export var module_width: float = 4.0
@export var module_height: float = 4.0
## The reveal spans the wall's thickness (stone faces at about ±0.16 m, relief to ±0.175).
@export var reveal_depth: float = 0.35
@export var backing_depth: float = 0.26
@export var occluder: bool = true

const ARC_SEGMENTS := 12
const BACKING_CLEARANCE := 0.03

const GLASS_NIGHT_EMISSION := Color(0.14, 0.19, 0.28)
const GLASS_DAY_EMISSION := Color(0.62, 0.68, 0.74)
## Daylit panes' emission energy with global illumination on (1.5 without).
const GLASS_DAY_ENERGY_GI := 3.0

static var _reveal_material: StandardMaterial3D
static var _glass_material: StandardMaterial3D
static var _shaft_material: ShaderMaterial

const SHAFT_SHADER := preload("res://objects/environment/modular/light_shaft.gdshader")
## A shaft drops this far below its window (metres), and reaches at most MAX_REACH
## along the light (a low sun gives long, flat shafts).
const SHAFT_DROP := 3.6
const SHAFT_MAX_REACH := 7.0
## The far end of the shaft is this much wider than the opening (the light spreads).
const SHAFT_SPREAD := 1.25
## A cell of shafts is drawn out to this distance from the camera (fading out over the last 6 m).
const SHAFT_RANGE := 40.0
const SHAFT_DAY := Color(1.0, 0.9, 0.72)
const SHAFT_NIGHT := Color(0.55, 0.65, 1.0)
## Shaft strength at full daylight and at night (moonlight).
const SHAFT_DAY_STRENGTH := 0.16
const SHAFT_NIGHT_STRENGTH := 0.035


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or window_scene == null:
		return
	for child in get_children():
		if child.has_meta("wall_window_generated"):
			remove_child(child)
			child.queue_free()
	var window := window_scene.instantiate() as Node3D
	window.position = Vector3(0.0, sill_height, 0.0)
	_add_generated(window)
	var frame := window as WindowFrame
	var o := frame.opening() if frame else Vector4.ZERO
	var arches := frame.layout() if frame else Vector2(1.0, 0.0)
	o.y += sill_height
	o.z += sill_height
	o.w += sill_height
	_cut_wall(o, arches)
	if o.x <= 0.0:
		return
	var segs := outline(o, arches)
	_add_generated(_build_reveal(segs))
	if frame.glass:
		_add_generated(_build_glass(segs))
		if not Engine.is_editor_hint() and not shafts_disabled:
			_queue_shaft(segs)
	_add_backing(o, arches)
	if occluder and not Engine.is_editor_hint():
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = Vector3(module_width - 0.1, module_height - 0.1, 0.2)
		occ.occluder = box
		occ.position = Vector3(0.0, module_height / 2.0, 0.0)
		_add_generated(occ)


func _add_generated(node: Node) -> void:
	node.set_meta("wall_window_generated", true)
	add_child(node)


## Hands the opening to every stone mesh of the wall model, in module space.
func _cut_wall(o: Vector4, arches: Vector2) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative(mi as Node3D)
		mi.set_instance_shader_parameter("mesh_scale", xf.basis.get_scale())
		mi.set_instance_shader_parameter("mesh_offset", xf.origin)
		mi.set_instance_shader_parameter("opening", o)
		mi.set_instance_shader_parameter("arches", arches)


func _relative(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Outline of the opening as segments [p0, n0, p1, n1] (counter-clockwise from
## the bottom left) with the inward normal at each end. Arc points carry the
## radial normal so curved reveals shade smoothly; corners are duplicated with
## each side's normal. Neighbouring arches meet where their arcs cross, or on
## the springing line (with a short flat soffit) when they don't reach.
static func outline(o: Vector4, arches: Vector2) -> Array:
	var w := o.x
	var b := o.y
	var s := o.z
	var h := o.w - s
	var c := (h * h - w * w) / (2.0 * w)
	var r := w + c
	var n := int(arches.x)
	var pitch := arches.y
	var half_total := w + pitch * (n - 1) / 2.0
	var top := atan2(h, c)
	# Angle (from the springing line) where an arc meets its neighbour's.
	var meet := 0.0
	if n > 1 and pitch / 2.0 < w:
		var dx := pitch / 2.0 + c
		meet = asin(sqrt(maxf(r * r - dx * dx, 0.0)) / r)
	var segs: Array = []
	segs.append([Vector2(-half_total, b), Vector2.UP, Vector2(half_total, b), Vector2.UP])
	segs.append([Vector2(half_total, b), Vector2.LEFT, Vector2(half_total, s), Vector2.LEFT])
	var prev := Vector2(half_total, s)
	for i in range(n - 1, -1, -1):
		var cx := (i - (n - 1) / 2.0) * pitch
		# Right half: centre (cx - c, s), rising from the springing line (or the meeting point) to the apex.
		var right_centre := Vector2(cx - c, s)
		var a0 := 0.0 if i == n - 1 else meet
		var start := right_centre + Vector2(r * cos(a0), r * sin(a0))
		if not start.is_equal_approx(prev):
			segs.append([prev, Vector2.DOWN, start, Vector2.DOWN])
		prev = start
		for k in range(1, ARC_SEGMENTS + 1):
			var a := lerpf(a0, top, float(k) / ARC_SEGMENTS)
			var p := right_centre + Vector2(r * cos(a), r * sin(a))
			segs.append([prev, (right_centre - prev).normalized(), p, (right_centre - p).normalized()])
			prev = p
		# Left half: centre (cx + c, s), falling from the apex.
		var left_centre := Vector2(cx + c, s)
		var a1 := 0.0 if i == 0 else meet
		for k in range(ARC_SEGMENTS - 1, -1, -1):
			var a := lerpf(a1, top, float(k) / ARC_SEGMENTS)
			var p := left_centre + Vector2(-r * cos(a), r * sin(a))
			segs.append([prev, (left_centre - prev).normalized(), p, (left_centre - p).normalized()])
			prev = p
	segs.append([prev, Vector2.RIGHT, Vector2(-half_total, b), Vector2.RIGHT])
	return segs


func _build_reveal(segs: Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := reveal_depth / 2.0
	for seg in segs:
		var p0: Vector2 = seg[0]
		var n0: Vector2 = seg[1]
		var p1: Vector2 = seg[2]
		var n1: Vector2 = seg[3]
		var quad := [
			[Vector3(p0.x, p0.y, -z), n0], [Vector3(p1.x, p1.y, -z), n1], [Vector3(p1.x, p1.y, z), n1],
			[Vector3(p0.x, p0.y, -z), n0], [Vector3(p1.x, p1.y, z), n1], [Vector3(p0.x, p0.y, z), n0],
		]
		for v in quad:
			var nv: Vector2 = v[1]
			st.set_normal(Vector3(nv.x, nv.y, 0.0))
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "Reveal"
	mi.mesh = st.commit()
	mi.material_override = _get_reveal_material()
	return mi


## One flat pane filling the whole opening on z = 0; the frame's bars pass
## through it like leading holding the glass.
func _build_glass(segs: Array) -> MeshInstance3D:
	var poly := PackedVector2Array()
	for seg in segs:
		poly.append(seg[0])
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in tris:
		st.set_uv(poly[i])
		st.add_vertex(Vector3(poly[i].x, poly[i].y, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "Glass"
	mi.mesh = st.commit()
	mi.material_override = _get_glass_material()
	return mi


## Where the light shaft of an opening outline (module space) sits: a transform that
## maps the unit shaft (shaft_mesh: a ±1 square in the window plane) onto the opening's
## bounding box, a little inside it and just inside the room's wall face.
static func shaft_transform(segs: Array) -> Transform3D:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for seg in segs:
		var p: Vector2 = seg[0]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var mid := (lo + hi) / 2.0
	var half := (hi - lo) / 2.0 * 0.9
	return Transform3D(Basis.from_scale(Vector3(half.x, half.y, 1.0)), Vector3(mid.x, mid.y, 0.2))


## The unit shaft every window shares: the four sides of a prism from a ±1 square in
## the window plane, its far end (UV.y = 1) widened by SHAFT_SPREAD and pushed along the
## light in the shader. UV.x runs across a side.
static func shaft_mesh() -> ArrayMesh:
	if _shaft_mesh != null:
		return _shaft_mesh
	var near: Array[Vector3] = []
	var far: Array[Vector3] = []
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		near.append(Vector3(c.x, c.y, 0.0))
		far.append(Vector3(c.x * SHAFT_SPREAD, c.y * SHAFT_SPREAD, 0.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var j := (i + 1) % 4
		var quad := [near[i], near[j], far[j], far[i]]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		st.set_normal((near[j] - near[i]).cross(Vector3.BACK).normalized())
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.add_vertex(quad[k])
	_shaft_mesh = st.commit()
	return _shaft_mesh


static var _shaft_mesh: ArrayMesh
## Dev switch (tools/perf_castle --no-shafts): no light shafts at all.
static var shafts_disabled := false
## Shafts waiting to be batched: level root → Array[Transform3D] (global).
static var _pending_shafts := {}


## Queues this window's shaft; LightShafts batches every queued shaft of a level into a
## MultiMesh per SHAFT_CELL cell once the level has loaded (one draw per cell).
func _queue_shaft(segs: Array) -> void:
	var level := _shaft_level()
	if level == null:
		return
	if not _pending_shafts.has(level):
		_pending_shafts[level] = []
		# A static callable: a window freed before the flush must not cancel its level's batch.
		Callable(WallWindow, &"_flush_shafts").call_deferred(level)
	(_pending_shafts[level] as Array).append(global_transform * shaft_transform(segs))


## The node whose shafts are batched together: the level (the nearest ancestor with a
## StaticBatch, as the castle has), else the scene this window was saved in, else its
## parent. Windows that wall runs create at runtime have no owner, so the owner alone
## would make a batch per wall run.
func _shaft_level() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_node(^"StaticBatch"):
			return node
		node = node.get_parent()
	return owner if owner != null else get_parent()


static func _flush_shafts(level: Node) -> void:
	var xforms: Array = _pending_shafts.get(level, [])
	_pending_shafts.erase(level)
	if is_instance_valid(level) and not xforms.is_empty():
		level.add_child(build_shaft_batches(xforms))


## Shafts are grouped into cells this wide (metres); each cell is one MultiMesh draw.
const SHAFT_CELL := 32.0


## A "LightShafts" node holding one MultiMeshInstance3D per SHAFT_CELL cell (and storey)
## for the given shaft transforms (global).
static func build_shaft_batches(xforms: Array) -> Node3D:
	var cells := {}
	for xf: Transform3D in xforms:
		var key := Vector3i(floori(xf.origin.x / SHAFT_CELL), floori(xf.origin.y / 6.0), floori(xf.origin.z / SHAFT_CELL))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(xf)
	var root := Node3D.new()
	root.name = "LightShafts"
	for key: Vector3i in cells:
		var list: Array = cells[key]
		var centre := Vector3.ZERO
		for xf: Transform3D in list:
			centre += xf.origin
		centre /= list.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shaft_mesh()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D((list[i] as Transform3D).basis, (list[i] as Transform3D).origin - centre))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LightShaft_%d_%d_%d" % [key.x, key.y, key.z]
		mmi.multimesh = mm
		mmi.position = centre
		mmi.material_override = _get_shaft_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.extra_cull_margin = SHAFT_MAX_REACH   # the shader pushes the far ends out along the light
		mmi.visibility_range_end = SHAFT_RANGE
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	return root


static func _get_shaft_material() -> ShaderMaterial:
	if _shaft_material == null:
		_shaft_material = ShaderMaterial.new()
		_shaft_material.shader = SHAFT_SHADER
		_shaft_material.set_shader_parameter("shaft", shaft_color(0.0))
		_shaft_material.set_shader_parameter("drop", SHAFT_DROP)
		_shaft_material.set_shader_parameter("max_reach", SHAFT_MAX_REACH)
	return _shaft_material


## Aims every shaft along `light_dir` (the way the sun's or moon's light travels,
## world space); `strength` (0–1) fades them while the body is low (the sun/moon swap).
## One uniform on the shared material, however many windows there are.
static func set_shaft_light(light_dir: Vector3, strength: float = 1.0) -> void:
	var mat := _get_shaft_material()
	mat.set_shader_parameter("light_dir", light_dir.normalized())
	_shaft_strength = clampf(strength, 0.0, 1.0)
	mat.set_shader_parameter("shaft", shaft_color(_shaft_daylight))


static var _shaft_strength := 1.0
static var _shaft_daylight := 0.0


## How far a shaft reaches along `light_dir` (mirrors light_shaft.gdshader).
static func shaft_reach(light_dir: Vector3) -> float:
	var l := light_dir.normalized()
	return minf(SHAFT_DROP / maxf(-l.y, 0.05), SHAFT_MAX_REACH)


## 0…1: whether light travelling along `light_dir` shines into a room whose inside is
## `inward` (the window module's +Z, world space). Mirrors light_shaft.gdshader.
static func shaft_facing(light_dir: Vector3, inward: Vector3) -> float:
	var l := light_dir.normalized()
	var lh := Vector2(l.x, l.z)
	var ih := Vector2(inward.x, inward.z)
	if lh.length() < 0.001 or ih.length() < 0.001 or l.y > -0.02:
		return 0.0
	return smoothstep(0.2, 0.45, lh.normalized().dot(ih.normalized()))


## The shaft's colour (rgb) and strength (a) at `daylight` 0 (night, moonlight) … 1 (day).
static func shaft_color(daylight: float) -> Color:
	var t := clampf(daylight, 0.0, 1.0)
	var c := SHAFT_NIGHT.lerp(SHAFT_DAY, t)
	c.a = lerpf(SHAFT_NIGHT_STRENGTH, SHAFT_DAY_STRENGTH, t) * _shaft_strength
	return c


## Dark mortar behind the stone faces like ModularWallRun's slab, around the opening.
func _add_backing(o: Vector4, arches: Vector2) -> void:
	# Kept clear of the reveal so their faces never z-fight with it.
	var half := module_width / 2.0
	var w := o.x + arches.y * (arches.x - 1.0) / 2.0 + BACKING_CLEARANCE
	var bottom := o.y - BACKING_CLEARANCE
	var top := o.w + BACKING_CLEARANCE
	var pieces := [
		Rect2(-half, 0.0, half - w, module_height),
		Rect2(w, 0.0, half - w, module_height),
		Rect2(-w, 0.0, 2.0 * w, bottom),
		Rect2(-w, top, 2.0 * w, module_height - top),
	]
	for rect: Rect2 in pieces:
		if rect.size.x <= 0.001 or rect.size.y <= 0.001:
			continue
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x, rect.size.y, backing_depth)
		box.material = ModularWallRun._get_backing_material()
		slab.mesh = box
		slab.position = Vector3(rect.get_center().x, rect.get_center().y, 0.0)
		_add_generated(slab)


static func _get_reveal_material() -> StandardMaterial3D:
	if _reveal_material == null:
		_reveal_material = StandardMaterial3D.new()
		_reveal_material.albedo_texture = load("res://assets/models/environment/modular/wall_plain_texture_0.png")
		_reveal_material.roughness_texture = load("res://assets/models/environment/modular/wall_plain_texture_0_metallic_roughness.png")
		_reveal_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		_reveal_material.uv1_triplanar = true
		_reveal_material.uv1_world_triplanar = true
		_reveal_material.uv1_scale = Vector3.ONE * 0.25
		_reveal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _reveal_material


## Daylight through the panes: 0 = night (the material as built below), 1 = noon,
## when the glass glows pale with the sky behind it. Driven by DayNightCycle; every
## window shares the one material, so this is a single property change.
## With global illumination on (`gi`), daylit panes shine brighter: SDFGI takes emissive
## geometry as a light source, so the windows light the walls around them.
static func set_daylight(amount: float, gi: bool = false) -> void:
	var glass := _get_glass_material()
	var t := clampf(amount, 0.0, 1.0)
	glass.emission = GLASS_NIGHT_EMISSION.lerp(GLASS_DAY_EMISSION, t)
	glass.emission_energy_multiplier = lerpf(0.6, GLASS_DAY_ENERGY_GI if gi else 1.5, t)
	_shaft_daylight = t
	_get_shaft_material().set_shader_parameter("shaft", shaft_color(t))


## Leaded glass at night: dark grey-blue, glossy, with a faint cool glow so the
## panes read against the iron even in a dim room. A soft noise mottles the
## tint and the sheen like hand-blown panes (UVs are the pane's metres).
static func _get_glass_material() -> StandardMaterial3D:
	if _glass_material == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.012
		noise.fractal_octaves = 2
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.72, 0.74, 0.8))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var mottle := NoiseTexture2D.new()
		mottle.width = 256
		mottle.height = 256
		mottle.seamless = true
		mottle.noise = noise
		mottle.color_ramp = ramp
		_glass_material = StandardMaterial3D.new()
		_glass_material.albedo_color = Color(0.07, 0.09, 0.12)
		_glass_material.albedo_texture = mottle
		_glass_material.metallic = 0.1
		_glass_material.roughness = 0.15
		_glass_material.emission_enabled = true
		_glass_material.emission = GLASS_NIGHT_EMISSION
		_glass_material.emission_energy_multiplier = 0.6
		_glass_material.emission_texture = mottle
		_glass_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_glass_material.uv1_scale = Vector3(1.2, 1.2, 1.0)
		_glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_material

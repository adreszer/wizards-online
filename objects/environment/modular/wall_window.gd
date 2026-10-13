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
## Generated children are rebuilt on ready and never saved. The glass is
## opaque, so the module keeps a full occluder and full collision like a plain
## wall.

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

static var _reveal_material: StandardMaterial3D


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
	o.y += sill_height
	o.z += sill_height
	o.w += sill_height
	_cut_wall(o)
	if o.x <= 0.0:
		return
	_add_generated(_build_reveal(o))
	_add_backing(o)
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
func _cut_wall(o: Vector4) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative(mi as Node3D)
		mi.set_instance_shader_parameter("mesh_scale", xf.basis.get_scale())
		mi.set_instance_shader_parameter("mesh_offset", xf.origin)
		mi.set_instance_shader_parameter("opening", o)


func _relative(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Outline of the opening (counter-clockwise from the bottom left) with the
## inward normal at each point. Arc points carry the radial normal so the
## curved reveal shades smoothly; corners are duplicated with each side's normal.
static func outline(o: Vector4) -> Array:
	var w := o.x
	var b := o.y
	var s := o.z
	var h := o.w - s
	var c := (h * h - w * w) / (2.0 * w)
	var r := w + c
	var segs: Array = []   # each: [p0, n0, p1, n1]
	segs.append([Vector2(-w, b), Vector2.UP, Vector2(w, b), Vector2.UP])
	segs.append([Vector2(w, b), Vector2.LEFT, Vector2(w, s), Vector2.LEFT])
	# Right arc: centre (-c, s), from angle 0 up to the apex.
	var top := atan2(h, c)
	var prev := Vector2(w, s)
	for i in range(1, ARC_SEGMENTS + 1):
		var a := top * i / ARC_SEGMENTS
		var p := Vector2(-c + r * cos(a), s + r * sin(a))
		segs.append([prev, (Vector2(-c, s) - prev).normalized(), p, (Vector2(-c, s) - p).normalized()])
		prev = p
	# Left arc mirrors it: centre (c, s), from the apex down to the springing line.
	for i in range(ARC_SEGMENTS - 1, -1, -1):
		var a := top * i / ARC_SEGMENTS
		var p := Vector2(c - r * cos(a), s + r * sin(a))
		segs.append([prev, (Vector2(c, s) - prev).normalized(), p, (Vector2(c, s) - p).normalized()])
		prev = p
	segs.append([Vector2(-w, s), Vector2.RIGHT, Vector2(-w, b), Vector2.RIGHT])
	return segs


func _build_reveal(o: Vector4) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := reveal_depth / 2.0
	for seg in outline(o):
		var p0: Vector2 = seg[0]
		var n0: Vector2 = seg[1]
		var p1: Vector2 = seg[2]
		var n1: Vector2 = seg[3]
		var quad := [
			[Vector3(p0.x, p0.y, -z), n0], [Vector3(p1.x, p1.y, -z), n1], [Vector3(p1.x, p1.y, z), n1],
			[Vector3(p0.x, p0.y, -z), n0], [Vector3(p1.x, p1.y, z), n1], [Vector3(p0.x, p0.y, z), n0],
		]
		for v in quad:
			var n: Vector2 = v[1]
			st.set_normal(Vector3(n.x, n.y, 0.0))
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "Reveal"
	mi.mesh = st.commit()
	mi.material_override = _get_reveal_material()
	return mi


## Dark mortar behind the stone faces like ModularWallRun's slab, around the opening.
func _add_backing(o: Vector4) -> void:
	# Kept clear of the reveal so their faces never z-fight with it.
	var half := module_width / 2.0
	var w := o.x + BACKING_CLEARANCE
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

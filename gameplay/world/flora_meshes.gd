class_name FloraMeshes
extends RefCounted
## Meshes for the grounds' scattered flora. A kind can be replaced by a real model:
## list its mesh resource under "flora" in content/castle/kit.json (kind -> res://…mesh.tres
## or a .glb, whose first mesh is used: tools/make_flora.py builds them, bark first and
## leaf cards second); otherwise a low-poly placeholder is built here from primitives.

const KIT_PATH := "res://content/castle/kit.json"

static var _cache: Dictionary = {}


static func mesh_for(kind: String) -> Mesh:
	if _cache.has(kind):
		return _cache[kind]
	var mesh: Mesh = null
	var kit: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH)) if FileAccess.file_exists(KIT_PATH) else null
	if kit is Dictionary and (kit as Dictionary).get("flora", {}).has(kind):
		var res: Resource = load(kit["flora"][kind])
		if res is Mesh:
			mesh = res
		elif res is PackedScene:
			mesh = _first_mesh(res as PackedScene)
	if mesh == null:
		mesh = _placeholder(kind)
	_cache[kind] = mesh
	return mesh


## The first mesh in a model scene, its leaf cards cut out (alpha scissor, both faces):
## a duplicate, so Seasons can tint it without touching the imported resource.
static func _first_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh.duplicate(true) as Mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and (mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.resource_name.begins_with("leaves")):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.4
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.free()
	return mesh


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.95
	return m


static func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D) -> void:
	st.append_from(prim, 0, xf)


static func _placeholder(kind: String) -> Mesh:
	var out := ArrayMesh.new()
	match kind:
		"conifer":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.22; trunk.bottom_radius = 0.35; trunk.height = 3.0; trunk.radial_segments = 6
			_surface(out, [[trunk, Transform3D(Basis(), Vector3(0, 1.5, 0))]], Color(0.25, 0.17, 0.1))
			var cones := []
			for i in range(3):
				var c := CylinderMesh.new()
				c.top_radius = 0.05
				c.bottom_radius = 2.6 - i * 0.6
				c.height = 4.2 - i * 0.6
				c.radial_segments = 7
				cones.append([c, Transform3D(Basis(), Vector3(0, 3.6 + i * 2.6, 0))])
			_surface(out, cones, Color(0.07, 0.17, 0.09))
		"broadleaf":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.3; trunk.bottom_radius = 0.45; trunk.height = 4.0; trunk.radial_segments = 6
			_surface(out, [[trunk, Transform3D(Basis(), Vector3(0, 2.0, 0))]], Color(0.27, 0.19, 0.12))
			var crowns := []
			for o in [Vector3(0, 6.0, 0), Vector3(1.4, 5.0, 0.6), Vector3(-1.2, 5.3, -0.8)]:
				var s := SphereMesh.new()
				s.radius = 2.6; s.height = 4.4; s.radial_segments = 8; s.rings = 5
				crowns.append([s, Transform3D(Basis(), o)])
			_surface(out, crowns, Color(0.12, 0.22, 0.08))
		"bush":
			var s := SphereMesh.new()
			s.radius = 1.0; s.height = 1.3; s.radial_segments = 7; s.rings = 4
			_surface(out, [[s, Transform3D(Basis(), Vector3(0, 0.45, 0))]], Color(0.1, 0.2, 0.08))
		_:
			var r := SphereMesh.new()
			r.radius = 0.9; r.height = 1.2; r.radial_segments = 6; r.rings = 3
			_surface(out, [[r, Transform3D(Basis().scaled(Vector3(1.3, 0.8, 1.0)), Vector3(0, 0.25, 0))]], Color(0.4, 0.39, 0.36))
	return out


static func _surface(out: ArrayMesh, parts: Array, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		_add(st, p[0], p[1])
	st.set_material(_material(colour))
	st.commit(out)

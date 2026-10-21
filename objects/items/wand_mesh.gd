class_name WandMesh
extends MeshInstance3D
## The student's wand, turned from one profile: a rounded pommel, a carved handle with
## two collars and a shaft tapering to the tip. The origin is the grip (the middle of the
## handle, where the fist closes); the wand points along +Y and its tip is at [constant TIP].

const TIP := 0.25
## (height along the wand, radius, colour band): pommel, handle, shaft.
const PROFILE := [
	[-0.092, 0.0, 0], [-0.0905, 0.0062, 0], [-0.087, 0.0098, 0], [-0.081, 0.0112, 0],
	[-0.075, 0.0098, 0], [-0.071, 0.0078, 0], [-0.067, 0.0102, 1], [-0.062, 0.0096, 1],
	[-0.030, 0.0102, 1], [0.000, 0.0098, 1], [0.020, 0.0092, 1], [0.024, 0.0108, 0],
	[0.029, 0.0108, 0], [0.033, 0.0074, 2], [0.080, 0.0064, 2], [0.160, 0.0052, 2],
	[0.235, 0.0040, 2], [0.246, 0.0034, 2], [TIP, 0.0, 2],
]
const BANDS := [Color(0.12, 0.065, 0.035), Color(0.17, 0.095, 0.05), Color(0.22, 0.13, 0.07)]
const SIDES := 12


func _ready() -> void:
	if mesh == null:
		mesh = build()


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in PROFILE.size() - 1:
		var a: Array = PROFILE[i]
		var b: Array = PROFILE[i + 1]
		# Grain: a faint lighter streak every few sides so the wood isn't flat.
		for s in SIDES:
			var t0 := TAU * s / SIDES
			var t1 := TAU * (s + 1) / SIDES
			var col: Color = BANDS[int(b[2])].lightened(0.06 if s % 4 == 0 else 0.0)
			var quad := [_ring(a, t0), _ring(b, t0), _ring(b, t1), _ring(a, t1)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal(_normal(a, b, t0 if k in [0, 1] else t1))
				st.add_vertex(quad[k])
	var out := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.42
	out.surface_set_material(0, mat)
	return out


static func _ring(p: Array, t: float) -> Vector3:
	return Vector3(cos(t) * float(p[1]), float(p[0]), sin(t) * float(p[1]))


## The side normal of the cone between two profile points, at angle `t`.
static func _normal(a: Array, b: Array, t: float) -> Vector3:
	var dy := float(b[0]) - float(a[0])
	var dr := float(b[1]) - float(a[1])
	return Vector3(cos(t) * dy, -dr, sin(t) * dy).normalized()

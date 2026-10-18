class_name DormitoryCorners
extends Node3D
## The house dormitories' bed corners: the server gives each member a bed (feature
## "dorm": {houses: {house: {bed number: {name, decor}}}}); every corner shows its
## owner's name on a plate over the headboard and up to three decorations they hung
## there (owned decor items). Your own corner has a spot to change them (DecorPanel).
## Beds are batched props, so StaticBatch records where they stand; they are numbered
## per dormitory in a stable order (by position). castle.gd adds this.

const BED := "res://objects/environment/placeholders/bed.tscn"
const COLOR_SPOT := Color(0.85, 0.75, 0.45)

## dormitory area id -> beds (global transforms) in number order
var beds_by_area: Dictionary = {}
## house -> dormitory area id
var dorm_of_house: Dictionary = {}
var _corners: Node3D
var _spot: InteractSpot


func _ready() -> void:
	var all_beds: Array[Transform3D] = []
	for batch in get_tree().get_nodes_in_group(StaticBatch.GROUP):
		all_beds.append_array((batch as StaticBatch).beds)
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		var zone := node as AreaZone
		if zone.kind != "dormitory" or zone.house < 1:
			continue
		var inside: Array[Transform3D] = []
		for b in all_beds:
			if AreaTracker.contains(zone, b.origin + Vector3.UP):
				inside.append(b)
		inside.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.x < b.origin.x or (a.origin.x == b.origin.x and a.origin.z < b.origin.z))
		if not inside.is_empty():
			beds_by_area[str(zone.area_id)] = inside
			if not dorm_of_house.has(zone.house):
				dorm_of_house[zone.house] = str(zone.area_id)
	_corners = Node3D.new()
	_corners.name = "Corners"
	add_child(_corners)
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "dorm":
			show_corners(data))
	show_corners(NetworkManager.feature("dorm"))


## Where bed `number` (1-based) of `house` stands, or null.
func bed_transform(house: int, number: int) -> Variant:
	var list: Array = beds_by_area.get(dorm_of_house.get(house, ""), [])
	if list.is_empty() or number < 1:
		return null
	return list[(number - 1) % list.size()]


func show_corners(data: Dictionary) -> void:
	# Detach before freeing: the new corners reuse the names.
	for c in _corners.get_children():
		_corners.remove_child(c)
		c.queue_free()
	if _spot != null:
		remove_child(_spot)
		_spot.queue_free()
		_spot = null
	var houses: Variant = data.get("houses", {})
	if not houses is Dictionary:
		return
	var me := NetworkManager.local_display_name
	for h: String in houses:
		var beds: Variant = houses[h]
		if not beds is Dictionary:
			continue
		for n: String in beds:
			var at: Variant = bed_transform(int(h), int(n))
			if at == null:
				continue
			var entry: Dictionary = beds[n]
			var corner := build_corner(at, str(entry.get("name", "")), entry.get("decor", []) if entry.get("decor", []) is Array else [], int(h))
			_corners.add_child(corner)
			if str(entry.get("name", "")) == me and int(h) == NetworkManager.get_local_house():
				_spot = InteractSpot.create("INTERACT_DECORATE", COLOR_SPOT, 0.25)
				_spot.name = "DecorateSpot"
				add_child(_spot)
				var xf: Transform3D = at
				_spot.global_position = xf.origin + xf.basis.z * 2.6 + Vector3.UP * 0.7
				_spot.used.connect(func(_who: Node) -> void: GameEvents.panel_requested.emit("decor", {}))


## A corner: the owner's name plate and the decorations, on the wall over the headboard.
static func build_corner(at: Transform3D, owner: String, decor: Array, house: int) -> Node3D:
	var corner := Node3D.new()
	corner.name = "Corner_" + owner.validate_node_name()
	corner.transform = at
	var plate := Label3D.new()
	plate.text = owner
	plate.font_size = 40
	plate.pixel_size = 0.004
	plate.outline_size = 6
	plate.modulate = Color(0.95, 0.88, 0.7)
	plate.position = Vector3(0, 1.25, 0.08)
	corner.add_child(plate)
	for i in decor.size():
		var piece := decor_mesh(str(decor[i]), house)
		piece.position = Vector3((i - 1) * 0.6, 1.85, 0.06)
		corner.add_child(piece)
	return corner


## A simple stand-in model for a decor item (real props come with art).
static func decor_mesh(id: String, house: int) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match id:
		"pennant":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.35, 0.5, 0.02)
			mi.mesh = prism
			mi.rotation_degrees = Vector3(0, 0, 180)
			mat.albedo_color = CharacterProfile.house_color(house)
		"star_chart":
			var q := QuadMesh.new()
			q.size = Vector2(0.45, 0.35)
			mi.mesh = q
			mat.albedo_color = Color(0.12, 0.16, 0.35)
			mat.emission_enabled = true
			mat.emission = Color(0.5, 0.6, 1.0)
			mat.emission_energy_multiplier = 0.3
		"brass_lantern", "potted_moonpetal", "music_box", "trophy_small", "game_set":
			var shelf := BoxMesh.new()
			shelf.size = Vector3(0.4, 0.03, 0.18)
			var s := MeshInstance3D.new()
			s.mesh = shelf
			s.position = Vector3(0, -0.14, 0.09)
			root.add_child(s)
			var shapes := {"brass_lantern": [CylinderMesh.new(), Color(0.8, 0.6, 0.25)], "potted_moonpetal": [SphereMesh.new(), Color(0.78, 0.82, 0.95)],
				"music_box": [BoxMesh.new(), Color(0.45, 0.25, 0.15)], "trophy_small": [CylinderMesh.new(), Color(0.95, 0.78, 0.3)], "game_set": [BoxMesh.new(), Color(0.2, 0.25, 0.45)]}
			var m: PrimitiveMesh = shapes[id][0]
			if m is CylinderMesh:
				(m as CylinderMesh).top_radius = 0.07
				(m as CylinderMesh).bottom_radius = 0.09
				(m as CylinderMesh).height = 0.22
			elif m is SphereMesh:
				(m as SphereMesh).radius = 0.1
				(m as SphereMesh).height = 0.2
			elif m is BoxMesh:
				(m as BoxMesh).size = Vector3(0.22, 0.12, 0.14)
			mi.mesh = m
			mi.position = Vector3(0, -0.02, 0.09)
			mat.albedo_color = shapes[id][1]
			mat.metallic = 0.6 if id in ["brass_lantern", "trophy_small"] else 0.0
			if id == "brass_lantern":
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.75, 0.4)
				var light := OmniLight3D.new()
				light.omni_range = 2.5
				light.light_energy = 0.7
				light.light_color = Color(1.0, 0.75, 0.45)
				root.add_child(light)
		_:
			var b := BoxMesh.new()
			b.size = Vector3(0.2, 0.2, 0.05)
			mi.mesh = b
			mat.albedo_color = Color(0.6, 0.6, 0.6)
	mi.material_override = mat
	root.add_child(mi)
	return root

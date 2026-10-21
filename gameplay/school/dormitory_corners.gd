class_name DormitoryCorners
extends Node3D
## The house dormitories' bed corners: the server gives each member a bed (feature
## "dorm": {houses: {house: {bed number: {name, decor}}}}); every corner shows its
## owner's name on a plate over the headboard and up to three decorations they hung
## there (owned decor items). Your own corner has a spot to change them (DecorPanel).
## Beds are batched props, so StaticBatch records where they stand; they are numbered
## per dormitory in a stable order (by position). castle.gd adds this.

const BED := "res://objects/environment/props/bed.tscn"
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
	plate.position = Vector3(0, 1.7, 0.08)
	corner.add_child(plate)
	for i in decor.size():
		var piece := decor_mesh(str(decor[i]), house)
		piece.position = Vector3((i - 1) * 0.6, 2.3, 0.06)
		corner.add_child(piece)
	return corner


## Shelf decorations: model and height (m). The trophy is the house cup in miniature,
## the music box a little chest, the moonpetal the castle's potted plant.
const DECOR_MODELS := {
	"brass_lantern": ["res://assets/models/decor/decor_lantern.glb", 0.22],
	"potted_moonpetal": ["res://assets/models/environment/modular/plant_pot.glb", 0.26],
	"music_box": ["res://assets/models/environment/modular/chest.glb", 0.12],
	"trophy_small": ["res://assets/models/school/house_cup.glb", 0.2],
	"game_set": ["res://assets/models/decor/decor_game_set.glb", 0.04],
}


## A decor item: a pennant in the house colour, a glowing star chart, or a model on a
## small shelf.
static func decor_mesh(id: String, house: int) -> Node3D:
	var root := Node3D.new()
	root.name = id
	if DECOR_MODELS.has(id):
		var shelf := BoxMesh.new()
		shelf.size = Vector3(0.4, 0.03, 0.18)
		var s := MeshInstance3D.new()
		s.mesh = shelf
		s.position = Vector3(0, -0.14, 0.09)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.3, 0.19, 0.11)
		wood.roughness = 0.7
		s.material_override = wood
		root.add_child(s)
		var piece := (load(DECOR_MODELS[id][0]) as PackedScene).instantiate() as Node3D
		fit_height(piece, DECOR_MODELS[id][1])
		piece.position = Vector3(0, -0.125, 0.09)
		root.add_child(piece)
		if id == "brass_lantern":
			var light := OmniLight3D.new()
			light.position = Vector3(0, -0.02, 0.09)
			light.omni_range = 2.5
			light.light_energy = 0.7
			light.light_color = Color(1.0, 0.75, 0.45)
			root.add_child(light)
		return root
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
		_:
			var b := BoxMesh.new()
			b.size = Vector3(0.2, 0.2, 0.05)
			mi.mesh = b
			mat.albedo_color = Color(0.6, 0.6, 0.6)
	mi.material_override = mat
	root.add_child(mi)
	return root


## Scales `node` uniformly so its meshes stand `height` tall (base kept at its origin).
static func fit_height(node: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).get_aabb()
		b = (mi as MeshInstance3D).transform * b if mi.get_parent() == node else b
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0001:
		node.scale = Vector3.ONE * (height / box.size.y)

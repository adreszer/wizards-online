class_name GroundsLife
extends Node3D
## Life outside the classrooms, as the server's feature modules describe it: the Potions
## classroom's cauldrons (open the CauldronPanel), the paddock's creatures (feed with a
## treat, else pet; bonds build up to adopting a familiar), and a counter in every
## village shop (the ShopPanel). castle.gd adds it; it only draws and asks.

const CREATURES := {"mossling": Color(0.45, 0.75, 0.35), "emberkit": Color(0.95, 0.45, 0.2), "glimmerwing": Color(0.75, 0.75, 1.0)}
const SHOPS := ["apothecary", "bookshop", "broom_workshop", "general_store", "instrument_maker", "joke_shop", "stationer", "sweet_shop", "tailor"]

var cauldrons: Array[InteractSpot] = []
var creatures: Dictionary = {}
var counters: Dictionary = {}
var _paddock: AreaZone


func _ready() -> void:
	var zones := {}
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		zones[str((node as AreaZone).area_id)] = node
	var elixirs := zones.get("class_elixirs") as AreaZone
	if elixirs != null:
		for i in 2:
			var c := InteractSpot.create("INTERACT_CAULDRON", Color(0.5, 0.9, 0.6), 0.35)
			c.name = "Cauldron%d" % (i + 1)
			add_child(c)
			c.global_position = elixirs.global_position + Vector3((i - 0.5) * elixirs.size.x * 0.3, -elixirs.size.y / 2.0 + 0.9, elixirs.size.z * 0.25)
			c.used.connect(func(_who: Node) -> void: GameEvents.panel_requested.emit("cauldron", {}))
			cauldrons.append(c)
	_paddock = zones.get("paddock") as AreaZone
	if _paddock != null:
		for kind: String in CREATURES:
			var body := build_creature(kind, CREATURES[kind])
			add_child(body)
			creatures[kind] = body
			var k := kind
			(body.get_node("Care") as InteractSpot).used.connect(func(_who: Node) -> void: care(k))
	for shop: String in SHOPS:
		var z := zones.get(shop) as AreaZone
		if z == null:
			continue
		var counter := InteractSpot.create("INTERACT_SHOP", Color(0.95, 0.8, 0.4), 0.3)
		counter.name = "Counter_" + shop
		add_child(counter)
		counter.global_position = z.global_position + Vector3(0, -z.size.y / 2.0 + 1.0, 0)
		var s := shop
		counter.used.connect(func(_who: Node) -> void: GameEvents.panel_requested.emit("shop", {"shop": s}))
		counters[shop] = counter


static func build_creature(kind: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Creature_" + kind
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if kind == "glimmerwing":
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28 if kind != "glimmerwing" else 0.12
	sphere.height = sphere.radius * 1.6
	body.mesh = sphere
	body.material_override = mat
	body.name = "Body"
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = sphere.radius * 0.6
	hs.height = hs.radius * 2.0
	head.mesh = hs
	head.material_override = mat
	head.position = Vector3(0, sphere.radius * 0.5, -sphere.radius * 1.1)
	root.add_child(head)
	if kind == "glimmerwing":
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.35, 0.22)
			wing.mesh = q
			wing.material_override = mat
			wing.position = Vector3(side * 0.2, 0.05, 0)
			wing.rotation_degrees = Vector3(-90, 0, 0)
			root.add_child(wing)
	var spot := InteractSpot.create("INTERACT_CREATURE", color, 0.25)
	spot.name = "Care"
	spot.position = Vector3(0, 0.55, 0)
	root.add_child(spot)
	return root


## Where a creature is at time `t`: a slow wander around its own patch of the paddock.
static func wander(center: Vector3, size: Vector3, index: int, t: float, flying: bool) -> Vector3:
	var a := t * (0.11 + index * 0.03) + index * 2.1
	var x := center.x + cos(a) * size.x * (0.18 + 0.05 * index)
	var z := center.z + sin(a * 1.3) * size.z * (0.2 + 0.04 * index)
	var y := center.y - size.y / 2.0 + (1.6 + sin(t * 2.0 + index) * 0.3 if flying else 0.3)
	return Vector3(x, y, z)


func _process(_delta: float) -> void:
	if _paddock == null:
		return
	var t := NetworkManager.server_time()
	var i := 0
	for kind: String in creatures:
		var c: Node3D = creatures[kind]
		var next := wander(_paddock.global_position, _paddock.size, i, t, kind == "glimmerwing")
		if next.distance_to(c.global_position) > 0.001:
			var ahead := wander(_paddock.global_position, _paddock.size, i, t + 0.5, kind == "glimmerwing")
			c.global_position = next
			if ahead.distance_to(next) > 0.01:
				c.look_at(Vector3(ahead.x, next.y, ahead.z), Vector3.UP)
		i += 1


## Feed (with a treat) or pet a creature; tells what the bond is now.
func care(kind: String) -> void:
	var has_treat := false
	var items: Variant = NetworkManager.get_local_inventory().get("items", [])
	for e: Variant in (items if items is Array else []):
		if str((e as Dictionary).get("id", "")) == "creature_treat":
			has_treat = true
	var r: Dictionary = await NetworkManager.request("creature_feed" if has_treat else "creature_pet", {"kind": kind})
	if not r.ok:
		GameEvents.notification_requested.emit(NetworkManager.refusal_text(r.reason), 3.0)
		return
	var key := "CREATURE_BOND_ADOPT" if r.data.get("can_adopt", false) else "CREATURE_BOND"
	GameEvents.notification_requested.emit(tr(key) % [tr("CREATURE_" + kind.to_upper()), int(r.data.get("bond", 0))], 4.0)

class_name CastleMap
extends Node
## What the map and minimap draw, read from the level at runtime: every
## AreaZone becomes a room rectangle on the storeys it spans, every Staircase
## and SpiralStaircase a stair symbol, every doorway module (Walls/Doorway_*) a
## gap in the room outlines, and the grounds' Terrain supplies the
## outdoor relief. Nothing is baked, so regenerating the castle (any seed)
## changes the map with it.
##
## Secret areas (kind "secret") stay off the map until this character has
## found them: walking in reveals one at once, and online the server records it
## in the profile's discoveries as "map:<area id>" so it stays revealed.
##
## Online the plain map is the school's plan: halls, corridors, classrooms, the
## library, stairs, the grounds and your own house's rooms. The Wayfinder's Chart (an
## item) draws every other place once you have walked into it (the server keeps what
## each student explored, feature "explored"). Offline every ordinary room is drawn.

## The level was (re)read: rooms, stairs and terrain may all be new.
signal rebuilt()
## What is known changed (a secret was found).
signal changed()

const STOREY_HEIGHT := 9.0
## Discovery ids the server stores for revealed secret areas.
const DISCOVERY_PREFIX := "map:"
## Grounds zones wider than this are the whole estate, not a named place.
const MAX_GROUNDS_LABEL_SIZE := 1000.0
## Rooms outside the castle (the village's shops, inns, post office, station hall): they
## stand on the terrain, so they are drawn with the ground floor whatever their height.
const OUTSIDE_KINDS := ["shop", "inn", "post_office", "station"]
## What the school's plan shows without the chart.
const PLAN_KINDS := ["hall", "corridor", "classroom", "library", "stair_turret", "shaft", "outdoor", "grounds", "bridge", "shop", "inn", "post_office", "station"]
const CHART_ITEM := "wayfinder_chart"
const DOORWAY_SCENE := "res://objects/environment/modular/doorway.tscn"
## The doorway module's opening, jamb to jamb (the arch is about 3.6 m at its base).
const DOORWAY_WIDTH := 3.6
## How far to either side of a doorway's wall its two rooms are looked for.
const DOORWAY_SIDE := 1.0

## {id, key, kind, house, rect: Rect2 (x, z), lo, hi (storeys, inclusive), secret}
## sorted largest first, so nested rooms draw over the ones they sit in.
var rooms: Array[Dictionary] = []
## Named outdoor places: {id, key, rect}.
var grounds: Array[Dictionary] = []
## {foot: Vector2, dir: Vector2 (uphill), run, width, lo, hi} straight flights;
## spirals have {centre, radius, lo, hi, spiral = true}.
var stairs: Array[Dictionary] = []
## Doorways: {at: Vector2 (centre, x z), along: Vector2 (unit, along the wall), width, storey}.
var doors: Array[Dictionary] = []
## Lowest and highest storey with a room.
var min_storey: int = 0
var max_storey: int = 0
## XZ bounds of the castle (all rooms).
var castle_bounds := Rect2()
var terrain: Terrain

var _revealed: Dictionary = {}
## Area ids this character has walked into (online, from the server).
var explored: Dictionary = {}


static func storey_of(y: float) -> int:
	# Switch storeys two thirds of the way up a flight, not at the first step.
	return floori((y + 3.0) / STOREY_HEIGHT)


func _ready() -> void:
	GameEvents.area_entered.connect(_on_area_entered)
	NetworkManager.profile_received.connect(_on_profile)
	_on_profile(NetworkManager.get_local_profile())
	NetworkManager.pushed.connect(_on_pushed)
	NetworkManager.inventory_received.connect(func(_s: Dictionary) -> void: changed.emit())
	_on_pushed("explored", NetworkManager.feature("explored"))


## Reads the level's Zones, Stairs and Grounds/Terrain (missing parts are skipped).
func build(level: Node) -> void:
	rooms.clear()
	grounds.clear()
	stairs.clear()
	doors.clear()
	min_storey = 0
	max_storey = 0
	var bounds_set := false
	var zones := level.get_node_or_null("Zones")
	for child in (zones.get_children() if zones != null else []):
		var z := child as AreaZone
		if z == null:
			continue
		var p := z.global_position
		var rect := Rect2(p.x - z.size.x * 0.5, p.z - z.size.z * 0.5, z.size.x, z.size.z)
		if z.kind == "grounds":
			if z.size.x < MAX_GROUNDS_LABEL_SIZE:
				grounds.append({"id": str(z.area_id), "key": z.display_key, "rect": rect})
			continue
		var outside := OUTSIDE_KINDS.has(z.kind)
		var lo := 0 if outside else roundi((p.y - z.size.y * 0.5) / STOREY_HEIGHT)
		var hi := 0 if outside else lo + maxi(1, roundi(z.size.y / STOREY_HEIGHT)) - 1
		rooms.append({"id": str(z.area_id), "key": z.display_key, "kind": z.kind, "house": z.house,
			"rect": rect, "lo": lo, "hi": hi, "secret": z.kind == "secret", "outside": outside})
		min_storey = mini(min_storey, lo)
		max_storey = maxi(max_storey, hi)
		if outside:
			continue
		castle_bounds = rect if not bounds_set else castle_bounds.merge(rect)
		bounds_set = true
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rect"].get_area() > b["rect"].get_area())
	var stair_root := level.get_node_or_null("Stairs")
	for node in (stair_root.find_children("*", "StaticBody3D", true, false) if stair_root != null else []):
		if node is Staircase:
			var s := node as Staircase
			var xf := s.global_transform
			var dir := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
			var lo := storey_of(xf.origin.y)
			stairs.append({"foot": Vector2(xf.origin.x, xf.origin.z), "dir": dir, "run": s.run, "width": s.width,
				"lo": lo, "hi": lo + maxi(1, roundi(s.rise / STOREY_HEIGHT))})
		elif node is SpiralStaircase:
			var sp := node as SpiralStaircase
			var lo := storey_of(sp.global_position.y)
			stairs.append({"centre": Vector2(sp.global_position.x, sp.global_position.z), "radius": sp.half_size,
				"lo": lo, "hi": lo + maxi(1, roundi(sp.turns * sp.rise_per_turn / STOREY_HEIGHT)), "spiral": true})
	var walls := level.get_node_or_null("Walls")
	for child in (walls.get_children() if walls != null else []):
		var d := child as Node3D
		if d == null or not (d.scene_file_path == DOORWAY_SCENE or str(d.name).begins_with("Doorway")):
			continue
		var dx := d.global_transform
		doors.append({"at": Vector2(dx.origin.x, dx.origin.z), "along": Vector2(dx.basis.x.x, dx.basis.x.z).normalized(),
			"width": DOORWAY_WIDTH, "storey": storey_of(dx.origin.y + 0.5)})
	terrain = level.get_node_or_null("Grounds/Terrain") as Terrain
	rebuilt.emit()


## True when the room is drawn: secrets once found; online the plan's rooms and your
## house's, and with the chart everything you explored; offline every ordinary room.
func is_known(room: Dictionary) -> bool:
	if room["secret"]:
		return _revealed.has(room["id"])
	if not NetworkManager.is_in_world():
		return true
	if PLAN_KINDS.has(room["kind"]) or (int(room["house"]) > 0 and int(room["house"]) == NetworkManager.get_local_house()):
		return true
	return has_chart() and explored.has(room["id"])


## Whether the local character carries the Wayfinder's Chart.
static func has_chart() -> bool:
	var inv: Variant = NetworkManager.get_local_inventory().get("items", [])
	return inv is Array and (inv as Array).any(func(e: Variant) -> bool: return e is Dictionary and str(e.get("id", "")) == CHART_ITEM)


func _on_pushed(kind: String, data: Dictionary) -> void:
	if kind == "explored":
		explored.clear()
		var list: Variant = data.get("areas", [])
		for a: Variant in (list if list is Array else []):
			explored[str(a)] = true
		changed.emit()
	elif kind == "explored_new":
		explored[str(data.get("area", ""))] = true
		changed.emit()


func is_revealed(area_id: String) -> bool:
	return _revealed.has(area_id)


func reveal(area_id: String) -> void:
	if _revealed.has(area_id):
		return
	_revealed[area_id] = true
	changed.emit()


## Rooms drawn on a storey, largest first.
func rooms_on(storey: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rooms:
		if storey >= r["lo"] and storey <= r["hi"] and is_known(r):
			out.append(r)
	return out


## Stairs that touch a storey (their foot or their top), skipping any inside an unfound secret.
func stairs_on(storey: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in stairs:
		if (storey == s["lo"] or storey == s["hi"] or (s.has("spiral") and storey > s["lo"] and storey < s["hi"])) and not _in_hidden_secret(s, storey):
			out.append(s)
	return out


## Doorways on a storey that lead into at least one room drawn there; one that opens into
## an unfound secret room stays off the map with it.
func doors_on(storey: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in doors:
		if d["storey"] != storey:
			continue
		var normal: Vector2 = (d["along"] as Vector2).orthogonal() * DOORWAY_SIDE
		var hidden := false
		var known := false
		for p: Vector2 in [d["at"] + normal, d["at"] - normal]:
			hidden = hidden or _in_hidden_secret_at(p, storey)
			known = known or not room_at_point(p, storey).is_empty()
		if known and not hidden:
			out.append(d)
	return out


## The smallest known room containing a world position on its storey, or {}.
func room_at(pos: Vector3) -> Dictionary:
	return room_at_point(Vector2(pos.x, pos.z), storey_of(pos.y))


func room_at_point(point: Vector2, storey: int) -> Dictionary:
	var best: Dictionary = {}
	for r in rooms:
		# Outside rooms stand on the terrain: whatever storey its height falls in, a step either way counts.
		var slack := 1 if r.get("outside", false) else 0
		if storey < r["lo"] - slack or storey > r["hi"] + slack or not is_known(r) or not (r["rect"] as Rect2).has_point(point):
			continue
		if best.is_empty() or r["rect"].get_area() < best["rect"].get_area():
			best = r
	return best


## The storey the map should show for someone standing at `pos`: their own
## storey inside the castle, the ground floor outdoors.
func view_storey_at(pos: Vector3) -> int:
	var storey := storey_of(pos.y)
	var room := room_at(pos)
	if not room.is_empty():
		return 0 if room.get("outside", false) else storey
	# On the terrain (which rises and falls far from storey heights) show the ground floor.
	for r in rooms:
		if (r["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)) and storey >= r["lo"] - 1 and storey <= r["hi"] + 1:
			return clampi(storey, r["lo"], r["hi"])
	return 0


## Translated name of the place at a position: a room, a named outdoor place, or "".
func place_name_at(pos: Vector3) -> String:
	var room := room_at(pos)
	if not room.is_empty():
		return tr(room["key"])
	var best: Dictionary = {}
	for g in grounds:
		if (g["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)) and (best.is_empty() or g["rect"].get_area() < best["rect"].get_area()):
			best = g
	return tr(best["key"]) if not best.is_empty() else ""


func _in_hidden_secret(stair: Dictionary, storey: int) -> bool:
	var point: Vector2 = stair["centre"] if stair.has("spiral") else stair["foot"] + stair["dir"] * stair["run"] * 0.5
	return _in_hidden_secret_at(point, storey)


func _in_hidden_secret_at(point: Vector2, storey: int) -> bool:
	for r in rooms:
		if r["secret"] and not _revealed.has(r["id"]) and storey >= r["lo"] and storey <= r["hi"] and (r["rect"] as Rect2).has_point(point):
			return true
	return false


func _on_area_entered(area_id: StringName, zone: Node) -> void:
	var z := zone as AreaZone
	if z != null and z.kind == "secret":
		reveal(str(area_id))


func _on_profile(profile: Dictionary) -> void:
	for id in profile.get("discoveries", []):
		if str(id).begins_with(DISCOVERY_PREFIX):
			reveal(str(id).substr(DISCOVERY_PREFIX.length()))

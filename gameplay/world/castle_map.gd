class_name CastleMap
extends Node
## What the map and minimap draw, read from the level at runtime: every
## AreaZone becomes a room rectangle on the storeys it spans, every Staircase
## and SpiralStaircase a stair symbol, and the grounds' Terrain supplies the
## outdoor relief. Nothing is baked, so regenerating the castle (any seed)
## changes the map with it.
##
## Secret areas (kind "secret") stay off the map until this character has
## found them: walking in reveals one at once, and online the server records it
## in the profile's discoveries as "map:<area id>" so it stays revealed.

## The level was (re)read: rooms, stairs and terrain may all be new.
signal rebuilt()
## What is known changed (a secret was found).
signal changed()

const STOREY_HEIGHT := 9.0
## Discovery ids the server stores for revealed secret areas.
const DISCOVERY_PREFIX := "map:"
## Grounds zones wider than this are the whole estate, not a named place.
const MAX_GROUNDS_LABEL_SIZE := 1000.0

## {id, key, kind, house, rect: Rect2 (x, z), lo, hi (storeys, inclusive), secret}
## sorted largest first, so nested rooms draw over the ones they sit in.
var rooms: Array[Dictionary] = []
## Named outdoor places: {id, key, rect}.
var grounds: Array[Dictionary] = []
## {foot: Vector2, dir: Vector2 (uphill), run, width, lo, hi} straight flights;
## spirals have {centre, radius, lo, hi, spiral = true}.
var stairs: Array[Dictionary] = []
## Lowest and highest storey with a room.
var min_storey: int = 0
var max_storey: int = 0
## XZ bounds of the castle (all rooms).
var castle_bounds := Rect2()
var terrain: Terrain

var _revealed: Dictionary = {}


static func storey_of(y: float) -> int:
	# Switch storeys two thirds of the way up a flight, not at the first step.
	return floori((y + 3.0) / STOREY_HEIGHT)


func _ready() -> void:
	GameEvents.area_entered.connect(_on_area_entered)
	NetworkManager.profile_received.connect(_on_profile)
	_on_profile(NetworkManager.get_local_profile())


## Reads the level's Zones, Stairs and Grounds/Terrain (missing parts are skipped).
func build(level: Node) -> void:
	rooms.clear()
	grounds.clear()
	stairs.clear()
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
		var lo := roundi((p.y - z.size.y * 0.5) / STOREY_HEIGHT)
		var hi := lo + maxi(1, roundi(z.size.y / STOREY_HEIGHT)) - 1
		rooms.append({"id": str(z.area_id), "key": z.display_key, "kind": z.kind, "house": z.house,
			"rect": rect, "lo": lo, "hi": hi, "secret": z.kind == "secret"})
		min_storey = mini(min_storey, lo)
		max_storey = maxi(max_storey, hi)
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
	terrain = level.get_node_or_null("Grounds/Terrain") as Terrain
	rebuilt.emit()


## True when the room is drawn: every ordinary room, secrets once found.
func is_known(room: Dictionary) -> bool:
	return not room["secret"] or _revealed.has(room["id"])


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


## The smallest known room containing a world position on its storey, or {}.
func room_at(pos: Vector3) -> Dictionary:
	return room_at_point(Vector2(pos.x, pos.z), storey_of(pos.y))


func room_at_point(point: Vector2, storey: int) -> Dictionary:
	var best: Dictionary = {}
	for r in rooms:
		if storey < r["lo"] or storey > r["hi"] or not is_known(r) or not (r["rect"] as Rect2).has_point(point):
			continue
		if best.is_empty() or r["rect"].get_area() < best["rect"].get_area():
			best = r
	return best


## The storey the map should show for someone standing at `pos`: their own
## storey inside the castle, the ground floor outdoors.
func view_storey_at(pos: Vector3) -> int:
	var storey := storey_of(pos.y)
	if not room_at(pos).is_empty():
		return storey
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

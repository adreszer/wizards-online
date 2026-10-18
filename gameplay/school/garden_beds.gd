class_name GardenBeds
extends Node3D
## The greenhouse beds (server feature "garden"): PLOTS beds in rows across the
## greenhouse, each showing what grows there, whose it is, and when it is ripe.
## Interact with a bed: plant your first seed in an empty bed, water a planted one,
## speed a growing one with Quicksprout (if you know it), harvest a ripe one.
## castle.gd adds this.

const AREA := &"greenhouse"
const PLOTS := 12
const COLOR_EMPTY := Color(0.45, 0.33, 0.2)
const COLOR_GROWING := Color(0.35, 0.7, 0.3)
const COLOR_RIPE := Color(0.95, 0.85, 0.3)
const GROWTH_SPELL := "quicksprout"

var beds: Array[InteractSpot] = []
var _view: Dictionary = {}


func _ready() -> void:
	var zone: AreaZone
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		if (node as AreaZone).area_id == AREA:
			zone = node
	if zone == null:
		return
	for i in PLOTS:
		var spot := InteractSpot.create("INTERACT_GARDEN_BED", COLOR_EMPTY, 0.3)
		spot.name = "Bed%d" % (i + 1)
		add_child(spot)
		spot.global_position = bed_position(zone.global_position, zone.size, i)
		var n := i + 1
		spot.used.connect(func(_who: Node) -> void: use_bed(n))
		beds.append(spot)
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "garden":
			_view = data
			refresh())
	_view = NetworkManager.feature("garden")
	refresh()


## Beds in three rows of four across the room, clear of the middle aisle.
static func bed_position(center: Vector3, size: Vector3, i: int) -> Vector3:
	var row := i / 4
	var col := i % 4
	var x := center.x + (col - 1.5) * size.x * 0.18
	var z := center.z + (row - 1.0) * size.z * 0.25
	return Vector3(x, center.y - size.y / 2.0 + 0.7, z)


func plot(n: int) -> Dictionary:
	var plots: Variant = _view.get("plots", {})
	return (plots as Dictionary).get(str(n), {}) if plots is Dictionary else {}


func refresh() -> void:
	var now := NetworkManager.server_time()
	for i in beds.size():
		var p := plot(i + 1)
		if p.is_empty():
			beds[i].set_state(COLOR_EMPTY, true, "")
			continue
		var herb := str(p.get("seed", "")).trim_prefix("seed_")
		var ripe: bool = p.get("ready", false) or (float(p.get("ready_at", 0)) > 0.0 and now >= float(p.get("ready_at", 0)))
		var text := "%s · %s" % [tr("ITEM_%s_NAME" % herb.to_upper()), str(p.get("name", ""))]
		if ripe:
			text += " · " + tr("GARDEN_RIPE_LABEL")
		elif not p.get("watered", false):
			text += " · " + tr("GARDEN_THIRSTY")
		else:
			text += " · %d min" % ceili((float(p.get("ready_at", 0)) - now) / 60.0)
		beds[i].set_state(COLOR_RIPE if ripe else COLOR_GROWING, true, text)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 120 == 0 and not _view.is_empty():
		refresh()


## What Interact does with bed `n` depends on what is in it.
func use_bed(n: int) -> void:
	var p := plot(n)
	var r: Dictionary
	if p.is_empty():
		var seed := first_seed()
		if seed == "":
			GameEvents.notification_requested.emit(tr("GARDEN_NO_SEEDS"), 4.0)
			return
		r = await NetworkManager.request("garden_plant", {"plot": n, "seed": seed})
	elif not p.get("watered", false):
		r = await NetworkManager.request("garden_water", {"plot": n})
	elif p.get("ready", false) or NetworkManager.server_time() >= float(p.get("ready_at", 0)):
		r = await NetworkManager.request("garden_harvest", {"plot": n})
	else:
		r = await NetworkManager.request("garden_spell", {"plot": n, "spell": GROWTH_SPELL})
	GameEvents.notification_requested.emit(NetworkManager.refusal_text(r.reason) if not r.ok else tr("GARDEN_DONE"), 3.0)


static func first_seed() -> String:
	var items: Variant = NetworkManager.get_local_inventory().get("items", [])
	for e: Variant in (items if items is Array else []):
		var id := str((e as Dictionary).get("id", ""))
		if id.begins_with("seed_"):
			return id
	return ""

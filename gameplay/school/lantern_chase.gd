class_name LanternChase
extends Node3D
## Lantern Chase on the pitch (server feature "lantern_chase"): the two rings at the
## pitch's ends, both teams' lanterns (on their carrier's broom, or lying where they
## fell, lit or snuffed), the score and the time left. The local player takes their
## team's lantern by Interact, relights a snuffed one with a fire spell (Interact
## while it lies dark), snuffs a rival carrier by hitting them with a wind or water
## spell, and scores by flying the lit lantern through the far ring (reported when
## close; the server checks). /chase join a|b, /chase start, /chase leave. castle.gd adds it.

const AREA := &"pitch"
const TEAM_COLOR := {"a": Color(0.95, 0.55, 0.2), "b": Color(0.35, 0.6, 1.0)}
## A goal: the lantern carried through the ring, heard at that ring by everyone near.
const GOAL := preload("res://assets/audio/flying/goal_ring_pass.wav")
const RING_RADIUS := 3.0
const RING_REPORT := 4.5

var rings: Dictionary = {}
var lanterns: Dictionary = {}
var hud: Label
var _zone: AreaZone
var _view: Dictionary = {}
var _ring_reported_at := 0.0


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		if (node as AreaZone).area_id == AREA:
			_zone = node
	if _zone == null:
		return
	var layout := layout_for(_zone.global_position, _zone.size)
	for t: String in ["a", "b"]:
		var ring := build_ring(TEAM_COLOR[other(t)])
		ring.name = "Ring_" + t
		add_child(ring)
		ring.global_position = on_ground(layout.rings[t], 7.0)
		rings[t] = ring
		var lantern := build_lantern(TEAM_COLOR[t])
		lantern.name = "Lantern_" + t
		add_child(lantern)
		lantern.global_position = on_ground(layout.homes[t], 1.2)
		lanterns[t] = lantern
		var spot: InteractSpot = lantern.get_node("Use")
		var team := t
		spot.used.connect(func(_who: Node) -> void: use_lantern(team))
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = Label.new()
	hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.offset_top = 40
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	hud.visible = false
	layer.add_child(hud)
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "lantern_chase":
			_cheer_goals(_view, data)
			_view = data)
	GameEvents.spell_hit_player.connect(_on_spell_hit_player)


static func other(t: String) -> String:
	return "b" if t == "a" else "a"


## The pitch's rings (where a team scores: "a" scores at the far ring) and the lanterns'
## homes, the same as the server's layout (features/lantern_chase.lua).
static func layout_for(center: Vector3, size: Vector3) -> Dictionary:
	var floor_y := center.y - size.y / 2.0
	var ax := size.x >= size.z
	var half := (size.x if ax else size.z) / 2.0
	var at := func(f: float, h: float) -> Vector3:
		return Vector3(center.x + f * half, floor_y + h, center.z) if ax else Vector3(center.x, floor_y + h, center.z + f * half)
	return {"rings": {"a": at.call(0.8, 7.0), "b": at.call(-0.8, 7.0)}, "homes": {"a": at.call(-0.6, 1.2), "b": at.call(0.6, 1.2)}}


## `p` (x, z) set `height` metres above the terrain there (the zone box's floor when no ground is hit).
func on_ground(p: Vector3, height: float) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null and _zone != null:
		var top := _zone.global_position.y + _zone.size.y / 2.0 + 50.0
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, top - 400.0, p.z), 1)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			return Vector3(p.x, (hit.position as Vector3).y + height, p.z)
	return p


static func build_ring(color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.25
	torus.outer_radius = RING_RADIUS
	mi.mesh = torus
	mi.rotation_degrees = Vector3(0, 0, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	root.add_child(mi)
	return root


static func build_lantern(color: Color) -> Node3D:
	var root := Node3D.new()
	var glass := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	glass.mesh = sphere
	glass.name = "Glass"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	glass.material_override = mat
	root.add_child(glass)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 6.0
	root.add_child(light)
	var spot := InteractSpot.create("INTERACT_LANTERN", color, 0.3)
	spot.name = "Use"
	spot.position = Vector3(0, -0.5, 0)
	root.add_child(spot)
	return root


func _process(_delta: float) -> void:
	if _zone == null:
		return
	var me := get_tree().get_first_node_in_group(&"local_player") as Node3D
	var on_pitch := me != null and (me.get("area_tracker") as AreaTracker) != null and (me.get("area_tracker") as AreaTracker).current_area_id() == AREA
	hud.visible = on_pitch and not _view.is_empty() and (_view.get("state", "") == "playing" or not _team_list("a").is_empty() or not _team_list("b").is_empty())
	if hud.visible:
		hud.text = hud_text(_view)
	for t: String in ["a", "b"]:
		_place_lantern(t)
	# The carrier scores by flying through the far ring.
	var mine := my_team()
	if mine != "" and _carrier(mine) == NetworkManager.local_display_name and me != null:
		var now := Time.get_ticks_msec() / 1000.0
		var ring_at := (rings[mine] as Node3D).global_position
		if Vector2(me.global_position.x - ring_at.x, me.global_position.z - ring_at.z).length() < RING_REPORT and now - _ring_reported_at > 1.5:
			_ring_reported_at = now
			NetworkManager.request("chase_ring", {})


## A team whose score went up just flew its lantern through its ring.
func _cheer_goals(before: Dictionary, after: Dictionary) -> void:
	var old: Variant = before.get("scores", {})
	var new: Variant = after.get("scores", {})
	if not old is Dictionary or not new is Dictionary:
		return
	for t: String in rings:
		if int((new as Dictionary).get(t, 0)) > int((old as Dictionary).get(t, 0)):
			Sfx.play_at(rings[t], GOAL, 0.0, 60.0)


func _place_lantern(t: String) -> void:
	var lantern: Node3D = lanterns[t]
	var info: Dictionary = (_view.get("lanterns", {}) as Dictionary).get(t, {}) if _view.get("lanterns", {}) is Dictionary else {}
	var lit: bool = info.get("lit", true)
	(lantern.get_node("Light") as OmniLight3D).visible = lit
	((lantern.get_node("Glass") as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 if lit else 0.1
	var carrier := str(info.get("carrier", ""))
	var body := _player_named(carrier) if carrier != "" else null
	if body != null:
		lantern.global_position = body.global_position + Vector3.UP * 1.9
		(lantern.get_node("Use") as InteractSpot).interactable.enabled = false
		return
	(lantern.get_node("Use") as InteractSpot).interactable.enabled = _view.get("state", "") == "playing"
	var pos: Variant = info.get("pos")
	if pos is Array and (pos as Array).size() == 3:
		lantern.global_position = on_ground(Vector3(float(pos[0]), 0.0, float(pos[2])), 1.2)


func _player_named(n: String) -> Node3D:
	if n == NetworkManager.local_display_name:
		return get_tree().get_first_node_in_group(&"local_player") as Node3D
	for p in get_tree().get_nodes_in_group(&"remote_players"):
		if str(p.get("display_name")) == n:
			return p as Node3D
	return null


func _team_list(t: String) -> Array:
	var teams: Variant = _view.get("teams", {})
	var list: Variant = (teams as Dictionary).get(t, []) if teams is Dictionary else []
	return list if list is Array else []


func _carrier(t: String) -> String:
	var l: Variant = _view.get("lanterns", {})
	return str(((l as Dictionary).get(t, {}) as Dictionary).get("carrier", "")) if l is Dictionary else ""


## The local player's team ("" when not playing).
func my_team() -> String:
	for t: String in ["a", "b"]:
		if _team_list(t).has(NetworkManager.local_display_name):
			return t
	return ""


static func hud_text(v: Dictionary) -> String:
	var s: Dictionary = v.get("scores", {}) if v.get("scores", {}) is Dictionary else {}
	if v.get("state", "") != "playing":
		return TranslationServer.translate("CHASE_LOBBY")
	var left := int(v.get("left", 0))
	return TranslationServer.translate("CHASE_HUD") % [int(s.get("a", 0)), int(s.get("b", 0)), left / 60, left % 60]


## Interact with a lantern: take your team's lit lantern, or relight it with fire.
func use_lantern(t: String) -> void:
	if my_team() != t:
		GameEvents.notification_requested.emit(tr("CHASE_NOT_YOUR_LANTERN"), 3.0)
		return
	var info: Dictionary = (_view.get("lanterns", {}) as Dictionary).get(t, {}) if _view.get("lanterns", {}) is Dictionary else {}
	var r: Dictionary
	if info.get("lit", true):
		r = await NetworkManager.request("chase_take", {})
	else:
		r = await NetworkManager.request("chase_relight", {"spell": "emberkindle"})
	if not r.ok:
		GameEvents.notification_requested.emit(NetworkManager.refusal_text(r.reason), 3.0)


func _on_spell_hit_player(peer_id: String, spell_id: StringName) -> void:
	if _view.get("state", "") != "playing" or my_team() == "":
		return
	NetworkManager.request("chase_snuff", {"sid": peer_id, "spell": str(spell_id)})

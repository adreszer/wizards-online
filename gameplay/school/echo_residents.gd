class_name EchoResidents
extends Node3D
## The Echoes: translucent memories of former students and staff, each standing in its
## own place (the server's feature "echoes" says where and how far along each story
## the local student is). Talking to one (Interact) asks the server for the next part
## of its story; the line floats over the Echo and goes into the chat log. castle.gd
## adds this; Echoes appear once the server has sent them (online only).

const COLOR := Color(0.62, 0.8, 1.0)
const SHOW_SECONDS := 9.0

## echo id -> the figure (Node3D with a bubble and an InteractSpot)
var figures: Dictionary = {}
var _zones: Dictionary = {}


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		_zones[str((node as AreaZone).area_id)] = node
	NetworkManager.pushed.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "echoes":
			show_echoes(data))
	show_echoes(NetworkManager.feature("echoes"))


## Where an Echo stands in its room: off the middle, where furniture usually is.
static func place_in(zone_center: Vector3, zone_size: Vector3) -> Vector3:
	return Vector3(zone_center.x + zone_size.x * 0.22, zone_center.y - zone_size.y / 2.0, zone_center.z - zone_size.z * 0.22)


func show_echoes(data: Dictionary) -> void:
	for id: String in data:
		var info: Variant = data[id]
		if not info is Dictionary or figures.has(id):
			if figures.has(id) and info is Dictionary:
				_mark(id, info)
			continue
		var zone := _zones.get(str(info.get("area", ""))) as AreaZone
		if zone == null:
			continue
		var fig := build_figure(id)
		add_child(fig)
		fig.global_position = place_in(zone.global_position, zone.size)
		figures[id] = fig
		var spot: InteractSpot = fig.get_node("Talk")
		spot.used.connect(func(_who: Node) -> void: talk(id))
		_mark(id, info)


func _mark(id: String, info: Dictionary) -> void:
	var fig: Node3D = figures[id]
	var name_label: Label3D = fig.get_node("Name")
	name_label.text = tr("ECHO_%s_NAME" % id.to_upper()) + ("  ✓" if info.get("done", false) else ("  !" if info.get("met", false) else ""))


## A pale, translucent figure: a robe-like cone, a head, a name and a talk spot.
static func build_figure(id: String) -> Node3D:
	var fig := Node3D.new()
	fig.name = "Echo_" + id
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.35)
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var robe := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.42
	cone.height = 1.35
	robe.mesh = cone
	robe.position = Vector3(0, 0.75, 0)
	robe.material_override = mat
	robe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fig.add_child(robe)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	head.mesh = sphere
	head.position = Vector3(0, 1.6, 0)
	head.material_override = mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fig.add_child(head)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 0.5
	light.omni_range = 3.0
	light.position = Vector3(0, 1.2, 0)
	fig.add_child(light)
	var name_label := Label3D.new()
	name_label.name = "Name"
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 2.05, 0)
	name_label.font_size = 32
	name_label.pixel_size = 0.004
	name_label.outline_size = 8
	name_label.modulate = COLOR.lightened(0.3)
	fig.add_child(name_label)
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position = Vector3(0, 2.5, 0)
	bubble.font_size = 30
	bubble.pixel_size = 0.0028
	bubble.width = 800.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.outline_size = 8
	bubble.visible = false
	fig.add_child(bubble)
	var spot := InteractSpot.create("INTERACT_TALK_ECHO", COLOR, 0.3)
	spot.name = "Talk"
	spot.position = Vector3(0, 1.1, 0.35)
	fig.add_child(spot)
	return fig


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id: String in figures:
		var fig: Node3D = figures[id]
		(fig.get_child(0) as Node3D).position.y = 0.75 + sin(t * 1.3 + fig.position.x) * 0.05


## Asks the Echo for the next part of its story.
func talk(id: String) -> void:
	var r: Dictionary = await NetworkManager.request("echo_talk", {"echo": id})
	if not r.ok:
		GameEvents.notification_requested.emit(NetworkManager.refusal_text(r.reason), 3.0)
		return
	var line := tr(str(r.data.get("line", "")))
	say(id, line)
	NetworkManager.system_message.emit("%s: %s" % [tr("ECHO_%s_NAME" % id.to_upper()), line])


func say(id: String, text: String) -> void:
	var fig: Node3D = figures.get(id)
	if fig == null:
		return
	var bubble: Label3D = fig.get_node("Bubble")
	bubble.text = text
	bubble.visible = true
	get_tree().create_timer(SHOW_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(bubble) and bubble.text == text:
			bubble.visible = false)

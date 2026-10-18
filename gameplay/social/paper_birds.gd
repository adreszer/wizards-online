class_name PaperBirds
extends Node3D
## Direct messages arrive as paper birds: a folded paper bird flies to the local player
## from the sender (when they are in sight) or from high above, circles once and
## unfolds; the message itself is in the chat log and the journal. Purely a visual,
## added by world.gd.

const FLIGHT_SECONDS := 2.2
const FROM_SKY := Vector3(6, 14, -6)

var birds: Array[Node3D] = []


func _ready() -> void:
	NetworkManager.chat_line_received.connect(func(line: Dictionary) -> void:
		if line.get("kind", "") == "dm" and not line.get("self", false):
			send_bird(str(line.get("name", line.get("from_name", "")))))


## A bird from the player called `from_name` (or the sky) to the local player.
func send_bird(from_name: String) -> Node3D:
	var me := get_tree().get_first_node_in_group(&"local_player") as Node3D
	if me == null:
		return null
	var start := me.global_position + FROM_SKY
	for p in get_tree().get_nodes_in_group(&"remote_players"):
		if str(p.get("display_name")) == from_name and (p as Node3D).global_position.distance_to(me.global_position) < 40.0:
			start = (p as Node3D).global_position + Vector3.UP * 1.6
	var bird := build_bird()
	add_child(bird)
	if GameSettings.get_value("captions"):
		GameEvents.notification_requested.emit(tr("CAPTION_PAPER_BIRD"), 3.0)
	bird.global_position = start
	birds.append(bird)
	var tween := create_tween()
	tween.tween_method(func(f: float) -> void:
		if not is_instance_valid(me) or not is_instance_valid(bird):
			return
		var target := me.global_position + Vector3.UP * 1.7
		var p := start.lerp(target, f) + Vector3.UP * sin(f * PI) * 2.0
		if p.distance_to(bird.global_position) > 0.001:
			bird.look_at_from_position(bird.global_position, p, Vector3.UP)
		bird.global_position = p, 0.0, 1.0, FLIGHT_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.tween_property(bird, "scale", Vector3.ONE * 0.01, 0.35)
	tween.tween_callback(func() -> void:
		birds.erase(bird)
		bird.queue_free())
	return bird


## Two white paper wings and a body, flapping.
static func build_bird() -> Node3D:
	var bird := Node3D.new()
	bird.name = "PaperBird"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.94, 0.88)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.22, 0.01, 0.18)
		wing.mesh = prism
		wing.material_override = mat
		wing.position = Vector3(side * 0.1, 0, 0)
		wing.name = "WingL" if side < 0.0 else "WingR"
		bird.add_child(wing)
	var body := MeshInstance3D.new()
	var b := PrismMesh.new()
	b.size = Vector3(0.05, 0.05, 0.25)
	body.mesh = b
	body.material_override = mat
	bird.add_child(body)
	return bird


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for bird in birds:
		if is_instance_valid(bird):
			var flap := sin(t * 14.0) * 0.6
			(bird.get_node("WingL") as Node3D).rotation.z = flap
			(bird.get_node("WingR") as Node3D).rotation.z = -flap

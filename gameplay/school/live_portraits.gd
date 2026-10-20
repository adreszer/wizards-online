class_name LivePortraits
extends Node
## The castle's portraits move. Paintings stay paint at a distance; the nearest few in
## front of the local player turn live (LivePortrait: the sitter's model drawn onto the
## canvas): they breathe, turn their head to follow the player, wave when they speak
## (TalkingPortraits.spoke) and now and then gesture on their own while the player
## lingers. castle.gd adds it after TalkingPortraits.

const RANGE := 7.0
const MAX_LIVE := 2
## Idle gestures while the player stays near, every IDLE_GAP seconds or so.
const IDLE_GESTURES: Array[StringName] = [&"wave", &"shrug", &"point", &"bow"]
const IDLE_REACH := 4.5
const IDLE_GAP := Vector2(14.0, 30.0)

var portraits: Array[Transform3D] = []
var sitters: Array[int] = []
## Live portraits by portrait index.
var live: Dictionary = {}
var _timer := 0.0
var _next_idle: Dictionary = {}
## Portraits that spoke before they came alive (index -> until when to still wave).
var _spoke_at: Dictionary = {}


func _ready() -> void:
	for batch in get_tree().get_nodes_in_group(StaticBatch.GROUP):
		portraits.append_array((batch as StaticBatch).portraits)
		sitters.append_array((batch as StaticBatch).portrait_sitters)
	var talking := get_parent().get_node_or_null("TalkingPortraits") as TalkingPortraits
	if talking != null:
		talking.spoke.connect(_on_spoke)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Node3D
	if player == null:
		return
	var head := player.global_position + Vector3.UP * 1.6
	for i: int in live:
		var lp: LivePortrait = live[i]
		if is_instance_valid(lp) and not lp.leaving:
			lp.look_toward(head)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	update_live(head)
	var now := Time.get_ticks_msec() / 1000.0
	for i: int in live:
		var lp: LivePortrait = live[i]
		if not is_instance_valid(lp) or lp.leaving or portraits[i].origin.distance_to(head) > IDLE_REACH:
			continue
		if now >= float(_next_idle.get(i, now + 4.0)):
			lp.gesture(IDLE_GESTURES[randi() % IDLE_GESTURES.size()])
			_next_idle[i] = now + randf_range(IDLE_GAP.x, IDLE_GAP.y)
		elif not _next_idle.has(i):
			_next_idle[i] = now + randf_range(4.0, 10.0)


## Which portraits should be live for a viewer at `head`: the nearest MAX_LIVE with a
## sitter model, within RANGE and with the viewer in front of the canvas.
func wanted(head: Vector3) -> Array[int]:
	var near: Array = []
	for i in portraits.size():
		if i >= sitters.size() or not LivePortrait.has_model(sitters[i]):
			continue
		var p: Transform3D = portraits[i]
		var d := p.origin.distance_to(head)
		if d > RANGE or (p.affine_inverse() * head).z < 0.3:
			continue
		near.append([d, i])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[int] = []
	for e: Array in near.slice(0, MAX_LIVE):
		out.append(e[1])
	return out


func update_live(head: Vector3) -> void:
	var want := wanted(head)
	for i: int in live.keys():
		var lp: LivePortrait = live[i]
		if not is_instance_valid(lp):
			live.erase(i)
		elif not want.has(i):
			lp.leaving = true
			live.erase(i)
			_next_idle.erase(i)
	for i in want:
		if live.has(i):
			continue
		var lp := LivePortrait.new()
		lp.name = "LivePortrait%d" % i
		add_child(lp)
		lp.global_transform = portraits[i]
		lp.setup(sitters[i])
		lp.look_toward(head)
		live[i] = lp
		if float(_spoke_at.get(i, 0.0)) > Time.get_ticks_msec() / 1000.0:
			lp.gesture(&"wave")
		_spoke_at.erase(i)


func _on_spoke(portrait: Transform3D) -> void:
	for i in portraits.size():
		if not portraits[i].origin.is_equal_approx(portrait.origin):
			continue
		var lp: LivePortrait = live.get(i)
		if lp != null and is_instance_valid(lp):
			lp.gesture(&"wave")
		else:
			_spoke_at[i] = Time.get_ticks_msec() / 1000.0 + 2.0
		return

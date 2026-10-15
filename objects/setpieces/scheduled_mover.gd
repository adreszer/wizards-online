class_name ScheduledMover
extends AnimatableBody3D
## A body whose pose is a pure function of the world's shared time
## (NetworkManager.server_time()): every client computes the same pose at the same
## moment and late joiners need no sync. Riders are carried (sync_to_physics).
##
## Modes:
##   STOPS  rest at each of `stops` (yaw degrees about the origin) for `hold` seconds,
##          then swing to the next one over `move` seconds; loops.
##   SPIN   turn about Y at `speed` degrees per second.
##   BOB    rise and fall by `amplitude` metres with `period` seconds.
## `phase` shifts the schedule so neighbouring movers never move in step.

enum Mode { STOPS, SPIN, BOB }

signal stop_reached(index: int)

@export var mode: Mode = Mode.STOPS
@export var stops: PackedFloat32Array = PackedFloat32Array([0.0, 90.0])
@export var hold: float = 20.0
@export var move: float = 6.0
@export var speed: float = 12.0
@export var amplitude: float = 1.0
@export var period: float = 8.0
@export var phase: float = 0.0
## Tests and tools may pin the clock (seconds); NAN uses the world's time.
var time_override := NAN

var _base: Transform3D
var _last_stop := -2


func _ready() -> void:
	sync_to_physics = true
	_base = transform


static func world_time() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var nm: Node = tree.root.get_node_or_null("NetworkManager") if tree != null else null
	if nm != null and nm.has_method("server_time"):
		return nm.server_time()
	return Time.get_unix_time_from_system()


func now() -> float:
	return time_override if not is_nan(time_override) else world_time()


func cycle() -> float:
	return stops.size() * (hold + move)


## Index of the stop the mover rests at at time `t`, or -1 while it is swinging.
func stop_at(t: float) -> int:
	if mode != Mode.STOPS or stops.is_empty():
		return -1
	var local := fposmod(t + phase, cycle())
	var i := int(local / (hold + move))
	return i if local - i * (hold + move) < hold else -1


func yaw_at(t: float) -> float:
	match mode:
		Mode.SPIN:
			return fposmod((t + phase) * speed, 360.0)
		Mode.STOPS:
			if stops.is_empty():
				return 0.0
			var local := fposmod(t + phase, cycle())
			var i := int(local / (hold + move))
			var into := local - i * (hold + move)
			var a := stops[i]
			var b := stops[(i + 1) % stops.size()]
			if into < hold:
				return a
			var k := smoothstep(0.0, 1.0, (into - hold) / move)
			return lerpf(a, b, k)
	return 0.0


func offset_at(t: float) -> float:
	return sin((t + phase) / period * TAU) * amplitude if mode == Mode.BOB else 0.0


func _physics_process(_delta: float) -> void:
	var t := now()
	var xf := _base
	if mode == Mode.BOB:
		xf.origin.y += offset_at(t)
	else:
		xf.basis = _base.basis * Basis(Vector3.UP, deg_to_rad(yaw_at(t)))
	transform = xf
	var s := stop_at(t)
	if s != _last_stop:
		_last_stop = s
		if s >= 0:
			stop_reached.emit(s)

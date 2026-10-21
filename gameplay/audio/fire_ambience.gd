class_name FireAmbience
extends Node3D
## The crackle of fires near the listener. The castle has hundreds of wall torches,
## so instead of a loop on each, a few voices move to the nearest burning ones
## (WallTorch.GROUP) and the nearest village hearths (HEARTH_GROUP, markers at the
## fire). world.gd adds it.

const HEARTH_GROUP := &"hearths"
const TORCH_LOOP := preload("res://assets/audio/world/torch_loop.wav")
const HEARTH_LOOP := preload("res://assets/audio/world/hearth_loop.wav")
const TORCH_VOICES := 4
const HEARTH_VOICES := 2
const TORCH_RANGE := 9.0
const HEARTH_RANGE := 16.0
## Seconds between re-picking the nearest fires.
const INTERVAL := 0.25

## voice -> the node it is placed at (null = idle)
var _sources := {}
var _torch_voices: Array[AudioStreamPlayer3D] = []
var _hearth_voices: Array[AudioStreamPlayer3D] = []
var _wait := 0.0


func _ready() -> void:
	for i in TORCH_VOICES:
		_torch_voices.append(Sfx.loop_player(self, "Torch%d" % i, TORCH_LOOP, -12.0, TORCH_RANGE))
	for i in HEARTH_VOICES:
		_hearth_voices.append(Sfx.loop_player(self, "Hearth%d" % i, HEARTH_LOOP, -6.0, HEARTH_RANGE))


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = INTERVAL
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	var torches := get_tree().get_nodes_in_group(WallTorch.GROUP).filter(func(t: Node) -> bool: return (t as WallTorch).burning())
	assign(_torch_voices, nearest(torches, at, TORCH_RANGE, TORCH_VOICES))
	assign(_hearth_voices, nearest(get_tree().get_nodes_in_group(HEARTH_GROUP), at, HEARTH_RANGE, HEARTH_VOICES))


## Up to `count` of `nodes` within `radius` of `at`, nearest first.
static func nearest(nodes: Array, at: Vector3, radius: float, count: int) -> Array:
	var close := nodes.filter(func(n: Node) -> bool: return (n as Node3D).global_position.distance_squared_to(at) < radius * radius)
	close.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	return close.slice(0, count)


## Keeps voices on fires still in `targets`, moves free voices to the new ones.
func assign(voices: Array[AudioStreamPlayer3D], targets: Array) -> void:
	var free: Array[AudioStreamPlayer3D] = []
	for v in voices:
		var source: Node = _sources.get(v)
		if source != null and is_instance_valid(source) and targets.has(source):
			targets.erase(source)
		else:
			_sources[v] = null
			v.stop()
			free.append(v)
	for i in mini(free.size(), targets.size()):
		_sources[free[i]] = targets[i]
		free[i].global_position = (targets[i] as Node3D).global_position
		Sfx.start_loop(free[i])


## The fire a voice is placed at, or null (tests).
func source_of(voice: AudioStreamPlayer3D) -> Node:
	return _sources.get(voice)

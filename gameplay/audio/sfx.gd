class_name Sfx
extends RefCounted
## Positional sound helpers for objects in the world.
##
## Loop points live in the gitignored .import files, so a WAV meant to loop is set
## to loop over its whole length here (the held torch, spells in flight, gears…).


static func looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


## Plays `stream` once at `parent` (offset by `at` in its space) and frees the player
## afterwards. Returns the player (tests read its stream).
static func play_at(parent: Node3D, stream: AudioStream, volume_db: float = 0.0, max_distance: float = 30.0, at: Vector3 = Vector3.ZERO) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.position = at
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()
	return p


## A looping player under `parent`, not yet playing; play() starts it at a random
## point so neighbouring copies never pulse in step.
static func loop_player(parent: Node3D, node_name: String, stream: AudioStreamWAV, volume_db: float, max_distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = looped(stream)
	p.volume_db = volume_db
	p.max_distance = max_distance
	parent.add_child(p)
	return p


## Starts a loop player at a random point of its stream (no-op while it plays).
static func start_loop(p: AudioStreamPlayer3D) -> void:
	if not p.playing:
		p.play(randf() * p.stream.get_length())

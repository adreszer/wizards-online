class_name ServerClock
extends RefCounted
## One clock for everyone in the world: the server's time (seconds since the epoch).
## Samples come with ping replies (server time + the round trip of that ping) and the
## join snapshot (no round trip). The offset to the local clock keeps the sample with the
## shortest round trip of the last few, which is the least delayed one. Offline, or
## before the first sample, it is the local system clock.

const WINDOW := 8

var _offset := 0.0          # server seconds - local seconds
var _has_sample := false
var _samples: Array = []    # [rtt_ms, offset]


static func local_seconds() -> float:
	return Time.get_unix_time_from_system()


func now() -> float:
	return local_seconds() + (_offset if _has_sample else 0.0)


func has_sample() -> bool:
	return _has_sample


## `server_ms` is the server clock when it answered; `rtt_ms` the round trip (-1: unknown).
func add_sample(server_ms: float, rtt_ms: int) -> void:
	var one_way := (rtt_ms / 2000.0) if rtt_ms >= 0 else 0.0
	var offset := server_ms / 1000.0 + one_way - local_seconds()
	_samples.append([rtt_ms if rtt_ms >= 0 else 100000, offset])
	if _samples.size() > WINDOW:
		_samples.pop_front()
	var best: Array = _samples[0]
	for s: Array in _samples:
		if s[0] < best[0]:
			best = s
	_offset = best[1]
	_has_sample = true


func reset() -> void:
	_samples.clear()
	_has_sample = false
	_offset = 0.0

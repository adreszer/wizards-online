class_name SoundLoops
extends RefCounted
## Loop points live in the gitignored .import files, so a WAV meant to loop is set
## to loop over its whole length here (the held torch, spell projectiles in flight).


static func looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

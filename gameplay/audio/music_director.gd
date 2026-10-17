class_name MusicDirector
extends Node
## Background music that follows the school clock: the day track from dawn, the
## night track from dusk. A phase change crossfades to the other track, and each
## track loops by crossfading its own end into its start, so the files need no
## exact loop points. Plays on the Music bus (default_bus_layout.tres), not
## positional. Added by castle.gd next to the DayNightCycle it listens to.
## With `fixed_track` set it plays only that track: the game root uses one for
## the main theme behind the menu (core/game.gd), stopped when the world loads.

const TRACKS := {
	&"day": preload("res://assets/audio/music/music_castle_day.mp3"),
	&"night": preload("res://assets/audio/music/music_castle_night.mp3"),
	&"main_theme": preload("res://assets/audio/music/music_main_theme.mp3"),
}
## Seconds of overlap when a track loops back to its start.
const LOOP_FADE := 6.0
## Tracks that end on their own (a fade to silence) and need only this much overlap.
const LOOP_FADE_BY_TRACK := {&"main_theme": 0.5}
## Seconds of overlap when the time of day switches tracks.
const SWITCH_FADE := 8.0
## Seconds the music takes to rise from silence when the level starts.
const START_FADE := 3.0

@export var volume_db: float = -6.0
## Seconds between checks of the phase and the loop point.
@export var interval: float = 0.25

## Plays only this track, whatever the time of day (empty: follow the clock).
@export var fixed_track: StringName = &""

## Where the phase comes from; without one the shared school clock is read.
var cycle: DayNightCycle
## The track playing now (&"day", &"night"), empty before the first update.
var current: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array[Tween] = [null, null]
var _timer := 0.0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = &"Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	update()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	update()


## The track for a phase of the school day.
static func track_for(phase: SchoolClock.Phase) -> StringName:
	return &"day" if phase == SchoolClock.Phase.DAWN or phase == SchoolClock.Phase.DAY else &"night"


## Switches track when the phase calls for another one and loops the one playing.
func update() -> void:
	var want := fixed_track
	if want.is_empty():
		var phase := cycle.phase if cycle != null else SchoolClock.phase_of(NetworkManager.school_hours())
		want = track_for(phase)
	if want != current:
		_play(want, START_FADE if current.is_empty() else SWITCH_FADE)
		return
	var p := _players[_active]
	var overlap := float(LOOP_FADE_BY_TRACK.get(current, LOOP_FADE))
	if p.playing and p.stream != null and p.get_playback_position() >= p.stream.get_length() - overlap:
		_play(current, overlap)


## Starts again from silence (after `stop`).
func start() -> void:
	current = &""
	set_process(true)
	update()


## Fades everything out over `fade` seconds and stays quiet until `start`.
func stop(fade := 2.0) -> void:
	set_process(false)
	current = &""
	for i in _players.size():
		if _players[i].playing:
			_fade(i, -80.0, fade, true)


## Starts `track` from the top on the idle player and crossfades over `fade` seconds.
func _play(track: StringName, fade: float) -> void:
	current = track
	var old := _active
	_active = 1 - _active
	var p := _players[_active]
	p.stream = TRACKS[track]
	p.volume_db = -80.0
	p.play()
	_fade(_active, volume_db, fade)
	if _players[old].playing:
		_fade(old, -80.0, fade, true)


func _fade(index: int, to_db: float, seconds: float, stop_after := false) -> void:
	if _tweens[index] != null:
		_tweens[index].kill()
	var p := _players[index]
	var tween := create_tween()
	# Fading the linear gain sounds even; fading decibels drops away too fast.
	tween.tween_method(func(g: float) -> void: p.volume_db = linear_to_db(maxf(g, 0.0001)),
		db_to_linear(p.volume_db), db_to_linear(to_db), seconds)
	if stop_after:
		tween.tween_callback(p.stop)
	_tweens[index] = tween

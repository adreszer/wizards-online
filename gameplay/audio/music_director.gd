class_name MusicDirector
extends Node
## Background music that follows the school clock and the local player's area:
## by day the castle track indoors and the grounds track out on open terrain
## (zone kind `grounds`: estate, lake, village…; walled courtyards count as the
## castle), the night track everywhere from dusk, and the lesson track inside a
## classroom while a lesson runs there (any hour), the flying track while the
## local player rides a broom (any hour), the mystery track inside a hidden room
## (zone kind `secret`). A change crossfades to the other
## track, which resumes where it was left, and each track loops by crossfading its
## own end into its start, so the files need no exact loop points. Plays on the
## Music bus (default_bus_layout.tres), not positional. Added by castle.gd next
## to the DayNightCycle it listens to.
## Feasts, duels and mysteries set `event_track`, which wins over the clock and the
## area until they clear it. ONE_SHOT tracks (the sorting ceremony, the house cup
## fanfare) play once and clear `event_track` themselves when they end.
## With `fixed_track` set it plays only that track: the game root uses one for
## the main theme behind the menu (core/game.gd), stopped when the world loads.

const TRACKS := {
	&"day": preload("res://assets/audio/music/music_castle_day.mp3"),
	&"night": preload("res://assets/audio/music/music_castle_night.mp3"),
	&"main_theme": preload("res://assets/audio/music/music_main_theme.mp3"),
	&"grounds": preload("res://assets/audio/music/music_grounds.mp3"),
	&"lesson": preload("res://assets/audio/music/music_lesson.mp3"),
	&"feast": preload("res://assets/audio/music/music_feast.mp3"),
	&"duel": preload("res://assets/audio/music/music_duel.mp3"),
	&"mystery": preload("res://assets/audio/music/music_mystery.mp3"),
	&"flying": preload("res://assets/audio/music/music_flying.mp3"),
	&"sorting": preload("res://assets/audio/music/music_sorting.mp3"),
	&"house_cup": preload("res://assets/audio/music/music_house_cup.mp3"),
}
## Tracks with a real ending: they play once instead of looping.
const ONE_SHOT: Array[StringName] = [&"sorting", &"house_cup"]
## Seconds of overlap when a track loops back to its start.
const LOOP_FADE := 6.0
## Tracks that end on their own (a fade to silence) and need only this much overlap.
const LOOP_FADE_BY_TRACK := {&"main_theme": 0.5}
## Seconds of overlap when the time of day switches tracks.
const SWITCH_FADE := 8.0
## Seconds of overlap when the area or an event changes the track (castle, grounds,
## lesson, feast…); the day/night switch uses SWITCH_FADE.
const AREA_FADE := 4.0
## Seconds the player must stay in or out (of the grounds, of a lesson, on a broom) before the
## music follows (doorways, gaps between zones).
const OUTDOOR_DELAY := 3.0
## Area kinds that play the grounds music by day.
const OUTDOOR_KINDS: Array[String] = ["grounds"]
## Area kinds that play the mystery track (hidden rooms).
const SECRET_KINDS: Array[String] = ["secret"]
## Seconds the music takes to rise from silence when the level starts.
const START_FADE := 3.0

@export var volume_db: float = -6.0
## Seconds between checks of the phase and the loop point.
@export var interval: float = 0.25

## Plays only this track, whatever the time of day (empty: follow the clock).
@export var fixed_track: StringName = &""
## Plays this track over the clock and the area while set (&"feast", &"duel",
## &"mystery"…); empty when no event is on. It starts from the top each time.
var event_track: StringName = &""
## Open lessons (area id → lesson) to follow instead of NetworkManager's (tests).
var lessons_override: Variant = null

## Where the phase comes from; without one the shared school clock is read.
var cycle: DayNightCycle
## The local player's area, set when the local player spawns.
var tracker: AreaTracker
## The local player's movement (is_flying), set when the local player spawns.
var movement: PlayerMovement
## The track playing now (&"day", &"night", &"grounds"…), empty before the first update.
var current: StringName = &""
## Whether the music treats the player as outdoors (follows the area after OUTDOOR_DELAY).
var outdoors := false
## Whether the music treats the player as inside a running lesson.
var in_lesson := false
## Whether the music treats the player as flying.
var flying := false
## Whether the music treats the player as inside a hidden room.
var in_secret := false

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array[Tween] = [null, null]
var _timer := 0.0
var _outdoor_for := 0.0
## Where each track was left (seconds), so it resumes instead of starting over.
var _positions := {}


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = &"Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	GameEvents.local_player_spawned.connect(func(player: Node) -> void:
		tracker = player.get("area_tracker")
		movement = player.get("movement"))
	GameEvents.local_player_removed.connect(func(_p: Node) -> void:
		tracker = null
		movement = null)
	update()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	update(interval)


## The track for a phase of the school day, indoors or out, in a lesson, on a broom.
static func track_for(phase: SchoolClock.Phase, outside := false, lesson := false, on_broom := false, secret := false) -> StringName:
	if lesson:
		return &"lesson"
	if on_broom:
		return &"flying"
	if secret:
		return &"mystery"
	if phase == SchoolClock.Phase.DAWN or phase == SchoolClock.Phase.DAY:
		return &"grounds" if outside else &"day"
	return &"night"


## Switches track when the phase or the area calls for another one and loops the
## one playing. `dt`: seconds since the last update (for OUTDOOR_DELAY).
func update(dt := 0.0) -> void:
	var want := fixed_track
	if want.is_empty():
		_follow_area(dt)
		var phase := cycle.phase if cycle != null else SchoolClock.phase_of(NetworkManager.school_hours())
		want = event_track if not event_track.is_empty() else track_for(phase, outdoors, in_lesson, flying, in_secret)
	if want != current:
		var fade := AREA_FADE
		if current.is_empty():
			fade = START_FADE
		elif [current, want].has(&"night") and ([current, want].has(&"day") or [current, want].has(&"grounds")):
			fade = SWITCH_FADE
		_play(want, fade, fixed_track.is_empty() and want != event_track)
		return
	var p := _players[_active]
	if ONE_SHOT.has(current):
		if not p.playing or p.get_playback_position() >= p.stream.get_length() - 0.25:
			if event_track == current:
				event_track = &""
		return
	var overlap := float(LOOP_FADE_BY_TRACK.get(current, LOOP_FADE))
	if p.playing and p.stream != null and p.get_playback_position() >= p.stream.get_length() - overlap:
		_play(current, overlap)


func _follow_area(dt: float) -> void:
	var out_here := tracker != null and OUTDOOR_KINDS.has(tracker.current_kind())
	var lesson_here := false
	if tracker != null and tracker.current_zone != null:
		var lessons: Dictionary = lessons_override if lessons_override != null else NetworkManager.get_lessons()
		lesson_here = lessons.has(str(tracker.current_area_id()))
	var flying_here := movement != null and movement.is_flying
	var secret_here := tracker != null and SECRET_KINDS.has(tracker.current_kind())
	if out_here == outdoors and lesson_here == in_lesson and flying_here == flying and secret_here == in_secret:
		_outdoor_for = 0.0
		return
	_outdoor_for += dt
	if _outdoor_for >= OUTDOOR_DELAY or current.is_empty():
		outdoors = out_here
		in_lesson = lesson_here
		flying = flying_here
		in_secret = secret_here
		_outdoor_for = 0.0


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


## Starts `track` on the idle player and crossfades over `fade` seconds; with
## `resume` from where it was last left (a loop restart always starts at the top).
func _play(track: StringName, fade: float, resume := false) -> void:
	var old := _active
	if _players[old].playing and not current.is_empty():
		_positions[current] = 0.0 if track == current else _players[old].get_playback_position()
	current = track
	_active = 1 - _active
	var p := _players[_active]
	p.stream = TRACKS[track]
	p.volume_db = -80.0
	var from := float(_positions.get(track, 0.0)) if resume else 0.0
	if from > p.stream.get_length() - LOOP_FADE - 10.0:
		from = 0.0   # too close to the end: a fresh start sounds better than an instant loop
	p.play(from)
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

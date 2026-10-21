class_name AmbienceDirector
extends Node
## The sound of the place the local player stands in: a looping bed per area
## (assets/audio/ambience/<id>.wav), chosen by area id, then by the area's kind,
## with night versions outdoors and a busy great hall while a meal is served. On
## rainy days (Seasons.rain_today) a second layer adds rain, on the grass outside
## or on the windows indoors, and thunder rolls now and then; underground rooms
## hear neither. Changes crossfade. Plays on the Ambience bus, not positional.
## The beds are MP3s whose last OVERLAP seconds repeat their first: each one loops
## by crossfading its end into a fresh start, so MP3 padding never gaps it.
## Added by castle.gd next to the MusicDirector.

const PATH := "res://assets/audio/ambience/%s.mp3"
## Seconds at the end of each bed that repeat its start (the loop crossfade).
const OVERLAP := 2.0
## Area id -> bed (the great hall and the forest edge are chosen in bed_for).
const BY_AREA := {
	"library": "amb_library", "great_archive": "amb_library", "reading_room": "amb_library",
	"staff_library": "amb_library", "scriptorium": "amb_library", "bindery": "amb_library",
	"records_room": "amb_library", "study_hall": "amb_library",
	"restricted_stacks": "amb_restricted_stacks", "hidden_records_room": "amb_restricted_stacks",
	"dungeon_corridor": "amb_dungeon", "old_cells": "amb_dungeon", "undercroft": "amb_dungeon",
	"lake_tunnel": "amb_dungeon", "lake_passage": "amb_dungeon",
	"cellars": "amb_cellars", "wine_cellar": "amb_cellars", "cold_store": "amb_cellars", "hidden_wine_cellar": "amb_cellars",
	"kitchens": "amb_kitchens", "greenhouse": "amb_greenhouse", "bathing_hall": "amb_bathing_hall", "roost": "amb_roost",
	"class_elixirs": "amb_classroom_elixirs", "office_elixirs": "amb_classroom_elixirs",
	"hidden_class_elixirs": "amb_classroom_elixirs", "apothecary": "amb_classroom_elixirs",
	"class_stargazing": "amb_star_tower_night", "duelling_hall": "amb_duelling_hall",
	"stone_circle": "amb_stone_circle", "sky_bridge": "amb_battlements", "viaduct": "amb_battlements",
	"boathouse": "amb_boathouse", "landing_stage": "amb_boathouse",
	"lake_shore": "amb_lake_shore", "lake_terrace": "amb_lake_shore",
}
## Area ids starting with these -> bed.
const BY_PREFIX := {"clock_tower": "amb_clock_tower", "archive_wing": "amb_library", "hidden_": "amb_hidden_room"}
## Area kind -> bed ("" = quiet: shops, the inn, the post office).
const BY_KIND := {
	"corridor": "amb_corridor", "stair_turret": "amb_corridor", "hall": "amb_corridor", "shaft": "amb_corridor",
	"room": "amb_corridor", "classroom": "amb_corridor", "tower": "amb_tower_wind", "secret": "amb_hidden_room",
	"common_room": "amb_common_room", "dormitory": "amb_dormitory_night", "library": "amb_library",
}
## Kinds under the open sky (no zone at all counts as outdoors too).
const OUTDOOR_KINDS: Array[String] = ["grounds", "outdoor", "bridge", "station"]
## Beds below ground: no rain or thunder reaches them.
const UNDERGROUND: Array[String] = ["amb_dungeon", "amb_cellars", "amb_hidden_room", "amb_restricted_stacks"]
## Per-bed level (dB) where the shared -24 dB RMS is too much (a room's quiet tone).
const GAIN := {"amb_corridor": -4.0, "amb_rain_window": -6.0, "amb_restricted_stacks": -8.0, "amb_hidden_room": -4.0}
const FADE := 3.0
const THUNDER_COUNT := 4
## Seconds between rolls of thunder on a rainy day.
const THUNDER_GAP := Vector2(45.0, 150.0)

@export var interval: float = 0.5

## The day/night cycle (night beds); without one the school clock is read.
var cycle: DayNightCycle
var tracker: AreaTracker
## The bed and rain layer playing now ("" = none), for tests.
var bed := ""
var rain := ""
## Overrides for tests: rain (null = Seasons.rain_today).
var rain_override: Variant = null

var _layers := {}   # "bed"/"rain" -> [AudioStreamPlayer, AudioStreamPlayer, active index]
var _layer_ids := {}   # "bed"/"rain" -> the bed id playing
var _layer_tweens := {}
var _streams := {}
var _timer := 0.0
var _thunder_in := 60.0
var _thunder: AudioStreamPlayer


func _ready() -> void:
	for layer: String in ["bed", "rain"]:
		var pair: Array = []
		for i in 2:
			var p := AudioStreamPlayer.new()
			p.name = "%s%d" % [layer.capitalize(), i]
			p.bus = &"Ambience"
			p.volume_db = -80.0
			add_child(p)
			pair.append(p)
		pair.append(0)
		_layers[layer] = pair
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	_thunder.bus = &"Ambience"
	add_child(_thunder)
	GameEvents.local_player_spawned.connect(func(player: Node) -> void: tracker = player.get("area_tracker"))
	GameEvents.local_player_removed.connect(func(_p: Node) -> void: tracker = null)


func _process(delta: float) -> void:
	# A bed near its end crossfades into a fresh start of itself.
	for layer: String in _layers:
		var pair: Array = _layers[layer]
		var p: AudioStreamPlayer = pair[pair[2]]
		if p.playing and p.stream != null and loop_due(p.get_playback_position(), p.stream.get_length()):
			_crossfade(layer, p.stream, 0.0, OVERLAP, float(GAIN.get(_layer_ids.get(layer, ""), 0.0)))
	_thunder_in -= delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	update()


## Picks the bed and the rain layer for where the local player is now.
func update() -> void:
	var zone := tracker.current_zone if tracker != null else null
	var area := str(zone.area_id) if zone != null else ""
	var kind := zone.kind if zone != null else ""
	var feast := get_parent().get_node_or_null("FeastMeals") if get_parent() != null else null
	var want := bed_for(area, kind, is_night(), feast != null and str(feast.get("serving")) != "")
	var raining: bool = rain_override if rain_override != null else Seasons.rain_today
	var outside := zone == null or OUTDOOR_KINDS.has(kind)
	var wet := rain_for(want, outside, raining)
	_switch("bed", want)
	_switch("rain", wet)
	bed = want
	rain = wet
	if wet != "" and _thunder_in <= 0.0:
		_thunder_in = randf_range(THUNDER_GAP.x, THUNDER_GAP.y)
		var roll := _stream("thunder_%d" % randi_range(1, THUNDER_COUNT))
		if roll != null:
			_thunder.stream = roll
			_thunder.volume_db = -4.0 if outside else -14.0
			_thunder.play()


func is_night() -> bool:
	var phase := cycle.phase if cycle != null else SchoolClock.phase_of(NetworkManager.school_hours())
	return phase == SchoolClock.Phase.NIGHT or phase == SchoolClock.Phase.DUSK


## Whether a bed `length` s long, now at `position`, should crossfade into its start.
static func loop_due(position: float, length: float) -> bool:
	return position >= length - OVERLAP


## The bed for an area (its id, else its kind; "" kind = outside every zone).
static func bed_for(area: String, kind: String, night: bool, meal: bool) -> String:
	if area == "great_hall":
		return "amb_great_hall_busy" if meal else "amb_great_hall_empty"
	if area == "forest_edge":
		return "amb_forest_night" if night else "amb_forest"
	if BY_AREA.has(area):
		return BY_AREA[area]
	for prefix: String in BY_PREFIX:
		if area.begins_with(prefix):
			return BY_PREFIX[prefix]
	if kind == "" or OUTDOOR_KINDS.has(kind):
		return "amb_grounds_night" if night else "amb_grounds_day"
	return BY_KIND.get(kind, "")


## The rain layer over `bed` ("" when dry or underground).
static func rain_for(bed_id: String, outside: bool, raining: bool) -> String:
	if not raining or UNDERGROUND.has(bed_id):
		return ""
	return "amb_rain_outdoor" if outside else "amb_rain_window"


func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		var path := PATH % id
		_streams[id] = load(path) if id != "" and ResourceLoader.exists(path) else null
	return _streams[id]


## Crossfades `layer` to the bed `id` (or to silence), starting somewhere inside it.
func _switch(layer: String, id: String) -> void:
	if _layer_ids.get(layer, "") == id:
		return
	_layer_ids[layer] = id
	var stream := _stream(id)
	var start := randf() * maxf(0.0, stream.get_length() - OVERLAP - FADE) if stream != null else 0.0
	_crossfade(layer, stream, start, FADE, float(GAIN.get(id, 0.0)))


## Fades the layer's playing player out and the other in with `stream` from `start`.
func _crossfade(layer: String, stream: AudioStream, start: float, fade: float, gain_db: float) -> void:
	var pair: Array = _layers[layer]
	var current: AudioStreamPlayer = pair[pair[2]]
	var next: AudioStreamPlayer = pair[1 - int(pair[2])]
	pair[2] = 1 - int(pair[2])
	if _layer_tweens.get(layer) != null:
		(_layer_tweens[layer] as Tween).kill()
	var tween := create_tween().set_parallel()
	_layer_tweens[layer] = tween
	tween.tween_property(current, "volume_db", -80.0, fade)
	next.stop()
	next.stream = stream
	if stream != null:
		next.volume_db = -80.0
		next.play(start)
		tween.tween_property(next, "volume_db", gain_db, fade)
	tween.chain().tween_callback(current.stop)

class_name SchoolBells
extends Node
## Rings the castle bell from the timetable (NetworkManager.timetable) on the
## shared world clock, so every player hears it at the same moment: one stroke
## five minutes before a lesson, three when it starts, two when it ends, each
## with a HUD notification naming the subject and room. The bell is heard
## everywhere in the castle (not positional). Added by castle.gd.

const STROKE_GAP := 0.9
## Strokes per event.
const STROKES := {"warn": 1, "start": 3, "end": 2}

## Seconds between checks.
@export var interval: float = 0.5
@export var volume_db: float = -10.0

var _player: AudioStreamPlayer
var _last := NAN
var _timer := 0.0
## Events rung so far (tests read it): [{event, entry, at}].
var rung: Array[Dictionary] = []


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Bell"
	_player.stream = bell_stream()
	_player.volume_db = volume_db
	_player.max_polyphony = 4
	add_child(_player)
	# A new or reloaded timetable starts listening from now on: no bells for the past.
	NetworkManager.timetable_changed.connect(func() -> void: _last = NetworkManager.server_time())


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	check(NetworkManager.server_time())


## Rings for every timetable moment since the last check (the first check only
## remembers the time).
func check(now: float) -> void:
	if is_nan(_last) or now < _last:
		_last = now
		return
	var events := NetworkManager.timetable.events_between(_last, now)
	_last = now
	if events.is_empty():
		return
	# After a long stall only the latest moment matters.
	ring(events[events.size() - 1])


func ring(ev: Dictionary) -> void:
	rung.append(ev)
	var entry: Dictionary = ev.entry
	var title := Timetable.title_of(entry)
	var room := Timetable.room_name(get_tree(), str(entry.area))
	var text := ""
	match str(ev.event):
		"warn":
			text = tr("TIMETABLE_STARTS_SOON") % [title, room]
		"start":
			text = tr("TIMETABLE_STARTS_NOW") % [title, room]
		_:
			text = tr("TIMETABLE_ENDED") % title
	if GameSettings.get_value("captions"):
		text = tr("CAPTION_BELL") % int(STROKES.get(str(ev.event), 1)) + " " + text
	GameEvents.notification_requested.emit(text, 6.0)
	GameEvents.school_bell_rang.emit(str(ev.event), entry)
	_strike(int(STROKES.get(str(ev.event), 1)))


func _strike(count: int) -> void:
	for i in count:
		if not is_inside_tree():
			return
		_player.play()
		if i < count - 1:
			await get_tree().create_timer(STROKE_GAP).timeout


## A bronze bell stroke, synthesised once: inharmonic partials (hum, prime,
## tierce, quint, nominal…) each decaying at its own rate.
static var _stream: AudioStreamWAV

static func bell_stream() -> AudioStreamWAV:
	if _stream != null:
		return _stream
	var rate := 22050
	var seconds := 3.2
	var base := 392.0
	var partials := [[0.5, 0.5, 0.9], [1.0, 1.0, 1.6], [1.19, 0.6, 2.2], [1.5, 0.45, 2.8], [2.0, 0.55, 3.4], [2.5, 0.25, 4.5], [3.0, 0.2, 5.5]]
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for p: Array in partials:
			v += float(p[1]) * exp(-float(p[2]) * t) * sin(TAU * base * float(p[0]) * t)
		v *= minf(1.0, t * 400.0) * 0.28   # a 2.5 ms strike, headroom for the sum
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	_stream = AudioStreamWAV.new()
	_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_stream.mix_rate = rate
	_stream.stereo = false
	_stream.data = data
	return _stream

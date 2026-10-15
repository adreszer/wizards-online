class_name SchoolClock
extends RefCounted
## The school's time of day. It is a pure function of the world's shared time
## (NetworkManager.server_time()), so every client agrees without anything being
## streamed: hours = ((world time + offset) / day length) mod 1 × 24.
## The server owns the day length (school_rules.json `day_length_minutes`) and the
## offset (moved by the /time cheat, persisted in storage) and sends both as
## OP_CLOCK; offline the defaults below apply and /time moves the local offset.
## nakama/modules/school.lua mirrors hours_at / offset_for.

enum Phase { NIGHT, DAWN, DAY, DUSK }

## One school day takes an hour of real time unless the server says otherwise.
const DEFAULT_DAY_SECONDS := 3600.0
## Phase boundaries in school hours: dawn 5:00–7:00, day until 19:00, dusk until 21:00.
const DAWN_START := 5.0
const DAY_START := 7.0
const DUSK_START := 19.0
const NIGHT_START := 21.0

var day_seconds := DEFAULT_DAY_SECONDS
var offset := 0.0   # seconds added to the world time


## School hours (0 ≤ h < 24) at `world_time` seconds.
func hours_at(world_time: float) -> float:
	return fposmod((world_time + offset) / day_seconds, 1.0) * 24.0


## The offset that makes `hours_at(world_time)` equal `hours`.
func offset_for(world_time: float, hours: float) -> float:
	return fposmod(fposmod(hours, 24.0) / 24.0 * day_seconds - world_time, day_seconds)


## Takes the server's {day, offset}; returns true when anything changed.
func apply(payload: Dictionary) -> bool:
	var day := float(payload.get("day", day_seconds))
	var off := float(payload.get("offset", offset))
	if day < 60.0:
		day = DEFAULT_DAY_SECONDS
	var changed := not is_equal_approx(day, day_seconds) or not is_equal_approx(off, offset)
	day_seconds = day
	offset = off
	return changed


func reset() -> void:
	day_seconds = DEFAULT_DAY_SECONDS
	offset = 0.0


static func phase_of(hours: float) -> Phase:
	if hours >= NIGHT_START or hours < DAWN_START:
		return Phase.NIGHT
	if hours < DAY_START:
		return Phase.DAWN
	if hours < DUSK_START:
		return Phase.DAY
	return Phase.DUSK


static func is_night(hours: float) -> bool:
	return phase_of(hours) == Phase.NIGHT


## "07:05" style text for the HUD.
static func format(hours: float) -> String:
	var minutes := int(floor(fposmod(hours, 24.0) * 60.0))
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Parses "14", "14:30", "7.5" into hours; returns -1.0 when it isn't a time.
static func parse(text: String) -> float:
	var t := text.strip_edges()
	if t.contains(":"):
		var parts := t.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return -1.0
		var h := parts[0].to_int()
		var m := parts[1].to_int()
		if h < 0 or h > 23 or m < 0 or m > 59:
			return -1.0
		return h + m / 60.0
	if not t.is_valid_float():
		return -1.0
	var v := t.to_float()
	return v if v >= 0.0 and v < 24.0 else -1.0


## Translation key of a phase (HUD tooltip, notifications).
static func phase_key(phase: Phase) -> String:
	return ["TIME_NIGHT", "TIME_DAWN", "TIME_DAY", "TIME_DUSK"][phase]

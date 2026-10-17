class_name Timetable
extends RefCounted
## The school week as the server sent it (OP_TIMETABLE): concrete lesson and
## self-study times in real time (epoch seconds), so every client agrees on when
## a lesson starts without knowing any time zone rules. The source is
## nakama/content/timetable.json (weekly slots in the school's time zone);
## nakama/modules/timetable.lua turns it into these occurrences. Times are shown
## in school time (the server's `tz` offset), the same for every player.
## Offline there is no timetable: lessons only happen in the online school.

const KIND_LESSON := "lesson"
const KIND_STUDY := "study"
## Bells warn this long before a start.
const WARNING_SECONDS := 5 * 60
const DAY_KEYS: Array[String] = ["DAY_MON", "DAY_TUE", "DAY_WED", "DAY_THU", "DAY_FRI", "DAY_SAT", "DAY_SUN"]

## [{id, kind, subject, area, professor, t0, t1}], sorted by t0.
var entries: Array[Dictionary] = []
## The school's UTC offset in minutes (school time = epoch + tz × 60).
var tz_minutes := 0
## True once the server has sent one (online).
var received := false
## Today in the school calendar (nakama/content/calendar.json): {term?: name key,
## week?: n, brk?: name key, exam: bool, next_term?: name key, next_day?: day number}.
var calendar: Dictionary = {}


func apply(payload: Dictionary) -> void:
	tz_minutes = int(payload.get("tz", 0))
	calendar = payload.get("cal", {}) if payload.get("cal", {}) is Dictionary else {}
	entries.clear()
	var raw: Variant = payload.get("slots", [])
	# An empty Lua table encodes as {}, so anything but an array is "no slots".
	if raw is Array:
		for s: Variant in raw:
			if not s is Dictionary:
				continue
			var d: Dictionary = s
			var t0 := float(d.get("t0", 0.0))
			var t1 := float(d.get("t1", 0.0))
			if t1 <= t0:
				continue
			entries.append({"id": str(d.get("id", "")), "kind": str(d.get("k", KIND_LESSON)), "subject": str(d.get("s", "")),
				"area": str(d.get("a", "")), "professor": str(d.get("p", "")), "t0": t0, "t1": t1, "exam": d.get("x", false) == true})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t0 < b.t0)
	received = true


func clear() -> void:
	entries.clear()
	calendar = {}
	tz_minutes = 0
	received = false


## Entries that have not ended at `now`, the running ones first; at most `limit` (0 = all).
func upcoming(now: float, limit: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if e.t1 > now:
			out.append(e)
			if limit > 0 and out.size() >= limit:
				break
	return out


## The entry running at `now` in `area` ("" = anywhere), or {}.
func current(now: float, area: String = "") -> Dictionary:
	for e in entries:
		if e.t0 <= now and now < e.t1 and (area == "" or e.area == area):
			return e
	return {}


## The next entry starting after `now`, or {}.
func next_after(now: float) -> Dictionary:
	for e in entries:
		if e.t0 > now:
			return e
	return {}


## Bell events with a moment in (from, to]: [{event: "warn" | "start" | "end", entry}].
func events_between(from: float, to: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if to <= from:
		return out
	for e in entries:
		for pair: Array in [["warn", e.t0 - WARNING_SECONDS], ["start", e.t0], ["end", e.t1]]:
			var at: float = pair[1]
			if at > from and at <= to:
				out.append({"event": pair[0], "entry": e, "at": at})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	return out


## School-time calendar fields of `t` (weekday 0 = Monday, hour, minute, day number).
func school_time(t: float) -> Dictionary:
	var local := int(floor(t)) + tz_minutes * 60
	var day := int(floor(local / 86400.0))
	var secs := local - day * 86400
	return {"weekday": posmod(day + 3, 7), "hour": secs / 3600, "minute": (secs % 3600) / 60, "day": day}


## "18:00" in school time.
func clock_text(t: float) -> String:
	var st := school_time(t)
	return "%02d:%02d" % [st.hour, st.minute]


## Translation key of the weekday of `t` (DAY_MON…).
func day_key(t: float) -> String:
	return DAY_KEYS[school_time(t).weekday]


## "Now: Charms (until 18:45)" or "Next: Charms · Mon 18:00"; "" without a timetable.
func status_line(now: float) -> String:
	if not received:
		return ""
	var running := current(now)
	if not running.is_empty():
		return TranslationServer.translate("HUD_LESSON_NOW") % [Timetable.title_of(running), clock_text(running.t1)]
	var next := next_after(now)
	if next.is_empty():
		return ""
	var when := clock_text(next.t0)
	if school_time(next.t0).day != school_time(now).day:
		when = TranslationServer.translate(day_key(next.t0)) + " " + when
	return TranslationServer.translate("HUD_LESSON_NEXT") % [Timetable.title_of(next), when]


## Where the school year stands today: "Autumn term, week 7 · exam week",
## "Holidays: …, no lessons" or "Between terms; … starts Mon 7 Jan"; "" without a calendar.
func calendar_line() -> String:
	if not received:
		return ""
	var tl := func(key: String) -> String: return TranslationServer.translate(key)
	if calendar.has("brk"):
		return tl.call("CALENDAR_HOLIDAY") % tl.call(str(calendar.brk))
	if calendar.has("term"):
		var line: String = tl.call("CALENDAR_TERM_WEEK") % [tl.call(str(calendar.term)), int(calendar.get("week", 1))]
		if calendar.get("exam", false) == true:
			line += " · " + tl.call("CALENDAR_EXAMS")
		return line
	if calendar.has("next_term"):
		var day := int(calendar.get("next_day", 0))
		var date := Time.get_date_dict_from_unix_time(day * 86400)
		return tl.call("CALENDAR_BETWEEN_TERMS") % [tl.call(str(calendar.next_term)), "%d.%02d.%d" % [date.day, date.month, date.year]]
	return ""


## The entry's title: its subject's name, or "Self-study".
static func title_of(entry: Dictionary) -> String:
	if entry.get("kind", KIND_LESSON) == KIND_STUDY and str(entry.get("subject", "")) == "":
		return TranslationServer.translate("TIMETABLE_STUDY")
	var def := SubjectRegistry.load_definition(str(entry.get("subject", "")))
	return TranslationServer.translate(def.display_name) if def != null else str(entry.get("subject", ""))


## Name of the room an entry is in: its AreaZone's display name, or the id.
static func room_name(tree: SceneTree, area_id: String) -> String:
	if tree != null:
		for zone in tree.get_nodes_in_group(AreaZone.GROUP):
			if str((zone as AreaZone).area_id) == area_id:
				return (zone as AreaZone).display_name()
	return area_id

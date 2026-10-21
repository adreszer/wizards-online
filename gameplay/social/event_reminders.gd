class_name EventReminders
extends Node
## Reminders for the calendar: five minutes before a school event (feature "events")
## or a meeting of one of your clubs, a notification says what and where, once each.
## Added by world.gd.

const AHEAD := 300.0
const CHECK_EVERY := 15.0

var _reminded: Dictionary = {}
var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	for r in due(NetworkManager.feature("events"), NetworkManager.feature("clubs"), NetworkManager.local_display_name, NetworkManager.server_time()):
		if not _reminded.has(r.key):
			_reminded[r.key] = true
			GameEvents.notification_requested.emit(tr("EVENT_REMINDER") % [r.title, Localization.area_name(r.area) if r.area != "" else tr("EVENT_ANYWHERE")], 8.0)


## Everything starting within AHEAD seconds of `now`: [{key, title, area}].
static func due(events: Dictionary, clubs: Dictionary, me: String, now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in (events.get("events", []) if events.get("events", []) is Array else []):
		var d: Dictionary = e
		var at := float(d.get("at", 0))
		if at > now and at - now <= AHEAD:
			out.append({"key": str(d.get("id", "")), "title": str(d.get("title", "")), "area": str(d.get("area", ""))})
	for c: Variant in (clubs.get("clubs", []) if clubs.get("clubs", []) is Array else []):
		var cd: Dictionary = c
		if not (cd.get("members", []) is Array and (cd.members as Array).has(me)):
			continue
		for b: Variant in (cd.get("bookings", []) if cd.get("bookings", []) is Array else []):
			var bd: Dictionary = b
			var at := float(bd.get("at", 0))
			if at > now and at - now <= AHEAD:
				out.append({"key": "%s@%d" % [cd.get("id", ""), int(at)], "title": str(cd.get("name", "")), "area": str(bd.get("area", ""))})
	return out


## The journal's calendar page: lessons, school events and club meetings in time order,
## then the fixed rhythm (meals) and where the school year stands.
static func calendar_bbcode(timetable: Timetable, events: Dictionary, clubs: Dictionary, now: float) -> String:
	var rows: Array = []
	for e in timetable.upcoming(now, 12):
		rows.append([float(e.t0), Timetable.title_of(e)])
	for e: Variant in (events.get("events", []) if events.get("events", []) is Array else []):
		var d: Dictionary = e
		var where: String = Localization.area_name(str(d.get("area", "")))
		rows.append([float(d.get("at", 0)), "[b]%s[/b]%s" % [str(d.get("title", "")), (" · " + where) if where != "" else ""]])
	for b: Variant in (events.get("clubs", []) if events.get("clubs", []) is Array else []):
		var bd: Dictionary = b
		rows.append([float(bd.get("at", 0)), TranslationServer.translate("CALENDAR_CLUB") % [str(bd.get("club", "")), Localization.area_name(str(bd.get("area", "")))]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var lines := PackedStringArray()
	if not timetable.calendar_line().is_empty():
		lines.append("[i]%s[/i]" % timetable.calendar_line())
	for r: Array in rows:
		var when: String = TranslationServer.translate("TIMETABLE_NOW") if r[0] <= now else "%s %s" % [TranslationServer.translate(timetable.day_key(r[0])), timetable.clock_text(r[0])]
		lines.append("%s   %s" % [when, r[1]])
	if rows.is_empty():
		lines.append(TranslationServer.translate("CALENDAR_EMPTY"))
	lines.append("")
	lines.append(TranslationServer.translate("CALENDAR_MEALS"))
	return "\n".join(lines)

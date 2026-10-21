class_name AdminPanel
extends FeaturePanel
## The in-game admin panel (/admin; admins only, the server checks every request):
## who is online and where (set role, house and year), a broadcast to the castle, the
## timetable (add, change or remove slots on top of the file), player reports, the chat
## log, school events, shared lesson plans to approve for self-study, and the Unfinished
## Wing's progress. Replaces tools/set_role.sh for day-to-day work.

var _tabs: TabContainer
var _pages: Dictionary = {}
var _who_list: RichTextLabel
var _name: LineEdit
var _role: OptionButton
var _house: SpinBox
var _year: SpinBox
var _broadcast: LineEdit
var _slot_fields: Dictionary = {}
var _out: Dictionary = {}

const ROLES := ["student", "prefect", "professor", "admin"]


func _ready() -> void:
	half_size = Vector2(460, 300)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "admin":
			open_panel())


func _page(key: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = tr(key)
	_tabs.add_child(page)
	_pages[key] = page
	return page


func _text_out(page: VBoxContainer, key: String) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	page.add_child(t)
	_out[key] = t
	return t


func _build() -> void:
	title_label.text = tr("ADMIN_TITLE")
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 470)
	body.add_child(_tabs)
	# Who's online
	var who := _page("ADMIN_TAB_WHO")
	var row := HBoxContainer.new()
	who.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = tr("ROOM_STUDENT_NAME")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	_role = OptionButton.new()
	for r in ROLES:
		_role.add_item(r)
	row.add_child(_role)
	_house = SpinBox.new()
	_house.max_value = 4
	_house.prefix = tr("ADMIN_HOUSE")
	row.add_child(_house)
	_year = SpinBox.new()
	_year.min_value = 1
	_year.max_value = 7
	_year.prefix = tr("ADMIN_YEAR")
	row.add_child(_year)
	row.add_child(button(tr("ADMIN_SET"), func() -> void:
		_report(await NetworkManager.request("admin_set", {"name": _name.text.strip_edges(), "role": ROLES[_role.selected], "house": int(_house.value), "year": int(_year.value)}))
		_refresh_who()))
	who.add_child(button(tr("ADMIN_REFRESH"), _refresh_who))
	_who_list = _text_out(who, "who")
	# Broadcast
	var cast := _page("ADMIN_TAB_BROADCAST")
	_broadcast = LineEdit.new()
	_broadcast.placeholder_text = tr("ADMIN_BROADCAST_HINT")
	cast.add_child(_broadcast)
	cast.add_child(button(tr("ADMIN_SEND"), func() -> void: _report(await NetworkManager.request("admin_broadcast", {"text": _broadcast.text}))))
	# Timetable
	var tt := _page("ADMIN_TAB_TIMETABLE")
	var fields := HBoxContainer.new()
	tt.add_child(fields)
	for f in ["id", "day", "start", "minutes", "subject", "room", "professor"]:
		var e := LineEdit.new()
		e.placeholder_text = f
		e.custom_minimum_size = Vector2(70, 0)
		fields.add_child(e)
		_slot_fields[f] = e
	var tt_buttons := HBoxContainer.new()
	tt.add_child(tt_buttons)
	tt_buttons.add_child(button(tr("ADMIN_SLOT_SET"), func() -> void:
		var p := {}
		for f: String in _slot_fields:
			p[f] = (_slot_fields[f] as LineEdit).text.strip_edges()
		p["kind"] = "lesson" if p["subject"] != "" else "study"
		_report(await NetworkManager.request("admin_timetable_set", p))
		_refresh_timetable()))
	tt_buttons.add_child(button(tr("ADMIN_SLOT_REMOVE"), func() -> void:
		_report(await NetworkManager.request("admin_timetable_remove", {"id": (_slot_fields["id"] as LineEdit).text.strip_edges()}))
		_refresh_timetable()))
	tt_buttons.add_child(button(tr("ADMIN_SLOT_RESET"), func() -> void:
		_report(await NetworkManager.request("admin_timetable_reset", {}))
		_refresh_timetable()))
	_text_out(tt, "timetable")
	# Reports and chat log
	var rep := _page("ADMIN_TAB_REPORTS")
	rep.add_child(button(tr("ADMIN_REFRESH"), _refresh_reports))
	_text_out(rep, "reports")
	var log := _page("ADMIN_TAB_CHATLOG")
	var log_row := HBoxContainer.new()
	log.add_child(log_row)
	var log_name := LineEdit.new()
	log_name.placeholder_text = tr("ADMIN_CHATLOG_NAME")
	log_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_row.add_child(log_name)
	log_row.add_child(button(tr("ADMIN_REFRESH"), func() -> void: _refresh_chatlog(log_name.text.strip_edges())))
	_text_out(log, "chatlog")
	# Events
	var ev := _page("ADMIN_TAB_EVENTS")
	var ev_row := HBoxContainer.new()
	ev.add_child(ev_row)
	var ev_fields := {}
	for f in ["kind", "title", "in_minutes", "minutes", "area"]:
		var e := LineEdit.new()
		e.placeholder_text = f
		e.custom_minimum_size = Vector2(80, 0)
		ev_row.add_child(e)
		ev_fields[f] = e
	ev.add_child(button(tr("ADMIN_EVENT_ADD"), func() -> void:
		_report(await NetworkManager.request("event_schedule", {"kind": (ev_fields.kind as LineEdit).text, "title": (ev_fields.title as LineEdit).text,
			"at": int((ev_fields.in_minutes as LineEdit).text), "minutes": int((ev_fields.minutes as LineEdit).text), "area": (ev_fields.area as LineEdit).text}))))
	# Plans and the wing
	var plans := _page("ADMIN_TAB_PLANS")
	plans.add_child(button(tr("ADMIN_REFRESH"), _refresh_plans))
	var plan_list := VBoxContainer.new()
	plans.add_child(plan_list)
	_out["plans"] = plan_list
	var wing := _page("ADMIN_TAB_WING")
	var wing_points := SpinBox.new()
	wing_points.max_value = 10000
	wing_points.value = 40
	wing.add_child(wing_points)
	wing.add_child(button(tr("ADMIN_WING_ADD"), func() -> void: _report(await NetworkManager.request("wing_contribute", {"points": int(wing_points.value)}), "wing_contribute")))


func refresh() -> void:
	_refresh_who()
	_refresh_timetable()


func _report(r: Dictionary, kind: String = "") -> void:
	status_label.text = RequestText.describe(kind, r) if kind != "" else (tr("REQUEST_DONE") if r.ok else NetworkManager.refusal_text(r.reason))


func _refresh_who() -> void:
	var r: Dictionary = await NetworkManager.request("admin_who", {})
	if not r.ok:
		_who_list.text = NetworkManager.refusal_text(r.reason)
		return
	var lines := PackedStringArray()
	for p: Variant in (r.data.get("players", []) if r.data.get("players", []) is Array else []):
		var d: Dictionary = p
		lines.append("[b]%s[/b] · %s · %s · %s · %s" % [str(d.get("name", "")), str(d.get("role", "")), CharacterProfile.house_name(int(d.get("house", 0))) if int(d.get("house", 0)) > 0 else "-",
			tr("YEAR_%d" % int(d.get("year", 1))), Localization.area_name(str(d.get("area", ""))) if str(d.get("area", "")) != "" else "-"])
	_who_list.text = "\n".join(lines)


func _refresh_timetable() -> void:
	var r: Dictionary = await NetworkManager.request("admin_timetable", {})
	if not r.ok:
		(_out["timetable"] as RichTextLabel).text = NetworkManager.refusal_text(r.reason)
		return
	var lines := PackedStringArray()
	for s: Variant in (r.data.get("slots", []) if r.data.get("slots", []) is Array else []):
		var d: Dictionary = s
		lines.append("%s  %s %s  %d min  %s  %s  %s" % [str(d.get("id", "")), str(d.get("day", "")), str(d.get("start", "")), int(d.get("minutes", 0)),
			str(d.get("subject", "")), str(d.get("room", "")), str(d.get("professor", ""))])
	(_out["timetable"] as RichTextLabel).text = "\n".join(lines)


func _refresh_reports() -> void:
	var r: Dictionary = await NetworkManager.request("admin_reports", {})
	var lines := PackedStringArray()
	for e: Variant in (r.data.get("reports", []) if r.ok and r.data.get("reports", []) is Array else []):
		var d: Dictionary = e
		lines.append("%s → %s: %s" % [str(d.get("from_name", "")), str(d.get("about_name", "")), str(d.get("reason", ""))])
	(_out["reports"] as RichTextLabel).text = "\n".join(lines) if not lines.is_empty() else tr("ADMIN_NOTHING")


func _refresh_chatlog(who: String) -> void:
	var r: Dictionary = await NetworkManager.request("admin_chat_log", {"name": who})
	var lines := PackedStringArray()
	for e: Variant in (r.data.get("lines", []) if r.ok and r.data.get("lines", []) is Array else []):
		var d: Dictionary = e
		lines.append("[%s] %s%s: %s" % [str(d.get("mode", "")), str(d.get("name", "")), (" → " + str(d.get("to", ""))) if str(d.get("to", "")) != "" else "", str(d.get("text", ""))])
	(_out["chatlog"] as RichTextLabel).text = "\n".join(lines) if not lines.is_empty() else tr("ADMIN_NOTHING")


func _refresh_plans() -> void:
	var list: VBoxContainer = _out["plans"]
	clear(list)
	var r: Dictionary = await NetworkManager.request("plans_shared", {})
	for p: Variant in (r.data.get("plans", []) if r.ok and r.data.get("plans", []) is Array else []):
		var d: Dictionary = p
		var row := HBoxContainer.new()
		var l := label("%s (%s, %s)%s" % [str(d.get("title", "")), str(d.get("owner_name", "")), str(d.get("subject", "")), "  ✓" if d.get("approved", false) else ""], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var id := str(d.get("id", ""))
		var on: bool = not d.get("approved", false)
		row.add_child(button(tr("ADMIN_APPROVE") if on else tr("ADMIN_UNAPPROVE"), func() -> void:
			_report(await NetworkManager.request("plan_approve", {"id": id, "on": on}))
			_refresh_plans()))
		list.add_child(row)

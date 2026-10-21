class_name ClubsPanel
extends FeaturePanel
## Clubs and societies (server feature "clubs"): every club with its badge, members and
## next meetings; join or leave; found a new one (name, badge colour and symbol); members
## read and post on the club board and book a room. Opened by /clubs.

const COLOURS := [Color(0.75, 0.2, 0.2), Color(0.2, 0.45, 0.8), Color(0.25, 0.65, 0.3), Color(0.85, 0.7, 0.2),
	Color(0.55, 0.3, 0.7), Color(0.85, 0.45, 0.2), Color(0.3, 0.7, 0.75), Color(0.5, 0.5, 0.5)]
const SYMBOLS := ["★", "☾", "☀", "✦", "♣", "⚘", "♞", "✎"]

var _list: VBoxContainer
var _name: LineEdit
var _colour: OptionButton
var _symbol: OptionButton
var _board_id := ""


func _ready() -> void:
	half_size = Vector2(360, 280)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "clubs":
			open_panel())
	NetworkManager.pushed.connect(func(kind: String, _d: Dictionary) -> void:
		if kind == "clubs" and is_open:
			refresh())


static func badge_text(badge: Variant) -> String:
	var b: Dictionary = badge if badge is Dictionary else {}
	return SYMBOLS[int(b.get("symbol", 0)) % SYMBOLS.size()]


static func badge_color(badge: Variant) -> Color:
	var b: Dictionary = badge if badge is Dictionary else {}
	return COLOURS[int(b.get("colour", 0)) % COLOURS.size()]


func _build() -> void:
	title_label.text = tr("CLUBS_TITLE")
	var row := HBoxContainer.new()
	body.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = tr("CLUBS_NEW_NAME")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	_colour = OptionButton.new()
	for i in COLOURS.size():
		_colour.add_item("■ %d" % (i + 1))
		_colour.set_item_icon(i, null)
	row.add_child(_colour)
	_symbol = OptionButton.new()
	for s in SYMBOLS:
		_symbol.add_item(s)
	row.add_child(_symbol)
	row.add_child(button(tr("CLUBS_FOUND"), _found))
	_list = VBoxContainer.new()
	body.add_child(_list)


func refresh() -> void:
	clear(_list)
	var me := NetworkManager.local_display_name
	var clubs: Variant = NetworkManager.feature("clubs").get("clubs", [])
	for c: Variant in (clubs if clubs is Array else []):
		var d: Dictionary = c
		var members: Array = d.get("members", []) if d.get("members", []) is Array else []
		var row := HBoxContainer.new()
		var badge := label(badge_text(d.get("badge")), 22)
		badge.add_theme_color_override("font_color", badge_color(d.get("badge")))
		row.add_child(badge)
		var info := label("%s  (%s)" % [str(d.get("name", "")), tr("CLUBS_MEMBERS") % members.size()], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var id := str(d.get("id", ""))
		if members.has(me):
			row.add_child(button(tr("CLUBS_BOARD"), func() -> void: _show_board(id)))
			row.add_child(button(tr("CLUBS_LEAVE"), func() -> void: _ask("club_leave", {"id": id})))
		else:
			row.add_child(button(tr("CLUBS_JOIN"), func() -> void: _ask("club_join", {"id": id})))
		_list.add_child(row)
		for b: Variant in (d.get("bookings", []) if d.get("bookings", []) is Array else []):
			var bd: Dictionary = b
			_list.add_child(label("    " + tr("CLUBS_MEETING") % [_when(float(bd.get("at", 0))), Localization.area_name(str(bd.get("area", "")))], 13))
	if _list.get_child_count() == 0:
		_list.add_child(label(tr("CLUBS_NONE"), 14))


static func _when(t: float) -> String:
	var tt := NetworkManager.timetable
	return "%s %s" % [TranslationServer.translate(tt.day_key(t)), tt.clock_text(t)]


func _found() -> void:
	await _ask("club_create", {"name": _name.text, "colour": _colour.selected, "symbol": _symbol.selected})


func _show_board(id: String) -> void:
	_board_id = id
	var r: Dictionary = await NetworkManager.request("club_board", {"id": id})
	if not r.ok:
		show_result(r)
		return
	clear(_list)
	_list.add_child(button(tr("CLUBS_BACK"), refresh))
	var post := LineEdit.new()
	post.placeholder_text = tr("CLUBS_POST_HINT")
	post.text_submitted.connect(func(text: String) -> void:
		await _ask("club_post", {"id": id, "text": text})
		_show_board(id))
	_list.add_child(post)
	for p: Variant in (r.data.get("posts", []) if r.data.get("posts", []) is Array else []):
		_list.add_child(label("• %s — %s" % [str((p as Dictionary).get("text", "")), str((p as Dictionary).get("by", ""))], 14))


func _ask(kind: String, payload: Dictionary) -> void:
	var r: Dictionary = await NetworkManager.request(kind, payload)
	show_result(r, "OK_" + kind.to_upper())

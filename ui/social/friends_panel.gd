class_name FriendsPanel
extends FeaturePanel
## Friends (server feature "friends"): who is online and where, requests to accept or
## decline, and a box to ask someone by name. Opened by /friends or from a profile card.

var _name: LineEdit
var _list: VBoxContainer


func _ready() -> void:
	half_size = Vector2(300, 250)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "friends":
			open_panel())
	NetworkManager.pushed.connect(func(kind: String, _d: Dictionary) -> void:
		if kind == "friends" and is_open:
			refresh())


func _build() -> void:
	title_label.text = tr("FRIENDS_TITLE")
	var row := HBoxContainer.new()
	body.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = tr("FRIENDS_NAME")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	row.add_child(button(tr("FRIENDS_ADD"), func() -> void: _ask("friend_add", _name.text)))
	_list = VBoxContainer.new()
	body.add_child(_list)


func refresh() -> void:
	clear(_list)
	var f := NetworkManager.feature("friends")
	for n: Variant in _arr(f.get("incoming")):
		var row := HBoxContainer.new()
		row.add_child(label(tr("FRIENDS_INCOMING") % str(n), 15))
		row.add_child(button(tr("FRIENDS_ACCEPT"), func() -> void: _ask("friend_accept", str(n))))
		row.add_child(button(tr("FRIENDS_DECLINE"), func() -> void: _ask("friend_remove", str(n))))
		_list.add_child(row)
	for e: Variant in _arr(f.get("friends")):
		var d: Dictionary = e
		var row := HBoxContainer.new()
		var where := (tr("FRIENDS_ONLINE_IN") % tr("AREA_" + str(d.get("area", "")).to_upper())) if d.get("online", false) and str(d.get("area", "")) != "" \
			else (tr("FRIENDS_ONLINE") if d.get("online", false) else tr("FRIENDS_OFFLINE"))
		var l := label("%s — %s" % [str(d.get("name", "")), where], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(button(tr("FRIENDS_REMOVE"), func() -> void: _ask("friend_remove", str(d.get("name", "")))))
		_list.add_child(row)
	for n: Variant in _arr(f.get("outgoing")):
		_list.add_child(label(tr("FRIENDS_OUTGOING") % str(n), 14))
	if _list.get_child_count() == 0:
		_list.add_child(label(tr("FRIENDS_NONE"), 14))


func _ask(kind: String, who: String) -> void:
	if who.strip_edges() == "":
		return
	var r: Dictionary = await NetworkManager.request(kind, {"name": who.strip_edges()})
	show_result(r, "OK_" + kind.to_upper())


static func _arr(v: Variant) -> Array:
	return v if v is Array else []

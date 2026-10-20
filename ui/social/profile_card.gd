class_name ProfileCard
extends FeaturePanel
## Another player's card (server feature "profile_card"): house, year, titles, favourite
## spell, discoveries, club badges, parlour games and the duel ladder, their familiar.
## Opened by looking at a player and pressing Interact, or by /profile name.

var who := ""
var _text: RichTextLabel
var _actions: HBoxContainer


func _ready() -> void:
	half_size = Vector2(270, 220)
	super()
	GameEvents.panel_requested.connect(func(panel: String, args: Dictionary) -> void:
		if panel == "profile":
			who = str(args.get("name", ""))
			open_panel())


func _build() -> void:
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.add_theme_color_override("default_color", INK)
	body.add_child(_text)
	_actions = HBoxContainer.new()
	body.add_child(_actions)


func refresh() -> void:
	title_label.text = who
	_text.text = tr("PROFILE_LOADING")
	clear(_actions)
	var r: Dictionary = await NetworkManager.request("profile_card", {"name": who})
	if not r.ok:
		_text.text = NetworkManager.refusal_text(r.reason)
		return
	_text.text = card_bbcode(r.data)
	if not r.data.get("self", false):
		if not r.data.get("friend", false):
			_actions.add_child(button(tr("FRIENDS_ADD"), func() -> void: show_result(await NetworkManager.request("friend_add", {"name": who}), "OK_FRIEND_ADD")))
		_actions.add_child(button(tr("GAME_INVITE"), func() -> void: show_result(await NetworkManager.request("game_invite", {"name": who}), "OK_GAME_INVITE")))


static func card_bbcode(d: Dictionary) -> String:
	var lines := PackedStringArray()
	var house := int(d.get("house", 0))
	# The card sits on parchment: the house crest is inked, not coloured.
	var crest := "[img=28x28 color=#%s]%s[/img] " % [UiTokens.INK.to_html(false), CharacterProfile.crest_path(house, CharacterProfile.CREST_ICON)] if house > 0 else ""
	lines.append("%s[b]%s[/b] · %s" % [crest, CharacterProfile.house_name(house) if house > 0 else TranslationServer.translate("PROFILE_UNSORTED"),
		TranslationServer.translate("YEAR_%d" % int(d.get("year", 1)))])
	var titles: Variant = d.get("titles", [])
	if titles is Array and not (titles as Array).is_empty():
		var t := PackedStringArray()
		for k: Variant in titles:
			t.append(TranslationServer.translate(str(k)))
		lines.append(", ".join(t))
	var fav := str(d.get("favourite", ""))
	if fav != "":
		var def := SpellRegistry.load_definition(fav)
		lines.append(TranslationServer.translate("PROFILE_FAVOURITE") % (TranslationServer.translate(def.display_name) if def != null else fav))
	lines.append(TranslationServer.translate("PROFILE_DISCOVERIES") % int(d.get("discoveries", 0)))
	var clubs: Variant = d.get("clubs", [])
	if clubs is Array and not (clubs as Array).is_empty():
		var c := PackedStringArray()
		for club: Variant in clubs:
			var cd: Dictionary = club
			c.append("[color=#%s]%s[/color] %s" % [ClubsPanel.badge_color(cd.get("badge")).to_html(false), ClubsPanel.badge_text(cd.get("badge")), str(cd.get("name", ""))])
		lines.append(TranslationServer.translate("PROFILE_CLUBS") % ", ".join(c))
	var g: Dictionary = d.get("games", {}) if d.get("games", {}) is Dictionary else {}
	lines.append(TranslationServer.translate("PROFILE_GAMES") % [int(g.get("wins", 0)), int(g.get("draws", 0)), int(g.get("losses", 0))])
	if d.get("rating") != null:
		lines.append(TranslationServer.translate("PROFILE_RATING") % int(d.rating))
	var fam := str(d.get("familiar", ""))
	if fam != "":
		lines.append(TranslationServer.translate("PROFILE_FAMILIAR") % TranslationServer.translate("ITEM_FAMILIAR_%s_NAME" % fam.to_upper()))
	return "\n".join(lines)

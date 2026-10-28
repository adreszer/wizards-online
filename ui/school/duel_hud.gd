class_name DuelHud
extends CanvasLayer
## The duel the local player is in or watching (OP_DUEL_STATE): a banner with the names
## and the score, the countdown, the result. Reports the local player's hits on the
## opponent (GameEvents.spell_hit_player) to the server, bows at the countdown and asks
## the music for the duel track while a fight runs nearby.

var duel: Dictionary = {}
var _label: Label


func _ready() -> void:
	layer = 2
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = 70
	_label.offset_left = -300
	_label.offset_right = 300
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The banner lettering: display face, brass, a shadow that reads over any scene.
	_label.theme_type_variation = &"BannerSubLabel"
	_label.visible = false
	add_child(_label)
	NetworkManager.server_message.connect(_on_message)
	GameEvents.spell_hit_player.connect(_on_hit)


func _self_sid() -> String:
	return NetworkManager.world_session.self_session_id


func _on_message(op: int, payload: Dictionary) -> void:
	if op != NetworkProtocol.OP_DUEL_STATE:
		return
	var before := str(duel.get("state", ""))
	duel = payload
	var me := _self_sid()
	var state := str(payload.get("state", ""))
	_label.text = banner_text(payload)
	_label.visible = state != "over"
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if state == "challenged" and payload.get("b", "") == me and before != "challenged":
		GameEvents.notify(tr("DUEL_CHALLENGED") % str(payload.get("a_name", "")), 8.0, ToastStack.Kind.INFO, "wand")
	elif state == "countdown" and before != "countdown" and player != null and me in [payload.get("a", ""), payload.get("b", "")]:
		player.gestures.play(&"bow")
	elif state == "over":
		var winner := str(payload.get("winner", ""))
		var line := tr("DUEL_EXPIRED") if payload.get("expired", false) else tr("DUEL_WON_BY") % (str(payload.a_name) if winner == str(payload.a) else str(payload.b_name))
		GameEvents.notification_requested.emit(line, 6.0)
	var music := get_tree().root.find_child("MusicDirector", true, false) as MusicDirector
	if music != null:
		if state == "fighting" or state == "countdown":
			music.event_track = &"duel"
		elif music.event_track == &"duel":
			music.event_track = &""


## "Ola 2 : 1 Kuba · first to 3", "Duel in 3…", or the challenge.
static func banner_text(d: Dictionary) -> String:
	var a := str(d.get("a_name", ""))
	var b := str(d.get("b_name", ""))
	var hits: Dictionary = d.get("hits", {}) if d.get("hits", {}) is Dictionary else {}
	match str(d.get("state", "")):
		"challenged":
			return TranslationServer.translate("DUEL_BANNER_CHALLENGE") % [a, b]
		"countdown":
			return TranslationServer.translate("DUEL_BANNER_COUNTDOWN") % [a, b]
		"fighting":
			return TranslationServer.translate("DUEL_BANNER_SCORE") % [a, int(hits.get(str(d.get("a", "")), 0)), int(hits.get(str(d.get("b", "")), 0)), b, int(d.get("to_win", 3))]
	return ""


func _on_hit(peer_id: String, spell_id: StringName) -> void:
	var me := _self_sid()
	if str(duel.get("state", "")) != "fighting" or not me in [duel.get("a", ""), duel.get("b", "")]:
		return
	var opponent := str(duel.b) if str(duel.a) == me else str(duel.a)
	if peer_id == opponent:
		NetworkManager.send_op(NetworkProtocol.OP_DUEL_HIT, {"sid": peer_id, "spell": String(spell_id)})

class_name TalkingPortraits
extends Node
## The castle's portraits talk. When the local player walks up to one (portraits are
## batched, so StaticBatch records where they hang), its sitter greets them by name and
## house and passes on the latest rumour from the server (or an old piece of castle
## gossip); the words float in front of the frame for a few seconds. Each portrait then
## keeps quiet for a while. castle.gd adds it.

const PORTRAIT := "res://objects/environment/placeholders/portrait.tscn"
## The painted portraits (one scene per sitter); the castle hangs them in turn.
const PORTRAIT_DIR := "res://objects/environment/props/portraits/"
const REACH := 3.2
const QUIET_SECONDS := 90.0
const SHOW_SECONDS := 7.0
const IDLE_LINES := 4

## A portrait spoke (LivePortraits has a live sitter gesture along).
signal spoke(portrait: Transform3D)

var portraits: Array[Transform3D] = []
var _quiet_until: Dictionary = {}
## Messages already spoken (their removal is on its way to the server).
var _delivered: Dictionary = {}
var _bubble: Label3D
var _bubble_left := 0.0
var _timer := 0.0



static func is_portrait(path: String) -> bool:
	return path == PORTRAIT or path.begins_with(PORTRAIT_DIR)


## The sitter a portrait scene shows (portrait_07.tscn → 7), 0 for the placeholder.
static func sitter_of(path: String) -> int:
	if not path.begins_with(PORTRAIT_DIR):
		return 0
	return path.get_file().get_basename().trim_prefix("portrait_").to_int()


func _ready() -> void:
	for batch in get_tree().get_nodes_in_group(StaticBatch.GROUP):
		portraits.append_array((batch as StaticBatch).portraits)
	_bubble = Label3D.new()
	_bubble.font_size = 36
	_bubble.pixel_size = 0.0028
	_bubble.outline_size = 10
	_bubble.width = 700.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.modulate = Color(1.0, 0.93, 0.78)
	_bubble.visible = false
	add_child(_bubble)


func _process(delta: float) -> void:
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or portraits.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for i in portraits.size():
		var p: Transform3D = portraits[i]
		if p.origin.distance_to(player.global_position + Vector3.UP * 1.6) < REACH:
			# A message other students left with the portraits is delivered by the first one passed.
			var mail := waiting_message(_delivered)
			if not mail.is_empty():
				_delivered[str(mail.get("id", ""))] = true
				speak(p, tr("PORTRAIT_MESSAGE") % [str(mail.get("from", "")), str(mail.get("text", ""))])
				NetworkManager.request("portrait_read", {"id": str(mail.get("id", ""))})
				return
			if now >= float(_quiet_until.get(i, 0.0)):
				_quiet_until[i] = now + QUIET_SECONDS
				speak(p, line_for(player.display_name, player.house, NetworkManager.rumours, i))
				return


## The oldest message waiting with the portraits for the local student ({} for none).
static func waiting_message(delivered: Dictionary = {}) -> Dictionary:
	var list: Variant = NetworkManager.feature("portrait_mail").get("messages", [])
	for m: Variant in (list if list is Array else []):
		if m is Dictionary and not delivered.has(str((m as Dictionary).get("id", ""))):
			return m
	return {}


## What a portrait says: a greeting, then a rumour (or idle gossip, by portrait).
static func line_for(player_name: String, house: int, rumours: Array, index: int) -> String:
	var greet: String = TranslationServer.translate("PORTRAIT_GREET_HOUSE") % [player_name, CharacterProfile.house_name(house)] if house > 0 \
		else TranslationServer.translate("PORTRAIT_GREET") % player_name
	var news: String
	if not rumours.is_empty():
		news = NetworkManager.rumour_text(rumours[index % rumours.size()])
	else:
		news = TranslationServer.translate("RUMOUR_IDLE_%d" % (index % IDLE_LINES + 1))
	return greet + " " + news


func speak(portrait: Transform3D, text: String) -> void:
	_bubble.text = text
	# Just in front of the frame (portraits face their +Z), a little above eye level.
	_bubble.global_position = portrait.origin + portrait.basis.z * 0.6 + Vector3.UP * 0.6
	_bubble.visible = true
	_bubble_left = SHOW_SECONDS
	spoke.emit(portrait)

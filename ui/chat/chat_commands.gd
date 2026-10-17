class_name ChatCommands
extends RefCounted
## Slash commands typed into the chat box (they never reach the chat channel).
## Today they are dev cheats for playtesting the big castle:
##   /broom (/miotla, /miotła)   give the local player a broom
##   /give <item id> (/daj)      give any registered item
##   /time [hh[:mm]] (/czas)     show the school time, or move the clock (everyone's, online)
##   /plan (/timetable)          open the timetable
##   /coins <±n> (/korony)      add coins to (or take them from) your own purse
##   /goto <place> (/idz)        jump to the station, the village, the castle gate or any area id
##                               (offline always; online only professors and admins)
##   /help (/pomoc)              list the commands
## Offline they act on the local inventory directly. Online the server owns the
## inventory: the request goes up as OP_CHEAT and is accepted from admins, or
## from anyone while nakama/content/school_rules.json has cheats_enabled.

const WHISPER_ALIASES: Array[String] = ["w", "whisper", "szept", "sz"]
const SHOUT_ALIASES: Array[String] = ["s", "shout", "krzyk", "k"]
const DM_ALIASES: Array[String] = ["msg", "dm", "pw", "tell", "napisz"]
const REPLY_ALIASES: Array[String] = ["r", "reply", "odp", "odpowiedz"]
## Gestures and seats as commands: /wave, /machaj… (any language's word for it).
const GESTURE_ALIASES := {"raise": &"raise_hand", "hand": &"raise_hand", "reka": &"raise_hand", "ręka": &"raise_hand", "zglos": &"raise_hand", "zgłoś": &"raise_hand",
	"wave": &"wave", "machaj": &"wave", "pomachaj": &"wave", "bow": &"bow", "uklon": &"bow", "ukłon": &"bow",
	"clap": &"clap", "klaszcz": &"clap", "brawo": &"clap", "point": &"point", "wskaz": &"point", "wskaż": &"point",
	"shrug": &"shrug", "wzrusz": &"shrug", "cheer": &"cheer", "wiwat": &"cheer", "hurra": &"cheer",
	"notes": &"notes", "notuj": &"notes", "notatki": &"notes"}
const SIT_ALIASES: Array[String] = ["sit", "usiadz", "usiądź", "siadaj"]
const SELF_STUDY_ALIASES: Array[String] = ["selfstudy", "samouk", "nauka"]
const LOOK_ALIASES: Array[String] = ["look", "wyglad", "wygląd", "postac", "postać"]
const RUNES_ALIASES: Array[String] = ["runes", "runy", "rune"]
const EXAM_ALIASES: Array[String] = ["exam", "egzamin"]
const GUEST_ALIASES: Array[String] = ["guest", "gosc", "gość"]
## Moderation: /report name reason, /block name, /unblock name; staff /mute name [minutes], /kick name; admins /ban name reason.
const MODERATION_ALIASES := {"report": "report", "zglos_gracza": "report", "zgłoś_gracza": "report", "block": "block", "blokuj": "block",
	"unblock": "unblock", "odblokuj": "unblock", "mute": "mute", "wycisz": "mute", "kick": "kick", "wyrzuc": "kick", "wyrzuć": "kick", "ban": "ban"}
const DEDUCT_ALIASES: Array[String] = ["deduct", "odejmij"]
const STAND_ALIASES: Array[String] = ["stand", "wstan", "wstań"]
const GIVE_ALIASES: Array[String] = ["give", "daj"]
const BROOM_ALIASES: Array[String] = ["broom", "miotla", "miotła"]
const HELP_ALIASES: Array[String] = ["help", "pomoc", "?"]
const TIME_ALIASES: Array[String] = ["time", "czas", "godzina"]
const PLAN_ALIASES: Array[String] = ["plan", "timetable", "lekcje"]
const GOTO_ALIASES: Array[String] = ["goto", "tp", "idz", "idź"]
const COINS_ALIASES: Array[String] = ["coins", "korony", "monety", "kasa"]
## Named places for /goto; anything else is looked up as an area id.
const PLACE_ALIASES := {"station": "@station", "stacja": "@station", "dworzec": "@station", "pociag": "@station", "pociąg": "@station",
	"village": "@village", "wioska": "@village", "rynek": "@village",
	"castle": "@start", "zamek": "@start", "start": "@start", "szkola": "@start", "szkoła": "@start"}


static func is_command(text: String) -> bool:
	return text.begins_with("/")


## Chat modes typed as commands: "/w text" (whisper), "/s text" (shout), "/msg name text"
## (a direct message; a name with spaces goes in quotes), "/r text" (reply to the last DM).
## Returns {mode: "whisper" | "shout" | "dm", to?, text} or {} when `text` is not one;
## {mode: "dm", to: "", text: ""} for a DM without a recipient or text (show the usage).
static func parse_chat(text: String, last_dm_from: String = "") -> Dictionary:
	if not text.begins_with("/"):
		return {}
	var body := text.substr(1)
	var space := body.find(" ")
	var name := (body if space < 0 else body.substr(0, space)).to_lower()
	var rest := "" if space < 0 else body.substr(space + 1).strip_edges()
	if WHISPER_ALIASES.has(name):
		return {"mode": NetworkProtocol.CHAT_WHISPER, "text": rest}
	if SHOUT_ALIASES.has(name):
		return {"mode": NetworkProtocol.CHAT_SHOUT, "text": rest}
	if REPLY_ALIASES.has(name):
		return {"mode": "dm", "to": last_dm_from, "text": rest}
	if DM_ALIASES.has(name):
		var to := ""
		if rest.begins_with("\""):
			var close := rest.find("\"", 1)
			if close > 0:
				to = rest.substr(1, close - 1)
				rest = rest.substr(close + 1).strip_edges()
		else:
			var gap := rest.find(" ")
			to = rest if gap < 0 else rest.substr(0, gap)
			rest = "" if gap < 0 else rest.substr(gap + 1).strip_edges()
		return {"mode": "dm", "to": to.strip_edges(), "text": rest}
	return {}


## Runs a command for `player` (the local Player, may be null). Returns the line
## to show in the chat log.
static func run(text: String, player: Node) -> String:
	var parts := text.substr(1).strip_edges().split(" ", false)
	var name := parts[0].to_lower() if parts.size() > 0 else ""
	if HELP_ALIASES.has(name):
		return _t("CHEAT_HELP")
	if GESTURE_ALIASES.has(name) or SIT_ALIASES.has(name) or STAND_ALIASES.has(name):
		return gesture(name, player)
	if RUNES_ALIASES.has(name):
		GameSession.set_trace_casting(not GameSession.trace_casting)
		return _t("RUNES_ON") if GameSession.trace_casting else _t("RUNES_OFF")
	if LOOK_ALIASES.has(name):
		GameEvents.character_creator_requested.emit.call_deferred()
		return ""
	if MODERATION_ALIASES.has(name):
		if parts.size() < 2:
			return _t("MODERATION_USAGE")
		var action: String = MODERATION_ALIASES[name]
		var minutes := int(parts[2]) if action == "mute" and parts.size() > 2 and parts[2].is_valid_int() else 10
		NetworkManager.send_moderation(action, parts[1], " ".join(parts.slice(2)) if action in ["report", "ban"] else "", minutes)
		return _t("MODERATION_SENT")
	if GUEST_ALIASES.has(name):
		if parts.size() < 2:
			return _t("GUEST_USAGE")
		NetworkManager.send_guest_pass(" ".join(parts.slice(1)))
		return _t("GUEST_REQUESTED")
	if DEDUCT_ALIASES.has(name):
		if parts.size() < 4 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
			return _t("DEDUCT_USAGE")
		NetworkManager.send_house_points(int(parts[1]), -absi(int(parts[2])), " ".join(parts.slice(3)))
		return _t("DEDUCT_REQUESTED")
	if EXAM_ALIASES.has(name):
		if not NetworkManager.send_op(NetworkProtocol.OP_CHEAT, {"self_study": true, "exam": true}):
			return _t("SELF_STUDY_ONLINE_ONLY")
		return _t("SELF_STUDY_REQUESTED")
	if SELF_STUDY_ALIASES.has(name):
		if not NetworkManager.send_op(NetworkProtocol.OP_CHEAT, {"self_study": true}):
			return _t("SELF_STUDY_ONLINE_ONLY")
		return _t("SELF_STUDY_REQUESTED")
	if BROOM_ALIASES.has(name):
		return give("broom", player)
	if GIVE_ALIASES.has(name):
		if parts.size() < 2:
			return _t("CHEAT_GIVE_USAGE") % ", ".join(ItemRegistry.ITEM_IDS)
		return give(parts[1].to_lower(), player)
	if PLAN_ALIASES.has(name):
		# Deferred: the chat box releases the keyboard first, then the panel takes it.
		GameEvents.timetable_requested.emit.call_deferred()
		return _t("CHEAT_PLAN_OPENED")
	if TIME_ALIASES.has(name):
		return time(parts[1] if parts.size() > 1 else "")
	if COINS_ALIASES.has(name):
		return coins(parts[1] if parts.size() > 1 else "")
	if GOTO_ALIASES.has(name):
		return goto(parts[1] if parts.size() > 1 else "", player)
	return _t("CHEAT_UNKNOWN") % text


## A gesture, sitting down or standing up for the local player.
static func gesture(name: String, player: Node) -> String:
	if not player is Player or not (player as Player).is_local:
		return _t("CHEAT_NO_PLAYER")
	var p := player as Player
	if SIT_ALIASES.has(name):
		return _t("GESTURE_SAT") if p.try_sit() else _t("GESTURE_NO_SEAT")
	if STAND_ALIASES.has(name):
		p.gestures.stand()
		return ""
	p.player_input.request_gesture(GESTURE_ALIASES[name])
	return ""


## No argument: says the balance. Otherwise adds (or with a minus, takes) coins: online
## the server decides (cheats_enabled or admins) and the purse follows as OP_WALLET.
static func coins(arg: String) -> String:
	if arg.is_empty():
		return _t("CHEAT_COINS_NOW") % Currency.format(NetworkManager.get_coins())
	if not arg.is_valid_int() or int(arg) == 0:
		return _t("CHEAT_COINS_USAGE")
	NetworkManager.cheat_coins(int(arg))
	if NetworkManager.is_in_world():
		return _t("CHEAT_COINS_REQUESTED")
	return _t("CHEAT_COINS_NOW") % Currency.format(NetworkManager.get_coins())


## Moves the local player to a named place or the floor of an area (a playtest shortcut:
## the village and the station are a long walk from the castle).
static func goto(place: String, player: Node) -> String:
	if place.is_empty():
		return _t("CHEAT_GOTO_USAGE")
	var body := player as Node3D
	if body == null or not body.is_inside_tree():
		return _t("CHEAT_NO_PLAYER")
	if NetworkManager.is_in_world() and not [CharacterProfile.ROLE_PROFESSOR, CharacterProfile.ROLE_ADMIN].has(NetworkManager.get_local_role()):
		return _t("CHEAT_GOTO_NOT_ALLOWED")
	var target: Variant = place_position(body, str(PLACE_ALIASES.get(place.to_lower(), place.to_lower())))
	if target == null:
		return _t("CHEAT_GOTO_UNKNOWN") % place
	body.global_position = target
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	return _t("CHEAT_GOTO_DONE") % place


## Where /goto puts you: "@station" / "@village" (markers on the platform and in the
## square), "@start" (the level's StartPoint) or the floor under an area's centre. null if
## there is no such place. The terrain's collision around the target is built first.
static func place_position(body: Node3D, place: String) -> Variant:
	var tree := body.get_tree()
	var terrain := tree.root.find_child("Terrain", true, false) as Terrain
	var markers := {"@station": "station_arrival", "@village": "village_arrival"}
	if markers.has(place):
		var marker := tree.get_first_node_in_group(markers[place]) as Node3D
		if marker != null and terrain != null:
			terrain.focus_on(marker.global_position, true)
		return marker.global_position if marker != null else null
	if place == "@start":
		var start := tree.root.find_child("StartPoint", true, false) as Node3D
		return start.global_position + Vector3(0, 0.2, 0) if start != null else null
	for node in tree.get_nodes_in_group(AreaZone.GROUP):
		var zone := node as AreaZone
		if zone == null or str(zone.area_id) != place:
			continue
		if terrain != null:
			terrain.focus_on(zone.global_position, true)
		var top := zone.global_position + Vector3(0, zone.size.y * 0.5, 0)
		var bottom := zone.global_position - Vector3(0, zone.size.y * 0.5, 0)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, bottom, 1))
		return (hit["position"] as Vector3) + Vector3(0, 0.2, 0) if not hit.is_empty() else bottom + Vector3(0, 0.5, 0)
	return null


## No argument: says the time. Otherwise sets it ("14", "14:30", "day", "night").
static func time(arg: String) -> String:
	if arg == "":
		var now := NetworkManager.school_hours()
		return _t("CHEAT_TIME_NOW") % [SchoolClock.format(now), _t(SchoolClock.phase_key(SchoolClock.phase_of(now)))]
	var hours: float = {"day": 12.0, "dzien": 12.0, "dzień": 12.0, "night": 0.0, "noc": 0.0,
		"dawn": 5.5, "swit": 5.5, "świt": 5.5, "dusk": 19.5, "zmierzch": 19.5}.get(arg.to_lower(), SchoolClock.parse(arg))
	if hours < 0.0:
		return _t("CHEAT_TIME_USAGE")
	NetworkManager.set_school_hours(hours)
	if NetworkManager.is_in_world():
		return _t("CHEAT_TIME_REQUESTED") % SchoolClock.format(hours)
	return _t("CHEAT_TIME_SET") % SchoolClock.format(hours)


static func give(item_id: String, player: Node) -> String:
	var definition := ItemRegistry.load_definition(ItemRegistry.sanitize(item_id))
	if definition == null:
		return _t("CHEAT_UNKNOWN_ITEM") % [item_id, ", ".join(ItemRegistry.ITEM_IDS)]
	var name := _t(definition.display_name)
	if NetworkManager.is_in_world():
		NetworkManager.send_cheat_give(item_id)
		return _t("CHEAT_REQUESTED") % name
	var inventory := Inventory.find_on(player)
	if inventory == null:
		return _t("CHEAT_NO_PLAYER")
	if not definition.is_stackable() and inventory.has(definition.id):
		return _t("NOTIFY_ALREADY_HAVE_ITEM") % name
	inventory.add(definition)
	return result_line(true, definition)


## The chat line for a granted (or refused) item.
static func result_line(ok: bool, definition: ItemDefinition, reason: String = "") -> String:
	var name := _t(definition.display_name) if definition != null else "?"
	if ok:
		var line := _t("CHEAT_GIVEN") % name
		if definition != null and definition.is_mount():
			line += " " + _t("CHEAT_BROOM_HINT")
		return line
	if reason == "already_owned":
		return _t("NOTIFY_ALREADY_HAVE_ITEM") % name
	if reason == "not_allowed":
		return _t("CHEAT_NOT_ALLOWED")
	if reason == "insufficient":
		return _t("CHEAT_COINS_INSUFFICIENT")
	if reason == "no_plan":
		return _t("SELF_STUDY_NO_PLAN")
	if reason == "already_open":
		return _t("SELF_STUDY_ALREADY_OPEN")
	return _t("CHEAT_FAILED") % reason


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))

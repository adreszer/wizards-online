class_name ChatChannels
extends RefCounted
## The chat box's tabs and what each shows (docs/ui.md, Milestone 71): every line the
## box has heard, filtered per tab, with an unread count for the tabs not on screen.
## The tabs map onto what the chat already carries: say, whisper and shout are the
## server's modes (NetworkProtocol.CHAT_*), "house" is the same lines narrowed to
## speakers of the player's own house (no separate server channel), "dm" is direct
## messages. System lines and lectures show on every tab and never count as unread.
## Pure data, so the tests drive it without a scene.

enum Tab { ALL, SAY, WHISPER, SHOUT, HOUSE, DM }

## Tab title keys and icons, in Tab order.
const TITLE_KEYS := ["CHAT_TAB_ALL", "CHAT_TAB_SAY", "CHAT_TAB_WHISPER", "CHAT_TAB_SHOUT", "CHAT_TAB_HOUSE", "CHAT_TAB_DM"]
const ICONS := ["chat", "chat_say", "chat_whisper", "chat_shout", "chat_house", "chat_dm"]
const MAX_LINES := 120

## Every line heard, oldest first: the chat line dictionaries of ChatManager.line_received
## plus {kind: "system" | "lecture"} entries; each carries "time" ("HH:MM") and "house".
var lines: Array[Dictionary] = []
## Unread lines per tab, in Tab order.
var unread: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var current: Tab = Tab.ALL
## The local player's house (0 = not sorted yet), for the house tab.
var own_house: int = 0


## Whether `tab` shows `line`.
static func accepts(tab: Tab, line: Dictionary, house: int) -> bool:
	var kind := str(line.get("kind", "chat"))
	if kind == "system" or kind == "lecture":
		return true
	if kind == "dm":
		return tab == Tab.ALL or tab == Tab.DM
	var mode := str(line.get("mode", NetworkProtocol.CHAT_SAY))
	match tab:
		Tab.ALL:
			return true
		Tab.SAY:
			return mode == NetworkProtocol.CHAT_SAY
		Tab.WHISPER:
			return mode == NetworkProtocol.CHAT_WHISPER
		Tab.SHOUT:
			return mode == NetworkProtocol.CHAT_SHOUT
		Tab.HOUSE:
			return house > 0 and int(line.get("house", 0)) == house
	return false


## The chat mode plain text typed on `tab` is sent in ("dm" answers the last sender).
static func send_mode(tab: Tab) -> String:
	match tab:
		Tab.WHISPER:
			return NetworkProtocol.CHAT_WHISPER
		Tab.SHOUT:
			return NetworkProtocol.CHAT_SHOUT
		Tab.DM:
			return "dm"
	return NetworkProtocol.CHAT_SAY


## Remembers a line and counts it unread on every other tab that shows it (not our own
## lines, system lines or lectures). Returns whether the current tab shows it.
func add(line: Dictionary) -> bool:
	lines.append(line)
	if lines.size() > MAX_LINES:
		lines.remove_at(0)
	var kind := str(line.get("kind", "chat"))
	var counts: bool = kind != "system" and kind != "lecture" and not line.get("self", false)
	if counts:
		for tab: int in Tab.values():
			if tab != current and accepts(tab, line, own_house):
				unread[tab] += 1
	return accepts(current, line, own_house)


## Switches tabs and clears the tab's unread count.
func select(tab: Tab) -> void:
	current = tab
	unread[tab] = 0


## The lines the current tab shows, oldest first.
func visible_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in lines:
		if accepts(current, line, own_house):
			out.append(line)
	return out


## A tab's title with its unread count ("Whisper (3)").
func title(tab: Tab) -> String:
	var name := TranslationServer.translate(TITLE_KEYS[tab])
	if unread[tab] > 0:
		return TranslationServer.translate("CHAT_TAB_UNREAD") % [name, mini(unread[tab], 99)]
	return name


## The compact title the tab strip shows: the open tab its name, the others only
## their unread count (their icon and tooltip name them), so six tabs fit the box.
func short_title(tab: Tab) -> String:
	if tab == current:
		return TranslationServer.translate(TITLE_KEYS[tab])
	return str(mini(unread[tab], 99)) if unread[tab] > 0 else ""


func clear() -> void:
	lines.clear()
	unread = PackedInt32Array([0, 0, 0, 0, 0, 0])

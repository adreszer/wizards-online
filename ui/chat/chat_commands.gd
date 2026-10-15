class_name ChatCommands
extends RefCounted
## Slash commands typed into the chat box (they never reach the chat channel).
## Today they are dev cheats for playtesting the big castle:
##   /broom (/miotla, /miotła)   give the local player a broom
##   /give <item id> (/daj)      give any registered item
##   /help (/pomoc)              list the commands
## Offline they act on the local inventory directly. Online the server owns the
## inventory: the request goes up as OP_CHEAT and is accepted from admins, or
## from anyone while nakama/content/school_rules.json has cheats_enabled.

const GIVE_ALIASES: Array[String] = ["give", "daj"]
const BROOM_ALIASES: Array[String] = ["broom", "miotla", "miotła"]
const HELP_ALIASES: Array[String] = ["help", "pomoc", "?"]


static func is_command(text: String) -> bool:
	return text.begins_with("/")


## Runs a command for `player` (the local Player, may be null). Returns the line
## to show in the chat log.
static func run(text: String, player: Node) -> String:
	var parts := text.substr(1).strip_edges().split(" ", false)
	var name := parts[0].to_lower() if parts.size() > 0 else ""
	if HELP_ALIASES.has(name):
		return _t("CHEAT_HELP")
	if BROOM_ALIASES.has(name):
		return give("broom", player)
	if GIVE_ALIASES.has(name):
		if parts.size() < 2:
			return _t("CHEAT_GIVE_USAGE") % ", ".join(ItemRegistry.ITEM_IDS)
		return give(parts[1].to_lower(), player)
	return _t("CHEAT_UNKNOWN") % text


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
	return _t("CHEAT_FAILED") % reason


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))

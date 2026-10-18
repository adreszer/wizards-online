class_name ItemRegistry
extends RefCounted
## Looks item definitions up by id. Ids travel over the network and live in
## Nakama storage, so anything received from outside goes through
## [method sanitize] before it is used. tools/export_server_content.gd exports
## the catalogue and the starting kit to the server.
##
## The list is explicit rather than a directory scan, like SpellRegistry.

const ITEMS_DIR := "res://resources/items/"
## Every item in the game.
const ITEM_IDS: Array[String] = [
	"torch",
	"broom",
	"pennant",
	"star_chart",
	"brass_lantern",
	"music_box",
	"trophy_small",
	"potted_moonpetal",
	"seed_glowcap",
	"seed_moonpetal",
	"seed_whisperroot",
	"seed_emberbloom",
	"glowcap",
	"moonpetal",
	"whisperroot",
	"emberbloom",
	"crystal_dust",
	"ember_salt",
	"dew_vial",
	"potion_glow",
	"potion_featherfall",
	"potion_voice",
	"potion_colour",
	"confetti_charm",
	"creature_treat",
	"familiar_mossling",
	"familiar_emberkit",
	"familiar_glimmerwing",
	"wayfinder_chart",
	"game_set",
]
## Items every new character owns (offline default; the server creates the
## same set on first join).
const STARTING_ITEMS := [{"id": "torch", "count": 1}]

static var _cache: Dictionary = {}


static func exists(id: String) -> bool:
	return ITEM_IDS.has(id)


## Returns the id if it names a known item, otherwise "".
static func sanitize(id: String) -> String:
	return id if exists(id) else ""


static func load_definition(id: String) -> ItemDefinition:
	if not exists(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var def := load(ITEMS_DIR + id + ".tres") as ItemDefinition
	if def != null:
		_cache[id] = def
	return def


## Inventory state a character starts with when nothing is stored yet.
static func default_state() -> Dictionary:
	return {"items": STARTING_ITEMS.duplicate(true), "held": ""}


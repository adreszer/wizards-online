class_name ItemRegistry
extends RefCounted
## Looks item definitions up by id. Ids travel over the network and live in
## Nakama storage, so anything received from outside goes through
## [method sanitize] before it is used. Mirrors `ITEMS` in
## nakama/modules/world_match.lua; keep the two in sync.

const ITEMS_DIR := "res://resources/items/"
## Items every new character owns (offline default; the server creates the
## same set on first join).
const STARTING_ITEMS := [{"id": "torch", "count": 1}]

static var _cache: Dictionary = {}


static func exists(id: String) -> bool:
	return _is_safe_id(id) and ResourceLoader.exists(ITEMS_DIR + id + ".tres")


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


static func _is_safe_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	for ch in id:
		var c := ch.unicode_at(0)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true

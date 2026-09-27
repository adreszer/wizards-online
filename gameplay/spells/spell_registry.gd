class_name SpellRegistry
extends RefCounted
## Looks spell definitions up by id. Ids travel over the network (cast events)
## and will live in Nakama storage once lessons grant spells, so anything that
## arrives from outside goes through [method sanitize] first.
##
## The list is explicit rather than a directory scan so exported builds (where
## .tres files become remapped resources) behave exactly like the editor.

const SPELLS_DIR := "res://resources/spells/"
## Every spell in the game, in curriculum order (also the default hotbar order
## for a character who learns them all).
const SPELL_IDS: Array[String] = [
	"arcane_pulse",
	"uplift",
	"galewind",
	"emberkindle",
	"wellspring",
	"frostbind",
	"glowmote",
	"duskveil",
	"unbolt",
	"mendweave",
	"quicksprout",
]

static var _cache: Dictionary = {}


static func exists(id: String) -> bool:
	return SPELL_IDS.has(id)


## Returns the id if it names a known spell, otherwise "".
static func sanitize(id: String) -> String:
	return id if exists(id) else ""


static func load_definition(id: String) -> SpellDefinition:
	if not exists(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var def := load(SPELLS_DIR + id + ".tres") as SpellDefinition
	if def != null:
		_cache[id] = def
	return def


## All definitions in [constant SPELL_IDS] order.
static func all() -> Array[SpellDefinition]:
	var out: Array[SpellDefinition] = []
	for id in SPELL_IDS:
		var def := load_definition(id)
		if def != null:
			out.append(def)
	return out

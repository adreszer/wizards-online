class_name SubjectRegistry
extends RefCounted
## Looks school subjects up by id, classroom or spell. The list is explicit,
## like SpellRegistry; tools/export_server_content.tscn exports it to the
## server (generated/subjects.lua).

const SUBJECTS_DIR := "res://resources/school/subjects/"
const SUBJECT_IDS: Array[String] = [
	"sigilcraft",
	"shapeshaping",
	"chronicles",
	"glyphs",
	"numeromancy",
	"warding",
	"elixirs",
	"herblore",
	"skyriding",
	"beastlore",
	"stargazing",
	"farsight",
]

static var _cache: Dictionary = {}


static func load_definition(id: String) -> SubjectDefinition:
	if not SUBJECT_IDS.has(id):
		return null
	if not _cache.has(id):
		_cache[id] = load(SUBJECTS_DIR + id + ".tres") as SubjectDefinition
	return _cache[id]


static func all() -> Array[SubjectDefinition]:
	var out: Array[SubjectDefinition] = []
	for id in SUBJECT_IDS:
		var def := load_definition(id)
		if def != null:
			out.append(def)
	return out


## The subject taught in an area, or null.
static func for_area(area_id: String) -> SubjectDefinition:
	for def in all():
		if def.classrooms.has(area_id):
			return def
	return null


## The subject that teaches a spell, or null.
static func for_spell(spell_id: String) -> SubjectDefinition:
	for def in all():
		if def.spells().has(spell_id):
			return def
	return null

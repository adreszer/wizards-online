class_name CharacterProfile
extends RefCounted
## The character record the server keeps per user (see nakama/modules/
## character_profile.lua): house, role and spellbook. The client only
## sanitises what it receives and asks for changes; it never decides them.

const ROLE_STUDENT := "student"
## A student trusted by the house: deducts small amounts of points, lets guests in.
const ROLE_PREFECT := "prefect"
const ROLE_PROFESSOR := "professor"
const ROLE_ADMIN := "admin"
const ROLES: Array[String] = [ROLE_STUDENT, ROLE_PREFECT, ROLE_PROFESSOR, ROLE_ADMIN]
const MAX_HOUSE := 4
## School years (placeholder names: First Circle … Seventh Circle, YEAR_n).
const MAX_YEAR := 7
## Houses (index 0 = unsorted): 1 Drakoryn (dragon), 2 Grypheon (griffin),
## 3 Phoenara (phoenix), 4 Hipporys (hippocampus). Names live in the CSV as
## HOUSE_<n>_NAME / HOUSE_<n>_ANIMAL; colours: dragon green, griffin gold,
## phoenix flame, sea blue.
const HOUSE_COLORS: Array[Color] = [Color(0.75, 0.75, 0.78), Color(0.2, 0.68, 0.38), Color(0.92, 0.72, 0.25), Color(0.95, 0.42, 0.18), Color(0.28, 0.55, 0.92)]
## House crests in assets/ui/brand/ (made by tools/prep_crests.py, see
## assets/ui/PROVENANCE.md). Full: colour, 1024 px, for 3D (mipmapped);
## CARD: colour at 256 px for 2D panels; MONO: a white glyph to tint, 1024 px;
## ICON: the glyph at 48 px for HUD and list icons.
const CREST_FULL := ""
const CREST_CARD := "_256"
const CREST_MONO := "_mono"
const CREST_ICON := "_mono_48"
const CREST_SLUGS: Array[String] = ["", "1_drakoryn", "2_grypheon", "3_phoenara", "4_hipporys"]


static func sanitize_role(role: String) -> String:
	return role if ROLES.has(role) else ROLE_STUDENT


static func sanitize_house(house: int) -> int:
	return clampi(house, 0, MAX_HOUSE)


static func is_staff(role: String) -> bool:
	return role == ROLE_PROFESSOR or role == ROLE_ADMIN


## {house, role, spells: {known, slots, equipped}} with unknown values dropped.
static func sanitize(raw: Dictionary) -> Dictionary:
	var spells: Dictionary = raw.get("spells", {}) if raw.get("spells") is Dictionary else {}
	return {
		"house": sanitize_house(int(raw.get("house", 0))),
		"role": sanitize_role(str(raw.get("role", ROLE_STUDENT))),
		"spells": {
			"known": _ids(spells.get("known", [])),
			"slots": _ids(spells.get("slots", []), true),
			"equipped": SpellRegistry.sanitize(str(spells.get("equipped", ""))),
		},
		"discoveries": _strings(raw.get("discoveries", [])),
		"appearance": CharacterLook.sanitize(raw.get("appearance", {})),
		"mastery": _mastery(raw.get("mastery", {})),
		"year": clampi(int(raw.get("year", 1)), 1, MAX_YEAR),
	}


## Spell id → mastery points, known spells only.
static func _mastery(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for id: Variant in raw:
			if SpellRegistry.load_definition(str(id)) != null:
				out[str(id)] = maxi(0, int(raw[id]))
	return out


## Translation key of a house's emblem animal; "" for unsorted.
static func house_animal_key(house: int) -> String:
	return "HOUSE_%d_ANIMAL" % house if house >= 1 and house <= MAX_HOUSE else ""


## Translation key of a house's name; "" for unsorted.
static func house_name_key(house: int) -> String:
	return "HOUSE_%d_NAME" % house if house >= 1 and house <= MAX_HOUSE else ""


static func house_name(house: int) -> String:
	var key := house_name_key(house)
	# Accessibility: a symbol beside the name, so houses never rely on colour alone.
	return GameSettings.house_label(house, TranslationServer.translate(key)) if not key.is_empty() else ""


static func house_color(house: int) -> Color:
	return HOUSE_COLORS[sanitize_house(house)]


static func crest_path(house: int, variant: String = CREST_FULL) -> String:
	if house < 1 or house > MAX_HOUSE:
		return ""
	return "res://assets/ui/brand/crest_%s%s.png" % [CREST_SLUGS[house], variant]


## The house's crest, or null for the unsorted.
static func crest(house: int, variant: String = CREST_FULL) -> Texture2D:
	var path := crest_path(house, variant)
	return load(path) as Texture2D if path != "" else null


## Translation key for a role's title shown next to a name ("" for students).
static func title_key(role: String) -> String:
	match role:
		ROLE_PROFESSOR:
			return "ROLE_PROFESSOR_TITLE"
		ROLE_ADMIN:
			return "ROLE_ADMIN_TITLE"
		ROLE_PREFECT:
			return "ROLE_PREFECT_TITLE"
	return ""


static func _ids(raw: Variant, keep_empty: bool = false) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			var id := SpellRegistry.sanitize(str(v))
			if not id.is_empty() or keep_empty:
				out.append(id)
	return out


## Discovery ids from the server (solved mysteries); anything else is dropped.
static func _strings(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for v: Variant in raw:
			if v is String and not (v as String).is_empty() and not out.has(v):
				out.append(v)
	return out

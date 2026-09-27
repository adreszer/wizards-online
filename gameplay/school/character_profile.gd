class_name CharacterProfile
extends RefCounted
## The character record the server keeps per user (see nakama/modules/
## character_profile.lua): house, role and spellbook. The client only
## sanitises what it receives and asks for changes; it never decides them.

const ROLE_STUDENT := "student"
const ROLE_PROFESSOR := "professor"
const ROLE_ADMIN := "admin"
const ROLES: Array[String] = [ROLE_STUDENT, ROLE_PROFESSOR, ROLE_ADMIN]
const MAX_HOUSE := 4
## Placeholder colours per house (index 0 = unsorted). Final names/colours come from the owner.
const HOUSE_COLORS: Array[Color] = [Color(0.75, 0.75, 0.78), Color(0.95, 0.6, 0.2), Color(0.25, 0.7, 0.75), Color(0.6, 0.4, 0.85), Color(0.9, 0.4, 0.55)]


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
	}


## Translation key of a house's (placeholder) name; "" for unsorted.
static func house_name_key(house: int) -> String:
	return "HOUSE_%d_NAME" % house if house >= 1 and house <= MAX_HOUSE else ""


static func house_name(house: int) -> String:
	var key := house_name_key(house)
	return TranslationServer.translate(key) if not key.is_empty() else ""


static func house_color(house: int) -> Color:
	return HOUSE_COLORS[sanitize_house(house)]


## Translation key for a role's title shown next to a name ("" for students).
static func title_key(role: String) -> String:
	match role:
		ROLE_PROFESSOR:
			return "ROLE_PROFESSOR_TITLE"
		ROLE_ADMIN:
			return "ROLE_ADMIN_TITLE"
	return ""


static func _ids(raw: Variant, keep_empty: bool = false) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			var id := SpellRegistry.sanitize(str(v))
			if not id.is_empty() or keep_empty:
				out.append(id)
	return out

class_name CharacterRegistry
extends RefCounted
## Playable character bodies. Ids travel over the network (join metadata /
## roster), so keep them short and stable. Scenes must expose an
## `AnimationController` child, a `CastOrigin` marker and an `OffHand` socket
## (held items) somewhere inside.

const DEFAULT := "apprentice_m"

const CHARACTERS := {
	"apprentice_m": {"scene": "res://characters/visuals/apprentice_m.tscn", "name_key": "CHAR_APPRENTICE_M"},
	"placeholder": {"scene": "res://characters/components/character_visual.tscn", "name_key": "CHAR_PLACEHOLDER"},
}


static func ids() -> Array:
	var out: Array = []
	for id in CHARACTERS:
		if ResourceLoader.exists(CHARACTERS[id]["scene"]):
			out.append(id)
	return out


static func is_valid(id: String) -> bool:
	return CHARACTERS.has(id) and ResourceLoader.exists(CHARACTERS[id]["scene"])


static func sanitize(id: String) -> String:
	return id if is_valid(id) else DEFAULT


static func load_scene(id: String) -> PackedScene:
	return load(CHARACTERS[sanitize(id)]["scene"]) as PackedScene


static func name_key(id: String) -> String:
	return str(CHARACTERS[sanitize(id)]["name_key"])

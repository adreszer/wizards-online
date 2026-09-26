class_name NetworkProtocol
extends RefCounted
## Op codes and payload helpers shared by the client and mirrored in
## `nakama/modules/world_match.lua`. Keep both in sync.

## client → server → all other players: movement snapshot
const OP_STATE := 1
## client → server → all other players: spell cast event
const OP_SPELL_CAST := 2
## server → joining player: full roster {players: [{sid, uid, name}], self_sid}
const OP_ROSTER := 10
## server → others: {sid, uid, name}
const OP_PLAYER_JOINED := 11
## server → others: {sid, uid, name}
const OP_PLAYER_LEFT := 12
## client → server → same client: {t: ms} (round-trip latency probe)
const OP_PING := 20

const CHAT_ROOM := "world"
const MAX_CHAT_LENGTH := 200


static func encode(data: Dictionary) -> String:
	return JSON.stringify(data)


static func decode(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Chat sanitization shared by sender and receiver: trims, strips control
## characters and BBCode brackets, and caps the length.
static func sanitize_chat(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		var code := ch.unicode_at(0)
		if code < 32 or code == 127:
			continue
		if ch == "[" or ch == "]":
			continue
		out += ch
	return out.substr(0, MAX_CHAT_LENGTH)

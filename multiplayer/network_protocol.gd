class_name NetworkProtocol
extends RefCounted
## Op codes and payload helpers shared by the client and mirrored in
## `nakama/modules/world_match.lua`. Keep both in sync.

## client → server → all other players: movement snapshot
const OP_STATE := 1
## client → server → all other players: spell cast event
const OP_SPELL_CAST := 2
## client → server (validated against the server-side inventory) → all other
## players: {id} the sender now holds ("" = hands free)
const OP_HELD_ITEM := 3
## client → server: {id} the AreaZone the local player is in ("" = none)
const OP_AREA := 4
## client (professor/admin) → server: {sid, id} teach a spell to a player in the same classroom
const OP_GRANT_SPELL := 5
## client → server: {slots: [ids or ""], equipped: id} hotbar layout to persist
const OP_SPELLBOOK := 6
## client → server: {id} learn a practice tome's spell (interim, until lessons only)
const OP_STUDY_TOME := 7
## client → server: {answers: [1..4 × questions]} the sorting ceremony's answers
const OP_SORT := 8
## server → joining player: full roster {players: [{sid, uid, name, char, held}], self_sid}
const OP_ROSTER := 10
## server → others: {sid, uid, name}
const OP_PLAYER_JOINED := 11
## server → others: {sid, uid, name}
const OP_PLAYER_LEFT := 12
## server → joining player: its own inventory {items: [{id, count}], held}
const OP_INVENTORY := 13
## server → same player: its character profile {house, role, spells: {known, slots, equipped}}
const OP_PROFILE := 14
## server → others: {sid, role, house} a player's role/house changed
const OP_ROSTER_UPDATE := 15
## server → target: {id, by} a spell was taught to you
const OP_SPELL_GRANTED := 16
## server → professor: {ok, sid, id, reason} outcome of OP_GRANT_SPELL
const OP_GRANT_RESULT := 17
## server → same player: {ok, house, reason} outcome of OP_SORT
const OP_SORT_RESULT := 18
## client → server → same client: {t: ms} (round-trip latency probe)
const OP_PING := 20

const CHAT_ROOM := "world"
## Server RPC that changes a character's role/house (admin or HTTP key).
const RPC_ADMIN_SET_PROFILE := "admin_set_profile"
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

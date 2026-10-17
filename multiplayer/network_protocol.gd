class_name NetworkProtocol
extends RefCounted
## Op codes and payload helpers. tools/export_server_content.gd exports every
## OP_* / RPC_* constant to nakama/modules/generated/protocol.lua, which the
## match handler uses; add an op here, re-export, and both sides agree.

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
## client → server: {o: object id, e: "spell" | "interact", spell?: id} the local
## player acted on a world object; the server validates it and answers with
## OP_OBJECT_STATE to everyone (or nothing when refused)
const OP_WORLD_EVENT := 9
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
## server → all: {o: object id, s: state} a world object changed
const OP_OBJECT_STATE := 19
## client → server → same client: {t: ms} (round-trip latency probe)
const OP_PING := 20
## server → joining player: {objects: {object id: state}} every world object not in its default state
const OP_WORLD_SNAPSHOT := 21
## server → one player: {text, seconds} text already resolved in the player's
## locale (mystery clues and rewards, which never ship in the client)
const OP_SERVER_TEXT := 22
## client (professor/admin) → server: {action: "open" | "close"} a lesson in the
## sender's classroom; spell grants need an open lesson of that room's subject
const OP_LESSON := 23
## server → all (and joiners): {lessons: {area: {subject, by, sid}}} every open lesson
const OP_LESSON_STATE := 24
## server → sender: {ok, action, reason} outcome of OP_LESSON
const OP_LESSON_RESULT := 25
## client (professor/admin) → server: {house: 1–4, delta: ±points, reason}
const OP_HOUSE_POINTS := 26
## server → all (and joiners): {totals: [house 1, 2, 3, 4]} the house points tally
const OP_HOUSE_TOTALS := 27
## server → sender: {ok, house, delta, reason} outcome of OP_HOUSE_POINTS
const OP_HOUSE_POINTS_RESULT := 28
## client (professor in an open lesson) → server: {text} lecture text for the room
const OP_LECTURE := 29
## server → everyone in that classroom: {by, sid, text}
const OP_LECTURE_TEXT := 30
## client → server: {give: item id}, {time: hours 0–24}, {coins: ±amount} or {self_study: true} (start the
## room's self-study lesson now) a cheat (dev / admin): accepted from admins,
## or from anyone while the school rules say cheats_enabled
const OP_CHEAT := 31
## server → sender: {ok, id, reason} outcome of OP_CHEAT (the inventory follows as OP_INVENTORY)
const OP_CHEAT_RESULT := 32
## server → joining player, and all when it changes: {day: seconds per school day,
## offset: seconds added to the world time, by?: who moved it} (see SchoolClock)
const OP_CLOCK := 33
## server → joining player, and all when the school day rolls over or the timetable
## is reloaded: {tz: school UTC offset in minutes, slots: [{id, k: "lesson" | "study",
## s: subject id, a: area id, p: professor name, t0, t1: start/end in epoch seconds}]}
## (see Timetable; the source is nakama/content/timetable.json)
const OP_TIMETABLE := 34
## server → one player, on join and whenever its purse changes: {coins: balance,
## delta?: change, source?: "lesson" | "mystery" | "admin" | "shop", detail?: subject /
## mystery / reason} (the currency, see nakama/modules/economy.lua)
const OP_WALLET := 35

## client → server: {text, mode: "say" | "whisper" | "shout"} a line of proximity chat;
## the server sends it only to players who could hear it (see nakama/modules/chat.lua)
const OP_CHAT := 36
## server → the speaker and everyone in earshot: {sid, name, text, mode}
const OP_CHAT_LINE := 37
## client → server: {to: display name, text} a direct message
const OP_DM := 38
## server → recipient and sender: {from, from_name, to_name, text, at, mail?: delivered from
## the mailbox, self?: the sender's own copy}
const OP_DM_LINE := 39
## server → sender: {ok: false, reason, mode?} a refused chat line or DM ("too_soon",
## "no_such_player", "mailbox_full", "empty", "bad_mode"); {ok: true, mailed: true, to_name} when
## a DM went to an absent player's mailbox
const OP_CHAT_RESULT := 40
## client (professor running the lesson) → server: {text} what the classroom board shows
## ("" wipes it); everyone gets it in OP_LESSON_STATE (lessons[area].board)
const OP_BOARD := 41
## client (professor running the lesson) → server: {action: "ask", question, choices: [text]
## (none = an open question), correct: index or -1} | {action: "close"} | {action: "mark", sid, right}
const OP_QUIZ := 42
## server → each player in the classroom: {id, question, choices, by, open, answer?, right?,
## correct?} the question as that player sees it; {id: 0} = no question any more
const OP_QUIZ_STATE := 43
## client (student) → server: {id, answer: choice index | text}
const OP_QUIZ_ANSWER := 44
## server → the professor: {id, answers: [{sid, name, answer, right?}]} live, as students answer
const OP_QUIZ_ANSWERS := 45
## server → sender: {ok, tool: "board" | "quiz" | "answer", reason} outcome of a lesson tool request
const OP_LESSON_TOOL_RESULT := 46
## client (professor running the lesson) → server: {action: "start", spell, hits: 1–10, grant: bool}
## | {action: "stop"} a practical: students in the room may cast `spell` for practice and
## must hit the room's practice target `hits` times; `grant` teaches the spell to whoever finishes
const OP_PRACTICAL := 47
## server → each student in the classroom: {spell, hits, progress, done, granted?} their task;
## {spell: ""} = no practical
const OP_PRACTICAL_STATE := 48
## server → the professor: {spell, hits, students: [{sid, name, progress, done}]}
const OP_PRACTICAL_PROGRESS := 49
## client → server: {body, skin, robe} the character's look (character creator); stored in the
## profile (`appearance`), sent back in OP_PROFILE and to everyone else in OP_ROSTER_UPDATE {sid, char, look}
const OP_APPEARANCE := 50
## server → one player: {spell, points} a spell's mastery points changed (SpellMastery reads levels)
const OP_MASTERY := 51
## client (professor running the lesson) → server: {text, days} homework for everyone who
## attended (answered by OP_LESSON_TOOL_RESULT, tool "homework")
const OP_HOMEWORK := 52
## server → each attendee online: {subject, text, due, by} new homework was set
const OP_HOMEWORK_NEW := 53
## Chat modes (OP_CHAT): hearing ranges are the server's (chat.lua RANGES).
const CHAT_SAY := "say"
const CHAT_WHISPER := "whisper"
const CHAT_SHOUT := "shout"
const CHAT_ROOM := "world"
## Server RPC that finds (or creates) the shared world match.
const RPC_JOIN_WORLD := "join_world"
## Server RPC that changes a character's role/house (admin or HTTP key).
const RPC_ADMIN_SET_PROFILE := "admin_set_profile"
## Server RPC that resets world objects and shared mysteries (admin or HTTP key; dev and tests).
const RPC_ADMIN_RESET_WORLD := "admin_reset_world"
## Admin RPC: {} → {ok, slots} re-reads nakama/content/timetable.json and resends it
const RPC_ADMIN_RELOAD_TIMETABLE := "admin_reload_timetable"
## Admin RPC: {limit?} → {records: [{house, delta, reason, by_name, source, subject, at}], totals}
const RPC_HOUSE_POINTS_LEDGER := "house_points_ledger"
## Staff RPC: {id?, title, lines: [text]} → {id} stores a lesson plan for the caller
const RPC_LESSON_PLAN_SAVE := "lesson_plan_save"
## Staff RPC: {} → {plans: [{id, title, lines}]} the caller's lesson plans
const RPC_LESSON_PLAN_LIST := "lesson_plan_list"
## Admin RPC: {user_id | name, amount: ±coins, reason} → {ok, user_id, coins} (online players see it at once)
const RPC_ADMIN_GRANT_COINS := "admin_grant_coins"
## RPC: {limit?, user_id? (admins)} → {coins, entries: [{delta, source, reason, by_name, subject, area, at}]} newest first
const RPC_WALLET_LEDGER := "wallet_ledger"
## RPC: {user_id? (staff, admins)} → {user_id, record: {subjects: {id: {attended, self_study,
## quiz_right, quiz_total}}, recent: [{subject, at, slot, by, kind}]}} (see records.lua)
const RPC_SCHOOL_RECORD := "school_record"
## Admin RPC: {limit?} → {entries: [{kind: "lesson" | "self_study" | "not_held", subject, area,
## slot, by_name, opened_at, closed_at, why, attended: {uid: name}, points}]} newest first
const RPC_LESSON_LOG := "lesson_log"
## RPC: {} → {homework: [{id, subject, by_name, text, set_at, due, answer?: {text, at, grade?, comment?}}]} your homework
const RPC_HOMEWORK_LIST := "homework_list"
## RPC: {id, text} → {ok} hand in (or replace) an answer before it is due and graded
const RPC_HOMEWORK_SUBMIT := "homework_submit"
## Staff RPC: {} → {homework: [{id, subject, text, due, answers: [{user_id, name, text, grade?, comment?}]}]} what you set
const RPC_HOMEWORK_INBOX := "homework_inbox"
## Staff RPC: {id, user_id, grade: 1–6, comment} → {ok} grade one answer (into the record; a pass pays coins)
const RPC_HOMEWORK_GRADE := "homework_grade"
## Admin RPC: {dry_run?, min_subjects? (3)} → {promoted: [{user_id, name, year}], kept: n} moves every student
## whose graded subjects all pass (grades.lua) up one year
const RPC_ADMIN_ADVANCE_YEARS := "admin_advance_years"
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

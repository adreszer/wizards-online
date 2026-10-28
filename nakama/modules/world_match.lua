-- Authoritative match handler for the shared world.
-- Op codes and payloads are documented in res://multiplayer/network_protocol.gd;
-- their numbers come from generated.protocol (tools/export_server_content.gd).
-- The server owns identity (display names come from join metadata and are
-- sanitized here), inventories (storage "inventory"/"items") and character
-- profiles (storage "character"/"profile": house, role, spellbook; see
-- character_profile.lua). A held-item change is accepted only for an owned,
-- holdable item; a spell cast only for a known spell; a spell grant only from
-- a professor/admin standing in the same classroom as the target (areas come
-- from world_areas.lua, generated with the castle). World objects (secret
-- walls, switches, torches, levers, statues) are server-authoritative: a
-- client's OP_WORLD_EVENT is checked by object_rules.lua (object exists, the
-- sender stands in its area, knows the spell, the object accepts its effect,
-- rate limit) and the new state goes to everyone; joiners get a snapshot.
-- Every validated event (and every area change) also feeds the mystery
-- engine (mysteries.lua, content in nakama/content/), whose clues and
-- rewards are sent as resolved text in the player's locale (OP_SERVER_TEXT).
-- Lessons (school.lua): a professor opens a lesson in a classroom; spell
-- grants need an open lesson there and a spell of the room's subject, the
-- lesson records attendance and carries the lecture text. House points go
-- through a stored ledger and a running total broadcast to everyone.
-- Items are granted by item racks (world objects of kind "item_rack", e.g. the
-- broom stands: one per character) and by OP_CHEAT (admins, or anyone while
-- the school rules have cheats_enabled).
-- Coins (economy.lua, Nakama's wallet): students still in the room when a lesson
-- closes are paid for it, a first solve of a mystery pays, admins grant (RPC
-- admin_grant_coins, signal "grant_coins") and the dev cheat {coins}; each player
-- gets OP_WALLET on join and on every change of their purse.
-- Movement is relayed but not yet validated.

local nk = require("nakama")
local Profile = require("character_profile")
local AREAS = require("world_areas")
local Objects = require("object_rules")
local Mysteries = require("mysteries")
local School = require("school")
local Timetable = require("timetable")
local Economy = require("economy")
local Records = require("records")
local Chat = require("chat")
local Quiz = require("quiz")
local SelfStudy = require("self_study")
local Homework = require("homework")
local Quests = require("house_quests")
local Moderation = require("moderation")
local Duel = require("duel")
local Movement = require("movement")
local WARDEN = require("generated.warden")
local Features = require("features")
local Plans = require("features.plans")
local Store = require("store")
local WORLD_OBJECTS = require("generated.world_objects")

local P = require("generated.protocol")
local OP_STATE, OP_SPELL_CAST, OP_HELD_ITEM, OP_AREA = P.OP_STATE, P.OP_SPELL_CAST, P.OP_HELD_ITEM, P.OP_AREA
local OP_GRANT_SPELL, OP_SPELLBOOK, OP_STUDY_TOME, OP_SORT = P.OP_GRANT_SPELL, P.OP_SPELLBOOK, P.OP_STUDY_TOME, P.OP_SORT
local OP_ROSTER, OP_PLAYER_JOINED, OP_PLAYER_LEFT, OP_INVENTORY = P.OP_ROSTER, P.OP_PLAYER_JOINED, P.OP_PLAYER_LEFT, P.OP_INVENTORY
local OP_PROFILE, OP_ROSTER_UPDATE, OP_SPELL_GRANTED = P.OP_PROFILE, P.OP_ROSTER_UPDATE, P.OP_SPELL_GRANTED
local OP_GRANT_RESULT, OP_SORT_RESULT, OP_PING = P.OP_GRANT_RESULT, P.OP_SORT_RESULT, P.OP_PING
local OP_WORLD_EVENT, OP_OBJECT_STATE, OP_WORLD_SNAPSHOT = P.OP_WORLD_EVENT, P.OP_OBJECT_STATE, P.OP_WORLD_SNAPSHOT
local OP_SERVER_TEXT = P.OP_SERVER_TEXT
local OP_LESSON, OP_LESSON_STATE, OP_LESSON_RESULT = P.OP_LESSON, P.OP_LESSON_STATE, P.OP_LESSON_RESULT
local OP_HOUSE_POINTS, OP_HOUSE_TOTALS, OP_HOUSE_POINTS_RESULT = P.OP_HOUSE_POINTS, P.OP_HOUSE_TOTALS, P.OP_HOUSE_POINTS_RESULT
local OP_LECTURE, OP_LECTURE_TEXT = P.OP_LECTURE, P.OP_LECTURE_TEXT
local OP_CHEAT, OP_CHEAT_RESULT, OP_CLOCK = P.OP_CHEAT, P.OP_CHEAT_RESULT, P.OP_CLOCK
local OP_TIMETABLE, OP_WALLET = P.OP_TIMETABLE, P.OP_WALLET
local OP_CHAT, OP_CHAT_LINE, OP_DM, OP_DM_LINE, OP_CHAT_RESULT = P.OP_CHAT, P.OP_CHAT_LINE, P.OP_DM, P.OP_DM_LINE, P.OP_CHAT_RESULT
local OP_BOARD, OP_QUIZ, OP_QUIZ_STATE, OP_QUIZ_ANSWER = P.OP_BOARD, P.OP_QUIZ, P.OP_QUIZ_STATE, P.OP_QUIZ_ANSWER
local OP_QUIZ_ANSWERS, OP_LESSON_TOOL_RESULT = P.OP_QUIZ_ANSWERS, P.OP_LESSON_TOOL_RESULT
local OP_PRACTICAL, OP_PRACTICAL_STATE, OP_PRACTICAL_PROGRESS = P.OP_PRACTICAL, P.OP_PRACTICAL_STATE, P.OP_PRACTICAL_PROGRESS
local OP_APPEARANCE, OP_MASTERY = P.OP_APPEARANCE, P.OP_MASTERY
local OP_HOMEWORK, OP_HOMEWORK_NEW = P.OP_HOMEWORK, P.OP_HOMEWORK_NEW
local OP_GUEST_PASS, OP_GUEST_PASS_GRANTED = P.OP_GUEST_PASS, P.OP_GUEST_PASS_GRANTED
local OP_HOUSE_CUP, OP_HOUSE_QUESTS = P.OP_HOUSE_CUP, P.OP_HOUSE_QUESTS
local OP_MODERATION = P.OP_MODERATION
local OP_DUEL, OP_DUEL_HIT, OP_DUEL_STATE = P.OP_DUEL, P.OP_DUEL_HIT, P.OP_DUEL_STATE
local OP_CAUGHT, OP_RUMOURS = P.OP_CAUGHT, P.OP_RUMOURS
local MAX_RUMOURS = 8
-- Mastery: points per validated spell on a world object (practice targets give more),
-- at most one award per spell per player every MASTERY_GAP seconds.
local MASTERY_POINTS, MASTERY_PRACTICE_POINTS, MASTERY_GAP = 1, 2, 6
local MAX_PRACTICAL_HITS = 10
local PROGRESS_COLLECTION, PROGRESS_KEY = "mysteries", "progress"
local TEXT_SECONDS = 6
local MAX_AREA_ID_BYTES = 48
local TICK_RATE = 15
-- Bytes, not characters: the client caps names at 16 characters, which with
-- UTF-8 diacritics (Polish etc.) can take more bytes.
local MAX_NAME_BYTES = 48
-- Area reports are checked against the player's position (metres beyond the zone box).
local POSITION_SLACK, PENDING_AREA_SECONDS = 3.0, 4.0
-- World objects are written to storage at most this often after a change.
local WORLD_SAVE_SECONDS = 10
-- A world match nobody has been in for this long, that is not the elected one
-- (storage "world"/"match", see world.lua), lost a start-up race: it shuts down.
local ELECTION_EMPTY_SECONDS = 60

local M = {}

local function sanitize_name(name, fallback)
  if type(name) ~= "string" then
    return fallback
  end
  -- Same rule as GameSession.sanitize_display_name: ASCII letters/digits, space,
  -- "_" and "-", plus any multi-byte UTF-8 sequence (accented Latin letters).
  name = name:gsub("[^%w _%-\128-\255]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #name > MAX_NAME_BYTES then
    local cut = MAX_NAME_BYTES
    -- do not split a multi-byte character: back off over continuation bytes
    while cut > 0 and name:byte(cut + 1) and name:byte(cut + 1) >= 128 and name:byte(cut + 1) < 192 do
      cut = cut - 1
    end
    name = name:sub(1, cut):gsub("%s+$", "")
  end
  if #name == 0 then
    return fallback
  end
  return name
end

local CHARACTER_LIST = require("generated.characters")
local CHARACTERS = {}
for _, id in ipairs(CHARACTER_LIST.ids) do
  CHARACTERS[id] = true
end

local function sanitize_character(id)
  if type(id) == "string" and CHARACTERS[id] then
    return id
  end
  return CHARACTER_LIST.default
end

-- Item catalogue (ItemRegistry) and what a brand-new character owns.
local ITEM_LIST = require("generated.items")
local ITEMS = ITEM_LIST.by_id
local STARTING_ITEMS = ITEM_LIST.starting
local INVENTORY_COLLECTION, INVENTORY_KEY = "inventory", "items"

local function sanitize_inventory(raw)
  local items, seen = {}, {}
  if type(raw) == "table" and type(raw.items) == "table" then
    for _, entry in ipairs(raw.items) do
      if type(entry) == "table" and type(entry.id) == "string" and ITEMS[entry.id] and not seen[entry.id] then
        local count = math.floor(tonumber(entry.count) or 0)
        if count > 0 then
          seen[entry.id] = true
          table.insert(items, { id = entry.id, count = count })
        end
      end
    end
  end
  local held = ""
  if type(raw) == "table" and type(raw.held) == "string" and seen[raw.held] and ITEMS[raw.held].holdable then
    held = raw.held
  end
  return { v = 1, items = items, held = held }
end

local function write_inventory(uid, inventory)
  local ok, err = pcall(nk.storage_write, {
    { collection = INVENTORY_COLLECTION, key = INVENTORY_KEY, user_id = uid, value = inventory, permission_read = 1, permission_write = 0 },
  })
  if not ok then
    nk.logger_warn(string.format("inventory write failed for %s: %s", uid, tostring(err)))
  end
end

-- Reads the user's inventory, creating the starting kit on first join.
local function load_inventory(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = INVENTORY_COLLECTION, key = INVENTORY_KEY, user_id = uid } })
  if ok and objects and objects[1] and objects[1].value then
    return sanitize_inventory(objects[1].value)
  end
  local inventory = sanitize_inventory({ items = STARTING_ITEMS, held = "" })
  write_inventory(uid, inventory)
  return inventory
end

local function owns(inventory, id)
  for _, entry in ipairs(inventory.items) do
    if entry.id == id then
      return true
    end
  end
  return false
end

-- Adds one `id` to the inventory of `sid` (up to a full stack), stores it and
-- sends the player its inventory. Returns nil on success, else a reason.
local function give_item(dispatcher, state, sid, id)
  local inv, p = state.inventories[sid], state.presences[sid]
  local def = type(id) == "string" and ITEMS[id] or nil
  if not inv or not p then return "no_player" end
  if not def then return "unknown_item" end
  local entry
  for _, e in ipairs(inv.items) do
    if e.id == id then entry = e end
  end
  if entry and entry.count >= (def.max_stack or 1) then return "already_owned" end
  if entry then
    entry.count = entry.count + 1
  else
    table.insert(inv.items, { id = id, count = 1 })
  end
  write_inventory(p.user_id, inv)
  dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(inv), { p }, nil, true)
  return nil
end

local function others(state, except_sid)
  local list = {}
  for sid, p in pairs(state.presences) do
    if sid ~= except_sid then
      table.insert(list, p)
    end
  end
  return list
end

local function entry_for(state, sid)
  local p = state.presences[sid]
  local inv = state.inventories[sid]
  local profile = state.profiles[sid]
  local look = profile and profile.appearance or {}
  return { sid = sid, uid = p.user_id, name = state.names[sid] or p.username, char = state.chars[sid] or "apprentice_m",
           held = inv and inv.held or "", role = profile and profile.role or "student", house = profile and profile.house or 0,
           look = { skin = look.skin or 0, robe = look.robe or 0 } }
end

local function send_profile(dispatcher, state, sid)
  local profile = state.profiles[sid]
  local p = state.presences[sid]
  if profile and p then
    dispatcher.broadcast_message(OP_PROFILE, nk.json_encode({ house = profile.house, role = profile.role, spells = profile.spells, discoveries = profile.discoveries,
      appearance = profile.appearance, mastery = profile.mastery, year = profile.year }), { p }, nil, true)
  end
end

-- Grants a spell to the player at `sid`, persists it and tells the client. Returns true when new.
local function grant_spell(dispatcher, state, sid, id, by_name)
  local profile = state.profiles[sid]
  if not profile then
    return false
  end
  local added = Profile.grant_spell(profile, id)
  if added then
    Profile.write(state.presences[sid].user_id, profile)
    send_profile(dispatcher, state, sid)
    dispatcher.broadcast_message(OP_SPELL_GRANTED, nk.json_encode({ id = id, by = by_name or "" }), { state.presences[sid] }, nil, true)
  end
  return added
end

local function find_sid(state, user_id, name)
  for sid, p in pairs(state.presences) do
    if (user_id and user_id ~= "" and p.user_id == user_id) or (name and name ~= "" and state.names[sid] == name) then
      return sid
    end
  end
  return nil
end

-- A player may only report an area that exists and, for house areas, belongs to their
-- house (or a prefect of that house gave them a guest pass that has not run out).
local function sanitize_area(id, profile, pass)
  if type(id) ~= "string" or #id > MAX_AREA_ID_BYTES or not AREAS[id] then
    return ""
  end
  local house = AREAS[id].house or 0
  if house ~= 0 and (not profile or profile.house ~= house) and not (pass and pass.house == house and pass.expires > nk.time() / 1000) then
    return ""
  end
  return id
end

local function broadcast_profile_change(dispatcher, state, sid)
  local profile = state.profiles[sid]
  local rest = others(state, sid)
  if #rest > 0 then
    dispatcher.broadcast_message(OP_ROSTER_UPDATE, nk.json_encode({ sid = sid, role = profile.role, house = profile.house }), rest, nil, true)
  end
end

-- Per-player mystery progress (storage "mysteries"/"progress", server-only).
local function load_progress(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = PROGRESS_COLLECTION, key = PROGRESS_KEY, user_id = uid } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then
    return objects[1].value
  end
  return {}
end

local function save_progress(uid, progress)
  pcall(nk.storage_write, {
    { collection = PROGRESS_COLLECTION, key = PROGRESS_KEY, user_id = uid, value = progress, permission_read = 0, permission_write = 0 },
  })
end

-- cue (optional): "clue" or "solved", a mystery's moment the client plays a chime for;
-- key may then be nil (a solve without text still chimes).
local function send_text(dispatcher, state, sid, key, cue)
  local p = state.presences[sid]
  if p then
    local text = key and Mysteries.text(state.engine, key, state.locales[sid]) or ""
    dispatcher.broadcast_message(OP_SERVER_TEXT, nk.json_encode({ text = text, seconds = TEXT_SECONDS, cue = cue }), { p }, nil, true)
  end
end

local function players_in(state, area)
  local out = {}
  for sid, a in pairs(state.areas) do
    if a == area and state.presences[sid] then
      table.insert(out, { sid = sid, uid = state.presences[sid].user_id, house = state.profiles[sid] and state.profiles[sid].house or 0 })
    end
  end
  return out
end

-- A player's purse: the balance, and what just changed it (delta, source, detail).
local function send_wallet(dispatcher, state, sid, balance, delta, source, detail)
  local p = state.presences[sid]
  if not p then return end
  local payload = { coins = balance }
  if delta and delta ~= 0 then
    payload.delta, payload.source, payload.detail = delta, source or "", detail or ""
  end
  dispatcher.broadcast_message(OP_WALLET, nk.json_encode(payload), { p }, nil, true)
end

local function sid_of_user(state, uid)
  for sid, p in pairs(state.presences) do
    if p.user_id == uid then return sid end
  end
  return nil
end

-- Earned coins (lesson, mystery) for an online player: capped per school day.
local function pay(dispatcher, state, sid, amount, meta, detail)
  local p = state.presences[sid]
  if not p or not amount or amount <= 0 then return 0 end
  local day = Timetable.school_day(state.timetable, nk.time() / 1000)
  local paid, balance, reason = Economy.earn(p.user_id, amount, meta, state.rules, day)
  if paid > 0 then
    send_wallet(dispatcher, state, sid, balance, paid, meta.source, detail)
  elseif reason then
    nk.logger_info(string.format("economy: %s not paid %d (%s, %s)", state.names[sid] or sid, amount, meta.source, reason))
  end
  return paid
end

local function send_house_totals(dispatcher, state, presences)
  dispatcher.broadcast_message(OP_HOUSE_TOTALS, nk.json_encode({ totals = state.totals }), presences, nil, true)
end

-- The only way house points change (professors and mysteries): one ledger
-- record per change, then the new totals to everyone. Returns true when stored.
local function award_house_points(dispatcher, state, house, delta, reason, by_sid, source, subject)
  local p = state.presences[by_sid]
  local record = { house = house, delta = delta, reason = reason, by = p and p.user_id or "", by_name = state.names[by_sid] or "",
                   source = source or "mystery", subject = subject or "" }
  if not School.record_points(state.totals, record) then
    return false
  end
  send_house_totals(dispatcher, state, nil)
  return true
end

local function lessons_payload(state)
  local out = {}
  for area, lesson in pairs(state.lessons) do
    out[area] = { subject = lesson.subject, by = lesson.by_name, sid = lesson.by_sid, slot = lesson.slot or "", board = lesson.board or "", exam = lesson.exam or nil,
                  auto = lesson.kind == "self_study" or nil, board_i18n = lesson.board_i18n }
  end
  return nk.json_encode({ lessons = out })
end

local function send_lessons(dispatcher, state, presences)
  dispatcher.broadcast_message(OP_LESSON_STATE, lessons_payload(state), presences, nil, true)
end

-- Rumours: anonymous news of real events (a house solved a mystery, finished a quest,
-- won the cup) for notice boards and portraits.
local function add_rumour(dispatcher, state, key, house)
  table.insert(state.rumours, 1, { k = key, house = house or 0, at = nk.time() / 1000 })
  while #state.rumours > MAX_RUMOURS do table.remove(state.rumours) end
  dispatcher.broadcast_message(OP_RUMOURS, nk.json_encode({ rumours = state.rumours }), nil, nil, true)
end

-- House quests: the school week, progress sent to everyone, completions award points.
local function quest_week(state, now)
  return math.floor(Timetable.school_day(state.timetable, now) / 7)
end

local function send_quests(dispatcher, state, presences)
  dispatcher.broadcast_message(OP_HOUSE_QUESTS, nk.json_encode(Quests.payload(state.quests, state.quest_defs)), presences, nil, true)
end

local function count_quest(dispatcher, state, house, counter, n)
  if not house or house < 1 then return end
  Quests.roll(state.quests, quest_week(state, nk.time() / 1000))
  for _, q in ipairs(Quests.count(state.quests, state.quest_defs, house, counter, n)) do
    award_house_points(dispatcher, state, house, q.points, "house quest: " .. q.id, nil, "quest")
    add_rumour(dispatcher, state, "RUMOUR_QUEST", house)
  end
  Quests.save_state(state.quests)
  send_quests(dispatcher, state, nil)
end

-- The lesson's question as each player in the room sees it ({id = 0}: none).
local function send_quiz(dispatcher, state, area, only_sid)
  local lesson = state.lessons[area]
  for _, pl in ipairs(players_in(state, area)) do
    if not only_sid or pl.sid == only_sid then
      local locale = state.locales[pl.sid]
      local by = lesson and (lesson.kind == "self_study" and SelfStudy.text(state.self_study.host, locale) or lesson.by_name) or ""
      local view = (lesson and lesson.quiz) and Quiz.view_for(lesson.quiz, pl.sid, by, locale) or { id = 0 }
      dispatcher.broadcast_message(OP_QUIZ_STATE, nk.json_encode(view), { state.presences[pl.sid] }, nil, true)
    end
  end
end

-- The live answers, to whoever runs the lesson.
local function send_quiz_answers(dispatcher, state, lesson)
  local p = state.presences[lesson.by_sid]
  if p and lesson.quiz then
    dispatcher.broadcast_message(OP_QUIZ_ANSWERS, nk.json_encode({ id = lesson.quiz.id, answers = Quiz.answers_list(lesson.quiz) }), { p }, nil, true)
  end
end

-- Whether `sid` may cast `spell` for practice: a practical of it runs in their room
-- (the professor who runs it uses their own spellbook).
local function practising(state, sid, spell)
  local lesson = state.lessons[state.areas[sid] or ""]
  return lesson ~= nil and lesson.practical ~= nil and lesson.practical.spell == spell and lesson.by_sid ~= sid
end

local function knows_or_practises(state, sid, spell)
  local profile = state.profiles[sid]
  return (profile and Profile.knows(profile, spell)) or practising(state, sid, spell)
end

-- The practical as each student in the room sees it ({spell = ""}: none).
local function send_practical(dispatcher, state, area, only_sid)
  local lesson = state.lessons[area]
  local pr = lesson and lesson.practical
  for _, pl in ipairs(players_in(state, area)) do
    if (not only_sid or pl.sid == only_sid) and (not lesson or pl.sid ~= lesson.by_sid) then
      local view = { spell = "" }
      if pr then
        local mine = pr.students[pl.sid] or {}
        view = { spell = pr.spell, hits = pr.hits, progress = mine.progress or 0, done = mine.done == true, granted = mine.granted == true }
      end
      dispatcher.broadcast_message(OP_PRACTICAL_STATE, nk.json_encode(view), { state.presences[pl.sid] }, nil, true)
    end
  end
end

-- Everyone's progress, to whoever runs the lesson.
local function send_practical_progress(dispatcher, state, lesson)
  local p = state.presences[lesson.by_sid]
  local pr = lesson.practical
  if not p then return end
  local students = {}
  if pr then
    for sid, s in pairs(pr.students) do
      table.insert(students, { sid = sid, name = s.name, progress = s.progress, done = s.done == true })
    end
    table.sort(students, function(a, b) return a.name < b.name end)
  end
  dispatcher.broadcast_message(OP_PRACTICAL_PROGRESS, nk.json_encode({ spell = pr and pr.spell or "", hits = pr and pr.hits or 0, students = students }), { p }, nil, true)
end

-- A hit on the room's practice target with the practised spell counts for `sid`; the
-- last one finishes the task (the record notes it; a granting practical teaches the spell).
local function count_practice_hit(dispatcher, state, sid, spell)
  local area = state.areas[sid] or ""
  local lesson = state.lessons[area]
  local pr = lesson and lesson.practical
  if not pr or pr.spell ~= spell or lesson.by_sid == sid then return end
  local s = pr.students[sid]
  if not s then
    s = { name = state.names[sid] or "", progress = 0 }
    pr.students[sid] = s
  end
  if s.done then return end
  s.progress = s.progress + 1
  if s.progress >= pr.hits then
    s.done = true
    Records.practical_done(state.presences[sid].user_id, lesson.subject)
    count_quest(dispatcher, state, state.profiles[sid] and state.profiles[sid].house, "practicals", 1)
    if pr.grant and grant_spell(dispatcher, state, sid, spell, lesson.by_name) then
      s.granted = true
    end
  end
  send_practical(dispatcher, state, area, sid)
  send_practical_progress(dispatcher, state, lesson)
end

-- Marked answers go into the students' records.
local function record_marks(lesson, marked, dispatcher, state)
  for _, a in pairs(marked) do
    Records.quiz_result(a.uid, lesson.subject, a.right and 1 or 0, 1, lesson.exam == true)
    if a.right and dispatcher then
      local sid = sid_of_user(state, a.uid)
      count_quest(dispatcher, state, sid and state.profiles[sid] and state.profiles[sid].house, "quiz_right", 1)
    end
  end
end

local function close_lesson(dispatcher, state, area, why)
  local lesson = state.lessons[area]
  if not lesson then return end
  if lesson.quiz and lesson.quiz.open then
    record_marks(lesson, Quiz.close(lesson.quiz), dispatcher, state)
  end
  state.lessons[area] = nil
  send_quiz(dispatcher, state, area)
  if lesson.practical then send_practical(dispatcher, state, area) end
  local count, paid = 0, 0
  for _ in pairs(lesson.attendance) do count = count + 1 end
  -- Attendance pays: every student who attended and is still in the room, when the
  -- lesson ran long enough (opening and closing at once pays nobody).
  local minutes = (nk.time() / 1000 - lesson.opened_at) / 60
  if minutes >= state.rules.lesson_coin_minutes then
    local amount = lesson.kind == "self_study" and state.rules.coins_per_self_study or state.rules.coins_per_lesson
    for _, pl in ipairs(players_in(state, area)) do
      local profile = state.profiles[pl.sid]
      if pl.sid ~= lesson.by_sid and lesson.attendance[pl.uid] and profile and not Profile.is_staff(profile.role) then
        paid = paid + pay(dispatcher, state, pl.sid, amount,
          { source = "lesson", subject = lesson.subject, area = area, by_name = lesson.by_name }, lesson.subject)
      end
    end
  end
  nk.logger_info(string.format("lesson %s in %s by %s closed (%s), %d attended, %d points, %d coins paid, slot %s", lesson.subject, area, lesson.by_name, why, count, lesson.points, paid, lesson.slot or "-"))
  -- Records: every student who came gets the lesson in their record; the lesson goes in the log.
  local kind = lesson.kind or "lesson"
  local per_house = {}
  for uid, _ in pairs(lesson.attendance) do
    Records.lesson_attended(uid, { subject = lesson.subject, at = lesson.opened_at, slot = lesson.slot, by = lesson.by_name, kind = kind })
    local other = sid_of_user(state, uid)
    local h = other and state.profiles[other] and state.profiles[other].house or 0
    if h > 0 then per_house[h] = (per_house[h] or 0) + 1 end
  end
  for h, n in pairs(per_house) do count_quest(dispatcher, state, h, "lessons", n) end
  Records.log_lesson({ kind = kind, subject = lesson.subject, area = area, slot = lesson.slot or "", t0 = lesson.slot_t0 or 0,
                       by = lesson.by_uid or "", by_name = lesson.by_name, opened_at = lesson.opened_at, closed_at = nk.time() / 1000,
                       why = why, attended = lesson.attendance, points = lesson.points })
  send_lessons(dispatcher, state, nil)
end

-- Everyone who hears `sid` say something in `mode` (the speaker included).
local function listeners_of(state, sid, mode)
  local speaker = { pos = state.positions[sid], area = state.areas[sid] or "" }
  local out = {}
  local uid = state.presences[sid] and state.presences[sid].user_id
  for other, p in pairs(state.presences) do
    local blocked = uid and state.blocks[other] and state.blocks[other][uid]
    if other == sid or (not blocked and Chat.hears(mode, speaker, { pos = state.positions[other], area = state.areas[other] or "" })) then
      table.insert(out, p)
    end
  end
  return out
end

local function chat_refused(dispatcher, presence, reason, extra)
  local payload = { ok = false, reason = reason }
  for k, v in pairs(extra or {}) do payload[k] = v end
  dispatcher.broadcast_message(OP_CHAT_RESULT, nk.json_encode(payload), { presence }, nil, true)
end

-- A direct message from `sid` to the player called `to_name`: delivered at once when
-- they are online, otherwise left in their mailbox for their next join.
local function send_dm(dispatcher, state, sid, to_name, text)
  local from = state.presences[sid]
  local line = { from = from.user_id, from_name = state.names[sid] or "", text = text, at = nk.time() / 1000 }
  local target = find_sid(state, nil, to_name)
  if target == nil and type(to_name) == "string" then
    -- Display names are matched without regard to case.
    for other, name in pairs(state.names) do
      if string.lower(name) == string.lower(to_name) then target = other end
    end
  end
  if target and state.blocks[target] and state.blocks[target][from.user_id] then
    chat_refused(dispatcher, from, "blocked", { to_name = state.names[target] })
    return
  end
  if target then
    line.to_name = state.names[target] or to_name
    dispatcher.broadcast_message(OP_DM_LINE, nk.json_encode(line), { state.presences[target] }, nil, true)
    line.self = true
    dispatcher.broadcast_message(OP_DM_LINE, nk.json_encode(line), { from }, nil, true)
    return
  end
  local uid, known_name = Chat.uid_for_name(to_name)
  if not uid then
    chat_refused(dispatcher, from, "no_such_player", { to_name = to_name })
    return
  end
  line.to_name = known_name or to_name
  local why = Chat.post_mail(uid, line)
  if why then
    chat_refused(dispatcher, from, why, { to_name = line.to_name })
    return
  end
  dispatcher.broadcast_message(OP_CHAT_RESULT, nk.json_encode({ ok = true, mailed = true, to_name = line.to_name }), { from }, nil, true)
  line.self = true
  dispatcher.broadcast_message(OP_DM_LINE, nk.json_encode(line), { from }, nil, true)
end

-- The open lesson in `sid`'s area that `sid` may run (its opener, or any admin).
local function own_lesson(state, sid)
  local lesson = state.lessons[state.areas[sid] or ""]
  local profile = state.profiles[sid]
  if lesson and profile and (lesson.by_sid == sid or profile.role == "admin") then
    return lesson
  end
  return nil
end

-- An automated (self-study) lesson in occurrence `o`'s room, run from the subject's plan.
local function open_self_study(dispatcher, state, o, now)
  local lesson = { subject = o.subject, by_sid = nil, by_uid = "", by_name = "", opened_at = now, attendance = {}, points = 0,
                   slot = o.id, slot_t0 = o.t0, kind = "self_study", exam = o.exam == true }
  for _, pl in ipairs(players_in(state, o.area)) do lesson.attendance[pl.uid] = state.names[pl.sid] or "" end
  state.lessons[o.area] = lesson
  state.held_slots[o.id .. "@" .. o.t0] = true
  local plan = state.self_study.plans[o.subject]
  -- A lesson plan an admin approved for this subject is read first (features/plans.lua).
  SelfStudy.start(lesson, o.exam and SelfStudy.exam_plan(plan) or Plans.with_approved(plan, o.subject), now)
  nk.logger_info(string.format("self-study: %s in %s (slot %s)", o.subject, o.area, o.id))
  send_lessons(dispatcher, state, nil)
end

-- One step of an automated lesson, when it is due.
local function run_self_study(dispatcher, state, area, lesson, now)
  for _, a in ipairs(SelfStudy.tick(lesson, now)) do
    local kind = a[1]
    if kind == "say" then
      for _, pl in ipairs(players_in(state, area)) do
        local locale = state.locales[pl.sid]
        dispatcher.broadcast_message(OP_LECTURE_TEXT, nk.json_encode({ by = SelfStudy.text(state.self_study.host, locale), sid = "", auto = true,
          text = SelfStudy.text(a[2], locale) }), { state.presences[pl.sid] }, nil, true)
      end
    elseif kind == "board" then
      lesson.board, lesson.board_i18n = SelfStudy.text(a[2], "pl"), a[2]
      send_lessons(dispatcher, state, nil)
    elseif kind == "quiz" then
      state.quiz_seq = (state.quiz_seq or 0) + 1
      lesson.quiz = { id = state.quiz_seq, question = a[2].quiz, choices = a[2].choices, correct = math.floor(tonumber(a[2].correct)), answers = {}, open = true }
      send_quiz(dispatcher, state, area)
    elseif kind == "close_quiz" then
      if lesson.quiz and lesson.quiz.open then
        record_marks(lesson, Quiz.close(lesson.quiz), dispatcher, state)
        send_quiz(dispatcher, state, area)
      end
    elseif kind == "practical" then
      lesson.practical = { spell = a[2], hits = a[3], grant = SelfStudy.may_teach(state.rules, a[2]), students = {} }
      send_practical(dispatcher, state, area)
    elseif kind == "stop_practical" then
      lesson.practical = nil
      send_practical(dispatcher, state, area)
    elseif kind == "end" then
      close_lesson(dispatcher, state, area, "self-study done")
    end
  end
end

-- Timetabled lessons nobody opened within the grace period run as self-study (when
-- the subject has a plan); running ones take their next step.
local function tick_self_study(dispatcher, state, now)
  local grace = state.rules.self_study_grace_minutes * 60
  for _, o in ipairs(Timetable.occurrences(state.timetable, now)) do
    if o.subject ~= "" and state.self_study.plans[o.subject] and now >= o.t0 + grace and now < o.t1 - 60
        and not state.lessons[o.area] and not state.held_slots[o.id .. "@" .. o.t0] then
      open_self_study(dispatcher, state, o, now)
    end
  end
  for area, lesson in pairs(state.lessons) do
    if lesson.kind == "self_study" then run_self_study(dispatcher, state, area, lesson, now) end
  end
end

local function send_cup(dispatcher, state, presences, fresh)
  if not state.cup or not state.cup.winner then return end
  dispatcher.broadcast_message(OP_HOUSE_CUP, nk.json_encode({ winner = state.cup.winner, term = state.cup.term or "", totals = state.cup.totals,
    fresh = fresh or nil }), presences, nil, true)
end

local function award_cup(dispatcher, state, term)
  state.cup = School.award_cup(state.totals, term)
  nk.logger_info(string.format("house cup %s: house %d", tostring(term), state.cup.winner))
  send_house_totals(dispatcher, state, nil)
  send_cup(dispatcher, state, nil, true)
  add_rumour(dispatcher, state, "RUMOUR_CUP", state.cup.winner)
end

-- At the end of each calendar term the cup goes to the leading house.
local function check_term_end(dispatcher, state, now)
  local day = Timetable.school_day(state.timetable, now)
  for _, term in ipairs((state.timetable.calendar or {}).terms or {}) do
    if day > term.d1 and day <= term.d1 + 30 and (state.cup or {}).term ~= term.id then
      award_cup(dispatcher, state, term.id)
    end
  end
end

-- Duels: whether `sid` stands in a duelling area.
local function in_duel_area(state, sid)
  local area = state.areas[sid] or ""
  for _, a in ipairs(state.rules.duel_areas or {}) do
    if a == area then return true end
  end
  return false
end

-- The duel's state to both duellists and everyone in their rooms.
local function send_duel(dispatcher, state, duel)
  local payload = nk.json_encode({ id = duel.id, state = duel.state, a = duel.a, b = duel.b, a_name = state.names[duel.a] or "",
    b_name = state.names[duel.b] or "", hits = duel.hits, winner = duel.winner, forfeit = duel.forfeit, expired = duel.expired,
    to_win = duel.to_win or state.rules.duel_hits_to_win, rules = duel.rules, referee = duel.referee_name })
  local seen, list = {}, {}
  for _, sid in ipairs({ duel.a, duel.b }) do
    if state.presences[sid] and not seen[sid] then seen[sid] = true; table.insert(list, state.presences[sid]) end
    for _, pl in ipairs(players_in(state, state.areas[sid] or "")) do
      if not seen[pl.sid] then seen[pl.sid] = true; table.insert(list, state.presences[pl.sid]) end
    end
  end
  if #list > 0 then dispatcher.broadcast_message(OP_DUEL_STATE, payload, list, nil, true) end
end

local function end_duel(dispatcher, state, duel)
  send_duel(dispatcher, state, duel)
  if duel.winner and not duel.expired then
    nk.logger_info(string.format("duel: %s beat %s", state.names[duel.winner] or "?", state.names[Duel.opponent(duel, duel.winner)] or "?"))
  end
  state.duel_of[duel.a], state.duel_of[duel.b] = nil, nil
  -- For feature modules (the ladder) on the next tick.
  table.insert(state.finished_duels, duel)
end

local function tick_duels(dispatcher, state, now)
  local done = {}
  for sid, duel in pairs(state.duel_of) do
    if not done[duel] then
      done[duel] = true
      if duel.state == "fighting" or duel.state == "countdown" then
        for _, s in ipairs({ duel.a, duel.b }) do
          if not state.presences[s] or not in_duel_area(state, s) then Duel.forfeit(duel, s) end
        end
      end
      if Duel.tick(duel, now) or duel.state == "over" then
        if duel.state == "over" then end_duel(dispatcher, state, duel) else send_duel(dispatcher, state, duel) end
      end
    end
  end
end

-- Timetabled lessons that ended since the last check without anyone opening them
-- go in the lesson log as "not_held" (the self-study fallback keys off the same slots).
local function check_ended_slots(state, now)
  local since = state.slots_checked_at or now
  state.slots_checked_at = now
  if since >= now then return end
  for _, o in ipairs(Timetable.occurrences(state.timetable, since)) do
    if o.t1 <= now and o.kind == "lesson" then
      local key = o.id .. "@" .. o.t0
      if not state.held_slots[key] then
        Records.log_lesson({ kind = "not_held", subject = o.subject, area = o.area, slot = o.id, t0 = o.t0, by = "", by_name = o.professor or "",
                             opened_at = 0, closed_at = 0, why = "no professor", attended = {}, points = 0 })
        nk.logger_info(string.format("timetable: %s (%s) was not held", o.id, o.subject))
      end
      state.held_slots[key] = nil
    end
  end
end

-- The school clock (day length + offset); `presences` nil = everyone.
local function send_clock(dispatcher, state, presences, by_name)
  local payload = { day = School.day_seconds(state.rules), offset = state.clock_offset }
  if by_name then payload.by = by_name end
  dispatcher.broadcast_message(OP_CLOCK, nk.json_encode(payload), presences, nil, true)
end

-- The timetable's coming occurrences; `presences` nil = everyone.
local function send_timetable(dispatcher, state, presences)
  local now = nk.time() / 1000
  state.timetable_day = Timetable.school_day(state.timetable, now)
  dispatcher.broadcast_message(OP_TIMETABLE, Timetable.payload(state.timetable, now), presences, nil, true)
end

local function broadcast_object(dispatcher, oid, value)
  dispatcher.broadcast_message(OP_OBJECT_STATE, nk.json_encode({ o = oid, s = value }), nil, nil, true)
end

local function run_actions(dispatcher, state, actions)
  local now = nk.time() / 1000
  for _, a in ipairs(actions) do
    local kind = a[1]
    if kind == "text" then
      send_text(dispatcher, state, a[2], a[3], a[4])
    elseif kind == "set_state" then
      if Objects.set(state.world, a[2], a[3], now) then
        broadcast_object(dispatcher, a[2], a[3] == nil and Objects.state_of(state.world, a[2]) or a[3])
      end
    elseif kind == "discovery" then
      local profile = state.profiles[a[2]]
      if profile and Profile.discover(profile, a[3]) then
        Profile.write(state.presences[a[2]].user_id, profile)
        send_profile(dispatcher, state, a[2])
        count_quest(dispatcher, state, profile.house, "mysteries", 1)
        add_rumour(dispatcher, state, "RUMOUR_SOLVED", profile.house)
        -- A first solve pays (once per character: the discovery is the receipt).
        pay(dispatcher, state, a[2], a[5] or state.rules.coins_per_mystery, { source = "mystery", reason = a[4] or a[3] }, a[4] or a[3])
      end
    elseif kind == "house_points" then
      award_house_points(dispatcher, state, a[2], a[3], a[4], a[5], "mystery")
    end
  end
end

-- Feeds one validated event from `sid` to the mystery engine and runs the result.
local function feed_mysteries(dispatcher, state, sid, ev)
  local p, profile = state.presences[sid], state.profiles[sid]
  if not p or not profile then
    return
  end
  local inv = state.inventories[sid]
  ev.sid, ev.uid, ev.house, ev.held, ev.year = sid, p.user_id, profile.house, inv and inv.held or "", profile.year or 1
  ev.area = ev.area or state.areas[sid]
  ev.now = nk.time() / 1000
  local ctx = {
    players_in = function(area) return players_in(state, area) end,
    player_progress = function(uid) return state.progress[uid] end,
    progress_changed = function(uid) save_progress(uid, state.progress[uid]) end,
    has_discovery = function(id)
      for _, d in ipairs(profile.discoveries or {}) do
        if d == id then return true end
      end
      return false
    end,
  }
  run_actions(dispatcher, state, Mysteries.on_event(state.engine, state.mysteries, ev, ctx))
end

-- World objects outlive a server restart: their states (but not torches, which relight
-- on timers) are written to storage when they changed, at most every WORLD_SAVE_SECONDS.
local function lasting_objects(objects)
  local out = {}
  for oid, s in pairs(objects) do
    local def = WORLD_OBJECTS[oid]
    if def and def.kind ~= "wall_torch" then out[oid] = s end
  end
  return out
end

local function save_world(state, now)
  if now - (state.world_saved_at or 0) < WORLD_SAVE_SECONDS then return end
  state.world_saved_at = now
  local value = { objects = lasting_objects(state.world.objects), mysteries = Mysteries.to_saved(state.mysteries) }
  local encoded = nk.json_encode(value)
  if encoded ~= state.world_saved then
    state.world_saved = encoded
    Store.write("world", "objects", nil, value)
  end
end

-- Built further down (it needs every helper); declared here for set_area.
local feature_api

-- Whether `sid`'s last reported position lies in (or within POSITION_SLACK of) `area`'s
-- zone box (world_areas.lua c/s). No position yet, no box, or no area: nothing to check.
local function position_fits(state, sid, area)
  local def = area ~= "" and AREAS[area] or nil
  local pos = state.positions[sid]
  if not def or not def.c or not def.s or not pos then return true end
  for i = 1, 3 do
    if math.abs(pos[i] - def.c[i]) > def.s[i] / 2 + POSITION_SLACK then return false end
  end
  return true
end

-- The player is in `area` now (already checked): lessons, quizzes, practicals, the
-- mystery engine, the map's secrets and the feature modules hear of it.
local function set_area(dispatcher, state, sid, area)
  local changed = area ~= state.areas[sid]
  local previous = state.areas[sid] or ""
  state.areas[sid] = area
  if not changed then return end
  Features.each("area", feature_api(dispatcher, state), sid, area, previous)
  if area == "" then return end
  local p = state.presences[sid]
  local lesson = state.lessons[area]
  if lesson and lesson.by_sid ~= sid and p then
    lesson.attendance[p.user_id] = state.names[sid] or ""
  end
  if lesson and lesson.quiz then send_quiz(dispatcher, state, area, sid) end
  if lesson and lesson.practical then send_practical(dispatcher, state, area, sid) end
  feed_mysteries(dispatcher, state, sid, { event = "enter", area = area })
  -- A secret area, once walked into, stays on this character's map.
  local profile = state.profiles[sid]
  if AREAS[area].kind == "secret" and profile and p and Profile.discover(profile, "map:" .. area) then
    Profile.write(p.user_id, profile)
    send_profile(dispatcher, state, sid)
  end
end

-- Takes `n` (default 1) of `id` from `sid`'s inventory. Returns true when they had enough.
local function take_item(dispatcher, state, sid, id, n)
  local inv, p = state.inventories[sid], state.presences[sid]
  n = n or 1
  if not inv or not p then return false end
  for i, e in ipairs(inv.items) do
    if e.id == id and e.count >= n then
      e.count = e.count - n
      if e.count == 0 then
        table.remove(inv.items, i)
        if inv.held == id then inv.held = "" end
      end
      write_inventory(p.user_id, inv)
      dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(inv), { p }, nil, true)
      return true
    end
  end
  return false
end

local function count_item(state, sid, id)
  for _, e in ipairs((state.inventories[sid] or { items = {} }).items) do
    if e.id == id then return e.count end
  end
  return 0
end

-- The helpers feature modules (features.lua) work through: the match state to read,
-- and every way they may change the world, bound to this dispatcher.
function feature_api(dispatcher, state)
  local api = { nk = nk, state = state, now = nk.time() / 1000, AREAS = AREAS, ITEMS = ITEMS, rules = state.rules }
  function api.uid(sid) local p = state.presences[sid] return p and p.user_id or nil end
  function api.name(sid) return state.names[sid] or "" end
  function api.profile(sid) return state.profiles[sid] end
  function api.role(sid) local pr = state.profiles[sid] return pr and pr.role or "student" end
  function api.house(sid) local pr = state.profiles[sid] return pr and pr.house or 0 end
  function api.is_staff(sid) local r = api.role(sid) return r == "professor" or r == "admin" end
  function api.is_admin(sid) return api.role(sid) == "admin" end
  function api.area(sid) return state.areas[sid] or "" end
  function api.position(sid) return state.positions[sid] end
  -- Whether the player's latest state has them on a broom.
  function api.riding(sid) return state.riding_at[sid] ~= nil end
  function api.locale(sid) return state.locales[sid] or "pl" end
  function api.online(sid) return state.presences[sid] ~= nil end
  function api.find(name) return find_sid(state, nil, name) end
  function api.sid_of_user(uid) return sid_of_user(state, uid) end
  function api.players_in(area) return players_in(state, area) end
  function api.sids()
    local out = {}
    for sid, _ in pairs(state.presences) do table.insert(out, sid) end
    return out
  end
  function api.save_profile(sid)
    local p = state.presences[sid]
    if p and state.profiles[sid] then
      Profile.write(p.user_id, state.profiles[sid])
      send_profile(dispatcher, state, sid)
    end
  end
  -- OP_PUSH {kind, data} to `sids` (a list, one sid, or nil for everyone).
  function api.push(kind, data, sids)
    local list
    if sids ~= nil then
      list = {}
      for _, sid in ipairs(type(sids) == "table" and sids or { sids }) do
        if state.presences[sid] then table.insert(list, state.presences[sid]) end
      end
      if #list == 0 then return end
    end
    dispatcher.broadcast_message(P.OP_PUSH, nk.json_encode({ kind = kind, data = data }), list, nil, true)
  end
  -- A notification the client translates: `key` and its `args` (translation keys among them are translated).
  function api.notice(sids, key, args, seconds)
    api.push("notice", { key = key, args = args or {}, seconds = seconds or 6 }, sids)
  end
  function api.award(house, delta, reason, source, by_sid)
    return award_house_points(dispatcher, state, house, delta, reason, by_sid, source)
  end
  function api.pay(sid, amount, source, detail)
    return pay(dispatcher, state, sid, amount, { source = source }, detail)
  end
  -- Coins taken for a purchase (or a fee): ok, balance, reason.
  function api.spend(sid, amount, reason)
    local uid = api.uid(sid)
    if not uid then return false, 0, "offline" end
    local done, balance, why = Economy.spend(uid, amount, reason)
    if done then send_wallet(dispatcher, state, sid, balance, -amount, "shop", reason) end
    return done, balance, why
  end
  function api.give_item(sid, id) return give_item(dispatcher, state, sid, id) end
  function api.take_item(sid, id, n) return take_item(dispatcher, state, sid, id, n) end
  function api.count_item(sid, id) return count_item(state, sid, id) end
  function api.rumour(key, house) add_rumour(dispatcher, state, key, house) end
  function api.text(sid, key) send_text(dispatcher, state, sid, key) end
  function api.log(entry) Records.log_lesson(entry) end
  function api.feed(sid, ev) feed_mysteries(dispatcher, state, sid, ev) end
  function api.grant_spell(sid, id, by_name) return grant_spell(dispatcher, state, sid, id, by_name) end
  function api.school_hours()
    local day = School.day_seconds(state.rules)
    return ((api.now + state.clock_offset) / day % 1) * 24
  end
  function api.school_day() return Timetable.school_day(state.timetable, api.now) end
  function api.timetable() return state.timetable end
  -- World objects: the state of one, set it (sent to everyone), and whether players may change it.
  function api.object_state(oid) return Objects.state_of(state.world, oid) end
  function api.set_object(oid, value)
    state.world.objects[oid] = value
    broadcast_object(dispatcher, oid, value)
  end
  function api.drive(oid, on) state.world.driven[oid] = on or nil end
  function api.profile_changed(sid)
    api.save_profile(sid)
    broadcast_profile_change(dispatcher, state, sid)
  end
  function api.reload_timetable()
    state.timetable = Timetable.load()
    send_timetable(dispatcher, state, nil)
    return #state.timetable.slots
  end
  return api
end

function M.match_init(context, params)
  local state = { presences = {}, names = {}, chars = {}, inventories = {}, profiles = {}, areas = {}, locales = {},
                  progress = {}, world = Objects.new_world(), mysteries = Mysteries.new_state(), engine = Mysteries.load(),
                  lessons = {}, rules = School.load_rules(), totals = School.load_totals(), points_at = {},
                  clock_offset = School.load_clock_offset(), timetable = Timetable.load(), timetable_day = 0, held_slots = {},
                  positions = {}, chat_at = {}, self_study = SelfStudy.load(), mastery_at = {}, guest_passes = {}, cup = School.load_cup(),
                  quests = Quests.load_state(), quest_defs = Quests.load_defs(), filter = Moderation.load_filter(), blocks = {}, moderation = {}, duel_of = {}, duel_seq = 0, caught_night = {}, rumours = {}, finished_duels = {}, features = {}, flight_checked = {}, pending_area = {}, riding_at = {}, movement = {} }
  state.world.driven = state.engine.driven
  local saved = Store.read("world", "objects", nil)
  if saved and type(saved.objects) == "table" then
    for oid, s in pairs(lasting_objects(saved.objects)) do state.world.objects[oid] = s end
  end
  if saved then
    state.mysteries = Mysteries.from_saved(state.engine, saved.mysteries)
    state.world_saved = nk.json_encode({ objects = lasting_objects(state.world.objects), mysteries = Mysteries.to_saved(state.mysteries) })
  end
  return state, TICK_RATE, "world"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  if Moderation.load(presence.user_id).banned then
    return state, false, "banned"
  end
  state.names[presence.session_id] = sanitize_name(metadata and metadata.display_name, presence.username)
  -- Display names go through the word filter: a filtered name falls back to the account's username.
  if Moderation.filter(state.names[presence.session_id], state.filter) ~= state.names[presence.session_id] then
    state.names[presence.session_id] = sanitize_name(presence.username, "student")
  end
  state.chars[presence.session_id] = sanitize_character(metadata and metadata.character)
  local locale = metadata and metadata.locale
  state.locales[presence.session_id] = (locale == "en" or locale == "pl") and locale or Mysteries.FALLBACK_LOCALE
  return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
  local admins = Profile.env_admins(context.env)
  for _, p in ipairs(presences) do
    state.presences[p.session_id] = p
    state.inventories[p.session_id] = load_inventory(p.user_id)
    local profile = Profile.load(p.user_id)
    if admins[p.user_id] and profile.role ~= "admin" then
      profile.role = "admin"
      Profile.write(p.user_id, profile)
    end
    state.profiles[p.session_id] = profile
    -- The stored look decides the body once chosen; before that the menu's pick does.
    if profile.appearance.set then
      state.chars[p.session_id] = profile.appearance.body
    else
      profile.appearance.body = state.chars[p.session_id] or profile.appearance.body
    end
    state.areas[p.session_id] = ""
    state.progress[p.user_id] = load_progress(p.user_id)
    Chat.remember_name(p.user_id, state.names[p.session_id])
    state.blocks[p.session_id] = Moderation.load_blocks(p.user_id)
    state.moderation[p.session_id] = Moderation.load(p.user_id)
  end
  for _, p in ipairs(presences) do
    local roster = {}
    for sid, _ in pairs(state.presences) do
      table.insert(roster, entry_for(state, sid))
    end
    dispatcher.broadcast_message(OP_ROSTER, nk.json_encode({ players = roster, self_sid = p.session_id }), { p }, nil, true)
    dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(state.inventories[p.session_id]), { p }, nil, true)
    send_profile(dispatcher, state, p.session_id)
    dispatcher.broadcast_message(OP_WORLD_SNAPSHOT, nk.json_encode({ objects = state.world.objects, s = nk.time() }), { p }, nil, true)
    send_lessons(dispatcher, state, { p })
    send_house_totals(dispatcher, state, { p })
    send_cup(dispatcher, state, { p })
    if Quests.roll(state.quests, quest_week(state, nk.time() / 1000)) then Quests.save_state(state.quests) end
    send_quests(dispatcher, state, { p })
    if #state.rumours > 0 then dispatcher.broadcast_message(OP_RUMOURS, nk.json_encode({ rumours = state.rumours }), { p }, nil, true) end
    send_wallet(dispatcher, state, p.session_id, Economy.balance(p.user_id))
    send_clock(dispatcher, state, { p })
    send_timetable(dispatcher, state, { p })
    Features.each("join", feature_api(dispatcher, state), p.session_id)
    -- Direct messages that arrived while the player was away.
    for _, mail in ipairs(Chat.take_mail(p.user_id)) do
      mail.mail = true
      dispatcher.broadcast_message(OP_DM_LINE, nk.json_encode(mail), { p }, nil, true)
    end
    local rest = others(state, p.session_id)
    if #rest > 0 then
      dispatcher.broadcast_message(OP_PLAYER_JOINED, nk.json_encode(entry_for(state, p.session_id)), rest, nil, true)
    end
  end
  return state
end

function M.match_leave(context, dispatcher, tick, state, presences)
  for _, p in ipairs(presences) do
    local sid = p.session_id
    if state.presences[sid] then
      local entry = entry_for(state, sid)
      Features.each("leave", feature_api(dispatcher, state), sid)
      state.presences[sid] = nil
      state.names[sid] = nil
      state.chars[sid] = nil
      state.inventories[sid] = nil
      state.profiles[sid] = nil
      state.areas[sid] = nil
      state.locales[sid] = nil
      state.points_at[sid] = nil
      state.positions[sid] = nil
      state.chat_at[sid] = nil
      state.mastery_at[sid] = nil
      state.guest_passes[sid] = nil
      state.blocks[sid] = nil
      state.moderation[sid] = nil
      state.flight_checked[sid] = nil
      state.pending_area[sid] = nil
      state.riding_at[sid] = nil
      state.movement[sid] = nil
      for area, lesson in pairs(state.lessons) do
        if lesson.by_sid == sid then
          close_lesson(dispatcher, state, area, "professor left")
        end
      end
      if not find_sid(state, p.user_id, nil) then
        state.progress[p.user_id] = nil
      end
      Objects.forget_player(state.world, sid)
      local rest = others(state, sid)
      if #rest > 0 then
        dispatcher.broadcast_message(OP_PLAYER_LEFT, nk.json_encode(entry), rest, nil, true)
      end
    end
  end
  return state
end

function M.match_loop(context, dispatcher, tick, state, messages)
  local now = nk.time() / 1000
  if tick % (TICK_RATE * 10) == 0 then
    if next(state.presences) then
      state.empty_since = nil
    else
      state.empty_since = state.empty_since or now
      if now - state.empty_since >= ELECTION_EMPTY_SECONDS then
        local elected = Store.read("world", "match", nil)
        if elected and elected.id and elected.id ~= context.match_id then
          nk.logger_info("world match " .. context.match_id .. " lost the election to " .. tostring(elected.id) .. "; shutting down")
          return nil
        end
      end
    end
  end
  for _, change in ipairs(Objects.tick(state.world, now)) do
    broadcast_object(dispatcher, change[1], change[2])
  end
  if tick % TICK_RATE == 0 then
    for area, lesson in pairs(state.lessons) do
      if now - lesson.opened_at > state.rules.session_max_minutes * 60 then
        close_lesson(dispatcher, state, area, "time")
      end
    end
    -- A new school day rolls the timetable window on.
    if Timetable.school_day(state.timetable, now) ~= state.timetable_day then
      send_timetable(dispatcher, state, nil)
    end
    check_ended_slots(state, now)
    tick_self_study(dispatcher, state, now)
    tick_duels(dispatcher, state, now)
    Features.each("tick", feature_api(dispatcher, state), now)
    save_world(state, now)
    if tick % (TICK_RATE * 60) == 0 then check_term_end(dispatcher, state, now) end
    local occupied = function(area) return #players_in(state, area) > 0 end
    run_actions(dispatcher, state, Mysteries.tick(state.engine, state.mysteries, nk.time() / 1000, occupied))
  end
  for _, message in ipairs(messages) do
    local sid = message.sender.session_id
    if message.op_code == OP_STATE then
      local reported = Chat.position_of(message.data)
      local verdict = "accept"
      -- Dev servers (cheats on: tests and cheats teleport) and admins are not checked.
      local profile = state.profiles[sid]
      local checked = state.rules.movement_check ~= false and not state.rules.cheats_enabled
                      and not (profile and profile.role == "admin")
      if not checked then
        state.movement[sid] = nil
        state.positions[sid] = reported or state.positions[sid]
      elseif reported then
        local tracker = state.movement[sid] or Movement.new()
        state.movement[sid] = tracker
        local info
        verdict, info = Movement.check(tracker, reported, now)
        if verdict == "accept" then
          state.positions[sid] = reported
        elseif verdict == "reject" then
          nk.logger_warn(string.format("movement: %s jumped %.1f m (allowed %.1f), strike %d", state.names[sid] or sid, info.moved, info.allowed, info.strikes))
          if info.correct and state.presences[sid] then
            dispatcher.broadcast_message(P.OP_PUSH, nk.json_encode({ kind = "position", data = { p = tracker.pos } }), { state.presences[sid] }, nil, true)
          end
          if info.report then
            Moderation.report({ from = "server", from_name = "server", about = message.sender.user_id, about_name = state.names[sid] or "",
                                reason = string.format("movement: %d impossible moves in %ds (last %.0f m, allowed %.0f m), snapped back", Movement.STRIKES_TO_CORRECT, Movement.STRIKE_WINDOW, info.moved, info.allowed) })
          end
        end
      end
      local pending = state.pending_area[sid]
      if pending then
        if position_fits(state, sid, pending.area) then
          state.pending_area[sid] = nil
          set_area(dispatcher, state, sid, pending.area)
        elseif now - pending.at > PENDING_AREA_SECONDS then
          state.pending_area[sid] = nil
          nk.logger_info(string.format("area report %s from %s refused: not where their state is", pending.area, state.names[sid] or sid))
        end
      end
      -- Riders: where flying is allowed is the server's call (features/flying.lua).
      local riding = message.data:find('"m":"broom"', 1, true) ~= nil
      state.riding_at[sid] = riding and now or nil
      if riding and now - (state.flight_checked[sid] or 0) >= 1 then
        state.flight_checked[sid] = now
        Features.each("flying", feature_api(dispatcher, state), sid)
      end
      local rest = verdict == "accept" and others(state, sid) or {}
      if #rest > 0 then
        dispatcher.broadcast_message(OP_STATE, message.data, rest, message.sender, false)
      end
    elseif message.op_code == OP_SPELL_CAST then
      -- Only spells the character actually knows leave the server.
      local ok, payload = pcall(nk.json_decode, message.data)
      if ok and type(payload) == "table" and type(payload.id) == "string" and knows_or_practises(state, sid, payload.id) then
        local rest = others(state, sid)
        if #rest > 0 then
          dispatcher.broadcast_message(OP_SPELL_CAST, message.data, rest, message.sender, true)
        end
      end
    elseif message.op_code == OP_AREA then
      local ok, payload = pcall(nk.json_decode, message.data)
      if ok and type(payload) == "table" then
        local area = sanitize_area(payload.id, state.profiles[sid], state.guest_passes[sid])
        -- Feature modules may keep a student out of a place (the sealed stacks without a slip).
        if area ~= "" and not Features.allow(feature_api(dispatcher, state), "enter", sid, area) then area = "" end
        -- The report must agree with where the player's own state says they are; a
        -- report ahead of the next state waits for it (a few seconds at most).
        if position_fits(state, sid, area) then
          state.pending_area[sid] = nil
          set_area(dispatcher, state, sid, area)
        else
          state.pending_area[sid] = { area = area, at = now }
        end
      end
    elseif message.op_code == OP_SORT then
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      local reason = nil
      local scores = ok and type(payload) == "table" and Profile.tally(payload.answers) or nil
      if not profile then
        reason = "no_profile"
      elseif profile.house ~= 0 then
        reason = "already_sorted"
      elseif not scores then
        reason = "bad_answers"
      end
      if not reason then
        local counts = Profile.load_counts()
        profile.house = Profile.pick_house(scores, counts)
        counts[profile.house] = (counts[profile.house] or 0) + 1
        Profile.write_counts(counts)
        Profile.write(message.sender.user_id, profile)
        send_profile(dispatcher, state, sid)
        broadcast_profile_change(dispatcher, state, sid)
      end
      dispatcher.broadcast_message(OP_SORT_RESULT, nk.json_encode({ ok = reason == nil, house = profile and profile.house or 0, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_GRANT_SPELL then
      local ok, payload = pcall(nk.json_decode, message.data)
      local target = ok and type(payload) == "table" and type(payload.sid) == "string" and payload.sid or ""
      local id = ok and type(payload) == "table" and type(payload.id) == "string" and payload.id or ""
      local profile = state.profiles[sid]
      local reason = nil
      if not profile or not Profile.is_staff(profile.role) then
        reason = "not_staff"
      elseif not Profile.SPELLS[id] then
        reason = "unknown_spell"
      elseif not state.presences[target] then
        reason = "no_such_player"
      else
        local area = state.areas[sid] or ""
        local info = AREAS[area]
        if area == "" or not info or info.kind ~= "classroom" then
          reason = "not_in_classroom"
        elseif not state.lessons[area] then
          reason = "no_lesson"
        elseif not own_lesson(state, sid) then
          reason = "not_your_lesson"
        elseif not School.teaches(state.lessons[area].subject, id) then
          reason = "not_in_subject"
        elseif (state.areas[target] or "") ~= area then
          reason = "target_elsewhere"
        elseif Profile.knows(state.profiles[target], id) then
          reason = "already_known"
        end
      end
      if not reason then
        grant_spell(dispatcher, state, target, id, state.names[sid])
      end
      dispatcher.broadcast_message(OP_GRANT_RESULT, nk.json_encode({ ok = reason == nil, sid = target, id = id, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_STUDY_TOME then
      -- Interim: practice tomes teach any registered spell while the school
      -- rules allow it (practice_tomes_enabled); lessons are the real path.
      local ok, payload = pcall(nk.json_decode, message.data)
      local id = ok and type(payload) == "table" and type(payload.id) == "string" and payload.id or ""
      if state.rules.practice_tomes_enabled and Profile.SPELLS[id] then
        grant_spell(dispatcher, state, sid, id, "")
      end
    elseif message.op_code == OP_SPELLBOOK then
      -- The player rearranged the hotbar: keep known spells, adopt slots/equipped.
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      if ok and type(payload) == "table" and profile then
        local spells = Profile.sanitize_spells({ known = profile.spells.known, slots = payload.slots, equipped = payload.equipped })
        profile.spells = spells
        Profile.write(message.sender.user_id, profile)
      end
    elseif message.op_code == OP_HELD_ITEM then
      local ok, payload = pcall(nk.json_decode, message.data)
      local inv = state.inventories[sid]
      local id = ok and type(payload) == "table" and payload.id or nil
      if inv and type(id) == "string" and (id == "" or (ITEMS[id] and ITEMS[id].holdable and owns(inv, id))) then
        if inv.held ~= id then
          inv.held = id
          write_inventory(message.sender.user_id, inv)
        end
        local rest = others(state, sid)
        if #rest > 0 then
          dispatcher.broadcast_message(OP_HELD_ITEM, nk.json_encode({ sid = sid, id = id }), rest, message.sender, true)
        end
      end
    elseif message.op_code == OP_WORLD_EVENT then
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      if ok and profile then
        local ctx = { sid = sid, area = state.areas[sid], knows = function(id) return knows_or_practises(state, sid, id) end }
        local ev, reason = Objects.validate(state.world, ctx, payload, now)
        if ev then
          local api = feature_api(dispatcher, state)
          local allowed, why = Features.allow(api, "object", sid, ev)
          if not allowed then
            api.notice(sid, "REFUSED_" .. tostring(why):upper(), {}, 4)
            ev, reason = nil, why
          end
        end
        if ev then
          local value = Objects.apply(state.world, ev, now)
          if value ~= nil then
            broadcast_object(dispatcher, ev.oid, value)
          end
          if ev.obj.kind == "item_rack" and ev.event == "interact" then
            local allowed, why = Features.allow(feature_api(dispatcher, state), "take_item", sid, ev.obj.item_id)
            if allowed then
              give_item(dispatcher, state, sid, ev.obj.item_id)
            else
              feature_api(dispatcher, state).notice(sid, "REFUSED_" .. tostring(why):upper(), {}, 5)
            end
          end
          if ev.obj.kind == "practice_target" and ev.event == "spell" then
            count_practice_hit(dispatcher, state, sid, ev.spell)
          end
          if ev.event == "spell" and Profile.knows(profile, ev.spell) then
            local gaps = state.mastery_at[sid] or {}
            state.mastery_at[sid] = gaps
            if not gaps[ev.spell] or now - gaps[ev.spell] >= MASTERY_GAP then
              gaps[ev.spell] = now
              local points = Profile.add_mastery(profile, ev.spell, ev.obj.kind == "practice_target" and MASTERY_PRACTICE_POINTS or MASTERY_POINTS)
              Profile.write(message.sender.user_id, profile)
              dispatcher.broadcast_message(OP_MASTERY, nk.json_encode({ spell = ev.spell, points = points }), { message.sender }, nil, true)
            end
          end
          feed_mysteries(dispatcher, state, sid, { event = ev.event, object = ev.oid, effect_type = ev.effect_type, state = Objects.state_of(state.world, ev.oid) })
          Features.each("event", feature_api(dispatcher, state), sid, ev)
        else
          nk.logger_debug(string.format("world event from %s refused: %s", sid, tostring(reason)))
        end
      end
    elseif message.op_code == OP_CHEAT then
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      local id = ok and type(payload) == "table" and type(payload.give) == "string" and payload.give or ""
      local hours = ok and type(payload) == "table" and type(payload.time) == "number" and payload.time or nil
      local coins = ok and type(payload) == "table" and type(payload.coins) == "number" and payload.coins or nil
      local self_study = ok and type(payload) == "table" and payload.self_study == true
      local reason
      if not profile or not (state.rules.cheats_enabled or profile.role == "admin") then
        reason = "not_allowed"
      elseif self_study then
        -- /selfstudy: start the room's self-study lesson now (playtesting the plans).
        local area = state.areas[sid] or ""
        local subject = School.subject_for_area(area)
        if not subject or not state.self_study.plans[subject] then
          reason = "no_plan"
        elseif state.lessons[area] then
          reason = "already_open"
        else
          open_self_study(dispatcher, state, { id = "cheat", t0 = now, subject = subject, area = area, exam = payload.exam == true }, now)
        end
      elseif coins ~= nil then
        -- /coins: add to (or take from) your own purse, answered by OP_WALLET.
        if coins ~= math.floor(coins) or coins == 0 or math.abs(coins) > state.rules.max_coin_grant then
          reason = "bad_amount"
        else
          local done, balance, why = Economy.change(message.sender.user_id, coins, { source = "admin", reason = "cheat", by_name = state.names[sid] or "" })
          reason = why
          if done then
            send_wallet(dispatcher, state, sid, balance, coins, "admin", "cheat")
            nk.logger_info(string.format("cheat: %s changed their purse by %d", state.names[sid] or sid, coins))
          end
        end
      elseif hours ~= nil then
        -- /time: move the school clock for everyone (answered by OP_CLOCK, not a result).
        if hours ~= hours or hours < 0 or hours >= 24 then
          reason = "bad_time"
        else
          state.clock_offset = School.offset_for(nk.time() / 1000, hours, School.day_seconds(state.rules))
          School.save_clock_offset(state.clock_offset)
          nk.logger_info(string.format("cheat: %s set the school clock to %.2f h", state.names[sid] or sid, hours))
          send_clock(dispatcher, state, nil, state.names[sid] or "")
        end
      else
        reason = give_item(dispatcher, state, sid, id)
        nk.logger_info(string.format("cheat: %s gave themselves %s (%s)", state.names[sid] or sid, id, tostring(reason or "ok")))
      end
      if (hours == nil and coins == nil and not self_study) or reason ~= nil then
        dispatcher.broadcast_message(OP_CHEAT_RESULT, nk.json_encode({ ok = reason == nil, id = ITEMS[id] and id or "", reason = reason or "" }), { message.sender }, nil, true)
      end
    elseif message.op_code == OP_LESSON then
      local ok, payload = pcall(nk.json_decode, message.data)
      local action = ok and type(payload) == "table" and payload.action or ""
      local profile = state.profiles[sid]
      local area = state.areas[sid] or ""
      local reason = nil
      if not profile or not Profile.is_staff(profile.role) then
        reason = "not_staff"
      elseif action == "open" then
        local subject = School.subject_for_area(area)
        -- A professor who arrives takes over from the self-study quill.
        if subject and state.lessons[area] and state.lessons[area].kind == "self_study" then
          close_lesson(dispatcher, state, area, "professor arrived")
        end
        if not subject then
          reason = "not_in_classroom"
        elseif state.lessons[area] then
          reason = "already_open"
        else
          -- A lesson opened in its timetable slot (or just before) belongs to that slot.
          local slot = Timetable.current(state.timetable, now, area, subject)
          state.lessons[area] = { subject = subject, by_sid = sid, by_uid = message.sender.user_id, by_name = state.names[sid] or "", opened_at = now,
                                  attendance = {}, points = 0, slot = slot and slot.id or nil, slot_t0 = slot and slot.t0 or nil }
          if slot then state.held_slots[slot.id .. "@" .. slot.t0] = true end
          for _, pl in ipairs(players_in(state, area)) do
            if pl.sid ~= sid then state.lessons[area].attendance[pl.uid] = state.names[pl.sid] or "" end
          end
          send_lessons(dispatcher, state, nil)
        end
      elseif action == "close" then
        if not own_lesson(state, sid) then
          reason = "no_lesson"
        else
          close_lesson(dispatcher, state, area, "closed")
        end
      else
        reason = "bad_action"
      end
      dispatcher.broadcast_message(OP_LESSON_RESULT, nk.json_encode({ ok = reason == nil, action = action, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_HOUSE_POINTS then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local profile = state.profiles[sid]
      local house, delta = payload.house, payload.delta
      local text = School.clean_text(payload.reason, state.rules.max_reason_bytes)
      local reason = nil
      local lesson = own_lesson(state, sid)
      local prefect = profile and profile.role == "prefect"
      if not profile or not (Profile.is_staff(profile.role) or prefect) then
        reason = "not_staff"
      elseif prefect and (type(delta) ~= "number" or delta >= 0 or math.abs(delta) > state.rules.max_prefect_points) then
        reason = "prefect_limit"
      elseif type(house) ~= "number" or house ~= math.floor(house) or house < 1 or house > School.HOUSES then
        reason = "bad_house"
      elseif type(delta) ~= "number" or delta ~= math.floor(delta) or delta == 0 or math.abs(delta) > state.rules.max_points_per_award then
        reason = "bad_amount"
      elseif text == "" then
        reason = "no_reason"
      elseif state.points_at[sid] and now - state.points_at[sid] < state.rules.points_cooldown_seconds then
        reason = "too_soon"
      elseif lesson and lesson.points + math.abs(delta) > state.rules.max_points_per_session then
        reason = "session_cap"
      elseif not award_house_points(dispatcher, state, house, delta, text, sid, prefect and "prefect" or "professor", lesson and lesson.subject or "") then
        reason = "storage"
      else
        state.points_at[sid] = now
        if lesson then lesson.points = lesson.points + math.abs(delta) end
      end
      dispatcher.broadcast_message(OP_HOUSE_POINTS_RESULT, nk.json_encode({ ok = reason == nil, house = house, delta = delta, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_LECTURE then
      local ok, payload = pcall(nk.json_decode, message.data)
      local text = Moderation.filter(School.clean_text(ok and type(payload) == "table" and payload.text or nil, state.rules.max_lecture_bytes), state.filter)
      if text ~= "" and own_lesson(state, sid) then
        local listeners = {}
        for _, pl in ipairs(players_in(state, state.areas[sid])) do
          table.insert(listeners, state.presences[pl.sid])
        end
        dispatcher.broadcast_message(OP_LECTURE_TEXT, nk.json_encode({ by = state.names[sid] or "", sid = sid, text = text }), listeners, nil, true)
      end
    elseif message.op_code == OP_CHAT or message.op_code == OP_DM then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local text = Moderation.filter(Chat.clean(payload.text), state.filter)
      local mode = message.op_code == OP_DM and "dm" or (payload.mode or "say")
      local last = state.chat_at[sid] or {}
      state.chat_at[sid] = last
      local cooldown = mode == "shout" and state.rules.shout_cooldown_seconds or mode == "dm" and state.rules.dm_cooldown_seconds or state.rules.chat_cooldown_seconds
      if Moderation.is_muted(state.moderation[sid] or {}, now) then
        chat_refused(dispatcher, message.sender, "muted")
      elseif text == "" then
        chat_refused(dispatcher, message.sender, "empty")
      elseif mode ~= "dm" and not Chat.MODES[mode] then
        chat_refused(dispatcher, message.sender, "bad_mode")
      elseif last[mode] and now - last[mode] < cooldown then
        chat_refused(dispatcher, message.sender, "too_soon", { mode = mode, wait = math.ceil(cooldown - (now - last[mode])) })
      else
        -- Feature modules may refuse a line (a quieted classroom) and see every delivered one (the chat log).
        local api = feature_api(dispatcher, state)
        local allowed, why = Features.allow(api, "chat", sid, mode)
        if not allowed then
          chat_refused(dispatcher, message.sender, why or "refused")
        else
          last[mode] = now
          local to = type(payload.to) == "string" and payload.to or ""
          Features.each("chat_line", api, sid, mode, text, mode == "dm" and to or nil)
          if mode == "dm" then
            send_dm(dispatcher, state, sid, to, text)
          else
            dispatcher.broadcast_message(OP_CHAT_LINE, nk.json_encode({ sid = sid, name = state.names[sid] or "", text = text, mode = mode,
              voice = Features.first("chat_voice", api, sid) }), listeners_of(state, sid, mode), nil, true)
          end
        end
      end
    elseif message.op_code == OP_HOMEWORK then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local lesson = own_lesson(state, sid)
      local reason
      if not lesson then
        reason = "no_lesson"
      else
        local hw, why = Homework.set(lesson, state.areas[sid] or "", message.sender.user_id, state.names[sid] or "", payload.text, payload.days, now)
        reason = why
        if hw then
          local notice = nk.json_encode({ subject = hw.subject, text = hw.text, due = hw.due, by = hw.by_name })
          for uid, _ in pairs(hw.students) do
            local other = sid_of_user(state, uid)
            if other then dispatcher.broadcast_message(OP_HOMEWORK_NEW, notice, { state.presences[other] }, nil, true) end
          end
        end
      end
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = "homework", reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_GUEST_PASS then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local profile = state.profiles[sid]
      local target = type(payload.name) == "string" and find_sid(state, nil, payload.name) or nil
      local reason
      if not profile or (profile.role ~= "prefect" and profile.role ~= "admin") or profile.house == 0 then
        reason = "not_prefect"
      elseif not target then
        reason = "no_such_player"
      elseif state.profiles[target] and state.profiles[target].house == profile.house then
        reason = "same_house"
      else
        local expires = now + state.rules.guest_pass_minutes * 60
        state.guest_passes[target] = { house = profile.house, expires = expires }
        dispatcher.broadcast_message(OP_GUEST_PASS_GRANTED, nk.json_encode({ house = profile.house, ["until"] = expires, by = state.names[sid] or "" }),
          { state.presences[target] }, nil, true)
      end
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = "guest", reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_CAUGHT then
      -- Checked: curfew by the school clock, the warden's room by the shared time, a
      -- student in it outside their own house, once per player per night.
      local profile = state.profiles[sid]
      local day = School.day_seconds(state.rules)
      local hours = ((now + state.clock_offset) / day % 1) * 24
      local curfew = hours >= WARDEN.curfew_start or hours < WARDEN.curfew_end
      local warden_area = WARDEN.route[(math.floor(now / WARDEN.dwell) % #WARDEN.route) + 1]
      local night = math.floor((now + state.clock_offset - WARDEN.curfew_end / 24 * day) / day)
      local area = state.areas[sid] or ""
      if profile and profile.role == "student" and curfew and (area == warden_area or area == "") and profile.house > 0
          and (state.caught_night[sid] or -1) ~= night then
        state.caught_night[sid] = night
        award_house_points(dispatcher, state, profile.house, -state.rules.curfew_points, "out after curfew: " .. (state.names[sid] or ""), nil, "curfew")
        Records.log_lesson({ kind = "detention", subject = "", area = area, slot = "", by = "", by_name = "warden", opened_at = now, closed_at = now,
                             why = "curfew", attended = { [message.sender.user_id] = state.names[sid] or "" }, points = state.rules.curfew_points })
        Features.each("caught", feature_api(dispatcher, state), sid)
      end
    elseif message.op_code == OP_DUEL then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local reason
      local mine = state.duel_of[sid]
      if payload.action == "challenge" then
        local target = type(payload.name) == "string" and find_sid(state, nil, payload.name) or nil
        if not in_duel_area(state, sid) then
          reason = "not_in_duel_area"
        elseif not target or target == sid then
          reason = "no_such_player"
        elseif mine or state.duel_of[target] then
          reason = "busy"
        else
          state.duel_seq = state.duel_seq + 1
          local duel = Duel.new(sid, target, now, payload.rules)
          duel.id = state.duel_seq
          state.duel_of[sid], state.duel_of[target] = duel, duel
          send_duel(dispatcher, state, duel)
        end
      elseif payload.action == "referee" then
        -- A professor in a duelling room sets two students against each other (both still accept).
        local a = type(payload.a) == "string" and find_sid(state, nil, payload.a) or nil
        local b = type(payload.b) == "string" and find_sid(state, nil, payload.b) or nil
        local profile = state.profiles[sid]
        if not profile or not Profile.is_staff(profile.role) then
          reason = "not_staff"
        elseif not in_duel_area(state, sid) then
          reason = "not_in_duel_area"
        elseif not a or not b or a == b then
          reason = "no_such_player"
        elseif state.duel_of[a] or state.duel_of[b] then
          reason = "busy"
        else
          state.duel_seq = state.duel_seq + 1
          local duel = Duel.new(a, b, now, payload.rules)
          duel.id, duel.referee, duel.referee_name = state.duel_seq, sid, state.names[sid] or ""
          duel.accepted = {}
          state.duel_of[a], state.duel_of[b] = duel, duel
          send_duel(dispatcher, state, duel)
        end
      elseif payload.action == "accept" and mine and mine.referee and mine.state == "challenged" then
        -- A refereed duel starts when both duellists accept.
        if not in_duel_area(state, mine.a) or not in_duel_area(state, mine.b) then
          reason = "not_in_duel_area"
        else
          mine.accepted[sid] = true
          if mine.accepted[mine.a] and mine.accepted[mine.b] then Duel.accept(mine, now) end
          send_duel(dispatcher, state, mine)
        end
      elseif payload.action == "accept" then
        if not mine or mine.b ~= sid or mine.state ~= "challenged" then
          reason = "no_challenge"
        elseif not in_duel_area(state, sid) or not in_duel_area(state, mine.a) then
          reason = "not_in_duel_area"
        else
          Duel.accept(mine, now)
          send_duel(dispatcher, state, mine)
        end
      elseif payload.action == "decline" or payload.action == "forfeit" then
        if not mine then
          reason = "no_duel"
        else
          if mine.state == "challenged" then mine.state = "over"; mine.expired = true else Duel.forfeit(mine, sid) end
          end_duel(dispatcher, state, mine)
        end
      else
        reason = "bad_action"
      end
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = "duel", reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_DUEL_HIT then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local duel = state.duel_of[sid]
      local profile = state.profiles[sid]
      if duel and type(payload.sid) == "string" and type(payload.spell) == "string" and profile and Profile.knows(profile, payload.spell)
          and in_duel_area(state, sid) and in_duel_area(state, payload.sid) then
        local result = Duel.hit(duel, sid, payload.sid, now, duel.to_win or state.rules.duel_hits_to_win)
        if result then
          if duel.state == "over" then end_duel(dispatcher, state, duel) else send_duel(dispatcher, state, duel) end
        end
      end
    elseif message.op_code == OP_MODERATION then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local profile = state.profiles[sid]
      local action = payload.action
      local target = type(payload.name) == "string" and find_sid(state, nil, payload.name) or nil
      local target_uid = target and state.presences[target].user_id or (type(payload.name) == "string" and Chat.uid_for_name(payload.name)) or nil
      local reason
      local staff = profile and Profile.is_staff(profile.role)
      if not target_uid then
        reason = "no_such_player"
      elseif target_uid == message.sender.user_id then
        reason = "self"
      elseif action == "report" then
        Moderation.report({ from = message.sender.user_id, from_name = state.names[sid] or "", about = target_uid, about_name = payload.name,
                            reason = School.clean_text(payload.reason, state.rules.max_reason_bytes) })
      elseif action == "block" or action == "unblock" then
        local blocks = state.blocks[sid] or {}
        blocks[target_uid] = action == "block" and payload.name or nil
        state.blocks[sid] = blocks
        Moderation.save_blocks(message.sender.user_id, blocks)
      elseif action == "mute" or action == "kick" then
        if not staff then
          reason = "not_staff"
        elseif action == "mute" then
          local rec = Moderation.load(target_uid)
          rec.muted_until = now + math.max(1, math.min(1440, math.floor(tonumber(payload.minutes) or 10))) * 60
          rec.by = state.names[sid] or ""
          Moderation.save(target_uid, rec)
          if target then state.moderation[target] = rec end
        elseif target then
          dispatcher.match_kick({ state.presences[target] })
        else
          reason = "offline"
        end
      elseif action == "ban" then
        if not profile or profile.role ~= "admin" then
          reason = "not_admin"
        else
          local rec = Moderation.load(target_uid)
          rec.banned, rec.reason, rec.by = true, School.clean_text(payload.reason, state.rules.max_reason_bytes), state.names[sid] or ""
          Moderation.save(target_uid, rec)
          if target then dispatcher.match_kick({ state.presences[target] }) end
        end
      else
        reason = "bad_action"
      end
      nk.logger_info(string.format("moderation: %s %s %s (%s)", state.names[sid] or sid, tostring(action), tostring(payload.name), reason or "ok"))
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = "moderation", reason = reason or "", action = action }), { message.sender }, nil, true)
    elseif message.op_code == OP_APPEARANCE then
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      if ok and type(payload) == "table" and profile then
        payload.set = true
        profile.appearance = Profile.sanitize_appearance(payload)
        state.chars[sid] = profile.appearance.body
        Profile.write(message.sender.user_id, profile)
        send_profile(dispatcher, state, sid)
        local rest = others(state, sid)
        if #rest > 0 then
          dispatcher.broadcast_message(OP_ROSTER_UPDATE, nk.json_encode({ sid = sid, role = profile.role, house = profile.house, char = profile.appearance.body,
            look = { skin = profile.appearance.skin, robe = profile.appearance.robe } }), rest, nil, true)
        end
      end
    elseif message.op_code == OP_PRACTICAL then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local lesson = own_lesson(state, sid)
      local area = state.areas[sid] or ""
      local reason
      if not lesson then
        reason = "no_lesson"
      elseif payload.action == "start" then
        local hits = tonumber(payload.hits) or 3
        if type(payload.spell) ~= "string" or not Profile.SPELLS[payload.spell] then
          reason = "unknown_spell"
        elseif not School.teaches(lesson.subject, payload.spell) then
          reason = "not_in_subject"
        elseif hits ~= math.floor(hits) or hits < 1 or hits > MAX_PRACTICAL_HITS then
          reason = "bad_hits"
        else
          lesson.practical = { spell = payload.spell, hits = hits, grant = payload.grant == true, students = {} }
          send_practical(dispatcher, state, area)
          send_practical_progress(dispatcher, state, lesson)
        end
      elseif payload.action == "stop" then
        if not lesson.practical then
          reason = "no_practical"
        else
          lesson.practical = nil
          send_practical(dispatcher, state, area)
          send_practical_progress(dispatcher, state, lesson)
        end
      else
        reason = "bad_action"
      end
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = "practical", reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_BOARD or message.op_code == OP_QUIZ or message.op_code == OP_QUIZ_ANSWER then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local tool = message.op_code == OP_BOARD and "board" or message.op_code == OP_QUIZ and "quiz" or "answer"
      local reason
      if message.op_code == OP_QUIZ_ANSWER then
        local lesson = state.lessons[state.areas[sid] or ""]
        if not lesson or not lesson.quiz or lesson.quiz.id ~= payload.id then
          reason = "no_question"
        elseif lesson.by_sid == sid then
          reason = "own_question"
        else
          local _, why = Quiz.answer(lesson.quiz, sid, message.sender.user_id, state.names[sid] or "", payload.answer)
          reason = why
          if not why then
            send_quiz(dispatcher, state, state.areas[sid], sid)
            send_quiz_answers(dispatcher, state, lesson)
          end
        end
      else
        local lesson = own_lesson(state, sid)
        local area = state.areas[sid] or ""
        if not lesson then
          reason = "no_lesson"
        elseif message.op_code == OP_BOARD then
          lesson.board = Moderation.filter(School.clean_text(payload.text, state.rules.max_board_bytes), state.filter)
          send_lessons(dispatcher, state, nil)
        elseif payload.action == "ask" then
          if lesson.quiz and lesson.quiz.open then record_marks(lesson, Quiz.close(lesson.quiz), dispatcher, state) end
          state.quiz_seq = (state.quiz_seq or 0) + 1
          local quiz, why = Quiz.new_question(state.quiz_seq, payload)
          reason = why
          if quiz then
            lesson.quiz = quiz
            send_quiz(dispatcher, state, area)
            send_quiz_answers(dispatcher, state, lesson)
          end
        elseif payload.action == "close" then
          if not lesson.quiz or not lesson.quiz.open then
            reason = "no_question"
          else
            record_marks(lesson, Quiz.close(lesson.quiz), dispatcher, state)
            send_quiz(dispatcher, state, area)
            send_quiz_answers(dispatcher, state, lesson)
          end
        elseif payload.action == "mark" then
          local entry, why
          if lesson.quiz then
            entry, why = Quiz.mark(lesson.quiz, payload.sid, payload.right)
          else
            why = "no_question"
          end
          reason = why
          if entry then
            record_marks(lesson, { entry }, dispatcher, state)
            send_quiz(dispatcher, state, area, payload.sid)
            send_quiz_answers(dispatcher, state, lesson)
          end
        else
          reason = "bad_action"
        end
      end
      dispatcher.broadcast_message(OP_LESSON_TOOL_RESULT, nk.json_encode({ ok = reason == nil, tool = tool, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == P.OP_REQUEST then
      local ok, payload = pcall(nk.json_decode, message.data)
      payload = ok and type(payload) == "table" and payload or {}
      local done, reason, data = Features.request(feature_api(dispatcher, state), sid, payload)
      if state.presences[sid] then
        dispatcher.broadcast_message(P.OP_REPLY, nk.json_encode({ rid = tonumber(payload.rid) or 0, req = tostring(payload.req or ""), ok = done,
          reason = reason, data = data }), { message.sender }, nil, true)
      end
    elseif message.op_code == OP_PING then
      -- Echo the client's send time with the server's clock (ms since the epoch), so
      -- clients can agree on one time for scheduled movers (shifting stairs, clockwork).
      local ok, data = pcall(nk.json_decode, message.data)
      local t = (ok and type(data) == "table") and data.t or 0
      dispatcher.broadcast_message(OP_PING, nk.json_encode({ t = t, s = nk.time() }), { message.sender }, nil, false)
    end
  end
  return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
  return state
end

-- Signals come from world.lua's admin RPCs:
--   { op = "set_profile", user_id | name, role?, house?, forget_spells?, forget_mysteries?, reset_inventory?, reset_purse? }
--   { op = "grant_coins", user_id | name, amount, reason, by_name }
--   { op = "reset_world" }  every object to its default, world/house mysteries unsolved, self-study lessons closed
-- Answers { ok, sid, user_id, role, house } or { ok = false, reason }.
function M.match_signal(context, dispatcher, tick, state, data)
  local ok, request = pcall(nk.json_decode, data or "")
  if ok and type(request) == "table" and request.op == "reload_timetable" then
    state.timetable = Timetable.load()
    state.self_study = SelfStudy.load()
    send_timetable(dispatcher, state, nil)
    return state, nk.json_encode({ ok = true, slots = #state.timetable.slots })
  end
  if ok and type(request) == "table" and request.op == "award_cup" then
    award_cup(dispatcher, state, type(request.term) == "string" and request.term or "manual")
    return state, nk.json_encode({ ok = true, winner = state.cup.winner, totals = state.cup.totals })
  end
  if ok and type(request) == "table" and request.op == "grant_coins" then
    local sid = find_sid(state, request.user_id, request.name)
    if not sid then
      return state, nk.json_encode({ ok = false, reason = "offline" })
    end
    local uid = state.presences[sid].user_id
    local done, balance, why = Economy.change(uid, request.amount, { source = "admin", reason = request.reason, by_name = request.by_name })
    if done then
      send_wallet(dispatcher, state, sid, balance, request.amount, "admin", request.reason)
    end
    return state, nk.json_encode({ ok = done, reason = why, user_id = uid, coins = balance })
  end
  if ok and type(request) == "table" and request.op == "reset_world" then
    local driven = state.world.driven
    state.world = Objects.new_world()
    state.world.driven = driven
    state.mysteries = Mysteries.new_state()
    for area, lesson in pairs(state.lessons) do
      if lesson.kind == "self_study" then close_lesson(dispatcher, state, area, "world reset") end
    end
    dispatcher.broadcast_message(OP_WORLD_SNAPSHOT, nk.json_encode({ objects = state.world.objects }), nil, nil, true)
    return state, nk.json_encode({ ok = true })
  end
  if not ok or type(request) ~= "table" or request.op ~= "set_profile" then
    return state, nk.json_encode({ ok = false, reason = "bad_request" })
  end
  local sid = find_sid(state, request.user_id, request.name)
  if not sid then
    return state, nk.json_encode({ ok = false, reason = "offline" })
  end
  local profile = state.profiles[sid]
  if type(request.role) == "string" and Profile.ROLES[request.role] then
    profile.role = request.role
  end
  if type(request.year) == "number" and request.year >= 1 and request.year <= Profile.MAX_YEAR then
    profile.year = math.floor(request.year)
  end
  if type(request.house) == "number" and request.house >= 0 and request.house <= Profile.MAX_HOUSE then
    profile.house = math.floor(request.house)
  end
  if request.forget_spells == true then
    profile.spells = Profile.sanitize_spells(nil)
  end
  if request.forget_mysteries == true then
    profile.discoveries = {}
    local uid = state.presences[sid].user_id
    state.progress[uid] = {}
    save_progress(uid, state.progress[uid])
  end
  if request.reset_inventory == true then
    local inv = sanitize_inventory({ items = STARTING_ITEMS, held = "" })
    state.inventories[sid] = inv
    write_inventory(state.presences[sid].user_id, inv)
    dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(inv), { state.presences[sid] }, nil, true)
  end
  -- A flying licence given (true) or taken away (false) by an admin (features/flying.lua).
  if type(request.flying_licence) == "boolean" then
    local lic = { broom = request.flying_licence, by = "admin", at = nk.time() / 1000 }
    state.features.licences = state.features.licences or {}
    state.features.licences[sid] = lic
    Store.write("school", "licences", state.presences[sid].user_id, lic, true)
    dispatcher.broadcast_message(P.OP_PUSH, nk.json_encode({ kind = "licence", data = { broom = lic.broom } }), { state.presences[sid] }, nil, true)
  end
  if request.reset_purse == true then
    send_wallet(dispatcher, state, sid, Economy.reset(state.presences[sid].user_id, "admin"))
  end
  Profile.write(state.presences[sid].user_id, profile)
  send_profile(dispatcher, state, sid)
  broadcast_profile_change(dispatcher, state, sid)
  return state, nk.json_encode({ ok = true, sid = sid, user_id = state.presences[sid].user_id, role = profile.role, house = profile.house })
end

return M

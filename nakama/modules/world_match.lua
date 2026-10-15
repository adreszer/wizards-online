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
-- Movement is relayed but not yet validated.

local nk = require("nakama")
local Profile = require("character_profile")
local AREAS = require("world_areas")
local Objects = require("object_rules")
local Mysteries = require("mysteries")
local School = require("school")

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
local PROGRESS_COLLECTION, PROGRESS_KEY = "mysteries", "progress"
local TEXT_SECONDS = 6
local MAX_AREA_ID_BYTES = 48
local TICK_RATE = 15
-- Bytes, not characters: the client caps names at 16 characters, which with
-- UTF-8 diacritics (Polish etc.) can take more bytes.
local MAX_NAME_BYTES = 48

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
  return { sid = sid, uid = p.user_id, name = state.names[sid] or p.username, char = state.chars[sid] or "apprentice_m",
           held = inv and inv.held or "", role = profile and profile.role or "student", house = profile and profile.house or 0 }
end

local function send_profile(dispatcher, state, sid)
  local profile = state.profiles[sid]
  local p = state.presences[sid]
  if profile and p then
    dispatcher.broadcast_message(OP_PROFILE, nk.json_encode({ house = profile.house, role = profile.role, spells = profile.spells, discoveries = profile.discoveries }), { p }, nil, true)
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

-- A player may only report an area that exists and, for house areas, belongs to their house.
local function sanitize_area(id, profile)
  if type(id) ~= "string" or #id > MAX_AREA_ID_BYTES or not AREAS[id] then
    return ""
  end
  local house = AREAS[id].house or 0
  if house ~= 0 and (not profile or profile.house ~= house) then
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

local function send_text(dispatcher, state, sid, key)
  local p = state.presences[sid]
  if p then
    local text = Mysteries.text(state.engine, key, state.locales[sid])
    dispatcher.broadcast_message(OP_SERVER_TEXT, nk.json_encode({ text = text, seconds = TEXT_SECONDS }), { p }, nil, true)
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
    out[area] = { subject = lesson.subject, by = lesson.by_name, sid = lesson.by_sid }
  end
  return nk.json_encode({ lessons = out })
end

local function send_lessons(dispatcher, state, presences)
  dispatcher.broadcast_message(OP_LESSON_STATE, lessons_payload(state), presences, nil, true)
end

local function close_lesson(dispatcher, state, area, why)
  local lesson = state.lessons[area]
  if not lesson then return end
  state.lessons[area] = nil
  local count = 0
  for _ in pairs(lesson.attendance) do count = count + 1 end
  nk.logger_info(string.format("lesson %s in %s by %s closed (%s), %d attended, %d points", lesson.subject, area, lesson.by_name, why, count, lesson.points))
  send_lessons(dispatcher, state, nil)
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

local function broadcast_object(dispatcher, oid, value)
  dispatcher.broadcast_message(OP_OBJECT_STATE, nk.json_encode({ o = oid, s = value }), nil, nil, true)
end

local function run_actions(dispatcher, state, actions)
  local now = nk.time() / 1000
  for _, a in ipairs(actions) do
    local kind = a[1]
    if kind == "text" then
      send_text(dispatcher, state, a[2], a[3])
    elseif kind == "set_state" then
      if Objects.set(state.world, a[2], a[3], now) then
        broadcast_object(dispatcher, a[2], a[3] == nil and Objects.state_of(state.world, a[2]) or a[3])
      end
    elseif kind == "discovery" then
      local profile = state.profiles[a[2]]
      if profile and Profile.discover(profile, a[3]) then
        Profile.write(state.presences[a[2]].user_id, profile)
        send_profile(dispatcher, state, a[2])
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
  ev.sid, ev.uid, ev.house, ev.held = sid, p.user_id, profile.house, inv and inv.held or ""
  ev.area = ev.area or state.areas[sid]
  ev.now = nk.time() / 1000
  local ctx = {
    players_in = function(area) return players_in(state, area) end,
    player_progress = function(uid) return state.progress[uid] end,
    progress_changed = function(uid) save_progress(uid, state.progress[uid]) end,
  }
  run_actions(dispatcher, state, Mysteries.on_event(state.engine, state.mysteries, ev, ctx))
end

function M.match_init(context, params)
  local state = { presences = {}, names = {}, chars = {}, inventories = {}, profiles = {}, areas = {}, locales = {},
                  progress = {}, world = Objects.new_world(), mysteries = Mysteries.new_state(), engine = Mysteries.load(),
                  lessons = {}, rules = School.load_rules(), totals = School.load_totals(), points_at = {} }
  state.world.driven = state.engine.driven
  return state, TICK_RATE, "world"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  state.names[presence.session_id] = sanitize_name(metadata and metadata.display_name, presence.username)
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
    state.areas[p.session_id] = ""
    state.progress[p.user_id] = load_progress(p.user_id)
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
      state.presences[sid] = nil
      state.names[sid] = nil
      state.chars[sid] = nil
      state.inventories[sid] = nil
      state.profiles[sid] = nil
      state.areas[sid] = nil
      state.locales[sid] = nil
      state.points_at[sid] = nil
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
  for _, change in ipairs(Objects.tick(state.world, now)) do
    broadcast_object(dispatcher, change[1], change[2])
  end
  if tick % TICK_RATE == 0 then
    for area, lesson in pairs(state.lessons) do
      if now - lesson.opened_at > state.rules.session_max_minutes * 60 then
        close_lesson(dispatcher, state, area, "time")
      end
    end
    local occupied = function(area) return #players_in(state, area) > 0 end
    run_actions(dispatcher, state, Mysteries.tick(state.engine, state.mysteries, nk.time() / 1000, occupied))
  end
  for _, message in ipairs(messages) do
    local sid = message.sender.session_id
    if message.op_code == OP_STATE then
      local rest = others(state, sid)
      if #rest > 0 then
        dispatcher.broadcast_message(OP_STATE, message.data, rest, message.sender, false)
      end
    elseif message.op_code == OP_SPELL_CAST then
      -- Only spells the character actually knows leave the server.
      local ok, payload = pcall(nk.json_decode, message.data)
      local profile = state.profiles[sid]
      if ok and type(payload) == "table" and type(payload.id) == "string" and profile and Profile.knows(profile, payload.id) then
        local rest = others(state, sid)
        if #rest > 0 then
          dispatcher.broadcast_message(OP_SPELL_CAST, message.data, rest, message.sender, true)
        end
      end
    elseif message.op_code == OP_AREA then
      local ok, payload = pcall(nk.json_decode, message.data)
      if ok and type(payload) == "table" then
        local area = sanitize_area(payload.id, state.profiles[sid])
        local changed = area ~= state.areas[sid]
        state.areas[sid] = area
        if changed and area ~= "" then
          local lesson = state.lessons[area]
          if lesson and lesson.by_sid ~= sid then
            lesson.attendance[message.sender.user_id] = state.names[sid] or ""
          end
          feed_mysteries(dispatcher, state, sid, { event = "enter", area = area })
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
        local ctx = { sid = sid, area = state.areas[sid], knows = function(id) return Profile.knows(profile, id) end }
        local ev, reason = Objects.validate(state.world, ctx, payload, now)
        if ev then
          local value = Objects.apply(state.world, ev, now)
          if value ~= nil then
            broadcast_object(dispatcher, ev.oid, value)
          end
          feed_mysteries(dispatcher, state, sid, { event = ev.event, object = ev.oid, effect_type = ev.effect_type, state = Objects.state_of(state.world, ev.oid) })
        else
          nk.logger_debug(string.format("world event from %s refused: %s", sid, tostring(reason)))
        end
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
        if not subject then
          reason = "not_in_classroom"
        elseif state.lessons[area] then
          reason = "already_open"
        else
          state.lessons[area] = { subject = subject, by_sid = sid, by_name = state.names[sid] or "", opened_at = now, attendance = {}, points = 0 }
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
      if not profile or not Profile.is_staff(profile.role) then
        reason = "not_staff"
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
      elseif not award_house_points(dispatcher, state, house, delta, text, sid, "professor", lesson and lesson.subject or "") then
        reason = "storage"
      else
        state.points_at[sid] = now
        if lesson then lesson.points = lesson.points + math.abs(delta) end
      end
      dispatcher.broadcast_message(OP_HOUSE_POINTS_RESULT, nk.json_encode({ ok = reason == nil, house = house, delta = delta, reason = reason or "" }), { message.sender }, nil, true)
    elseif message.op_code == OP_LECTURE then
      local ok, payload = pcall(nk.json_decode, message.data)
      local text = School.clean_text(ok and type(payload) == "table" and payload.text or nil, state.rules.max_lecture_bytes)
      if text ~= "" and own_lesson(state, sid) then
        local listeners = {}
        for _, pl in ipairs(players_in(state, state.areas[sid])) do
          table.insert(listeners, state.presences[pl.sid])
        end
        dispatcher.broadcast_message(OP_LECTURE_TEXT, nk.json_encode({ by = state.names[sid] or "", text = text }), listeners, nil, true)
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
--   { op = "set_profile", user_id | name, role?, house?, forget_spells?, forget_mysteries? }
--   { op = "reset_world" }  every object to its default, world/house mysteries unsolved
-- Answers { ok, sid, user_id, role, house } or { ok = false, reason }.
function M.match_signal(context, dispatcher, tick, state, data)
  local ok, request = pcall(nk.json_decode, data or "")
  if ok and type(request) == "table" and request.op == "reset_world" then
    local driven = state.world.driven
    state.world = Objects.new_world()
    state.world.driven = driven
    state.mysteries = Mysteries.new_state()
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
  Profile.write(state.presences[sid].user_id, profile)
  send_profile(dispatcher, state, sid)
  broadcast_profile_change(dispatcher, state, sid)
  return state, nk.json_encode({ ok = true, sid = sid, user_id = state.presences[sid].user_id, role = profile.role, house = profile.house })
end

return M

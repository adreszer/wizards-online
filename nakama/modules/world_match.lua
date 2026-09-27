-- Authoritative match handler for the shared world.
-- Op codes mirror res://multiplayer/network_protocol.gd:
--   1  STATE        client -> others (movement snapshot)
--   2  SPELL_CAST   client -> others
--   3  HELD_ITEM    client -> server (validated) -> others  {id}
--   4  AREA         client -> server  {id}  the area the player is in ("" = none)
--   5  GRANT_SPELL  client (professor) -> server  {sid, id}
--   6  SPELLBOOK    client -> server  {slots, equipped}  hotbar layout
--   7  STUDY_TOME   client -> server  {id}  practice tome (interim, until lessons only)
--   8  SORT         client -> server  {answers = {1..4 x4}}  sorting ceremony
--   10 ROSTER       server -> joining client
--   11 PLAYER_JOINED server -> others
--   12 PLAYER_LEFT  server -> others
--   13 INVENTORY    server -> joining client  {items = {{id, count}}, held}
--   14 PROFILE      server -> same client  {house, role, spells}
--   15 ROSTER_UPDATE server -> others  {sid, role, house}
--   16 SPELL_GRANTED server -> target  {id, by}
--   17 GRANT_RESULT server -> professor  {ok, sid, id, reason}
--   18 SORT_RESULT  server -> same client  {ok, house, reason}
--   20 PING         client -> same client (latency probe)
-- The server owns identity (display names come from join metadata and are
-- sanitized here), inventories (storage "inventory"/"items") and character
-- profiles (storage "character"/"profile": house, role, spellbook; see
-- character_profile.lua). A held-item change is accepted only for an owned,
-- holdable item; a spell cast only for a known spell; a spell grant only from
-- a professor/admin standing in the same classroom as the target (areas come
-- from world_areas.lua, generated with the castle). Movement is relayed but
-- not yet validated.

local nk = require("nakama")
local Profile = require("character_profile")
local AREAS = require("world_areas")

local OP_STATE, OP_SPELL_CAST, OP_HELD_ITEM, OP_AREA, OP_GRANT_SPELL, OP_SPELLBOOK, OP_STUDY_TOME, OP_SORT = 1, 2, 3, 4, 5, 6, 7, 8
local OP_ROSTER, OP_PLAYER_JOINED, OP_PLAYER_LEFT, OP_INVENTORY = 10, 11, 12, 13
local OP_PROFILE, OP_ROSTER_UPDATE, OP_SPELL_GRANTED, OP_GRANT_RESULT, OP_SORT_RESULT = 14, 15, 16, 17, 18
local OP_PING = 20
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
  -- Mirrors GameSession.sanitize_display_name: ASCII letters/digits, space,
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

local CHARACTERS = { apprentice_m = true, apprentice_f = true, placeholder = true }

local function sanitize_character(id)
  if type(id) == "string" and CHARACTERS[id] then
    return id
  end
  return "apprentice_m"
end

-- Item catalogue; mirrors res://resources/items/*.tres (ItemRegistry).
local ITEMS = { torch = { holdable = true, max_stack = 1 } }
-- What a brand-new character owns.
local STARTING_ITEMS = { { id = "torch", count = 1 } }
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
    dispatcher.broadcast_message(OP_PROFILE, nk.json_encode({ house = profile.house, role = profile.role, spells = profile.spells }), { p }, nil, true)
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

function M.match_init(context, params)
  local state = { presences = {}, names = {}, chars = {}, inventories = {}, profiles = {}, areas = {} }
  return state, TICK_RATE, "world"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  state.names[presence.session_id] = sanitize_name(metadata and metadata.display_name, presence.username)
  state.chars[presence.session_id] = sanitize_character(metadata and metadata.character)
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
  end
  for _, p in ipairs(presences) do
    local roster = {}
    for sid, _ in pairs(state.presences) do
      table.insert(roster, entry_for(state, sid))
    end
    dispatcher.broadcast_message(OP_ROSTER, nk.json_encode({ players = roster, self_sid = p.session_id }), { p }, nil, true)
    dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(state.inventories[p.session_id]), { p }, nil, true)
    send_profile(dispatcher, state, p.session_id)
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
      local rest = others(state, sid)
      if #rest > 0 then
        dispatcher.broadcast_message(OP_PLAYER_LEFT, nk.json_encode(entry), rest, nil, true)
      end
    end
  end
  return state
end

function M.match_loop(context, dispatcher, tick, state, messages)
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
        state.areas[sid] = sanitize_area(payload.id, state.profiles[sid])
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
      -- Interim: practice tomes teach any registered spell. Lessons will replace this.
      local ok, payload = pcall(nk.json_decode, message.data)
      local id = ok and type(payload) == "table" and type(payload.id) == "string" and payload.id or ""
      if Profile.SPELLS[id] then
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
    elseif message.op_code == OP_PING then
      dispatcher.broadcast_message(OP_PING, message.data, { message.sender }, nil, false)
    end
  end
  return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
  return state
end

-- Signals come from world.lua's admin_set_profile RPC:
--   { op = "set_profile", user_id | name, role?, house? }
-- Answers { ok, sid, user_id, role, house } or { ok = false, reason }.
function M.match_signal(context, dispatcher, tick, state, data)
  local ok, request = pcall(nk.json_decode, data or "")
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
  Profile.write(state.presences[sid].user_id, profile)
  send_profile(dispatcher, state, sid)
  broadcast_profile_change(dispatcher, state, sid)
  return state, nk.json_encode({ ok = true, sid = sid, user_id = state.presences[sid].user_id, role = profile.role, house = profile.house })
end

return M

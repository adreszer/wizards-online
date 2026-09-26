-- Authoritative match handler for the shared world.
-- Op codes mirror res://multiplayer/network_protocol.gd:
--   1  STATE        client -> others (movement snapshot)
--   2  SPELL_CAST   client -> others
--   3  HELD_ITEM    client -> server (validated) -> others  {id}
--   10 ROSTER       server -> joining client
--   11 PLAYER_JOINED server -> others
--   12 PLAYER_LEFT  server -> others
--   13 INVENTORY    server -> joining client  {items = {{id, count}}, held}
--   20 PING         client -> same client (latency probe)
-- The server owns identity (display names come from join metadata and are
-- sanitized here) and inventories (Nakama storage, collection "inventory",
-- key "items", per user: a new character gets the starting kit). A held-item
-- change is accepted only for an owned, holdable item. Movement is relayed
-- but not yet validated. This is the place where authority can be tightened
-- later (rate limits, sanity checks, duel resolution).

local nk = require("nakama")

local OP_STATE, OP_SPELL_CAST, OP_HELD_ITEM = 1, 2, 3
local OP_ROSTER, OP_PLAYER_JOINED, OP_PLAYER_LEFT, OP_INVENTORY = 10, 11, 12, 13
local OP_PING = 20
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

local function entry_for(state, sid)
  local p = state.presences[sid]
  local inv = state.inventories[sid]
  return { sid = sid, uid = p.user_id, name = state.names[sid] or p.username, char = state.chars[sid] or "apprentice_m", held = inv and inv.held or "" }
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

function M.match_init(context, params)
  local state = { presences = {}, names = {}, chars = {}, inventories = {} }
  return state, TICK_RATE, "world"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  state.names[presence.session_id] = sanitize_name(metadata and metadata.display_name, presence.username)
  state.chars[presence.session_id] = sanitize_character(metadata and metadata.character)
  return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
  for _, p in ipairs(presences) do
    state.presences[p.session_id] = p
    state.inventories[p.session_id] = load_inventory(p.user_id)
  end
  for _, p in ipairs(presences) do
    local roster = {}
    for sid, _ in pairs(state.presences) do
      table.insert(roster, entry_for(state, sid))
    end
    dispatcher.broadcast_message(OP_ROSTER, nk.json_encode({ players = roster, self_sid = p.session_id }), { p }, nil, true)
    dispatcher.broadcast_message(OP_INVENTORY, nk.json_encode(state.inventories[p.session_id]), { p }, nil, true)
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
      local rest = others(state, sid)
      if #rest > 0 then
        dispatcher.broadcast_message(OP_SPELL_CAST, message.data, rest, message.sender, true)
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

function M.match_signal(context, dispatcher, tick, state, data)
  return state, data
end

return M

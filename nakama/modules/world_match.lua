-- Authoritative match handler for the shared world.
-- Op codes mirror res://multiplayer/network_protocol.gd:
--   1  STATE        client -> others (movement snapshot)
--   2  SPELL_CAST   client -> others
--   10 ROSTER       server -> joining client
--   11 PLAYER_JOINED server -> others
--   12 PLAYER_LEFT  server -> others
--   20 PING         client -> same client (latency probe)
-- The server owns identity (display names come from join metadata and are
-- sanitized here); movement is relayed but not yet validated. This is the
-- place where authority can be tightened later (rate limits, sanity checks,
-- duel resolution).

local nk = require("nakama")

local OP_STATE, OP_SPELL_CAST = 1, 2
local OP_ROSTER, OP_PLAYER_JOINED, OP_PLAYER_LEFT = 10, 11, 12
local OP_PING = 20
local TICK_RATE = 15
local MAX_NAME_LENGTH = 16

local M = {}

local function sanitize_name(name, fallback)
  if type(name) ~= "string" then
    return fallback
  end
  name = name:gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, MAX_NAME_LENGTH)
  if #name == 0 then
    return fallback
  end
  return name
end

local function entry_for(state, sid)
  local p = state.presences[sid]
  return { sid = sid, uid = p.user_id, name = state.names[sid] or p.username }
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
  local state = { presences = {}, names = {} }
  return state, TICK_RATE, "world"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  state.names[presence.session_id] = sanitize_name(metadata and metadata.display_name, presence.username)
  return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
  for _, p in ipairs(presences) do
    state.presences[p.session_id] = p
  end
  for _, p in ipairs(presences) do
    local roster = {}
    for sid, _ in pairs(state.presences) do
      table.insert(roster, entry_for(state, sid))
    end
    dispatcher.broadcast_message(OP_ROSTER, nk.json_encode({ players = roster, self_sid = p.session_id }), { p }, nil, true)
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

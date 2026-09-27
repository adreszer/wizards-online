-- Server module: shared world discovery + chat validation.
-- Loaded once per Lua VM, so it keeps no module-level state; the world match
-- is discovered by label through match_list and created on demand.

local nk = require("nakama")
local Profile = require("character_profile")

local WORLD_LABEL = "world"
local MAX_CHAT_LENGTH = 200

local function find_or_create_world()
  local matches = nk.match_list(1, true, WORLD_LABEL, 0, 200, "")
  if matches and #matches > 0 then
    return matches[1].match_id
  end
  return nk.match_create("world_match", {})
end

-- RPC "join_world": returns the id of the shared world match.
local function rpc_join_world(context, payload)
  local match_id = find_or_create_world()
  return nk.json_encode({ match_id = match_id })
end
nk.register_rpc(rpc_join_world, "join_world")

-- Reject oversized or empty chat messages before they are stored/broadcast.
local function before_channel_message_send(context, payload)
  local content = payload.channel_message_send and payload.channel_message_send.content
  if not content then
    return nil
  end
  local ok, decoded = pcall(nk.json_decode, content)
  if not ok or type(decoded) ~= "table" or type(decoded.text) ~= "string" then
    return nil
  end
  local text = decoded.text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text == 0 or #text > MAX_CHAT_LENGTH then
    return nil
  end
  return payload
end
nk.register_rt_before(before_channel_message_send, "ChannelMessageSend")

-- RPC "admin_set_profile": {user_id | name, role?, house?, forget_spells?} → changes a
-- character's role and/or house (and can wipe its spellbook for testing). Allowed for server-to-server calls (HTTP key,
-- no session), for users listed in ADMIN_USER_IDS and for admins by profile.
-- The change is applied by the world match (so an online player is updated
-- live and by display name); an offline target is written to storage here.
local function rpc_admin_set_profile(context, payload)
  if context.user_id and context.user_id ~= "" then
    local admins = Profile.env_admins(context.env)
    if not admins[context.user_id] then
      local caller = Profile.load(context.user_id)
      if caller.role ~= "admin" then
        error({ "only admins may change roles", 7 })  -- 7 = PERMISSION_DENIED
      end
    end
  end
  local ok, data = pcall(nk.json_decode, payload or "")
  if not ok or type(data) ~= "table" then
    error({ "invalid payload", 3 })  -- 3 = INVALID_ARGUMENT
  end
  if data.role ~= nil and not Profile.ROLES[data.role] then
    error({ "unknown role", 3 })
  end
  if data.house ~= nil and (type(data.house) ~= "number" or data.house < 0 or data.house > Profile.MAX_HOUSE) then
    error({ "house must be 0.." .. Profile.MAX_HOUSE, 3 })
  end
  local request = { op = "set_profile", user_id = data.user_id, name = data.name, role = data.role, house = data.house, forget_spells = data.forget_spells == true }
  local match_id = find_or_create_world()
  local result = nk.match_signal(match_id, nk.json_encode(request))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" then
    error({ "match did not answer", 13 })
  end
  if not decoded.ok and decoded.reason == "offline" and type(data.user_id) == "string" and data.user_id ~= "" then
    local ok_users, users = pcall(nk.users_get_id, { data.user_id })
    if not ok_users or not users or #users == 0 then
      error({ "no such user", 5 })
    end
    local profile = Profile.load(data.user_id)
    if data.role then profile.role = data.role end
    if data.house then profile.house = data.house end
    if data.forget_spells == true then profile.spells = Profile.sanitize_spells(nil) end
    Profile.write(data.user_id, profile)
    decoded = { ok = true, user_id = data.user_id, role = profile.role, house = profile.house, offline = true }
  end
  if not decoded.ok then
    error({ decoded.reason or "failed", 5 })  -- 5 = NOT_FOUND
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_set_profile, "admin_set_profile")

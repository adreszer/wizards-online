-- Server module: shared world discovery + chat validation.
-- Loaded once per Lua VM, so it keeps no module-level state; the world match
-- is discovered by label through match_list and created on demand.

local nk = require("nakama")
local Profile = require("character_profile")
local P = require("generated.protocol")
local School = require("school")

local WORLD_LABEL = "world"
local MAX_CHAT_LENGTH = P.MAX_CHAT_LENGTH

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
nk.register_rpc(rpc_join_world, P.RPC_JOIN_WORLD)

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

-- RPC "admin_set_profile": {user_id | name, role?, house?, forget_spells?, forget_mysteries?, reset_inventory?} → changes a
-- character's role and/or house (and can wipe its spellbook, discoveries and mystery progress for testing). Allowed for server-to-server calls (HTTP key,
-- no session), for users listed in ADMIN_USER_IDS and for admins by profile.
-- The change is applied by the world match (so an online player is updated
-- live and by display name); an offline target is written to storage here.
local function require_admin(context)
  if context.user_id and context.user_id ~= "" then
    local admins = Profile.env_admins(context.env)
    if not admins[context.user_id] then
      local caller = Profile.load(context.user_id)
      if caller.role ~= "admin" then
        error({ "only admins may do this", 7 })  -- 7 = PERMISSION_DENIED
      end
    end
  end
end

local function rpc_admin_set_profile(context, payload)
  require_admin(context)
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
  local request = { op = "set_profile", user_id = data.user_id, name = data.name, role = data.role, house = data.house, forget_spells = data.forget_spells == true, forget_mysteries = data.forget_mysteries == true, reset_inventory = data.reset_inventory == true }
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
    if data.forget_mysteries == true then
      profile.discoveries = {}
      pcall(nk.storage_delete, { { collection = "mysteries", key = "progress", user_id = data.user_id } })
    end
    if data.reset_inventory == true then
      -- The next join recreates the starting kit.
      pcall(nk.storage_delete, { { collection = "inventory", key = "items", user_id = data.user_id } })
    end
    Profile.write(data.user_id, profile)
    decoded = { ok = true, user_id = data.user_id, role = profile.role, house = profile.house, offline = true }
  end
  if not decoded.ok then
    error({ decoded.reason or "failed", 5 })  -- 5 = NOT_FOUND
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_set_profile, P.RPC_ADMIN_SET_PROFILE)

-- RPC "admin_reset_world": {} → every world object back to its default and every
-- world/house mystery unsolved (dev tooling and tests). Admins or the HTTP key.
local function rpc_admin_reset_world(context, payload)
  require_admin(context)
  local result = nk.match_signal(find_or_create_world(), nk.json_encode({ op = "reset_world" }))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" or not decoded.ok then
    error({ "match did not answer", 13 })
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_reset_world, P.RPC_ADMIN_RESET_WORLD)

-- RPC "house_points_ledger": {limit?} → {records, totals}: the stored record of
-- every house points change, newest first (admins or the HTTP key).
local function rpc_house_points_ledger(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  local limit = ok and type(data) == "table" and tonumber(data.limit) or 50
  return nk.json_encode({ records = School.list_ledger(math.max(1, math.min(500, math.floor(limit)))), totals = School.load_totals() })
end
nk.register_rpc(rpc_house_points_ledger, P.RPC_HOUSE_POINTS_LEDGER)

local function require_staff(context)
  if not context.user_id or context.user_id == "" then
    error({ "lesson plans belong to a professor's session", 3 })
  end
  if not Profile.env_admins(context.env)[context.user_id] and not Profile.is_staff(Profile.load(context.user_id).role) then
    error({ "only professors keep lesson plans", 7 })
  end
end

-- RPC "lesson_plan_save": {id?, title, lines} → {id}. Plans are stored per
-- professor (owner-readable, written only here), never in the game build.
local function rpc_lesson_plan_save(context, payload)
  require_staff(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  local id, err = School.save_plan(context.user_id, ok and data or nil, School.load_rules().max_lecture_bytes)
  if not id then
    error({ err, 3 })
  end
  return nk.json_encode({ id = id })
end
nk.register_rpc(rpc_lesson_plan_save, P.RPC_LESSON_PLAN_SAVE)

-- RPC "lesson_plan_list": {} → {plans = {{id, title, lines}}} for the caller.
local function rpc_lesson_plan_list(context, payload)
  require_staff(context)
  return nk.json_encode({ plans = School.list_plans(context.user_id) })
end
nk.register_rpc(rpc_lesson_plan_list, P.RPC_LESSON_PLAN_LIST)

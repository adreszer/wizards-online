-- Server module: shared world discovery + chat validation.
-- Loaded once per Lua VM, so it keeps no module-level state; the world match
-- is discovered by label through match_list and created on demand.

local nk = require("nakama")

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

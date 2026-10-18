-- Portraits as messengers: a student asks the portraits to carry a short message to
-- another student (/portrait name text); the next portrait the recipient walks past
-- delivers it aloud, then forgets it. At most MAX_WAITING messages wait per recipient;
-- the word filter applies. Works for absent recipients too (by their last name).
--
-- Storage: portrait_mail/inbox per recipient (server-only): { messages = { { id, from, text, at } } }
-- Push "portrait_mail": { messages } to the recipient.

local Store = require("store")
local School = require("school")
local Moderation = require("moderation")
local Chat = require("chat")

local M = { name = "portraits" }

M.COLLECTION, M.KEY = "portrait_mail", "inbox"
M.MAX_WAITING = 5
M.MAX_TEXT_BYTES = 200
M.SEND_GAP = 20

local function inbox(uid)
  local r = Store.read(M.COLLECTION, M.KEY, uid) or {}
  r.messages = type(r.messages) == "table" and r.messages or {}
  return r
end

function M.join(api, sid)
  local r = inbox(api.uid(sid))
  if #r.messages > 0 then api.push("portrait_mail", { messages = r.messages }, sid) end
end

M.requests = {}

-- {name, text}
M.requests.portrait_message = function(api, sid, payload)
  local f = api.state.features
  f.portrait_at = f.portrait_at or {}
  if f.portrait_at[sid] and api.now - f.portrait_at[sid] < M.SEND_GAP then return nil, "too_fast" end
  local to_sid = type(payload.name) == "string" and api.find(payload.name) or nil
  local uid = to_sid and api.uid(to_sid) or (type(payload.name) == "string" and Chat.uid_for_name(payload.name)) or nil
  if not uid then return nil, "no_such_player" end
  local text = School.clean_text(payload.text, M.MAX_TEXT_BYTES)
  if text == "" then return nil, "empty" end
  local r = inbox(uid)
  if #r.messages >= M.MAX_WAITING then return nil, "too_many" end
  f.portrait_at[sid] = api.now
  table.insert(r.messages, { id = api.nk.uuid_v4(), from = api.name(sid), text = Moderation.filter(text, api.state.filter or {}), at = api.now })
  Store.write(M.COLLECTION, M.KEY, uid, r)
  if to_sid then api.push("portrait_mail", { messages = r.messages }, to_sid) end
  return {}
end

-- {id}: a portrait delivered this message.
M.requests.portrait_read = function(api, sid, payload)
  local uid = api.uid(sid)
  local r = inbox(uid)
  local keep = {}
  for _, m in ipairs(r.messages) do
    if m.id ~= payload.id then table.insert(keep, m) end
  end
  r.messages = keep
  Store.write(M.COLLECTION, M.KEY, uid, r)
  api.push("portrait_mail", { messages = keep }, sid)
  return {}
end

return M

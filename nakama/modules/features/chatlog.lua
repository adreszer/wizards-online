-- Chat logs for moderation: every public line and direct message is kept for
-- `chat_log_days` (school rules, default 7) and then deleted; admins read them by day and
-- name (admin panel, admin_chat_log). Lines go to storage in batches.
--
-- Storage: chat_log/<day number> (system): { lines = { { at, name, mode, text, area, to? } } }

local Store = require("store")

local M = { name = "chatlog" }

M.COLLECTION = "chat_log"
M.FLUSH_SECONDS = 20
M.MAX_LINES_PER_DAY = 20000

local function buffer(api)
  api.state.features.chat_buffer = api.state.features.chat_buffer or {}
  return api.state.features.chat_buffer
end

-- The match calls this for every delivered line.
function M.chat_line(api, sid, mode, text, to)
  table.insert(buffer(api), { at = api.now, name = api.name(sid), mode = mode, text = text, area = api.area(sid), to = to })
end

local function flush(api)
  local b = buffer(api)
  if #b == 0 then return end
  local by_day = {}
  for _, l in ipairs(b) do
    local day = tostring(math.floor(l.at / 86400))
    by_day[day] = by_day[day] or {}
    table.insert(by_day[day], l)
  end
  for day, lines in pairs(by_day) do
    local rec = Store.read(M.COLLECTION, day, nil) or { lines = {} }
    for _, l in ipairs(lines) do
      if #rec.lines < M.MAX_LINES_PER_DAY then table.insert(rec.lines, l) end
    end
    Store.write(M.COLLECTION, day, nil, rec)
  end
  api.state.features.chat_buffer = {}
end

function M.tick(api, now)
  local f = api.state.features
  if not f.chat_flushed or now - f.chat_flushed >= M.FLUSH_SECONDS then
    f.chat_flushed = now
    flush(api)
  end
  if not f.chat_purged or now - f.chat_purged >= 3600 then
    f.chat_purged = now
    local keep_from = math.floor(now / 86400) - (tonumber(api.rules.chat_log_days) or 7)
    for _, o in ipairs(Store.list(M.COLLECTION, nil, 400)) do
      if tonumber(o.key) and tonumber(o.key) < keep_from then Store.delete(M.COLLECTION, o.key, nil) end
    end
  end
end

M.requests = {}

-- Admins: {name?, days_ago? (0 = today), limit?} → { lines } newest first.
M.requests.admin_chat_log = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  flush(api)
  local day = math.floor(api.now / 86400) - math.max(0, math.floor(tonumber(payload.days_ago) or 0))
  local rec = Store.read(M.COLLECTION, tostring(day), nil) or { lines = {} }
  local who = type(payload.name) == "string" and payload.name ~= "" and payload.name or nil
  local limit = math.max(1, math.min(500, math.floor(tonumber(payload.limit) or 100)))
  local out = {}
  for i = #rec.lines, 1, -1 do
    local l = rec.lines[i]
    if not who or l.name == who or l.to == who then
      table.insert(out, l)
      if #out >= limit then break end
    end
  end
  return { day = day, lines = out }
end

return M

-- Analytics without tracking people: per day, how often each area is walked into, how
-- many distinct students came, and how often each feature request is made and refused.
-- Counts only, never who; kept like chat logs for `analytics_days` (rules, default 60).
-- Admins read a day (admin panel or admin_analytics) to see where people go, where they
-- get lost and which systems they use.
--
-- Storage: analytics/<day number> (system): { areas = { [area] = n }, requests = { [kind] = n }, refused = { [kind] = n }, students = n }

local Store = require("store")

local M = { name = "analytics" }

M.COLLECTION = "analytics"
M.FLUSH_SECONDS = 60

local function today(api) return math.floor(api.now / 86400) end

local function day(api)
  local f = api.state.features
  local d = today(api)
  if not f.analytics or f.analytics.day ~= d then
    if f.analytics then M.flush(api) end
    local stored = Store.read(M.COLLECTION, tostring(d), nil) or {}
    f.analytics = { day = d, areas = stored.areas or {}, requests = stored.requests or {}, refused = stored.refused or {},
                    students = tonumber(stored.students) or 0, seen = {} }
  end
  return f.analytics
end

function M.flush(api)
  local a = api.state.features.analytics
  if not a then return end
  Store.write(M.COLLECTION, tostring(a.day), nil, { areas = a.areas, requests = a.requests, refused = a.refused, students = a.students })
end

function M.join(api, sid)
  local a = day(api)
  -- Distinct students per day, counted by an anonymous in-memory mark (never stored).
  local uid = api.uid(sid)
  if uid and not a.seen[uid] then
    a.seen[uid] = true
    a.students = a.students + 1
  end
end

function M.area(api, sid, area)
  if area == "" then return end
  local a = day(api)
  a.areas[area] = (a.areas[area] or 0) + 1
end

function M.requested(api, sid, kind, ok)
  local a = day(api)
  a.requests[kind] = (a.requests[kind] or 0) + 1
  if not ok then a.refused[kind] = (a.refused[kind] or 0) + 1 end
end

function M.tick(api, now)
  local f = api.state.features
  if not f.analytics_flushed or now - f.analytics_flushed >= M.FLUSH_SECONDS then
    f.analytics_flushed = now
    day(api)
    M.flush(api)
  end
  if not f.analytics_purged or now - f.analytics_purged >= 6 * 3600 then
    f.analytics_purged = now
    local keep_from = today(api) - (tonumber(api.rules.analytics_days) or 60)
    for _, o in ipairs(Store.list(M.COLLECTION, nil, 400)) do
      if tonumber(o.key) and tonumber(o.key) < keep_from then Store.delete(M.COLLECTION, o.key, nil) end
    end
  end
end

M.requests = {}

-- Admins: {days_ago?} → that day's counts.
M.requests.admin_analytics = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  M.flush(api)
  local d = today(api) - math.max(0, math.floor(tonumber(payload.days_ago) or 0))
  local rec = Store.read(M.COLLECTION, tostring(d), nil) or {}
  return { day = d, areas = rec.areas or {}, requests = rec.requests or {}, refused = rec.refused or {}, students = rec.students or 0 }
end

return M

-- The school's events: admins (and professors, for their own lessons' extras) schedule
-- one-off events as data (a feast, an exam in the great hall, a community mystery night,
-- duelling hours, the winter ball, a match on the pitch) with a start, a length and a
-- place; the server announces each when it starts and everyone's calendar lists them
-- with club meetings. The calendar's fixed parts (lessons, meals, term dates) come from
-- the timetable the client already has.
--
-- Storage: school/events (system): { list = { { id, kind, title, at, minutes, area, by } } }
-- Push "events": { events = [...], clubs = [club bookings] } to everyone.

local Store = require("store")
local School = require("school")
local Clubs = require("features.clubs")

local M = { name = "events" }

M.COLLECTION, M.KEY = "school", "events"
-- A "ball" dresses the great hall while it runs (Seasons on the client).
M.KINDS = { feast = true, exam = true, mystery = true, duelling = true, ball = true, match = true, meeting = true, other = true }
M.MAX_EVENTS = 40
M.MAX_TITLE_BYTES = 80

local function events(api)
  local f = api.state.features
  if not f.events then
    local e = Store.read(M.COLLECTION, M.KEY, nil) or {}
    f.events = type(e.list) == "table" and e.list or {}
  end
  return f.events
end

local function upcoming(api)
  local out = {}
  for _, e in ipairs(events(api)) do
    if e.at + e.minutes * 60 > api.now then table.insert(out, e) end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

local function view(api) return { events = upcoming(api), clubs = Clubs.bookings(api) } end

local function save(api)
  local keep = upcoming(api)
  api.state.features.events = keep
  Store.write(M.COLLECTION, M.KEY, nil, { list = keep })
  api.push("events", view(api), nil)
end

-- Whether an event of `kind` runs now (other modules: duelling hours, the ball's decor).
function M.running(api, kind)
  for _, e in ipairs(events(api)) do
    if e.kind == kind and e.at <= api.now and api.now < e.at + e.minutes * 60 then return e end
  end
  return nil
end

function M.join(api, sid) api.push("events", view(api), sid) end

function M.tick(api, now)
  local f = api.state.features
  if f.events_checked and now - f.events_checked < 10 then return end
  f.events_checked = now
  f.event_started = f.event_started or {}
  f.events_clubs_sent = f.events_clubs_sent or 0
  for _, e in ipairs(events(api)) do
    if not f.event_started[e.id] and e.at <= now and now < e.at + e.minutes * 60 then
      f.event_started[e.id] = true
      api.notice(nil, "EVENT_STARTS", { e.title, e.area ~= "" and ("AREA_" .. e.area:upper()) or "EVENT_ANYWHERE" }, 10)
      api.push("events", view(api), nil)
    end
  end
  -- Club bookings change elsewhere; refresh the calendar now and then.
  if now - f.events_clubs_sent > 60 then
    f.events_clubs_sent = now
    api.push("events", view(api), nil)
  end
end

M.requests = {}

-- Admins: {kind, title, at, minutes, area?}
M.requests.event_schedule = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local kind = tostring(payload.kind or "other")
  if not M.KINDS[kind] then return nil, "bad_kind" end
  local title = School.clean_text(payload.title, M.MAX_TITLE_BYTES)
  if title == "" then return nil, "empty" end
  local at = math.floor(tonumber(payload.at) or 0)
  -- Small numbers are minutes from now (typed in chat: /event feast 30 60 great_hall …).
  if at < 100000000 then at = math.floor(api.now) + at * 60 end
  local minutes = math.floor(tonumber(payload.minutes) or 60)
  if at < api.now - 60 or at > api.now + 180 * 86400 then return nil, "bad_time" end
  if minutes < 5 or minutes > 24 * 60 then return nil, "bad_length" end
  local area = tostring(payload.area or "")
  if area == "-" then area = "" end
  if area ~= "" and not api.AREAS[area] then return nil, "unknown_area" end
  local list = upcoming(api)
  if #list >= M.MAX_EVENTS then return nil, "too_many" end
  local e = { id = api.nk.uuid_v4(), kind = kind, title = title, at = at, minutes = minutes, area = area, by = api.name(sid) }
  table.insert(list, e)
  api.state.features.events = list
  save(api)
  return e
end

-- Admins: {id}
M.requests.event_cancel = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local list, found = {}, false
  for _, e in ipairs(events(api)) do
    if e.id == payload.id then found = true else table.insert(list, e) end
  end
  if not found then return nil, "no_event" end
  api.state.features.events = list
  save(api)
  return {}
end

M.requests.events_list = function(api, sid, payload) return view(api) end

return M

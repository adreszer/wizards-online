-- Clubs and societies: any student founds a club (a name and a badge: a colour and a
-- symbol), others join and leave; members post to the club board and book a room for a
-- meeting (a public room, up to two hours, within the next fortnight, not overlapping
-- another club's booking there). Bookings go into everyone's events calendar; a member
-- gets a notice when a meeting starts. The founder (or an admin) can close the club.
--
-- Storage: clubs/<id> (system): { id, name, badge = { colour, symbol }, founder, founder_name,
--   members = { [uid] = name }, posts = { { by, text, at } }, bookings = { { area, at, minutes } } }
-- Push "clubs": { clubs = [ summary ] } to everyone; "club_board": { id, posts } to members on demand.

local Store = require("store")
local School = require("school")
local Moderation = require("moderation")

local M = { name = "clubs" }

M.COLLECTION = "clubs"
M.MAX_NAME_BYTES = 40
M.MAX_POST_BYTES = 300
M.MAX_POSTS = 20
M.MAX_CLUBS_PER_FOUNDER = 1
M.MAX_MEMBERSHIPS = 6
M.BADGE_COLOURS, M.BADGE_SYMBOLS = 8, 8
M.MAX_BOOKINGS = 6
M.MAX_MINUTES = 120
M.BOOK_AHEAD = 14 * 86400
M.BOOKABLE = { classroom = true, room = true, library = true, hall = true, tower = true, grounds = true, outdoor = true }

local function all(api)
  local f = api.state.features
  if not f.clubs then
    f.clubs = {}
    for _, o in ipairs(Store.list(M.COLLECTION, nil, 500)) do
      if type(o.value.id) == "string" then f.clubs[o.value.id] = o.value end
    end
  end
  return f.clubs
end

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- What everyone sees of a club.
local function summary(api, c)
  local upcoming = {}
  for _, b in ipairs(c.bookings or {}) do
    if b.at + b.minutes * 60 > api.now then table.insert(upcoming, b) end
  end
  local member_names = {}
  for _, n in pairs(c.members) do table.insert(member_names, n) end
  table.sort(member_names)
  return { id = c.id, name = c.name, badge = c.badge, founder = c.founder_name, members = member_names, bookings = upcoming }
end

local function club_list(api)
  local list = {}
  for _, c in pairs(all(api)) do table.insert(list, summary(api, c)) end
  table.sort(list, function(a, b) return a.name < b.name end)
  return { clubs = list }
end

local function save(api, c)
  Store.write(M.COLLECTION, c.id, nil, c)
  api.push("clubs", club_list(api), nil)
end

function M.join(api, sid) api.push("clubs", club_list(api), sid) end

-- A meeting starting: tell its online members once.
function M.tick(api, now)
  local f = api.state.features
  if f.clubs_checked and now - f.clubs_checked < 15 then return end
  f.clubs_checked = now
  f.club_started = f.club_started or {}
  for _, c in pairs(all(api)) do
    for _, b in ipairs(c.bookings or {}) do
      local key = c.id .. "@" .. b.at
      if not f.club_started[key] and b.at <= now and now < b.at + b.minutes * 60 then
        f.club_started[key] = true
        local sids = {}
        for uid, _ in pairs(c.members) do
          local s = api.sid_of_user(uid)
          if s then table.insert(sids, s) end
        end
        if #sids > 0 then api.notice(sids, "CLUB_MEETING_STARTS", { c.name, "AREA_" .. b.area:upper() }, 10) end
      end
    end
  end
end

local function memberships(api, uid)
  local n = 0
  for _, c in pairs(all(api)) do
    if c.members[uid] then n = n + 1 end
  end
  return n
end

-- The clubs `uid` belongs to (for profile cards): { {name, badge} }.
function M.of(api, uid)
  local out = {}
  for _, c in pairs(all(api)) do
    if c.members[uid] then table.insert(out, { name = c.name, badge = c.badge }) end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Club bookings as calendar entries: { {club, area, at, minutes} }.
function M.bookings(api)
  local out = {}
  for _, c in pairs(all(api)) do
    for _, b in ipairs(c.bookings or {}) do
      if b.at + b.minutes * 60 > api.now then table.insert(out, { club = c.name, area = b.area, at = b.at, minutes = b.minutes }) end
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

M.requests = {}

-- {name, colour, symbol}
M.requests.club_create = function(api, sid, payload)
  local uid = api.uid(sid)
  local name = School.clean_text(payload.name, M.MAX_NAME_BYTES)
  if #name < 3 then return nil, "name_too_short" end
  if Moderation.filter(name, api.state.filter or {}) ~= name then return nil, "name_not_allowed" end
  local founded = 0
  for _, c in pairs(all(api)) do
    if c.name:lower() == name:lower() then return nil, "name_taken" end
    if c.founder == uid then founded = founded + 1 end
  end
  if founded >= M.MAX_CLUBS_PER_FOUNDER and not api.is_admin(sid) then return nil, "already_founded" end
  if memberships(api, uid) >= M.MAX_MEMBERSHIPS then return nil, "too_many" end
  local colour = math.floor(tonumber(payload.colour) or 0) % M.BADGE_COLOURS
  local symbol = math.floor(tonumber(payload.symbol) or 0) % M.BADGE_SYMBOLS
  local c = { id = api.nk.uuid_v4(), name = name, badge = { colour = colour, symbol = symbol }, founder = uid, founder_name = api.name(sid),
              members = { [uid] = api.name(sid) }, posts = {}, bookings = {} }
  all(api)[c.id] = c
  save(api, c)
  return { id = c.id, name = name }
end

M.requests.club_join = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  if not c then return nil, "no_club" end
  local uid = api.uid(sid)
  if c.members[uid] then return nil, "already_member" end
  if memberships(api, uid) >= M.MAX_MEMBERSHIPS then return nil, "too_many" end
  c.members[uid] = api.name(sid)
  save(api, c)
  return { id = c.id }
end

M.requests.club_leave = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  local uid = api.uid(sid)
  if not c or not c.members[uid] then return nil, "not_member" end
  c.members[uid] = nil
  if count(c.members) == 0 then
    all(api)[c.id] = nil
    Store.delete(M.COLLECTION, c.id, nil)
    api.push("clubs", club_list(api), nil)
  else
    if c.founder == uid then
      local next_uid, next_name = next(c.members)
      c.founder, c.founder_name = next_uid, next_name
    end
    save(api, c)
  end
  return { id = c.id }
end

-- The founder or an admin: {id} closes the club.
M.requests.club_close = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  if not c then return nil, "no_club" end
  if c.founder ~= api.uid(sid) and not api.is_admin(sid) then return nil, "not_allowed" end
  all(api)[c.id] = nil
  Store.delete(M.COLLECTION, c.id, nil)
  api.push("clubs", club_list(api), nil)
  return { id = c.id }
end

M.requests.club_post = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  if not c or not c.members[api.uid(sid)] then return nil, "not_member" end
  local text = School.clean_text(payload.text, M.MAX_POST_BYTES)
  if text == "" then return nil, "empty" end
  local f = api.state.features
  f.club_post_at = f.club_post_at or {}
  if f.club_post_at[sid] and api.now - f.club_post_at[sid] < 5 then return nil, "too_fast" end
  f.club_post_at[sid] = api.now
  table.insert(c.posts, 1, { by = api.name(sid), text = Moderation.filter(text, api.state.filter or {}), at = api.now })
  while #c.posts > M.MAX_POSTS do table.remove(c.posts) end
  Store.write(M.COLLECTION, c.id, nil, c)
  return { id = c.id, posts = c.posts }
end

M.requests.club_board = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  if not c or not c.members[api.uid(sid)] then return nil, "not_member" end
  return { id = c.id, posts = c.posts }
end

-- {id, area, at (unix seconds), minutes}
M.requests.club_book = function(api, sid, payload)
  local c = all(api)[tostring(payload.id or "")]
  if not c or not c.members[api.uid(sid)] then return nil, "not_member" end
  local area = tostring(payload.area or "")
  local def = api.AREAS[area]
  if not def or def.house ~= 0 or not M.BOOKABLE[def.kind] then return nil, "not_bookable" end
  local at = math.floor(tonumber(payload.at) or 0)
  local minutes = math.floor(tonumber(payload.minutes) or 60)
  if minutes < 15 or minutes > M.MAX_MINUTES then return nil, "bad_length" end
  if at < api.now - 60 or at > api.now + M.BOOK_AHEAD then return nil, "bad_time" end
  local upcoming = 0
  for _, b in ipairs(c.bookings) do
    if b.at + b.minutes * 60 > api.now then upcoming = upcoming + 1 end
  end
  if upcoming >= M.MAX_BOOKINGS then return nil, "too_many" end
  for _, other in pairs(all(api)) do
    for _, b in ipairs(other.bookings or {}) do
      if b.area == area and at < b.at + b.minutes * 60 and b.at < at + minutes * 60 then return nil, "room_taken" end
    end
  end
  local keep = {}
  for _, b in ipairs(c.bookings) do
    if b.at + b.minutes * 60 > api.now then table.insert(keep, b) end
  end
  table.insert(keep, { area = area, at = at, minutes = minutes, by = api.name(sid) })
  c.bookings = keep
  save(api, c)
  return { id = c.id, area = area, at = at }
end

return M

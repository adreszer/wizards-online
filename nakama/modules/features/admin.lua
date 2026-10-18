-- The in-game admin panel's server side (admins only; the HTTP-key RPCs in world.lua
-- stay for tooling): who is online and where, roles, houses and years set live, a
-- broadcast to the whole castle, the timetable edited in the game (slots added, changed
-- or removed on top of nakama/content/timetable.json, kept in storage), the player
-- reports, and lesson plans approved for self-study.

local School = require("school")
local Timetable = require("timetable")
local Moderation = require("moderation")
local Profile = require("character_profile")

local M = { name = "admin" }

M.MAX_BROADCAST_BYTES = 300

local function need_admin(api, sid)
  return api.is_admin(sid)
end

M.requests = {}

M.requests.admin_who = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local list = {}
  for _, s in ipairs(api.sids()) do
    local p = api.profile(s)
    table.insert(list, { name = api.name(s), role = p and p.role or "student", house = p and p.house or 0, year = p and p.year or 1, area = api.area(s) })
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return { players = list }
end

-- {name, role?, house?, year?}
M.requests.admin_set = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  local p = api.profile(target)
  if type(payload.role) == "string" and payload.role ~= "" then
    if not Profile.ROLES[payload.role] then return nil, "bad_role" end
    p.role = payload.role
  end
  local house = tonumber(payload.house)
  if house then
    if house < 0 or house > Profile.MAX_HOUSE then return nil, "bad_house" end
    p.house = math.floor(house)
  end
  local year = tonumber(payload.year)
  if year then
    if year < 1 or year > Profile.MAX_YEAR then return nil, "bad_year" end
    p.year = math.floor(year)
  end
  api.profile_changed(target)
  return { name = api.name(target), role = p.role, house = p.house, year = p.year }
end

-- {text}: a notice to everyone in the castle.
M.requests.admin_broadcast = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local text = School.clean_text(payload.text, M.MAX_BROADCAST_BYTES)
  if text == "" then return nil, "empty" end
  api.notice(nil, "ADMIN_BROADCAST", { api.name(sid), text }, 12)
  return {}
end

-- The timetable as the file and the in-game changes make it: { slots, added, removed }.
M.requests.admin_timetable = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local o = Timetable.load_overrides()
  local slots = {}
  local names = { [0] = "mon", "tue", "wed", "thu", "fri", "sat", "sun" }
  for _, s in ipairs(api.timetable().slots) do
    table.insert(slots, { id = s.id, kind = s.kind, day = names[s.day] or tostring(s.day), start = string.format("%02d:%02d", math.floor(s.start / 3600), math.floor(s.start % 3600 / 60)),
                          minutes = math.floor(s.seconds / 60), subject = s.subject, room = s.area, professor = s.professor })
  end
  local removed = {}
  for id, _ in pairs(o.remove) do table.insert(removed, id) end
  return { slots = slots, added = #o.add, removed = removed }
end

-- {id, day, start, minutes, kind?, subject?, room?, professor?}: adds (or replaces) a slot.
M.requests.admin_timetable_set = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local raw = { id = payload.id, day = payload.day, start = payload.start, minutes = tonumber(payload.minutes), kind = payload.kind or "lesson",
                subject = payload.subject ~= "" and payload.subject or nil, room = payload.room ~= "" and payload.room or nil,
                professor = payload.professor ~= "" and payload.professor or nil }
  local slot, why = Timetable.sanitize_slot(raw)
  if not slot then
    api.nk.logger_info("admin timetable slot refused: " .. tostring(why))
    return nil, "bad_slot"
  end
  local o = Timetable.load_overrides()
  local keep = {}
  for _, s in ipairs(o.add) do
    if s.id ~= raw.id then table.insert(keep, s) end
  end
  table.insert(keep, raw)
  o.add = keep
  o.remove[raw.id] = true   -- replaces a file slot of the same id
  Timetable.save_overrides(o)
  return { slots = api.reload_timetable() }
end

-- {id}: removes a slot (from the file's or the added ones).
M.requests.admin_timetable_remove = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  local id = tostring(payload.id or "")
  if id == "" then return nil, "bad_slot" end
  local o = Timetable.load_overrides()
  local keep = {}
  for _, s in ipairs(o.add) do
    if s.id ~= id then table.insert(keep, s) end
  end
  o.add = keep
  o.remove[id] = true
  Timetable.save_overrides(o)
  return { slots = api.reload_timetable() }
end

-- Undo every in-game change: back to the file.
M.requests.admin_timetable_reset = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  Timetable.save_overrides({ add = {}, remove = {} })
  return { slots = api.reload_timetable() }
end

M.requests.admin_reports = function(api, sid, payload)
  if not need_admin(api, sid) then return nil, "not_allowed" end
  return { reports = Moderation.list_reports(math.max(1, math.min(100, math.floor(tonumber(payload.limit) or 30)))) }
end

return M

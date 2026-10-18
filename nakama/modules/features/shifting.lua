-- The shifting castle: doors that follow the days and the night (generated/castle_schedule.lua,
-- from gameplay/world/castle_schedule.gd). The server drives them, so no player can hold one
-- open or shut against the schedule, and sets each to what the shared time says.

local SCHEDULE = require("generated.castle_schedule")
local Timetable = require("timetable")

local M = { name = "shifting" }

local function is_night(h) return h >= SCHEDULE.night_from or h < SCHEDULE.night_until end

function M.open_at(rule, weekday, hours)
  if rule.days then
    for _, d in ipairs(rule.days) do
      if d == weekday then return true end
    end
    return false
  end
  if rule.night ~= nil then return is_night(hours) == rule.night end
  return false
end

function M.tick(api, now)
  local f = api.state.features
  if f.shifting_at and now - f.shifting_at < 5 then return end
  f.shifting_at = now
  local weekday = Timetable.weekday(api.school_day())
  local hours = api.school_hours()
  for oid, rule in pairs(SCHEDULE.doors) do
    api.drive(oid, true)
    local want = M.open_at(rule, weekday, hours)
    if api.object_state(oid) ~= want then api.set_object(oid, want) end
  end
end

return M

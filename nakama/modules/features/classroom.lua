-- Classroom controls for the professor running a lesson in their room: quiet the room
-- (students' say and shout do not reach anyone until it is lifted; whispers and the
-- professor still do), lock the room's doors (exams: nobody opens them until unlocked)
-- and ring the hand bell (everyone in the room is asked for attention). Each lasts at
-- most as long as the lesson: closing the lesson lifts them.
--
-- Memory only: state.features.classroom[area] = { muted, locked = { oid… } }
-- Push "classroom": { [area] = { muted, locked } } to everyone.

local OBJECTS = require("generated.world_objects")

local M = { name = "classroom" }

local function rooms(api)
  api.state.features.classroom = api.state.features.classroom or {}
  return api.state.features.classroom
end

local function view(api)
  local out = {}
  for area, c in pairs(rooms(api)) do
    out[area] = { muted = c.muted == true, locked = c.locked ~= nil and #c.locked > 0 }
  end
  return out
end

-- The room the professor teaches in now, or nil and a reason.
local function teaching(api, sid)
  local area = api.area(sid)
  local lesson = api.state.lessons[area]
  if not lesson then return nil, "no_lesson" end
  if lesson.by_sid ~= sid and not api.is_admin(sid) then return nil, "not_your_lesson" end
  return area
end

local function doors_of(area)
  local out = {}
  for oid, obj in pairs(OBJECTS) do
    if obj.kind == "castle_door" then
      for _, a in ipairs(obj.areas or {}) do
        if a == area then table.insert(out, oid) break end
      end
    end
  end
  table.sort(out)
  return out
end

local function unlock(api, c)
  for _, oid in ipairs(c.locked or {}) do api.drive(oid, false) end
  c.locked = nil
end

function M.join(api, sid) api.push("classroom", view(api), sid) end

-- A lesson that closed takes its controls with it.
function M.tick(api, now)
  local changed = false
  for area, c in pairs(rooms(api)) do
    if not api.state.lessons[area] then
      unlock(api, c)
      rooms(api)[area] = nil
      changed = true
    end
  end
  if changed then api.push("classroom", view(api), nil) end
end

-- Students' say and shout in a quieted room are refused.
function M.allow(api, what, sid, mode)
  if what ~= "chat" or mode == "whisper" or mode == "dm" then return true end
  local c = rooms(api)[api.area(sid)]
  if c and c.muted and not api.is_staff(sid) then return false, "room_quiet" end
  -- Exams are held in silence (the self-study exam lessons on exam days).
  local lesson = api.state.lessons[api.area(sid)]
  if lesson and lesson.exam and not api.is_staff(sid) then return false, "exam_silence" end
  return true
end

M.requests = {}

M.requests.classroom_mute = function(api, sid, payload)
  local area, why = teaching(api, sid)
  if not area then return nil, why end
  local c = rooms(api)[area] or {}
  rooms(api)[area] = c
  c.muted = payload.on ~= false
  local sids = {}
  for _, pl in ipairs(api.players_in(area)) do table.insert(sids, pl.sid) end
  api.notice(sids, c.muted and "CLASSROOM_QUIET" or "CLASSROOM_QUIET_OFF", { api.name(sid) }, 5)
  api.push("classroom", view(api), nil)
  return { muted = c.muted }
end

M.requests.classroom_lock = function(api, sid, payload)
  local area, why = teaching(api, sid)
  if not area then return nil, why end
  local c = rooms(api)[area] or {}
  rooms(api)[area] = c
  if payload.on == false then
    unlock(api, c)
  else
    unlock(api, c)
    c.locked = {}
    for _, oid in ipairs(doors_of(area)) do
      if api.object_state(oid) ~= "locked" then
        api.set_object(oid, false)
        api.drive(oid, true)
        table.insert(c.locked, oid)
      end
    end
  end
  api.push("classroom", view(api), nil)
  return { locked = c.locked ~= nil, doors = c.locked and #c.locked or 0 }
end

M.requests.classroom_bell = function(api, sid, payload)
  local area, why = teaching(api, sid)
  if not area then return nil, why end
  local f = api.state.features
  f.bell_at = f.bell_at or {}
  if f.bell_at[area] and api.now - f.bell_at[area] < 5 then return nil, "too_fast" end
  f.bell_at[area] = api.now
  local sids = {}
  for _, pl in ipairs(api.players_in(area)) do
    if pl.sid ~= sid then table.insert(sids, pl.sid) end
  end
  api.notice(sids, "CLASSROOM_BELL", { api.name(sid) }, 5)
  api.push("bell", { area = area, by = api.name(sid), at = api.now }, sids)
  return { heard = #sids }
end

return M

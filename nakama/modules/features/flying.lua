-- Flying lessons for real: a broom licence. The Flying professor (or any professor or
-- admin) passes a student who stands with them in the flying classroom or on the
-- pitch: the student gets the licence and a broom. Without a licence the broom racks
-- stay shut and the broom workshop will not sell one. In the air, the server checks
-- where each rider is: flying is allowed only outdoors (outdoor and grounds areas, or
-- outside every area); a rider reported elsewhere is told to land.
--
-- Storage: school/licences per user (owner-readable): { broom = bool, by, at }
-- Push "licence": { broom } to the student; "flight": { land = true } to a rider out of bounds.

local Store = require("store")

local M = { name = "flying" }

M.COLLECTION, M.KEY = "school", "licences"
M.LESSON_AREAS = { class_skyriding = true, pitch = true }
M.FLY_KINDS = { outdoor = true, grounds = true }
M.CHECK_GAP = 1.0

local function cache(api)
  api.state.features.licences = api.state.features.licences or {}
  return api.state.features.licences
end

function M.licensed(api, sid)
  if api.is_staff(sid) then return true end
  local l = cache(api)[sid]
  return l ~= nil and l.broom == true
end

function M.join(api, sid)
  local l = Store.read(M.COLLECTION, M.KEY, api.uid(sid)) or {}
  cache(api)[sid] = l
  api.push("licence", { broom = M.licensed(api, sid) }, sid)
end

function M.leave(api, sid) cache(api)[sid] = nil end

-- The match asks before an item rack hands something out: brooms need a licence.
function M.allow(api, what, sid, item)
  if what == "take_item" and item == "broom" and not M.licensed(api, sid) then return false, "no_licence" end
  return true
end

-- A rider's state arrived (at most once a second per rider): land them if not outdoors.
function M.flying(api, sid)
  local area = api.area(sid)
  local def = area ~= "" and api.AREAS[area] or nil
  if def and not M.FLY_KINDS[def.kind] then
    api.push("flight", { land = true, area = area }, sid)
  end
end

M.requests = {}

-- Staff: {name} passes a student's flying lesson.
M.requests.flying_licence = function(api, sid, payload)
  if not api.is_staff(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  local area = api.area(sid)
  if not M.LESSON_AREAS[area] then return nil, "not_flying_lesson" end
  if api.area(target) ~= area then return nil, "not_together" end
  local l = { broom = true, by = api.name(sid), at = api.now }
  cache(api)[target] = l
  Store.write(M.COLLECTION, M.KEY, api.uid(target), l, true)
  api.give_item(target, "broom")
  api.push("licence", { broom = true }, target)
  api.notice(target, "FLYING_LICENCE_GRANTED", { api.name(sid) }, 8)
  return { name = api.name(target) }
end

-- Admins: {name} takes a licence away.
M.requests.flying_revoke = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  cache(api)[target] = { broom = false }
  Store.write(M.COLLECTION, M.KEY, api.uid(target), { broom = false }, true)
  api.push("licence", { broom = false }, target)
  return {}
end

return M

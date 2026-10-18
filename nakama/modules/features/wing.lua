-- The Unfinished Wing: a sealed part of the castle the whole school opens together.
-- Its locked doors (every locked castle door into or inside an unfinished_wing area, from
-- generated/world_objects.lua) cannot be unbolted by hand; they open one at a time, in
-- order from the entrance, as the school's shared progress passes the next threshold.
-- Progress comes from what students do together: exploring new places, finishing an
-- Echo's story, serving detention, harvesting, brewing, finishing games and matches
-- (other modules call M.contribute). Admins can add progress for a live event.
--
-- Storage: school/wing (system): { points, opened }
-- Push "wing": { points, opened, doors, next }

local Store = require("store")
local OBJECTS = require("generated.world_objects")

local M = { name = "wing" }

M.COLLECTION, M.KEY = "school", "wing"
M.PREFIX = "unfinished_wing"
-- Points for the k-th door: STEP * k (cumulative).
M.STEP = 40

local function in_wing(area) return type(area) == "string" and area:sub(1, #M.PREFIX) == M.PREFIX end

-- The wing's locked doors, entrance first, then by distance from it.
local doors
function M.doors()
  if doors then return doors end
  local list, entry = {}, nil
  for oid, obj in pairs(OBJECTS) do
    if obj.kind == "castle_door" and obj.locked then
      local inside, outside = false, false
      for _, a in ipairs(obj.areas or {}) do
        if in_wing(a) then inside = true else outside = true end
      end
      if inside then
        table.insert(list, { oid = oid, pos = obj.pos })
        if outside then entry = { oid = oid, pos = obj.pos } end
      end
    end
  end
  local origin = entry and entry.pos or { 0, 0, 0 }
  local function dist(d)
    local dx, dy, dz = d.pos[1] - origin[1], d.pos[2] - origin[2], d.pos[3] - origin[3]
    return dx * dx + dy * dy * 4 + dz * dz
  end
  table.sort(list, function(a, b)
    local da, db = dist(a), dist(b)
    if da == db then return a.oid < b.oid end
    return da < db
  end)
  doors = list
  return doors
end

-- Points needed before `n` doors are open.
function M.needed(n) return M.STEP * n * (n + 1) / 2 end

local function wing(api)
  local f = api.state.features
  if not f.wing then
    local w = Store.read(M.COLLECTION, M.KEY, nil) or {}
    f.wing = { points = tonumber(w.points) or 0, opened = tonumber(w.opened) or 0 }
  end
  return f.wing
end

local function view(api)
  local w = wing(api)
  local total = #M.doors()
  return { points = w.points, opened = w.opened, doors = total, next = w.opened < total and M.needed(w.opened + 1) or 0 }
end

-- Keeps the doors as they should be: sealed ones driven (players cannot unbolt them),
-- opened ones free and no longer locked.
local function apply(api, announce)
  local w = wing(api)
  for i, d in ipairs(M.doors()) do
    if i <= w.opened then
      api.drive(d.oid, false)
      if api.object_state(d.oid) == "locked" then
        api.set_object(d.oid, false)
        if announce then api.notice(nil, "WING_ROOM_OPENED", { i, #M.doors() }, 10) end
      end
    else
      api.drive(d.oid, true)
    end
  end
end

-- Adds `n` points of shared progress; opens every door whose threshold is passed.
function M.contribute(api, n)
  if not n or n <= 0 then return end
  local w = wing(api)
  w.points = w.points + n
  local opened = w.opened
  while w.opened < #M.doors() and w.points >= M.needed(w.opened + 1) do
    w.opened = w.opened + 1
  end
  Store.write(M.COLLECTION, M.KEY, nil, { points = w.points, opened = w.opened })
  if w.opened > opened then
    apply(api, true)
    api.rumour("RUMOUR_WING", 0)
    api.push("wing", view(api), nil)
  else
    local f = api.state.features
    -- Progress is sent at most every few seconds to everyone (it changes often).
    if not f.wing_sent or api.now - f.wing_sent > 5 then
      f.wing_sent = api.now
      api.push("wing", view(api), nil)
    end
  end
end

function M.join(api, sid)
  if not api.state.features.wing_applied then
    api.state.features.wing_applied = true
    apply(api, false)
  end
  api.push("wing", view(api), sid)
end

-- A world reset forgets the driven marks and the unbolted doors: put them back.
function M.tick(api, now)
  local f = api.state.features
  if not f.wing_checked or now - f.wing_checked > 30 then
    f.wing_checked = now
    apply(api, false)
  end
end

M.requests = {}

-- Admins: {points} adds shared progress (a live event); answers the new state.
M.requests.wing_contribute = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local n = math.floor(tonumber(payload.points) or 0)
  if n <= 0 or n > 100000 then return nil, "bad_amount" end
  M.contribute(api, n)
  return view(api)
end

M.requests.wing_state = function(api, sid, payload)
  return view(api)
end

return M

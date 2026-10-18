-- The Echoes: translucent memories of former students and staff, each bound to one
-- place in the castle (nakama/content/echoes.json). Talking to an Echo (standing in its
-- area) tells the next part of its story and sets a goal: visit a place, visit it at
-- night, bring an item (it is taken), or come back with someone (another player in the
-- goal's area when you report). Goals are met as they happen (area changes) or when you
-- talk; the last line pays the reward once (coins, a discovery on the profile, an item).
--
-- Storage: school/echoes per user (server-only): { [echo] = { step, met = bool, done = bool } }
-- Push "echoes": { [echo] = { step, met, done, goal? } }

local Store = require("store")
local Profile = require("character_profile")

local M = { name = "echoes" }

M.COLLECTION, M.KEY = "school", "echoes"

local content
local function echoes()
  if not content then
    local data = Store.content("echoes.json")
    content = data and type(data.echoes) == "table" and data.echoes or {}
  end
  return content
end

local function cache(api)
  api.state.features.echoes = api.state.features.echoes or {}
  return api.state.features.echoes
end

local function progress(api, sid)
  local c = cache(api)
  if not c[sid] then c[sid] = Store.read(M.COLLECTION, M.KEY, api.uid(sid)) or {} end
  return c[sid]
end

local function view(api, sid)
  local out = {}
  for id, e in pairs(echoes()) do
    local p = progress(api, sid)[id] or { step = 0 }
    local step = e.steps[p.step]
    out[id] = { step = p.step or 0, met = p.met == true, done = p.done == true, area = e.area, goal = step and step.goal or nil }
  end
  return out
end

local function save(api, sid)
  Store.write(M.COLLECTION, M.KEY, api.uid(sid), progress(api, sid))
  api.push("echoes", view(api, sid), sid)
end

local function night(api)
  local h = api.school_hours()
  return h >= 20 or h < 6
end

-- Whether the goal is met now by `sid` standing in `area`.
local function met_by_area(api, sid, goal, area)
  if goal.visit and goal.visit == area then return true end
  if goal.night_visit and goal.night_visit == area and night(api) then return true end
  if goal.together and goal.together == area and #api.players_in(area) >= 2 then return true end
  return false
end

function M.join(api, sid)
  api.push("echoes", view(api, sid), sid)
end

function M.leave(api, sid) cache(api)[sid] = nil end

function M.area(api, sid, area)
  local changed = false
  for id, e in pairs(echoes()) do
    local p = progress(api, sid)[id]
    local step = p and not p.done and e.steps[p.step]
    if step and step.goal and not p.met and met_by_area(api, sid, step.goal, area) then
      p.met = true
      changed = true
      api.notice(sid, "ECHO_GOAL_MET", { "ECHO_" .. id:upper() .. "_NAME" }, 5)
    end
  end
  if changed then save(api, sid) end
end

M.requests = {}

-- {echo}: talk to an Echo in its area. Returns { line, step, done }.
M.requests.echo_talk = function(api, sid, payload)
  local id = tostring(payload.echo or "")
  local e = echoes()[id]
  if not e then return nil, "unknown_echo" end
  if api.area(sid) ~= e.area then return nil, "wrong_room" end
  local all = progress(api, sid)
  local p = all[id] or { step = 0 }
  all[id] = p
  if p.done then return { line = "ECHO_" .. id:upper() .. "_AFTER", step = p.step, done = true } end
  local current = e.steps[p.step]
  if current and current.goal then
    local goal = current.goal
    if goal.item and not p.met then
      if api.count_item(sid, goal.item) < 1 then return { line = "ECHO_WAITING", step = p.step, done = false, waiting = true } end
      api.take_item(sid, goal.item, 1)
      p.met = true
    end
    if goal.together and not p.met and met_by_area(api, sid, goal, goal.together) then p.met = true end
    if not p.met then return { line = "ECHO_WAITING", step = p.step, done = false, waiting = true } end
  end
  p.step = (p.step or 0) + 1
  p.met = false
  local step = e.steps[p.step]
  if p.step >= #e.steps then
    p.done = true
    local r = e.reward or {}
    if r.coins then api.pay(sid, r.coins, "echo", id) end
    if r.item then api.give_item(sid, r.item) end
    local profile = api.profile(sid)
    if r.discovery and profile and Profile.discover(profile, r.discovery) then api.save_profile(sid) end
  end
  save(api, sid)
  return { line = step and step.line or "", step = p.step, done = p.done == true }
end

-- Admins: {name} starts a student's Echo stories again (support, tests).
M.requests.echo_reset = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  cache(api)[target] = {}
  save(api, target)
  return {}
end

return M

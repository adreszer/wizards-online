-- Weekly house quests (nakama/content/house_quests.json): each school week a few quests
-- rotate in; every member's lessons, practicals, right answers and first mystery solves
-- count for their house; a house that reaches a target is awarded the quest's points
-- once that week. Progress is stored (school/house_quests) so a restart keeps it.

local nk = require("nakama")

local M = {}

M.PATH = "../content/house_quests.json"
M.COLLECTION, M.KEY = "school", "house_quests"
M.COUNTERS = { lessons = true, practicals = true, quiz_right = true, mysteries = true }

function M.load_defs()
  local defs = { per_week = 2, quests = {} }
  local ok, raw = pcall(nk.file_read, M.PATH)
  if not ok then return defs end
  local ok2, data = pcall(nk.json_decode, raw)
  if not ok2 or type(data) ~= "table" then
    nk.logger_error("house quests: " .. M.PATH .. " is not valid JSON")
    return defs
  end
  defs.per_week = math.max(1, math.floor(tonumber(data.per_week) or 2))
  for _, q in ipairs(type(data.quests) == "table" and data.quests or {}) do
    if type(q.id) == "string" and M.COUNTERS[q.counter] and tonumber(q.target) and tonumber(q.points) and type(q.name_key) == "string" then
      table.insert(defs.quests, { id = q.id, counter = q.counter, target = math.max(1, math.floor(q.target)), points = math.floor(q.points), name_key = q.name_key })
    else
      nk.logger_error("house quests: quest " .. tostring(q.id) .. " left out")
    end
  end
  return defs
end

-- The quests of school week `week` (days since the epoch // 7).
function M.active(defs, week)
  local out = {}
  local n = #defs.quests
  if n == 0 then return out end
  for i = 0, math.min(defs.per_week, n) - 1 do
    table.insert(out, defs.quests[((week * defs.per_week + i) % n) + 1])
  end
  return out
end

function M.load_state()
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = M.KEY, user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return { week = -1, progress = {}, done = {} }
end

function M.save_state(qs)
  pcall(nk.storage_write, { { collection = M.COLLECTION, key = M.KEY, user_id = nil, value = qs, permission_read = 2, permission_write = 0 } })
end

-- A new week clears the progress.
function M.roll(qs, week)
  if qs.week ~= week then
    qs.week, qs.progress, qs.done = week, {}, {}
    return true
  end
  return false
end

-- Adds `n` to `counter` for `house`; returns the quests this completed for the house.
function M.count(qs, defs, house, counter, n)
  if house < 1 or house > 4 or n <= 0 then return {} end
  local key = counter .. ":" .. house
  qs.progress[key] = (qs.progress[key] or 0) + n
  local finished = {}
  for _, q in ipairs(M.active(defs, qs.week)) do
    local done_key = q.id .. ":" .. house
    if q.counter == counter and not qs.done[done_key] and qs.progress[key] >= q.target then
      qs.done[done_key] = true
      table.insert(finished, q)
    end
  end
  return finished
end

-- What clients see: { week, quests = { {id, name_key, target, points, progress = {h1..h4}, done = {h1..h4}} } }
function M.payload(qs, defs)
  local list = {}
  for _, q in ipairs(M.active(defs, qs.week)) do
    local progress, done = {}, {}
    for h = 1, 4 do
      progress[h] = qs.progress[q.counter .. ":" .. h] or 0
      done[h] = qs.done[q.id .. ":" .. h] == true
    end
    table.insert(list, { id = q.id, name_key = q.name_key, target = q.target, points = q.points, progress = progress, done = done })
  end
  return { week = qs.week, quests = list }
end

return M

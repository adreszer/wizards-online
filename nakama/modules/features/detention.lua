-- Detention tasks: the night warden (a student caught after curfew), a professor or a
-- prefect gives a student a task in a room (polish the trophies, re-shelve the library,
-- sort ingredients, scrub the kitchen pots: nakama/content/detention.json). The task's
-- spots show in that room for the student only; each must be worked (interact) once,
-- standing in the room, at most one every STEP_GAP seconds. When every spot is done the
-- detention is over, logged, and some tasks let a secret slip (a notice, and a
-- "detention" event for the mystery engine). One detention at a time; it persists.
--
-- Storage: school/detention per user (server-only): { task, by_name, at, done = { [spot] = true } }
-- Push "detention": { task, area, spots, done = [spot…], by } or {} when free.

local Store = require("store")

local M = { name = "detention" }

M.COLLECTION, M.KEY = "school", "detention"
M.STEP_GAP = 2.0
M.DEFAULT = {
  tasks = { polish_trophies = { area = "trophy_room", spots = 5 } },
  warden_tasks = { "polish_trophies" },
}

local content
local function defs()
  if not content then
    content = Store.content("detention.json") or M.DEFAULT
    if type(content.tasks) ~= "table" then content = M.DEFAULT end
  end
  return content
end

function M.task(id) return defs().tasks[id] end

local function cache(api)
  api.state.features.detention = api.state.features.detention or {}
  return api.state.features.detention
end

-- The push for one detention record (nil = free).
function M.view(d)
  local t = d and M.task(d.task)
  if not t then return {} end
  local done = {}
  for i = 1, t.spots do
    if d.done[tostring(i)] then table.insert(done, i) end
  end
  return { task = d.task, area = t.area, spots = t.spots, done = done, by = d.by_name or "" }
end

local function send(api, sid)
  api.push("detention", M.view(cache(api)[sid]), sid)
end

-- Gives `sid` the detention `task` (from `by_name`). Returns the record or nil, reason.
function M.assign(api, sid, task, by_name)
  local uid = api.uid(sid)
  if not uid then return nil, "no_player" end
  if not M.task(task) then return nil, "unknown_task" end
  local c = cache(api)
  if c[sid] then return nil, "already_in_detention" end
  local d = { task = task, by_name = by_name, at = api.now, done = {} }
  c[sid] = d
  Store.write(M.COLLECTION, M.KEY, uid, d)
  send(api, sid)
  api.notice(sid, "DETENTION_GIVEN", { by_name, "DETENTION_TASK_" .. task:upper(), "AREA_" .. M.task(task).area:upper() }, 8)
  return d
end

function M.join(api, sid)
  local d = Store.read(M.COLLECTION, M.KEY, api.uid(sid))
  if d and M.task(d.task) and type(d.done) == "table" then
    cache(api)[sid] = d
  end
  send(api, sid)
end

function M.leave(api, sid)
  cache(api)[sid] = nil
end

-- The warden's catch (curfew) comes with a task.
function M.caught(api, sid)
  local list = defs().warden_tasks or {}
  if #list == 0 or cache(api)[sid] then return end
  M.assign(api, sid, list[math.random(#list)], "WARDEN_NAME")
end

M.requests = {}

-- Staff and prefects: {name, task?}.
M.requests.detention_assign = function(api, sid, payload)
  local role = api.role(sid)
  if role ~= "professor" and role ~= "admin" and role ~= "prefect" then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  if api.is_staff(target) then return nil, "not_a_student" end
  if role == "prefect" and api.house(target) ~= api.house(sid) then return nil, "other_house" end
  local task = type(payload.task) == "string" and payload.task or nil
  if not task then
    local list = defs().warden_tasks or {}
    task = list[math.random(math.max(1, #list))]
  end
  local d, reason = M.assign(api, target, task, api.name(sid))
  if not d then return nil, reason end
  return { task = task, name = api.name(target) }
end

-- The student works one spot: {spot}.
M.requests.detention_step = function(api, sid, payload)
  local c = cache(api)
  local d = c[sid]
  if not d then return nil, "no_detention" end
  local t = M.task(d.task)
  local spot = math.floor(tonumber(payload.spot) or 0)
  if spot < 1 or spot > t.spots then return nil, "bad_spot" end
  if api.area(sid) ~= t.area then return nil, "wrong_room" end
  if d.done[tostring(spot)] then return nil, "already_done" end
  if d.last and api.now - d.last < M.STEP_GAP then return nil, "too_fast" end
  d.last = api.now
  d.done[tostring(spot)] = true
  local count = 0
  for _ in pairs(d.done) do count = count + 1 end
  local uid = api.uid(sid)
  if count >= t.spots then
    c[sid] = nil
    Store.delete(M.COLLECTION, M.KEY, uid)
    api.log({ kind = "detention_done", subject = "", area = t.area, slot = "", by = "", by_name = d.by_name or "", opened_at = d.at, closed_at = api.now,
              why = d.task, attended = { [uid] = api.name(sid) }, points = 0 })
    api.notice(sid, "DETENTION_DONE", { "DETENTION_TASK_" .. d.task:upper() }, 6)
    if t.secret then api.notice(sid, t.secret, {}, 10) end
    api.feed(sid, { event = "detention", task = d.task, area = t.area })
    send(api, sid)
    return { done = true, task = d.task }
  end
  Store.write(M.COLLECTION, M.KEY, uid, d)
  send(api, sid)
  return { done = false, count = count, spots = t.spots }
end

return M

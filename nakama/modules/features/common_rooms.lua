-- Common-room doors ask the riddle of the week. Each house's door has its own riddle
-- each school week (nakama/content/riddles.json, rotated by week and house); a member
-- answers it once a week to be let in (the door opens without asking again that week).
-- Answers are compared folded: lower case, no diacritics or punctuation, articles off.
-- Guests with a prefect's pass and staff skip the riddle. The rule is the door's: the
-- server keeps who has answered, the client door asks before it opens.
--
-- Storage: school/riddle per user (server-only): { week }
-- Push "riddle": { house, week, question = {pl, en}, solved }

local Store = require("store")
local Moderation = require("moderation")

local M = { name = "common_rooms" }

M.COLLECTION, M.KEY = "school", "riddle"
M.MAX_ANSWER_BYTES = 80
M.TRY_GAP = 3.0

local riddles
local function list()
  if not riddles then
    local data = Store.content("riddles.json")
    riddles = data and type(data.riddles) == "table" and data.riddles or {}
  end
  return riddles
end

function M.week(api) return math.floor(api.school_day() / 7) end

-- The riddle on `house`'s door in `week` (nil without riddles).
function M.riddle_for(house, week)
  local all = list()
  if #all == 0 or house < 1 then return nil end
  return all[((week + house * 3) % #all) + 1]
end

-- An answer as compared: folded letters and single spaces, no leading article.
function M.normalize(text)
  local s = Moderation.fold(tostring(text or ""))
  s = s:gsub("[^%a%s]", " "):gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
  for _, article in ipairs({ "a ", "an ", "the " }) do
    if s:sub(1, #article) == article then s = s:sub(#article + 1) end
  end
  return s
end

function M.correct(riddle, answer)
  local given = M.normalize(answer)
  if given == "" then return false end
  for _, a in ipairs(riddle.a or {}) do
    if M.normalize(a) == given then return true end
  end
  return false
end

local function cache(api)
  api.state.features.riddle = api.state.features.riddle or {}
  return api.state.features.riddle
end

local function send(api, sid)
  local house = api.house(sid)
  local week = M.week(api)
  local r = M.riddle_for(house, week)
  local c = cache(api)[sid] or {}
  api.push("riddle", { house = house, week = week, question = r and r.q or nil, solved = r == nil or c.week == week or api.is_staff(sid) }, sid)
end

function M.join(api, sid)
  cache(api)[sid] = Store.read(M.COLLECTION, M.KEY, api.uid(sid)) or {}
  send(api, sid)
end

function M.leave(api, sid) cache(api)[sid] = nil end

-- A new week brings new riddles: refresh once a minute.
function M.tick(api, now)
  local week = M.week(api)
  if api.state.features.riddle_week ~= week then
    api.state.features.riddle_week = week
    for _, sid in ipairs(api.sids()) do send(api, sid) end
  end
end

M.requests = {}

-- {answer}: answers this week's riddle on the member's own door.
M.requests.riddle_answer = function(api, sid, payload)
  local house = api.house(sid)
  if house < 1 then return nil, "no_house" end
  local week = M.week(api)
  local r = M.riddle_for(house, week)
  if not r then return { solved = true } end
  local c = cache(api)[sid] or {}
  cache(api)[sid] = c
  if c.week == week then return { solved = true } end
  if c.tried and api.now - c.tried < M.TRY_GAP then return nil, "too_fast" end
  c.tried = api.now
  if type(payload.answer) ~= "string" or #payload.answer > M.MAX_ANSWER_BYTES or not M.correct(r, payload.answer) then
    return nil, "wrong_answer"
  end
  c.week = week
  Store.write(M.COLLECTION, M.KEY, api.uid(sid), { week = week })
  send(api, sid)
  return { solved = true }
end

-- Admins: {name} makes a student answer this week's riddle again (support, tests).
M.requests.riddle_reset = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  cache(api)[target] = {}
  Store.write(M.COLLECTION, M.KEY, api.uid(target), {})
  send(api, target)
  return {}
end

return M

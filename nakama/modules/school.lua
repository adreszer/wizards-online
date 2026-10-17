-- School rules shared by the world match and the admin/staff RPCs: lesson
-- subjects (generated.subjects), house points (a ledger plus a running total,
-- so every total can be explained record by record) and professors' lesson
-- plans. Numbers come from nakama/content/school_rules.json.
--
-- Storage (all system-owned unless noted):
--   house_points/totals       { totals = {h1, h2, h3, h4} }
--   house_points/<uuid>       { house, delta, reason, by, by_name, source, subject, at }
--   lesson_plans/<id>         per professor (owner-readable): { title, lines = {text} }
--   school/clock              { offset } seconds added to the world time (see SchoolClock)

local nk = require("nakama")
local SUBJECTS = require("generated.subjects")

local M = {}

M.RULES_PATH = "../content/school_rules.json"
M.DEFAULT_RULES = {
  max_points_per_award = 20,
  max_points_per_session = 50,
  points_cooldown_seconds = 5,
  session_max_minutes = 120,
  practice_tomes_enabled = true,
  -- Dev cheats (OP_CHEAT, chat commands such as /broom) for everyone; admins always may.
  cheats_enabled = false,
  max_reason_bytes = 120,
  max_lecture_bytes = 400,
  -- Real minutes per school day (the day/night cycle); clients get it as OP_CLOCK.
  day_length_minutes = 60,
  -- Currency (economy.lua): paid to students still in the room when a lesson that ran
  -- at least lesson_coin_minutes closes; for a first solve of a mystery without its own
  -- on_solved.coins; earned coins per school day are capped; one admin grant at most.
  coins_per_lesson = 10,
  lesson_coin_minutes = 10,
  coins_per_mystery = 15,
  max_daily_coins = 100,
  max_coin_grant = 1000,
  -- Chat (chat.lua): at most one line per chat_cooldown_seconds, one shout per
  -- shout_cooldown_seconds, one DM per dm_cooldown_seconds.
  chat_cooldown_seconds = 0.5,
  shout_cooldown_seconds = 10,
  dm_cooldown_seconds = 1,
  -- Lessons 2.0: what the classroom board holds.
  max_board_bytes = 800,
  -- Self-study (self_study.lua): a timetabled lesson nobody opened within this many
  -- minutes runs as self-study; only spells listed here are taught by it (the owner
  -- decides; empty = none); attendance pays this much.
  self_study_grace_minutes = 5,
  self_study_spells = {},
  coins_per_self_study = 5,
  -- Homework (homework.lua): a passing grade pays this much (earned, daily cap applies).
  coins_per_homework = 10,
  -- Prefects: the most they may deduct at once, and how long a guest pass to their
  -- house's rooms lasts.
  max_prefect_points = 5,
  guest_pass_minutes = 10,
  -- Duels (duel.lua): only in these areas, first to this many hits.
  duel_areas = { "duelling_hall", "class_warding" },
  duel_hits_to_win = 3,
}
M.HOUSES = 4
M.POINTS_COLLECTION, M.TOTALS_KEY = "house_points", "totals"
M.PLAN_COLLECTION = "lesson_plans"
M.MAX_PLAN_LINES = 100
M.MAX_TITLE_BYTES = 80
M.CLOCK_COLLECTION, M.CLOCK_KEY = "school", "clock"

function M.load_rules()
  local rules = {}
  for k, v in pairs(M.DEFAULT_RULES) do rules[k] = v end
  local ok, text = pcall(nk.file_read, M.RULES_PATH)
  if ok then
    local ok2, data = pcall(nk.json_decode, text)
    if ok2 and type(data) == "table" then
      for k, v in pairs(data) do
        if M.DEFAULT_RULES[k] ~= nil and type(v) == type(M.DEFAULT_RULES[k]) then rules[k] = v end
      end
    end
  else
    nk.logger_warn("school: cannot read " .. M.RULES_PATH .. ", using defaults")
  end
  return rules
end

function M.subject_for_area(area)
  return area and SUBJECTS.by_area[area] or nil
end

function M.teaches(subject, spell)
  local def = SUBJECTS.by_id[subject]
  if not def then return false end
  for _, id in ipairs(def.spells) do
    if id == spell then return true end
  end
  return false
end

-- Trims, drops control characters and BBCode brackets, caps at max_bytes
-- without splitting a UTF-8 sequence. Returns "" for non-strings.
function M.clean_text(text, max_bytes)
  if type(text) ~= "string" then return "" end
  text = text:gsub("[%z\1-\31\127%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > max_bytes then
    local cut = max_bytes
    while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
      cut = cut - 1
    end
    text = text:sub(1, cut):gsub("%s+$", "")
  end
  return text
end

function M.load_totals()
  local ok, objects = pcall(nk.storage_read, { { collection = M.POINTS_COLLECTION, key = M.TOTALS_KEY, user_id = nil } })
  local totals = { 0, 0, 0, 0 }
  if ok and objects and objects[1] and type(objects[1].value) == "table" and type(objects[1].value.totals) == "table" then
    for h = 1, M.HOUSES do
      totals[h] = math.floor(tonumber(objects[1].value.totals[h]) or 0)
    end
  end
  return totals
end

-- Applies one change to `totals` and stores the ledger record with the new
-- total in one write. Returns true on success.
function M.record_points(totals, record)
  totals[record.house] = totals[record.house] + record.delta
  record.at = nk.time()
  local ok, err = pcall(nk.storage_write, {
    { collection = M.POINTS_COLLECTION, key = nk.uuid_v4(), user_id = nil, value = record, permission_read = 0, permission_write = 0 },
    { collection = M.POINTS_COLLECTION, key = M.TOTALS_KEY, user_id = nil, value = { totals = totals }, permission_read = 2, permission_write = 0 },
  })
  if not ok then
    totals[record.house] = totals[record.house] - record.delta
    nk.logger_error("house points write failed: " .. tostring(err))
  end
  return ok
end

-- Most recent ledger records first (up to `limit`).
function M.list_ledger(limit)
  local records, cursor = {}, ""
  repeat
    local ok, objects, next_cursor = pcall(nk.storage_list, nil, M.POINTS_COLLECTION, 100, cursor)
    if not ok then break end
    for _, o in ipairs(objects or {}) do
      if o.key ~= M.TOTALS_KEY and type(o.value) == "table" then table.insert(records, o.value) end
    end
    cursor = next_cursor or ""
  until cursor == "" or #records >= 1000
  table.sort(records, function(a, b) return (a.at or 0) > (b.at or 0) end)
  local out = {}
  for i = 1, math.min(limit, #records) do out[i] = records[i] end
  return out
end

function M.save_plan(uid, payload, max_line_bytes)
  if type(payload) ~= "table" then return nil, "bad_payload" end
  local title = M.clean_text(payload.title, M.MAX_TITLE_BYTES)
  if title == "" then return nil, "no_title" end
  local lines = {}
  for _, line in ipairs(type(payload.lines) == "table" and payload.lines or {}) do
    local clean = M.clean_text(line, max_line_bytes)
    if clean ~= "" and #lines < M.MAX_PLAN_LINES then table.insert(lines, clean) end
  end
  local id = type(payload.id) == "string" and payload.id:match("^[%w%-]+$") and #payload.id <= 64 and payload.id or nk.uuid_v4()
  local ok, err = pcall(nk.storage_write, {
    { collection = M.PLAN_COLLECTION, key = id, user_id = uid, value = { title = title, lines = lines }, permission_read = 1, permission_write = 0 },
  })
  if not ok then return nil, tostring(err) end
  return id
end

function M.list_plans(uid)
  local plans = {}
  local ok, objects = pcall(nk.storage_list, uid, M.PLAN_COLLECTION, 100, "")
  if ok then
    for _, o in ipairs(objects or {}) do
      if type(o.value) == "table" then
        table.insert(plans, { id = o.key, title = o.value.title or "", lines = o.value.lines or {} })
      end
    end
  end
  table.sort(plans, function(a, b) return a.title < b.title end)
  return plans
end

-- School time of day (mirrors gameplay/world/school_clock.gd): hours are
-- ((world seconds + offset) / day seconds) mod 1 x 24.
function M.day_seconds(rules)
  return math.max(1, rules.day_length_minutes) * 60
end

function M.offset_for(now, hours, day)
  return ((hours % 24) / 24 * day - now) % day
end

function M.load_clock_offset()
  local ok, objects = pcall(nk.storage_read, { { collection = M.CLOCK_COLLECTION, key = M.CLOCK_KEY, user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then
    return tonumber(objects[1].value.offset) or 0
  end
  return 0
end

-- The house cup: the last award { term, winner, totals, at } (system-owned, public read).
M.CUP_KEY = "house_cup"

function M.load_cup()
  local ok, objects = pcall(nk.storage_read, { { collection = M.CLOCK_COLLECTION, key = M.CUP_KEY, user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return {}
end

-- Awards the cup for `term` to the house with the most points (ties: the lower house
-- number, i.e. none is favoured by luck), records it and starts every house from zero
-- through the ledger. Returns the cup record.
function M.award_cup(totals, term)
  local winner = 1
  for h = 2, M.HOUSES do
    if totals[h] > totals[winner] then winner = h end
  end
  local cup = { term = term, winner = winner, totals = { totals[1], totals[2], totals[3], totals[4] }, at = nk.time() }
  pcall(nk.storage_write, {
    { collection = M.CLOCK_COLLECTION, key = M.CUP_KEY, user_id = nil, value = cup, permission_read = 2, permission_write = 0 },
  })
  for h = 1, M.HOUSES do
    if totals[h] ~= 0 then
      M.record_points(totals, { house = h, delta = -totals[h], reason = "house cup: new term", by = "", by_name = "", source = "cup", subject = "" })
    end
  end
  return cup
end

function M.save_clock_offset(offset)
  local ok, err = pcall(nk.storage_write, {
    { collection = M.CLOCK_COLLECTION, key = M.CLOCK_KEY, user_id = nil, value = { offset = offset }, permission_read = 2, permission_write = 0 },
  })
  if not ok then
    nk.logger_error("school clock write failed: " .. tostring(err))
  end
  return ok
end

return M
